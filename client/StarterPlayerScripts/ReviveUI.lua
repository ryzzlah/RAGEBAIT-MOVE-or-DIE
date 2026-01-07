-- StarterPlayerScripts/ReviveUI.client.lua
-- Revive popup: shows REVIVE if available, otherwise BUY REVIVE.
-- Clicking outside does nothing. Spectate UI won’t be affected by this script.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MarketplaceService = game:GetService("MarketplaceService")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local reviveRemote = ReplicatedStorage:WaitForChild("ReviveRemote")

local isMobile = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled

local function mk(parent, class, props)
	local o = Instance.new(class)
	for k,v in pairs(props or {}) do o[k] = v end
	o.Parent = parent
	return o
end

local old = playerGui:FindFirstChild("ReviveGui")
if old then old:Destroy() end

local gui = mk(playerGui, "ScreenGui", {
	Name = "ReviveGui",
	ResetOnSpawn = false,
	IgnoreGuiInset = true,
	Enabled = false,
	DisplayOrder = 500,
})

-- swallow clicks (prevents click-through)
local overlay = mk(gui, "TextButton", {
	Size = UDim2.new(1,0,1,0),
	BackgroundColor3 = Color3.fromRGB(0,0,0),
	BackgroundTransparency = 0.45,
	Text = "",
	AutoButtonColor = false,
	Active = true,
	Selectable = true,
	ZIndex = 1,
})
overlay.MouseButton1Click:Connect(function() end)

local panelW = isMobile and 520 or 560
local panelH = isMobile and 260 or 240

local panel = mk(gui, "Frame", {
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.new(0.5,0,0.5,0),
	Size = UDim2.new(0, panelW, 0, panelH),
	BackgroundColor3 = Color3.fromRGB(18,18,18),
	BorderSizePixel = 0,
	ZIndex = 2,
})
mk(panel, "UICorner", {CornerRadius = UDim.new(0,16)})
mk(panel, "UIStroke", {Thickness = 2, Color = Color3.fromRGB(65,190,235), Transparency = 0})
mk(panel, "UIPadding", {
	PaddingLeft = UDim.new(0, 16),
	PaddingRight = UDim.new(0, 16),
	PaddingTop = UDim.new(0, 14),
	PaddingBottom = UDim.new(0, 14),
})

local title = mk(panel, "TextLabel", {
	Size = UDim2.new(1, 0, 0, 38),
	BackgroundTransparency = 1,
	Text = "Eliminated",
	TextColor3 = Color3.fromRGB(255,255,255),
	Font = Enum.Font.GothamBold,
	TextScaled = true,
	TextXAlignment = Enum.TextXAlignment.Left,
	ZIndex = 3,
})
mk(title, "UITextSizeConstraint", { MinTextSize = isMobile and 18 or 20, MaxTextSize = isMobile and 26 or 28 })

local desc = mk(panel, "TextLabel", {
	Size = UDim2.new(1, 0, 0, isMobile and 92 or 74),
	Position = UDim2.new(0, 0, 0, 44),
	BackgroundTransparency = 1,
	Text = "",
	TextColor3 = Color3.fromRGB(230,230,230),
	Font = Enum.Font.Gotham,
	TextScaled = true,
	TextWrapped = true,
	TextXAlignment = Enum.TextXAlignment.Left,
	TextYAlignment = Enum.TextYAlignment.Top,
	ZIndex = 3,
})
mk(desc, "UITextSizeConstraint", { MinTextSize = isMobile and 14 or 14, MaxTextSize = isMobile and 18 or 18 })

local timerLbl = mk(panel, "TextLabel", {
	Size = UDim2.new(1, 0, 0, 24),
	Position = UDim2.new(0, 0, 1, -64),
	BackgroundTransparency = 1,
	Text = "",
	TextColor3 = Color3.fromRGB(200,200,200),
	Font = Enum.Font.Gotham,
	TextScaled = true,
	TextXAlignment = Enum.TextXAlignment.Left,
	ZIndex = 3,
})
mk(timerLbl, "UITextSizeConstraint", { MinTextSize = 12, MaxTextSize = 16 })

local btnRow = mk(panel, "Frame", {
	Size = UDim2.new(1, 0, 0, 46),
	Position = UDim2.new(0, 0, 1, -46),
	BackgroundTransparency = 1,
	ZIndex = 3,
})
mk(btnRow, "UIListLayout", {
	FillDirection = Enum.FillDirection.Horizontal,
	HorizontalAlignment = Enum.HorizontalAlignment.Right,
	SortOrder = Enum.SortOrder.LayoutOrder,
	Padding = UDim.new(0, 10),
})

local btnHome = mk(btnRow, "TextButton", {
	Size = UDim2.new(0, isMobile and 170 or 160, 1, 0),
	Text = "HOME",
	BackgroundColor3 = Color3.fromRGB(40,40,46),
	TextColor3 = Color3.fromRGB(255,255,255),
	Font = Enum.Font.GothamBold,
	TextScaled = true,
	AutoButtonColor = true,
	ZIndex = 4,
})
mk(btnHome, "UICorner", {CornerRadius = UDim.new(0,12)})
mk(btnHome, "UITextSizeConstraint", { MinTextSize = 14, MaxTextSize = 18 })

local btnRevive = mk(btnRow, "TextButton", {
	Size = UDim2.new(0, isMobile and 170 or 160, 1, 0),
	Text = "REVIVE",
	BackgroundColor3 = Color3.fromRGB(65,190,235),
	TextColor3 = Color3.fromRGB(10,10,10),
	Font = Enum.Font.GothamBold,
	TextScaled = true,
	AutoButtonColor = true,
	LayoutOrder = -1,
	ZIndex = 4,
})
mk(btnRevive, "UICorner", {CornerRadius = UDim.new(0,12)})
mk(btnRevive, "UITextSizeConstraint", { MinTextSize = 14, MaxTextSize = 18 })

local timeoutToken = 0
local canConsumeNow = false
local showReviveButton = true

local function close()
	gui.Enabled = false
	timeoutToken += 1
end

btnHome.MouseButton1Click:Connect(function()
	reviveRemote:FireServer("Home")
	close()
end)

btnRevive.MouseButton1Click:Connect(function()
	-- Unified request: server decides whether this revives OR prompts purchase
	reviveRemote:FireServer("RequestReviveOrBuy")
end)

local function startTimeout(seconds)
	timeoutToken += 1
	local my = timeoutToken
	task.spawn(function()
		for i = seconds, 0, -1 do
			if my ~= timeoutToken then return end
			timerLbl.Text = ("Auto HOME in %ds"):format(i)
			task.wait(1)
		end
		if my ~= timeoutToken then return end
		reviveRemote:FireServer("Home")
		close()
	end)
end

reviveRemote.OnClientEvent:Connect(function(kind, payload)
	if kind == "Show" then
		gui.Enabled = true

		canConsumeNow = payload and payload.canConsumeNow == true
		showReviveButton = payload and payload.showReviveButton ~= false

		btnRevive.Visible = showReviveButton
		btnRevive.Text = canConsumeNow and "REVIVE" or "BUY REVIVE"

		desc.Text = payload and payload.text or "Choose an option."
		startTimeout(tonumber(payload and payload.timeout) or 10)

	elseif kind == "Hide" then
		close()

	elseif kind == "PromptPurchase" then
		local productId = tonumber(payload)
		if productId then
			MarketplaceService:PromptProductPurchase(player, productId)
		end

	elseif kind == "Message" then
		if typeof(payload) == "string" then
			desc.Text = payload
		end

	elseif kind == "Refresh" then
		-- server got purchase or pass update; ask for UI refresh
		reviveRemote:FireServer("Refresh")
	end
end)
