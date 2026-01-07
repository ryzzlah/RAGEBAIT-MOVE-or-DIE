-- ServerScriptService/RoundManager
-- Stable rounds + tile recovery + earnings + spectator targets
-- + Revive system (Extra Life pass OR small revive dev product)
-- + Auto-revive after dev product purchase
-- + Spectator works in lobby + for mid-match joiners
-- + NEW: 5s "Round 1 begins in..." countdown ONLY once per match start

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

-- ===== CONFIG =====
local MIN_PLAYERS = 2
local INTERMISSION = 15
local BETWEEN_ROUNDS = 2
local ROUND_COUNT = 4
local ROUND_TIME = 22
local TELEPORT_Y = 6

-- Make respawns quick (RoundManager handles teleports anyway)
Players.RespawnTime = 1.0

-- Round difficulty tuning
local STEP_INTERVAL = {0.95, 0.75, 0.60, 0.48}
local BREAKS_PER_STEP = {1, 2, 3, 5}
local RADIUS_FRACTION = {0.95, 0.78, 0.58, 0.42}

-- Warning/kill window
local WARNING_STEP_TIME = 0.10
local WARNING_STEPS_BY_ROUND = {9, 7, 6, 5}
local KILL_ACTIVE = 0.80

-- Tile recovery
local TILE_RESPAWN_BY_ROUND = {1.25, 1.50, 1.70, 1.90}
local TILE_RESPAWN_SUDDEN = 1.25

-- Targeting
local THREAT_CHANCE = 0.80
local THREAT_RADIUS = 16

-- Sudden death
local SUDDEN_DEATH_TIME = 25
local SUDDEN_INTERVAL = 0.22
local SUDDEN_BREAKS = 7
local SUDDEN_WARNING = 4

-- ===== REWARDS =====
local SURVIVAL_COIN_INTERVAL = 2
local SURVIVAL_COINS_PER_TICK = 1
local WIN_BONUS_COINS = 25

-- ===== ANTI-CAMP / ANTI-IDLE =====
local OUTSIDE_RADIUS_GRACE = 2.0
local IDLE_TIME_LIMIT = 4.0
local IDLE_MOVE_EPS = 1.25

-- ===== REVIVE CONFIG =====
local SMALL_REVIVE_PRODUCT = 3498314947 -- must match MonetisationGrants
local REVIVE_TIMEOUT = 10
local NO_REVIVES_IF_MATCH_SIZE_LEQ = 2

-- ===== NEW: PRE-ROUND COUNTDOWN (ONLY ONCE) =====
local PRE_ROUND_COUNTDOWN = 5

-- ===== REFERENCES =====
local mapTilesFolder = workspace:WaitForChild("MapTiles")
local arenaSpawnsFolder = workspace:WaitForChild("ArenaSpawns")
local arenaCenter = workspace:WaitForChild("ArenaCenter")
local lobbySpawnsFolder = workspace:FindFirstChild("LobbySpawns")

-- ===== RemoteEvents =====
local function getOrMakeRemote(name: string)
	local r = ReplicatedStorage:FindFirstChild(name)
	if not r then
		r = Instance.new("RemoteEvent")
		r.Name = name
		r.Parent = ReplicatedStorage
	end
	return r
end

local statusEvent   = getOrMakeRemote("RoundStatus")
local earningsEvent = getOrMakeRemote("MatchEarnings")
local matchState    = getOrMakeRemote("MatchState")
local spectateEvent = getOrMakeRemote("SpectateEvent")
local reviveRemote  = getOrMakeRemote("ReviveRemote")

local function broadcast(msg)
	statusEvent:FireAllClients(tostring(msg))
end

-- ===== READY =====
local function isReady(plr: Player): boolean
	return plr:GetAttribute("Ready") == true
end

local function readyPlayers()
	local t = {}
	for _, plr in ipairs(Players:GetPlayers()) do
		if isReady(plr) then
			table.insert(t, plr)
		end
	end
	return t
end

-- ===== LEADERSTATS =====
local function ensureLeaderstats(plr: Player)
	local ls = plr:FindFirstChild("leaderstats")
	if not ls then
		ls = Instance.new("Folder")
		ls.Name = "leaderstats"
		ls.Parent = plr
	end

	local wins = ls:FindFirstChild("Wins")
	if not wins then
		wins = Instance.new("IntValue")
		wins.Name = "Wins"
		wins.Value = 0
		wins.Parent = ls
	end

	local coins = ls:FindFirstChild("Coins")
	if not coins then
		coins = Instance.new("IntValue")
		coins.Name = "Coins"
		coins.Value = 0
		coins.Parent = ls
	end

	if plr:GetAttribute("CoinMultiplier") == nil then plr:SetAttribute("CoinMultiplier", 1) end
	if plr:GetAttribute("Ready") == nil then plr:SetAttribute("Ready", true) end
	if plr:GetAttribute("InRound") == nil then plr:SetAttribute("InRound", false) end
	if plr:GetAttribute("AliveInRound") == nil then plr:SetAttribute("AliveInRound", false) end
	if plr:GetAttribute("Eliminated") == nil then plr:SetAttribute("Eliminated", false) end
	if plr:GetAttribute("ReviveTokens") == nil then plr:SetAttribute("ReviveTokens", 0) end
end

Players.PlayerAdded:Connect(ensureLeaderstats)
for _, p in ipairs(Players:GetPlayers()) do ensureLeaderstats(p) end

local function addCoinsToLeaderboard(plr: Player, amount: number)
	if amount <= 0 then return end
	local ls = plr:FindFirstChild("leaderstats")
	local coins = ls and ls:FindFirstChild("Coins")
	if not coins then return end
	local mult = plr:GetAttribute("CoinMultiplier") or 1
	coins.Value += math.floor(amount * mult)
end

local function addWin(plr: Player)
	local ls = plr:FindFirstChild("leaderstats")
	local wins = ls and ls:FindFirstChild("Wins")
	if wins then wins.Value += 1 end
end

-- ===== PLAYER HELPERS =====
local function getChar(plr: Player) return plr.Character end
local function getHum(plr: Player)
	local char = getChar(plr)
	return char and char:FindFirstChildOfClass("Humanoid")
end
local function getRoot(plr: Player)
	local char = getChar(plr)
	return char and char:FindFirstChild("HumanoidRootPart")
end

local function teleportTo(plr: Player, cf: CFrame)
	local root = getRoot(plr)
	if root then
		root.CFrame = cf
	end
end

local function pickRandomChild(folder: Instance)
	local kids = folder:GetChildren()
	if #kids == 0 then return nil end
	return kids[math.random(1, #kids)]
end

local function teleportToLobby(plr: Player)
	if lobbySpawnsFolder and #lobbySpawnsFolder:GetChildren() > 0 then
		local sp = pickRandomChild(lobbySpawnsFolder)
		if sp and sp:IsA("SpawnLocation") then
			teleportTo(plr, sp.CFrame + Vector3.new(0, TELEPORT_Y, 0))
			return
		end
	end
	plr:LoadCharacter()
end

local function teleportToArena(plr: Player)
	local sp = pickRandomChild(arenaSpawnsFolder)
	if sp and sp:IsA("BasePart") then
		teleportTo(plr, sp.CFrame + Vector3.new(0, TELEPORT_Y, 0))
	end
end

-- ===== MATCH STATE =====
local CURRENT_MATCH_PLAYERS: {Player} = {}
local MATCH_RUNNING = false

local REVIVE_USED_PASS: {[Player]: boolean} = {}
local REVIVE_PENDING: {[Player]: boolean} = {}
local TOKEN_WATCH_CONN: {[Player]: RBXScriptConnection} = {}

local function setInRound(plr: Player, v: boolean) plr:SetAttribute("InRound", v) end
local function setAliveInRound(plr: Player, v: boolean) plr:SetAttribute("AliveInRound", v) end
local function setElim(plr: Player, v: boolean) plr:SetAttribute("Eliminated", v) end
local function isElim(plr: Player): boolean return plr:GetAttribute("Eliminated") == true end

local function alivePlayers(matchPlayers: {Player})
	local t = {}
	for _, plr in ipairs(matchPlayers) do
		if plr and plr.Parent == Players and not isElim(plr) then
			if plr:GetAttribute("InRound") == true and plr:GetAttribute("AliveInRound") == true then
				local hum = getHum(plr)
				if hum and hum.Health > 0 and getRoot(plr) then
					table.insert(t, plr)
				end
			end
		end
	end
	return t
end

-- ===== SPECTATE =====
-- Anyone can request targets during a running match as long as they are NOT alive in-round.
spectateEvent.OnServerEvent:Connect(function(plr, action)
	if action ~= "GetTargets" then return end

	if not MATCH_RUNNING then
		spectateEvent:FireClient(plr, "Targets", {})
		return
	end

	local alive = plr:GetAttribute("AliveInRound") == true
	if alive then
		spectateEvent:FireClient(plr, "Targets", {})
		return
	end

	local ids = {}
	for _, p in ipairs(CURRENT_MATCH_PLAYERS) do
		if p and p.Parent == Players then
			if p:GetAttribute("InRound") == true and p:GetAttribute("AliveInRound") == true then
				table.insert(ids, p.UserId)
			end
		end
	end
	spectateEvent:FireClient(plr, "Targets", ids)
end)

-- ===== REVIVE HELPERS =====
local function canPlayerRevive(plr: Player): (boolean, boolean, string)
	-- returns: canConsumeNow, canShowReviveButton, messageText
	if not MATCH_RUNNING then
		return false, false, "Match ended."
	end

	if plr:GetAttribute("AliveInRound") == true then
		return false, false, "You are alive."
	end

	-- If match is basically 1v1/2-player, no revive
	if #CURRENT_MATCH_PLAYERS <= NO_REVIVES_IF_MATCH_SIZE_LEQ then
		return false, false, "No revives in 2-player matches."
	end

	local alive = alivePlayers(CURRENT_MATCH_PLAYERS)
	if #alive <= 1 then
		return false, false, "Round is ending."
	end

	local tokens = tonumber(plr:GetAttribute("ReviveTokens")) or 0
	local hasPass = (plr:GetAttribute("HasExtraLifePass") == true)
	local passUnused = hasPass and (REVIVE_USED_PASS[plr] ~= true)

	if passUnused then
		return true, true, "Use your Extra Life revive?"
	end

	if tokens > 0 then
		return true, true, ("Use 1 Revive Token? (You have %d)"):format(tokens)
	end

	-- No tokens/pass: still show button to buy
	return false, true, "Buy 1 revive for this match?"
end

local function showReviveUI(plr: Player)
	if REVIVE_PENDING[plr] then return end
	REVIVE_PENDING[plr] = true

	local canConsumeNow, showBtn, text = canPlayerRevive(plr)
	reviveRemote:FireClient(plr, "Show", {
		canConsumeNow = canConsumeNow,
		showReviveButton = showBtn,
		text = text,
		timeout = REVIVE_TIMEOUT,
	})

	task.delay(REVIVE_TIMEOUT + 1, function()
		if not plr or plr.Parent ~= Players then return end
		if not REVIVE_PENDING[plr] then return end
		if plr:GetAttribute("AliveInRound") == true then
			REVIVE_PENDING[plr] = nil
			return
		end

		REVIVE_PENDING[plr] = nil
		reviveRemote:FireClient(plr, "Hide")

		-- Keep them spectator-in-match so Spectate UI stays
		setInRound(plr, true)
		setAliveInRound(plr, false)
		setElim(plr, true)
		teleportToLobby(plr)
	end)
end

local function doRevive(plr: Player)
	plr:LoadCharacter()
	task.wait(0.05)
	teleportToArena(plr)
	setElim(plr, false)
	setInRound(plr, true)
	setAliveInRound(plr, true)
	REVIVE_PENDING[plr] = nil
	reviveRemote:FireClient(plr, "Hide")
end

local function sendHomeSpectator(plr: Player)
	REVIVE_PENDING[plr] = nil
	reviveRemote:FireClient(plr, "Hide")

	-- Stay in match as spectator so spectate UI doesn’t disappear
	setElim(plr, true)
	setInRound(plr, true)
	setAliveInRound(plr, false)

	teleportToLobby(plr)
end

local function attachTokenWatcher(plr: Player)
	if TOKEN_WATCH_CONN[plr] then return end
	TOKEN_WATCH_CONN[plr] = plr:GetAttributeChangedSignal("ReviveTokens"):Connect(function()
		if not MATCH_RUNNING then return end
		if not REVIVE_PENDING[plr] then return end
		if plr:GetAttribute("AliveInRound") == true then return end

		local tokens = tonumber(plr:GetAttribute("ReviveTokens")) or 0
		if tokens <= 0 then return end

		plr:SetAttribute("ReviveTokens", tokens - 1)
		doRevive(plr)
	end)
end

local function detachTokenWatcher(plr: Player)
	if TOKEN_WATCH_CONN[plr] then
		TOKEN_WATCH_CONN[plr]:Disconnect()
		TOKEN_WATCH_CONN[plr] = nil
	end
end

local function eliminate(plr: Player, reason: string?)
	if isElim(plr) then return end
	setElim(plr, true)
	setAliveInRound(plr, false)

	broadcast(plr.Name .. " " .. (reason or "died!"))

	local hum = getHum(plr)
	if hum and hum.Health > 0 then
		hum.Health = 0
	end

	attachTokenWatcher(plr)

	task.defer(function()
		if plr and plr.Parent == Players and MATCH_RUNNING then
			setInRound(plr, true)
			setAliveInRound(plr, false)
			showReviveUI(plr)
		end
	end)
end

reviveRemote.OnServerEvent:Connect(function(plr: Player, action)
	if typeof(action) ~= "string" then return end
	if not plr or plr.Parent ~= Players then return end

	if action == "Home" then
		sendHomeSpectator(plr)
		return
	end

	if action == "RequestReviveOrBuy" then
		if not MATCH_RUNNING then
			sendHomeSpectator(plr)
			return
		end

		if plr:GetAttribute("AliveInRound") == true then
			return
		end

		local canConsumeNow, showBtn = canPlayerRevive(plr)
		if not showBtn then return end

		local tokens = tonumber(plr:GetAttribute("ReviveTokens")) or 0
		local hasPass = (plr:GetAttribute("HasExtraLifePass") == true)
		local passUnused = hasPass and (REVIVE_USED_PASS[plr] ~= true)

		if canConsumeNow then
			if passUnused then
				REVIVE_USED_PASS[plr] = true
				doRevive(plr)
				return
			end

			if tokens > 0 then
				plr:SetAttribute("ReviveTokens", tokens - 1)
				doRevive(plr)
				return
			end
		end

		reviveRemote:FireClient(plr, "PromptPurchase", SMALL_REVIVE_PRODUCT)
		return
	end

	if action == "Refresh" then
		if MATCH_RUNNING and plr:GetAttribute("AliveInRound") ~= true then
			REVIVE_PENDING[plr] = nil
			showReviveUI(plr)
		end
		return
	end
end)

-- ===== TILE DEFAULTS =====
local TileDefaults: {[BasePart]: {
	Color: Color3,
	Material: Enum.Material,
	Transparency: number,
	CanCollide: boolean,
	CanTouch: boolean,
}} = {}

local function snapshotTileDefaults()
	TileDefaults = {}
	for _, tile in ipairs(mapTilesFolder:GetChildren()) do
		if tile:IsA("BasePart") then
			TileDefaults[tile] = {
				Color = tile.Color,
				Material = tile.Material,
				Transparency = tile.Transparency,
				CanCollide = tile.CanCollide,
				CanTouch = tile.CanTouch,
			}
		end
	end
end

local function restoreTileDefaults(tile: BasePart)
	local d = TileDefaults[tile]
	if not d then return end
	tile.Color = d.Color
	tile.Material = d.Material
	tile.Transparency = d.Transparency
	tile.CanCollide = d.CanCollide
	tile.CanTouch = d.CanTouch
end

local function resetTilesToDefaults()
	for _, tile in ipairs(mapTilesFolder:GetChildren()) do
		if tile:IsA("BasePart") then
			tile:SetAttribute("Disabled", false)
			tile:SetAttribute("IsKillTile", false)
			tile:SetAttribute("InUse", false)
			restoreTileDefaults(tile)
		end
	end
end

-- ===== RADIUS / CANDIDATES =====
local function computeMaxRadius()
	local maxR = 0
	for _, tile in ipairs(mapTilesFolder:GetChildren()) do
		if tile:IsA("BasePart") then
			local d = (tile.Position - arenaCenter.Position).Magnitude
			if d > maxR then maxR = d end
		end
	end
	return maxR
end

local function buildCandidates(radius: number)
	local candidates = {}
	for _, tile in ipairs(mapTilesFolder:GetChildren()) do
		if tile:IsA("BasePart") then
			if tile:GetAttribute("Disabled") ~= true and tile:GetAttribute("InUse") ~= true then
				local d = (tile.Position - arenaCenter.Position).Magnitude
				if d <= radius then
					table.insert(candidates, tile)
				end
			end
		end
	end
	return candidates
end

local function popRandom(list)
	local n = #list
	if n == 0 then return nil end
	local idx = math.random(1, n)
	local t = list[idx]
	list[idx] = list[n]
	list[n] = nil
	return t
end

local function removeFromCandidates(candidates: {BasePart}, tile: BasePart)
	for i = #candidates, 1, -1 do
		if candidates[i] == tile then
			candidates[i] = candidates[#candidates]
			candidates[#candidates] = nil
			return
		end
	end
end

local function getNearestTileToPosition(pos: Vector3, candidates: {BasePart}, maxDist: number)
	local best, bestD = nil, maxDist
	for _, tile in ipairs(candidates) do
		if tile and tile.Parent then
			local d = (tile.Position - pos).Magnitude
			if d < bestD then
				bestD = d
				best = tile
			end
		end
	end
	return best
end

local function pickThreatTile(candidates: {BasePart}, aliveList: {Player})
	for i = #candidates, 1, -1 do
		if (not candidates[i]) or (not candidates[i].Parent) then
			candidates[i] = candidates[#candidates]
			candidates[#candidates] = nil
		end
	end
	if #candidates == 0 then return nil end

	if #aliveList > 0 and math.random() < THREAT_CHANCE then
		local plr = aliveList[math.random(1, #aliveList)]
		local root = getRoot(plr)
		if root then
			local tile = getNearestTileToPosition(root.Position, candidates, THREAT_RADIUS)
			if tile then
				removeFromCandidates(candidates, tile)
				return tile
			end
		end
	end

	return popRandom(candidates)
end

-- ===== TILE VISUALS + RECOVERY =====
local function warningFlash(tile: BasePart, warningSteps: number)
	tile.Material = Enum.Material.Neon
	for i = 1, warningSteps do
		if not tile.Parent then return end
		tile.Transparency = 0
		tile.Color = (i % 2 == 0) and Color3.fromRGB(255, 255, 255) or Color3.fromRGB(255, 0, 0)
		task.wait(WARNING_STEP_TIME)
	end
end

local function disableTileThenRespawn(tile: BasePart, respawnDelay: number)
	if not tile or not tile.Parent then return end
	tile:SetAttribute("Disabled", true)
	tile:SetAttribute("IsKillTile", false)
	tile:SetAttribute("InUse", false)
	tile.CanCollide = false
	tile.CanTouch = false
	tile.Transparency = 1

	task.delay(respawnDelay, function()
		if not tile or not tile.Parent then return end
		tile:SetAttribute("Disabled", false)
		tile:SetAttribute("IsKillTile", false)
		tile:SetAttribute("InUse", false)
		restoreTileDefaults(tile)
	end)
end

local function warnKillThenRecover(tile: BasePart, warningSteps: number, respawnDelay: number)
	if not tile or not tile.Parent then return end
	if tile:GetAttribute("Disabled") == true then return end
	if tile:GetAttribute("InUse") == true then return end

	tile:SetAttribute("InUse", true)
	tile:SetAttribute("IsKillTile", false)

	warningFlash(tile, warningSteps)
	if not tile or not tile.Parent then return end

	tile.Transparency = 0
	tile.Material = Enum.Material.Neon
	tile.Color = Color3.fromRGB(255, 40, 40)
	tile:SetAttribute("IsKillTile", true)

	task.wait(KILL_ACTIVE)

	if tile and tile.Parent then
		disableTileThenRespawn(tile, respawnDelay)
	end
end

-- ===== KILL CHECK =====
local function getStandingTile(hrp: BasePart)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Whitelist
	params.FilterDescendantsInstances = {mapTilesFolder}
	params.IgnoreWater = true

	local origin = hrp.Position
	local dir = Vector3.new(0, -8, 0)
	local result = workspace:Raycast(origin, dir, params)
	if result and result.Instance and result.Instance:IsA("BasePart") then
		return result.Instance
	end
	return nil
end

-- ===== STARTUP =====
math.randomseed(os.clock())

while #mapTilesFolder:GetChildren() < 50 do
	broadcast("Waiting for tiles...")
	task.wait(0.2)
end

snapshotTileDefaults()
resetTilesToDefaults()

matchState:FireAllClients(false)
broadcast("Waiting for players...")

-- ===== MAIN LOOP =====
while true do
	-- Wait until enough ready players
	while true do
		local r = readyPlayers()
		if #r >= MIN_PLAYERS then break end
		broadcast(("Waiting for players... (Ready %d/%d)"):format(#r, MIN_PLAYERS))
		task.wait(1)
	end

	-- lobby staging reset
	for _, plr in ipairs(Players:GetPlayers()) do
		ensureLeaderstats(plr)
		setElim(plr, true)
		setInRound(plr, false)
		setAliveInRound(plr, false)
		REVIVE_PENDING[plr] = nil
		REVIVE_USED_PASS[plr] = nil
		detachTokenWatcher(plr)

		if not plr.Character then plr:LoadCharacter() end
		task.wait(0.02)
		teleportToLobby(plr)
	end

	-- intermission
	for i = INTERMISSION, 1, -1 do
		local r = readyPlayers()
		if #r < MIN_PLAYERS then
			broadcast(("Waiting for players... (Ready %d/%d)"):format(#r, MIN_PLAYERS))
			break
		end
		broadcast("Intermission: " .. i)
		task.wait(1)
	end

	local matchPlayers = readyPlayers()
	if #matchPlayers < MIN_PLAYERS then
		continue
	end

	CURRENT_MATCH_PLAYERS = matchPlayers
	MATCH_RUNNING = true
	matchState:FireAllClients(true)

	resetTilesToDefaults()
	local maxR = computeMaxRadius()

	local earnedThisMatch: {[Player]: number} = {}
	local LAST_STANDING: Player? = nil

	-- spawn match players into arena
	for _, plr in ipairs(matchPlayers) do
		ensureLeaderstats(plr)
		earnedThisMatch[plr] = 0
		REVIVE_USED_PASS[plr] = nil
		REVIVE_PENDING[plr] = nil
		detachTokenWatcher(plr)

		if not plr.Character then plr:LoadCharacter() end
		setElim(plr, false)
		setInRound(plr, true)
		setAliveInRound(plr, true)

		task.wait(0.03)
		teleportToArena(plr)
	end

	-- Anyone who joins mid-match becomes a spectator (so they get spectate button)
	local joinConn
	joinConn = Players.PlayerAdded:Connect(function(plr)
		task.defer(function()
			if not MATCH_RUNNING then return end
			ensureLeaderstats(plr)
			setElim(plr, true)
			setInRound(plr, true)
			setAliveInRound(plr, false)
			if not plr.Character then plr:LoadCharacter() end
			task.wait(0.05)
			teleportToLobby(plr)
		end)
	end)

	-- ===== NEW: PRE-ROUND COUNTDOWN (ONLY ONCE PER MATCH) =====
	local PRE_ROUND = true
	for i = PRE_ROUND_COUNTDOWN, 1, -1 do
		-- Only a friendly countdown. No tiles, no kills yet.
		broadcast(("Round 1 begins in %d..."):format(i))
		task.wait(1)
	end
	broadcast("Round 1 GO!")
	PRE_ROUND = false
	-- =========================================================

	local nextPay = os.clock() + SURVIVAL_COIN_INTERVAL
	local lastPos: {[Player]: Vector3} = {}
	local lastMoveTime: {[Player]: number} = {}
	local outsideSince: {[Player]: number?} = {}

	for _, plr in ipairs(matchPlayers) do
		local hrp = getRoot(plr)
		lastPos[plr] = hrp and hrp.Position or Vector3.zero
		lastMoveTime[plr] = os.clock()
		outsideSince[plr] = nil
	end

	local currentRoundIndex = 1
	local currentActiveRadius = maxR * (RADIUS_FRACTION[currentRoundIndex] or 0.5)
	local currentWarningSteps = WARNING_STEPS_BY_ROUND[currentRoundIndex] or 6
	local currentRespawnDelay = TILE_RESPAWN_BY_ROUND[currentRoundIndex] or 1.5

	local function forceKillTileUnder(plr: Player, warningSteps: number, respawnDelay: number)
		local hrp = getRoot(plr)
		if not hrp then return end
		local tile = getStandingTile(hrp)
		if not tile then return end
		if tile:GetAttribute("Disabled") == true then return end
		if tile:GetAttribute("InUse") == true then return end
		task.spawn(function()
			warnKillThenRecover(tile, math.max(3, math.floor(warningSteps/2)), respawnDelay)
		end)
	end

	-- Heartbeat kill / anti-idle / anti-outside (STARTS AFTER COUNTDOWN)
	local killConn
	killConn = RunService.Heartbeat:Connect(function()
		if PRE_ROUND then return end -- << IMPORTANT: no kills during countdown

		for _, plr in ipairs(matchPlayers) do
			if plr.Parent ~= Players then continue end
			if isElim(plr) then continue end
			if plr:GetAttribute("InRound") ~= true or plr:GetAttribute("AliveInRound") ~= true then continue end

			local hrp = getRoot(plr)
			if not hrp then continue end

			local tile = getStandingTile(hrp)
			if tile and tile:GetAttribute("IsKillTile") == true then
				eliminate(plr, "touched a kill tile!")
				continue
			end

			local now = os.clock()
			local lp = lastPos[plr]
			if (hrp.Position - lp).Magnitude >= IDLE_MOVE_EPS then
				lastPos[plr] = hrp.Position
				lastMoveTime[plr] = now
			end

			-- idle punish
			if (now - (lastMoveTime[plr] or now)) >= IDLE_TIME_LIMIT then
				lastMoveTime[plr] = now
				forceKillTileUnder(plr, currentWarningSteps, currentRespawnDelay)
				continue
			end

			-- outside radius punish
			local distFromCenter = (hrp.Position - arenaCenter.Position).Magnitude
			if distFromCenter > currentActiveRadius then
				if outsideSince[plr] == nil then
					outsideSince[plr] = now
				elseif (now - outsideSince[plr]) >= OUTSIDE_RADIUS_GRACE then
					outsideSince[plr] = now
					forceKillTileUnder(plr, currentWarningSteps, currentRespawnDelay)
				end
			else
				outsideSince[plr] = nil
			end
		end
	end)

	-- ===== ROUND LOOP =====
	for round = 1, ROUND_COUNT do
		currentRoundIndex = round
		currentActiveRadius = maxR * (RADIUS_FRACTION[round] or 0.5)
		currentWarningSteps = WARNING_STEPS_BY_ROUND[round] or 6
		currentRespawnDelay = TILE_RESPAWN_BY_ROUND[round] or 1.5

		local alive = alivePlayers(matchPlayers)
		if #alive == 1 then LAST_STANDING = alive[1] end
		if #alive <= 1 then break end

		local radius = currentActiveRadius
		local interval = STEP_INTERVAL[round] or 0.6
		local breaksPer = BREAKS_PER_STEP[round] or 3
		local warningSteps = currentWarningSteps
		local respawnDelay = currentRespawnDelay

		local candidates = buildCandidates(radius)
		if #candidates < 20 then
			candidates = buildCandidates(maxR)
		end

		local endTime = os.clock() + ROUND_TIME
		while os.clock() < endTime do
			alive = alivePlayers(matchPlayers)
			if #alive == 1 then LAST_STANDING = alive[1] end
			if #alive <= 1 then break end

			if os.clock() >= nextPay then
				for _, p in ipairs(alive) do
					earnedThisMatch[p] += SURVIVAL_COINS_PER_TICK
				end
				nextPay = os.clock() + SURVIVAL_COIN_INTERVAL
			end

			broadcast(("Round %d/%d | Alive: %d"):format(round, ROUND_COUNT, #alive))

			if #candidates < (breaksPer + 5) then
				candidates = buildCandidates(radius)
				if #candidates < 20 then
					candidates = buildCandidates(maxR)
				end
			end

			for _ = 1, breaksPer do
				local t = pickThreatTile(candidates, alive)
				if not t then break end
				task.spawn(function()
					warnKillThenRecover(t, warningSteps, respawnDelay)
				end)
			end

			task.wait(interval)
		end

		broadcast("Round " .. round .. " ended.")
		task.wait(BETWEEN_ROUNDS)
	end

	-- ===== SUDDEN DEATH =====
	local alive = alivePlayers(matchPlayers)
	if #alive == 1 then LAST_STANDING = alive[1] end

	if #alive > 1 then
		broadcast("SUDDEN DEATH!")
		currentActiveRadius = maxR * 0.7
		currentWarningSteps = SUDDEN_WARNING
		currentRespawnDelay = TILE_RESPAWN_SUDDEN

		local endSD = os.clock() + SUDDEN_DEATH_TIME
		while os.clock() < endSD do
			alive = alivePlayers(matchPlayers)
			if #alive == 1 then LAST_STANDING = alive[1] end
			if #alive <= 1 then break end

			broadcast(("SUDDEN DEATH | Alive: %d"):format(#alive))

			local candidates = buildCandidates(maxR * 0.7)
			if #candidates < 20 then candidates = buildCandidates(maxR) end

			for _ = 1, SUDDEN_BREAKS do
				local t = pickThreatTile(candidates, alive)
				if not t then break end
				task.spawn(function()
					warnKillThenRecover(t, SUDDEN_WARNING, TILE_RESPAWN_SUDDEN)
				end)
			end

			task.wait(SUDDEN_INTERVAL)
		end
	end

	alive = alivePlayers(matchPlayers)
	if #alive == 1 then
		local winner = alive[1]
		broadcast("Winner: " .. winner.Name)
		addWin(winner)
		earnedThisMatch[winner] += WIN_BONUS_COINS
	elseif #alive == 0 and LAST_STANDING and LAST_STANDING.Parent == Players then
		local winner = LAST_STANDING
		broadcast("Winner: " .. winner.Name)
		addWin(winner)
		earnedThisMatch[winner] += WIN_BONUS_COINS
	else
		broadcast("No winner.")
	end

	-- ===== END MATCH =====
	MATCH_RUNNING = false
	PRE_ROUND = false

	if joinConn then joinConn:Disconnect() end
	if killConn then killConn:Disconnect() end

	for _, plr in ipairs(matchPlayers) do
		local earned = earnedThisMatch[plr] or 0
		earningsEvent:FireClient(plr, earned)
		if earned > 0 then addCoinsToLeaderboard(plr, earned) end

		plr:SetAttribute("Ready", true)
		REVIVE_PENDING[plr] = nil
		REVIVE_USED_PASS[plr] = nil
		detachTokenWatcher(plr)

		setElim(plr, true)
		setInRound(plr, false)
		setAliveInRound(plr, false)

		reviveRemote:FireClient(plr, "Hide")
		teleportToLobby(plr)
	end

	-- reset spectators after match ends
	for _, plr in ipairs(Players:GetPlayers()) do
		if plr:GetAttribute("InRound") == true and plr:GetAttribute("AliveInRound") == false then
			setInRound(plr, false)
			setAliveInRound(plr, false)
			setElim(plr, true)
			reviveRemote:FireClient(plr, "Hide")
		end
	end

	matchState:FireAllClients(false)
	CURRENT_MATCH_PLAYERS = {}

	task.wait(3)
end

