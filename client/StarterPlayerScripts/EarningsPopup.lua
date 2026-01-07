-- StarterPlayerScripts/EarningsPopup (LocalScript)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local player = Players.LocalPlayer

local event = ReplicatedStorage:FindFirstChild("MatchEarnings")
if not event then
	warn("[EarningsPopup] MatchEarnings missing")
	return
end


local gui = Instance.new("ScreenGui")
gui.Name = "EarningsGui"
gui.ResetOnSpawn = false
gui.Parent = player:WaitForChild("PlayerGui")

local frame = Instance.new("Frame")
frame.Size = UDim2.new(0, 320, 0, 90)
frame.Position = UDim2.new(0.5, -160, 0.2, 0)
frame.BackgroundTransparency = 0.2
frame.Visible = false
frame.Parent = gui

local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0, 10)
corner.Parent = frame

local label = Instance.new("TextLabel")
label.Size = UDim2.new(1, -20, 1, -20)
label.Position = UDim2.new(0, 10, 0, 10)
label.BackgroundTransparency = 1
label.TextScaled = true
label.Font = Enum.Font.GothamBold
label.TextColor3 = Color3.fromRGB(255,255,255)
label.Text = ""
label.Parent = frame

event.OnClientEvent:Connect(function(amount)
	frame.Visible = true
	label.Text = "Match Earnings: +" .. tostring(amount) .. " Coins"
	task.delay(3, function()
		frame.Visible = false
	end)
end)
