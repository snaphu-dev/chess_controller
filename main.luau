local rs = game:GetService("ReplicatedStorage");
local ts = game:GetService("TweenService");
local Players = game:GetService("Players");

local MoveEvent = rs:WaitForChild("MovePiece");
local ChessPiecesFolder = workspace:WaitForChild("ChessPieces");
local BoardFolder = workspace:WaitForChild("Board");

local currentTurn = "White";
local board = {};
local lastMove = {};

local function initializeBoard()
    board = {};
    for file = 1, 8 do
        board[file] = {};
        for rank = 1, 8 do board[file][rank] = nil; end;
    end;

    local setup = {
        {1, "Rook"}, {2, "Knight"}, {3, "Bishop"}, {4, "Queen"}, 
        {5, "King"}, {6, "Bishop"}, {7, "Knight"}, {8, "Rook"}
    };

    local whiteCounts = {};
    local blackCounts = {};

    local function createPieceData(file, rank, pType, color)
        local counts = (color == "White") and whiteCounts or blackCounts;
        counts[pType] = (counts[pType] or 0) + 1;
        local id = color .. "_" .. pType .. "_" .. counts[pType];

        board[file][rank] = {
            pieceType = pType,
            color = color,
            uniqueId = id,
            hasMoved = false
        };
    end;

    for _, p in ipairs(setup) do
        createPieceData(p[1], 1, p[2], "White");
        createPieceData(p[1], 8, p[2], "Black");
    end;

    for file = 1, 8 do
        createPieceData(file, 2, "Pawn", "White");
        createPieceData(file, 7, "Pawn", "Black");
    end;
end;

initializeBoard();

local function isWithinBounds(pos)
    return pos.file >= 1 and pos.file <= 8 and pos.rank >= 1 and pos.rank <= 8;
end;

local function findTargetPart(uniqueId)
    return ChessPiecesFolder:FindFirstChild(uniqueId);
end;

local function getBoardSquarePart(pos)
    local fileChar = string.char(string.byte('A') + pos.file - 1);
    local squareName = fileChar .. tostring(pos.rank);
    return BoardFolder:FindFirstChild(squareName);
end;

local function isPathClear(startPos, endPos)
    local dFile = endPos.file - startPos.file;
    local dRank = endPos.rank - startPos.rank;
    local stepFile = (dFile == 0) and 0 or (dFile > 0 and 1 or -1);
    local stepRank = (dRank == 0) and 0 or (dRank > 0 and 1 or -1);

    local currFile = startPos.file + stepFile;
    local currRank = startPos.rank + stepRank;

    while (currFile ~= endPos.file) or (currRank ~= endPos.rank) do
        if board[currFile][currRank] ~= nil then return false; end;
        currFile = currFile + stepFile;
        currRank = currRank + stepRank;
    end;
    return true;
end;

local function isValidMove(startPos, endPos, piece)
    local dx = math.abs(startPos.file - endPos.file);
    local dy = math.abs(startPos.rank - endPos.rank);
    local dFileRaw = endPos.file - startPos.file;
    local dRankRaw = endPos.rank - startPos.rank;

    local targetPiece = board[endPos.file][endPos.rank];

    if targetPiece and targetPiece.color == piece.color then
        return false;
    end;

    if piece.pieceType == "Rook" then
        if dx == 0 or dy == 0 then
            return isPathClear(startPos, endPos);
        end;

    elseif piece.pieceType == "Bishop" then
        if dx == dy then
            return isPathClear(startPos, endPos);
        end;

    elseif piece.pieceType == "Queen" then
        if (dx == 0 or dy == 0) or (dx == dy) then
            return isPathClear(startPos, endPos);
        end;

    elseif piece.pieceType == "Knight" then
        if (dx == 1 and dy == 2) or (dx == 2 and dy == 1) then
            return true;
        end;

    elseif piece.pieceType == "King" then
        if dx <= 1 and dy <= 1 then
            return true;
        end;

        if not piece.hasMoved and dy == 0 and dx == 2 then
            local rookFile = (dFileRaw > 0) and 8 or 1;
            local rookPiece = board[rookFile][startPos.rank];
            if rookPiece and rookPiece.pieceType == "Rook" and not rookPiece.hasMoved then
                return isPathClear(startPos, {file = rookFile, rank = startPos.rank});
            end;
        end;

    elseif piece.pieceType == "Pawn" then
        local direction = (piece.color == "White") and 1 or -1;
        local startRank = (piece.color == "White") and 2 or 7;

        if dx == 0 then 
            if dRankRaw == direction then
                return targetPiece == nil;
            end;
            if dRankRaw == (direction * 2) and startPos.rank == startRank then
                return targetPiece == nil and board[startPos.file][startPos.rank + direction] == nil;
            end;
        elseif dx == 1 and dRankRaw == direction then
            if targetPiece and targetPiece.color ~= piece.color then
                return true;
            end;
            if not targetPiece and lastMove.piece and lastMove.piece.pieceType == "Pawn" then
                if lastMove.endPos.rank == startPos.rank and lastMove.endPos.file == endPos.file then
                    if math.abs(lastMove.startPos.rank - lastMove.endPos.rank) == 2 then
                        return true;
                    end;
                end;
            end;
        end;
    end;

    return false;
end;

local function movePiecePhysical(uniqueId, endPos)
    local part = findTargetPart(uniqueId);
    local squarePart = getBoardSquarePart(endPos);

    if part and squarePart then
        local newWorldPos = Vector3.new(squarePart.Position.X, part.Position.Y, squarePart.Position.Z);

        local tweenInfo = TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out);
        local goal = {Position = newWorldPos};
        ts:Create(part, tweenInfo, goal):Play();
    end;
end;

MoveEvent.OnServerEvent:Connect(function(player, startPos, endPos)
    if type(startPos) ~= "table" or type(endPos) ~= "table" then return; end;
    if not (startPos.file and startPos.rank and endPos.file and endPos.rank) then return; end;
    if not isWithinBounds(startPos) or not isWithinBounds(endPos) then return; end;

    local piece = board[startPos.file][startPos.rank];

    if not piece then return; end;
    if piece.color ~= currentTurn then return; end;

    if isValidMove(startPos, endPos, piece) then
        local targetPiece = board[endPos.file][endPos.rank];
        local isEnPassant = false;
        local isCastling = false;

        if piece.pieceType == "Pawn" and not targetPiece and math.abs(startPos.file - endPos.file) == 1 then
            isEnPassant = true;
            local capturedPawnPos = {file = endPos.file, rank = startPos.rank};
            local capturedPawn = board[capturedPawnPos.file][capturedPawnPos.rank];
            if capturedPawn then
                local capPart = findTargetPart(capturedPawn.uniqueId);
                if capPart then capPart:Destroy(); end;
                board[capturedPawnPos.file][capturedPawnPos.rank] = nil;
            end;
        end;

        if piece.pieceType == "King" and math.abs(startPos.file - endPos.file) == 2 then
            isCastling = true;
            local rookStartFile = (endPos.file > startPos.file) and 8 or 1;
            local rookEndFile = (endPos.file > startPos.file) and 6 or 4;
            local rook = board[rookStartFile][startPos.rank];

            if rook then
                board[rookEndFile][startPos.rank] = rook;
                board[rookStartFile][startPos.rank] = nil;
                rook.hasMoved = true;
                movePiecePhysical(rook.uniqueId, {file = rookEndFile, rank = startPos.rank});
            end;
        end;

        if targetPiece and not isEnPassant then
            local targetPart = findTargetPart(targetPiece.uniqueId);
            if targetPart then targetPart:Destroy(); end;
        end;

        board[endPos.file][endPos.rank] = piece;
        board[startPos.file][startPos.rank] = nil;

        lastMove = {
            piece = piece,
            startPos = startPos,
            endPos = endPos
        };

        piece.hasMoved = true;

        if piece.pieceType == "Pawn" then
            if (piece.color == "White" and endPos.rank == 8) or (piece.color == "Black" and endPos.rank == 1) then
                piece.pieceType = "Queen";
            end;
        end;

        movePiecePhysical(piece.uniqueId, endPos);

        currentTurn = (currentTurn == "White") and "Black" or "White";
        print("New Turn: " .. currentTurn);
    end;
end);
