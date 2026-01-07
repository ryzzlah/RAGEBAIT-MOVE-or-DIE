-- SprintClient (LocalScript) - StarterPlayerScripts
-- PC: Hold Shift to sprint (ContextActionService)
-- Mobile: Uses EXISTING ImageButton named "SprintButton" inside PlayerGui > MobileControls
-- Sprint for 2s max, recovers in 5s
-- UI: bottom-center stamina bar + ⚡ icon
-- Adds camera FOV boost while sprinting (stable)

local Players = game:GetService("Players")
local UIS = game:GetService("UserInputService")
local CAS = game:GetService("ContextActionService")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- ===== TUNABLES =====
local BASE_SPEED_FALLBACK = 16
local SPRINT_SPEED = 28
local SPRINT_DURATION = 2.0
local RECOVER_TIME = 5.0

local UI_Y_OFFSET = 90

local FOV_BOOST = 10
local FOV_TWEEN = 0.15

local START_SPRINT_THRESHOLD = 0.15
local STOP_SPRINT_THRESHOLD  = 0.02

-- ===== MOBILE BUTTON LAYOUT (YOUR EXISTING BUTTON) =====
-- Goal: near Jump button (bottom-right), slightly above + a bit left.
-- Tune these 2 numbers only.
local MOBILE_OFFSET_X = -90     -- more negative = further left
local MOBILE_OFFSET_Y = -90   -- more negative = higher up

-- Size behavior across devices
local MOBILE_TARGET_SIZE = 62    -- your "normal" size
local MOBILE_MIN_SIZE = 60
local MOBILE_MAX_SIZE = 90

-- ===== STATE =====
local character, humanoid
local stamina = 1.0
local wantsSprint = false
local isSprinting = false
local baseSpeed = BASE_SPEED_FALLBACK
local externalSpeedWatch = nil

-- ===== FOV state =====
local camera = workspace.CurrentCamera
local baseFov = 70
local tweenIn, tweenOut
local lastSprintVisual = false
local lastFovToggle = 0
local FOV_TOGGLE_COOLDOWN = 0.08

local function isMobile()
	return UIS.TouchEnabled and not UIS.KeyboardEnabled
end

local function rebuildFovTweens()
	camera = workspace.CurrentCamera
	if not camera then return end

	baseFov = math.clamp(camera.FieldOfView, 60, 90)
	camera.FieldOfView = baseFov

	tweenIn = TweenService:Create(
		camera,
		TweenInfo.new(FOV_TWEEN, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ FieldOfView = baseFov + FOV_BOOST }
	)

	tweenOut = TweenService:Create(
		camera,
		TweenInfo.new(FOV_TWEEN, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ FieldOfView = baseFov }
	)
end

rebuildFovTweens()
workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
	task.defer(rebuildFovTweens)
end)

-- ===== UI BUILD (stamina bar) =====
local function makeUI()
	local gui = Instance.new("ScreenGui")
	gui.Name = "SprintUI"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.Parent = playerGui

	local safe = Instance.new("Frame")
	safe.Name = "Safe"
	safe.BackgroundTransparency = 1
	safe.Size = UDim2.new(1, 0, 1, 0)
	safe.Parent = gui

	local container = Instance.new("Frame")
	container.Name = "SprintContainer"
	container.AnchorPoint = Vector2.new(0.5, 1)
	container.Position = UDim2.new(0.5, 0, 1, -UI_Y_OFFSET)
	container.Size = UDim2.new(0, 260, 0, 26)
	container.BackgroundTransparency = 1
	container.Parent = safe

	local bg = Instance.new("Frame")
	bg.Name = "BarBG"
	bg.Size = UDim2.new(1, 0, 1, 0)
	bg.BackgroundColor3 = Color3.fromRGB(20, 35, 55)
	bg.BackgroundTransparency = 0.15
	bg.BorderSizePixel = 0
	bg.Parent = container

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = bg

	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 1
	stroke.Transparency = 0.35
	stroke.Color = Color3.fromRGB(120, 170, 255)
	stroke.Parent = bg

	local icon = Instance.new("TextLabel")
	icon.Name = "Icon"
	icon.BackgroundTransparency = 1
	icon.Size = UDim2.new(0, 30, 1, 0)
	icon.Position = UDim2.new(0, 6, 0, 0)
	icon.Font = Enum.Font.GothamBold
	icon.Text = "⚡"
	icon.TextScaled = true
	icon.TextColor3 = Color3.fromRGB(160, 210, 255)
	icon.Parent = bg

	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.AnchorPoint = Vector2.new(0, 0.5)
	fill.Position = UDim2.new(0, 40, 0.5, 0)
	fill.Size = UDim2.new(1, -48, 0, 14)
	fill.BackgroundColor3 = Color3.fromRGB(70, 140, 255)
	fill.BorderSizePixel = 0
	fill.Parent = bg

	local fillCorner = Instance.new("UICorner")
	fillCorner.CornerRadius = UDim.new(0, 8)
	fillCorner.Parent = fill

	local amt = Instance.new("Frame")
	amt.Name = "Amount"
	amt.Size = UDim2.new(1, 0, 1, 0)
	amt.BackgroundColor3 = Color3.fromRGB(90, 170, 255)
	amt.BorderSizePixel = 0
	amt.Parent = fill

	local amtCorner = Instance.new("UICorner")
	amtCorner.CornerRadius = UDim.new(0, 8)
	amtCorner.Parent = amt

	return gui, amt, icon
end

local sprintGui, staminaFill, iconLabel = makeUI()

local function setStaminaUI(v)
	v = math.clamp(v, 0, 1)
	staminaFill.Size = UDim2.new(v, 0, 1, 0)

	if v <= 0.02 then
		iconLabel.TextColor3 = Color3.fromRGB(90, 110, 140)
	else
		iconLabel.TextColor3 = Color3.fromRGB(160, 210, 255)
	end
end

setStaminaUI(stamina)

-- ===== SPEED HANDLING =====
local function applySpeed()
	if not humanoid then return end
	if isSprinting then
		humanoid.WalkSpeed = SPRINT_SPEED
	else
		humanoid.WalkSpeed = baseSpeed
	end
end

local function attachCharacter(char)
	character = char
	humanoid = char:WaitForChild("Humanoid", 5)
	if not humanoid then return end

	baseSpeed = humanoid.WalkSpeed
	if baseSpeed <= 0 then baseSpeed = BASE_SPEED_FALLBACK end

	if externalSpeedWatch then externalSpeedWatch:Disconnect() end
	externalSpeedWatch = humanoid:GetPropertyChangedSignal("WalkSpeed"):Connect(function()
		if humanoid and not isSprinting then
			baseSpeed = humanoid.WalkSpeed
			if baseSpeed <= 0 then baseSpeed = BASE_SPEED_FALLBACK end
		end
	end)

	applySpeed()
end

player.CharacterAdded:Connect(attachCharacter)
if player.Character then attachCharacter(player.Character) end

-- ===== INPUT (PC SHIFT via CAS) =====
local ACTION_NAME = "SprintAction"

local function setSprintIntent(on)
	wantsSprint = on and stamina > 0.001
end

local function sprintAction(_, inputState, _)
	if inputState == Enum.UserInputState.Begin then
		setSprintIntent(true)
	elseif inputState == Enum.UserInputState.End or inputState == Enum.UserInputState.Cancel then
		setSprintIntent(false)
	end
	return Enum.ContextActionResult.Sink
end

CAS:BindAction(ACTION_NAME, sprintAction, true, Enum.KeyCode.LeftShift, Enum.KeyCode.RightShift)

-- Hide CAS mobile button (we're using your UI button on mobile)
pcall(function()
	local casBtn = CAS:GetButton(ACTION_NAME)
	if casBtn then
		casBtn.Visible = false
	end
end)

-- ===== MOBILE: hook YOUR button =====
local mobileBtnConnBegan, mobileBtnConnEnded
local mobileBtn -- ImageButton

local function findSprintButton()
	local mobileControls = playerGui:FindFirstChild("MobileControls")
	if not mobileControls then return nil end

	for _, d in ipairs(mobileControls:GetDescendants()) do
		if d:IsA("ImageButton") and d.Name == "SprintButton" then
			return d
		end
	end
	return nil
end

local function styleAndPlaceMobileButton(btn: ImageButton)
	-- Only show it on mobile
	if not isMobile() then
		btn.Visible = false
		return
	end

	btn.Visible = true
	btn.Active = true
	btn.AutoButtonColor = true

	btn.AnchorPoint = Vector2.new(1, 1)
	btn.Position = UDim2.new(1, MOBILE_OFFSET_X, 1, MOBILE_OFFSET_Y)
	btn.Size = UDim2.new(0, MOBILE_TARGET_SIZE, 0, MOBILE_TARGET_SIZE)

	local sc = btn:FindFirstChildOfClass("UISizeConstraint")
	if not sc then
		sc = Instance.new("UISizeConstraint")
		sc.Parent = btn
	end
	sc.MinSize = Vector2.new(MOBILE_MIN_SIZE, MOBILE_MIN_SIZE)
	sc.MaxSize = Vector2.new(MOBILE_MAX_SIZE, MOBILE_MAX_SIZE)
end

local function disconnectMobileBtn()
	if mobileBtnConnBegan then mobileBtnConnBegan:Disconnect() mobileBtnConnBegan = nil end
	if mobileBtnConnEnded then mobileBtnConnEnded:Disconnect() mobileBtnConnEnded = nil end
end

local function hookMobileButton()
	mobileBtn = findSprintButton()
	if not mobileBtn then return end

	styleAndPlaceMobileButton(mobileBtn)
	disconnectMobileBtn()

	if not isMobile() then
		return
	end

	-- HOLD to sprint
	mobileBtnConnBegan = mobileBtn.InputBegan:Connect(function(input)
		if input.UserInputType ~= Enum.UserInputType.Touch then return end
		if stamina <= START_SPRINT_THRESHOLD then return end
		wantsSprint = true
	end)

	mobileBtnConnEnded = mobileBtn.InputEnded:Connect(function(input)
		if input.UserInputType ~= Enum.UserInputType.Touch then return end
		wantsSprint = false
	end)
end

-- Try now, and also re-try if UI loads late
hookMobileButton()
playerGui.ChildAdded:Connect(function(child)
	if child.Name == "MobileControls" then
		task.defer(hookMobileButton)
	end
end)

-- ===== MAIN LOOP =====
RunService.RenderStepped:Connect(function(dt)
	if not humanoid or humanoid.Health <= 0 then
		if isSprinting then
			isSprinting = false
			if tweenIn then tweenIn:Cancel() end
			if tweenOut then tweenOut:Play() end
			lastSprintVisual = false
		end
		return
	end

	-- Keep mobile hook alive (UI reload/device change)
	if isMobile() then
		if not mobileBtn or not mobileBtn.Parent then
			hookMobileButton()
		end
	else
		-- if on PC, force-hide mobile sprint button if it exists
		local btn = mobileBtn or findSprintButton()
		if btn then btn.Visible = false end
	end

	-- Hysteresis
	local canSprint
	if isSprinting then
		canSprint = wantsSprint and stamina > STOP_SPRINT_THRESHOLD
	else
		canSprint = wantsSprint and stamina > START_SPRINT_THRESHOLD
	end

	if canSprint then
		isSprinting = true
		stamina -= (dt / SPRINT_DURATION)
	else
		isSprinting = false
		stamina += (dt / RECOVER_TIME)
	end

	stamina = math.clamp(stamina, 0, 1)
	setStaminaUI(stamina)
	applySpeed()

	-- Camera FOV feel
	if isSprinting ~= lastSprintVisual then
		local now = os.clock()
		if (now - lastFovToggle) >= FOV_TOGGLE_COOLDOWN then
			lastFovToggle = now
			lastSprintVisual = isSprinting

			if isSprinting then
				if tweenOut then tweenOut:Cancel() end
				if tweenIn then tweenIn:Play() end
			else
				if tweenIn then tweenIn:Cancel() end
				if tweenOut then tweenOut:Play() end
			end
		end
	end
end)

