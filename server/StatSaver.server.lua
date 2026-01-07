-- ServerScriptService/DataStoreSave.server.lua
-- Saves leaderstats Coins + Wins permanently.
-- Works with your existing RoundManager because it already updates leaderstats.

local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")

local STORE_NAME = "PlayerStats_v1" -- change this if you ever change your data format
local store = DataStoreService:GetDataStore(STORE_NAME)

local AUTOSAVE_INTERVAL = 60 -- seconds
local MAX_RETRIES = 6

local function retry(pcallFn)
	local lastErr
	for i = 1, MAX_RETRIES do
		local ok, result = pcall(pcallFn)
		if ok then return true, result end
		lastErr = result
		task.wait(0.5 * i)
	end
	return false, lastErr
end

local function getStatsFolder(plr: Player)
	return plr:FindFirstChild("leaderstats")
end

local function readInt(ls: Instance?, name: string): number
	local v = ls and ls:FindFirstChild(name)
	if v and v:IsA("IntValue") then
		return v.Value
	end
	return 0
end

local function writeInt(ls: Instance?, name: string, value: number)
	if not ls then return end
	local v = ls:FindFirstChild(name)
	if v and v:IsA("IntValue") then
		v.Value = value
	end
end

local function loadPlayer(plr: Player)
	-- Wait a moment for your RoundManager/leaderstats creator to run
	task.wait(0.2)

	local ls = getStatsFolder(plr)
	if not ls then
		-- If your game ever spawns player without leaderstats, we still won't crash
		warn("[DataStoreSave] No leaderstats for", plr.Name)
		return
	end

	local key = "u_" .. plr.UserId

	local ok, data = retry(function()
		return store:GetAsync(key)
	end)

	if not ok then
		warn("[DataStoreSave] Load failed for", plr.Name, data)
		return
	end

	if type(data) ~= "table" then
		-- first time player (or corrupted old data), leave defaults
		return
	end

	-- Apply loaded stats
	writeInt(ls, "Coins", tonumber(data.Coins) or 0)
	writeInt(ls, "Wins", tonumber(data.Wins) or 0)
end

local function savePlayer(plr: Player)
	local ls = getStatsFolder(plr)
	if not ls then return end

	local key = "u_" .. plr.UserId
	local payload = {
		Coins = readInt(ls, "Coins"),
		Wins  = readInt(ls, "Wins"),
		-- add more later if you want (Inventory, EquippedTrail, etc.)
	}

	local ok, err = retry(function()
		-- Use UpdateAsync to reduce “last write wins” issues if they rejoin fast
		return store:UpdateAsync(key, function(old)
			old = (type(old) == "table") and old or {}
			old.Coins = payload.Coins
			old.Wins = payload.Wins
			return old
		end)
	end)

	if not ok then
		warn("[DataStoreSave] Save failed for", plr.Name, err)
	end
end

-- Load on join
Players.PlayerAdded:Connect(loadPlayer)

-- Save on leave
Players.PlayerRemoving:Connect(savePlayer)

-- Autosave loop (helps if server crashes)
task.spawn(function()
	while true do
		task.wait(AUTOSAVE_INTERVAL)
		for _, plr in ipairs(Players:GetPlayers()) do
			savePlayer(plr)
		end
	end
end)

-- Save on shutdown
game:BindToClose(function()
	for _, plr in ipairs(Players:GetPlayers()) do
		savePlayer(plr)
	end
	task.wait(2) -- give requests a moment to finish
end)
