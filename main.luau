local rs = game:GetService("ReplicatedStorage");
local ts = game:GetService("TweenService");
local Players = game:GetService("Players");

local MoveEvent = rs:WaitForChild("MovePiece");
local PieceTemplates = rs:WaitForChild("PieceTemplates");

local currentTurn = "White";
local board = {};
local ChessPiecesFolder = workspace:WaitForChild("ChessPieces");

local function initializeBoard()
    for file = 1, 8 do
        board[file] = {};
        for rank = 1, 8 do board[file][rank] = nil; end;
    end

    local setup = {
        {1, "Rook"}, {2, "Knight"}, {3, "Bishop"}, {4, "Queen"}, 
        {5, "King"}, {6, "Bishop"}, {7, "Knight"}, {8, "Rook"}
    };

    for _, p in ipairs(setup) do
        board[p[1]][1] = {pieceType = p[2], color = "White", uniqueId = "White_"..p[2]..(p[1]==1 and "_1" or (p[1]==8 and "_2" or ""))};
        board[p[1]][8] = {pieceType = p[2], color = "Black", uniqueId = "Black_"..p[2]..(p[1]==1 and "_1" or (p[1]==8 and "_2" or ""))};
    end

    for file = 1, 8 do
        board[file][2] = {pieceType = "Pawn", color = "White", uniqueId = "White_Pawn_" .. file};
        board[file][7] = {pieceType = "Pawn", color = "Black", uniqueId = "Black_Pawn_" .. file};
    end
end;

initializeBoard();

local function isWithinBounds(pos)
    return pos.file >= 1 and pos.file <= 8 and pos.rank >= 1 and pos.rank <= 8;
end;

local function boardPositionToWorldPosition(pos)
    local fileChar = string.char(string.byte('A') + pos.file - 1);
    local squareName = fileChar .. tostring(pos.rank);
    local squarePart = workspace.Board:FindFirstChild(squareName);
    return squarePart and squarePart.Position or nil;
end;

local function findTargetPart(uniqueId)
    return ChessPiecesFolder:FindFirstChild(uniqueId);
end;

local function isValidMove(startPos, endPos, piece)
    return true; 
end;

local function movePiecePhysical(uniqueId, endPos)
    local part = findTargetPart(uniqueId);
    if part then
        local newWorldPos = boardPositionToWorldPosition(endPos);
        if newWorldPos then
            local tweenInfo = TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out);
            local goal = {Position = Vector3.new(newWorldPos.X, part.Position.Y, newWorldPos.Z)};
            ts:Create(part, tweenInfo, goal):Play();
        end
    end
end;

MoveEvent.OnServerEvent:Connect(function(player, startPos, endPos)
    if type(startPos) ~= "table" or type(endPos) ~= "table" then
        warn(player.Name .. " sent invalid data types.");
        return;
    end

    if not (startPos.file and startPos.rank and endPos.file and endPos.rank) then
        warn(player.Name .. " sent incomplete coordinates.");
        return;
    end

    if not isWithinBounds(startPos) or not isWithinBounds(endPos) then
        warn(player.Name .. " sent out-of-bounds coordinates.");
        return;
    end

    local piece = board[startPos.file][startPos.rank];

    if not piece then 
        warn("No piece found at start position for " .. player.Name);
        return; 
    end

    if piece.color ~= currentTurn then 
        warn(player.Name .. " tried to move out of turn.");
        return; 
    end

    if isValidMove(startPos, endPos, piece) then
        print("Server: Valid Move by " .. player.Name);

        local targetPiece = board[endPos.file][endPos.rank];
        if targetPiece then
            local targetPart = findTargetPart(targetPiece.uniqueId);
            if targetPart then targetPart:Destroy(); end
        end

        board[endPos.file][endPos.rank] = piece;
        board[startPos.file][startPos.rank] = nil;

        movePiecePhysical(piece.uniqueId, endPos);

        currentTurn = (currentTurn == "White") and "Black" or "White";
        print("New Turn: " .. currentTurn);
    else
        warn("Server: Invalid move logic from " .. player.Name);
    end
end);
