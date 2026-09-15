--[[
	Map 2/6 : Baie des Eclaboussures
	Plage ouverte bordee par la mer. Deux pontons de bois servent de bases, un
	chateau de sable geant tient le centre. Les rochers et les barques offrent
	une couverture basse : c'est la map des duels a moyenne distance.
]]

local MAP_WIDTH = 340
local MAP_DEPTH = 250

local SAND = Color3.fromRGB(232, 214, 168)
local SAND_WET = Color3.fromRGB(206, 186, 140)
local WOOD = Color3.fromRGB(162, 122, 82)
local WOOD_DARK = Color3.fromRGB(118, 88, 60)
local ROCK = Color3.fromRGB(128, 126, 122)
local SEA = Color3.fromRGB(46, 152, 210)

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

Map.id = "splash_bay"
Map.name = "Baie des Eclaboussures"
Map.theme = "Plage de sable fin"
Map.description = "Une plage immense, deux pontons de bois et un chateau de sable au centre. Terrain ouvert qui recompense la precision."
Map.size = Vector2.new(MAP_WIDTH, MAP_DEPTH)
Map.killY = -30
Map.skyColor = Color3.fromRGB(170, 220, 255)

Map.lighting = {
	ClockTime = 16.5,
	Brightness = 3,
	Ambient = Color3.fromRGB(135, 130, 120),
	OutdoorAmbient = Color3.fromRGB(175, 170, 155),
	FogColor = Color3.fromRGB(225, 235, 245),
	FogStart = 260,
	FogEnd = 850,
	ColorShift_Top = Color3.fromRGB(255, 225, 180),
}

Map.spawns = {
	Blue = concat(row(-146, -30, 6, 15), row(-146, 46, 6, 15)),
	Red = concat(row(146, -30, 6, 15), row(146, 46, 6, 15)),
	FFA = concat(
		row(-128, 0, 5, 24),
		row(128, 0, 5, 24),
		row(-56, -92, 3, 28),
		row(56, 92, 3, 28),
		row(-56, 92, 2, 34),
		row(56, -92, 2, 34)
	),
}

Map.controlPoint = Vector3.new(0, 8, 0)

Map.refillStations = {
	Vector3.new(-126, 0, 8),
	Vector3.new(126, 0, 8),
	Vector3.new(0, 0, -86),
	Vector3.new(0, 0, 86),
}

Map.powerupSpots = {
	Vector3.new(0, 19, 0),
	Vector3.new(-74, 2, -70),
	Vector3.new(74, 2, 70),
	Vector3.new(-74, 2, 70),
	Vector3.new(74, 2, -70),
}

function Map.build(b)
	-- ---------------------------------------------------------------- sable
	b:Ground(MAP_WIDTH, MAP_DEPTH, { color = SAND, material = Enum.Material.Sand })
	b:Bounds(MAP_WIDTH, MAP_DEPTH, 170)

	-- Bande de sable mouille pres du rivage, puis la mer.
	b:Block(Vector3.new(0, 0.12, -108), Vector3.new(MAP_WIDTH, 0.4, 36), {
		name = "WetSand", color = SAND_WET, material = Enum.Material.Sand, castShadow = false,
	})
	b:Block(Vector3.new(0, -0.6, -190), Vector3.new(MAP_WIDTH + 400, 2, 200), {
		name = "Sea", color = SEA, material = Enum.Material.Glass,
		transparency = 0.35, canCollide = false, castShadow = false, reflectance = 0.3,
	})
	b:Block(Vector3.new(0, -0.6, 190), Vector3.new(MAP_WIDTH + 400, 2, 200), {
		name = "Sea", color = SEA, material = Enum.Material.Glass,
		transparency = 0.35, canCollide = false, castShadow = false, reflectance = 0.3,
	})

	-- ------------------------------------------------- chateau de sable
	-- Trois etages en escalier : le sommet est le meilleur poste de tir.
	local tiers = {
		{ size = Vector3.new(76, 6, 76), y = 3 },
		{ size = Vector3.new(54, 6, 54), y = 9 },
		{ size = Vector3.new(34, 6, 34), y = 15 },
	}
	for _, tier in ipairs(tiers) do
		b:Block(Vector3.new(0, tier.y, 0), tier.size, {
			name = "CastleTier", color = SAND_WET, material = Enum.Material.Sandstone,
		})
	end
	-- Tourelles d'angle
	for _, corner in ipairs({
		Vector3.new(1, 0, 1), Vector3.new(-1, 0, 1), Vector3.new(1, 0, -1), Vector3.new(-1, 0, -1),
	}) do
		b:Cylinder(
			CFrame.new(corner.X * 32, 11, corner.Z * 32) * CFrame.Angles(0, 0, math.rad(90)),
			Vector3.new(22, 12, 12),
			{ name = "CastleTurret", color = SAND, material = Enum.Material.Sandstone }
		)
		b:Block(Vector3.new(corner.X * 14, 19.5, corner.Z * 14), Vector3.new(4, 3, 4), {
			name = "Merlon", color = SAND_WET, material = Enum.Material.Sandstone,
		})
	end
	-- Quatre rampes d'acces, une par direction : le centre reste prenable.
	b:Mirror(function(side)
		b:Ramp(Vector3.new(side * 46, 0, 0), 18, 20, 6, side > 0 and 90 or 270, {
			color = SAND_WET, material = Enum.Material.Sandstone,
		})
		b:Ramp(Vector3.new(0, 0, side * 46), 18, 20, 6, side > 0 and 180 or 0, {
			color = SAND_WET, material = Enum.Material.Sandstone,
		})
		b:Stairs(Vector3.new(side * 22, 6, 0), 12, 14, 9, 5, side > 0 and 90 or 270, {
			color = SAND, material = Enum.Material.Sandstone,
		})
	end)

	-- ------------------------------------------------- pontons (2 bases)
	b:Mirror(function(side)
		local baseX = side * 134

		-- Ponton sur pilotis, legerement sureleve.
		b:Platform(Vector3.new(baseX, 6, 8), Vector3.new(58, 1.5, 96), {
			name = "Pier", color = WOOD, material = Enum.Material.WoodPlanks, legs = true, legColor = WOOD_DARK,
		})
		for offset = -44, 44, 22 do
			b:Block(Vector3.new(baseX, 8, 8 + offset), Vector3.new(58, 3, 1), {
				name = "PierPlank", color = WOOD_DARK, material = Enum.Material.WoodPlanks, castShadow = false,
			})
		end
		b:Ramp(Vector3.new(baseX - side * 34, 0, 8), 26, 18, 6, side > 0 and 90 or 270, {
			color = WOOD, material = Enum.Material.WoodPlanks,
		})

		-- Cabane du maitre nageur : point haut de la base.
		b:Tower(Vector3.new(baseX + side * 12, 6, -52), 11, 20, {
			color = WOOD, railColor = WOOD_DARK, pillarColor = WOOD_DARK, levels = 2,
		})
		b:Block(Vector3.new(baseX + side * 12, 29, -52), Vector3.new(26, 1, 26), {
			name = "TowerRoof", color = side < 0 and Color3.fromRGB(70, 140, 220) or Color3.fromRGB(220, 90, 80),
			material = Enum.Material.Fabric,
		})
		b:Stairs(Vector3.new(baseX + side * 12, 6, -34), 10, 16, 10, 6, 180, {
			color = WOOD_DARK, material = Enum.Material.WoodPlanks,
		})

		-- Barques retournees : couverture avancee.
		b:Mirror(function(inner)
			b:Block(
				CFrame.new(baseX - side * 46, 2.2, inner * 56) * CFrame.Angles(0, math.rad(inner * 22), math.rad(8)),
				Vector3.new(30, 4.5, 11),
				{ name = "Boat", color = Color3.fromRGB(205, 205, 200), material = Enum.Material.Plastic }
			)
		end)

		-- Parasols : couverture haute qui bloque les tirs en cloche.
		for _, z in ipairs({ -78, 74 }) do
			b:Block(Vector3.new(baseX - side * 62, 5, z), Vector3.new(1, 10, 1), {
				name = "UmbrellaPole", color = Color3.fromRGB(230, 230, 225), material = Enum.Material.Metal,
			})
			b:Cylinder(
				CFrame.new(baseX - side * 62, 10.5, z) * CFrame.Angles(0, 0, math.rad(90)),
				Vector3.new(1, 24, 24),
				{ name = "Umbrella", color = Color3.fromRGB(240, 120, 110), material = Enum.Material.Fabric }
			)
		end

		-- Recifs rocheux : le seul relief naturel des flancs.
		for index = 1, 4 do
			local scale = 10 + index * 3
			b:Sphere(
				Vector3.new(baseX - side * (30 + index * 18), scale * 0.22, 96 - index * 8),
				scale,
				{ name = "Rock", color = ROCK, material = Enum.Material.Slate }
			)
		end
	end)

	-- ------------------------------------------------ couloirs lateraux
	b:Mirror(function(side)
		-- Digue de rochers qui casse la ligne de vue d'un bout a l'autre.
		for index = -3, 3 do
			b:Block(
				CFrame.new(index * 26, 3.5, side * 74) * CFrame.Angles(0, math.rad(index * 12), 0),
				Vector3.new(18, 7, 12),
				{ name = "Breakwater", color = ROCK, material = Enum.Material.Slate }
			)
		end
		-- Passerelle en bois au-dessus de la digue.
		b:Bridge(Vector3.new(-56, 11, side * 74), Vector3.new(56, 11, side * 74), 12, {
			color = WOOD, railColor = WOOD_DARK,
		})
		b:Ramp(Vector3.new(-70, 0, side * 74), 14, 22, 11, 270, { color = WOOD, material = Enum.Material.WoodPlanks })
		b:Ramp(Vector3.new(70, 0, side * 74), 14, 22, 11, 90, { color = WOOD, material = Enum.Material.WoodPlanks })

		b:Crates(Vector3.new(side * 84, 0, -side * 28), 4, 18, { maxStack = 2, color = WOOD })
	end)

	-- ------------------------------------------------------------ palmiers
	local palmSpots = {
		Vector3.new(-100, 0, 104), Vector3.new(100, 0, 104),
		Vector3.new(-40, 0, 110), Vector3.new(40, 0, 110),
		Vector3.new(-158, 0, 98), Vector3.new(158, 0, 98),
		Vector3.new(-158, 0, -66), Vector3.new(158, 0, -66),
	}
	for index, spot in ipairs(palmSpots) do
		b:Tree(spot, 1.1 + (index % 3) * 0.15, {
			trunkColor = Color3.fromRGB(150, 118, 80),
			leafColor = Color3.fromRGB(86, 168, 92),
		})
	end
end

return Map
