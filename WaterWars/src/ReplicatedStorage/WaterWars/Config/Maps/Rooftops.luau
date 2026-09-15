--[[
	Map 4/6 : Toits de la Ville
	Combat sur deux etages : des ruelles etroites au niveau de la rue et un
	reseau de toits relies par des planches. Chaque base possede son propre
	acces au toit, mais le centre ne se tient qu'en hauteur.
]]

local MAP_WIDTH = 300
local MAP_DEPTH = 240

local ASPHALT = Color3.fromRGB(62, 64, 70)
local ROOF = Color3.fromRGB(96, 98, 106)
local BRICK_A = Color3.fromRGB(152, 96, 82)
local BRICK_B = Color3.fromRGB(122, 124, 132)
local METAL = Color3.fromRGB(138, 142, 150)
local NEON_BLUE = Color3.fromRGB(70, 180, 255)
local NEON_RED = Color3.fromRGB(255, 96, 90)

local ROOF_Y = 46

local function row(x, zCenter, count, spacing, y)
	local points = {}
	local start = zCenter - (count - 1) * spacing / 2
	for index = 1, count do
		table.insert(points, Vector3.new(x, y or 4, start + (index - 1) * spacing))
	end
	return points
end

local function concat(...)
	local out = {}
	for _, list in ipairs({ ... }) do
		for _, value in ipairs(list) do
			table.insert(out, value)
		end
	end
	return out
end

local Map = {}

Map.id = "rooftops"
Map.name = "Toits de la Ville"
Map.theme = "Ville au crepuscule"
Map.description = "Ruelles sombres au sol, passerelles et chateaux d'eau sur les toits. Deux etages de jeu totalement differents."
Map.size = Vector2.new(MAP_WIDTH, MAP_DEPTH)
Map.killY = -25
Map.skyColor = Color3.fromRGB(70, 90, 130)

Map.lighting = {
	ClockTime = 18.6,
	Brightness = 1.9,
	Ambient = Color3.fromRGB(88, 92, 108),
	OutdoorAmbient = Color3.fromRGB(110, 118, 140),
	FogColor = Color3.fromRGB(90, 105, 135),
	FogStart = 140,
	FogEnd = 560,
	ColorShift_Top = Color3.fromRGB(255, 180, 140),
}

Map.spawns = {
	Blue = concat(row(-126, -40, 6, 16, 4), row(-126, 40, 6, 16, ROOF_Y + 4)),
	Red = concat(row(126, -40, 6, 16, 4), row(126, 40, 6, 16, ROOF_Y + 4)),
	FFA = concat(
		row(-110, 0, 4, 26, 4),
		row(110, 0, 4, 26, 4),
		row(-58, -70, 3, 28, ROOF_Y + 4),
		row(58, 70, 3, 28, ROOF_Y + 4),
		row(-58, 70, 3, 28, 4),
		row(58, -70, 3, 28, 4)
	),
}

Map.controlPoint = Vector3.new(0, ROOF_Y + 6, 0)

Map.refillStations = {
	Vector3.new(-118, 0, 0),
	Vector3.new(118, 0, 0),
	Vector3.new(-40, ROOF_Y, 0),
	Vector3.new(40, ROOF_Y, 0),
}

Map.powerupSpots = {
	Vector3.new(0, ROOF_Y + 14, 0),
	Vector3.new(0, 3, -76),
	Vector3.new(0, 3, 76),
	Vector3.new(-78, ROOF_Y + 3, -60),
	Vector3.new(78, ROOF_Y + 3, 60),
}

function Map.build(b)
	-- ------------------------------------------------------------- la rue
	b:Ground(MAP_WIDTH, MAP_DEPTH, { color = ASPHALT, material = Enum.Material.Asphalt })
	b:Bounds(MAP_WIDTH, MAP_DEPTH, 220)

	-- Marquage au sol de l'avenue centrale.
	for index = -7, 7 do
		b:Block(Vector3.new(index * 20, 0.06, 0), Vector3.new(12, 0.2, 2), {
			name = "RoadLine", color = Color3.fromRGB(226, 216, 150), material = Enum.Material.Concrete, castShadow = false,
		})
	end

	-- ------------------------------------------------- immeubles centraux
	-- Quatre blocs d'immeubles forment une croix de ruelles au sol
	-- et une plateforme continue sur les toits.
	local blocks = {
		{ x = -46, z = -52, sx = 72, sz = 62, color = BRICK_A },
		{ x = 46, z = -52, sx = 72, sz = 62, color = BRICK_B },
		{ x = -46, z = 52, sx = 72, sz = 62, color = BRICK_B },
		{ x = 46, z = 52, sx = 72, sz = 62, color = BRICK_A },
	}
	for _, block in ipairs(blocks) do
		b:Block(Vector3.new(block.x, ROOF_Y / 2, block.z), Vector3.new(block.sx, ROOF_Y, block.sz), {
			name = "Building", color = block.color, material = Enum.Material.Brick,
		})
		-- Corniche et toit.
		b:Block(Vector3.new(block.x, ROOF_Y + 0.5, block.z), Vector3.new(block.sx + 3, 1, block.sz + 3), {
			name = "RoofSlab", color = ROOF, material = Enum.Material.Concrete,
		})
		-- Parapet ajoure : couverture a hauteur de taille sur le toit.
		local halfX, halfZ = block.sx / 2, block.sz / 2
		for _, edge in ipairs({
			{ Vector3.new(0, 0, halfZ), Vector3.new(block.sx + 3, 4, 1.5) },
			{ Vector3.new(0, 0, -halfZ), Vector3.new(block.sx + 3, 4, 1.5) },
			{ Vector3.new(halfX, 0, 0), Vector3.new(1.5, 4, block.sz + 3) },
			{ Vector3.new(-halfX, 0, 0), Vector3.new(1.5, 4, block.sz + 3) },
		}) do
			b:Block(Vector3.new(block.x + edge[1].X, ROOF_Y + 3, block.z + edge[1].Z), edge[2], {
				name = "Parapet", color = ROOF, material = Enum.Material.Concrete,
			})
		end
		-- Fenetres eclairees pour donner de la profondeur.
		for level = 1, 4 do
			for column = -1, 1 do
				b:Block(Vector3.new(block.x + column * 20, level * 9, block.z + halfZ + 0.4), Vector3.new(8, 5, 0.4), {
					name = "Window", color = Color3.fromRGB(255, 226, 160), material = Enum.Material.Neon,
					canCollide = false, castShadow = false,
				})
			end
		end
	end

	-- Passerelles reliant les quatre toits : le coeur du jeu en hauteur.
	b:Mirror(function(side)
		b:Bridge(Vector3.new(side * 10, ROOF_Y + 1, -21), Vector3.new(side * 10, ROOF_Y + 1, 21), 12, {
			color = Color3.fromRGB(140, 120, 90), railColor = Color3.fromRGB(100, 84, 62),
		})
		b:Bridge(Vector3.new(-21, ROOF_Y + 1, side * 10), Vector3.new(21, ROOF_Y + 1, side * 10), 12, {
			color = Color3.fromRGB(140, 120, 90), railColor = Color3.fromRGB(100, 84, 62),
		})
	end)

	-- Plateforme centrale suspendue : le point de controle.
	b:Platform(Vector3.new(0, ROOF_Y + 5, 0), Vector3.new(34, 1.2, 34), {
		name = "CentralDeck", color = METAL, material = Enum.Material.DiamondPlate,
	})
	b:Mirror(function(side)
		b:Block(Vector3.new(side * 16, ROOF_Y + 8, 0), Vector3.new(1.5, 5, 34), {
			name = "DeckRail", color = METAL, material = Enum.Material.Metal,
		})
		b:Ramp(Vector3.new(side * 24, ROOF_Y + 1, 0), 12, 14, 4, side > 0 and 90 or 270, {
			color = METAL, material = Enum.Material.DiamondPlate,
		})
	end)

	-- ------------------------------------------------------- deux bases
	b:Mirror(function(side)
		local baseX = side * 122
		local accent = side < 0 and NEON_BLUE or NEON_RED

		-- Immeuble de base, plus large, avec un toit de depart degage.
		b:Block(Vector3.new(baseX, ROOF_Y / 2, 0), Vector3.new(56, ROOF_Y, 150), {
			name = "BaseBuilding", color = Color3.fromRGB(104, 106, 116), material = Enum.Material.Concrete,
		})
		b:Block(Vector3.new(baseX, ROOF_Y + 0.5, 0), Vector3.new(60, 1, 154), {
			name = "BaseRoof", color = ROOF, material = Enum.Material.Concrete,
		})
		b:Mirror(function(inner)
			b:Block(Vector3.new(baseX, ROOF_Y + 3, inner * 76), Vector3.new(60, 4, 1.5), {
				name = "Parapet", color = ROOF, material = Enum.Material.Concrete,
			})
		end)
		b:Block(Vector3.new(baseX + side * 29, ROOF_Y + 3, 0), Vector3.new(1.5, 4, 154), {
			name = "Parapet", color = ROOF, material = Enum.Material.Concrete,
		})

		-- Escalier de secours exterieur : seule liaison rue <-> toit de la base.
		b:Stairs(Vector3.new(baseX - side * 34, 0, 60), 12, 40, ROOF_Y, 14, side > 0 and 90 or 270, {
			color = METAL, material = Enum.Material.Metal,
		})
		b:Platform(Vector3.new(baseX - side * 34, ROOF_Y + 1, 60), Vector3.new(18, 1, 18), {
			name = "FireEscapeTop", color = METAL, material = Enum.Material.DiamondPlate,
		})
		b:Bridge(Vector3.new(baseX - side * 34, ROOF_Y + 1, 60), Vector3.new(baseX, ROOF_Y + 1, 60), 12, {
			color = METAL, railColor = Color3.fromRGB(110, 114, 122), material = Enum.Material.Metal,
		})

		-- Chateau d'eau : point haut de la base et station de recharge naturelle.
		b:Cylinder(
			CFrame.new(baseX, ROOF_Y + 16, -54) * CFrame.Angles(0, 0, math.rad(90)),
			Vector3.new(22, 26, 26),
			{ name = "WaterTower", color = Color3.fromRGB(150, 130, 100), material = Enum.Material.WoodPlanks }
		)
		for _, offset in ipairs({
			Vector3.new(9, 0, 9), Vector3.new(-9, 0, 9), Vector3.new(9, 0, -9), Vector3.new(-9, 0, -9),
		}) do
			b:Block(Vector3.new(baseX + offset.X, ROOF_Y + 3, -54 + offset.Z), Vector3.new(1.4, 6, 1.4), {
				name = "TowerLeg", color = METAL, material = Enum.Material.Metal,
			})
		end

		-- Enseigne neon aux couleurs de l'equipe.
		b:Block(Vector3.new(baseX - side * 29, 32, 0), Vector3.new(1, 18, 60), {
			name = "NeonSign", color = accent, material = Enum.Material.Neon, canCollide = false, castShadow = false,
		})

		-- Climatiseurs sur le toit : couverture basse.
		for index = -2, 2 do
			b:Block(Vector3.new(baseX + side * 14, ROOF_Y + 3.5, index * 26), Vector3.new(12, 5, 10), {
				name = "AirConditioner", color = Color3.fromRGB(176, 180, 188), material = Enum.Material.Metal,
			})
		end

		-- Rue : bennes et camionnettes en couverture.
		b:Block(Vector3.new(baseX - side * 46, 3.5, -30), Vector3.new(20, 7, 12), {
			name = "Dumpster", color = Color3.fromRGB(60, 120, 80), material = Enum.Material.Metal,
		})
		b:Block(Vector3.new(baseX - side * 46, 4.5, 34), Vector3.new(26, 9, 13), {
			name = "Truck", color = Color3.fromRGB(180, 180, 176), material = Enum.Material.Metal,
		})
		b:Crates(Vector3.new(baseX - side * 60, 0, 0), 4, 20, { maxStack = 2 })
	end)

	-- ---------------------------------------------------- ruelles au sol
	b:Mirror(function(side)
		-- Conteneurs dans l'avenue centrale.
		b:Block(
			CFrame.new(side * 62, 6, 0) * CFrame.Angles(0, math.rad(side * 8), 0),
			Vector3.new(34, 12, 16),
			{ name = "Container", color = side > 0 and Color3.fromRGB(190, 110, 60) or Color3.fromRGB(70, 130, 170), material = Enum.Material.Metal }
		)
		b:Block(Vector3.new(side * 62, 13.5, 0), Vector3.new(34, 3, 16), {
			name = "ContainerTop", color = Color3.fromRGB(90, 94, 100), material = Enum.Material.Metal,
		})
		b:Ramp(Vector3.new(side * 84, 0, 0), 14, 18, 12, side > 0 and 270 or 90, {
			color = METAL, material = Enum.Material.Metal,
		})

		-- Echafaudage : acces rue -> toit au milieu du terrain.
		b:Stairs(Vector3.new(0, 0, side * 96), 14, 44, ROOF_Y, 15, side > 0 and 180 or 0, {
			color = Color3.fromRGB(196, 160, 90), material = Enum.Material.Metal,
		})
		b:Platform(Vector3.new(0, ROOF_Y + 1, side * 96), Vector3.new(26, 1, 20), {
			name = "ScaffoldTop", color = Color3.fromRGB(196, 160, 90), material = Enum.Material.Metal,
		})
		b:Bridge(Vector3.new(0, ROOF_Y + 1, side * 96), Vector3.new(0, ROOF_Y + 1, side * 84), 14, {
			color = Color3.fromRGB(196, 160, 90), rails = false,
		})
		-- Liaison echafaudage -> toits des immeubles centraux.
		b:Mirror(function(inner)
			b:Bridge(Vector3.new(0, ROOF_Y + 1, side * 84), Vector3.new(inner * 46, ROOF_Y + 1, side * 84), 12, {
				color = Color3.fromRGB(140, 120, 90), railColor = Color3.fromRGB(100, 84, 62),
			})
		end)
	end)
end

return Map
