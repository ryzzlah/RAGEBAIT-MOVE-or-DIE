-- ServerScriptService/ShopServer (Script)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PlayerData = require(script.Parent:WaitForChild("PlayerData"))

-- RemoteEvents
local buyWithCoins = ReplicatedStorage:FindFirstChild("BuyWithCoins")
if not buyWithCoins then
	buyWithCoins = Instance.new("RemoteEvent")
	buyWithCoins.Name = "BuyWithCoins"
	buyWithCoins.Parent = ReplicatedStorage
end

local shopResult = ReplicatedStorage:FindFirstChild("ShopResult")
if not shopResult then
	shopResult = Instance.new("RemoteEvent")
	shopResult.Name = "ShopResult"
	shopResult.Parent = ReplicatedStorage
end

-- Prices + category mapping
-- category must match your profile.Owned keys AND attribute keys (no spaces)
local COIN_ITEMS = {
	Trail_Red  = { price = 220, category = "Trails" },
	Trail_Blue = { price = 180, category = "Trails" },
	Trail_White = { price = 600, category = "Trails" },
	Trail_Yellow = { price = 80, category = "Trails" },
	Trail_Green = { price = 120, category = "Trails" },
	Trail_Orange = { price = 180, category = "Trails" },
	Trail_Pink = { price = 300, category = "Trails" },
	Trail_Teal = { price = 340, category = "Trails" },
	Trail_Purple = { price = 380, category = "Trails" },
	Trail_Magenta = { price = 420, category = "Trails" },
}

local function getCoinsValue(plr: Player)
	local ls = plr:FindFirstChild("leaderstats")
	if not ls then return nil end
	local coins = ls:FindFirstChild("Coins")
	if coins and coins:IsA("IntValue") then
		return coins
	end
	return nil
end

buyWithCoins.OnServerEvent:Connect(function(plr: Player, itemKey)
	if type(itemKey) ~= "string" then return end

	local item = COIN_ITEMS[itemKey]
	if not item then
		shopResult:FireClient(plr, false, "This item isn't available yet.")
		return
	end

	local profile = PlayerData.Get(plr)
	if not profile then
		shopResult:FireClient(plr, false, "Data not loaded yet, try again.")
		return
	end

	local coinsVal = getCoinsValue(plr)
	if not coinsVal then
		shopResult:FireClient(plr, false, "Coins not found.")
		return
	end

	local category = item.category
	local price = tonumber(item.price) or 0
	if price < 0 then price = 0 end

	-- Already owned?
	if PlayerData.IsOwned(plr, category, itemKey) then
		shopResult:FireClient(plr, false, "Owned.")
		return
	end

	-- Can afford?
	if coinsVal.Value < price then
		shopResult:FireClient(plr, false, ("Insufficient coins (%d/%d)"):format(coinsVal.Value, price))
		return
	end

	-- Deduct + grant
	coinsVal.Value -= price

	PlayerData.MarkOwned(plr, category, itemKey)
	PlayerData.Save(plr)

	shopResult:FireClient(plr, true, "Purchase successful!")
end)
