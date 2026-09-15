--[[
	WeaponService
	Fabrique les 25 armes sous forme de Tool entierement procedural (aucun
	asset a uploader), distribue l'equipement et fait autorite sur les
	munitions : reservoir, cadence et rechargement sont valides cote serveur.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local WaterWars = ReplicatedStorage:WaitForChild("WaterWars")
local Config = WaterWars:WaitForChild("Config")
local Shared = WaterWars:WaitForChild("Shared")

local GameConfig = require(Config:WaitForChild("GameConfig"))
local Weapons = require(Config:WaitForChild("Weapons"))
local Net = require(Shared:WaitForChild("Net"))

local DataService = require(script.Parent:WaitForChild("DataService"))

local WeaponService = {}

-- ammoState[player] = { [weaponId] = { ammo, reloading, lastShot, reloadToken } }
local ammoState = {}

-- ------------------------------------------------------------------ modele

local function weld(part, handle)
	local constraint = Instance.new("WeldConstraint")
	constraint.Part0 = handle
	constraint.Part1 = part
	constraint.Parent = part
end

local function makePart(name, size, cframe, color, material, parent)
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.CFrame = cframe
	part.Color = color
	part.Material = material
	part.Anchored = false
	part.CanCollide = false
	part.CanQuery = false
	part.Massless = true
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = parent
	return part
end

--- Assemble le modele 3D d'une arme a partir de ses dimensions.
function WeaponService.BuildTool(weapon)
	local model = weapon.model
	local barrelLength = model.barrel
	local thickness = model.thick
	local tankScale = model.tank

	local tool = Instance.new("Tool")
	tool.Name = weapon.name
	tool.RequiresHandle = true
	tool.CanBeDropped = false
	tool.ToolTip = weapon.desc
	tool:SetAttribute("WeaponId", weapon.id)
	tool:SetAttribute("Category", weapon.category)
	-- Position de l'arme dans la main droite.
	tool.Grip = CFrame.new(0, -0.25, 0.35) * CFrame.Angles(math.rad(-6), 0, 0)

	-- La poignee : c'est elle qui est tenue par le personnage.
	local handle = Instance.new("Part")
	handle.Name = "Handle"
	handle.Size = Vector3.new(thickness * 1.1, 1.5, thickness * 1.2)
	handle.CFrame = CFrame.new(0, 0, 0)
	handle.Color = Color3.fromRGB(45, 48, 56)
	handle.Material = Enum.Material.SmoothPlastic
	handle.Anchored = false
	handle.CanCollide = false
	handle.CanQuery = false
	handle.Massless = true
	handle.TopSurface = Enum.SurfaceType.Smooth
	handle.BottomSurface = Enum.SurfaceType.Smooth
	handle.Parent = tool

	-- Corps principal, aligne sur -Z (la direction dans laquelle l'arme pointe).
	local body = makePart(
		"Body",
		Vector3.new(thickness * 1.25, thickness * 1.35, barrelLength * 0.62),
		CFrame.new(0, 0.95, -barrelLength * 0.2),
		weapon.color,
		Enum.Material.SmoothPlastic,
		tool
	)
	weld(body, handle)

	-- Canon.
	local barrel = makePart(
		"Barrel",
		Vector3.new(barrelLength * 0.78, thickness * 0.78, thickness * 0.78),
		CFrame.new(0, 1.0, -barrelLength * 0.62) * CFrame.Angles(0, math.rad(90), math.rad(90)),
		weapon.accent,
		Enum.Material.Metal,
		tool
	)
	barrel.Shape = Enum.PartType.Cylinder
	weld(barrel, handle)

	-- Buse lumineuse : repere visuel de la sortie d'eau.
	local nozzle = makePart(
		"Nozzle",
		Vector3.new(thickness * 0.5, thickness * 0.95, thickness * 0.95),
		CFrame.new(0, 1.0, -barrelLength * 1.0) * CFrame.Angles(0, math.rad(90), math.rad(90)),
		weapon.trail,
		Enum.Material.Neon,
		tool
	)
	nozzle.Shape = Enum.PartType.Cylinder
	nozzle.CastShadow = false
	weld(nozzle, handle)

	-- Reservoir d'eau, monte sur le dessus.
	local tank = makePart(
		"Tank",
		Vector3.new(barrelLength * 0.42 * tankScale, thickness * 1.5 * tankScale, thickness * 1.5 * tankScale),
		CFrame.new(0, 1.05 + thickness * 1.1, barrelLength * 0.12) * CFrame.Angles(0, math.rad(90), math.rad(90)),
		Color3.fromRGB(150, 225, 255),
		Enum.Material.Glass,
		tool
	)
	tank.Shape = Enum.PartType.Cylinder
	tank.Transparency = 0.35
	weld(tank, handle)

	local water = makePart(
		"TankWater",
		Vector3.new(barrelLength * 0.38 * tankScale, thickness * 1.15 * tankScale, thickness * 1.15 * tankScale),
		tank.CFrame,
		Color3.fromRGB(60, 170, 235),
		Enum.Material.SmoothPlastic,
		tool
	)
	water.Shape = Enum.PartType.Cylinder
	water.Transparency = 0.15
	weld(water, handle)

	-- Garde et crosse pour donner du volume.
	local guard = makePart(
		"Guard",
		Vector3.new(thickness * 0.4, 0.55, thickness * 1.3),
		CFrame.new(0, 0.35, -thickness * 0.5),
		Color3.fromRGB(38, 40, 48),
		Enum.Material.SmoothPlastic,
		tool
	)
	weld(guard, handle)

	if weapon.category == "Sniper" then
		local scope = makePart(
			"Scope",
			Vector3.new(barrelLength * 0.3, thickness * 0.55, thickness * 0.55),
			CFrame.new(0, 1.05 + thickness * 1.9, -barrelLength * 0.1) * CFrame.Angles(0, math.rad(90), math.rad(90)),
			Color3.fromRGB(28, 30, 36),
			Enum.Material.Metal,
			tool
		)
		scope.Shape = Enum.PartType.Cylinder
		weld(scope, handle)
	elseif weapon.category == "Heavy" then
		local shroud = makePart(
			"Shroud",
			Vector3.new(thickness * 1.9, thickness * 1.9, barrelLength * 0.35),
			CFrame.new(0, 1.0, -barrelLength * 0.5),
			Color3.fromRGB(70, 74, 84),
			Enum.Material.DiamondPlate,
			tool
		)
		weld(shroud, handle)
	elseif weapon.category == "Launcher" then
		local drum = makePart(
			"Drum",
			Vector3.new(thickness * 1.6, thickness * 2.1, thickness * 2.1),
			CFrame.new(0, 1.0, barrelLength * 0.05) * CFrame.Angles(0, math.rad(90), math.rad(90)),
			weapon.color,
			Enum.Material.SmoothPlastic,
			tool
		)
		drum.Shape = Enum.PartType.Cylinder
		weld(drum, handle)
	end

	-- Point de sortie des projectiles, lu par le client pour les effets.
	local muzzle = Instance.new("Attachment")
	muzzle.Name = "Muzzle"
	muzzle.CFrame = CFrame.new(0, 1.0, -barrelLength * 1.05)
	muzzle.Parent = handle

	return tool
end

-- ----------------------------------------------------------------- etat

local function stateFor(player)
	local state = ammoState[player]
	if not state then
		state = {}
		ammoState[player] = state
	end
	return state
end

local function entryFor(player, weapon)
	local state = stateFor(player)
	local entry = state[weapon.id]
	if not entry then
		entry = { ammo = weapon.tankSize, reloading = false, lastShot = 0, reloadToken = 0 }
		state[weapon.id] = entry
	end
	return entry
end

--- Envoie l'etat des munitions de l'arme tenue au client.
function WeaponService.PushAmmo(player)
	local weapon = WeaponService.GetEquipped(player)
	if not weapon then
		Net.Event("AmmoUpdate"):FireClient(player, nil, 0, 0, false)
		return
	end
	local entry = entryFor(player, weapon)
	Net.Event("AmmoUpdate"):FireClient(player, weapon.id, entry.ammo, weapon.tankSize, entry.reloading)
end

--- Arme actuellement tenue par le joueur, ou nil.
function WeaponService.GetEquipped(player)
	local character = player.Character
	if not character then
		return nil
	end
	local tool = character:FindFirstChildOfClass("Tool")
	if not tool then
		return nil
	end
	local id = tool:GetAttribute("WeaponId")
	if type(id) ~= "string" then
		return nil
	end
	return Weapons.Get(id)
end

function WeaponService.GetAmmo(player, weapon)
	return entryFor(player, weapon).ammo
end

function WeaponService.IsReloading(player, weapon)
	return entryFor(player, weapon).reloading
end

--- Lance un rechargement. Renvoie true s'il a effectivement demarre.
function WeaponService.Reload(player, weapon)
	local entry = entryFor(player, weapon)
	if entry.reloading or entry.ammo >= weapon.tankSize then
		return false
	end
	entry.reloading = true
	entry.reloadToken = entry.reloadToken + 1
	local token = entry.reloadToken
	WeaponService.PushAmmo(player)

	task.delay(weapon.reloadTime, function()
		-- Un changement d'arme ou une mort annule le rechargement en cours.
		if entry.reloadToken ~= token then
			return
		end
		entry.reloading = false
		entry.ammo = weapon.tankSize
		if player.Parent then
			WeaponService.PushAmmo(player)
		end
	end)
	return true
end

--- Verifie cadence + munitions et consomme l'eau. Renvoie (autorise, raison).
function WeaponService.TryConsume(player, weapon)
	local entry = entryFor(player, weapon)
	if entry.reloading then
		return false, "reloading"
	end

	local now = os.clock()
	local minimumDelay = (1 / weapon.fireRate) * GameConfig.FireRateTolerance
	if now - entry.lastShot < minimumDelay then
		return false, "ratelimit"
	end

	local cost = weapon.tankCost * weapon.burst
	if entry.ammo < cost then
		WeaponService.Reload(player, weapon)
		return false, "empty"
	end

	entry.lastShot = now
	entry.ammo = entry.ammo - cost
	if entry.ammo < cost then
		-- Rechargement automatique des que le reservoir ne suffit plus.
		WeaponService.Reload(player, weapon)
	else
		WeaponService.PushAmmo(player)
	end
	return true, nil
end

--- Remet tous les reservoirs a plein (apparition, station de recharge).
function WeaponService.RefillAll(player)
	local state = stateFor(player)
	for id, entry in pairs(state) do
		local weapon = Weapons.Get(id)
		if weapon then
			entry.ammo = weapon.tankSize
			entry.reloading = false
			entry.reloadToken = entry.reloadToken + 1
		end
	end
	WeaponService.PushAmmo(player)
end

--- Recharge progressive pres d'une station. Renvoie true si de l'eau a ete ajoutee.
function WeaponService.AddWater(player, amount)
	local weapon = WeaponService.GetEquipped(player)
	if not weapon then
		return false
	end
	local entry = entryFor(player, weapon)
	if entry.ammo >= weapon.tankSize then
		return false
	end
	entry.ammo = math.min(weapon.tankSize, entry.ammo + amount)
	entry.reloading = false
	entry.reloadToken = entry.reloadToken + 1
	WeaponService.PushAmmo(player)
	return true
end

--- Vide le sac et la main du joueur.
function WeaponService.ClearTools(player)
	local backpack = player:FindFirstChildOfClass("Backpack")
	if backpack then
		for _, child in ipairs(backpack:GetChildren()) do
			if child:IsA("Tool") then
				child:Destroy()
			end
		end
	end
	local character = player.Character
	if character then
		for _, child in ipairs(character:GetChildren()) do
			if child:IsA("Tool") then
				child:Destroy()
			end
		end
	end
end

--- Donne au joueur les deux armes de son equipement et remplit les reservoirs.
function WeaponService.GiveLoadout(player)
	local profile = DataService.Get(player)
	local backpack = player:FindFirstChildOfClass("Backpack")
	if not profile or not backpack then
		return
	end

	WeaponService.ClearTools(player)
	ammoState[player] = {}

	local order = { profile.loadout.primary, profile.loadout.secondary }
	local firstTool = nil
	for _, id in ipairs(order) do
		local weapon = Weapons.Get(id)
		if weapon then
			local tool = WeaponService.BuildTool(weapon)
			tool.Parent = backpack
			entryFor(player, weapon)
			if not firstTool then
				firstTool = tool
			end
		end
	end

	-- L'arme principale est mise en main : le joueur peut tirer immediatement.
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if firstTool and humanoid and humanoid.Health > 0 then
		humanoid:EquipTool(firstTool)
	end

	WeaponService.PushAmmo(player)
end

function WeaponService.Start()
	Net.Event("RequestReload").OnServerEvent:Connect(function(player)
		local weapon = WeaponService.GetEquipped(player)
		if weapon then
			WeaponService.Reload(player, weapon)
		end
	end)

	Net.Event("RequestEquip").OnServerEvent:Connect(function(player, slot, weaponId)
		if type(slot) ~= "string" or type(weaponId) ~= "string" then
			return
		end
		local success, message = DataService.SetLoadout(player, slot, weaponId)
		Net.Event("Notify"):FireClient(player, message, success and "good" or "bad")
		if success then
			-- Applique immediatement si le joueur est vivant.
			local character = player.Character
			local humanoid = character and character:FindFirstChildOfClass("Humanoid")
			if humanoid and humanoid.Health > 0 then
				WeaponService.GiveLoadout(player)
			end
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		ammoState[player] = nil
	end)
end

return WeaponService
