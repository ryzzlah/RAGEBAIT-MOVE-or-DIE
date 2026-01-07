-- StarterPlayerScripts/StatusUI (LocalScript)
-- FIXED: never creates RemoteEvents on client (that breaks everything)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local isMobile = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled

-- UI
local gui = Instance.new("ScreenGui")
gui.Name = "RoundStatusUI"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = isMobile
gui.Parent = player:WaitForChild("PlayerGui")

local label = Instance.new("TextLabel")
label.Name = "StatusLabel"
label.AnchorPoint = Vector2.new(0.5, 0)
label.Position = UDim2.new(0.5, 0, 0, 18)
label.Size = UDim2.new(1, 0, 0, 60)

label.BackgroundTransparency = 0.35
label.BackgroundColor3 = Color3.fromRGB(0, 0, 0)

label.TextScaled = true
label.Font = Enum.Font.GothamBold
label.TextColor3 = Color3.fromRGB(255, 255, 255)
label.TextStrokeTransparency = 0.6
label.Text = "Status UI loaded... (waiting for server)"
label.Parent = gui

-- Mobile styling (black text + white outline)
if isMobile then
	label.Size = UDim2.new(0.92, 0, 0, 36)
	label.Position = UDim2.new(0.5, 0, 0.025, 6)

	label.BackgroundTransparency = 1
	label.TextScaled = false
	label.TextSize = 25

	label.TextColor3 = Color3.fromRGB(0, 0, 0) -- black text
	label.TextStrokeColor3 = Color3.fromRGB(255, 255, 255) -- white outline
	label.TextStrokeTransparency = 0

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = label
end

-- Mobile auto-hide
local hideToken = 0
local function mobileAutoHide()
	if not isMobile then return end
	hideToken += 1
	local myToken = hideToken
	label.Visible = true
	task.delay(3, function()
		if hideToken == myToken then
			label.Visible = false
		end
	end)
end

-- IMPORTANT: wait for the SERVER to create the RemoteEvent
local event = ReplicatedStorage:WaitForChild("RoundStatus")

label.Text = "Connected to server status."
if isMobile then mobileAutoHide() end

event.OnClientEvent:Connect(function(text)
	label.Visible = true
	label.Text = tostring(text)
	mobileAutoHide()
end)
