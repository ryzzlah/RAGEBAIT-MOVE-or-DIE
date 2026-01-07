-- StarterGui/InventoryUI (LocalScript)
-- FIXED + AUTO-PREMIUM TRAILS:
-- ✅ Your original UI logic preserved
-- ✅ Auto-loads premium trails (Robux_Trails folder names) via RemoteFunction
-- ✅ Ownership still comes ONLY from Owned_* attributes
-- ✅ Equipped state ONLY from Equipped_* attributes
-- ✅ No double click, no world detect, no invisible overlay

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local matchState = ReplicatedStorage:WaitForChild("MatchState")
local equipEvent = ReplicatedStorage:WaitForChild("EquipItem")

-- RemoteFunction to fetch premium trail ids (folder names)
local getPremiumTrailIds = ReplicatedStorage:WaitForChild("GetPremiumTrailIds")

-- ===== OPTIONAL FAILSAFE =====
local FAILSAFE_TIMEOUT = 2.0

-- ===== THEME =====
local ACCENT = Color3.fromRGB(65, 190, 235)
local BTN        = Color3.fromRGB(40,40,48)
local BTN_DIM    = Color3.fromRGB(30,30,36)
local BTN_STROKE = Color3.fromRGB(70,70,80)
local PANEL_BG   = Color3.fromRGB(16,16,20)
local ROW_BG     = Color3.fromRGB(22,22,28)

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

-- ===== Ownership via attributes =====
local function owns(category: string, itemId: string)
	return player:GetAttribute(("Owned_%s_%s"):format(category, itemId)) == true
end

-- ===== Premium trail ids loaded from server =====
local premiumTrailIds = {}

local function fetchPremiumTrails()
	local ok, result = pcall(function()
		return getPremiumTrailIds:InvokeServer()
	end)
	if ok and type(result) == "table" then
		premiumTrailIds = result
	else
		premiumTrailIds = {}
		warn("[InventoryUI] Failed to fetch premium trails list.")
	end
end

local function prettyNameFromId(id: string)
	-- Turns "RoyalPlasma" -> "Royal Plasma", "Trail_Red" -> "Trail Red"
	local s = id:gsub("_", " ")
	s = s:gsub("(%l)(%u)", "%1 %2")
	return s
end

local function buildTrailsItems()
	-- Your existing coin trails
	local items = {
		{ itemId="Trail_Red",     name="Red Trail",     desc="A bright red trail" },
		{ itemId="Trail_Blue",    name="Blue Trail",    desc="A bright blue trail" },
		{ itemId="Trail_Green",   name="Green Trail",   desc="A clean green trail" },
		{ itemId="Trail_Yellow",  name="Yellow Trail",  desc="A clean yellow trail" },
		{ itemId="Trail_Orange",  name="Orange Trail",  desc="A bright orange trail" },
		{ itemId="Trail_Pink",    name="Pink Trail",    desc="A neon pink trail" },
		{ itemId="Trail_Teal",    name="Teal Trail",    desc="A neon teal trail" },
		{ itemId="Trail_Purple",  name="Purple Trail",  desc="A flashy galaxy purple trail" },
		{ itemId="Trail_Magenta", name="Magenta Trail", desc="A premium magenta trail" },
		{ itemId="Trail_White",   name="White Trail",   desc="A flashy glowing legendary white trail." },
	}

	-- Append premium trails dynamically (from folder names)
	for _, id in ipairs(premiumTrailIds) do
		table.insert(items, {
			itemId = id,
			name = prettyNameFromId(id),
			desc = "Premium trail",
		})
	end

	return items
end

-- ===== Inventory data =====
local INVENTORY_CATEGORIES = {
	{
		id = "Trails",
		category = "Trails",
		slot = "Trail",
		items = {}, -- filled after we fetch premium ids
	},
	{
		id = "Troll Items",
		category = "TrollItems",
		slot = "TrollItem",
		items = {
			
		}
	},
}

-- ===== Equipped tracking =====
local equippedCache = {}
local pendingOverride = {}
local pendingLock = {}
local pendingToken = {}

local function normalizeEquippedValue(v): string
	if typeof(v) == "string" then
		return v
	end
	return ""
end

local function readEquippedFromAttr(slot: string): string
	local raw = player:GetAttribute("Equipped_" .. slot)
	local val = normalizeEquippedValue(raw)
	equippedCache[slot] = val
	return val
end

local function getEquipped(slot: string): string
	if pendingOverride[slot] ~= nil then
		return pendingOverride[slot]
	end
	return readEquippedFromAttr(slot)
end

local function lockSlot(slot: string): number
	pendingLock[slot] = true
	pendingToken[slot] = (pendingToken[slot] or 0) + 1
	return pendingToken[slot]
end

local function unlockSlot(slot: string)
	pendingLock[slot] = false
end

-- ===== destroy old versions so you don't stack overlays =====
local function destroyIfExists(name: string)
	local g = playerGui:FindFirstChild(name)
	if g then g:Destroy() end
end
destroyIfExists("InventoryGui")
destroyIfExists("InventoryButtonsGui")
destroyIfExists("InventoryPanelGui")
destroyIfExists("InventoryButtonsGui2")
destroyIfExists("InventoryPanelGui2")

-- ===== Two ScreenGuis =====
local guiButtons = mk(playerGui, "ScreenGui", {
	Name = "InventoryButtonsGui",
	ResetOnSpawn = false,
	IgnoreGuiInset = true,
	Enabled = true,
	DisplayOrder = 90,
})

local guiPanel = mk(playerGui, "ScreenGui", {
	Name = "InventoryPanelGui",
	ResetOnSpawn = false,
	IgnoreGuiInset = true,
	Enabled = false,
	DisplayOrder = 200,
})

-- ===== Toast =====
local toast = mk(guiPanel, "Frame", {
	Size=UDim2.new(0, 420, 0, 48),
	Position=UDim2.new(0.5, -210, 1, -70),
	BackgroundColor3=Color3.fromRGB(16,16,16),
	BorderSizePixel=0,
	Visible=false,
	ZIndex=400
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
	ZIndex=401
})
local toastId = 0
local function showToast(msg, isBad)
	toastId += 1
	local myId = toastId
	toast.Visible = true
	toastText.Text = tostring(msg)
	toastStroke.Color = isBad and Color3.fromRGB(255, 90, 90) or ACCENT
	task.delay(1.2, function()
		if toastId == myId then toast.Visible = false end
	end)
end

-- ===== Match state hide =====
matchState.OnClientEvent:Connect(function(inMatch)
	guiButtons.Enabled = not inMatch
	guiPanel.Enabled = not inMatch
	if inMatch then
		local p = guiPanel:FindFirstChild("InventoryPanel")
		local o = guiPanel:FindFirstChild("Overlay")
		if p then p.Visible = false end
		if o then o.Visible = false end
		guiPanel.Enabled = false
	end
end)

-- ===== INV button =====
local invBtn = mk(guiButtons, "TextButton", {
	Name="InventoryButton",
	Text="INV",
	Size=UDim2.new(0,140,0,44),
	Position = UDim2.new(0, 20, 0.5, 30),
	BackgroundColor3=BTN,
	TextColor3=Color3.fromRGB(255,255,255),
	TextScaled=true,
	Font=Enum.Font.GothamBold,
	AutoButtonColor=true,
	ZIndex=5
})
mk(invBtn, "UICorner", {CornerRadius=UDim.new(0,10)})
mk(invBtn, "UIStroke", {Thickness=1, Color=BTN_STROKE, Transparency=0})

-- ===== Overlay + Panel =====
local overlay = mk(guiPanel, "TextButton", {
	Name="Overlay",
	Size=UDim2.new(1,0,1,0),
	BackgroundColor3=Color3.fromRGB(0,0,0),
	BackgroundTransparency=0.45,
	Text="",
	Visible=false,
	AutoButtonColor=false,
	ZIndex=10
})

local PANEL_W, PANEL_H = 670, 380
local panel = mk(guiPanel, "Frame", {
	Name="InventoryPanel",
	Size=UDim2.new(0,PANEL_W,0,PANEL_H),
	Position=UDim2.new(0.5,-PANEL_W/2,0.5,-PANEL_H/2),
	BackgroundColor3=PANEL_BG,
	BorderSizePixel=0,
	Visible=false,
	ZIndex=20,
	Active=true,
})
mk(panel, "UICorner", {CornerRadius=UDim.new(0,16)})
mk(panel, "UIStroke", {Thickness=2, Color=Color3.fromRGB(40,40,50), Transparency=0})

local top = mk(panel, "Frame", {
	Size=UDim2.new(1,0,0,54),
	BackgroundColor3=Color3.fromRGB(12,12,16),
	BorderSizePixel=0,
	ZIndex=21,
	Active=true
})
mk(top, "UICorner", {CornerRadius=UDim.new(0,16)})
mk(top, "Frame", {
	Size=UDim2.new(1,0,0.5,0),
	Position=UDim2.new(0,0,0.5,0),
	BackgroundColor3=Color3.fromRGB(12,12,16),
	BorderSizePixel=0,
	ZIndex=21,
	Active=true
})
mk(panel, "Frame", {
	Size=UDim2.new(1,0,0,2),
	Position=UDim2.new(0,0,0,54),
	BackgroundColor3=ACCENT,
	BorderSizePixel=0,
	ZIndex=21,
	Active=true
})
mk(top, "TextLabel", {
	Size=UDim2.new(1,-110,1,0),
	Position=UDim2.new(0,16,0,0),
	BackgroundTransparency=1,
	Text="Inventory",
	TextXAlignment=Enum.TextXAlignment.Left,
	TextScaled=true,
	Font=Enum.Font.GothamBold,
	TextColor3=Color3.fromRGB(255,255,255),
	ZIndex=22
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
mk(closeBtn, "UIStroke", {Thickness=1, Color=Color3.fromRGB(20,70,90), Transparency=0})

local function makeLine(parent, rot)
	local line = mk(parent, "Frame", {
		Size=UDim2.new(0,18,0,2),
		Position=UDim2.new(0.5,-9,0.5,-1),
		BackgroundColor3=Color3.fromRGB(255,255,255),
		BorderSizePixel=0,
		ZIndex=23,
		Active=true
	})
	line.Rotation = rot
	return line
end
makeLine(closeBtn, 45)
makeLine(closeBtn, -45)

local catBar = mk(panel, "Frame", {
	Name="CategoryBar",
	Size=UDim2.new(1,-32,0,34),
	Position=UDim2.new(0,16,0,68),
	BackgroundTransparency=1,
	ZIndex=21,
	Active=true
})
local catLayout = mk(catBar, "UIListLayout", {
	FillDirection = Enum.FillDirection.Horizontal,
	SortOrder = Enum.SortOrder.LayoutOrder,
	Padding = UDim.new(0,10),
})
catLayout.VerticalAlignment = Enum.VerticalAlignment.Center

local list = mk(panel, "ScrollingFrame", {
	Name="List",
	Size=UDim2.new(1,-32,1,-120),
	Position=UDim2.new(0,16,0,110),
	BackgroundTransparency=1,
	BorderSizePixel=0,
	ScrollBarThickness=6,
	AutomaticCanvasSize=Enum.AutomaticSize.Y,
	CanvasSize=UDim2.new(0,0,0,0),
	ZIndex=21,
	Active=true
})
mk(list, "UIListLayout", {Padding=UDim.new(0,10), SortOrder=Enum.SortOrder.LayoutOrder})
mk(list, "UIPadding", {PaddingTop=UDim.new(0,4), PaddingBottom=UDim.new(0,10)})

local function addRow(itemName, subText, buttonText, buttonColor, onClick, disabled)
	local row = mk(list, "Frame", {
		Size=UDim2.new(1,0,0,66),
		BackgroundColor3=ROW_BG,
		BorderSizePixel=0,
		ZIndex=22,
		Active=true
	})
	mk(row, "UICorner", {CornerRadius=UDim.new(0,12)})
	mk(row, "UIStroke", {Thickness=1, Color=Color3.fromRGB(45,45,55), Transparency=0})

	mk(row, "TextLabel", {
		Size=UDim2.new(1,-160,1,-16),
		Position=UDim2.new(0,14,0,8),
		BackgroundTransparency=1,
		TextXAlignment=Enum.TextXAlignment.Left,
		TextYAlignment=Enum.TextYAlignment.Center,
		Text=itemName .. "\n" .. subText,
		TextColor3=disabled and Color3.fromRGB(170,170,170) or Color3.fromRGB(255,255,255),
		Font=Enum.Font.Gotham,
		TextSize=18,
		ZIndex=23
	})

	local b = mk(row, "TextButton", {
		Size=UDim2.new(0,130,0,38),
		Position=UDim2.new(1,-144,0.5,-19),
		Text=buttonText,
		BackgroundColor3=buttonColor,
		TextColor3=Color3.fromRGB(255,255,255),
		Font=Enum.Font.GothamBold,
		TextScaled=true,
		ZIndex=23,
		AutoButtonColor = not disabled,
		Active = not disabled
	})
	mk(b, "UICorner", {CornerRadius=UDim.new(0,10)})
	mk(b, "UIStroke", {Thickness=1, Color=disabled and BTN_STROKE or ACCENT, Transparency=0})

	if not disabled then
		b.MouseButton1Click:Connect(function()
			local ok, err = pcall(onClick)
			if not ok then warn("[InventoryUI] click failed:", err) end
		end)
	end
end

local categoryButtons = {}
local selectedId: string? = nil

local function styleCatBtn(b, active)
	local st = b:FindFirstChildOfClass("UIStroke")
	if active then
		b.BackgroundColor3 = BTN
		b.TextColor3 = Color3.fromRGB(255,255,255)
		if st then st.Color = ACCENT end
	else
		b.BackgroundColor3 = BTN_DIM
		b.TextColor3 = Color3.fromRGB(230,230,230)
		if st then st.Color = BTN_STROKE end
	end
end

local function renderCategory(catId)
	clearFrames(list)

	local foundCat
	for _, cat in ipairs(INVENTORY_CATEGORIES) do
		if cat.id == catId then foundCat = cat break end
	end
	if not foundCat then return end

	local equippedNow = getEquipped(foundCat.slot)
	local ownedCount = 0

	for _, item in ipairs(foundCat.items) do
		if owns(foundCat.category, item.itemId) then
			ownedCount += 1

			local isEquipped = (equippedNow == item.itemId)
			local isPending = pendingLock[foundCat.slot] == true

			local btnText, btnColor
			if isPending then
				btnText = "..."
				btnColor = BTN_DIM
			else
				btnText = isEquipped and "Unequip" or "Equip"
				btnColor = isEquipped and BTN_DIM or BTN
			end

			local sub = isEquipped and "Equipped ✅" or (item.desc or "")

			addRow(item.name, sub, btnText, btnColor, function()
				if pendingLock[foundCat.slot] then return end

				local slot = foundCat.slot
				local token = lockSlot(slot)

				local now = getEquipped(slot)
				local wasEquipped = (now == item.itemId)
				local equip = not wasEquipped

				pendingOverride[slot] = equip and item.itemId or ""

				equipEvent:FireServer(foundCat.category, item.itemId, equip)

				showToast((equip and "Equipped: " or "Unequipped: ") .. item.name, false)
				if selectedId then renderCategory(selectedId) end

				if FAILSAFE_TIMEOUT and FAILSAFE_TIMEOUT > 0 then
					task.delay(FAILSAFE_TIMEOUT, function()
						if pendingToken[slot] ~= token then return end
						if pendingLock[slot] then
							pendingOverride[slot] = nil
							unlockSlot(slot)
							if panel.Visible and selectedId then
								renderCategory(selectedId)
							end
						end
					end)
				end
			end, false)
		end
	end

	if ownedCount == 0 then
		addRow("Nothing owned here", "Buy something in the Shop first.", "OK", BTN_DIM, function() end, true)
	end

	for _, cat in ipairs(INVENTORY_CATEGORIES) do
		local b = categoryButtons[cat.id]
		if b then styleCatBtn(b, cat.id == catId) end
	end
end

local function buildCategoryButtons()
	clearButtons(catBar)
	categoryButtons = {}

	local CAT_BTN_W = 150
	for _, cat in ipairs(INVENTORY_CATEGORIES) do
		local b = mk(catBar, "TextButton", {
			Name = "Cat_" .. cat.id,
			Size = UDim2.new(0, CAT_BTN_W, 1, 0),
			BackgroundColor3 = BTN_DIM,
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
			selectedId = cat.id
			renderCategory(selectedId)
		end)
	end
end

local function refreshEquipped()
	for _, cat in ipairs(INVENTORY_CATEGORIES) do
		readEquippedFromAttr(cat.slot)
	end
	if panel.Visible and selectedId then
		renderCategory(selectedId)
	end
end

local function openInv()
	guiPanel.Enabled = true
	overlay.Visible = true
	panel.Visible = true

	if not next(categoryButtons) then
		buildCategoryButtons()
	end
	if not selectedId then
		selectedId = INVENTORY_CATEGORIES[1] and INVENTORY_CATEGORIES[1].id or "Trails"
	end

	refreshEquipped()
end

local function closeInv()
	panel.Visible = false
	overlay.Visible = false
	guiPanel.Enabled = false
end

invBtn.MouseButton1Click:Connect(function()
	if panel.Visible then closeInv() else openInv() end
end)

closeBtn.MouseButton1Click:Connect(closeInv)

overlay.MouseButton1Click:Connect(function()
	local pos = UserInputService:GetMouseLocation()
	local absPos = panel.AbsolutePosition
	local absSize = panel.AbsoluteSize
	local inside =
		pos.X >= absPos.X and pos.X <= (absPos.X + absSize.X) and
		pos.Y >= absPos.Y and pos.Y <= (absPos.Y + absSize.Y)
	if not inside then closeInv() end
end)

player.AttributeChanged:Connect(function(attrName)
	if typeof(attrName) ~= "string" then return end
	if attrName:sub(1,9) ~= "Equipped_" then
		if panel.Visible and selectedId and attrName:sub(1,6) == "Owned_" then
			renderCategory(selectedId)
		end
		return
	end

	local slot = attrName:sub(10)
	if not slot or slot == "" then return end

	readEquippedFromAttr(slot)
	pendingOverride[slot] = nil
	unlockSlot(slot)

	if panel.Visible and selectedId then
		renderCategory(selectedId)
	end
end)

player.CharacterAdded:Connect(function()
	if panel.Visible then
		refreshEquipped()
	end
end)

-- ===== INIT =====
-- Load premium ids, then build trails items list once.
fetchPremiumTrails()
INVENTORY_CATEGORIES[1].items = buildTrailsItems()

closeInv()

