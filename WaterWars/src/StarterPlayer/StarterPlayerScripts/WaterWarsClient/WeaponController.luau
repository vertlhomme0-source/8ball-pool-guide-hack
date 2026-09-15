--[[
	WeaponController
	Entrees de combat : tir, rafale automatique, charge, visee, rechargement
	et course. Le client ne fait que declarer une intention de tir ; le serveur
	verifie la cadence, les munitions et applique les degats.

	La prediction locale (munitions, gouttes, recul) rend le tir instantane a
	l'ecran malgre la latence.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local WaterWars = ReplicatedStorage:WaitForChild("WaterWars")
local Config = WaterWars:WaitForChild("Config")
local Shared = WaterWars:WaitForChild("Shared")

local GameConfig = require(Config:WaitForChild("GameConfig"))
local Net = require(Shared:WaitForChild("Net"))

local ClientState = require(script.Parent:WaitForChild("ClientState"))
local EffectsController = require(script.Parent:WaitForChild("EffectsController"))

local WeaponController = {}

local localPlayer = Players.LocalPlayer
local DEFAULT_FOV = 70
local AIM_DISTANCE = 1200

local triggerHeld = false
local chargeStart = 0
local lastShot = 0
local aiming = false
local sprintHeld = false
local recoil = 0

local fireRemote = nil
local aimParams = RaycastParams.new()

--- Point vise par le joueur au centre de l'ecran.
local function getAimPoint(camera)
	local origin = camera.CFrame.Position
	local look = camera.CFrame.LookVector
	local character = localPlayer.Character
	aimParams.FilterType = Enum.RaycastFilterType.Exclude
	aimParams.FilterDescendantsInstances = {
		character,
		workspace:FindFirstChild("WaterWarsEffects"),
	}
	aimParams.IgnoreWater = true
	local result = workspace:Raycast(origin, look * AIM_DISTANCE, aimParams)
	if result then
		return result.Position
	end
	return origin + look * AIM_DISTANCE
end

--- Position de sortie d'eau : la buse si elle existe, sinon la camera.
local function getMuzzlePosition(tool, camera)
	local handle = tool and tool:FindFirstChild("Handle")
	if handle then
		local muzzle = handle:FindFirstChild("Muzzle")
		if muzzle and muzzle:IsA("Attachment") then
			return muzzle.WorldPosition
		end
		return (handle :: BasePart).Position
	end
	return camera.CFrame.Position
end

local function canFire(weapon)
	if not weapon then
		return false
	end
	local ammo = ClientState.ammo
	if ammo.reloading then
		return false
	end
	if ammo.weaponId == weapon.id and ammo.current < weapon.tankCost * weapon.burst then
		return false
	end
	return os.clock() - lastShot >= 1 / weapon.fireRate
end

local function applyRecoil(weapon)
	local kick = math.min(3.2, weapon.damage * weapon.pellets * 0.012 + 0.25)
	recoil = math.min(6, recoil + kick)
end

local function doFire(weapon, tool)
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	local character = localPlayer.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return
	end

	local chargeRatio = 0
	if weapon.chargeTime > 0 then
		chargeRatio = math.clamp((os.clock() - chargeStart) / weapon.chargeTime, 0, 1)
	end

	local muzzle = getMuzzlePosition(tool, camera)
	local target = getAimPoint(camera)
	local direction = target - muzzle
	if direction.Magnitude < 0.05 then
		direction = camera.CFrame.LookVector
	end
	direction = direction.Unit

	lastShot = os.clock()

	-- Prediction locale : munitions et visuel immediats.
	local ammo = ClientState.ammo
	if ammo.weaponId == weapon.id then
		ClientState.SetAmmo(
			ammo.weaponId,
			math.max(0, ammo.current - weapon.tankCost * weapon.burst),
			ammo.max,
			ammo.reloading
		)
	end

	for shot = 1, weapon.burst do
		if shot == 1 then
			EffectsController.SpawnVolley(weapon, muzzle, direction, chargeRatio)
			EffectsController.MuzzleFlash(tool, weapon)
		else
			task.delay((shot - 1) * 0.07, function()
				EffectsController.SpawnVolley(weapon, getMuzzlePosition(tool, camera), direction, chargeRatio)
				EffectsController.MuzzleFlash(tool, weapon)
			end)
		end
	end

	applyRecoil(weapon)
	if fireRemote then
		fireRemote:FireServer(muzzle, direction, chargeRatio)
	end
end

--- Appelee a chaque frame : gere la rafale et les armes a charge.
local function updateFiring()
	local weapon, tool = ClientState.GetEquippedWeapon()
	if not weapon or not tool then
		return
	end

	if weapon.chargeTime > 0 then
		-- Arme a charge : le tir part au relachement.
		return
	end
	if not triggerHeld then
		return
	end
	if not weapon.autoFire and lastShot > chargeStart then
		-- Semi-automatique : un seul tir par appui.
		return
	end
	if canFire(weapon) then
		doFire(weapon, tool)
	end
end

--- Visee : reduit le champ de vision des armes qui le permettent.
local function updateAim(deltaTime)
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	local weapon = ClientState.GetEquippedWeapon()
	local targetFov = DEFAULT_FOV
	if aiming and weapon and weapon.zoom > 0 then
		targetFov = weapon.zoom
	end
	camera.FieldOfView = camera.FieldOfView + (targetFov - camera.FieldOfView) * math.min(1, deltaTime * 12)

	-- Recul : petit coup de camera vers le haut qui retombe.
	recoil = math.max(0, recoil - deltaTime * 14)
	local character = localPlayer.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.CameraOffset = humanoid.CameraOffset:Lerp(Vector3.new(0, recoil * 0.06, recoil * 0.05), 0.35)
	end
end

local function setSprint(enabled)
	if sprintHeld == enabled then
		return
	end
	sprintHeld = enabled
	Net.Event("SetSprint"):FireServer(enabled)
end

function WeaponController.IsAiming()
	return aiming
end

--- Ratio de charge en cours (0..1), utilise par le HUD.
function WeaponController.GetCharge()
	local weapon = ClientState.GetEquippedWeapon()
	if not weapon or weapon.chargeTime <= 0 or not triggerHeld then
		return 0
	end
	return math.clamp((os.clock() - chargeStart) / weapon.chargeTime, 0, 1)
end

function WeaponController.Start()
	fireRemote = Net.Event("FireWeapon")

	UserInputService.InputBegan:Connect(function(input, processed)
		if processed then
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch then
			triggerHeld = true
			chargeStart = os.clock()
			local weapon, tool = ClientState.GetEquippedWeapon()
			if weapon and tool and weapon.chargeTime <= 0 and canFire(weapon) then
				doFire(weapon, tool)
			end
		elseif input.UserInputType == Enum.UserInputType.MouseButton2 then
			aiming = true
		elseif input.KeyCode == GameConfig.Keys.Reload then
			Net.Event("RequestReload"):FireServer()
		elseif input.KeyCode == GameConfig.Keys.Sprint then
			setSprint(true)
		end
	end)

	UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch then
			-- Relachement : c'est ici que partent les tirs charges.
			local weapon, tool = ClientState.GetEquippedWeapon()
			if triggerHeld and weapon and tool and weapon.chargeTime > 0 and canFire(weapon) then
				doFire(weapon, tool)
			end
			triggerHeld = false
		elseif input.UserInputType == Enum.UserInputType.MouseButton2 then
			aiming = false
		elseif input.KeyCode == GameConfig.Keys.Sprint then
			setSprint(false)
		end
	end)

	-- Perte de focus : on relache tout pour ne pas rester bloque en tir.
	UserInputService.WindowFocusReleased:Connect(function()
		triggerHeld = false
		aiming = false
		setSprint(false)
	end)

	Net.Event("AmmoUpdate").OnClientEvent:Connect(function(weaponId, current, max, reloading)
		ClientState.SetAmmo(weaponId, current, max, reloading)
	end)

	RunService.RenderStepped:Connect(function(deltaTime)
		local ok, err = pcall(function()
			updateFiring()
			updateAim(math.min(deltaTime, 0.1))
		end)
		if not ok then
			warn("[WaterWars] Erreur du controleur d'arme : " .. tostring(err))
		end
	end)
end

return WeaponController
