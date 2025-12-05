local Players = game:GetService("Players");
local rs = game:GetService("ReplicatedStorage");
local cas = game:GetService("ContextActionService");
local ts = game:GetService("TweenService");

local Player = Players.LocalPlayer;
local Mouse = Player:GetMouse();
local MoveEvent = rs:WaitForChild("MovePiece");
local ChessPiecesFolder = workspace:WaitForChild("ChessPieces");

local selectedPieceModel = nil;
local selectedPosition = nil;
local selectionBoxes = {};

local function ChessNotationToIndex(notation)
    if typeof(notation) ~= "string" then return nil; end
    local fileChar = notation:sub(1, 1):upper();
    local rankChar = notation:sub(2, 2);
    local file = string.byte(fileChar) - string.byte("A") + 1;
    local rank = tonumber(rankChar);
    if file >= 1 and file <= 8 and rank >= 1 and rank <= 8 then
        return {file = file, rank = rank};
    end
    return nil;
end;

local function raycastToBoard()
    local rayOrigin = Mouse.UnitRay.Origin;
    local rayDirection = Mouse.UnitRay.Direction * 500;
    local params = RaycastParams.new();
    params.FilterDescendantsInstances = {ChessPiecesFolder};
    params.FilterType = Enum.RaycastFilterType.Exclude;

    local result = workspace:Raycast(rayOrigin, rayDirection, params);
    if result and result.Instance and result.Instance:IsDescendantOf(workspace.Board) then
        return ChessNotationToIndex(result.Instance.Name), result.Instance;
    end
    return nil, nil;
end;

local function clearSelection()
    for _, box in pairs(selectionBoxes) do box:Destroy(); end
    selectionBoxes = {};
    selectedPieceModel = nil;
    selectedPosition = nil;
end;

local function highlightSquare(part, color)
    local box = Instance.new("SelectionBox");
    box.Adornee = part;
    box.Color3 = color;
    box.Parent = part;
    table.insert(selectionBoxes, box);
end;

local function OnAction(actionName, userInputState, inputObject)
    if actionName == "SelectPiece" and userInputState == Enum.UserInputState.Begin then
        local clickedBoardPos, clickedPart = raycastToBoard();

        if clickedBoardPos then
            if not selectedPieceModel then
                local pieceCheckRay = workspace:Raycast(clickedPart.Position + Vector3.new(0,5,0), Vector3.new(0,-10,0));

                if pieceCheckRay and pieceCheckRay.Instance:IsDescendantOf(ChessPiecesFolder) then
                    selectedPieceModel = pieceCheckRay.Instance;
                    selectedPosition = clickedBoardPos;
                    highlightSquare(clickedPart, Color3.new(0,1,0));
                end
            else
                if clickedBoardPos.file == selectedPosition.file and clickedBoardPos.rank == selectedPosition.rank then
                    clearSelection();
                else
                    MoveEvent:FireServer(selectedPosition, clickedBoardPos);
                    clearSelection();
                end
            end
        else
            clearSelection();
        end
    end
end;

cas:BindAction("SelectPiece", OnAction, false, Enum.UserInputType.MouseButton1, Enum.UserInputType.Touch);
