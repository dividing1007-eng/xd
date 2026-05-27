local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Players = game:GetService("Players")

local AbilitySystem = {}
AbilitySystem.__index = AbilitySystem

local ActiveEffects = {}
local PlayerCooldowns = {}

local CONFIG = {
	MaxCastDistance = 150,
	BaseDamage = 35,
	ExplosionRadius = 12,
	CooldownTime = 4.5,
	ProjectileSpeed = 75,
	TagLabel = "ActiveProjectile"
}

local function CreateVFX(position, radius)
	local part = Instance.new("Part")
	part.Anchored = true
	part.CanCollide = false
	part.Shape = Enum.PartType.Ball
	part.Color = Color3.fromRGB(255, 85, 0)
	part.Material = Enum.Material.Neon
	part.Size = Vector3.new(1, 1, 1)
	part.Position = position
	part.Parent = workspace

	local tween = TweenService:Create(part, TweenInfo.new(0.4, Enum.EasingStyle.QuadOut), {
		Size = Vector3.new(radius * 2, radius * 2, radius * 2),
		Transparency = 1
	})
	
	tween.Completed:Connect(function()
		part:Destroy()
	end)
	tween:Play()
end

local function ApplyAoEDamage(caster, center, radius, damage)
	local overlapParams = OverlapParams.new()
	overlapParams.FilterType = Enum.RaycastFilterType.Exclude
	overlapParams.FilterDescendantsInstances = {caster.Character, workspace.CurrentCamera}

	local parts = workspace:GetPartBoundsInRadius(center, radius, overlapParams)
	local processedHumanoids = {}

	for _, part in ipairs(parts) do
		local model = part:FindFirstAncestorOfClass("Model")
		if model then
			local humanoid = model:FindFirstChildOfClass("Humanoid")
			if humanoid and humanoid.Health > 0 and not processedHumanoids[humanoid] then
				processedHumanoids[humanoid] = true
				
				local player = Players:GetPlayerFromCharacter(model)
				if player and player == caster then continue end
				
				humanoid:TakeDamage(damage)
			end
		end
	end
end

local function GetRaycastResult(origin, direction, excludeList)
	local raycastParams = RaycastParams.new()
	raycastParams.FilterType = Enum.RaycastFilterType.Exclude
	raycastParams.FilterDescendantsInstances = excludeList
	raycastParams.IgnoreWater = true
	
	return workspace:Raycast(origin, direction, raycastParams)
end

function AbilitySystem.new(player)
	local self = setmetatable({}, AbilitySystem)
	self.Player = player
	self.Character = player.Character or player.CharacterAdded:Wait()
	
	return self
end

function AbilitySystem:CheckCooldown()
	local userId = self.Player.UserId
	if PlayerCooldowns[userId] and os.clock() - PlayerCooldowns[userId] < CONFIG.CooldownTime then
		return false
	end
	return true
end

function AbilitySystem:SetCooldown()
	local userId = self.Player.UserId
	PlayerCooldowns[userId] = os.clock()
end

function AbilitySystem:CastProjectile(targetPosition)
	if not self.Character or not self.Character:FindFirstChild("HumanoidRootPart") then
		return false
	end

	if not self:CheckCooldown() then
		return false
	end

	local rootPart = self.Character.HumanoidRootPart
	local origin = rootPart.Position + Vector3.new(0, 2, 0)
	local direction = (targetPosition - origin).Unit

	if (targetPosition - origin).Magnitude > CONFIG.MaxCastDistance then
		targetPosition = origin + (direction * CONFIG.MaxCastDistance)
	end

	self:SetCooldown()

	local projectile = Instance.new("Part")
	projectile.Size = Vector3.new(1.5, 1.5, 3)
	projectile.Color = Color3.fromRGB(0, 170, 255)
	projectile.Material = Enum.Material.Neon
	projectile.CanCollide = false
	projectile.CFrame = CFrame.lookAt(origin, targetPosition)
	projectile.Parent = workspace
	
	CollectionService:AddTag(projectile, CONFIG.TagLabel)

	local attachment = Instance.new("Attachment", projectile)
	local linearVelocity = Instance.new("LinearVelocity")
	linearVelocity.MaxForce = math.huge
	linearVelocity.VectorVelocity = direction * CONFIG.ProjectileSpeed
	linearVelocity.Attachment0 = attachment
	linearVelocity.Parent = projectile

	local castData = {
		Projectile = projectile,
		Caster = self.Player,
		StartTime = os.clock(),
		Active = true
	}
	
	table.insert(ActiveEffects, castData)

	task.defer(function()
		local excludeList = {self.Character, projectile}
		local distanceTraveled = 0
		local maxRange = CONFIG.MaxCastDistance

		while castData.Active and projectile.Parent and distanceTraveled < maxRange do
			local currentPos = projectile.Position
			local frameVelocity = linearVelocity.VectorVelocity * task.wait()
			local rayResult = GetRaycastResult(currentPos, frameVelocity, excludeList)

			if rayResult then
				self:Explode(rayResult.Position)
				castData.Active = false
				projectile:Destroy()
				break
			end

			distanceTraveled = distanceTraveled + frameVelocity.Magnitude
		end

		if projectile.Parent and castData.Active then
			self:Explode(projectile.Position)
			projectile:Destroy()
		end
	end)

	return true
end

function AbilitySystem:Explode(position)
	task.spawn(CreateVFX, position, CONFIG.ExplosionRadius)
	task.spawn(ApplyAoEDamage, self.Player, position, CONFIG.ExplosionRadius, CONFIG.BaseDamage)
end

function AbilitySystem:Cleanup()
	local userId = self.Player.UserId
	if PlayerCooldowns[userId] then
		PlayerCooldowns[userId] = nil
	end
	self.Player = nil
	self.Character = nil
end

Players.PlayerRemoving:Connect(function(player)
	if PlayerCooldowns[player.UserId] then
		PlayerCooldowns[player.UserId] = nil
	end
end)

return AbilitySystem
