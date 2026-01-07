-- StarterPlayerScripts/ReadyUI (clean + safe, won't mess with Sprint UI)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local readyEvent = ReplicatedStorage:WaitForChild("ReadyToggle")
local matchState = ReplicatedStorage:WaitForChild("MatchState")

local function mk(parent, class, props)
	local o = Instance.new(class)
	for k, v in pairs(props or {}) do
		o[k] = v
	end
	o.Parent = parent
	return o
end

local old = playerGui:FindFirstChild("ReadyGui")
if old then old:Destroy() end

local gui = mk(playerGui, "ScreenGui", {
	Name = "ReadyGui",
	ResetOnSpawn = false,
	IgnoreGuiInset = true,
	Enabled = true,
	DisplayOrder = -10,
})

local isMobile = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled

local BTN_W = isMobile and 180 or 220
local BTN_H = isMobile and 44 or 56
local BOTTOM_PAD = 24

local btn = mk(gui, "TextButton", {
	Name = "ReadyButton",
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 1, -BOTTOM_PAD),
	Size = UDim2.new(0, BTN_W, 0, BTN_H),

	BackgroundColor3 = Color3.fromRGB(25, 25, 25),
	TextColor3 = Color3.fromRGB(255, 255, 255),

	Font = Enum.Font.GothamBold,
	Text = "...",

	TextScaled = true,
	TextWrapped = false, -- IMPORTANT
	AutoButtonColor = true,
})

mk(btn, "UICorner", { CornerRadius = UDim.new(0, 14) })
local stroke = mk(btn, "UIStroke", {
	Thickness = 2,
	Color = Color3.fromRGB(235, 65, 65),
	Transparency = 0,
})

-- THIS is the magic
mk(btn, "UITextSizeConstraint", {
	MinTextSize = isMobile and 24 or 30,
	MaxTextSize = isMobile and 28 or 34,
})

mk(btn, "UIPadding", {
	PaddingLeft = UDim.new(0, 10),
	PaddingRight = UDim.new(0, 10),
	PaddingTop = UDim.new(0, 6),
	PaddingBottom = UDim.new(0, 6),
})

local ready = true

local function refresh()
	btn.Text = ready and "UNREADY" or "READY"
	stroke.Color = ready
		and Color3.fromRGB(235, 65, 65)
		or Color3.fromRGB(85, 200, 120)
end

local function push()
	refresh()
	readyEvent:FireServer(ready)
end

push()

player.CharacterAdded:Connect(function()
	task.wait(0.2)
	ready = true
	push()
end)

btn.MouseButton1Click:Connect(function()
	ready = not ready
	push()
end)

matchState.OnClientEvent:Connect(function(inMatch)
	gui.Enabled = not inMatch
	btn.Active = not inMatch
end)
