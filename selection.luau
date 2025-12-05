local rs = game:GetService("ReplicatedStorage");

local updatePieceUniqueIdEvent = rs:FindFirstChild("UpdatePieceUniqueId");
if not updatePieceUniqueIdEvent then
	updatePieceUniqueIdEvent = Instance.new("RemoteEvent");
	updatePieceUniqueIdEvent.Name = "UpdatePieceUniqueId";
	updatePieceUniqueIdEvent.Parent = rs;
end

local function printTable(tbl, indent)
    indent = indent or "";

    if not tbl then
        print(indent .. "Value is nil");
        return;
    end

    if type(tbl) ~= "table" then
        print(indent .. tostring(tbl));
        return;
    end

    for key, value in pairs(tbl) do
        if type(value) == "table" then
            print(indent .. tostring(key) .. ":");
            printTable(value, indent .. "  ");
        else
            print(indent .. tostring(key) .. " = " .. tostring(value));
        end
    end
end;

game.ReplicatedStorage.MovePiece.OnServerEvent:Connect(function(player, selectedPiece, selectedPosition, clickedPosition)
	print("Selected Piece Table:");
	printTable(selectedPiece);

	print("Selected Position Table:");
	printTable(selectedPosition);

	print("Clicked Position Table:");
	printTable(clickedPosition);

	if selectedPiece and selectedPiece.uniqueId then
		selectedPiece.uniqueId = selectedPiece.uniqueId .. "_" .. clickedPosition.rank .. selectedPosition.file
		print("Updated selectedPiece uniqueId to:", selectedPiece.uniqueId);

		updatePieceUniqueIdEvent:FireAllClients(selectedPiece.uniqueId, selectedPiece.pieceType);
	else
		print("selectedPiece does not have a uniqueId field.");
	end
end);
