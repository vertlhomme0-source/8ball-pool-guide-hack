--[[
	Stub minimal de l'API Roblox, utilise uniquement par tools/check_data.py.

	Il permet d'executer hors de Studio :
	  - les modules de donnees (GameConfig, Weapons, Maps) ;
	  - le vrai MapBuilder et les vraies fonctions build() des 6 maps.
	Ce fichier ne fait pas partie du jeu.
]]

local vec3Meta
local function vec3(x, y, z)
	return setmetatable({ X = x or 0, Y = y or 0, Z = z or 0, __isVector3 = true }, vec3Meta)
end

vec3Meta = {
	__add = function(a, b) return vec3(a.X + b.X, a.Y + b.Y, a.Z + b.Z) end,
	__sub = function(a, b) return vec3(a.X - b.X, a.Y - b.Y, a.Z - b.Z) end,
	__unm = function(a) return vec3(-a.X, -a.Y, -a.Z) end,
	__mul = function(a, b)
		if type(a) == "number" then return vec3(a * b.X, a * b.Y, a * b.Z) end
		if type(b) == "number" then return vec3(a.X * b, a.Y * b, a.Z * b) end
		return vec3(a.X * b.X, a.Y * b.Y, a.Z * b.Z)
	end,
	__div = function(a, b) return vec3(a.X / b, a.Y / b, a.Z / b) end,
	__eq = function(a, b) return a.X == b.X and a.Y == b.Y and a.Z == b.Z end,
	__tostring = function(a) return string.format("(%.2f, %.2f, %.2f)", a.X, a.Y, a.Z) end,
	__index = function(self, key)
		if key == "Magnitude" then
			return math.sqrt(self.X * self.X + self.Y * self.Y + self.Z * self.Z)
		elseif key == "Unit" then
			local m = math.sqrt(self.X * self.X + self.Y * self.Y + self.Z * self.Z)
			if m == 0 then return vec3(0, 0, 0) end
			return vec3(self.X / m, self.Y / m, self.Z / m)
		elseif key == "Dot" then
			return function(a, b) return a.X * b.X + a.Y * b.Y + a.Z * b.Z end
		elseif key == "Cross" then
			return function(a, b)
				return vec3(a.Y * b.Z - a.Z * b.Y, a.Z * b.X - a.X * b.Z, a.X * b.Y - a.Y * b.X)
			end
		elseif key == "Lerp" then
			return function(a, b, t) return a + (b - a) * t end
		end
		return nil
	end,
}

Vector3 = {
	new = vec3,
	zero = vec3(0, 0, 0),
	one = vec3(1, 1, 1),
	xAxis = vec3(1, 0, 0),
	yAxis = vec3(0, 1, 0),
	zAxis = vec3(0, 0, 1),
}

Vector2 = { new = function(x, y) return { X = x or 0, Y = y or 0, __isVector2 = true } end }

Color3 = {
	new = function(r, g, b) return { R = r or 0, G = g or 0, B = b or 0, __isColor3 = true } end,
	fromRGB = function(r, g, b)
		return { R = (r or 0) / 255, G = (g or 0) / 255, B = (b or 0) / 255, __isColor3 = true }
	end,
	fromHSV = function(h, s, v) return { R = h, G = s, B = v, __isColor3 = true } end,
}

BrickColor = { new = function(name) return { Name = name, __isBrickColor = true } end }

UDim = { new = function(s, o) return { Scale = s or 0, Offset = o or 0, __isUDim = true } end }
UDim2 = {
	new = function(sx, ox, sy, oy)
		return { X = UDim.new(sx, ox), Y = UDim.new(sy, oy), __isUDim2 = true }
	end,
	fromScale = function(sx, sy) return UDim2.new(sx, 0, sy, 0) end,
	fromOffset = function(ox, oy) return UDim2.new(0, ox, 0, oy) end,
}

-- CFrame : on ne modelise que la translation (suffisant pour valider les maps ;
-- les rotations sont acceptees mais ignorees).
local cframeMeta
local function cframe(x, y, z)
	local c = { X = x or 0, Y = y or 0, Z = z or 0, __isCFrame = true }
	c.Position = vec3(c.X, c.Y, c.Z)
	c.LookVector = vec3(0, 0, -1)
	c.RightVector = vec3(1, 0, 0)
	c.UpVector = vec3(0, 1, 0)
	return setmetatable(c, cframeMeta)
end
cframeMeta = {
	__mul = function(a, b)
		if type(b) == "table" and b.__isVector3 then return vec3(a.X + b.X, a.Y + b.Y, a.Z + b.Z) end
		if type(b) == "table" and b.__isCFrame then return cframe(a.X + b.X, a.Y + b.Y, a.Z + b.Z) end
		return a
	end,
	__index = function(self, key)
		if key == "Inverse" then return function(s) return cframe(-s.X, -s.Y, -s.Z) end end
		if key == "Lerp" then return function(s, o, t) return cframe(s.X, s.Y, s.Z) end end
		if key == "ToWorldSpace" then return function(s, o) return s * o end end
		return nil
	end,
}

CFrame = {
	new = function(a, b, c)
		if type(a) == "table" and a.__isVector3 then return cframe(a.X, a.Y, a.Z) end
		if type(a) == "table" and a.__isCFrame then return cframe(a.X, a.Y, a.Z) end
		return cframe(a, b, c)
	end,
	Angles = function() return cframe(0, 0, 0) end,
	fromEulerAnglesXYZ = function() return cframe(0, 0, 0) end,
	fromAxisAngle = function() return cframe(0, 0, 0) end,
	lookAt = function(from) return cframe(from.X, from.Y, from.Z) end,
	identity = cframe(0, 0, 0),
}

NumberRange = { new = function(a, b) return { Min = a, Max = b or a, __isNumberRange = true } end }
NumberSequenceKeypoint = { new = function(t, v) return { Time = t, Value = v } end }
NumberSequence = { new = function(a) return { Keypoints = a, __isNumberSequence = true } end }
ColorSequenceKeypoint = { new = function(t, v) return { Time = t, Value = v } end }
ColorSequence = { new = function(a) return { Keypoints = a, __isColorSequence = true } end }
Rect = { new = function() return {} end }

-- Enum : n'importe quel Enum.Categorie.Valeur renvoie un jeton unique et stable.
local enumCache = {}
Enum = setmetatable({}, {
	__index = function(_, category)
		if not enumCache[category] then
			enumCache[category] = setmetatable({}, {
				__index = function(self, value)
					local item = { Name = value, EnumType = category, Value = 0 }
					rawset(self, value, item)
					return item
				end,
			})
		end
		return enumCache[category]
	end,
})

Random = {
	new = function(seed)
		local state = seed or 0
		local generator = {}
		local function nextRaw()
			state = (state * 1103515245 + 12345) % 2147483648
			return state / 2147483648
		end
		function generator:NextNumber(minimum, maximum)
			local value = nextRaw()
			if minimum and maximum then return minimum + value * (maximum - minimum) end
			return value
		end
		function generator:NextInteger(minimum, maximum)
			return math.floor(minimum + nextRaw() * (maximum - minimum + 1 - 1e-9))
		end
		function generator:NextUnitVector()
			return vec3(0, 1, 0)
		end
		return generator
	end,
}

-- --------------------------------------------------------------------------
-- Instances
-- --------------------------------------------------------------------------
STUB_INSTANCES = {}

local HIERARCHY = {
	Part = { "Part", "BasePart", "PVInstance", "Instance" },
	WedgePart = { "WedgePart", "BasePart", "PVInstance", "Instance" },
	MeshPart = { "MeshPart", "BasePart", "PVInstance", "Instance" },
	Model = { "Model", "PVInstance", "Instance" },
	Folder = { "Folder", "Instance" },
	SurfaceGui = { "SurfaceGui", "LayerCollector", "GuiBase2d", "Instance" },
	BillboardGui = { "BillboardGui", "LayerCollector", "GuiBase2d", "Instance" },
	TextLabel = { "TextLabel", "GuiObject", "GuiBase2d", "Instance" },
	Frame = { "Frame", "GuiObject", "GuiBase2d", "Instance" },
	SpecialMesh = { "SpecialMesh", "DataModelMesh", "Instance" },
	PointLight = { "PointLight", "Light", "Instance" },
	Attachment = { "Attachment", "Instance" },
	ParticleEmitter = { "ParticleEmitter", "Instance" },
	Beam = { "Beam", "Instance" },
	Sound = { "Sound", "Instance" },
	Humanoid = { "Humanoid", "Instance" },
}

local function newInstance(className)
	local instance
	instance = {
		ClassName = className,
		Name = className,
		Parent = nil,
		__children = {},
		IsA = function(self, queried)
			local chain = HIERARCHY[self.ClassName] or { self.ClassName, "Instance" }
			return table.find(chain, queried) ~= nil
		end,
		Destroy = function(self) self.Parent = nil end,
		Clone = function(self) return newInstance(self.ClassName) end,
		FindFirstChild = function(self, name)
			for _, child in ipairs(self.__children) do
				if child.Name == name then return child end
			end
			return nil
		end,
		FindFirstChildOfClass = function(self, class)
			for _, child in ipairs(self.__children) do
				if child.ClassName == class then return child end
			end
			return nil
		end,
		GetChildren = function(self) return self.__children end,
		WaitForChild = function(self, name) return self:FindFirstChild(name) end,
		SetAttribute = function() end,
		GetAttribute = function() return nil end,
		PivotTo = function() end,
		GetPivot = function() return cframe(0, 0, 0) end,
	}
	table.insert(STUB_INSTANCES, instance)
	return instance
end

Instance = { new = function(className) return newInstance(className) end }

-- typeof doit reconnaitre nos faux types, sinon MapBuilder confond CFrame et Vector3.
local rawTypeof = typeof
typeof = function(value)
	if type(value) == "table" then
		if value.__isVector3 then return "Vector3" end
		if value.__isCFrame then return "CFrame" end
		if value.__isColor3 then return "Color3" end
		if value.__isVector2 then return "Vector2" end
		if value.__isUDim2 then return "UDim2" end
		if value.ClassName then return "Instance" end
	end
	return rawTypeof(value)
end

task = {
	wait = function() return 0 end,
	spawn = function(fn, ...) fn(...) end,
	defer = function(fn, ...) fn(...) end,
	delay = function(_, fn, ...) return fn end,
}

workspace = newInstance("Workspace")
game = {
	GetService = function(_, name) return newInstance(name) end,
	Workspace = workspace,
}
