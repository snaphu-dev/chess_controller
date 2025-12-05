--[[
5 November, 2024
Snaphu-Dev
This is a full chess game implementation for Roblox. It includes movement rules
for each piece and ensures moves are validated according to chess rules.
This script supports all major platforms, except for controller.
--]]

-- Initialize so it doesn't fail to load.
local HoldOn = false
task.wait(5)

-- Required services:
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ContextActionService = game:GetService("ContextActionService")
local PieceTemplates = ReplicatedStorage:WaitForChild("PieceTemplates")

-- Required variables:
local selectedPiece = nil
local selectedPosition = nil
local wiggleTween = nil
local originalOrientation = nil
local lastMove = nil
local squareSize = 4
local enPassantTarget = nil
local currentTurn = "White"
local boardOrigin = Vector3.new(-8, 0.5, 48)

-- Event:
local MoveEvent = ReplicatedStorage:WaitForChild("MovePiece")

-- Required objects:
local Camera = Workspace.CurrentCamera
local Player = Players.LocalPlayer
local Character = Player.Character or Player.CharacterAdded:Wait()
local Mouse = Player:GetMouse()
local ChessPiecesFolder = Workspace:FindFirstChild("ChessPieces")
local promotionImages = {
	Queen = "rbxassetid://12414180706",
	Knight = "rbxassetid://12414177497",
	Rook = "rbxassetid://12414179583",
	Bishop = "rbxassetid://12414178467"
}
-- Raycast parameters:
local Parameters = RaycastParams.new()
Parameters.FilterDescendantsInstances = {ChessPiecesFolder}
Parameters.FilterType = Enum.RaycastFilterType.Exclude

-- Table to keep track of selection boxes
local selectionBoxes = {}
local checkSelectionBox = nil
local checkmateSelectionBox = nil

-- Logical board:
local board = {}
for file = 1, 8 do
	board[file] = {}
	for rank = 1, 8 do
		board[file][rank] = nil
	end
end

board[1][1] = {pieceType = "Rook", color = "White", uniqueId = "White_Rook_1"}
board[2][1] = {pieceType = "Knight", color = "White", uniqueId = "White_Knight_1"}
board[3][1] = {pieceType = "Bishop", color = "White", uniqueId = "White_Bishop_1"}
board[4][1] = {pieceType = "Queen", color = "White", uniqueId = "White_Queen"}
board[5][1] = {pieceType = "King", color = "White", uniqueId = "White_King"}
board[6][1] = {pieceType = "Bishop", color = "White", uniqueId = "White_Bishop_2"}
board[7][1] = {pieceType = "Knight", color = "White", uniqueId = "White_Knight_2"}
board[8][1] = {pieceType = "Rook", color = "White", uniqueId = "White_Rook_2"}

for file = 1, 8 do
	board[file][2] = {pieceType = "Pawn", color = "White", uniqueId = "White_Pawn_" .. file}
end

board[1][8] = {pieceType = "Rook", color = "Black", uniqueId = "Black_Rook_1"}
board[2][8] = {pieceType = "Knight", color = "Black", uniqueId = "Black_Knight_1"}
board[3][8] = {pieceType = "Bishop", color = "Black", uniqueId = "Black_Bishop_1"}
board[4][8] = {pieceType = "Queen", color = "Black", uniqueId = "Black_Queen"}
board[5][8] = {pieceType = "King", color = "Black", uniqueId = "Black_King"}
board[6][8] = {pieceType = "Bishop", color = "Black", uniqueId = "Black_Bishop_2"}
board[7][8] = {pieceType = "Knight", color = "Black", uniqueId = "Black_Knight_2"}
board[8][8] = {pieceType = "Rook", color = "Black", uniqueId = "Black_Rook_2"}

for file = 1, 8 do
	board[file][7] = {pieceType = "Pawn", color = "Black", uniqueId = "Black_Pawn_" .. file}
end

-- Is the piece in the bounds of the board?
local function isWithinBounds(pos)
	if not pos or not pos.file or not pos.rank then
		return false
	end
	return pos.file >= 1 and pos.file <= 8 and pos.rank >= 1 and pos.rank <= 8
end

-- Converts a physical board to align with the logical board.
local function ChessNotationToIndex(notation)
	if typeof(notation) ~= "string" then
		return nil
	end

	local fileChar = notation:sub(1, 1):upper()
	local rankChar = notation:sub(2, 2)
	local file = string.byte(fileChar) - string.byte("A") + 1
	local rank = tonumber(rankChar)

	if file >= 1 and file <= 8 and rank >= 1 and rank <= 8 then
		return {file = file, rank = rank}
	else
		return nil
	end
end

-- Validates rook moves.
local function isValidRookMove(startPos, endPos)
	return startPos.file == endPos.file or startPos.rank == endPos.rank
end

-- Validates bishop moves.
local function isValidBishopMove(startPos, endPos)
	return math.abs(startPos.file - endPos.file) == math.abs(startPos.rank - endPos.rank)
end

-- Validates queen moves.
local function isValidQueenMove(startPos, endPos)
	return isValidRookMove(startPos, endPos) or isValidBishopMove(startPos, endPos)
end

-- Validates knight moves.
local function isValidKnightMove(startPos, endPos)
	local dx = math.abs(startPos.file - endPos.file)
	local dy = math.abs(startPos.rank - endPos.rank)
	return (dx == 2 and dy == 1) or (dx == 1 and dy == 2)
end

local hasWhiteKingMoved = false
local hasBlackKingMoved = false
local hasWhiteRookMoved = {left = false, right = false}
local hasBlackRookMoved = {left = false, right = false}

-- Is the path clear for the piece to move to?
local function isPathClear(startPos, endPos)
	if startPos.file == endPos.file then
		local step = (endPos.rank > startPos.rank) and 1 or -1
		for rank = startPos.rank + step, endPos.rank - step, step do
			if board[startPos.file][rank] then
				return false
			end
		end
	elseif startPos.rank == endPos.rank then
		local step = (endPos.file > startPos.file) and 1 or -1
		for file = startPos.file + step, endPos.file - step, step do
			if board[file][startPos.rank] then
				return false
			end
		end
	elseif math.abs(endPos.file - startPos.file) == math.abs(endPos.rank - startPos.rank) then
		local fileStep = (endPos.file > startPos.file) and 1 or -1
		local rankStep = (endPos.rank > startPos.rank) and 1 or -1
		local file, rank = startPos.file + fileStep, startPos.rank + rankStep
		while file ~= endPos.file and rank ~= endPos.rank do
			if board[file][rank] then
				return false
			end
			file = file + fileStep
			rank = rank + rankStep
		end
	end
	return true
end

-- Finds the king's position.
local function findKingPosition(color)
	for file = 1, 8 do
		for rank = 1, 8 do
			local piece = board[file][rank]
			if piece and piece.pieceType == "King" and piece.color == color then
				return {file = file, rank = rank}
			end
		end
	end
	return nil
end

-- Is the king in check?
local function isKingInCheck(color)
	local kingPosition = findKingPosition(color)
	if not kingPosition then
		return false
	end

	local opponentColor = (color == "White") and "Black" or "White"
	for file = 1, 8 do
		for rank = 1, 8 do
			local piece = board[file][rank]
			if piece and piece.color == opponentColor then
				if isValidMove({file = file, rank = rank}, kingPosition, piece, true) then
					return true
				end
			end
		end
	end

	return false
end

-- Checks if the squares the king passes through during castling are under attack
local function isCastlingPathSafe(startPos, endPos, piece)
	local step = (endPos.file > startPos.file) and 1 or -1
	local file = startPos.file
	while file ~= endPos.file do
		file = file + step
		local tempStart = {file = startPos.file, rank = startPos.rank}
		local tempEnd = {file = file, rank = startPos.rank}

		local oldPiece = board[tempEnd.file][tempEnd.rank]
		board[tempStart.file][tempStart.rank] = nil
		board[tempEnd.file][tempEnd.rank] = piece

		local inCheck = isKingInCheck(piece.color)
		board[tempStart.file][tempStart.rank] = piece
		board[tempEnd.file][tempEnd.rank] = oldPiece

		if inCheck then
			return false
		end
	end
	return true
end

-- Validates king moves.
local function isValidKingMove(startPos, endPos, piece)
	local isCastling = math.abs(endPos.file - startPos.file) == 2 and startPos.rank == endPos.rank
	if isCastling then
		local rookFile = (endPos.file > startPos.file) and 8 or 1
		local rookMoved = (piece.color == "White") and hasWhiteRookMoved or hasBlackRookMoved
		local kingMoved = (piece.color == "White") and hasWhiteKingMoved or hasBlackKingMoved
		local rookPosition = board[rookFile][startPos.rank]
		if not kingMoved and not rookMoved[rookFile == 8 and "right" or "left"] and isPathClear(startPos, endPos) and rookPosition and rookPosition.pieceType == "Rook" and rookPosition.color == piece.color then
			-- Cannot castle if king is in check or moves through/into check
			if not isKingInCheck(piece.color) and isCastlingPathSafe(startPos, endPos, piece) then
				return true
			end
		end
	end
	-- Regular king move
	return math.max(math.abs(startPos.file - endPos.file), math.abs(startPos.rank - endPos.rank)) == 1
end

-- Validates pawn moves.
local function isValidPawnMove(startPos, endPos, pieceColor)
	local direction = (pieceColor == "White") and 1 or -1
	local targetPiece = board[endPos.file][endPos.rank]

	if startPos.file == endPos.file then
		if not targetPiece then
			if endPos.rank == startPos.rank + direction then
				return true
			elseif ((startPos.rank == 2 and pieceColor == "White") or (startPos.rank == 7 and pieceColor == "Black")) and endPos.rank == startPos.rank + 2 * direction then
				local intermediateRank = startPos.rank + direction
				if not board[startPos.file][intermediateRank] then
					return true
				end
			end
		end

	elseif math.abs(startPos.file - endPos.file) == 1 and endPos.rank == startPos.rank + direction then
		if targetPiece and targetPiece.color ~= pieceColor then
			return true
		elseif enPassantTarget and enPassantTarget.file == endPos.file and enPassantTarget.rank == endPos.rank then
			return true
		end
	end
	return false
end

-- Is this a valid move?
function isValidMove(startPos, endPos, piece, ignoreCheck)
	if not isWithinBounds(endPos) then
		return false
	end

	local targetPiece = board[endPos.file][endPos.rank]
	if targetPiece and targetPiece.color == piece.color then
		return false
	end

	local valid = false

	if piece.pieceType == "Knight" then
		valid = isValidKnightMove(startPos, endPos)
	elseif piece.pieceType == "Rook" then
		valid = isValidRookMove(startPos, endPos) and isPathClear(startPos, endPos)
	elseif piece.pieceType == "Bishop" then
		valid = isValidBishopMove(startPos, endPos) and isPathClear(startPos, endPos)
	elseif piece.pieceType == "Queen" then
		valid = isValidQueenMove(startPos, endPos) and isPathClear(startPos, endPos)
	elseif piece.pieceType == "King" then
		valid = isValidKingMove(startPos, endPos, piece)
	elseif piece.pieceType == "Pawn" then
		valid = isValidPawnMove(startPos, endPos, piece.color)
	end

	if valid and not ignoreCheck then
		local oldStart = board[startPos.file][startPos.rank]
		local oldEnd = board[endPos.file][endPos.rank]
		local savedEnPassantTarget = enPassantTarget

		board[startPos.file][startPos.rank] = nil
		board[endPos.file][endPos.rank] = piece

		if piece.pieceType == "Pawn" and enPassantTarget and enPassantTarget.file == endPos.file and enPassantTarget.rank == endPos.rank then
			local capturedPawnPos = {file = endPos.file, rank = startPos.rank}
			board[capturedPawnPos.file][capturedPawnPos.rank] = nil
		end

		local kingInCheck = isKingInCheck(piece.color)

		board[startPos.file][startPos.rank] = oldStart
		board[endPos.file][endPos.rank] = oldEnd
		enPassantTarget = savedEnPassantTarget

		if kingInCheck then
			return false
		end
	end

	return valid
end

-- Gets valid moves for a piece.
local function getValidMoves(startPos)
	local validMoves = {}
	local piece = board[startPos.file][startPos.rank]
	if not piece then return validMoves end

	for file = 1, 8 do
		for rank = 1, 8 do
			local endPos = {file = file, rank = rank}
			if startPos.file ~= endPos.file or startPos.rank ~= endPos.rank then
				if isValidMove(startPos, endPos, piece) then
					table.insert(validMoves, endPos)
				end
			end
		end
	end

	return validMoves
end

-- Converts board position to physical position
local function boardPositionToWorldPosition(pos)
	local fileChar = string.char(string.byte('A') + pos.file - 1)
	local squareName = fileChar .. tostring(pos.rank)
	local squarePart = Workspace.Board:FindFirstChild(squareName)
	if squarePart then
		return squarePart.Position
	else
		return nil
	end
end

-- This is the promotion handler.
local function showPromotionGui(piece, position, pawnPart)
	local player = game.Players.LocalPlayer
	local playerGui = player:WaitForChild("PlayerGui")

	if playerGui:FindFirstChild("PromotionGui") then
		playerGui:FindFirstChild("PromotionGui"):Destroy()
	end

	local promotionGui = Instance.new("ScreenGui")
	promotionGui.Name = "PromotionGui"
	promotionGui.Parent = playerGui

	local buttonSize = UDim2.new(0, 100, 0, 100)
	local buttonSpacing = UDim2.new(0, 110, 0, 0)
	local startPosition = UDim2.new(0.5, -220, 0.5, -50)
	local pieces = {"Queen", "Knight", "Rook", "Bishop"}

	local pieceYValues = {
		Queen =  3.588,
		Knight = 2.94,
		Rook =  2.805,
		Bishop = 3.055
	}
	local pieceOrientations = {
		Queen = Vector3.new(0, 0, 180),
		Knight = Vector3.new(-70, 0, 90),
		Rook = Vector3.new(0, 180, 0),
		Bishop = Vector3.new(0, 180, 0)
	}
	
	for i, pieceType in ipairs(pieces) do
		local button = Instance.new("ImageButton")
		button.Name = pieceType .. "Button"
		button.Size = buttonSize
		button.Position = startPosition + UDim2.new(0, (i - 1) * 110, 0, 0)
		button.Image = promotionImages[pieceType]
		button.Parent = promotionGui
		button.Transparency = 1
		button.MouseButton1Click:Connect(function()
			local templateNameBase = piece.color .. "_" .. pieceType
			local pieceTemplate = nil

			for suffix = 1, 2 do
				pieceTemplate = PieceTemplates:FindFirstChild(templateNameBase .. "_" .. suffix)
				if pieceTemplate then break end
			end

			if not pieceTemplate then
				pieceTemplate = PieceTemplates:FindFirstChild(templateNameBase)
			end

			if not pieceTemplate then
				warn("Template not found for " .. templateNameBase)
			else
				print("Template found: " .. pieceTemplate.Name)

				local newPiece = pieceTemplate:Clone()
				local newPieceUniqueId = piece.color .. "_" .. pieceType .. "_" .. position.file .. "_" .. position.rank
				newPiece.Name = newPieceUniqueId

				local newPosition = boardPositionToWorldPosition(position)
				local yValue = pieceYValues[pieceType]
				if newPosition then
					newPiece.Position = Vector3.new(newPosition.X, yValue, newPosition.Z)
				else
					newPiece.Position = Vector3.new(pawnPart.Position.X, yValue, pawnPart.Position.Z)
				end

				newPiece.Orientation = pieceOrientations[pieceType] or Vector3.new(0, 180, 0)
				newPiece.Parent = ChessPiecesFolder

				local promotedPiece = {pieceType = pieceType, color = piece.color, uniqueId = newPieceUniqueId}
				board[position.file][position.rank] = promotedPiece

				pawnPart:Destroy()
				promotionGui:Destroy()
			end
		end)
	end
end

-- Call this function within `promotePawn`
local function promotePawn(piece, position, pawnPart)
	showPromotionGui(piece, position, pawnPart)
end


-- Finds the target piece.
local function findTargetPart(targetPiece)
	local targetPart = ChessPiecesFolder:FindFirstChild(targetPiece.uniqueId)
	if targetPart then
		return targetPart
	end
	return nil
end

-- Checks for checkmate.
local function isCheckmate(color)
	if not isKingInCheck(color) then
		return false
	end

	local kingPosition = findKingPosition(color)
	if not kingPosition then
		return false
	end
	
	for fileDelta = -1, 1 do
		for rankDelta = -1, 1 do
			if fileDelta ~= 0 or rankDelta ~= 0 then
				local newKingPos = {file = kingPosition.file + fileDelta, rank = kingPosition.rank + rankDelta}
				if isWithinBounds(newKingPos) and (not board[newKingPos.file][newKingPos.rank] or board[newKingPos.file][newKingPos.rank].color ~= color) then
					if isValidMove(kingPosition, newKingPos, board[kingPosition.file][kingPosition.rank]) then
						return false
					end
				end
			end
		end
	end
	
	local opponentColor = (color == "White") and "Black" or "White"
	local attackingPieces = {}

	for file = 1, 8 do
		for rank = 1, 8 do
			local piece = board[file][rank]
			if piece and piece.color == opponentColor then
				if isValidMove({file = file, rank = rank}, kingPosition, piece, true) then
					table.insert(attackingPieces, {file = file, rank = rank, pieceType = piece.pieceType})
				end
			end
		end
	end

	if #attackingPieces > 1 then
		return true
	end

	local attacker = attackingPieces[1]

	for file = 1, 8 do
		for rank = 1, 8 do
			local piece = board[file][rank]
			if piece and piece.color == color and piece.pieceType ~= "King" then
				if isValidMove({file = file, rank = rank}, attacker, piece) then
					return false
				end
			end
		end
	end

	if attacker.pieceType ~= "Knight" and attacker.pieceType ~= "Pawn" then
		local dx = math.sign(attacker.file - kingPosition.file)
		local dy = math.sign(attacker.rank - kingPosition.rank)
		local blockPos = {file = kingPosition.file + dx, rank = kingPosition.rank + dy}
		while blockPos.file ~= attacker.file or blockPos.rank ~= attacker.rank do
			for file = 1, 8 do
				for rank = 1, 8 do
					local piece = board[file][rank]
					if piece and piece.color == color and piece.pieceType ~= "King" then
						if isValidMove({file = file, rank = rank}, blockPos, piece) then
							return false
						end
					end
				end
			end
			blockPos.file = blockPos.file + dx
			blockPos.rank = blockPos.rank + dy
		end
	end

	return true
end

-- Attempt to move the piece.
local function attemptMovePiece(startPos, endPos)
    local piece = board[startPos.file][startPos.rank]

    if not piece or piece.color ~= currentTurn then
        return false
    end

    if isValidMove(startPos, endPos, piece) then
        local oldStart = board[startPos.file][startPos.rank]
        local oldEnd = board[endPos.file][endPos.rank]
        local savedEnPassantTarget = enPassantTarget
        local savedLastMove = lastMove

        local targetPiece = board[endPos.file][endPos.rank]
        local capturedPiecePart = nil
        if targetPiece and targetPiece.color ~= piece.color then
            capturedPiecePart = findTargetPart(targetPiece)
            board[endPos.file][endPos.rank] = nil
        end

        board[startPos.file][startPos.rank] = nil
        board[endPos.file][endPos.rank] = piece
        local isEnPassant = false
        if piece.pieceType == "Pawn" and enPassantTarget and enPassantTarget.file == endPos.file and enPassantTarget.rank == endPos.rank then
            local capturedPawnPos = {file = endPos.file, rank = startPos.rank}
            local capturedPawn = board[capturedPawnPos.file][capturedPawnPos.rank]
            if capturedPawn and capturedPawn.pieceType == "Pawn" and capturedPawn.color ~= piece.color then
                board[capturedPawnPos.file][capturedPawnPos.rank] = nil
                capturedPiecePart = findTargetPart(capturedPawn)
                isEnPassant = true
			end
        end

        local isCastling = piece.pieceType == "King" and math.abs(endPos.file - startPos.file) == 2
        if isCastling then
            local rookStartFile = (endPos.file > startPos.file) and 8 or 1
            local rookEndFile = (endPos.file > startPos.file) and (startPos.file + 1) or (startPos.file - 1)
            local rook = board[rookStartFile][startPos.rank]
            board[rookStartFile][startPos.rank] = nil
            board[rookEndFile][startPos.rank] = rook
            local rookPart = findTargetPart(rook)
            if rookPart then
                local rookPosition = boardPositionToWorldPosition({file = rookEndFile, rank = startPos.rank})
                if rookPosition then
                    local tweenInfo = TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
                    local tweenGoal = {Position = Vector3.new(rookPosition.X, rookPart.Position.Y, rookPosition.Z)}
                    local moveTween = TweenService:Create(rookPart, tweenInfo, tweenGoal)
                    moveTween:Play()
                end
            end
        end

        if isKingInCheck(currentTurn) then
            board[startPos.file][startPos.rank] = oldStart
            board[endPos.file][endPos.rank] = oldEnd
            if isEnPassant then
                local capturedPawnPos = {file = endPos.file, rank = startPos.rank}
                board[capturedPawnPos.file][capturedPawnPos.rank] = {pieceType = "Pawn", color = (currentTurn == "White") and "Black" or "White", uniqueId = capturedPiecePart.Name}
            end
            if isCastling then
                local rookStartFile = (endPos.file > startPos.file) and 8 or 1
                local rookEndFile = (endPos.file > startPos.file) and (startPos.file + 1) or (startPos.file - 1)
                board[rookStartFile][startPos.rank] = board[rookEndFile][startPos.rank]
                board[rookEndFile][startPos.rank] = nil
            end
            enPassantTarget = savedEnPassantTarget
            lastMove = savedLastMove
            return false
        end

        if capturedPiecePart then
            capturedPiecePart:Destroy()
        end

        if piece.pieceType == "Pawn" and math.abs(startPos.rank - endPos.rank) == 2 then
            enPassantTarget = {file = startPos.file, rank = (startPos.rank + endPos.rank) / 2}
        else
            enPassantTarget = nil
        end

        if piece.pieceType == "Pawn" then
            if (piece.color == "White" and endPos.rank == 8) or (piece.color == "Black" and endPos.rank == 1) then
                local pawnPart = ChessPiecesFolder:FindFirstChild(piece.uniqueId)
                if pawnPart then
                    local newPosition = boardPositionToWorldPosition(endPos)
                    if newPosition then
                        pawnPart.Position = Vector3.new(newPosition.X, pawnPart.Position.Y, newPosition.Z)
                    end
                    task.wait(0.1)
                    promotePawn(piece, endPos, pawnPart)
                end
            end
        end

        if piece.pieceType == "King" then
            if piece.color == "White" then
                hasWhiteKingMoved = true
            else
                hasBlackKingMoved = true
            end
        elseif piece.pieceType == "Rook" then
            if piece.color == "White" then
                if startPos.file == 1 and startPos.rank == 1 then
                    hasWhiteRookMoved.left = true
                elseif startPos.file == 8 and startPos.rank == 1 then
                    hasWhiteRookMoved.right = true
                end
            else
                if startPos.file == 1 and startPos.rank == 8 then
                    hasBlackRookMoved.left = true
                elseif startPos.file == 8 and startPos.rank == 8 then
                    hasBlackRookMoved.right = true
                end
            end
        end

        if checkSelectionBox then
            checkSelectionBox:Destroy()
            checkSelectionBox = nil
        end
        if checkmateSelectionBox then
            checkmateSelectionBox:Destroy()
            checkmateSelectionBox = nil
        end

        lastMove = {startPos = startPos, endPos = endPos}
        currentTurn = (currentTurn == "White") and "Black" or "White"

        local opponentColor = (currentTurn == "White") and "Black" or "White"
        if isKingInCheck(opponentColor) then
            local kingPosition = findKingPosition(opponentColor)
            if kingPosition then
                local fileChar = string.char(string.byte('A') + kingPosition.file - 1)
                local squareName = fileChar .. tostring(kingPosition.rank)
                local squarePart = Workspace.Board:FindFirstChild(squareName)
                if squarePart then
                    if isCheckmate(opponentColor) then
                        checkmateSelectionBox = Instance.new("SelectionBox")
                        checkmateSelectionBox.Adornee = squarePart
                        checkmateSelectionBox.Color3 = Color3.new(1, 0, 0)
                        checkmateSelectionBox.LineThickness = 0.05
                        checkmateSelectionBox.SurfaceTransparency = 0.5
                        checkmateSelectionBox.Parent = squarePart
                        ContextActionService:UnbindAction("SelectPiece")
                    else
                        checkSelectionBox = Instance.new("SelectionBox")
                        checkSelectionBox.Adornee = squarePart
                        checkSelectionBox.Color3 = Color3.new(1, 1, 0)
                        checkSelectionBox.LineThickness = 0.05
                        checkSelectionBox.SurfaceTransparency = 0.5
                        checkSelectionBox.Parent = squarePart
                    end
                end
            end
		end
		MoveEvent:FireServer(piece, startPos, endPos)
        return true
    else
        return false
    end
end

-- Ensures the piece is actually on the board.
function raycastToBoard(position)
    local rayOrigin = position + Vector3.new(0, 10, 0)
    local rayDirection = Vector3.new(0, -1, 0) * 100

    local raycastParams = RaycastParams.new()
    raycastParams.FilterDescendantsInstances = {ChessPiecesFolder}
    raycastParams.FilterType = Enum.RaycastFilterType.Exclude

    local result = Workspace:Raycast(rayOrigin, rayDirection, raycastParams)
    if result and result.Instance then
        local partName = result.Instance.Name
        if result.Instance:IsDescendantOf(Workspace.Board) and typeof(partName) == "string" then
            local boardIndex = ChessNotationToIndex(partName)
            if boardIndex then
                return boardIndex, result.Instance.Position
            end
		end
    end
    return nil, nil
end

-- Function to clear selection.
local function clearSelection()
    if wiggleTween then
        wiggleTween:Cancel()
        wiggleTween = nil
    end

    if selectedPiece and selectedPiece.Parent and originalOrientation then
        selectedPiece.Orientation = originalOrientation
    end

    selectedPiece = nil
    selectedPosition = nil
    originalOrientation = nil

    for _, selectionBox in ipairs(selectionBoxes) do
        if selectionBox and selectionBox.Parent then
            selectionBox:Destroy()
        end
    end
    selectionBoxes = {}
end

-- Binds user inputs to the attempt move and selection functions.
local function OnAction(actionName, userInputState, inputObject)
    if actionName == "SelectPiece" and userInputState == Enum.UserInputState.Begin then
        local target = Mouse.Target
        if target then
            local clickedPosition, center = raycastToBoard(Mouse.Hit.p)
            if clickedPosition and isWithinBounds(clickedPosition) then
                local clickedPiece = board[clickedPosition.file][clickedPosition.rank]
                if clickedPiece then
                    if clickedPiece.color == currentTurn then
                        local clickedPieceInstance = ChessPiecesFolder:FindFirstChild(clickedPiece.uniqueId)
                        if selectedPiece == clickedPieceInstance then
                            return
                        end
                        clearSelection()

                        selectedPiece = clickedPieceInstance
                        selectedPosition = clickedPosition
                        originalOrientation = selectedPiece.Orientation

                        local validMoves = getValidMoves(selectedPosition)
                        for _, move in ipairs(validMoves) do
                            local fileChar = string.char(string.byte('A') + move.file - 1)
                            local squareName = fileChar .. tostring(move.rank)
                            local squarePart = Workspace.Board:FindFirstChild(squareName)
                            if squarePart then
                                local selectionBox = Instance.new("SelectionBox")
                                selectionBox.Adornee = squarePart
                                selectionBox.Color3 = Color3.new(0, 1, 0)
                                selectionBox.LineThickness = 0.05
                                selectionBox.SurfaceTransparency = 0.75
                                selectionBox.Parent = squarePart

                                table.insert(selectionBoxes, selectionBox)
                            end
                        end

                        if selectedPiece then
                            selectedPiece.Orientation = originalOrientation + Vector3.new(0, 0, -10)
                            local wiggleInfo = TweenInfo.new(0.4, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true, 0)
                            local wiggleGoal = {Orientation = originalOrientation + Vector3.new(0, 0, 10)}
                            wiggleTween = TweenService:Create(selectedPiece, wiggleInfo, wiggleGoal)
                            wiggleTween:Play()
                        end
                    else
                        if selectedPiece then
                            local success = attemptMovePiece(selectedPosition, clickedPosition)
                            if success then
                                local center = center or target.Position
                                local tweenInfo = TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
                                local tweenGoal = {Position = Vector3.new(center.X, selectedPiece.Position.Y, center.Z)}
                                local moveTween = TweenService:Create(selectedPiece, tweenInfo, tweenGoal)
                                moveTween:Play()
                            end
                            clearSelection()
                        end
                    end
                else
                    if selectedPiece then
                        local success = attemptMovePiece(selectedPosition, clickedPosition)
						if success then
							local center = center or boardPositionToWorldPosition(clickedPosition)
							if center then
								local tweenInfo = TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
								local tweenGoal = {Position = Vector3.new(center.X, selectedPiece.Position.Y, center.Z)}
								local moveTween = TweenService:Create(selectedPiece, tweenInfo, tweenGoal)
								moveTween:Play()
							end
						end

                        clearSelection()
                    end
                end
            else
                -- Clicked outside the board
                clearSelection()
            end
        else
            -- Clicked on something else
            clearSelection()
        end
    end
end

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local updatePieceUniqueIdEvent = ReplicatedStorage:WaitForChild("UpdatePieceUniqueId")

updatePieceUniqueIdEvent.OnClientEvent:Connect(function(newUniqueId, pieceType)
	print("Updated uniqueId on client:", newUniqueId)
	print("Piece Type:", pieceType)

	local piece = game.Workspace:FindFirstChild(pieceType)
	if piece then
		piece:SetAttribute("uniqueId", newUniqueId)
	end
end)

ContextActionService:BindAction("SelectPiece", OnAction, false, Enum.UserInputType.MouseButton1, Enum.UserInputType.Touch)
