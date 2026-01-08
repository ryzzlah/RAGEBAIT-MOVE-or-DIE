-- StarterPlayerScripts/SpectateClient.lua
-- FIXED:
-- ✅ Auto-spectate if you join mid-match (even if you're not InRound)
-- ✅ Auto-spectate on elimination
-- ✅ Hides ALL other ScreenGuis while spectating (except StatusUI + this SpectateGui)
-- ✅ Exit restores UI properly
-- ✅ Match end restores UI + stops spectating

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local matchState = ReplicatedStorage:WaitForChild("MatchState") -- RemoteEvent(bool inMatch)
local spectateEvent = ReplicatedStorage:WaitForChild("SpectateEvent") -- RemoteEvent("RequestList" / "SpectateUserId", etc)

local inMatch = false
local isSpectating = false
local currentTargetUserId = nil
local spectateOptOut = false

-- ========= UI helpers =========
local function mk(parent, class, props)
	local o = Instance.new(class)
	for k,v in pairs(props or {}) do
		o[k] = v
	end
	o.Parent = parent
	return o
end

-- Kill duplicates
local old = playerGui:FindFirstChild("SpectateGui")
if old then old:Destroy() end

local gui = mk(playerGui, "ScreenGui", {
	Name = "SpectateGui",
	ResetOnSpawn = false,
	IgnoreGuiInset = true,
	Enabled = false,
	DisplayOrder = 50, -- above normal UI, below hardcore popups
})

-- Put it where ReadyUI usually sits (bottom center)
local panel = mk(gui, "Frame", {
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 1, -24),
	Size = UDim2.new(0, 520, 0, 58),
	BackgroundColor3 = Color3.fromRGB(18,18,18),
	BackgroundTransparency = 0.15,
	BorderSizePixel = 0
})
mk(panel, "UICorner", {CornerRadius = UDim.new(0, 14)})
mk(panel, "UIStroke", {Thickness = 1, Color = Color3.fromRGB(60,60,60), Transparency = 0})

local title = mk(panel, "TextLabel", {
	BackgroundTransparency = 1,
	Size = UDim2.new(1, -170, 1, 0),
	Position = UDim2.new(0, 14, 0, 0),
	TextXAlignment = Enum.TextXAlignment.Left,
	Font = Enum.Font.GothamBold,
	TextSize = 18,
	TextColor3 = Color3.fromRGB(255,255,255),
	Text = "SPECTATING..."
})

local prevBtn = mk(panel, "TextButton", {
	AnchorPoint = Vector2.new(1, 0.5),
	Position = UDim2.new(1, -146, 0.5, 0),
	Size = UDim2.new(0, 56, 0, 38),
	Text = "<",
	Font = Enum.Font.GothamBold,
	TextSize = 22,
	TextColor3 = Color3.fromRGB(255,255,255),
	BackgroundColor3 = Color3.fromRGB(35,35,35),
	AutoButtonColor = true
})
mk(prevBtn, "UICorner", {CornerRadius = UDim.new(0, 10)})

local nextBtn = mk(panel, "TextButton", {
	AnchorPoint = Vector2.new(1, 0.5),
	Position = UDim2.new(1, -84, 0.5, 0),
	Size = UDim2.new(0, 56, 0, 38),
	Text = ">",
	Font = Enum.Font.GothamBold,
	TextSize = 22,
	TextColor3 = Color3.fromRGB(255,255,255),
	BackgroundColor3 = Color3.fromRGB(35,35,35),
	AutoButtonColor = true
})
mk(nextBtn, "UICorner", {CornerRadius = UDim.new(0, 10)})

local exitBtn = mk(panel, "TextButton", {
	AnchorPoint = Vector2.new(1, 0.5),
	Position = UDim2.new(1, -16, 0.5, 0),
	Size = UDim2.new(0, 56, 0, 38),
	Text = "X",
	Font = Enum.Font.GothamBold,
	TextSize = 20,
	TextColor3 = Color3.fromRGB(255,255,255),
	BackgroundColor3 = Color3.fromRGB(235,65,65),
	AutoButtonColor = true
})
mk(exitBtn, "UICorner", {CornerRadius = UDim.new(0, 10)})

-- ========= Hide other UI while spectating =========
local savedGuiEnabled = {}

local function shouldKeepGui(screenGui: ScreenGui)
	if screenGui == gui then return true end
	if screenGui.Name == "StatusGui" then return true end -- keep Status UI visible
	return false
end

local function setOtherUIHidden(hidden: boolean)
	if hidden then
		table.clear(savedGuiEnabled)
		for _, child in ipairs(playerGui:GetChildren()) do
			if child:IsA("ScreenGui") and not shouldKeepGui(child) then
				savedGuiEnabled[child] = child.Enabled
				child.Enabled = false
			end
		end
	else
		for g, was in pairs(savedGuiEnabled) do
			if g and g.Parent == playerGui then
				g.Enabled = was
			end
		end
		table.clear(savedGuiEnabled)
	end
end

-- ========= spectate camera =========
local function setCameraToUserId(userId: number?)
	local cam = workspace.CurrentCamera
	if not cam then return end

	if not userId then
		currentTargetUserId = nil
		title.Text = "SPECTATING..."
		cam.CameraSubject = (player.Character and player.Character:FindFirstChildWhichIsA("Humanoid")) or nil
		cam.CameraType = Enum.CameraType.Custom
		return
	end

	local targetPlr = Players:GetPlayerByUserId(userId)
	if not targetPlr then return end
	local char = targetPlr.Character
	if not char then return end
	local hum = char:FindFirstChildWhichIsA("Humanoid")
	if not hum then return end

	currentTargetUserId = userId
	title.Text = ("SPECTATING: %s"):format(targetPlr.Name)
	cam.CameraSubject = hum
	cam.CameraType = Enum.CameraType.Custom
end

-- ========= state logic =========
local function shouldSpectateNow()
	if not inMatch then return false end
	if spectateOptOut then return false end

	local inRoundAttr = player:GetAttribute("InRound") == true
	local aliveAttr = player:GetAttribute("AliveInRound") == true

	-- If match is running AND you're not actively alive in the round => spectate
	-- This includes:
	-- - eliminated players (alive=false)
	-- - mid-round joiners sitting in lobby (inRound=false)
	if (not inRoundAttr) or (not aliveAttr) then
		return true
	end
	return false
end

local function enterSpectate()
	if isSpectating then return end
	isSpectating = true
	spectateOptOut = false
	gui.Enabled = true
	setOtherUIHidden(true)
	spectateEvent:FireServer("RequestList")
end

local function exitSpectate()
	if not isSpectating then return end
	isSpectating = false
	gui.Enabled = false
	setOtherUIHidden(false)
	setCameraToUserId(nil)
end

local function refreshState()
	if shouldSpectateNow() then
		enterSpectate()
	else
		exitSpectate()
	end
end

-- Buttons
prevBtn.MouseButton1Click:Connect(function()
	if not isSpectating then return end
	spectateEvent:FireServer("Prev")
end)

nextBtn.MouseButton1Click:Connect(function()
	if not isSpectating then return end
	spectateEvent:FireServer("Next")
end)

exitBtn.MouseButton1Click:Connect(function()
	-- This is a CLIENT exit. You still might be dead, so we do:
	-- - restore UI (so they can chill)
	-- - camera back to self
	-- - keep spectate UI closed until they press next/prev again
	spectateOptOut = true
	exitSpectate()
end)

-- Server pushes target
spectateEvent.OnClientEvent:Connect(function(kind, payload)
	if kind == "SetTarget" then
		if typeof(payload) == "number" then
			setCameraToUserId(payload)
		else
			setCameraToUserId(nil)
		end
	elseif kind == "NoTargets" then
		setCameraToUserId(nil)
		title.Text = "SPECTATING: (no one alive)"
	end
end)

-- Match start/end
matchState.OnClientEvent:Connect(function(state)
	inMatch = state == true
	if not inMatch then
		-- Match ended: hard reset spectate
		spectateOptOut = false
		exitSpectate()
	else
		refreshState()
	end
end)

-- Attribute changes (elimination, join mid-round, etc)
player:GetAttributeChangedSignal("InRound"):Connect(refreshState)
player:GetAttributeChangedSignal("AliveInRound"):Connect(function()
	if player:GetAttribute("AliveInRound") == true then
		spectateOptOut = false
	end
	refreshState()
end)

-- If they spawn in while match is already running, this catches it
task.defer(function()
	refreshState()
end)
