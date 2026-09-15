--[[
	Map 6/6 : Arene Neon
	Arene futuriste parfaitement symetrique, sans decor superflu : plateformes
	flottantes, passerelles de verre et un anneau central sureleve. C'est la map
	competitive du lot, pensee pour les duels et le mode Roi de la piscine.
]]

local MAP_WIDTH = 280
local MAP_DEPTH = 230

local FLOOR = Color3.fromRGB(28, 32, 44)
local FLOOR_LIGHT = Color3.fromRGB(42, 48, 64)
local GLASS = Color3.fromRGB(150, 220, 255)
local NEON_BLUE = Color3.fromRGB(70, 190, 255)
local NEON_RED = Color3.fromRGB(255, 90, 110)
local NEON_CYAN = Color3.fromRGB(90, 255, 230)

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

Map.id = "neon_arena"
Map.name = "Arene Neon"
Map.theme = "Stade futuriste"
Map.description = "Une arene symetrique en verre et en neon, sans angle mort. Terrain de reference pour les duels et les tournois."
Map.size = Vector2.new(MAP_WIDTH, MAP_DEPTH)
Map.killY = -40
Map.skyColor = Color3.fromRGB(20, 24, 40)

Map.lighting = {
	ClockTime = 0.5,
	Brightness = 1.4,
	Ambient = Color3.fromRGB(70, 78, 98),
	OutdoorAmbient = Color3.fromRGB(58, 66, 88),
	FogColor = Color3.fromRGB(24, 30, 48),
	FogStart = 90,
	FogEnd = 480,
	ColorShift_Top = Color3.fromRGB(120, 160, 255),
}

Map.spawns = {
	Blue = concat(row(-116, -28, 6, 14, 14), row(-116, 40, 6, 14, 14)),
	Red = concat(row(116, -28, 6, 14, 14), row(116, 40, 6, 14, 14)),
	FFA = concat(
		row(-100, 0, 5, 22, 14),
		row(100, 0, 5, 22, 14),
		row(-44, -80, 3, 24, 4),
		row(44, 80, 3, 24, 4),
		row(44, -80, 2, 30, 4),
		row(-44, 80, 2, 30, 4)
	),
}

Map.controlPoint = Vector3.new(0, 18, 0)

Map.refillStations = {
	Vector3.new(-104, 12, 6),
	Vector3.new(104, 12, 6),
	Vector3.new(0, 0, -72),
	Vector3.new(0, 0, 72),
}

Map.powerupSpots = {
	Vector3.new(0, 28, 0),
	Vector3.new(-58, 2, -58),
	Vector3.new(58, 2, 58),
	Vector3.new(-58, 2, 58),
	Vector3.new(58, 2, -58),
}

function Map.build(b)
	-- --------------------------------------------------------------- sol
	b:Ground(MAP_WIDTH, MAP_DEPTH, { color = FLOOR, material = Enum.Material.Metal })
	b:Bounds(MAP_WIDTH, MAP_DEPTH, 220)

	-- Grille lumineuse au sol : repere visuel des distances.
	for index = -6, 6 do
		b:Block(Vector3.new(index * 22, 0.1, 0), Vector3.new(1.2, 0.3, MAP_DEPTH - 30), {
			name = "GridLine", color = NEON_CYAN, material = Enum.Material.Neon,
			canCollide = false, castShadow = false, transparency = 0.3,
		})
	end
	for index = -5, 5 do
		b:Block(Vector3.new(0, 0.1, index * 22), Vector3.new(MAP_WIDTH - 30, 0.3, 1.2), {
			name = "GridLine", color = NEON_CYAN, material = Enum.Material.Neon,
			canCollide = false, castShadow = false, transparency = 0.3,
		})
	end

	-- Mur d'enceinte lumineux.
	b:Mirror(function(side)
		b:Block(Vector3.new(side * (MAP_WIDTH / 2 - 4), 20, 0), Vector3.new(6, 40, MAP_DEPTH), {
			name = "ArenaWall", color = FLOOR_LIGHT, material = Enum.Material.Metal,
		})
		b:Block(Vector3.new(side * (MAP_WIDTH / 2 - 7.5), 30, 0), Vector3.new(1, 3, MAP_DEPTH), {
			name = "WallStrip", color = side < 0 and NEON_BLUE or NEON_RED, material = Enum.Material.Neon,
			canCollide = false, castShadow = false,
		})
		b:Block(Vector3.new(0, 20, side * (MAP_DEPTH / 2 - 4)), Vector3.new(MAP_WIDTH, 40, 6), {
			name = "ArenaWall", color = FLOOR_LIGHT, material = Enum.Material.Metal,
		})
		b:Block(Vector3.new(0, 30, side * (MAP_DEPTH / 2 - 7.5)), Vector3.new(MAP_WIDTH, 3, 1), {
			name = "WallStrip", color = NEON_CYAN, material = Enum.Material.Neon,
			canCollide = false, castShadow = false,
		})
	end)

	-- ------------------------------------------------------ anneau central
	-- Trois niveaux concentriques : plus on monte, plus on est expose.
	b:Cylinder(
		CFrame.new(0, 4, 0) * CFrame.Angles(0, 0, math.rad(90)),
		Vector3.new(8, 96, 96),
		{ name = "RingBase", color = FLOOR_LIGHT, material = Enum.Material.Metal }
	)
	b:Cylinder(
		CFrame.new(0, 11, 0) * CFrame.Angles(0, 0, math.rad(90)),
		Vector3.new(6, 68, 68),
		{ name = "RingMid", color = Color3.fromRGB(52, 58, 76), material = Enum.Material.Metal }
	)
	b:Cylinder(
		CFrame.new(0, 17, 0) * CFrame.Angles(0, 0, math.rad(90)),
		Vector3.new(6, 44, 44),
		{ name = "RingTop", color = Color3.fromRGB(64, 70, 92), material = Enum.Material.DiamondPlate }
	)
	b:Cylinder(
		CFrame.new(0, 20.4, 0) * CFrame.Angles(0, 0, math.rad(90)),
		Vector3.new(0.6, 40, 40),
		{ name = "RingGlow", color = NEON_CYAN, material = Enum.Material.Neon, canCollide = false, castShadow = false }
	)

	-- Quatre rampes d'acces a 45 degres : aucun cote n'est avantage.
	for index = 0, 3 do
		local angle = math.rad(45 + index * 90)
		local distance = 58
		local x = math.cos(angle) * distance
		local z = math.sin(angle) * distance
		b:Ramp(Vector3.new(x, 0, z), 18, 40, 8, math.deg(-angle) + 90, {
			color = Color3.fromRGB(60, 66, 86), material = Enum.Material.DiamondPlate,
		})
		b:Block(Vector3.new(x * 0.62, 12, z * 0.62), Vector3.new(14, 0.8, 14), {
			name = "RingStep", color = Color3.fromRGB(70, 78, 100), material = Enum.Material.DiamondPlate,
			rotation = Vector3.new(0, math.deg(-angle), 0),
		})
	end

	-- Colonne centrale : couverture au coeur du point.
	b:Cylinder(
		CFrame.new(0, 26, 0) * CFrame.Angles(0, 0, math.rad(90)),
		Vector3.new(14, 12, 12),
		{ name = "CorePillar", color = Color3.fromRGB(40, 46, 62), material = Enum.Material.Metal }
	)
	b:Sphere(Vector3.new(0, 34, 0), 10, {
		name = "Core", color = NEON_CYAN, material = Enum.Material.Neon, canCollide = false,
	})

	-- -------------------------------------------------- bases surelevees
	b:Mirror(function(side)
		local baseX = side * 108
		local accent = side < 0 and NEON_BLUE or NEON_RED

		-- Plateforme de depart en surplomb.
		b:Platform(Vector3.new(baseX, 12, 6), Vector3.new(56, 2, 110), {
			name = "BasePlatform", color = Color3.fromRGB(46, 52, 70), material = Enum.Material.DiamondPlate, legs = true,
		})
		b:Block(Vector3.new(baseX + side * 27, 16, 6), Vector3.new(2, 6, 110), {
			name = "BaseRail", color = accent, material = Enum.Material.Neon, castShadow = false,
		})
		b:Mirror(function(inner)
			b:Block(Vector3.new(baseX, 16, 6 + inner * 54), Vector3.new(56, 6, 2), {
				name = "BaseRail", color = accent, material = Enum.Material.Neon, castShadow = false,
			})
			-- Rampes de sortie vers le sol.
			b:Ramp(Vector3.new(baseX - side * 40, 0, 6 + inner * 40), 16, 32, 13, side > 0 and 90 or 270, {
				color = Color3.fromRGB(56, 62, 82), material = Enum.Material.DiamondPlate,
			})
		end)

		-- Auvent : protege la base des tirs en cloche.
		b:Block(Vector3.new(baseX, 30, 6), Vector3.new(60, 1.5, 114), {
			name = "BaseCanopy", color = Color3.fromRGB(36, 42, 58), material = Enum.Material.Metal,
		})
		for index = -2, 2 do
			b:Block(Vector3.new(baseX + side * 24, 21, 6 + index * 26), Vector3.new(2, 18, 2), {
				name = "CanopyPost", color = Color3.fromRGB(60, 66, 86), material = Enum.Material.Metal,
			})
		end

		-- Blocs de couverture sur la plateforme.
		for index = -1, 1 do
			b:Block(Vector3.new(baseX - side * 14, 15.5, 6 + index * 34), Vector3.new(10, 5, 14), {
				name = "Cover", color = Color3.fromRGB(58, 64, 84), material = Enum.Material.Metal,
			})
		end

		-- Piliers lumineux de flanc, couverture verticale au sol.
		for index = -2, 2 do
			if index ~= 0 then
				b:Block(Vector3.new(side * 66, 9, index * 34), Vector3.new(9, 18, 9), {
					name = "Pylon", color = FLOOR_LIGHT, material = Enum.Material.Metal,
				})
				b:Block(Vector3.new(side * 66, 19, index * 34), Vector3.new(6, 3, 6), {
					name = "PylonLight", color = NEON_CYAN, material = Enum.Material.Neon, castShadow = false,
				})
			end
		end
	end)

	-- ----------------------------------------------- passerelles de verre
	b:Mirror(function(side)
		-- Deux longues passerelles laterales reliant les bases par l'exterieur.
		b:Block(Vector3.new(0, 22, side * 76), Vector3.new(190, 1, 16), {
			name = "GlassWalk", color = GLASS, material = Enum.Material.Glass,
			transparency = 0.45, reflectance = 0.2,
		})
		b:Mirror(function(inner)
			b:Block(Vector3.new(inner * 95, 24.5, side * 76), Vector3.new(6, 6, 16), {
				name = "WalkAnchor", color = FLOOR_LIGHT, material = Enum.Material.Metal,
			})
			b:Ramp(Vector3.new(inner * 78, 14, side * 76), 14, 26, 8, inner > 0 and 90 or 270, {
				color = Color3.fromRGB(56, 62, 82), material = Enum.Material.DiamondPlate,
			})
		end)
		b:Block(Vector3.new(0, 25, side * 83.5), Vector3.new(190, 5, 1), {
			name = "WalkRail", color = NEON_CYAN, material = Enum.Material.Neon, castShadow = false,
		})

		-- Plateformes flottantes intermediaires : chemin vertical vers le centre.
		for index = -1, 1, 2 do
			b:Platform(Vector3.new(index * 46, 15, side * 44), Vector3.new(24, 1.2, 24), {
				name = "FloatPad", color = Color3.fromRGB(50, 56, 74), material = Enum.Material.DiamondPlate,
			})
			b:Block(Vector3.new(index * 46, 14.2, side * 44), Vector3.new(20, 0.5, 20), {
				name = "PadGlow", color = index < 0 and NEON_BLUE or NEON_RED, material = Enum.Material.Neon,
				canCollide = false, castShadow = false,
			})
		end

		-- Blocs de couverture bas repartis symetriquement.
		for index = -1, 1 do
			b:Block(Vector3.new(index * 34, 3, side * 30), Vector3.new(14, 6, 10), {
				name = "Cover", color = FLOOR_LIGHT, material = Enum.Material.Metal,
			})
		end
	end)
end

return Map
