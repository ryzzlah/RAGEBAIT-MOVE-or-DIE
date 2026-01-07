-- ServerScriptService/MonetisationGrants.server.lua
-- SINGLE SOURCE OF TRUTH for:
--  - Trail Pack GamePass grants
--  - Extra Life GamePass ownership flag
--  - Small Revive Dev Product receipts (ReviveTokens)
-- IMPORTANT: This script is the ONLY place with MarketplaceService.ProcessReceipt.

local Players = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MarketplaceService = game:GetService("MarketplaceService")

-- =========================
-- YOUR IDs
-- =========================
local TRAIL_PACK_PASS_ID   = 1651928187
local EXTRA_LIFE_PASS_ID   = 1652150771
local SMALL_REVIVE_PRODUCT = 3498314947

-- Folder holding premium trails
local PREMIUM_FOLDER_NAME = "Robux_Trails"

-- Optional PlayerData (safe)
local PlayerData
pcall(function()
	PlayerData = require(script.Parent:WaitForChild("PlayerData"))
end)

-- Remote ping so RoundManager can instantly re-check revive availability after purchases
local reviveRemote = ReplicatedStorage:FindFirstChild("ReviveRemote")
if not reviveRemote then
	reviveRemote = Instance.new("RemoteEvent")
	reviveRemote.Name = "ReviveRemote"
	reviveRemote.Parent = ReplicatedStorage
end

local premiumFolder = ServerStorage:WaitForChild(PREMIUM_FOLDER_NAME)

local function safePrint(...)
	print("[MonetisationGrants]", ...)
end

local function ownsPass(plr: Player, passId: number): boolean
	if not passId or passId == 0 then return false end
	local ok, res = pcall(MarketplaceService.UserOwnsGamePassAsync, MarketplaceService, plr.UserId, passId)
	return ok and res == true
end

local function safeSetOwned(plr: Player, category: string, itemId: string)
	-- 1) Save if PlayerData exists
	if PlayerData and PlayerData.SetOwned then
		pcall(function()
			PlayerData.SetOwned(plr, category, itemId, true)
		end)
	end

	-- 2) Mirror attribute for UI
	plr:SetAttribute(("Owned_%s_%s"):format(category, itemId), true)

	-- 3) Save
	if PlayerData and PlayerData.Save then
		pcall(function()
			PlayerData.Save(plr)
		end)
	end
end

local function grantTrailPack(plr: Player)
	local kids = premiumFolder:GetChildren()
	if #kids == 0 then
		warn("[MonetisationGrants] No trails found in ServerStorage/" .. PREMIUM_FOLDER_NAME)
		return
	end

	for _, folder in ipairs(kids) do
		if folder:IsA("Folder") then
			local itemId = folder.Name
			safeSetOwned(plr, "Trails", itemId)

			-- optional stripped alias
			if itemId:sub(1, 6) == "Trail_" then
				local stripped = itemId:sub(7)
				if stripped and stripped ~= "" then
					safeSetOwned(plr, "Trails", stripped)
				end
			end
		end
	end

	plr:SetAttribute("HasTrailPackPass", true)
	safePrint(("Granted Trail Pack to %s (%d items)"):format(plr.Name, #kids))
end

local function syncPassFlags(plr: Player)
	local hasTrailPack = ownsPass(plr, TRAIL_PACK_PASS_ID)
	local hasExtraLife = ownsPass(plr, EXTRA_LIFE_PASS_ID)

	plr:SetAttribute("HasTrailPackPass", hasTrailPack)
	plr:SetAttribute("HasExtraLifePass", hasExtraLife)

	if hasTrailPack then
		grantTrailPack(plr)
	end

	if hasExtraLife then
		safePrint(("Extra Life pass detected for %s"):format(plr.Name))
	end
end

-- ============
-- JOIN SYNC
-- ============
Players.PlayerAdded:Connect(function(plr)
	task.defer(function()
		-- init tokens attribute if absent
		if plr:GetAttribute("ReviveTokens") == nil then
			plr:SetAttribute("ReviveTokens", 0)
		end
		syncPassFlags(plr)
	end)
end)

for _, plr in ipairs(Players:GetPlayers()) do
	task.defer(function()
		if plr:GetAttribute("ReviveTokens") == nil then
			plr:SetAttribute("ReviveTokens", 0)
		end
		syncPassFlags(plr)
	end)
end

-- ============
-- PASS PURCHASE FINISHED
-- ============
MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(plr, passId, purchased)
	if not purchased then return end

	if passId == TRAIL_PACK_PASS_ID then
		grantTrailPack(plr)
		return
	end

	if passId == EXTRA_LIFE_PASS_ID then
		plr:SetAttribute("HasExtraLifePass", true)
		safePrint(("Extra Life purchased by %s"):format(plr.Name))
		-- if they're currently dead in-match, tell client to refresh UI
		reviveRemote:FireClient(plr, "Refresh")
		return
	end
end)

-- ============
-- DEV PRODUCT RECEIPTS (ONLY HERE)
-- ============
MarketplaceService.ProcessReceipt = function(receiptInfo)
	local plr = Players:GetPlayerByUserId(receiptInfo.PlayerId)
	if not plr then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	if receiptInfo.ProductId == SMALL_REVIVE_PRODUCT then
		local current = tonumber(plr:GetAttribute("ReviveTokens")) or 0
		plr:SetAttribute("ReviveTokens", current + 1)

		safePrint(("Granted +1 ReviveToken to %s (now %d)"):format(plr.Name, current + 1))

		-- If they're currently eliminated in a running match, ping UI/server logic to re-check
		reviveRemote:FireClient(plr, "Refresh")

		return Enum.ProductPurchaseDecision.PurchaseGranted
	end

	return Enum.ProductPurchaseDecision.PurchaseGranted
end
