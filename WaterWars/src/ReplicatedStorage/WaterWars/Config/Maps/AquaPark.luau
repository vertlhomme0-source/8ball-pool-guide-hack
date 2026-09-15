--[[
	Map 3/6 : Aqua Parc
	Un parc aquatique abandonne pour la journee. Deux tours de toboggans
	servent de bases et dominent une piscine a vagues centrale. Map tres
	verticale : les toboggans sont des raccourcis a sens unique vers le centre.
]]

local MAP_WIDTH = 310
local MAP_DEPTH = 250

local PAVEMENT = Color3.fromRGB(206, 202, 192)
local PAVEMENT_DARK = Color3.fromRGB(168, 164, 156)
local WATER = Color3.fromRGB(58, 172, 224)
local SLIDE_BLUE = Color3.fromRGB(64, 148, 238)
local SLIDE_RED = Color3.fromRGB(240, 96, 88)
local TOWER = Color3.fromRGB(236, 232, 222)

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

Map.id = "aqua_park"
Map.name = "Aqua Parc"
Map.theme = "Parc aquatique"
Map.description = "Toboggans geants, piscine a vagues et passerelles suspendues. La map la plus verticale du jeu."
Map.size = Vector2.new(MAP_WIDTH, MAP_DEPTH)
Map.killY = -30
Map.skyColor = Color3.fromRGB(160, 210, 250)

Map.lighting = {
	ClockTime = 13,
	Brightness = 2.8,
	Ambient = Color3.fromRGB(128, 132, 138),
	OutdoorAmbient = Color3.fromRGB(160, 168, 178),
	FogColor = Color3.fromRGB(205, 228, 245),
	FogStart = 240,
	FogEnd = 780,
	ColorShift_Top = Color3.fromRGB(240, 250, 255),
}

Map.spawns = {
	Blue = concat(row(-132, -34, 6, 15), row(-132, 42, 6, 15)),
	Red = concat(row(132, -34, 6, 15), row(132, 42, 6, 15)),
	FFA = concat(
		row(-116, 0, 5, 24),
		row(116, 0, 5, 24),
		row(-48, -96, 3, 26),
		row(48, 96, 3, 26),
		row(48, -96, 2, 34),
		row(-48, 96, 2, 34)
	),
}

Map.controlPoint = Vector3.new(0, 9, 0)

Map.refillStations = {
	Vector3.new(-112, 0, 0),
	Vector3.new(112, 0, 0),
	Vector3.new(0, 0, -88),
	Vector3.new(0, 0, 88),
}

Map.powerupSpots = {
	Vector3.new(0, 20, 0),
	Vector3.new(-66, 2, -74),
	Vector3.new(66, 2, 74),
	Vector3.new(-66, 2, 74),
	Vector3.new(66, 2, -74),
}

function Map.build(b)
	-- --------------------------------------------------------------- dalles
	b:Ground(MAP_WIDTH, MAP_DEPTH, { color = PAVEMENT, material = Enum.Material.Pebble })
	b:Bounds(MAP_WIDTH, MAP_DEPTH, 200)

	-- Motif de dallage pour lire les distances au sol.
	for x = -6, 6 do
		b:Block(Vector3.new(x * 24, 0.08, 0), Vector3.new(2, 0.3, MAP_DEPTH - 30), {
			name = "Tile", color = PAVEMENT_DARK, material = Enum.Material.Concrete, castShadow = false,
		})
	end

	-- ------------------------------------------------ piscine a vagues
	b:Pool(Vector3.new(0, 1, 0), Vector3.new(120, 1, 76), {
		color = WATER, floorColor = Color3.fromRGB(120, 210, 235),
		rimColor = Color3.fromRGB(246, 244, 236), depth = 5,
	})

	-- Ile centrale : le point de controle, accessible par quatre rampes.
	b:Block(Vector3.new(0, 4, 0), Vector3.new(46, 8, 40), {
		name = "Island", color = Color3.fromRGB(226, 216, 186), material = Enum.Material.Sandstone,
	})
	b:Block(Vector3.new(0, 8.5, 0), Vector3.new(30, 1, 24), {
		name = "IslandTop", color = Color3.fromRGB(240, 232, 206), material = Enum.Material.Sandstone,
	})
	b:Mirror(function(side)
		b:Ramp(Vector3.new(side * 34, 0.5, 0), 16, 24, 8, side > 0 and 90 or 270, {
			color = Color3.fromRGB(216, 206, 178), material = Enum.Material.Sandstone,
		})
		-- Parasol central : bloque les tirs en cloche sur le point.
		b:Block(Vector3.new(side * 12, 13, 0), Vector3.new(1, 8, 1), {
			name = "Pole", color = Color3.fromRGB(220, 220, 215), material = Enum.Material.Metal,
		})
		b:Cylinder(
			CFrame.new(side * 12, 17.5, 0) * CFrame.Angles(0, 0, math.rad(90)),
			Vector3.new(1, 22, 22),
			{ name = "Canopy", color = Color3.fromRGB(80, 200, 220), material = Enum.Material.Fabric, canCollide = false }
		)
	end)

	-- ----------------------------------------- tours de toboggans (bases)
	b:Mirror(function(side)
		local baseX = side * 126
		local slideColor = side < 0 and SLIDE_BLUE or SLIDE_RED

		-- Tour a trois niveaux.
		b:Tower(Vector3.new(baseX, 0, 4), 22, 42, {
			color = TOWER, railColor = Color3.fromRGB(190, 190, 185),
			pillarColor = Color3.fromRGB(150, 150, 148), levels = 3,
		})
		-- Escaliers exterieurs entre les niveaux.
		for level = 1, 3 do
			local y = (42 / 3) * (level - 1)
			b:Stairs(Vector3.new(baseX + side * 26, y, 4), 12, 22, 14, 7, side > 0 and 90 or 270, {
				color = PAVEMENT_DARK, material = Enum.Material.Concrete,
			})
			b:Block(Vector3.new(baseX + side * 26, y + 14.5, 4), Vector3.new(14, 1, 14), {
				name = "Landing", color = TOWER, material = Enum.Material.Concrete,
			})
		end

		-- Deux toboggans qui plongent vers le centre : descente rapide.
		for _, z in ipairs({ -16, 24 }) do
			local segments = 5
			for index = 1, segments do
				local progress = index / segments
				local x = baseX - side * (18 + progress * 62)
				local y = 40 - progress * 34
				b:Cylinder(
					CFrame.new(x, y, z + progress * 8) * CFrame.Angles(0, math.rad(side * 90), math.rad(90)),
					Vector3.new(16, 13, 13),
					{ name = "SlideTube", color = slideColor, material = Enum.Material.Plastic, transparency = 0.25 }
				)
				b:Block(Vector3.new(x, y - 6, z + progress * 8), Vector3.new(2, 12, 2), {
					name = "SlideSupport", color = Color3.fromRGB(170, 170, 168), material = Enum.Material.Metal,
				})
			end
		end

		-- Bassin de reception a la sortie des toboggans.
		b:Pool(Vector3.new(baseX - side * 86, 1, 4), Vector3.new(34, 1, 50), {
			color = WATER, floorColor = Color3.fromRGB(140, 215, 235),
			rimColor = Color3.fromRGB(240, 238, 230), depth = 3,
		})

		-- Kiosque : couverture au sol devant la base.
		b:Building(Vector3.new(baseX - side * 40, 0, -66), Vector3.new(28, 13, 24), {
			color = Color3.fromRGB(240, 226, 180), material = Enum.Material.Concrete,
			roofColor = slideColor, openings = { north = true, south = true },
			doorWidth = 10, doorHeight = 9,
		})
		b:Sign(Vector3.new(baseX - side * 40, 16, -78), side < 0 and "AQUA BLEU" or "AQUA ROUGE", {
			size = Vector3.new(22, 5, 0.8),
			textColor = slideColor,
		})

		-- Transats et bouees.
		for index = 1, 4 do
			b:Block(
				CFrame.new(baseX - side * 62, 1.5, -30 + index * 22) * CFrame.Angles(0, math.rad(side * 15), 0),
				Vector3.new(12, 3, 5),
				{ name = "DeckChair", color = Color3.fromRGB(246, 246, 240), material = Enum.Material.Plastic }
			)
		end
		b:Crates(Vector3.new(baseX - side * 30, 0, 74), 4, 16, { maxStack = 2, color = Color3.fromRGB(200, 200, 195) })
	end)

	-- --------------------------------------------- riviere et passerelles
	b:Mirror(function(side)
		-- Riviere lente : couloir lateral abrite.
		b:Block(Vector3.new(0, 0.1, side * 86), Vector3.new(210, 0.5, 26), {
			name = "RiverBed", color = Color3.fromRGB(120, 200, 220), material = Enum.Material.Pebble, castShadow = false,
		})
		b:Block(Vector3.new(0, 0.7, side * 86), Vector3.new(210, 0.6, 24), {
			name = "River", color = WATER, material = Enum.Material.Glass,
			transparency = 0.4, canCollide = false, castShadow = false, reflectance = 0.2,
		})
		b:Mirror(function(inner)
			b:Block(Vector3.new(inner * 106, 1.5, side * 86), Vector3.new(4, 3, 26), {
				name = "RiverEnd", color = PAVEMENT_DARK, material = Enum.Material.Concrete,
			})
		end)

		-- Passerelle suspendue au-dessus de la riviere.
		b:Bridge(Vector3.new(-92, 20, side * 86), Vector3.new(92, 20, side * 86), 14, {
			color = Color3.fromRGB(200, 198, 190), railColor = Color3.fromRGB(150, 150, 148),
			material = Enum.Material.Metal,
		})
		b:Mirror(function(inner)
			b:Stairs(Vector3.new(inner * 100, 0, side * 86), 12, 30, 20, 8, inner > 0 and 90 or 270, {
				color = PAVEMENT_DARK, material = Enum.Material.Metal,
			})
		end)

		-- Mur d'eau decoratif reliant la passerelle au centre.
		b:Block(Vector3.new(side * 60, 6, side * 46), Vector3.new(30, 12, 3), {
			name = "Screen", color = Color3.fromRGB(180, 225, 240), material = Enum.Material.Glass,
			transparency = 0.5, rotation = Vector3.new(0, side * 35, 0),
		})
	end)

	-- Machinerie centrale : couverture au bord de la piscine.
	b:Mirror(function(side)
		b:Block(Vector3.new(side * 76, 5, 0), Vector3.new(16, 10, 30), {
			name = "PumpHouse", color = Color3.fromRGB(150, 156, 164), material = Enum.Material.DiamondPlate,
		})
		b:Cylinder(
			CFrame.new(side * 76, 12, 0) * CFrame.Angles(0, 0, math.rad(90)),
			Vector3.new(30, 8, 8),
			{ name = "Pipe", color = Color3.fromRGB(120, 128, 138), material = Enum.Material.Metal }
		)
	end)
end

return Map
