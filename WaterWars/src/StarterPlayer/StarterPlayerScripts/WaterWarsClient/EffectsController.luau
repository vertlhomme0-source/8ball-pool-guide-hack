--[[
	EffectsController
	Tout le visuel du combat cote client : gouttes d'eau, gerbes d'impact,
	flaques au sol et lueur de canon.

	Les projectiles affiches ici sont purement decoratifs (le serveur fait
	autorite sur les degats), mais ils suivent exactement la meme physique, ce
	qui donne une visee coherente.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local WaterWars = ReplicatedStorage:WaitForChild("WaterWars")
local Config = WaterWars:WaitForChild("Config")
local Shared = WaterWars:WaitForChild("Shared")

local Weapons = require(Config:WaitForChild("Weapons"))
local Net = require(Shared:WaitForChild("Net"))
local Util = require(Shared:WaitForChild("Util"))

local EffectsController = {}

local GRAVITY = 196.2
local MAX_DROPLETS = 260
local SMOKE_TEXTURE = "rbxasset://textures/particles/smoke_main.dds"

local localPlayer = Players.LocalPlayer
local rng = Random.new()

local container = nil
local pool = {}
local active = {}
local raycastParams = RaycastParams.new()

-- ----------------------------------------------------------------- gouttes

local function newDroplet()
	local part = Instance.new("Part")
	part.Name = "Droplet"
	part.Shape = Enum.PartType.Ball
	part.Material = Enum.Material.Neon
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	return part
end

local function acquire()
	local part = table.remove(pool)
	if not part then
		part = newDroplet()
	end
	part.Parent = container
	return part
end

local function release(part)
	part.Parent = nil
	if #pool < MAX_DROPLETS then
		table.insert(pool, part)
	else
		part:Destroy()
	end
end

-- ---------------------------------------------------------------- impacts

--- Gerbe d'eau + flaque a l'endroit de l'impact.
function EffectsController.Impact(position, normal, weapon, hitCharacter)
	if not container then
		return
	end
	local anchor = Instance.new("Part")
	anchor.Name = "Impact"
	anchor.Size = Vector3.new(0.2, 0.2, 0.2)
	anchor.CFrame = CFrame.new(position)
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.CastShadow = false
	anchor.Transparency = 1
	anchor.Parent = container

	local attachment = Instance.new("Attachment")
	attachment.Parent = anchor

	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = SMOKE_TEXTURE
	emitter.Color = ColorSequence.new(weapon.trail, weapon.color)
	emitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, hitCharacter and 1.8 or 1.2),
		NumberSequenceKeypoint.new(1, 0),
	})
	emitter.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.25),
		NumberSequenceKeypoint.new(1, 1),
	})
	emitter.Lifetime = NumberRange.new(0.25, 0.5)
	emitter.Speed = NumberRange.new(9, 18)
	emitter.SpreadAngle = Vector2.new(45, 45)
	emitter.Rate = 0
	emitter.Rotation = NumberRange.new(0, 360)
	emitter.LightEmission = 0.35
	emitter.Enabled = false
	emitter.Parent = attachment
	emitter:Emit(hitCharacter and 22 or 14)

	Debris:AddItem(anchor, 1.4)

	-- Flaque plaquee sur la surface touchee, qui s'estompe.
	if not hitCharacter then
		local puddle = Instance.new("Part")
		puddle.Name = "Puddle"
		puddle.Shape = Enum.PartType.Cylinder
		local radius = math.max(1.4, weapon.radius * 4 + weapon.splashRadius * 0.12)
		puddle.Size = Vector3.new(0.12, radius, radius)
		puddle.CFrame = CFrame.lookAt(position + normal * 0.06, position + normal * 1.06)
			* CFrame.Angles(0, math.rad(90), 0)
		puddle.Anchored = true
		puddle.CanCollide = false
		puddle.CanQuery = false
		puddle.CanTouch = false
		puddle.CastShadow = false
		puddle.Material = Enum.Material.SmoothPlastic
		puddle.Color = weapon.color
		puddle.Transparency = 0.35
		puddle.Parent = container

		TweenService:Create(puddle, TweenInfo.new(2.2, Enum.EasingStyle.Quad), {
			Transparency = 1,
			Size = Vector3.new(0.12, radius * 1.6, radius * 1.6),
		}):Play()
		Debris:AddItem(puddle, 2.4)
	end
end

--- Eclair lumineux a la sortie du canon.
function EffectsController.MuzzleFlash(tool, weapon)
	local handle = tool and tool:FindFirstChild("Handle")
	if not handle then
		return
	end
	local muzzle = handle:FindFirstChild("Muzzle")
	if not muzzle or not muzzle:IsA("Attachment") then
		return
	end
	local flash = Instance.new("PointLight")
	flash.Color = weapon.trail
	flash.Brightness = 4
	flash.Range = 12
	flash.Parent = handle
	Debris:AddItem(flash, 0.08)
end

-- ------------------------------------------------------------ projectiles

--- Cree les gouttes visibles d'un tir.
function EffectsController.SpawnVolley(weapon, origin, direction, chargeRatio)
	if not container then
		return
	end
	local scale = 1 + (weapon.chargeBonus - 1) * (chargeRatio or 0) * 0.3
	for _ = 1, weapon.pellets do
		if #active >= MAX_DROPLETS then
			break
		end
		local unit = Util.ApplySpread(direction, weapon.spread, rng)
		local part = acquire()
		local size = weapon.radius * 2 * scale
		part.Size = Vector3.new(size, size, size)
		part.Color = weapon.trail
		part.Transparency = 0.15
		part.CFrame = CFrame.new(origin)
		table.insert(active, {
			part = part,
			position = origin,
			velocity = unit * weapon.speed,
			gravity = weapon.gravity,
			expires = os.clock() + weapon.lifetime,
		})
	end
end

local function stepDroplets(deltaTime)
	if #active == 0 then
		return
	end
	local character = localPlayer.Character
	raycastParams.FilterType = Enum.RaycastFilterType.Exclude
	raycastParams.FilterDescendantsInstances = { container, character }
	raycastParams.IgnoreWater = true

	local currentTime = os.clock()
	local index = 1
	while index <= #active do
		local droplet = active[index]
		droplet.velocity = droplet.velocity - Vector3.new(0, GRAVITY * droplet.gravity * deltaTime, 0)
		local nextPosition = droplet.position + droplet.velocity * deltaTime

		local remove = false
		local hit = workspace:Raycast(droplet.position, nextPosition - droplet.position, raycastParams)
		if hit then
			remove = true
		else
			droplet.position = nextPosition
			droplet.part.CFrame = CFrame.new(nextPosition)
			if currentTime >= droplet.expires then
				remove = true
			end
		end

		if remove then
			release(droplet.part)
			active[index] = active[#active]
			active[#active] = nil
		else
			index = index + 1
		end
	end
end

function EffectsController.Start()
	container = Instance.new("Folder")
	container.Name = "WaterWarsEffects"
	container.Parent = workspace

	Net.Event("ProjectileSpawned").OnClientEvent:Connect(function(shooter, weaponId, origin, direction, charge)
		-- Le tireur a deja vu ses propres gouttes au moment du clic.
		if shooter == localPlayer then
			return
		end
		local weapon = Weapons.Get(weaponId)
		if weapon and typeof(origin) == "Vector3" and typeof(direction) == "Vector3" then
			EffectsController.SpawnVolley(weapon, origin, direction, charge)
		end
	end)

	Net.Event("ImpactEffect").OnClientEvent:Connect(function(position, normal, weaponId, hitCharacter)
		local weapon = Weapons.Get(weaponId)
		if not weapon or typeof(position) ~= "Vector3" then
			return
		end
		-- On n'affiche pas les impacts hors de vue : c'est du calcul gratuit.
		local camera = workspace.CurrentCamera
		if camera and (camera.CFrame.Position - position).Magnitude > 320 then
			return
		end
		EffectsController.Impact(position, typeof(normal) == "Vector3" and normal or Vector3.new(0, 1, 0), weapon, hitCharacter == true)
	end)

	RunService.RenderStepped:Connect(function(deltaTime)
		local ok, err = pcall(stepDroplets, math.min(deltaTime, 0.1))
		if not ok then
			warn("[WaterWars] Erreur d'affichage des gouttes : " .. tostring(err))
		end
	end)
end

return EffectsController
