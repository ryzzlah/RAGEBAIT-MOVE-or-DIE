-- StarterPlayerScripts/CoinHUD.client.lua
-- Bottom-left coin HUD (PC unchanged). Mobile moved up to avoid joystick.
-- Reads leaderstats.Coins (preferred) and falls back to player Attribute "Coins".

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local function mk(parent, className, props)
	local o = Instance.new(className)
	for k, v in pairs(props or {}) do
		o[k] = v
	end
	o.Parent = parent
	return o
end

-- Kill duplicates (so it doesn't randomly stack or hide)
local old = playerGui:FindFirstChild("CoinsHUD")
if old then old:Destroy() end

-- ✅ More reliable mobile detection:
-- If Touch is enabled, we treat it as mobile (even if Roblox claims a keyboard exists).
local isMobile = UserInputService.TouchEnabled

-- PC: keep EXACT old position
local PC_POS = UDim2.new(0, 18, 1, -35)

-- Mobile: move up so it doesn't clash with joystick (bottom-left)
-- Change -150 to move it up/down on mobile only.
local MOBILE_POS = UDim2.new(0, 18, 1, -245)

-- GUI
local gui = mk(playerGui, "ScreenGui", {
	Name = "CoinsHUD",
	ResetOnSpawn = false,
	IgnoreGuiInset = true,
	Enabled = true,
	DisplayOrder = 5, -- above most normal HUD, below popups
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
})

local frame = mk(gui, "Frame", {
	AnchorPoint = Vector2.new(0, 1),
	Position = isMobile and MOBILE_POS or PC_POS,
	Size = UDim2.new(0, 210, 0, 46), -- ✅ keep size same for PC; still fine on mobile
	BackgroundColor3 = Color3.fromRGB(18, 18, 18),
	BackgroundTransparency = 0.25,
	BorderSizePixel = 0,
})

mk(frame, "UICorner", { CornerRadius = UDim.new(0, 12) })
mk(frame, "UIStroke", { Thickness = 1, Color = Color3.fromRGB(60, 60, 60), Transparency = 0 })

local label = mk(frame, "TextLabel", {
	Size = UDim2.new(1, -16, 1, 0),
	Position = UDim2.new(0, 8, 0, 0),
	BackgroundTransparency = 1,
	TextXAlignment = Enum.TextXAlignment.Left,
	Font = Enum.Font.GothamBold,
	TextSize = isMobile and 26 or 30,
	TextColor3 = Color3.fromRGB(255, 255, 255),
	Text = "💰 Coins: ...",
})

-- ---------- Data hookup ----------
local coinsValue -- IntValue (leaderstats)
local connections = {}

local function disconnectAll()
	for _, c in ipairs(connections) do
		if c then c:Disconnect() end
	end
	table.clear(connections)
end

local function setText(n)
	n = tonumber(n) or 0
	label.Text = ("💰 Coins: %d"):format(n)
end

local function bindToCoinsIntValue(intValue)
	coinsValue = intValue
	setText(coinsValue.Value)

	table.insert(connections, coinsValue.Changed:Connect(function()
		setText(coinsValue.Value)
	end))
end

local function tryBind()
	disconnectAll()

	-- Prefer leaderstats.Coins
	local leaderstats = player:FindFirstChild("leaderstats")
	if leaderstats then
		local c = leaderstats:FindFirstChild("Coins")
		if c and c:IsA("IntValue") then
			bindToCoinsIntValue(c)
			return
		end
	end

	-- Fallback: player Attribute "Coins"
	setText(player:GetAttribute("Coins") or 0)
	table.insert(connections, player:GetAttributeChangedSignal("Coins"):Connect(function()
		setText(player:GetAttribute("Coins") or 0)
	end))
end

-- Rebind whenever leaderstats appears / changes
table.insert(connections, player.ChildAdded:Connect(function(child)
	if child.Name == "leaderstats" then
		task.wait(0.1)
		tryBind()
	end
end))

-- Also handle leaderstats Coins being created later
local function watchLeaderstats()
	local leaderstats = player:FindFirstChild("leaderstats")
	if not leaderstats then return end

	table.insert(connections, leaderstats.ChildAdded:Connect(function(child)
		if child.Name == "Coins" and child:IsA("IntValue") then
			tryBind()
		end
	end))
end

-- Initial bind (with a bit of patience)
task.defer(function()
	tryBind()

	-- If leaderstats loads shortly after, catch it
	for _ = 1, 30 do
		local ls = player:FindFirstChild("leaderstats")
		if ls and ls:FindFirstChild("Coins") then
			tryBind()
			watchLeaderstats()
			return
		end
		task.wait(0.1)
	end

	-- still no leaderstats? fine, attribute fallback stays
	watchLeaderstats()
end)

