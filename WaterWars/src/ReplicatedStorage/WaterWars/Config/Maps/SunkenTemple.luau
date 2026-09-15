--[[
	Map 5/6 : Temple Englouti
	Des ruines envahies par la jungle autour d'un bassin sacre. Pyramide
	centrale a gradins, galeries couvertes sur les flancs, cascades en fond.
	Map de controle : celui qui tient les gradins tient la partie.
]]

local MAP_WIDTH = 320
local MAP_DEPTH = 250

local STONE = Color3.fromRGB(148, 144, 132)
local STONE_DARK = Color3.fromRGB(112, 110, 100)
local MOSS = Color3.fromRGB(92, 128, 74)
local JUNGLE = Color3.fromRGB(64, 104, 58)
local WATER = Color3.fromRGB(60, 168, 186)
local GOLD = Color3.fromRGB(222, 186, 96)

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

Map.id = "sunken_temple"
Map.name = "Temple Englouti"
Map.theme = "Ruines dans la jungle"
Map.description = "Une pyramide a gradins au milieu d'un bassin sacre, entouree de galeries de pierre et de cascades."
Map.size = Vector2.new(MAP_WIDTH, MAP_DEPTH)
Map.killY = -35
Map.skyColor = Color3.fromRGB(120, 170, 160)

Map.lighting = {
	ClockTime = 9.5,
	Brightness = 2.2,
	Ambient = Color3.fromRGB(104, 112, 100),
	OutdoorAmbient = Color3.fromRGB(128, 142, 126),
	FogColor = Color3.fromRGB(150, 180, 160),
	FogStart = 120,
	FogEnd = 620,
	ColorShift_Top = Color3.fromRGB(220, 240, 210),
}

Map.spawns = {
	Blue = concat(row(-140, -30, 6, 15), row(-140, 44, 6, 15)),
	Red = concat(row(140, -30, 6, 15), row(140, 44, 6, 15)),
	FFA = concat(
		row(-122, 0, 5, 24),
		row(122, 0, 5, 24),
		row(-52, -94, 3, 26),
		row(52, 94, 3, 26),
		row(52, -94, 2, 34),
		row(-52, 94, 2, 34)
	),
}

Map.controlPoint = Vector3.new(0, 24, 0)

Map.refillStations = {
	Vector3.new(-120, 0, 0),
	Vector3.new(120, 0, 0),
	Vector3.new(0, 0, -84),
	Vector3.new(0, 0, 84),
}

Map.powerupSpots = {
	Vector3.new(0, 34, 0),
	Vector3.new(-70, 2, -68),
	Vector3.new(70, 2, 68),
	Vector3.new(-70, 2, 68),
	Vector3.new(70, 2, -68),
}

function Map.build(b)
	-- ------------------------------------------------------------ jungle
	b:Ground(MAP_WIDTH, MAP_DEPTH, { color = JUNGLE, material = Enum.Material.Grass })
	b:Bounds(MAP_WIDTH, MAP_DEPTH, 200)

	-- Dallage antique autour du temple.
	b:Block(Vector3.new(0, 0.15, 0), Vector3.new(190, 0.5, 170), {
		name = "Plaza", color = STONE, material = Enum.Material.Slate, castShadow = false,
	})
	for index = -4, 4 do
		b:Block(Vector3.new(index * 22, 0.25, 0), Vector3.new(1.5, 0.5, 168), {
			name = "PlazaLine", color = STONE_DARK, material = Enum.Material.Slate, castShadow = false,
		})
	end

	-- ------------------------------------------------- bassin et pyramide
	b:Pool(Vector3.new(0, 1.2, 0), Vector3.new(120, 1, 100), {
		color = WATER, floorColor = Color3.fromRGB(110, 190, 190),
		rimColor = STONE, depth = 4,
	})

	-- Pyramide a quatre gradins.
	local tiers = {
		{ size = 92, y = 4 },
		{ size = 72, y = 10 },
		{ size = 52, y = 16 },
		{ size = 34, y = 22 },
	}
	for index, tier in ipairs(tiers) do
		b:Block(Vector3.new(0, tier.y, 0), Vector3.new(tier.size, 6, tier.size * 0.85), {
			name = "TempleTier",
			color = index % 2 == 0 and STONE or STONE_DARK,
			material = Enum.Material.Slate,
		})
		-- Mousse sur les aretes.
		b:Block(Vector3.new(0, tier.y + 3.2, 0), Vector3.new(tier.size - 4, 0.6, tier.size * 0.85 - 4), {
			name = "Moss", color = MOSS, material = Enum.Material.Grass, castShadow = false, canCollide = false,
		})
	end

	-- Sanctuaire au sommet : le point de controle, abrite par quatre piliers.
	b:Block(Vector3.new(0, 25.5, 0), Vector3.new(26, 1, 22), {
		name = "Shrine", color = GOLD, material = Enum.Material.Sandstone,
	})
	for _, corner in ipairs({
		Vector3.new(11, 0, 9), Vector3.new(-11, 0, 9), Vector3.new(11, 0, -9), Vector3.new(-11, 0, -9),
	}) do
		b:Cylinder(
			CFrame.new(corner.X, 31, corner.Z) * CFrame.Angles(0, 0, math.rad(90)),
			Vector3.new(11, 3.2, 3.2),
			{ name = "ShrinePillar", color = STONE, material = Enum.Material.Sandstone }
		)
	end
	b:Block(Vector3.new(0, 37, 0), Vector3.new(30, 1.5, 26), {
		name = "ShrineRoof", color = STONE_DARK, material = Enum.Material.Slate,
	})

	-- Escaliers monumentaux sur les quatre faces.
	b:Mirror(function(side)
		b:Stairs(Vector3.new(side * 60, 0, 0), 26, 32, 25, 10, side > 0 and 90 or 270, {
			color = STONE, material = Enum.Material.Slate,
		})
		b:Stairs(Vector3.new(0, 0, side * 56), 26, 30, 25, 10, side > 0 and 180 or 0, {
			color = STONE, material = Enum.Material.Slate,
		})
	end)

	-- ------------------------------------------------ galeries (2 bases)
	b:Mirror(function(side)
		local baseX = side * 130
		local accent = side < 0 and Color3.fromRGB(70, 150, 230) or Color3.fromRGB(230, 100, 80)

		-- Grande salle couverte a colonnes.
		b:Building(Vector3.new(baseX, 0, 8), Vector3.new(62, 22, 96), {
			color = STONE, material = Enum.Material.Sandstone,
			roofColor = STONE_DARK, roofMaterial = Enum.Material.Slate,
			floorColor = Color3.fromRGB(132, 128, 118), floorMaterial = Enum.Material.Slate,
			openings = { north = true, south = true, east = side < 0, west = side > 0 },
			doorWidth = 18, doorHeight = 14, wallThickness = 3,
		})
		-- Colonnes interieures.
		for index = -1, 1 do
			b:Mirror(function(inner)
				b:Cylinder(
					CFrame.new(baseX + inner * 20, 11, 8 + index * 30) * CFrame.Angles(0, 0, math.rad(90)),
					Vector3.new(22, 5, 5),
					{ name = "Column", color = STONE, material = Enum.Material.Sandstone }
				)
			end)
		end
		-- Terrasse sur le toit de la galerie.
		b:Platform(Vector3.new(baseX, 23.5, 8), Vector3.new(58, 1, 92), {
			name = "GalleryRoof", color = STONE_DARK, material = Enum.Material.Slate,
		})
		b:Mirror(function(inner)
			b:Block(Vector3.new(baseX + inner * 28, 26, 8), Vector3.new(2, 5, 92), {
				name = "RoofEdge", color = STONE, material = Enum.Material.Sandstone,
			})
		end)
		b:Stairs(Vector3.new(baseX + side * 36, 0, 8), 14, 26, 23, 9, side > 0 and 90 or 270, {
			color = STONE_DARK, material = Enum.Material.Slate,
		})

		-- Statue gardienne devant la base.
		b:Block(Vector3.new(baseX - side * 44, 5, -56), Vector3.new(12, 10, 12), {
			name = "StatueBase", color = STONE_DARK, material = Enum.Material.Slate,
		})
		b:Block(Vector3.new(baseX - side * 44, 15, -56), Vector3.new(8, 10, 8), {
			name = "Statue", color = GOLD, material = Enum.Material.Sandstone,
		})
		b:Sphere(Vector3.new(baseX - side * 44, 23, -56), 8, {
			name = "StatueHead", color = GOLD, material = Enum.Material.Sandstone,
		})
		b:Block(Vector3.new(baseX - side * 44, 28, -56), Vector3.new(10, 3, 10), {
			name = "StatueCrown", color = accent, material = Enum.Material.Neon, canCollide = false,
		})

		-- Cascade en fond de base.
		b:Block(Vector3.new(baseX + side * 26, 30, 70), Vector3.new(4, 60, 34), {
			name = "Waterfall", color = Color3.fromRGB(180, 230, 240), material = Enum.Material.Glass,
			transparency = 0.35, canCollide = false, castShadow = false,
			rotation = Vector3.new(0, side * 20, 0),
		})
		b:Block(Vector3.new(baseX + side * 26, 1.2, 70), Vector3.new(30, 1, 30), {
			name = "WaterfallPool", color = WATER, material = Enum.Material.Glass,
			transparency = 0.4, canCollide = false, castShadow = false,
		})

		-- Colonnes brisees : couverture de milieu de terrain.
		for index = 1, 5 do
			local height = 8 + (index % 3) * 7
			b:Cylinder(
				CFrame.new(baseX - side * (58 + index * 12), height / 2, -70 + index * 30) * CFrame.Angles(0, 0, math.rad(90)),
				Vector3.new(height, 7, 7),
				{ name = "BrokenColumn", color = index % 2 == 0 and STONE or STONE_DARK, material = Enum.Material.Sandstone }
			)
		end
	end)

	-- --------------------------------------------- galeries transversales
	b:Mirror(function(side)
		-- Mur de ruines qui borde le terrain au nord et au sud.
		for index = -3, 3 do
			local height = 12 + (index % 2) * 6
			b:Block(Vector3.new(index * 30, height / 2, side * 96), Vector3.new(24, height, 6), {
				name = "RuinWall", color = STONE, material = Enum.Material.Sandstone,
			})
		end
		-- Passerelle de lianes reliant les deux cotes par l'exterieur.
		b:Bridge(Vector3.new(-70, 16, side * 88), Vector3.new(70, 16, side * 88), 12, {
			color = Color3.fromRGB(122, 96, 62), railColor = MOSS,
		})
		b:Mirror(function(inner)
			b:Stairs(Vector3.new(inner * 80, 0, side * 88), 12, 24, 16, 8, inner > 0 and 90 or 270, {
				color = STONE_DARK, material = Enum.Material.Slate,
			})
		end)
	end)

	-- ---------------------------------------------------------- vegetation
	local treeSpots = {
		Vector3.new(-104, 0, -104), Vector3.new(104, 0, 104),
		Vector3.new(-104, 0, 104), Vector3.new(104, 0, -104),
		Vector3.new(-152, 0, -40), Vector3.new(152, 0, 40),
		Vector3.new(-152, 0, 74), Vector3.new(152, 0, -74),
		Vector3.new(-24, 0, -112), Vector3.new(24, 0, 112),
	}
	for index, spot in ipairs(treeSpots) do
		b:Tree(spot, 1.3 + (index % 3) * 0.2, {
			trunkColor = Color3.fromRGB(96, 74, 54),
			leafColor = index % 2 == 0 and Color3.fromRGB(56, 116, 56) or MOSS,
		})
	end
end

return Map
