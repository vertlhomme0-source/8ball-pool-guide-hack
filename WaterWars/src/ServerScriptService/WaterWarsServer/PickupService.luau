--[[
	PickupService
	Bonus au sol : turbo, haute pression, impermeable et citerne.
	Les plaques apparaissent aux emplacements definis par la map, se
	reactivent apres un delai, et sont ramassees par simple proximite (plus
	fiable que Touched, qui rate des collisions a grande vitesse).
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

local WeaponService = require(script.Parent:WaitForChild("WeaponService"))

local PickupService = {}

local PICKUP_RADIUS = 7
local CHECK_INTERVAL = 0.15

local pads = {}
local container = nil
local accumulator = 0
local spin = 0

local function powerupById(id)
	for _, definition in ipairs(GameConfig.Powerups) do
		if definition.id == id then
			return definition
		end
	end
	return GameConfig.Powerups[1]
end

local function buildPad(position, definition)
	local model = Instance.new("Model")
	model.Name = "Powerup_" .. definition.id

	local base = Instance.new("Part")
	base.Name = "Base"
	base.Shape = Enum.PartType.Cylinder
	base.Size = Vector3.new(0.6, 9, 9)
	base.CFrame = CFrame.new(position) * CFrame.Angles(0, 0, math.rad(90))
	base.Anchored = true
	base.CanCollide = false
	base.CanQuery = false
	base.CanTouch = false
	base.CastShadow = false
	base.Material = Enum.Material.Neon
	base.Color = definition.color
	base.Transparency = 0.5
	base.Parent = model

	local core = Instance.new("Part")
	core.Name = "Core"
	core.Size = Vector3.new(3.4, 3.4, 3.4)
	core.CFrame = CFrame.new(position + Vector3.new(0, 4, 0))
	core.Anchored = true
	core.CanCollide = false
	core.CanQuery = false
	core.CanTouch = false
	core.Material = Enum.Material.Neon
	core.Color = definition.color
	core.Parent = model

	local light = Instance.new("PointLight")
	light.Color = definition.color
	light.Brightness = 3
	light.Range = 20
	light.Parent = core

	local billboard = Instance.new("BillboardGui")
	billboard.Size = UDim2.fromOffset(190, 40)
	billboard.StudsOffsetWorldSpace = Vector3.new(0, 4, 0)
	billboard.MaxDistance = 130
	billboard.Parent = core

	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Text = string.upper(definition.name)
	label.TextColor3 = definition.color
	label.TextStrokeTransparency = 0.35
	label.Font = Enum.Font.GothamBold
	label.TextScaled = true
	label.Parent = billboard

	model.Parent = container
	return model, core
end

local function setPadVisible(pad, visible)
	pad.active = visible
	pad.model.Parent = visible and container or nil
end

--- Applique l'effet d'un bonus au joueur.
local function grant(player, definition)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not character or not humanoid then
		return false
	end

	if definition.id == "Refill" then
		WeaponService.RefillAll(player)
		humanoid.Health = math.min(humanoid.MaxHealth, humanoid.Health + 25)
	elseif definition.id == "Speed" then
		character:SetAttribute("SpeedBoostUntil", os.clock() + definition.duration)
	elseif definition.id == "Damage" then
		character:SetAttribute("DamageBoostUntil", os.clock() + definition.duration)
	elseif definition.id == "Shield" then
		character:SetAttribute("ShieldUntil", os.clock() + definition.duration)
		local existing = character:FindFirstChildOfClass("ForceField")
		if existing then
			existing:Destroy()
		end
		local field = Instance.new("ForceField")
		field.Visible = true
		field.Parent = character
		Util.DestroyAfter(field, definition.duration)
	end

	Net.Event("Notify"):FireClient(player, definition.name .. " recupere !", "good")
	Net.Event("EffectState"):FireClient(player, definition.id, definition.duration)
	return true
end

local function step(deltaTime)
	spin = spin + deltaTime * 2
	for _, pad in ipairs(pads) do
		if pad.active and pad.core.Parent then
			pad.core.CFrame = CFrame.new(pad.position + Vector3.new(0, 4 + math.sin(spin * 1.5) * 0.7, 0))
				* CFrame.Angles(spin, spin * 0.8, 0)
		end
	end

	accumulator = accumulator + deltaTime
	if accumulator < CHECK_INTERVAL then
		return
	end
	accumulator = 0

	for _, pad in ipairs(pads) do
		if pad.active then
			for _, player in ipairs(Players:GetPlayers()) do
				local character = player.Character
				local root = character and character:FindFirstChild("HumanoidRootPart")
				local humanoid = character and character:FindFirstChildOfClass("Humanoid")
				if root and humanoid and humanoid.Health > 0 then
					if ((root :: BasePart).Position - pad.position).Magnitude <= PICKUP_RADIUS then
						if grant(player, pad.definition) then
							setPadVisible(pad, false)
							task.delay(GameConfig.PowerupRespawn, function()
								if pad.model.Parent ~= nil or container ~= nil then
									-- Nouveau bonus tire au sort a la reapparition.
									setPadVisible(pad, true)
								end
							end)
						end
						break
					end
				end
			end
		end
	end
end

--- (Re)cree les plaques de bonus pour la map courante.
function PickupService.Setup(map)
	PickupService.Clear()
	container = Instance.new("Folder")
	container.Name = "Powerups"
	container.Parent = workspace

	for index, position in ipairs(map.powerupSpots) do
		-- Un bonus different a chaque emplacement, dans l'ordre de la config.
		local definition = GameConfig.Powerups[((index - 1) % #GameConfig.Powerups) + 1]
		if index == 1 then
			-- L'emplacement central est toujours un bonus offensif.
			definition = powerupById("Damage")
		end
		local model, core = buildPad(position, definition)
		table.insert(pads, {
			position = position,
			definition = definition,
			model = model,
			core = core,
			active = true,
		})
	end
end

function PickupService.Clear()
	for _, pad in ipairs(pads) do
		pad.model:Destroy()
	end
	table.clear(pads)
	if container then
		container:Destroy()
		container = nil
	end
end

function PickupService.Start()
	RunService.Heartbeat:Connect(function(deltaTime)
		if #pads == 0 then
			return
		end
		local ok, err = pcall(step, deltaTime)
		if not ok then
			warn("[WaterWars] Erreur des bonus : " .. tostring(err))
		end
	end)
end

return PickupService
