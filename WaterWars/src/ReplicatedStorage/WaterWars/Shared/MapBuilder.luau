--[[
	MapBuilder
	Petite bibliotheque de construction utilisee par les 6 maps.

	Chaque map recoit un "builder" et decrit son terrain avec des primitives
	lisibles (bloc, mur, rampe, batiment, piscine, pont, caisses...). Tout est
	genere au demarrage de la manche : aucun asset externe, aucun ID a uploader.

	Toutes les pieces sont ancrees et regroupees dans un Model unique, ce qui
	rend le nettoyage de fin de manche instantane (Model:Destroy()).
]]

local MapBuilder = {}
MapBuilder.__index = MapBuilder

local DEFAULT_MATERIAL = Enum.Material.SmoothPlastic

--- Cree un builder qui depose ses pieces dans `container`.
function MapBuilder.new(container, seed)
	local self = setmetatable({}, MapBuilder)
	self.container = container
	self.rng = Random.new(seed or 1337)
	self.count = 0
	return self
end

local function toCFrame(position, rotation)
	local cf
	if typeof(position) == "CFrame" then
		cf = position
	else
		cf = CFrame.new(position)
	end
	if rotation then
		cf = cf * CFrame.Angles(math.rad(rotation.X), math.rad(rotation.Y), math.rad(rotation.Z))
	end
	return cf
end

--- Primitive de base : un BasePart ancre, place et colore.
function MapBuilder:Part(className, position, size, options)
	options = options or {}
	-- className vaut toujours "Part" ou "WedgePart" : les deux sont des BasePart.
	local part = Instance.new(className) :: BasePart
	part.Name = options.name or "Part"
	part.Size = size
	part.CFrame = toCFrame(position, options.rotation)
	part.Anchored = true
	local canCollide = options.canCollide ~= false
	part.CanCollide = canCollide
	-- Le decor traversable ne doit pas non plus arreter les projectiles.
	if options.canQuery ~= nil then
		part.CanQuery = options.canQuery
	else
		part.CanQuery = canCollide
	end
	part.CanTouch = false
	part.CastShadow = options.castShadow ~= false
	part.Material = options.material or DEFAULT_MATERIAL
	part.Color = options.color or Color3.fromRGB(180, 180, 180)
	part.Transparency = options.transparency or 0
	part.Reflectance = options.reflectance or 0
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth

	if options.shape and part:IsA("Part") then
		part.Shape = options.shape
	end
	if options.collisionGroup then
		part.CollisionGroup = options.collisionGroup
	end
	part.Parent = self.container
	self.count = self.count + 1
	return part
end

--- Bloc rectangulaire (le pain quotidien des maps).
function MapBuilder:Block(position, size, options)
	return self:Part("Part", position, size, options)
end

--- Rampe (WedgePart). `rotation.Y` oriente la pente.
function MapBuilder:Wedge(position, size, options)
	return self:Part("WedgePart", position, size, options)
end

--- Cylindre couche ou debout selon la rotation fournie.
function MapBuilder:Cylinder(position, size, options)
	options = options or {}
	local merged = table.clone(options)
	merged.shape = Enum.PartType.Cylinder
	return self:Part("Part", position, size, merged)
end

--- Sphere.
function MapBuilder:Sphere(position, diameter, options)
	options = options or {}
	local merged = table.clone(options)
	merged.shape = Enum.PartType.Ball
	return self:Part("Part", position, Vector3.new(diameter, diameter, diameter), merged)
end

--- Sol principal de la map, centre sur l'origine.
function MapBuilder:Ground(width, depth, options)
	options = options or {}
	local thickness = options.thickness or 4
	local ground = self:Block(Vector3.new(0, -thickness / 2, 0), Vector3.new(width, thickness, depth), {
		name = "Ground",
		color = options.color or Color3.fromRGB(90, 140, 80),
		material = options.material or Enum.Material.Grass,
	})
	return ground
end

--- Plateforme surelevee : dalle + support optionnel.
function MapBuilder:Platform(position, size, options)
	options = options or {}
	local slab = self:Block(position, size, {
		name = options.name or "Platform",
		color = options.color or Color3.fromRGB(150, 150, 155),
		material = options.material or Enum.Material.Concrete,
		rotation = options.rotation,
	})
	if options.legs then
		local legSize = Vector3.new(1.2, position.Y - size.Y / 2, 1.2)
		if legSize.Y > 0.5 then
			local dx = size.X / 2 - 1.5
			local dz = size.Z / 2 - 1.5
			for _, offset in ipairs({
				Vector3.new(dx, 0, dz), Vector3.new(-dx, 0, dz),
				Vector3.new(dx, 0, -dz), Vector3.new(-dx, 0, -dz),
			}) do
				self:Block(
					Vector3.new(position.X + offset.X, legSize.Y / 2, position.Z + offset.Z),
					legSize,
					{ name = "Leg", color = options.legColor or Color3.fromRGB(110, 110, 115), material = Enum.Material.Metal }
				)
			end
		end
	end
	return slab
end

--- Mur droit entre deux points, avec hauteur et epaisseur.
function MapBuilder:Wall(fromPosition, toPosition, height, thickness, options)
	options = options or {}
	local delta = toPosition - fromPosition
	local length = delta.Magnitude
	if length < 0.05 then
		return nil
	end
	local center = fromPosition + delta * 0.5 + Vector3.new(0, height / 2, 0)
	local angle = math.atan2(-delta.Z, delta.X)
	local part = self:Block(
		CFrame.new(center) * CFrame.Angles(0, angle, 0),
		Vector3.new(length, height, thickness),
		{
			name = options.name or "Wall",
			color = options.color or Color3.fromRGB(160, 160, 165),
			material = options.material or Enum.Material.Concrete,
			transparency = options.transparency or 0,
			canCollide = options.canCollide,
		}
	)
	return part
end

--- Rampe praticable entre deux hauteurs.
function MapBuilder:Ramp(position, width, length, height, rotationY, options)
	options = options or {}
	return self:Wedge(
		CFrame.new(position + Vector3.new(0, height / 2, 0)) * CFrame.Angles(0, math.rad(rotationY), 0),
		Vector3.new(width, height, length),
		{
			name = options.name or "Ramp",
			color = options.color or Color3.fromRGB(150, 150, 155),
			material = options.material or Enum.Material.Concrete,
		}
	)
end

--- Escalier a marches.
function MapBuilder:Stairs(position, width, totalRun, totalRise, steps, rotationY, options)
	options = options or {}
	local stepRun = totalRun / steps
	local stepRise = totalRise / steps
	local yaw = math.rad(rotationY or 0)
	for index = 1, steps do
		local along = -totalRun / 2 + stepRun * (index - 0.5)
		local height = stepRise * index
		-- Chaque marche part du sol : sa hauteur augmente a mesure qu'on avance.
		local cf = CFrame.new(position)
			* CFrame.Angles(0, yaw, 0)
			* CFrame.new(0, height / 2, along)
		self:Block(cf, Vector3.new(width, height, stepRun), {
			name = "Step",
			color = options.color or Color3.fromRGB(150, 150, 155),
			material = options.material or Enum.Material.Concrete,
		})
	end
end

--- Bassin d'eau decoratif (non bloquant, legerement transparent).
function MapBuilder:Pool(position, size, options)
	options = options or {}
	local depth = options.depth or 3
	-- Cuvette
	self:Block(position - Vector3.new(0, depth + 0.5, 0), Vector3.new(size.X, 1, size.Z), {
		name = "PoolFloor",
		color = options.floorColor or Color3.fromRGB(90, 190, 210),
		material = Enum.Material.Pebble,
	})
	local rim = options.rim
	if rim ~= false then
		local rimColor = options.rimColor or Color3.fromRGB(230, 230, 220)
		local halfX, halfZ = size.X / 2, size.Z / 2
		self:Block(position + Vector3.new(0, 0.2, halfZ + 1), Vector3.new(size.X + 4, 1.4, 2), { color = rimColor, material = Enum.Material.Concrete, name = "PoolRim" })
		self:Block(position + Vector3.new(0, 0.2, -halfZ - 1), Vector3.new(size.X + 4, 1.4, 2), { color = rimColor, material = Enum.Material.Concrete, name = "PoolRim" })
		self:Block(position + Vector3.new(halfX + 1, 0.2, 0), Vector3.new(2, 1.4, size.Z), { color = rimColor, material = Enum.Material.Concrete, name = "PoolRim" })
		self:Block(position + Vector3.new(-halfX - 1, 0.2, 0), Vector3.new(2, 1.4, size.Z), { color = rimColor, material = Enum.Material.Concrete, name = "PoolRim" })
	end
	-- Surface
	local water = self:Block(position, Vector3.new(size.X, 0.6, size.Z), {
		name = "Water",
		color = options.color or Color3.fromRGB(70, 180, 230),
		material = Enum.Material.Glass,
		transparency = 0.45,
		canCollide = false,
		castShadow = false,
		reflectance = 0.25,
	})
	return water
end

--- Batiment creux avec ouvertures : la base des zones de combat interieures.
function MapBuilder:Building(position, size, options)
	options = options or {}
	local wallThickness = options.wallThickness or 1.5
	local color = options.color or Color3.fromRGB(190, 180, 165)
	local material = options.material or Enum.Material.Brick
	local halfX, halfZ = size.X / 2, size.Z / 2
	local centerY = position.Y + size.Y / 2
	local openings = options.openings or { north = true, south = true }
	local doorWidth = options.doorWidth or 10
	local doorHeight = options.doorHeight or 9

	local function buildSide(axis, sign)
		local isX = axis == "x"
		local sideLength = isX and size.Z or size.X
		local key
		if isX then
			key = sign > 0 and "east" or "west"
		else
			key = sign > 0 and "north" or "south"
		end
		local hasDoor = openings[key] == true
		local wallCenter = isX
			and Vector3.new(position.X + sign * halfX, centerY, position.Z)
			or Vector3.new(position.X, centerY, position.Z + sign * halfZ)
		local wallSize = isX
			and Vector3.new(wallThickness, size.Y, sideLength)
			or Vector3.new(sideLength, size.Y, wallThickness)

		if not hasDoor then
			self:Block(wallCenter, wallSize, { name = "BuildingWall", color = color, material = material })
			return
		end

		-- Deux pans + un linteau au-dessus de la porte.
		local sidePanel = (sideLength - doorWidth) / 2
		if sidePanel > 0.2 then
			for _, direction in ipairs({ 1, -1 }) do
				local offset = direction * (doorWidth / 2 + sidePanel / 2)
				local panelCenter = isX
					and Vector3.new(wallCenter.X, centerY, position.Z + offset)
					or Vector3.new(position.X + offset, centerY, wallCenter.Z)
				local panelSize = isX
					and Vector3.new(wallThickness, size.Y, sidePanel)
					or Vector3.new(sidePanel, size.Y, wallThickness)
				self:Block(panelCenter, panelSize, { name = "BuildingWall", color = color, material = material })
			end
		end
		local lintelHeight = size.Y - doorHeight
		if lintelHeight > 0.2 then
			local lintelCenter = isX
				and Vector3.new(wallCenter.X, position.Y + doorHeight + lintelHeight / 2, position.Z)
				or Vector3.new(position.X, position.Y + doorHeight + lintelHeight / 2, wallCenter.Z)
			local lintelSize = isX
				and Vector3.new(wallThickness, lintelHeight, doorWidth)
				or Vector3.new(doorWidth, lintelHeight, wallThickness)
			self:Block(lintelCenter, lintelSize, { name = "BuildingWall", color = color, material = material })
		end
	end

	buildSide("x", 1)
	buildSide("x", -1)
	buildSide("z", 1)
	buildSide("z", -1)

	if options.floor ~= false then
		self:Block(Vector3.new(position.X, position.Y + 0.25, position.Z), Vector3.new(size.X, 0.5, size.Z), {
			name = "BuildingFloor",
			color = options.floorColor or Color3.fromRGB(120, 105, 90),
			material = options.floorMaterial or Enum.Material.WoodPlanks,
		})
	end
	if options.roof ~= false then
		self:Block(Vector3.new(position.X, position.Y + size.Y + 0.5, position.Z), Vector3.new(size.X + 2, 1, size.Z + 2), {
			name = "Roof",
			color = options.roofColor or Color3.fromRGB(120, 70, 60),
			material = options.roofMaterial or Enum.Material.Slate,
		})
	end
end

--- Tas de caisses : couverture rapide et lisible pour le joueur.
function MapBuilder:Crates(position, count, spread, options)
	options = options or {}
	local size = options.size or 5
	for _ = 1, count do
		local offsetX = (self.rng:NextNumber() - 0.5) * spread
		local offsetZ = (self.rng:NextNumber() - 0.5) * spread
		local stack = self.rng:NextInteger(1, options.maxStack or 2)
		for level = 1, stack do
			local jitter = (self.rng:NextNumber() - 0.5) * 0.6
			self:Block(
				CFrame.new(position + Vector3.new(offsetX + jitter, size / 2 + size * (level - 1), offsetZ + jitter))
					* CFrame.Angles(0, self.rng:NextNumber() * math.pi, 0),
				Vector3.new(size, size, size),
				{
					name = "Crate",
					color = options.color or Color3.fromRGB(170, 125, 70),
					material = options.material or Enum.Material.WoodPlanks,
				}
			)
		end
	end
end

--- Barriere ajouree entre deux points.
function MapBuilder:Fence(fromPosition, toPosition, height, options)
	options = options or {}
	local delta = toPosition - fromPosition
	local length = delta.Magnitude
	if length < 0.05 then
		return
	end
	local direction = delta.Unit
	local color = options.color or Color3.fromRGB(190, 170, 140)
	local postSpacing = options.spacing or 8
	local postCount = math.max(2, math.floor(length / postSpacing) + 1)
	for index = 0, postCount - 1 do
		local position = fromPosition + direction * (length * index / (postCount - 1))
		self:Block(position + Vector3.new(0, height / 2, 0), Vector3.new(1, height, 1), {
			name = "FencePost",
			color = color,
			material = options.material or Enum.Material.WoodPlanks,
		})
	end
	-- Lisses horizontales
	local angle = math.atan2(-delta.Z, delta.X)
	for _, ratio in ipairs(options.rails or { 0.35, 0.85 }) do
		local center = fromPosition + delta * 0.5 + Vector3.new(0, height * ratio, 0)
		self:Block(CFrame.new(center) * CFrame.Angles(0, angle, 0), Vector3.new(length, height * 0.18, 0.6), {
			name = "FenceRail",
			color = color,
			material = options.material or Enum.Material.WoodPlanks,
		})
	end
end

--- Pont plat avec garde-corps.
function MapBuilder:Bridge(fromPosition, toPosition, width, options)
	options = options or {}
	local delta = toPosition - fromPosition
	local length = delta.Magnitude
	local center = fromPosition + delta * 0.5
	local angle = math.atan2(-delta.Z, delta.X)
	local baseCFrame = CFrame.new(center) * CFrame.Angles(0, angle, 0)
	self:Block(baseCFrame, Vector3.new(length, 1, width), {
		name = "BridgeDeck",
		color = options.color or Color3.fromRGB(140, 105, 70),
		material = options.material or Enum.Material.WoodPlanks,
	})
	if options.rails ~= false then
		for _, side in ipairs({ 1, -1 }) do
			self:Block(baseCFrame * CFrame.new(0, 2, side * width / 2), Vector3.new(length, 3, 0.5), {
				name = "BridgeRail",
				color = options.railColor or Color3.fromRGB(110, 80, 55),
				material = Enum.Material.WoodPlanks,
			})
		end
	end
end

--- Tour d'observation avec rampe d'acces en spirale simplifiee.
function MapBuilder:Tower(position, radius, height, options)
	options = options or {}
	local color = options.color or Color3.fromRGB(160, 155, 150)
	local levels = options.levels or 2
	for level = 1, levels do
		local y = position.Y + (height / levels) * level
		self:Block(Vector3.new(position.X, y, position.Z), Vector3.new(radius * 2, 1, radius * 2), {
			name = "TowerFloor",
			color = color,
			material = options.material or Enum.Material.Concrete,
		})
		-- Garde-corps ajoure
		for _, offset in ipairs({
			Vector3.new(radius, 0, 0), Vector3.new(-radius, 0, 0),
			Vector3.new(0, 0, radius), Vector3.new(0, 0, -radius),
		}) do
			local size = offset.X ~= 0 and Vector3.new(0.6, 3, radius * 2) or Vector3.new(radius * 2, 3, 0.6)
			self:Block(Vector3.new(position.X + offset.X, y + 2, position.Z + offset.Z), size, {
				name = "TowerRail",
				color = options.railColor or color,
				material = Enum.Material.Metal,
			})
		end
	end
	-- Piliers d'angle
	for _, offset in ipairs({
		Vector3.new(radius - 0.8, 0, radius - 0.8), Vector3.new(-radius + 0.8, 0, radius - 0.8),
		Vector3.new(radius - 0.8, 0, -radius + 0.8), Vector3.new(-radius + 0.8, 0, -radius + 0.8),
	}) do
		self:Block(Vector3.new(position.X + offset.X, position.Y + height / 2, position.Z + offset.Z), Vector3.new(1.4, height, 1.4), {
			name = "TowerPillar",
			color = options.pillarColor or Color3.fromRGB(120, 115, 110),
			material = Enum.Material.Metal,
		})
	end
end

--- Grand panneau decoratif avec du texte (habille les maps sans asset).
function MapBuilder:Sign(position, text, options)
	options = options or {}
	local board = self:Block(position, options.size or Vector3.new(16, 6, 0.6), {
		name = "Sign",
		color = options.color or Color3.fromRGB(35, 45, 60),
		material = Enum.Material.SmoothPlastic,
		rotation = options.rotation,
	})
	for _, face in ipairs({ Enum.NormalId.Front, Enum.NormalId.Back }) do
		local gui = Instance.new("SurfaceGui")
		gui.Face = face
		gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		gui.PixelsPerStud = 30
		gui.Parent = board
		local label = Instance.new("TextLabel")
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundTransparency = 1
		label.Text = text
		label.TextColor3 = options.textColor or Color3.fromRGB(120, 220, 255)
		label.Font = Enum.Font.GothamBold
		label.TextScaled = true
		label.Parent = gui
	end
	return board
end

--- Arbre stylise (tronc + houppier).
function MapBuilder:Tree(position, scale, options)
	options = options or {}
	scale = scale or 1
	self:Cylinder(
		CFrame.new(position + Vector3.new(0, 5 * scale, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		Vector3.new(10 * scale, 2.2 * scale, 2.2 * scale),
		{ name = "Trunk", color = options.trunkColor or Color3.fromRGB(105, 75, 50), material = Enum.Material.Wood }
	)
	for index = 1, 3 do
		local y = 10 * scale + index * 2.2 * scale
		local diameter = (11 - index * 2.2) * scale
		self:Sphere(position + Vector3.new(0, y, 0), diameter, {
			name = "Leaves",
			color = options.leafColor or Color3.fromRGB(70, 140, 70),
			material = Enum.Material.Grass,
			canCollide = false,
		})
	end
end

--- Murs invisibles qui empechent de sortir de la map.
function MapBuilder:Bounds(width, depth, height)
	local thickness = 6
	local halfWidth = width / 2 + thickness / 2
	local halfDepth = depth / 2 + thickness / 2
	local options = {
		name = "Boundary",
		transparency = 1,
		material = Enum.Material.SmoothPlastic,
		color = Color3.fromRGB(255, 255, 255),
		castShadow = false,
	}
	self:Block(Vector3.new(0, height / 2, halfDepth), Vector3.new(width + thickness * 2, height, thickness), options)
	self:Block(Vector3.new(0, height / 2, -halfDepth), Vector3.new(width + thickness * 2, height, thickness), options)
	self:Block(Vector3.new(halfWidth, height / 2, 0), Vector3.new(thickness, height, depth + thickness * 2), options)
	self:Block(Vector3.new(-halfWidth, height / 2, 0), Vector3.new(thickness, height, depth + thickness * 2), options)
end

--- Execute `callback` deux fois : une fois par cote (1 puis -1).
--- Permet d'ecrire une moitie de map et d'obtenir une arene parfaitement symetrique.
function MapBuilder:Mirror(callback)
	callback(1)
	callback(-1)
end

return MapBuilder
