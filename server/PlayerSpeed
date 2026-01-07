-- ServerScriptService/PlayerSpeed
local Players = game:GetService("Players")

local DEFAULT_SPEED = 20

local function applySpeed(humanoid, speed)
	if humanoid and humanoid.Parent and humanoid.Health > 0 then
		humanoid.WalkSpeed = speed
	end
end

Players.PlayerAdded:Connect(function(player)
	-- You can change this per-player later (VIP/skills) by setting this attribute elsewhere
	if player:GetAttribute("BaseWalkSpeed") == nil then
		player:SetAttribute("BaseWalkSpeed", DEFAULT_SPEED)
	end

	player.CharacterAdded:Connect(function(char)
		local humanoid = char:WaitForChild("Humanoid", 10)
		if not humanoid then return end

		local function desiredSpeed()
			return player:GetAttribute("BaseWalkSpeed") or DEFAULT_SPEED
		end

		-- Apply immediately + after a couple delays (covers load timing weirdness)
		applySpeed(humanoid, desiredSpeed())
		task.delay(0.25, function() applySpeed(humanoid, desiredSpeed()) end)
		task.delay(1.00, function() applySpeed(humanoid, desiredSpeed()) end)

		-- If something tries to change it back to 16, force it back
		humanoid:GetPropertyChangedSignal("WalkSpeed"):Connect(function()
			local target = desiredSpeed()
			if humanoid.WalkSpeed ~= target then
				-- tiny delay to avoid fights with Roblox internal updates
				task.defer(function()
					applySpeed(humanoid, target)
				end)
			end
		end)

		-- If you change BaseWalkSpeed attribute (VIP/skills), it updates live
		player:GetAttributeChangedSignal("BaseWalkSpeed"):Connect(function()
			applySpeed(humanoid, desiredSpeed())
		end)
	end)
end)
