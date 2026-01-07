-- StarterPlayerScripts/SpectateUI.client.lua
-- Fixed: reliable attribute watching + Exit returns camera only (UI stays)
-- Keeps your same UI style/placement.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local camera = workspace.CurrentCamera

local SpectateEvent = ReplicatedStorage:WaitForChild("SpectateEvent")
local MatchState = ReplicatedStorage:WaitForChild("MatchState")

-- ===== helpers =====
local function mk(parent, class, props)
	local o = Instance.new(class)
	for k, v in pairs(props or {}) do
		o[k] = v
	end
	o.Parent = parent
	return o
end

local function getHum(plr: Player)
	local ch = plr.Character
	return ch and ch:FindFirstChildOfClass("Humanoid")
end

local function aliveTargetListFromUserIds(ids)
	local list = {}
	for _, uid in ipairs(ids) do
		local p = Players:GetPlayerByUserId(uid)
		if p and p ~= player then
			table.insert(list, p)
		end
	end
	return list
end

local function isDeadInRound()
	return player:GetAttribute("InRound") == true and player:GetAttribute("AliveInRound") == false
end

local function setCameraToSelf()
	local hum = getHum(player)
	if hum then
		camera.CameraType = Enum.CameraType.Custom
		camera.CameraSubject = hum
	end
end

-- ===== UI =====
local old = playerGui:FindFirstChild("SpectateGui")
if old then old:Destroy() end

local gui = mk(playerGui, "ScreenGui", {
	Name = "SpectateGui",
	ResetOnSpawn = false,
	IgnoreGuiInset = true,
	Enabled = false,
	DisplayOrder = -10,
})

local BOTTOM_PAD = 24
local W, H = 480, 56

local frame = mk(gui, "Frame", {
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 1, -BOTTOM_PAD),
	Size = UDim2.new(0, W, 0, H),
	BackgroundColor3 = Color3.fromRGB(25,25,25),
	BorderSizePixel = 0,
})
mk(frame, "UICorner", { CornerRadius = UDim.new(0, 14) })
mk(frame, "UIStroke", { Thickness = 2, Color = Color3.fromRGB(65,190,235), Transparency = 0 })

local nameLbl = mk(frame, "TextLabel", {
	BackgroundTransparency = 1,
	Position = UDim2.new(0, 12, 0, 0),
	Size = UDim2.new(1, -160, 1, 0),
	Font = Enum.Font.GothamBold,
	TextSize = 22,
	TextColor3 = Color3.fromRGB(255,255,255),
	TextXAlignment = Enum.TextXAlignment.Left,
	Text = "Spectate",
})

local function makeBtn(txt, x)
	local b = mk(frame, "TextButton", {
		Size = UDim2.new(0, 44, 0, 40),
		Position = UDim2.new(0, x, 0.5, -20),
		BackgroundColor3 = Color3.fromRGB(40,40,46),
		Text = txt,
		Font = Enum.Font.GothamBold,
		TextSize = 18,
		TextColor3 = Color3.fromRGB(255,255,255),
		AutoButtonColor = true,
	})
	mk(b, "UICorner", { CornerRadius = UDim.new(0, 10) })
	return b
end

local prevBtn = makeBtn("<", W - 140)
local nextBtn = makeBtn(">", W - 90)
local exitBtn = makeBtn("X", W - 44)
exitBtn.BackgroundColor3 = Color3.fromRGB(200,60,60)

-- ===== state =====
local inMatch = false
local spectating = false
local targets = {} -- Player list
local idx = 1
local camConn: RBXScriptConnection? = nil
local requestToken = 0

local function disconnectTargetConn()
	if camConn then
		camConn:Disconnect()
		camConn = nil
	end
end

local function setUiEnabledForDead()
	-- UI should be visible when match is running AND player is dead-in-round.
	gui.Enabled = (inMatch and isDeadInRound())
	if not gui.Enabled then
		-- If we are not eligible, fully stop spectate and go back to self.
		spectating = false
		disconnectTargetConn()
		setCameraToSelf()
	end
end

local function applyCameraToTarget(t: Player)
	if not t then return end
	local hum = getHum(t)
	if not hum then return end

	spectating = true
	camera.CameraType = Enum.CameraType.Custom
	camera.CameraSubject = hum
	nameLbl.Text = ("Spectating: %s"):format(t.Name)

	-- keep camera locked even if target respawns
	disconnectTargetConn()
	camConn = t.CharacterAdded:Connect(function()
		task.wait(0.1)
		if spectating then
			local h = getHum(t)
			if h then camera.CameraSubject = h end
		end
	end)
end

local function clampIndex()
	if #targets == 0 then
		idx = 1
		return
	end
	if idx < 1 then idx = #targets end
	if idx > #targets then idx = 1 end
end

local function spectateCurrent()
	if #targets == 0 then
		spectating = false
		disconnectTargetConn()
		setCameraToSelf()
		nameLbl.Text = "No one alive"
		return
	end

	clampIndex()
	local t = targets[idx]
	if not t or t.Parent ~= Players then
		-- target left, ask again
		SpectateEvent:FireServer("GetTargets")
		return
	end

	applyCameraToTarget(t)
end

local function refreshTargets()
	requestToken += 1
	local myTok = requestToken

	SpectateEvent:FireServer("GetTargets")

	-- small fallback message if server returns empty
	task.delay(1.2, function()
		if requestToken ~= myTok then return end
		if gui.Enabled and (#targets == 0) then
			nameLbl.Text = "No one alive"
		end
	end)
end

local function ensureSpectateMode()
	-- Called whenever match state / alive state changes
	setUiEnabledForDead()
	if not gui.Enabled then return end

	-- When you first become dead, show UI and fetch targets.
	-- Do NOT force spectating. Let Exit keep UI visible.
	if not spectating then
		nameLbl.Text = "Spectate (tap < or >)"
		setCameraToSelf()
	end

	refreshTargets()
end

-- ===== remote responses =====
SpectateEvent.OnClientEvent:Connect(function(kind, payload)
	if kind ~= "Targets" then return end
	if not gui.Enabled then return end

	local ids = (typeof(payload) == "table") and payload or {}
	targets = aliveTargetListFromUserIds(ids)

	-- If we are actively spectating, keep it updated.
	if spectating then
		if #targets == 0 then
			spectating = false
			disconnectTargetConn()
			setCameraToSelf()
			nameLbl.Text = "No one alive"
			return
		end
		clampIndex()
		spectateCurrent()
	end
end)

-- ===== buttons =====
local function startOrCycle(delta)
	if not gui.Enabled then return end
	if #targets == 0 then
		refreshTargets()
		return
	end
	idx += delta
	clampIndex()
	spectateCurrent()
end

prevBtn.MouseButton1Click:Connect(function()
	startOrCycle(-1)
end)

nextBtn.MouseButton1Click:Connect(function()
	startOrCycle(1)
end)

exitBtn.MouseButton1Click:Connect(function()
	-- Per your instruction:
	-- Exit ONLY switches camera back to your character, UI stays.
	spectating = false
	disconnectTargetConn()
	setCameraToSelf()
	nameLbl.Text = "Spectate (tap < or >)"
end)

-- ===== match state =====
MatchState.OnClientEvent:Connect(function(v)
	inMatch = (v == true)
	ensureSpectateMode()
end)

-- ===== proper attribute watchers (your old code was wrong) =====
player:GetAttributeChangedSignal("AliveInRound"):Connect(function()
	ensureSpectateMode()
end)

player:GetAttributeChangedSignal("InRound"):Connect(function()
	ensureSpectateMode()
end)

-- Handle respawns so self-camera doesn't get stuck on nil humanoid
player.CharacterAdded:Connect(function()
	task.wait(0.1)
	if not spectating then
		setCameraToSelf()
	end
end)

-- initial
ensureSpectateMode()
