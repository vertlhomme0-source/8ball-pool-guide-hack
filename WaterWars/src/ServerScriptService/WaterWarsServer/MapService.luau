--[[
	MapService
	Construit et detruit les terrains, applique l'ambiance lumineuse, et
	fabrique les elements de jeu propres a la map : stations de recharge,
	zone de controle, points d'apparition.

	Toute la geometrie vit dans un seul Model (workspace.CurrentMap) : le
	nettoyage de fin de manche est donc instantane et ne laisse rien derriere.
]]

local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local WaterWars = ReplicatedStorage:WaitForChild("WaterWars")
local Config = WaterWars:WaitForChild("Config")
local Shared = WaterWars:WaitForChild("Shared")

local GameConfig = require(Config:WaitForChild("GameConfig"))
local Maps = require(Config:WaitForChild("Maps"))
local MapBuilder = require(Shared:WaitForChild("MapBuilder"))

local MapService = {}

local currentMap = nil
local currentModel = nil
local refillParts = {}
local hillPart = nil

local MAP_MODEL_NAME = "CurrentMap"

--- Ambiance par defaut, restauree si aucune map n'est chargee.
local function applyLighting(settings)
	Lighting.ClockTime = settings.ClockTime or 14
	Lighting.Brightness = settings.Brightness or 2.5
	Lighting.Ambient = settings.Ambient or Color3.fromRGB(120, 120, 120)
	Lighting.OutdoorAmbient = settings.OutdoorAmbient or Color3.fromRGB(150, 150, 150)
	Lighting.FogColor = settings.FogColor or Color3.fromRGB(200, 220, 240)
	Lighting.FogStart = settings.FogStart or 200
	Lighting.FogEnd = settings.FogEnd or 800
	Lighting.ColorShift_Top = settings.ColorShift_Top or Color3.fromRGB(255, 255, 255)
	Lighting.GlobalShadows = true
	Lighting.EnvironmentDiffuseScale = 0.6
	Lighting.EnvironmentSpecularScale = 0.6

	local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
	if not atmosphere then
		atmosphere = Instance.new("Atmosphere")
		atmosphere.Parent = Lighting
	end
	atmosphere.Density = settings.Density or 0.3
	atmosphere.Haze = settings.Haze or 1.2
	atmosphere.Glare = 0.2
	atmosphere.Color = settings.FogColor or Color3.fromRGB(200, 220, 240)
	atmosphere.Decay = settings.ColorShift_Top or Color3.fromRGB(180, 200, 220)
end

--- Station de recharge : une plaque lumineuse avec un bidon qui tourne.
local function createRefillStation(parent, position, index)
	local station = Instance.new("Model")
	station.Name = "RefillStation" .. index

	local pad = Instance.new("Part")
	pad.Name = "Pad"
	pad.Shape = Enum.PartType.Cylinder
	pad.Size = Vector3.new(1, GameConfig.RefillRadius * 2, GameConfig.RefillRadius * 2)
	pad.CFrame = CFrame.new(position + Vector3.new(0, 0.5, 0)) * CFrame.Angles(0, 0, math.rad(90))
	pad.Anchored = true
	pad.CanCollide = false
	pad.CanQuery = false
	pad.CanTouch = false
	pad.Material = Enum.Material.Neon
	pad.Color = Color3.fromRGB(70, 200, 255)
	pad.Transparency = 0.55
	pad.CastShadow = false
	pad.Parent = station

	local tank = Instance.new("Part")
	tank.Name = "Tank"
	tank.Shape = Enum.PartType.Cylinder
	tank.Size = Vector3.new(7, 5, 5)
	tank.CFrame = CFrame.new(position + Vector3.new(0, 4.5, 0)) * CFrame.Angles(0, 0, math.rad(90))
	tank.Anchored = true
	tank.CanCollide = true
	tank.Material = Enum.Material.SmoothPlastic
	tank.Color = Color3.fromRGB(40, 130, 200)
	tank.Parent = station

	local light = Instance.new("PointLight")
	light.Brightness = 2
	light.Range = 22
	light.Color = Color3.fromRGB(90, 200, 255)
	light.Parent = tank

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "Label"
	billboard.Size = UDim2.fromOffset(180, 46)
	billboard.StudsOffsetWorldSpace = Vector3.new(0, 5, 0)
	billboard.AlwaysOnTop = false
	billboard.MaxDistance = 140
	billboard.Parent = tank

	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Text = "RECHARGE"
	label.TextColor3 = Color3.fromRGB(180, 240, 255)
	label.TextStrokeTransparency = 0.4
	label.Font = Enum.Font.GothamBold
	label.TextScaled = true
	label.Parent = billboard

	station.Parent = parent
	return station
end

--- Marqueur de la zone de controle (mode Roi de la piscine).
local function createHill(parent, position)
	local zone = Instance.new("Part")
	zone.Name = "HillZone"
	zone.Shape = Enum.PartType.Cylinder
	zone.Size = Vector3.new(60, GameConfig.HillRadius * 2, GameConfig.HillRadius * 2)
	zone.CFrame = CFrame.new(position) * CFrame.Angles(0, 0, math.rad(90))
	zone.Anchored = true
	zone.CanCollide = false
	zone.CanQuery = false
	zone.CanTouch = false
	zone.Material = Enum.Material.Neon
	zone.Color = Color3.fromRGB(230, 230, 230)
	zone.Transparency = 0.86
	zone.CastShadow = false
	zone.Parent = parent
	return zone
end

--- Detruit la map courante et remet le monde a plat.
function MapService.Unload()
	if currentModel then
		currentModel:Destroy()
	end
	currentModel = nil
	currentMap = nil
	refillParts = {}
	hillPart = nil
end

--- Construit `map` dans le workspace. Renvoie le Model cree.
function MapService.Load(map)
	assert(map, "MapService.Load : map manquante")
	MapService.Unload()

	local model = Instance.new("Model")
	model.Name = MAP_MODEL_NAME

	local geometry = Instance.new("Folder")
	geometry.Name = "Geometry"
	geometry.Parent = model

	local builder = MapBuilder.new(geometry, 20240900 + (map.order or 1))
	map.build(builder)

	local props = Instance.new("Folder")
	props.Name = "Props"
	props.Parent = model

	refillParts = {}
	for index, position in ipairs(map.refillStations) do
		local station = createRefillStation(props, position, index)
		table.insert(refillParts, { position = position, model = station })
	end

	hillPart = createHill(props, map.controlPoint)

	model.Parent = workspace
	currentModel = model
	currentMap = map

	applyLighting(map.lighting)
	workspace.FallenPartsDestroyHeight = (map.killY or -50) - 200

	return model
end

function MapService.GetCurrentMap()
	return currentMap
end

function MapService.GetModel()
	return currentModel
end

function MapService.GetRefillStations()
	return refillParts
end

function MapService.GetHillPart()
	return hillPart
end

--- Colore la zone de controle selon l'equipe qui la tient.
function MapService.SetHillColor(color, transparency)
	if hillPart then
		hillPart.Color = color
		hillPart.Transparency = transparency or 0.86
	end
end

--- Renvoie une liste de points d'apparition pour un camp donne.
--- `teamId` vaut "Blue", "Red" ou nil (chacun pour soi).
function MapService.GetSpawnList(teamId)
	if not currentMap then
		return {}
	end
	local spawns = currentMap.spawns
	if teamId and spawns[teamId] then
		return spawns[teamId]
	end
	return spawns.FFA
end

--- CFrame d'apparition, orientee vers le centre du terrain.
function MapService.GetSpawnCFrame(teamId, index)
	local list = MapService.GetSpawnList(teamId)
	if #list == 0 then
		return CFrame.new(0, 20, 0)
	end
	local position = list[((index - 1) % #list) + 1]
	local target = currentMap and currentMap.controlPoint or Vector3.new(0, position.Y, 0)
	local flatTarget = Vector3.new(target.X, position.Y, target.Z)
	if (flatTarget - position).Magnitude < 1 then
		return CFrame.new(position)
	end
	return CFrame.lookAt(position, flatTarget)
end

--- Hauteur en dessous de laquelle un joueur est considere comme tombe.
function MapService.GetKillY()
	return currentMap and currentMap.killY or -100
end

--- Donnees envoyees au client pour l'ecran de vote et le HUD.
function MapService.Describe(map)
	return {
		id = map.id,
		name = map.name,
		theme = map.theme,
		description = map.description,
	}
end

function MapService.GetAll()
	return Maps.List
end

function MapService.PickRandom(count, excludeId, rng)
	return Maps.PickRandom(count, excludeId, rng)
end

function MapService.GetById(id)
	return Maps.Get(id)
end

return MapService
