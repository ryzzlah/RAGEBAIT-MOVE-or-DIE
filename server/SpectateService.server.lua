-- ServerScriptService/SpectateService (ModuleScript)
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local spectateEvent = ReplicatedStorage:WaitForChild("SpectateEvent")

local SpectateService = {}

local function getAliveUserIds()
	local ids = {}
	for _, p in ipairs(Players:GetPlayers()) do
		if p:GetAttribute("InRound") == true and p:GetAttribute("AliveInRound") == true then
			table.insert(ids, p.UserId)
		end
	end
	return ids
end

local function getIndex(ids, userId)
	for i, v in ipairs(ids) do
		if v == userId then
			return i
		end
	end
	return nil
end

local function sendDefault(plr)
	local ids = getAliveUserIds()
	if #ids == 0 then
		spectateEvent:FireClient(plr, "NoTargets")
		return
	end
	spectateEvent:FireClient(plr, "SetTarget", ids[1])
end

local function cycle(plr, dir)
	local ids = getAliveUserIds()
	if #ids == 0 then
		spectateEvent:FireClient(plr, "NoTargets")
		return
	end

	local current = plr:GetAttribute("SpectateTargetUserId")
	local idx = current and getIndex(ids, current) or 1

	local newIdx = idx + dir
	if newIdx < 1 then newIdx = #ids end
	if newIdx > #ids then newIdx = 1 end

	local newTarget = ids[newIdx]
	plr:SetAttribute("SpectateTargetUserId", newTarget)
	spectateEvent:FireClient(plr, "SetTarget", newTarget)
end

spectateEvent.OnServerEvent:Connect(function(plr, action)
	if action == "RequestList" then
		sendDefault(plr)
	elseif action == "Next" then
		cycle(plr, 1)
	elseif action == "Prev" then
		cycle(plr, -1)
	end
end)

-- Helper calls
function SpectateService.MarkEliminated(plr: Player)
	plr:SetAttribute("AliveInRound", false)
end

function SpectateService.SetInMatchLobbySpectate(plr: Player)
	-- Mid-round joiner: not in round, not alive in round, but match running
	plr:SetAttribute("InRound", false)
	plr:SetAttribute("AliveInRound", false)
	plr:SetAttribute("SpectateTargetUserId", nil)
end

function SpectateService.ClearPlayer(plr: Player)
	plr:SetAttribute("InRound", false)
	plr:SetAttribute("AliveInRound", false)
	plr:SetAttribute("SpectateTargetUserId", nil)
end

return SpectateService

