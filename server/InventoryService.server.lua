-- ServerScriptService/InventoryService
-- PURPOSE: Equip + Reapply only (NO monetisation here)
-- Works with:
--   ReplicatedStorage/EquipItem:FireServer(category, itemId, equipBool)
--
-- Requires:
--   ServerStorage/TrollItems/<ToolName> (Tool)
-- Trails can live in multiple folders (see TRAIL_ROOT_NAMES)
--
-- Uses PlayerData:
--   PlayerData.IsOwned(plr, category, itemId)
--   PlayerData.SetEquipped(plr, slotKey, value)
--   PlayerData.Save(plr)
--   PlayerData.Get(plr) -> profile.Equipped
--
-- ALSO supports ownership attributes (shop/grants):
--   Owned_<Category>_<ItemId> = true

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local Players = game:GetService("Players")

local PlayerData = require(script.Parent:WaitForChild("PlayerData"))

-- RemoteEvent: EquipItem(category, itemId, equipBool)
local EquipItem = ReplicatedStorage:FindFirstChild("EquipItem")
if not EquipItem then
	EquipItem = Instance.new("RemoteEvent")
	EquipItem.Name = "EquipItem"
	EquipItem.Parent = ReplicatedStorage
end

-- Roots
local TOOLS_ROOT = ServerStorage:WaitForChild("TrollItems")

-- Put your actual folder names here.
-- From your screenshot you have: "Trails" and "Robux_Trails"
local TRAIL_ROOT_NAMES = {
	"Trails",
	"Robux_Trails",
	-- "RobuxTrails",
	-- "PremiumTrails",
}

local TRAIL_ROOTS = {}
for _, name in ipairs(TRAIL_ROOT_NAMES) do
	local folder = ServerStorage:FindFirstChild(name)
	if folder and folder:IsA("Folder") then
		table.insert(TRAIL_ROOTS, folder)
	end
end

local function findTrailFolder(trailId: string): Folder?
	for _, root in ipairs(TRAIL_ROOTS) do
		local f = root:FindFirstChild(trailId)
		if f and f:IsA("Folder") then
			return f
		end
	end
	return nil
end

-- ========= Ownership =========
local function ownedAttrName(category: string, itemId: string): string
	return ("Owned_%s_%s"):format(category, itemId)
end

local function isOwned(plr: Player, category: string, itemId: string): boolean
	-- Attribute truth (shop/grants) wins immediately
	if plr:GetAttribute(ownedAttrName(category, itemId)) == true then
		return true
	end
	-- Fallback to PlayerData
	local ok, res = pcall(function()
		return PlayerData.IsOwned(plr, category, itemId)
	end)
	return ok and res == true
end

-- ========= Helpers =========
local function setEquipped(plr: Player, slotKey: string, value: any): boolean
	local ok = false
	local success, err = pcall(function()
		ok = PlayerData.SetEquipped(plr, slotKey, value)
		if ok then
			PlayerData.Save(plr)
		end
	end)
	if not success then
		warn("[InventoryService] SetEquipped failed:", err)
	end
	return ok == true
end

local function getBackPart(char: Model): BasePart?
	return char:FindFirstChild("UpperTorso")
		or char:FindFirstChild("Torso")
		or char:FindFirstChild("HumanoidRootPart")
end

-- ========= Troll Items (Tools) =========
local function removeExistingTrollTools(plr: Player)
	local backpack = plr:FindFirstChildOfClass("Backpack")
	if backpack then
		for _, t in ipairs(backpack:GetChildren()) do
			if t:IsA("Tool") and TOOLS_ROOT:FindFirstChild(t.Name) then
				t:Destroy()
			end
		end
	end

	local char = plr.Character
	if char then
		for _, t in ipairs(char:GetChildren()) do
			if t:IsA("Tool") and TOOLS_ROOT:FindFirstChild(t.Name) then
				t:Destroy()
			end
		end
	end
end

local function giveTool(plr: Player, itemId: string): boolean
	local template = TOOLS_ROOT:FindFirstChild(itemId)
	if not template or not template:IsA("Tool") then
		warn("[InventoryService] Missing Tool template:", itemId, "in ServerStorage/TrollItems")
		return false
	end

	local backpack = plr:FindFirstChildOfClass("Backpack")
	if not backpack then
		warn("[InventoryService] No Backpack for", plr.Name)
		return false
	end

	removeExistingTrollTools(plr)
	template:Clone().Parent = backpack
	return true
end

-- ========= Trails =========
local function removeExistingTrail(char: Model)
	for _, obj in ipairs(char:GetChildren()) do
		if obj:IsA("Trail") and obj.Name == "EquippedTrail" then
			obj:Destroy()
		end
	end
	for _, d in ipairs(char:GetDescendants()) do
		if d:IsA("Attachment") and (d.Name == "TrailBack_A0" or d.Name == "TrailBack_A1") then
			d:Destroy()
		end
	end
end

local function equipBackTrail(plr: Player, trailId: string): boolean
	local char = plr.Character
	if not char then return false end

	local backPart = getBackPart(char)
	if not backPart then
		warn("[InventoryService] No back part to attach trail for", plr.Name)
		return false
	end

	local templateFolder = findTrailFolder(trailId)
	if not templateFolder then
		warn(("[InventoryService] Missing trail folder '%s' (searched: %s)")
			:format(trailId, table.concat(TRAIL_ROOT_NAMES, ", ")))
		return false
	end

	local templateTrail = templateFolder:FindFirstChildWhichIsA("Trail", true)
	if not templateTrail then
		warn("[InventoryService] No Trail object found inside:", templateFolder:GetFullName())
		return false
	end

	removeExistingTrail(char)

	local a0 = Instance.new("Attachment")
	a0.Name = "TrailBack_A0"
	a0.Position = Vector3.new(0, 0.8, -0.35)
	a0.Parent = backPart

	local a1 = Instance.new("Attachment")
	a1.Name = "TrailBack_A1"
	a1.Position = Vector3.new(0, -0.2, -0.35)
	a1.Parent = backPart

	local trail = templateTrail:Clone()
	trail.Name = "EquippedTrail"
	trail.Attachment0 = a0
	trail.Attachment1 = a1
	trail.Parent = char

	return true
end

local function unequipTrail(plr: Player): boolean
	local char = plr.Character
	if char then
		removeExistingTrail(char)
	end
	return true
end

-- ========= Equip handling =========
EquipItem.OnServerEvent:Connect(function(plr: Player, category: string, itemId: string, equip: boolean)
	if type(category) ~= "string" or type(itemId) ~= "string" or type(equip) ~= "boolean" then
		warn("[InventoryService] Bad args from", plr.Name, category, itemId, equip)
		return
	end

	category = category:gsub("%s+", "")

	-- Troll Items
	if category == "TrollItems" then
		if not isOwned(plr, "TrollItems", itemId) then
			warn("[InventoryService] Tried to equip unowned TrollItem:", plr.Name, itemId)
			return
		end

		if equip then
			if setEquipped(plr, "TrollItem", itemId) then
				giveTool(plr, itemId)
			end
		else
			setEquipped(plr, "TrollItem", nil)
			removeExistingTrollTools(plr)
		end
		return
	end

	-- Trails
	if category == "Trails" then
		if not isOwned(plr, "Trails", itemId) then
			warn("[InventoryService] Tried to equip unowned Trail:", plr.Name, itemId)
			return
		end

		if equip then
			if setEquipped(plr, "Trail", itemId) then
				equipBackTrail(plr, itemId)
			end
		else
			setEquipped(plr, "Trail", nil)
			unequipTrail(plr)
		end
		return
	end

	warn("[InventoryService] Unsupported category:", category, "from", plr.Name)
end)

-- ========= Reapply on respawn =========
local function reapplyFor(plr: Player)
	local profile
	local ok = pcall(function()
		profile = PlayerData.Get(plr)
	end)
	if not ok or not profile or not profile.Equipped then return end

	local troll = profile.Equipped.TrollItem
	if type(troll) == "string" and troll ~= "" then
		giveTool(plr, troll)
	end

	local tr = profile.Equipped.Trail
	if type(tr) == "string" and tr ~= "" then
		equipBackTrail(plr, tr)
	end
end

Players.PlayerAdded:Connect(function(plr)
	plr.CharacterAdded:Connect(function()
		task.wait(0.25)
		reapplyFor(plr)
	end)
end)

-- Studio test
for _, plr in ipairs(Players:GetPlayers()) do
	if plr.Parent == Players then
		task.defer(function()
			if plr.Character then
				reapplyFor(plr)
			end
		end)
	end
end
