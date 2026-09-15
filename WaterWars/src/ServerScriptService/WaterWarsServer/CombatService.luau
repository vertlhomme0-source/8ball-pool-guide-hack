--[[
	CombatService
	Simulation des projectiles et application des degats, entierement cote
	serveur : le client n'envoie qu'une intention de tir (origine + direction).

	Consequences :
	  - impossible de tricher sur les degats, la cadence ou la portee ;
	  - tous les joueurs voient la meme trajectoire ;
	  - le client se contente d'afficher une goutte purement decorative.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local WaterWars = ReplicatedStorage:WaitForChild("WaterWars")
local Config = WaterWars:WaitForChild("Config")
local Shared = WaterWars:WaitForChild("Shared")

local GameConfig = require(Config:WaitForChild("GameConfig"))
local Net = require(Shared:WaitForChild("Net"))
local Util = require(Shared:WaitForChild("Util"))

local ServerEvents = require(script.Parent:WaitForChild("ServerEvents"))
local TeamService = require(script.Parent:WaitForChild("TeamService"))
local WeaponService = require(script.Parent:WaitForChild("WeaponService"))
local DataService = require(script.Parent:WaitForChild("DataService"))

local CombatService = {}

local GRAVITY = 196.2 -- gravite Roblox par defaut (studs/s^2)

local projectiles = {}
local roundActive = false
local rng = Random.new(os.time())

-- ------------------------------------------------------------- utilitaires

local function getHumanoid(character)
	return character and character:FindFirstChildOfClass("Humanoid") or nil
end

local function isAlive(player)
	local humanoid = getHumanoid(player.Character)
	return humanoid ~= nil and humanoid.Health > 0
end

local function now()
	return os.clock()
end

--- true si le personnage est encore protege par son apparition.
local function isProtected(character)
	if not character then
		return false
	end
	local until_ = character:GetAttribute("ProtectedUntil")
	return type(until_) == "number" and until_ > now()
end

local function damageMultiplierFor(character)
	if not character then
		return 1
	end
	local until_ = character:GetAttribute("DamageBoostUntil")
	if type(until_) == "number" and until_ > now() then
		return GameConfig.PowerupDamageMultiplier
	end
	return 1
end

local function shieldMultiplierFor(character)
	if not character then
		return 1
	end
	local until_ = character:GetAttribute("ShieldUntil")
	if type(until_) == "number" and until_ > now() then
		return GameConfig.PowerupShieldReduction
	end
	return 1
end

-- ----------------------------------------------------------------- degats

--- Applique des degats a une victime. Gere protection, bouclier et elimination.
function CombatService.ApplyDamage(victimPlayer, victimCharacter, attacker, amount, isHead, weapon)
	local humanoid = getHumanoid(victimCharacter)
	if not humanoid or humanoid.Health <= 0 then
		return 0
	end
	if isProtected(victimCharacter) then
		return 0
	end

	local final = amount * shieldMultiplierFor(victimCharacter)
	if attacker then
		final = final * damageMultiplierFor(attacker.Character)
	end
	final = math.max(1, math.floor(final + 0.5))

	humanoid.Health = math.max(0, humanoid.Health - final)
	victimCharacter:SetAttribute("LastHitAt", now())
	-- Memorise le dernier agresseur : PlayerService s'en sert au moment du
	-- deces pour attribuer l'elimination (y compris apres une chute).
	if attacker then
		victimCharacter:SetAttribute("LastAttackerUserId", attacker.UserId)
		victimCharacter:SetAttribute("LastAttackerAt", now())
		victimCharacter:SetAttribute("LastWeaponId", weapon and weapon.id or nil)
	end

	if victimPlayer then
		local origin = attacker and attacker.Character and attacker.Character:FindFirstChild("HumanoidRootPart")
		Net.Event("Damaged"):FireClient(
			victimPlayer,
			final,
			origin and (origin :: BasePart).Position or nil,
			attacker and attacker.Name or nil
		)
		ServerEvents.PlayerDamaged:Fire(victimPlayer, attacker, final, isHead)
	end

	if attacker and attacker ~= victimPlayer then
		Net.Event("HitMarker"):FireClient(attacker, final, humanoid.Health <= 0, isHead)
		DataService.AddStat(attacker, "hits", 1)
	end

	return final
end

--- Ralentit temporairement un personnage (Rayon Glace, Lance a incendie).
local function applySlow(character, amount, duration)
	local humanoid = getHumanoid(character)
	if not humanoid or amount <= 0 or duration <= 0 then
		return
	end
	local baseSpeed = character:GetAttribute("BaseWalkSpeed")
	if type(baseSpeed) ~= "number" then
		baseSpeed = GameConfig.WalkSpeed
	end
	local until_ = now() + duration
	character:SetAttribute("SlowUntil", until_)
	character:SetAttribute("SlowFactor", 1 - math.clamp(amount, 0, 0.8))
	humanoid.WalkSpeed = baseSpeed * (1 - math.clamp(amount, 0, 0.8))

	task.delay(duration, function()
		if character.Parent and character:GetAttribute("SlowUntil") == until_ then
			character:SetAttribute("SlowUntil", nil)
			character:SetAttribute("SlowFactor", nil)
			local currentHumanoid = getHumanoid(character)
			if currentHumanoid and currentHumanoid.Health > 0 then
				local restore = character:GetAttribute("BaseWalkSpeed")
				currentHumanoid.WalkSpeed = type(restore) == "number" and restore or GameConfig.WalkSpeed
			end
		end
	end)
end

--- Degats de zone avec attenuation et verification de la ligne de vue.
local function applySplash(position, weapon, attacker, damageScale)
	if weapon.splashRadius <= 0 then
		return
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.IgnoreWater = true

	for _, player in ipairs(Players:GetPlayers()) do
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if root and isAlive(player) then
			local rootPart = root :: BasePart
			local offset = rootPart.Position - position
			local distance = offset.Magnitude
			if distance <= weapon.splashRadius then
				local allied = attacker ~= nil and TeamService.AreAllies(attacker, player)
				if not allied or weapon.heal > 0 then
					-- Ligne de vue : une explosion ne traverse pas un mur.
					params.FilterDescendantsInstances = { character }
					local blocked = false
					if distance > 1 then
						local hit = workspace:Raycast(position, offset, params)
						blocked = hit ~= nil
					end
					if not blocked then
						local falloff = 1 - (distance / weapon.splashRadius) * 0.75
						if allied and weapon.heal > 0 then
							local humanoid = getHumanoid(character)
							if humanoid then
								humanoid.Health = math.min(humanoid.MaxHealth, humanoid.Health + weapon.heal * falloff)
							end
						elseif not allied then
							CombatService.ApplyDamage(
								player,
								character,
								attacker,
								weapon.splashDamage * falloff * damageScale,
								false,
								weapon
							)
						end
					end
				end
			end
		end
	end
end

-- ------------------------------------------------------------ projectiles

local function spawnProjectile(player, weapon, origin, direction, damageScale)
	if #projectiles >= GameConfig.MaxActiveProjectiles then
		return
	end
	local character = player.Character
	table.insert(projectiles, {
		position = origin,
		velocity = direction * weapon.speed,
		weapon = weapon,
		owner = player,
		ownerCharacter = character,
		damageScale = damageScale,
		expires = now() + weapon.lifetime,
	})
end

--- Resout l'impact d'un projectile.
local function resolveHit(projectile, result)
	local weapon = projectile.weapon
	local attacker = projectile.owner
	local position = result.Position

	local character, humanoid = Util.GetCharacterFromPart(result.Instance)
	local hitCharacter = false

	if character and humanoid and humanoid.Health > 0 then
		local victim = Players:GetPlayerFromCharacter(character)
		local allied = victim ~= nil and attacker ~= nil and TeamService.AreAllies(attacker, victim)

		if allied and weapon.heal > 0 then
			humanoid.Health = math.min(humanoid.MaxHealth, humanoid.Health + weapon.heal)
			hitCharacter = true
		elseif not allied and character ~= projectile.ownerCharacter then
			local isHead = result.Instance.Name == "Head"
			local damage = weapon.damage * projectile.damageScale
			if isHead then
				damage = damage * weapon.headshot
			end
			CombatService.ApplyDamage(victim, character, attacker, damage, isHead, weapon)
			if weapon.slow > 0 then
				applySlow(character, weapon.slow, weapon.slowTime)
			end
			hitCharacter = true
		end
	end

	applySplash(position, weapon, attacker, projectile.damageScale)

	Net.Event("ImpactEffect"):FireAllClients(position, result.Normal, weapon.id, hitCharacter)
end

local function stepProjectiles(deltaTime)
	if #projectiles == 0 then
		return
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.IgnoreWater = true

	local currentTime = now()
	local index = 1
	while index <= #projectiles do
		local projectile = projectiles[index]
		local weapon = projectile.weapon
		local remove = false

		projectile.velocity = projectile.velocity - Vector3.new(0, GRAVITY * weapon.gravity * deltaTime, 0)
		local nextPosition = projectile.position + projectile.velocity * deltaTime

		params.FilterDescendantsInstances = { projectile.ownerCharacter }
		local result = workspace:Raycast(projectile.position, nextPosition - projectile.position, params)
		if result then
			resolveHit(projectile, result)
			remove = true
		else
			projectile.position = nextPosition
			if currentTime >= projectile.expires or nextPosition.Y < -500 then
				remove = true
			end
		end

		if remove then
			-- Suppression en O(1) : on remplace par le dernier element.
			projectiles[index] = projectiles[#projectiles]
			projectiles[#projectiles] = nil
		else
			index = index + 1
		end
	end
end

-- ------------------------------------------------------------------- tir

local function handleFire(player, origin, direction, charge)
	if not roundActive or not isAlive(player) then
		return
	end
	if typeof(origin) ~= "Vector3" or typeof(direction) ~= "Vector3" then
		return
	end
	if direction.Magnitude < 0.01 or origin.Magnitude > 100000 then
		return
	end

	local weapon = WeaponService.GetEquipped(player)
	if not weapon then
		return
	end

	-- Anti-triche : l'origine declaree doit rester pres du personnage.
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root then
		return
	end
	if ((root :: BasePart).Position - origin).Magnitude > GameConfig.MaxFireOriginDistance then
		return
	end

	local allowed = WeaponService.TryConsume(player, weapon)
	if not allowed then
		return
	end

	-- Tirer annule la protection d'apparition : on ne tire pas depuis un abri.
	if character and isProtected(character) then
		character:SetAttribute("ProtectedUntil", nil)
	end

	local chargeRatio = 0
	if weapon.chargeTime > 0 and type(charge) == "number" then
		chargeRatio = math.clamp(charge, 0, 1)
	end
	local damageScale = 1 + (weapon.chargeBonus - 1) * chargeRatio

	DataService.AddStat(player, "shots", 1)

	local unit = direction.Unit
	local function volley()
		for _ = 1, weapon.pellets do
			local spread = Util.ApplySpread(unit, weapon.spread, rng)
			spawnProjectile(player, weapon, origin, spread, damageScale)
		end
		Net.Event("ProjectileSpawned"):FireAllClients(
			player,
			weapon.id,
			origin,
			unit,
			chargeRatio
		)
	end

	volley()
	-- Rafales : les coups suivants partent du meme point, sans nouvel envoi client.
	for shot = 2, weapon.burst do
		task.delay((shot - 1) * 0.07, function()
			if roundActive and isAlive(player) then
				volley()
			end
		end)
	end
end

-- ----------------------------------------------------------------- cycle

function CombatService.SetRoundActive(active)
	roundActive = active
	if not active then
		table.clear(projectiles)
	end
end

function CombatService.GetProjectileCount()
	return #projectiles
end

function CombatService.Start()
	Net.Event("FireWeapon").OnServerEvent:Connect(function(player, origin, direction, charge)
		local ok, err = pcall(handleFire, player, origin, direction, charge)
		if not ok then
			warn("[WaterWars] Erreur de tir : " .. tostring(err))
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		for index = #projectiles, 1, -1 do
			if projectiles[index].owner == player then
				projectiles[index] = projectiles[#projectiles]
				projectiles[#projectiles] = nil
			end
		end
	end)

	RunService.Heartbeat:Connect(function(deltaTime)
		local ok, err = pcall(stepProjectiles, math.min(deltaTime, 0.1))
		if not ok then
			warn("[WaterWars] Erreur de simulation : " .. tostring(err))
		end
	end)
end

return CombatService
