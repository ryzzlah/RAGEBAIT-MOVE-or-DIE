-- StarterPlayerScripts/ArenaUISuppressor.lua
-- Hides non-essential UI while the local player is in the arena during a match.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local matchStateEvent = ReplicatedStorage:WaitForChild("MatchState")
local roundInfoEvent = ReplicatedStorage:WaitForChild("RoundInfo")

local inMatch = false
local arenaUiSuppressed = false
local suppressedGuis = {}

local function isWhitelistedGui(screenGui: ScreenGui)
	return screenGui.Name == "SprintUI"
end

local function suppressArenaUi()
	if arenaUiSuppressed then
		return
	end

	arenaUiSuppressed = true
	table.clear(suppressedGuis)

	for _, child in ipairs(playerGui:GetChildren()) do
		if child:IsA("ScreenGui") and not isWhitelistedGui(child) and child.Enabled then
			suppressedGuis[child] = true
			child.Enabled = false
		end
	end
end

local function restoreArenaUi()
	if not arenaUiSuppressed then
		return
	end

	for gui in pairs(suppressedGuis) do
		if gui and gui.Parent == playerGui then
			gui.Enabled = true
		end
	end

	table.clear(suppressedGuis)
	arenaUiSuppressed = false
end

local function trySuppressForArena()
	if inMatch and not arenaUiSuppressed and player:GetAttribute("InRound") == true then
		suppressArenaUi()
	end
end

local function setInMatchState(state: boolean)
	if inMatch == state then
		return
	end

	inMatch = state
	if not inMatch then
		restoreArenaUi()
	else
		trySuppressForArena()
	end
end

matchStateEvent.OnClientEvent:Connect(function(state)
	setInMatchState(state == true)
end)

roundInfoEvent.OnClientEvent:Connect(function(payload)
	if typeof(payload) ~= "table" then
		return
	end

	if payload.inMatch ~= nil then
		setInMatchState(payload.inMatch == true)
	end
end)

player:GetAttributeChangedSignal("InRound"):Connect(function()
	trySuppressForArena()
end)

-- Initial check in case we join mid-round.
task.defer(function()
	trySuppressForArena()
end)
