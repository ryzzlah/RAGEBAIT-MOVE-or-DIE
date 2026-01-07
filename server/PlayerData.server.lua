-- ServerScriptService/PlayerData (ModuleScript)
-- Robust profile load/save + OWNED + EQUIPPED attributes (sanitized attribute NAMES)
-- Provides:
--   PlayerData.MarkOwned(plr, category, itemKey)
--   PlayerData.IsOwned(plr, category, itemKey)
--   PlayerData.SetEquipped(plr, slotKey, itemIdOrNil)
--   PlayerData.Get(plr)
--   PlayerData.Load(plr)
--   PlayerData.Save(plr)

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")

local STORE_NAME = "PlayerProfile_v1"
local store = DataStoreService:GetDataStore(STORE_NAME)

local PlayerData = {}
PlayerData.Profiles = {} -- [userId] = profileTable

local DEFAULT_PROFILE = {
	Owned = {
		Trails = {},
		WinAnims = {},
		DeathAnims = {},
		TrollItems = {},
		Skills = {},
	},
	Equipped = {
		Trail = nil,
		WinAnim = nil,
		DeathAnim = nil,
		TrollItem = nil,
		Skill = nil,
	}
}

-- Map UI-friendly category names to internal keys
local CATEGORY_ALIASES = {
	["Troll Items"] = "TrollItems",
	["Win Emotes"] = "WinAnims",
	["Fall Animations"] = "DeathAnims",
}

local function deepCopy(t)
	local out = {}
	for k, v in pairs(t) do
		out[k] = (type(v) == "table") and deepCopy(v) or v
	end
	return out
end

local function reconcile(default, loaded)
	loaded = loaded or {}
	for k, v in pairs(default) do
		if loaded[k] == nil then
			loaded[k] = (type(v) == "table") and deepCopy(v) or v
		elseif type(v) == "table" and type(loaded[k]) == "table" then
			reconcile(v, loaded[k])
		end
	end
	return loaded
end

-- Attribute NAME segments must be safe (Roblox restriction)
local function sanitizeSegment(s: any): string
	s = tostring(s or "")
	s = s:gsub("[^%w_]", "_")   -- anything not A-Z a-z 0-9 _ becomes _
	s = s:gsub("_+", "_")      -- collapse
	s = s:gsub("^_+", ""):gsub("_+$", "")
	if s == "" then s = "X" end
	return s
end

local function normalizeCategory(category: any): string
	local raw = tostring(category or "")

	if CATEGORY_ALIASES[raw] then
		return CATEGORY_ALIASES[raw]
	end

	-- remove spaces fallback
	local noSpaces = raw:gsub("%s+", "")
	if DEFAULT_PROFILE.Owned[noSpaces] ~= nil then
		return noSpaces
	end

	return raw
end

local function makeOwnedAttrName(category: any, itemKey: any): string
	local cat = sanitizeSegment(normalizeCategory(category))
	local item = sanitizeSegment(itemKey)
	return ("Owned_%s_%s"):format(cat, item)
end

local function makeEquippedAttrName(slotKey: any): string
	local slot = sanitizeSegment(slotKey)
	return ("Equipped_%s"):format(slot)
end

local function clearAttributesByPrefix(plr: Player, prefix: string)
	for name, _ in pairs(plr:GetAttributes()) do
		if typeof(name) == "string" and name:sub(1, #prefix) == prefix then
			plr:SetAttribute(name, nil)
		end
	end
end

local function applyOwnedAttributes(plr: Player, profile)
	clearAttributesByPrefix(plr, "Owned_")

	for category, items in pairs(profile.Owned) do
		if type(items) == "table" then
			for itemKey, owned in pairs(items) do
				if owned == true then
					plr:SetAttribute(makeOwnedAttrName(category, itemKey), true)
				end
			end
		end
	end
end

local function applyEquippedAttributes(plr: Player, profile)
	clearAttributesByPrefix(plr, "Equipped_")

	profile.Equipped = profile.Equipped or {}

	for slotKey, itemId in pairs(profile.Equipped) do
		local attr = makeEquippedAttrName(slotKey)
		if type(itemId) == "string" and itemId ~= "" then
			-- IMPORTANT: attribute VALUE is the real itemId (do not sanitize the value)
			plr:SetAttribute(attr, itemId)
		else
			plr:SetAttribute(attr, "")
		end
	end

	-- Ensure default slots exist as empty strings so UI always has something consistent
	for slotKey, _ in pairs(DEFAULT_PROFILE.Equipped) do
		local attr = makeEquippedAttrName(slotKey)
		if plr:GetAttribute(attr) == nil then
			plr:SetAttribute(attr, "")
		end
	end
end

-- Optional migration of bad datastore category keys like "Troll Items" -> "TrollItems"
local function migrateProfile(profile)
	if type(profile) ~= "table" then return end
	if type(profile.Owned) ~= "table" then return end

	for badKey, goodKey in pairs(CATEGORY_ALIASES) do
		if profile.Owned[badKey] ~= nil then
			profile.Owned[goodKey] = profile.Owned[goodKey] or {}
			for itemKey, owned in pairs(profile.Owned[badKey]) do
				if owned == true then
					profile.Owned[goodKey][itemKey] = true
				end
			end
			profile.Owned[badKey] = nil
		end
	end
end

function PlayerData.Load(plr: Player)
	local key = tostring(plr.UserId)
	local loaded = nil

	local ok, err = pcall(function()
		loaded = store:GetAsync(key)
	end)
	if not ok then
		warn("[PlayerData] Load failed:", err)
		loaded = nil
	end

	local profile = reconcile(DEFAULT_PROFILE, loaded)
	migrateProfile(profile)

	PlayerData.Profiles[plr.UserId] = profile

	applyOwnedAttributes(plr, profile)
	applyEquippedAttributes(plr, profile)

	return profile
end

function PlayerData.Save(plr: Player)
	local profile = PlayerData.Profiles[plr.UserId]
	if not profile then return end

	local key = tostring(plr.UserId)
	local ok, err = pcall(function()
		store:SetAsync(key, profile)
	end)
	if not ok then
		warn("[PlayerData] Save failed:", err)
	end
end

function PlayerData.Get(plr: Player)
	return PlayerData.Profiles[plr.UserId]
end

function PlayerData.MarkOwned(plr: Player, category: any, itemKey: any)
	local profile = PlayerData.Profiles[plr.UserId]
	if not profile then return false end

	local normalized = normalizeCategory(category)

	profile.Owned[normalized] = profile.Owned[normalized] or {}
	profile.Owned[normalized][tostring(itemKey)] = true

	-- Mirror to attribute for client UI
	plr:SetAttribute(makeOwnedAttrName(normalized, itemKey), true)

	return true
end

function PlayerData.IsOwned(plr: Player, category: any, itemKey: any)
	local profile = PlayerData.Profiles[plr.UserId]
	if not profile then return false end

	local normalized = normalizeCategory(category)
	return profile.Owned[normalized] and profile.Owned[normalized][tostring(itemKey)] == true
end

-- ✅ This is what your InventoryService should use now
function PlayerData.SetEquipped(plr: Player, slotKey: any, itemId: any)
	local profile = PlayerData.Profiles[plr.UserId]
	if not profile then return false end

	profile.Equipped = profile.Equipped or {}
	local slot = tostring(slotKey)

	if type(itemId) == "string" and itemId ~= "" then
		profile.Equipped[slot] = itemId
	else
		profile.Equipped[slot] = nil
	end

	-- Mirror instantly so UI reads correct state on join + immediately after equip
	local attr = makeEquippedAttrName(slot)
	plr:SetAttribute(attr, (type(itemId) == "string" and itemId) or "")

	return true
end

-- Auto load/save
Players.PlayerAdded:Connect(function(plr)
	PlayerData.Load(plr)
end)

Players.PlayerRemoving:Connect(function(plr)
	PlayerData.Save(plr)
	PlayerData.Profiles[plr.UserId] = nil
end)

game:BindToClose(function()
	for _, plr in ipairs(Players:GetPlayers()) do
		PlayerData.Save(plr)
	end
end)

return PlayerData
