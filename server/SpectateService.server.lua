-- ServerScriptService/SpectateService (ServerScript)
-- Handles spectate cycling independently of RoundManager to avoid module load issues.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local spectateEvent = ReplicatedStorage:WaitForChild("SpectateEvent")

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

local function canSpectate(plr: Player)
	return plr:GetAttribute("AliveInRound") ~= true
end

local function sendDefault(plr: Player)
	local ids = getAliveUserIds()
	if #ids == 0 then
		spectateEvent:FireClient(plr, "NoTargets")
		return
	end
	spectateEvent:FireClient(plr, "SetTarget", ids[1])
end

local function cycle(plr: Player, dir: number)
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
		if not canSpectate(plr) then
			spectateEvent:FireClient(plr, "NoTargets")
			return
		end
		sendDefault(plr)
	elseif action == "Next" then
		if not canSpectate(plr) then
			spectateEvent:FireClient(plr, "NoTargets")
			return
		end
		cycle(plr, 1)
	elseif action == "Prev" then
		if not canSpectate(plr) then
			spectateEvent:FireClient(plr, "NoTargets")
			return
		end
		cycle(plr, -1)
	end
end)
