--[[
	Map 1/6 : Jardin d'Ete
	Une grande bataille d'arriere-cour : deux maisons face a face, une piscine
	centrale, du mobilier de jardin en guise de couverture. Map d'initiation :
	lisible, ouverte, avec des angles courts et un centre disputable.
]]

local MAP_WIDTH = 320
local MAP_DEPTH = 230

local GRASS = Color3.fromRGB(96, 152, 82)
local GRASS_DARK = Color3.fromRGB(78, 128, 68)
local DECK = Color3.fromRGB(186, 148, 104)
local HOUSE_BLUE = Color3.fromRGB(196, 214, 236)
local HOUSE_RED = Color3.fromRGB(236, 196, 190)
local ROOF = Color3.fromRGB(122, 74, 62)

--- Genere une ligne de points d'apparition alignes sur Z.
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

Map.id = "backyard"
Map.name = "Jardin d'Ete"
Map.theme = "Banlieue ensoleillee"
Map.description = "Deux maisons, une piscine au milieu et beaucoup de mobilier de jardin. La map parfaite pour apprendre le jeu."
Map.size = Vector2.new(MAP_WIDTH, MAP_DEPTH)
Map.killY = -35
Map.skyColor = Color3.fromRGB(150, 205, 255)

Map.lighting = {
	ClockTime = 14,
	Brightness = 2.6,
	Ambient = Color3.fromRGB(120, 125, 130),
	OutdoorAmbient = Color3.fromRGB(150, 160, 170),
	FogColor = Color3.fromRGB(190, 220, 245),
	FogStart = 220,
	FogEnd = 700,
	ColorShift_Top = Color3.fromRGB(255, 240, 210),
}

Map.spawns = {
	Blue = concat(row(-138, -20, 6, 14), row(-138, 52, 6, 14)),
	Red = concat(row(138, -20, 6, 14), row(138, 52, 6, 14)),
	FFA = concat(
		row(-120, 0, 5, 22),
		row(120, 0, 5, 22),
		row(-45, -85, 3, 26),
		row(45, 85, 3, 26),
		row(0, -95, 2, 40),
		row(0, 95, 2, 40)
	),
}

Map.controlPoint = Vector3.new(0, 3, 0)

Map.refillStations = {
	Vector3.new(-118, 0, 0),
	Vector3.new(118, 0, 0),
	Vector3.new(0, 0, -78),
	Vector3.new(0, 0, 78),
}

Map.powerupSpots = {
	Vector3.new(0, 12, 0),
	Vector3.new(-62, 2, -62),
	Vector3.new(62, 2, 62),
	Vector3.new(-62, 2, 62),
	Vector3.new(62, 2, -62),
}

function Map.build(b)
	-- ----------------------------------------------------------------- sol
	b:Ground(MAP_WIDTH, MAP_DEPTH, { color = GRASS, material = Enum.Material.Grass })
	b:Bounds(MAP_WIDTH, MAP_DEPTH, 160)

	-- Allee centrale en dalles, elle guide le joueur vers le point chaud.
	b:Block(Vector3.new(0, 0.1, 0), Vector3.new(36, 0.4, MAP_DEPTH - 40), {
		name = "Path", color = Color3.fromRGB(205, 200, 185), material = Enum.Material.Concrete, castShadow = false,
	})

	-- ------------------------------------------------------------- piscine
	b:Block(Vector3.new(0, 0.3, 0), Vector3.new(96, 0.6, 62), {
		name = "PoolDeck", color = DECK, material = Enum.Material.WoodPlanks,
	})
	b:Pool(Vector3.new(0, 0.6, 0), Vector3.new(70, 1, 42), {
		color = Color3.fromRGB(64, 176, 226),
		floorColor = Color3.fromRGB(120, 205, 225),
		rimColor = Color3.fromRGB(238, 236, 226),
		depth = 4,
	})

	-- Plongeoir central : le point haut le plus expose de la map.
	b:Block(Vector3.new(0, 5, 0), Vector3.new(22, 1, 14), {
		name = "DivingPlatform", color = Color3.fromRGB(235, 235, 230), material = Enum.Material.Concrete,
	})
	b:Mirror(function(side)
		b:Block(Vector3.new(side * 9, 2.5, 0), Vector3.new(2, 5, 12), {
			name = "PlatformLeg", color = Color3.fromRGB(180, 180, 175), material = Enum.Material.Metal,
		})
		b:Ramp(Vector3.new(side * 20, 0.5, 0), 10, 14, 4.5, side > 0 and 90 or 270, {
			color = Color3.fromRGB(225, 225, 220),
		})
	end)

	-- --------------------------------------------------- maisons (2 bases)
	b:Mirror(function(side)
		local baseX = side * 122
		local houseColor = side < 0 and HOUSE_BLUE or HOUSE_RED

		b:Building(Vector3.new(baseX, 0, 16), Vector3.new(58, 18, 74), {
			color = houseColor,
			material = Enum.Material.Brick,
			roofColor = ROOF,
			floorColor = Color3.fromRGB(150, 122, 96),
			openings = { north = true, south = true, east = side < 0, west = side > 0 },
			doorWidth = 14,
			doorHeight = 11,
			wallThickness = 2,
		})

		-- Terrasse et marches devant la maison, cote terrain.
		local porchX = baseX - side * 38
		b:Block(Vector3.new(porchX, 1, 16), Vector3.new(20, 2, 58), {
			name = "Porch", color = DECK, material = Enum.Material.WoodPlanks,
		})
		b:Stairs(Vector3.new(porchX - side * 13, 0, 16), 24, 8, 2, 4, side > 0 and 90 or 270, {
			color = DECK, material = Enum.Material.WoodPlanks,
		})

		-- Toit accessible : une echelle de caisses puis un poste de tir.
		b:Crates(Vector3.new(baseX - side * 34, 0, -26), 3, 8, { maxStack = 3, size = 6 })
		b:Platform(Vector3.new(baseX, 19.5, 16), Vector3.new(50, 1, 62), {
			name = "RoofDeck", color = ROOF, material = Enum.Material.Slate,
		})
		b:Mirror(function(inner)
			b:Block(Vector3.new(baseX + inner * 24, 21.5, 16), Vector3.new(2, 4, 62), {
				name = "RoofRail", color = Color3.fromRGB(96, 60, 50), material = Enum.Material.Slate,
			})
		end)

		-- Cabane de jardin : couverture avancee sur un flanc.
		b:Building(Vector3.new(baseX - side * 50, 0, -72), Vector3.new(26, 12, 22), {
			color = Color3.fromRGB(150, 118, 88),
			material = Enum.Material.WoodPlanks,
			roofColor = Color3.fromRGB(90, 70, 55),
			openings = { north = true, south = true },
			doorWidth = 8,
			doorHeight = 8,
		})

		-- Trampoline : saut d'attaque vers le centre.
		b:Cylinder(
			CFrame.new(baseX - side * 62, 3, 66) * CFrame.Angles(0, 0, math.rad(90)),
			Vector3.new(3, 26, 26),
			{ name = "Trampoline", color = Color3.fromRGB(40, 44, 58), material = Enum.Material.Fabric }
		)
		b:Cylinder(
			CFrame.new(baseX - side * 62, 1.5, 66) * CFrame.Angles(0, 0, math.rad(90)),
			Vector3.new(3, 30, 30),
			{ name = "TrampolineFrame", color = Color3.fromRGB(70, 130, 200), material = Enum.Material.Metal }
		)

		-- Haies et mobilier pour casser les lignes de tir.
		b:Block(Vector3.new(baseX - side * 62, 2.5, -20), Vector3.new(6, 5, 40), {
			name = "Hedge", color = GRASS_DARK, material = Enum.Material.Grass,
		})
		b:Block(Vector3.new(baseX - side * 72, 2, 34), Vector3.new(5, 4, 30), {
			name = "Hedge", color = GRASS_DARK, material = Enum.Material.Grass,
		})

		-- Table de jardin renversee, couverture basse.
		b:Block(Vector3.new(baseX - side * 80, 2, -48), Vector3.new(14, 4, 8), {
			name = "Table", color = Color3.fromRGB(215, 210, 200), material = Enum.Material.Plastic,
			rotation = Vector3.new(0, 25 * side, 0),
		})
	end)

	-- ------------------------------------------- flancs : jeu exterieur
	b:Mirror(function(side)
		-- Terrasse laterale surelevee reliant les deux moities du terrain.
		b:Platform(Vector3.new(0, 8, side * 84), Vector3.new(120, 1.2, 26), {
			name = "SideDeck", color = DECK, material = Enum.Material.WoodPlanks, legs = true,
		})
		b:Mirror(function(inner)
			b:Ramp(Vector3.new(inner * 70, 0, side * 84), 22, 26, 8, inner > 0 and 90 or 270, {
				color = DECK, material = Enum.Material.WoodPlanks,
			})
			b:Block(Vector3.new(inner * 58, 10.5, side * 84), Vector3.new(4, 4, 26), {
				name = "DeckRail", color = Color3.fromRGB(150, 118, 84), material = Enum.Material.WoodPlanks,
			})
		end)

		-- Barbecue et caisses sous la terrasse.
		b:Block(Vector3.new(side * 26, 2, side * 62), Vector3.new(10, 4, 7), {
			name = "Grill", color = Color3.fromRGB(45, 48, 55), material = Enum.Material.Metal,
		})
		b:Crates(Vector3.new(-side * 34, 0, side * 58), 4, 16, { maxStack = 2 })
		b:Crates(Vector3.new(side * 50, 0, side * 40), 3, 14, { maxStack = 2, color = Color3.fromRGB(150, 110, 60) })
	end)

	-- ------------------------------------------------------- vegetation
	local treeSpots = {
		Vector3.new(-88, 0, -92), Vector3.new(88, 0, 92),
		Vector3.new(-88, 0, 92), Vector3.new(88, 0, -92),
		Vector3.new(-30, 0, -100), Vector3.new(30, 0, 100),
		Vector3.new(-150, 0, -95), Vector3.new(150, 0, 95),
	}
	for index, spot in ipairs(treeSpots) do
		b:Tree(spot, 1 + (index % 3) * 0.18, {
			leafColor = index % 2 == 0 and Color3.fromRGB(74, 146, 74) or Color3.fromRGB(88, 160, 78),
		})
	end

	-- Cloture peripherique, purement visuelle (les limites sont invisibles).
	local halfWidth = MAP_WIDTH / 2 - 8
	local halfDepth = MAP_DEPTH / 2 - 8
	b:Fence(Vector3.new(-halfWidth, 0, -halfDepth), Vector3.new(halfWidth, 0, -halfDepth), 12)
	b:Fence(Vector3.new(-halfWidth, 0, halfDepth), Vector3.new(halfWidth, 0, halfDepth), 12)
	b:Fence(Vector3.new(-halfWidth, 0, -halfDepth), Vector3.new(-halfWidth, 0, halfDepth), 12)
	b:Fence(Vector3.new(halfWidth, 0, -halfDepth), Vector3.new(halfWidth, 0, halfDepth), 12)
end

return Map
