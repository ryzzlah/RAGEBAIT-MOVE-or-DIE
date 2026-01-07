-- ServerScriptService/TrailCatalog.server.lua
-- Lets clients request the list of premium trails (folder names) safely.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local RF = ReplicatedStorage:FindFirstChild("GetPremiumTrailIds")
if not RF then
	RF = Instance.new("RemoteFunction")
	RF.Name = "GetPremiumTrailIds"
	RF.Parent = ReplicatedStorage
end

local PREMIUM_FOLDER_NAME = "Robux_Trails" -- this matches your screenshot
local premiumFolder = ServerStorage:WaitForChild(PREMIUM_FOLDER_NAME)

RF.OnServerInvoke = function(plr)
	local ids = {}
	for _, child in ipairs(premiumFolder:GetChildren()) do
		if child:IsA("Folder") then
			table.insert(ids, child.Name)
		end
	end
	table.sort(ids)
	return ids
end

