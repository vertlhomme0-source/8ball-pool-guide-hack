--[[
	PlayerService
	Tout ce qui concerne le personnage en jeu :
	  - apparition sur un point de la map avec protection temporaire ;
	  - course (sprint) et endurance ;
	  - regeneration hors combat ;
	  - rechargement aux stations d'eau ;
	  - chute hors de la map ;
	  - file de reapparition.

	Les valeurs affichees par le HUD (endurance, bonus actifs) passent par des
	attributs du personnage : ils se repliquent tout seuls vers le client, ce
	qui evite une vingtaine de RemoteEvents par seconde.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local WaterWars = ReplicatedStorage:WaitForChild("WaterWars")
local Config = WaterWars:WaitForChild("Config")
local Shared = WaterWars:WaitForChild("Shared")

local GameConfig = require(Config:WaitForChild("GameConfig"))
local Net = require(Shared:WaitForChild("Net"))

local ServerEvents = require(script.Parent:WaitForChild("ServerEvents"))
local MapService = require(script.Parent:WaitForChild("MapService"))
local TeamService = require(script.Parent:WaitForChild("TeamService"))
local WeaponService = require(script.Parent:WaitForChild("WeaponService"))

local PlayerService = {}

local respawnEnabled = false
local spawnCounters = { Blue = 0, Red = 0, FFA = 0 }
local sprinting = {}
local pendingRespawn = {}
local refillAccumulator = 0

local function now()
	return os.clock()
end

local function nextSpawnIndex(key)
	spawnCounters[key] = (spawnCounters[key] or 0) + 1
	return spawnCounters[key]
end

--- Fait apparaitre le joueur sur un point de la map courante.
function PlayerService.Spawn(player)
	if not player.Parent then
		return
	end
	pendingRespawn[player] = nil

	-- Sans terrain, faire apparaitre le joueur le ferait tomber dans le vide
	-- indefiniment. Mieux vaut ne pas l'incarner et le dire clairement.
	if not MapService.GetCurrentMap() then
		warn("[WaterWars] Apparition annulee : aucun terrain n'est charge.")
		return
	end

	local teamId = TeamService.IsTeamMode() and TeamService.GetTeamId(player) or nil
	local key = teamId or "FFA"
	local spawnCFrame = MapService.GetSpawnCFrame(teamId, nextSpawnIndex(key))

	player:LoadCharacter()

	local character = player.Character
	if not character then
		return
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart")
	if not humanoid or not root then
		return
	end

	character:PivotTo(spawnCFrame + Vector3.new(0, 3.5, 0))

	humanoid.MaxHealth = GameConfig.MaxHealth
	humanoid.Health = GameConfig.MaxHealth
	humanoid.UseJumpPower = true
	humanoid.JumpPower = GameConfig.JumpPower
	humanoid.WalkSpeed = GameConfig.WalkSpeed
	humanoid.BreakJointsOnDeath = false
	humanoid.NameDisplayDistance = 90
	humanoid.HealthDisplayDistance = 90

	character:SetAttribute("BaseWalkSpeed", GameConfig.WalkSpeed)
	character:SetAttribute("Stamina", GameConfig.StaminaMax)
	character:SetAttribute("ProtectedUntil", now() + GameConfig.SpawnProtectionTime)
	character:SetAttribute("LastHitAt", 0)
	character:SetAttribute("LastAttackerUserId", nil)
	character:SetAttribute("LastWeaponId", nil)
	sprinting[player] = false

	-- Bouclier visuel pendant la protection d'apparition.
	local field = Instance.new("ForceField")
	field.Visible = true
	field.Parent = character
	task.delay(GameConfig.SpawnProtectionTime, function()
		if field.Parent then
			field:Destroy()
		end
	end)

	WeaponService.GiveLoadout(player)

	humanoid.Died:Connect(function()
		PlayerService.HandleDeath(player, character)
	end)

	ServerEvents.CharacterSpawned:Fire(player, character)
end

--- Gere un deces : attribution de l'elimination puis file de reapparition.
function PlayerService.HandleDeath(player, character)
	if character:GetAttribute("DeathHandled") then
		return
	end
	character:SetAttribute("DeathHandled", true)

	local killer = nil
	local attackerId = character:GetAttribute("LastAttackerUserId")
	local attackerAt = character:GetAttribute("LastAttackerAt")
	-- On n'attribue l'elimination que si le dernier coup est recent (10 s).
	if type(attackerId) == "number" and type(attackerAt) == "number" and now() - attackerAt < 10 then
		local candidate = Players:GetPlayerByUserId(attackerId)
		if candidate and candidate ~= player then
			killer = candidate
		end
	end
	local weaponId = character:GetAttribute("LastWeaponId")

	ServerEvents.PlayerKilled:Fire(player, killer, type(weaponId) == "string" and weaponId or nil)

	if respawnEnabled then
		pendingRespawn[player] = now() + GameConfig.RespawnTime
		Net.Event("Notify"):FireClient(player, string.format("Reapparition dans %d s", GameConfig.RespawnTime), "info")
	end
end

function PlayerService.SetRespawnEnabled(enabled)
	respawnEnabled = enabled
	if not enabled then
		table.clear(pendingRespawn)
	end
end

--- Fait apparaitre tout le monde (debut de manche).
function PlayerService.SpawnAll()
	spawnCounters.Blue = 0
	spawnCounters.Red = 0
	spawnCounters.FFA = 0
	for _, player in ipairs(Players:GetPlayers()) do
		task.spawn(PlayerService.Spawn, player)
	end
end

--- Renvoie tout le monde au vestiaire (fin de manche).
function PlayerService.DespawnAll()
	table.clear(pendingRespawn)
	for _, player in ipairs(Players:GetPlayers()) do
		WeaponService.ClearTools(player)
		if player.Character then
			local humanoid = player.Character:FindFirstChildOfClass("Humanoid")
			if humanoid then
				humanoid.WalkSpeed = GameConfig.WalkSpeed
			end
		end
	end
end

-- ------------------------------------------------------- boucle par frame

local function updateCharacter(player, deltaTime)
	local character = player.Character
	if not character then
		return
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart")
	if not humanoid or not root or humanoid.Health <= 0 then
		return
	end
	local rootPart = root :: BasePart
	local currentTime = now()

	-- ------------------------------------------------------- endurance
	local stamina = character:GetAttribute("Stamina")
	if type(stamina) ~= "number" then
		stamina = GameConfig.StaminaMax
	end
	local wantsSprint = sprinting[player] == true
	local moving = rootPart.AssemblyLinearVelocity.Magnitude > 4
	local isSprinting = wantsSprint and moving and stamina > 0

	if isSprinting then
		stamina = math.max(0, stamina - GameConfig.StaminaDrain * deltaTime)
		if stamina <= 0 then
			sprinting[player] = false
		end
	else
		stamina = math.min(GameConfig.StaminaMax, stamina + GameConfig.StaminaRegen * deltaTime)
	end
	character:SetAttribute("Stamina", stamina)

	-- ------------------------------------------------ vitesse effective
	local weapon = WeaponService.GetEquipped(player)
	local base = isSprinting and GameConfig.SprintSpeed or GameConfig.WalkSpeed
	if weapon then
		base = base * weapon.walkSpeedMul
	end
	character:SetAttribute("BaseWalkSpeed", base)

	local multiplier = 1
	local slowUntil = character:GetAttribute("SlowUntil")
	if type(slowUntil) == "number" and slowUntil > currentTime then
		local factor = character:GetAttribute("SlowFactor")
		multiplier = multiplier * (type(factor) == "number" and factor or 1)
	end
	local speedUntil = character:GetAttribute("SpeedBoostUntil")
	if type(speedUntil) == "number" and speedUntil > currentTime then
		multiplier = multiplier * GameConfig.PowerupSpeedMultiplier
	end
	humanoid.WalkSpeed = base * multiplier

	-- ------------------------------------------------- regeneration
	local lastHit = character:GetAttribute("LastHitAt")
	if type(lastHit) == "number" and currentTime - lastHit > GameConfig.RegenDelay then
		if humanoid.Health < humanoid.MaxHealth then
			humanoid.Health = math.min(humanoid.MaxHealth, humanoid.Health + GameConfig.RegenRate * deltaTime)
		end
	end

	-- --------------------------------------------------------- chute
	if rootPart.Position.Y < MapService.GetKillY() then
		humanoid.Health = 0
	end
end

local function updateRefills(deltaTime)
	local stations = MapService.GetRefillStations()
	if #stations == 0 then
		return
	end
	for _, player in ipairs(Players:GetPlayers()) do
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if root and humanoid and humanoid.Health > 0 then
			local position = (root :: BasePart).Position
			for _, station in ipairs(stations) do
				if (position - station.position).Magnitude <= GameConfig.RefillRadius then
					WeaponService.AddWater(player, GameConfig.RefillRate * deltaTime)
					humanoid.Health = math.min(
						humanoid.MaxHealth,
						humanoid.Health + GameConfig.RefillHealRate * deltaTime
					)
					break
				end
			end
		end
	end
end

local function step(deltaTime)
	local currentTime = now()
	for _, player in ipairs(Players:GetPlayers()) do
		updateCharacter(player, deltaTime)
	end

	refillAccumulator = refillAccumulator + deltaTime
	if refillAccumulator >= 0.2 then
		updateRefills(refillAccumulator)
		refillAccumulator = 0
	end

	for player, readyAt in pairs(pendingRespawn) do
		if currentTime >= readyAt then
			pendingRespawn[player] = nil
			if respawnEnabled and player.Parent then
				task.spawn(PlayerService.Spawn, player)
			end
		end
	end
end

function PlayerService.Start()
	Players.CharacterAutoLoads = false

	Net.Event("SetSprint").OnServerEvent:Connect(function(player, wants)
		sprinting[player] = wants == true
	end)

	Players.PlayerRemoving:Connect(function(player)
		sprinting[player] = nil
		pendingRespawn[player] = nil
	end)

	RunService.Heartbeat:Connect(function(deltaTime)
		local ok, err = pcall(step, math.min(deltaTime, 0.25))
		if not ok then
			warn("[WaterWars] Erreur de mise a jour joueur : " .. tostring(err))
		end
	end)
end

return PlayerService
