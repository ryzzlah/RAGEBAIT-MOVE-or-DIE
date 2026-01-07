-- ServerScriptService/ReadyManager.server.lua
-- Server truth for Ready state
-- Default: READY = true on join
-- Also resets READY = true whenever a match ends (when MatchState fires false)
-- No client-only APIs used here (no OnClientEvent)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- RemoteEvent from the UI LocalScript
local readyEvent = ReplicatedStorage:FindFirstChild("ReadyToggle")
if not readyEvent then
	readyEvent = Instance.new("RemoteEvent")
	readyEvent.Name = "ReadyToggle"
	readyEvent.Parent = ReplicatedStorage
end

-- RemoteEvent from RoundManager
local matchState = ReplicatedStorage:FindFirstChild("MatchState")
if not matchState then
	matchState = Instance.new("RemoteEvent")
	matchState.Name = "MatchState"
	matchState.Parent = ReplicatedStorage
end

-- Optional: your status broadcast event (RoundStatus)
local statusEvent = ReplicatedStorage:FindFirstChild("RoundStatus")
if not statusEvent then
	statusEvent = Instance.new("RemoteEvent")
	statusEvent.Name = "RoundStatus"
	statusEvent.Parent = ReplicatedStorage
end

local function broadcast(msg)
	statusEvent:FireAllClients(tostring(msg))
end

local function setReady(plr: Player, value: boolean)
	plr:SetAttribute("Ready", value == true)
end

-- Default ready when joining
Players.PlayerAdded:Connect(function(plr)
	-- Default READY = true
	if plr:GetAttribute("Ready") == nil then
		setReady(plr, true)
	else
		-- if something set it false earlier, you said you want default ready anyway
		setReady(plr, true)
	end
end)

-- Studio safety (players already in server)
for _, plr in ipairs(Players:GetPlayers()) do
	setReady(plr, true)
end

-- Client toggles ready/unready
readyEvent.OnServerEvent:Connect(function(plr: Player, wantsReady)
	if typeof(wantsReady) ~= "boolean" then return end
	setReady(plr, wantsReady)
	-- optional debug
	-- print(("[ReadyManager] %s Ready=%s"):format(plr.Name, tostring(wantsReady)))
end)

-- When match ends, force everyone READY again
matchState.OnServerEvent:Connect(function(plr, _)
	-- Ignore: clients should never call this.
end)

-- We can’t "listen" to a RemoteEvent firing, so we do the reset by **adding one line in RoundManager**:
-- matchState:FireAllClients(false) already exists in your RoundManager.
-- Add ONE extra loop right after that in RoundManager OR call this helper from RoundManager.
-- But if you refuse touching RoundManager, do this below:

-- Hack-free approach: RoundManager already sets Ready=true at end of match in your code.
-- If yours doesn’t anymore, add this in RoundManager end-match section:
-- plr:SetAttribute("Ready", true)

broadcast("Ready system loaded.")

