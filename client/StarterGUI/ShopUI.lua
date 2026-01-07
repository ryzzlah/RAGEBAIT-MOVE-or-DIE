-- StarterGui/ShopUI (LocalScript)
-- REWRITE (same features, faster Robux loading + coin balance in header)
-- ✅ Coins + Robux tabs
-- ✅ Icons FIXED (each item uses its own ID)
-- ✅ Icon caching (no repeated GetProductInfo spam)
-- ✅ Robux tab loads instantly (icons/owned update asynchronously)
-- ✅ Owned state:
--    - Coins: Owned_* attributes (server truth)
--    - Gamepasses: UserOwnsGamePassAsync (client truth) + refresh after purchase prompt
-- ✅ Shows coin balance inside Shop header (top right)
-- ✅ Overlay closes ONLY when clicking outside panel

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local MarketplaceService = game:GetService("MarketplaceService")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- ==== IDs (your real IDs here) ====
local GAMEPASS = {
	VIP        = 1234567890,
	EXTRA_LIFE = 1652150771,
	TRAIL_PACK = 1651928187,
}

local PRODUCT = {
	REVIVE     = 3498314947,
	COIN_BOOST = 1234567901,
	CHAOS      = 1234567902,
}

-- Accent
local ACCENT = Color3.fromRGB(235, 65, 65)

-- Theme
local BTN_GREY     = Color3.fromRGB(42,42,42)
local BTN_GREY_DIM = Color3.fromRGB(32,32,32)
local BTN_STROKE   = Color3.fromRGB(75,75,75)
local ROW_BG       = Color3.fromRGB(24,24,24)
local PANEL_BG     = Color3.fromRGB(18,18,18)
local TOP_BG       = Color3.fromRGB(14,14,14)

-- Remotes
local buyWithCoins = ReplicatedStorage:WaitForChild("BuyWithCoins")
local matchState   = ReplicatedStorage:WaitForChild("MatchState")

local shopResult = ReplicatedStorage:FindFirstChild("ShopResult")
if not shopResult then
	shopResult = Instance.new("RemoteEvent")
	shopResult.Name = "ShopResult"
	shopResult.Parent = ReplicatedStorage
end

-- =========================
-- Helpers
-- =========================
local function mk(parent, class, props)
	local o = Instance.new(class)
	for k,v in pairs(props or {}) do o[k] = v end
	o.Parent = parent
	return o
end

local function clearFrames(container)
	for _, c in ipairs(container:GetChildren()) do
		if c:IsA("Frame") then c:Destroy() end
	end
end

local function clearButtons(container)
	for _, c in ipairs(container:GetChildren()) do
		if c:IsA("TextButton") then c:Destroy() end
	end
end

-- Owned via server attributes (coins shop items)
local function isOwnedAttr(categoryKey: string, itemId: string)
	return player:GetAttribute(("Owned_%s_%s"):format(categoryKey, itemId)) == true
end

-- =========================
-- ICON SYSTEM (FAST + ASYNC)
-- =========================
local iconCache = {} -- key: "<type>:<id>" -> iconAssetId (number) or false
local iconInFlight = {} -- key -> true while fetching

local function getIconAssetIdCached(id: number, infoType: Enum.InfoType)
	local key = ("%s:%d"):format(infoType.Name, id)
	if iconCache[key] ~= nil then
		return iconCache[key] or nil
	end
	return nil
end

local function fetchIconAssetId(id: number, infoType: Enum.InfoType)
	local key = ("%s:%d"):format(infoType.Name, id)
	if iconCache[key] ~= nil then
		return iconCache[key] or nil
	end
	if iconInFlight[key] then
		return nil
	end

	iconInFlight[key] = true
	local ok, info = pcall(MarketplaceService.GetProductInfo, MarketplaceService, id, infoType)
	iconInFlight[key] = nil

	if ok and info and type(info.IconImageAssetId) == "number" and info.IconImageAssetId > 0 then
		iconCache[key] = info.IconImageAssetId
		return info.IconImageAssetId
	end

	iconCache[key] = false
	return nil
end

local function setCircularIcon(img: ImageLabel, assetId: number?)
	if assetId and assetId > 0 then
		img.Image = ("rbxassetid://%d"):format(assetId)
	else
		img.Image = ""
	end
end

-- =========================
-- GUI ROOT
-- =========================
local oldGui = playerGui:FindFirstChild("ShopGui")
if oldGui then oldGui:Destroy() end

local gui = mk(playerGui, "ScreenGui", {
	Name = "ShopGui",
	ResetOnSpawn = false,
	IgnoreGuiInset = true,
	Enabled = true,
	DisplayOrder = 100,
})

matchState.OnClientEvent:Connect(function(inMatch)
	gui.Enabled = not inMatch
	if inMatch then
		local p = gui:FindFirstChild("ShopPanel")
		local o = gui:FindFirstChild("Overlay")
		if p then p.Visible = false end
		if o then o.Visible = false end
	end
end)

-- Toggle button
local btn = mk(gui, "TextButton", {
	Name="ShopButton",
	Text="SHOP",
	Size=UDim2.new(0,140,0,44),
	Position = UDim2.new(0, 20, 0.5, -22),
	BackgroundColor3=BTN_GREY,
	TextColor3=Color3.fromRGB(255,255,255),
	TextScaled=true,
	Font=Enum.Font.GothamBold,
	AutoButtonColor=true,
	ZIndex = 5,
})
mk(btn, "UICorner", {CornerRadius=UDim.new(0,10)})
mk(btn, "UIStroke", {Thickness=1, Color=BTN_STROKE, Transparency=0})

-- Overlay
local overlay = mk(gui, "TextButton", {
	Name="Overlay",
	Size=UDim2.new(1,0,1,0),
	BackgroundColor3=Color3.fromRGB(0,0,0),
	BackgroundTransparency=0.45,
	Text="",
	Visible=false,
	AutoButtonColor=false,
	ZIndex=10
})

-- Panel
local PANEL_W, PANEL_H = 670, 380
local panel = mk(gui, "Frame", {
	Name="ShopPanel",
	Size=UDim2.new(0,PANEL_W,0,PANEL_H),
	Position=UDim2.new(0.5,-PANEL_W/2,0.5,-PANEL_H/2),
	BackgroundColor3=PANEL_BG,
	BorderSizePixel=0,
	Visible=false,
	ZIndex=20
})
mk(panel, "UICorner", {CornerRadius=UDim.new(0,16)})
mk(panel, "UIStroke", {Thickness=2, Color=Color3.fromRGB(45,45,45), Transparency=0})

-- Header
local top = mk(panel, "Frame", {
	Size=UDim2.new(1,0,0,54),
	BackgroundColor3=TOP_BG,
	BorderSizePixel=0,
	ZIndex=21,
})
mk(top, "UICorner", {CornerRadius=UDim.new(0,16)})
mk(top, "Frame", {
	Size=UDim2.new(1,0,0.5,0),
	Position=UDim2.new(0,0,0.5,0),
	BackgroundColor3=TOP_BG,
	BorderSizePixel=0,
	ZIndex=21,
})

mk(panel, "Frame", {
	Size=UDim2.new(1,0,0,2),
	Position=UDim2.new(0,0,0,54),
	BackgroundColor3=ACCENT,
	BorderSizePixel=0,
	ZIndex=21
})

mk(top, "TextLabel", {
	Size=UDim2.new(1,-240,1,0),
	Position=UDim2.new(0,16,0,0),
	BackgroundTransparency=1,
	Text="Shop",
	TextXAlignment=Enum.TextXAlignment.Left,
	TextScaled=true,
	Font=Enum.Font.GothamBold,
	TextColor3=Color3.fromRGB(255,255,255),
	ZIndex=22
})

-- ✅ Coin balance in header (top right, opposite side)
local coinsHeader = mk(top, "TextLabel", {
	Size = UDim2.new(0, 170, 1, 0),
	Position = UDim2.new(1, -230, 0, 0),
	BackgroundTransparency = 1,
	Text = "Coins: ...",
	TextXAlignment = Enum.TextXAlignment.Right,
	TextScaled = true,
	Font = Enum.Font.GothamBold,
	TextColor3 = Color3.fromRGB(255,255,255),
	ZIndex = 22,
})

local closeBtn = mk(top, "TextButton", {
	Size=UDim2.new(0,34,0,34),
	Position=UDim2.new(1,-50,0.5,-17),
	BackgroundColor3=ACCENT,
	Text="",
	AutoButtonColor=true,
	ZIndex=22
})
mk(closeBtn, "UICorner", {CornerRadius=UDim.new(1,0)})
mk(closeBtn, "UIStroke", {Thickness=1, Color=Color3.fromRGB(90,20,20), Transparency=0})

local function makeLine(parent, rot)
	local line = mk(parent, "Frame", {
		Size=UDim2.new(0,18,0,2),
		Position=UDim2.new(0.5,-9,0.5,-1),
		BackgroundColor3=Color3.fromRGB(255,255,255),
		BorderSizePixel=0,
		ZIndex=23
	})
	line.Rotation = rot
	return line
end
makeLine(closeBtn, 45)
makeLine(closeBtn, -45)

-- =========================
-- Coins display logic
-- =========================
local coinsValueObj: IntValue? = nil

local function bindCoins()
	local ls = player:FindFirstChild("leaderstats")
	if not ls then return end
	local c = ls:FindFirstChild("Coins")
	if c and c:IsA("IntValue") then
		coinsValueObj = c
	end
end

local function refreshCoinsHeader()
	if not coinsValueObj then
		bindCoins()
	end
	local v = coinsValueObj and coinsValueObj.Value or 0
	coinsHeader.Text = ("Coins: %d"):format(v)
end

task.spawn(function()
	while gui.Parent do
		refreshCoinsHeader()
		task.wait(0.25)
	end
end)

player.ChildAdded:Connect(function(ch)
	if ch.Name == "leaderstats" then
		task.wait(0.1)
		bindCoins()
		refreshCoinsHeader()
	end
end)

-- =========================
-- Tabs
-- =========================
local tabs = mk(panel, "Frame", {
	Size=UDim2.new(1,-32,0,38),
	Position=UDim2.new(0,16,0,68),
	BackgroundTransparency=1,
	ZIndex=21
})

local coinsTab = mk(tabs, "TextButton", {
	Size=UDim2.new(0,140,1,0),
	Text="Coins",
	BackgroundColor3=BTN_GREY,
	TextColor3=Color3.fromRGB(255,255,255),
	TextScaled=true,
	Font=Enum.Font.GothamBold,
	ZIndex=22
})
mk(coinsTab, "UICorner", {CornerRadius=UDim.new(0,10)})
local coinsStroke = mk(coinsTab, "UIStroke", {Thickness=1, Color=ACCENT, Transparency=0})

local robuxTab = mk(tabs, "TextButton", {
	Size=UDim2.new(0,140,1,0),
	Position=UDim2.new(0,152,0,0),
	Text="Robux",
	BackgroundColor3=BTN_GREY_DIM,
	TextColor3=Color3.fromRGB(230,230,230),
	TextScaled=true,
	Font=Enum.Font.GothamBold,
	ZIndex=22
})
mk(robuxTab, "UICorner", {CornerRadius=UDim.new(0,10)})
local robuxStroke = mk(robuxTab, "UIStroke", {Thickness=1, Color=BTN_STROKE, Transparency=0})

local function setTab(activeCoins: boolean)
	if activeCoins then
		coinsTab.BackgroundColor3 = BTN_GREY
		coinsTab.TextColor3 = Color3.fromRGB(255,255,255)
		coinsStroke.Color = ACCENT

		robuxTab.BackgroundColor3 = BTN_GREY_DIM
		robuxTab.TextColor3 = Color3.fromRGB(230,230,230)
		robuxStroke.Color = BTN_STROKE
	else
		robuxTab.BackgroundColor3 = BTN_GREY
		robuxTab.TextColor3 = Color3.fromRGB(255,255,255)
		robuxStroke.Color = ACCENT

		coinsTab.BackgroundColor3 = BTN_GREY_DIM
		coinsTab.TextColor3 = Color3.fromRGB(230,230,230)
		coinsStroke.Color = BTN_STROKE
	end
end

-- Category bar (Coins only)
local catBar = mk(panel, "Frame", {
	Name="CategoryBar",
	Size=UDim2.new(1,-32,0,34),
	Position=UDim2.new(0,16,0,112),
	BackgroundTransparency=1,
	ZIndex=21,
	Visible=true
})
local catLayout = mk(catBar, "UIListLayout", {
	FillDirection = Enum.FillDirection.Horizontal,
	SortOrder = Enum.SortOrder.LayoutOrder,
	Padding = UDim.new(0,10),
})
catLayout.VerticalAlignment = Enum.VerticalAlignment.Center

-- List
local list = mk(panel, "ScrollingFrame", {
	Name="List",
	Size=UDim2.new(1,-32,1,-160),
	Position=UDim2.new(0,16,0,154),
	BackgroundTransparency=1,
	BorderSizePixel=0,
	ScrollBarThickness=6,
	AutomaticCanvasSize=Enum.AutomaticSize.Y,
	CanvasSize=UDim2.new(0,0,0,0),
	ZIndex=21
})
mk(list, "UIListLayout", {Padding=UDim.new(0,10), SortOrder=Enum.SortOrder.LayoutOrder})
mk(list, "UIPadding", {PaddingTop=UDim.new(0,4), PaddingBottom=UDim.new(0,10)})

-- Toast
local toast = mk(gui, "Frame", {
	Size=UDim2.new(0, 420, 0, 48),
	Position=UDim2.new(0.5, -210, 1, -70),
	BackgroundColor3=Color3.fromRGB(16,16,16),
	BorderSizePixel=0,
	Visible=false,
	ZIndex=50
})
mk(toast, "UICorner", {CornerRadius=UDim.new(0,12)})
local toastStroke = mk(toast, "UIStroke", {Thickness=1, Color=ACCENT, Transparency=0})
local toastText = mk(toast, "TextLabel", {
	Size=UDim2.new(1,-16,1,0),
	Position=UDim2.new(0,8,0,0),
	BackgroundTransparency=1,
	Text="",
	TextScaled=true,
	Font=Enum.Font.GothamBold,
	TextColor3=Color3.fromRGB(255,255,255),
	ZIndex=51
})
local toastId = 0
local function showToast(msg, isBad)
	toastId += 1
	local myId = toastId
	toast.Visible = true
	toastText.Text = tostring(msg)
	toastStroke.Color = isBad and Color3.fromRGB(255, 90, 90) or ACCENT
	task.delay(2.0, function()
		if toastId == myId then toast.Visible = false end
	end)
end

-- =========================
-- Row builder (returns references so we can async-update)
-- =========================
local function addItemRow(labelText, subText, buttonText, onClick, disabled, forceOwned)
	local row = mk(list, "Frame", {
		Size=UDim2.new(1,0,0,66),
		BackgroundColor3=ROW_BG,
		BorderSizePixel=0,
		ZIndex=22
	})
	mk(row, "UICorner", {CornerRadius=UDim.new(0,12)})
	mk(row, "UIStroke", {Thickness=1, Color=Color3.fromRGB(40,40,40), Transparency=0})

	local icon = mk(row, "ImageLabel", {
		Size=UDim2.new(0,44,0,44),
		Position=UDim2.new(0,12,0.5,-22),
		BackgroundColor3=Color3.fromRGB(16,16,16),
		BorderSizePixel=0,
		ZIndex=23,
		ScaleType=Enum.ScaleType.Crop
	})
	mk(icon, "UICorner", {CornerRadius=UDim.new(1,0)})
	mk(icon, "UIStroke", {Thickness=1, Color=Color3.fromRGB(55,55,55), Transparency=0})
	setCircularIcon(icon, nil)

	local textLbl = mk(row, "TextLabel", {
		Size=UDim2.new(1,-210,1,-16),
		Position=UDim2.new(0,68,0,8),
		BackgroundTransparency=1,
		TextXAlignment=Enum.TextXAlignment.Left,
		TextYAlignment=Enum.TextYAlignment.Center,
		Text=labelText .. "\n" .. subText,
		TextColor3=(disabled or forceOwned) and Color3.fromRGB(170,170,170) or Color3.fromRGB(255,255,255),
		Font=Enum.Font.Gotham,
		TextSize=18,
		ZIndex=23
	})

	local finalDisabled = disabled or forceOwned
	local finalText = forceOwned and "Owned" or (disabled and "Soon" or (buttonText or "Buy"))

	local b = mk(row, "TextButton", {
		Size=UDim2.new(0,120,0,38),
		Position=UDim2.new(1,-134,0.5,-19),
		Text=finalText,
		BackgroundColor3=finalDisabled and BTN_GREY_DIM or BTN_GREY,
		TextColor3=Color3.fromRGB(255,255,255),
		Font=Enum.Font.GothamBold,
		TextScaled=true,
		ZIndex=23,
		AutoButtonColor = not finalDisabled,
		Active = not finalDisabled
	})
	mk(b, "UICorner", {CornerRadius=UDim.new(0,10)})
	local bStroke = mk(b, "UIStroke", {Thickness=1, Color=finalDisabled and BTN_STROKE or ACCENT, Transparency=0})

	if not finalDisabled then
		b.MouseButton1Click:Connect(function()
			local ok, err = pcall(onClick)
			if not ok then warn("[ShopUI] click failed:", err) end
		end)
	end

	return row, icon, textLbl, b, bStroke
end

local function setButtonOwned(button: TextButton, buttonStroke: UIStroke, owned: boolean)
	if not button or not button.Parent then return end
	if owned then
		button.Text = "Owned"
		button.Active = false
		button.AutoButtonColor = false
		button.BackgroundColor3 = BTN_GREY_DIM
		buttonStroke.Color = BTN_STROKE
	else
		button.Text = "BUY"
		button.Active = true
		button.AutoButtonColor = true
		button.BackgroundColor3 = BTN_GREY
		buttonStroke.Color = ACCENT
	end
end

-- =========================
-- Coins categories
-- =========================
local COIN_CATEGORIES = {
	{
		id = "Trails",
		ownedCategory = "Trails",
		items = {
			{ itemId="Trail_Yellow",  name="Yellow Trail",  desc="Basic Tier",  price="80",  buy=function() buyWithCoins:FireServer("Trail_Yellow") end },
			{ itemId="Trail_Green",   name="Green Trail",   desc="Basic Tier",  price="120", buy=function() buyWithCoins:FireServer("Trail_Green") end },
			{ itemId="Trail_Blue",    name="Blue Trail",    desc="Uncommon",    price="180", buy=function() buyWithCoins:FireServer("Trail_Blue") end },
			{ itemId="Trail_Orange",  name="Orange Trail",  desc="Uncommon",    price="180", buy=function() buyWithCoins:FireServer("Trail_Orange") end },
			{ itemId="Trail_Red",     name="Red Trail",     desc="Uncommon",    price="220", buy=function() buyWithCoins:FireServer("Trail_Red") end },
			{ itemId="Trail_Pink",    name="Pink Trail",    desc="Rare",        price="300", buy=function() buyWithCoins:FireServer("Trail_Pink") end },
			{ itemId="Trail_Teal",    name="Teal Trail",    desc="Rare",        price="340", buy=function() buyWithCoins:FireServer("Trail_Teal") end },
			{ itemId="Trail_Purple",  name="Purple Trail",  desc="Rare",        price="380", buy=function() buyWithCoins:FireServer("Trail_Purple") end },
			{ itemId="Trail_Magenta", name="Magenta Trail", desc="Epic",        price="420", buy=function() buyWithCoins:FireServer("Trail_Magenta") end },
			{ itemId="Trail_White",   name="White Trail",   desc="Legendary",   price="600", buy=function() buyWithCoins:FireServer("Trail_White") end },
		}
	},
	{
		id = "Troll Items",
		ownedCategory = "TrollItems",
		items = {
			-- add later
		}
	},
}

-- =========================
-- Robux items
-- =========================
local robuxItems = {
	{ kind="GamePass", id=GAMEPASS.EXTRA_LIFE, name="Extra Life",           desc="Permanent 1 revive per game forever" },
	{ kind="GamePass", id=GAMEPASS.TRAIL_PACK, name="Exclusive Trail Pack", desc="Unlock 5 limited edition trails" },
	{ kind="Product",  id=PRODUCT.REVIVE,      name="Small Revive",         desc="Revive once after dying (one match)" },
}

local gamepassOwnedCache = {} -- passId -> bool or nil when unknown
local function ownsGamepass(passId: number): boolean
	if gamepassOwnedCache[passId] ~= nil then
		return gamepassOwnedCache[passId]
	end
	local ok, res = pcall(MarketplaceService.UserOwnsGamePassAsync, MarketplaceService, player.UserId, passId)
	gamepassOwnedCache[passId] = (ok and res == true)
	return gamepassOwnedCache[passId]
end
local function refreshGamepassOwned()
	gamepassOwnedCache = {}
end

-- ✅ prefetch icons in background (helps first open)
task.spawn(function()
	for _, item in ipairs(robuxItems) do
		if item.kind == "GamePass" then
			task.spawn(function() fetchIconAssetId(item.id, Enum.InfoType.GamePass) end)
		else
			task.spawn(function() fetchIconAssetId(item.id, Enum.InfoType.Product) end)
		end
	end
end)

-- =========================
-- Category buttons (Coins)
-- =========================
local categoryButtons = {}
local selectedCategoryId: string? = nil

local function styleCategoryButton(b: TextButton, active: boolean)
	local st = b:FindFirstChildOfClass("UIStroke")
	if active then
		b.BackgroundColor3 = BTN_GREY
		b.TextColor3 = Color3.fromRGB(255,255,255)
		if st then st.Color = ACCENT end
	else
		b.BackgroundColor3 = BTN_GREY_DIM
		b.TextColor3 = Color3.fromRGB(230,230,230)
		if st then st.Color = BTN_STROKE end
	end
end

local function renderCoinsCategory(catId: string)
	clearFrames(list)
	for _, cat in ipairs(COIN_CATEGORIES) do
		if cat.id == catId then
			for _, item in ipairs(cat.items) do
				local owned = isOwnedAttr(cat.ownedCategory, item.itemId)
				addItemRow(item.name, item.desc, item.price, item.buy, false, owned)
			end
			break
		end
	end
	for _, cat in ipairs(COIN_CATEGORIES) do
		local b = categoryButtons[cat.id]
		if b then styleCategoryButton(b, cat.id == catId) end
	end
end

local function buildCategoryButtons()
	clearButtons(catBar)
	categoryButtons = {}

	local CAT_BTN_W = 120
	for _, cat in ipairs(COIN_CATEGORIES) do
		local b = mk(catBar, "TextButton", {
			Name = "Cat_" .. cat.id,
			Size = UDim2.new(0, CAT_BTN_W, 1, 0),
			BackgroundColor3 = BTN_GREY_DIM,
			TextColor3 = Color3.fromRGB(230,230,230),
			TextScaled = true,
			Font = Enum.Font.GothamBold,
			Text = cat.id,
			ZIndex = 22,
			AutoButtonColor = true
		})
		mk(b, "UICorner", {CornerRadius=UDim.new(0,10)})
		mk(b, "UIStroke", {Thickness=1, Color=BTN_STROKE, Transparency=0})

		categoryButtons[cat.id] = b
		b.MouseButton1Click:Connect(function()
			selectedCategoryId = cat.id
			renderCoinsCategory(selectedCategoryId)
		end)
	end
end

-- =========================
-- Tabs content
-- =========================
local function showCoins()
	catBar.Visible = true
	clearFrames(list)

	if not next(categoryButtons) then
		buildCategoryButtons()
	end
	if not selectedCategoryId then
		selectedCategoryId = COIN_CATEGORIES[1] and COIN_CATEGORIES[1].id or "Trails"
	end
	renderCoinsCategory(selectedCategoryId)
end

local function showRobux()
	catBar.Visible = false
	clearFrames(list)

	for _, item in ipairs(robuxItems) do
		if item.kind == "GamePass" then
			local row, icon, _, b, bStroke = addItemRow(
				item.name,
				item.desc,
				"BUY",
				function() MarketplaceService:PromptGamePassPurchase(player, item.id) end,
				false,
				false -- temp, updated async
			)

			-- set owned quickly from cache or async check
			task.spawn(function()
				if not row.Parent then return end
				local owned = ownsGamepass(item.id)
				if row.Parent then
					setButtonOwned(b, bStroke, owned)
				end
			end)

			-- icon async
			task.spawn(function()
				if not row.Parent then return end
				local cached = getIconAssetIdCached(item.id, Enum.InfoType.GamePass)
				if cached then
					setCircularIcon(icon, cached)
					return
				end
				local iconId = fetchIconAssetId(item.id, Enum.InfoType.GamePass)
				if row.Parent then
					setCircularIcon(icon, iconId)
				end
			end)

		elseif item.kind == "Product" then
			local row, icon = addItemRow(
				item.name,
				item.desc,
				"BUY",
				function() MarketplaceService:PromptProductPurchase(player, item.id) end,
				false,
				false
			)

			task.spawn(function()
				if not row.Parent then return end
				local cached = getIconAssetIdCached(item.id, Enum.InfoType.Product)
				if cached then
					setCircularIcon(icon, cached)
					return
				end
				local iconId = fetchIconAssetId(item.id, Enum.InfoType.Product)
				if row.Parent then
					setCircularIcon(icon, iconId)
				end
			end)
		end
	end
end

-- =========================
-- Open/Close
-- =========================
local function openShop()
	refreshCoinsHeader()
	overlay.Visible = true
	panel.Visible = true
end

local function closeShop()
	panel.Visible = false
	overlay.Visible = false
end

btn.MouseButton1Click:Connect(function()
	if panel.Visible then closeShop() else openShop() end
end)
closeBtn.MouseButton1Click:Connect(closeShop)

-- ✅ Close ONLY if click is OUTSIDE panel (works reliably)
overlay.MouseButton1Click:Connect(function()
	if not panel.Visible then return end

	local mousePos = UserInputService:GetMouseLocation()
	local pos = panel.AbsolutePosition
	local size = panel.AbsoluteSize

	local inside =
		mousePos.X >= pos.X and mousePos.X <= (pos.X + size.X) and
		mousePos.Y >= pos.Y and mousePos.Y <= (pos.Y + size.Y)

	if not inside then
		closeShop()
	end
end)

-- Tabs
coinsTab.MouseButton1Click:Connect(function()
	setTab(true)
	showCoins()
end)

robuxTab.MouseButton1Click:Connect(function()
	setTab(false)
	showRobux()
end)

-- When purchase prompt closes, refresh and rerender if Robux tab is open
MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(plr, passId, purchased)
	if plr ~= player then return end
	refreshGamepassOwned()
	if panel.Visible and robuxTab.BackgroundColor3 == BTN_GREY then
		showRobux()
	end
end)

-- Default
setTab(true)
showCoins()

-- Attribute owned updates (coins)
player.AttributeChanged:Connect(function(attrName)
	if not panel.Visible then return end
	if typeof(attrName) ~= "string" then return end
	if attrName:sub(1,6) == "Owned_" and coinsTab.BackgroundColor3 == BTN_GREY and selectedCategoryId then
		renderCoinsCategory(selectedCategoryId)
	end
end)

shopResult.OnClientEvent:Connect(function(success, message)
	showToast(message or (success and "Purchase successful!" or "Insufficient coins."), not success)
	if panel.Visible and coinsTab.BackgroundColor3 == BTN_GREY and selectedCategoryId then
		task.defer(function()
			renderCoinsCategory(selectedCategoryId)
		end)
	end
end)

