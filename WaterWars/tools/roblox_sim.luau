--[[
	roblox_sim.luau
	Simulateur d'API Roblox suffisamment complet pour DEMARRER le serveur du
	jeu hors de Studio : instances, hierarchie, evenements, attributs,
	RemoteEvents, Humanoid, et un ordonnanceur cooperatif (task.wait / spawn /
	delay) avec un temps virtuel.

	Utilise par tools/boot_test.py. Ne fait pas partie du jeu.
]]

-- ============================== types de base ==============================
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
	__tostring = function(a) return string.format("(%.1f, %.1f, %.1f)", a.X, a.Y, a.Z) end,
	__index = function(self, key)
		if key == "Magnitude" then
			return math.sqrt(self.X ^ 2 + self.Y ^ 2 + self.Z ^ 2)
		elseif key == "Unit" then
			local m = math.sqrt(self.X ^ 2 + self.Y ^ 2 + self.Z ^ 2)
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
Vector3 = { new = vec3, zero = vec3(0, 0, 0), one = vec3(1, 1, 1), yAxis = vec3(0, 1, 0) }
Vector2 = { new = function(x, y) return { X = x or 0, Y = y or 0, __isVector2 = true } end }

Color3 = {
	new = function(r, g, b) return { R = r or 0, G = g or 0, B = b or 0, __isColor3 = true } end,
	fromRGB = function(r, g, b)
		return { R = (r or 0) / 255, G = (g or 0) / 255, B = (b or 0) / 255, __isColor3 = true }
	end,
}
BrickColor = { new = function(name) return { Name = name, __isBrickColor = true } end }
UDim = { new = function(s, o) return { Scale = s or 0, Offset = o or 0 } end }
UDim2 = {
	new = function(sx, ox, sy, oy) return { X = UDim.new(sx, ox), Y = UDim.new(sy, oy), __isUDim2 = true } end,
	fromScale = function(sx, sy) return UDim2.new(sx, 0, sy, 0) end,
	fromOffset = function(ox, oy) return UDim2.new(0, ox, 0, oy) end,
}

local cframeMeta
local function cframe(x, y, z)
	local c = { X = x or 0, Y = y or 0, Z = z or 0, __isCFrame = true }
	c.Position = vec3(c.X, c.Y, c.Z)
	c.LookVector = vec3(0, 0, -1)
	return setmetatable(c, cframeMeta)
end
cframeMeta = {
	__mul = function(a, b)
		if type(b) == "table" and b.__isVector3 then return cframe(a.X + b.X, a.Y + b.Y, a.Z + b.Z) end
		if type(b) == "table" and b.__isCFrame then return cframe(a.X + b.X, a.Y + b.Y, a.Z + b.Z) end
		return a
	end,
	__add = function(a, b) return cframe(a.X + b.X, a.Y + b.Y, a.Z + b.Z) end,
	__index = function() return nil end,
}
CFrame = {
	new = function(a, b, c)
		if type(a) == "table" and (a.__isVector3 or a.__isCFrame) then return cframe(a.X, a.Y, a.Z) end
		return cframe(a, b, c)
	end,
	Angles = function() return cframe(0, 0, 0) end,
	lookAt = function(from) return cframe(from.X, from.Y, from.Z) end,
	identity = cframe(0, 0, 0),
}
NumberRange = { new = function(a, b) return { Min = a, Max = b or a } end }
NumberSequenceKeypoint = { new = function(t, v) return { Time = t, Value = v } end }
NumberSequence = { new = function(a) return { Keypoints = a } end }
ColorSequence = { new = function(a) return { Keypoints = a } end }

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
		local state = (seed or 0) % 2147483647
		local gen = {}
		local function raw()
			state = (state * 1103515245 + 12345) % 2147483648
			return state / 2147483648
		end
		function gen:NextNumber(a, b)
			local v = raw()
			if a and b then return a + v * (b - a) end
			return v
		end
		function gen:NextInteger(a, b) return math.floor(a + raw() * (b - a + 1 - 1e-9)) end
		return gen
	end,
}

-- ============================== ordonnanceur ==============================
SIM = { time = 0, errors = {}, warnings = {}, prints = {}, sleeping = {}, ready = {} }

local function recordError(message)
	table.insert(SIM.errors, tostring(message))
end

local function resumeThread(co, ...)
	local ok, err = coroutine.resume(co, ...)
	if not ok then
		recordError(err)
	end
end

task = {}

function task.spawn(fn, ...)
	local co = type(fn) == "thread" and fn or coroutine.create(fn)
	resumeThread(co, ...)
	return co
end

function task.defer(fn, ...)
	table.insert(SIM.ready, { fn = fn, args = table.pack(...) })
	return nil
end

function task.delay(seconds, fn, ...)
	table.insert(SIM.sleeping, {
		co = coroutine.create(fn),
		at = SIM.time + (seconds or 0),
		args = table.pack(...),
	})
	return nil
end

function task.wait(seconds)
	local co = coroutine.running()
	table.insert(SIM.sleeping, { co = co, at = SIM.time + (seconds or 0) })
	return coroutine.yield()
end

function task.cancel() end
wait = task.wait
delay = function(s, f) task.delay(s, f) end
spawn = task.spawn

-- Le jeu mesure le temps avec os.clock : il doit suivre le temps virtuel.
local realOs = os
os = setmetatable({
	clock = function() return SIM.time end,
	time = function() return 1700000000 + math.floor(SIM.time) end,
	date = realOs.date,
}, { __index = realOs })

local function stepScheduler()
	local ready = SIM.ready
	SIM.ready = {}
	for _, entry in ipairs(ready) do
		resumeThread(coroutine.create(entry.fn), table.unpack(entry.args, 1, entry.args.n))
	end

	local remaining = {}
	local due = {}
	for _, entry in ipairs(SIM.sleeping) do
		if entry.at <= SIM.time then
			table.insert(due, entry)
		else
			table.insert(remaining, entry)
		end
	end
	SIM.sleeping = remaining
	for _, entry in ipairs(due) do
		if entry.args then
			resumeThread(entry.co, table.unpack(entry.args, 1, entry.args.n))
		else
			resumeThread(entry.co)
		end
	end
end

-- ================================ signaux =================================
local Signal = {}
Signal.__index = Signal
local function newSignal(name)
	return setmetatable({ _handlers = {}, _name = name }, Signal)
end
function Signal:Connect(fn)
	table.insert(self._handlers, fn)
	local handlers = self._handlers
	return {
		Disconnect = function()
			local index = table.find(handlers, fn)
			if index then table.remove(handlers, index) end
		end,
		Connected = true,
	}
end
Signal.Once = Signal.Connect
function Signal:Wait() return task.wait(0) end
function Signal:Fire(...)
	for _, fn in ipairs(table.clone(self._handlers)) do
		local ok, err = pcall(fn, ...)
		if not ok then
			recordError(string.format("[%s] %s", tostring(self._name), tostring(err)))
		end
	end
end

local EVENT_NAMES = {
	Heartbeat = true, RenderStepped = true, Stepped = true, PostSimulation = true,
	PlayerAdded = true, PlayerRemoving = true, CharacterAdded = true, CharacterRemoving = true,
	Died = true, HealthChanged = true, Touched = true, TouchEnded = true,
	ChildAdded = true, ChildRemoved = true, DescendantAdded = true, AncestryChanged = true,
	Changed = true, Destroying = true, Equipped = true, Unequipped = true, Activated = true,
	OnServerEvent = true, OnClientEvent = true, StateChanged = true,
}

-- =============================== instances ================================
local HIERARCHY = {
	Part = { "Part", "BasePart", "PVInstance" },
	WedgePart = { "WedgePart", "BasePart", "PVInstance" },
	Model = { "Model", "PVInstance" },
	Tool = { "Tool", "BackpackItem", "Model", "PVInstance" },
	Folder = { "Folder" },
	Humanoid = { "Humanoid" },
	Team = { "Team" },
	RemoteEvent = { "RemoteEvent" },
	RemoteFunction = { "RemoteFunction" },
	Script = { "Script", "BaseScript", "LuaSourceContainer" },
	ModuleScript = { "ModuleScript", "LuaSourceContainer" },
	Backpack = { "Backpack" },
	Player = { "Player" },
}

local instanceMeta = {}
local allInstances = {}

local function fireAncestryEvents(instance, oldParent, newParent)
	if oldParent then
		local index = table.find(oldParent.__children, instance)
		if index then table.remove(oldParent.__children, index) end
		local signal = rawget(oldParent, "__events") and oldParent.__events.ChildRemoved
		if signal then signal:Fire(instance) end
	end
	if newParent then
		table.insert(newParent.__children, instance)
		local signal = rawget(newParent, "__events") and newParent.__events.ChildAdded
		if signal then signal:Fire(instance) end
	end
end

local METHODS = {}

function METHODS:IsA(queried)
	local chain = HIERARCHY[self.ClassName] or { self.ClassName }
	if table.find(chain, queried) then return true end
	return queried == "Instance"
end

function METHODS:Destroy()
	self.Parent = nil
	self.__destroyed = true
	for _, child in ipairs(table.clone(self.__children)) do
		child:Destroy()
	end
end

function METHODS:ClearAllChildren()
	for _, child in ipairs(table.clone(self.__children)) do
		child:Destroy()
	end
end

function METHODS:GetChildren() return table.clone(self.__children) end
function METHODS:GetDescendants()
	local out = {}
	for _, child in ipairs(self.__children) do
		table.insert(out, child)
		for _, sub in ipairs(child:GetDescendants()) do table.insert(out, sub) end
	end
	return out
end

function METHODS:FindFirstChild(name)
	for _, child in ipairs(self.__children) do
		if child.Name == name then return child end
	end
	return nil
end

function METHODS:FindFirstChildOfClass(class)
	for _, child in ipairs(self.__children) do
		if child.ClassName == class then return child end
	end
	return nil
end
METHODS.FindFirstChildWhichIsA = METHODS.FindFirstChildOfClass

function METHODS:WaitForChild(name)
	local found = self:FindFirstChild(name)
	if found then return found end
	-- En simulation l'arbre est complet des le depart : une attente infinie
	-- est donc forcement une erreur de chemin, on la signale tout de suite.
	error(string.format("WaitForChild('%s') introuvable sous %s", tostring(name), self:GetFullName()), 2)
end

function METHODS:GetFullName()
	local parts = { self.Name }
	local current = self.Parent
	while current do
		table.insert(parts, 1, current.Name)
		current = current.Parent
	end
	return table.concat(parts, ".")
end

function METHODS:SetAttribute(name, value) self.__attributes[name] = value end
function METHODS:GetAttribute(name) return self.__attributes[name] end
function METHODS:GetAttributes() return table.clone(self.__attributes) end
function METHODS:GetAttributeChangedSignal() return newSignal("AttributeChanged") end
function METHODS:GetPropertyChangedSignal() return newSignal("PropertyChanged") end

function METHODS:PivotTo(cf) self.__pivot = cf end
function METHODS:GetPivot() return self.__pivot or cframe(0, 0, 0) end
function METHODS:Clone()
	local copy = newInstance(self.ClassName)
	copy.Name = self.Name
	return copy
end
function METHODS:EquipTool(tool) tool.Parent = self.Parent end
function METHODS:MoveTo() end
function METHODS:TakeDamage(amount) self.Health = math.max(0, self.Health - amount) end
function METHODS:Emit() end
function METHODS:Play() end
function METHODS:FireClient() SIM.remoteCalls = (SIM.remoteCalls or 0) + 1 end
function METHODS:FireAllClients() SIM.remoteCalls = (SIM.remoteCalls or 0) + 1 end
function METHODS:AddItem() end

-- Les proprietes vivent dans __props et jamais directement sur l'instance :
-- sinon __newindex ne se declencherait qu'a la premiere ecriture, et
-- Destroy() comme Humanoid.Died passeraient silencieusement a la trappe.
instanceMeta.__index = function(self, key)
	local props = rawget(self, "__props")
	local value = props[key]
	if value ~= nil then return value end

	local method = METHODS[key]
	if method then return method end

	if EVENT_NAMES[key] then
		local events = rawget(self, "__events")
		if not events[key] then events[key] = newSignal(props.Name .. "." .. key) end
		return events[key]
	end

	-- Dans Roblox, instance.NomEnfant renvoie l'enfant portant ce nom.
	for _, child in ipairs(rawget(self, "__children")) do
		if rawget(child, "__props").Name == key then return child end
	end
	return nil
end

instanceMeta.__newindex = function(self, key, value)
	if string.sub(key, 1, 2) == "__" then
		rawset(self, key, value)
		return
	end
	local props = rawget(self, "__props")

	if key == "Parent" then
		local old = props.Parent
		if old == value then return end
		props.Parent = value
		fireAncestryEvents(self, old, value)
		return
	end

	if key == "Health" and props.ClassName == "Humanoid" then
		local previous = props.Health or 0
		props.Health = value
		if value <= 0 and previous > 0 then
			local events = rawget(self, "__events")
			if events.Died then events.Died:Fire() end
		end
		return
	end

	props[key] = value
end

instanceMeta.__tostring = function(self) return rawget(self, "__props").Name end

local DEFAULTS = {
	Part = { Size = vec3(4, 1, 2), Transparency = 0, Anchored = false, CanCollide = true },
	Humanoid = { Health = 100, MaxHealth = 100, WalkSpeed = 16, JumpPower = 50 },
}

local function newInstance(className, parent)
	local props = { ClassName = className, Name = className }
	for key, value in pairs(DEFAULTS[className] or {}) do
		props[key] = value
	end
	if className == "Part" or className == "WedgePart" then
		props.CFrame = cframe(0, 0, 0)
		props.Position = vec3(0, 0, 0)
		props.AssemblyLinearVelocity = vec3(0, 0, 0)
	end
	local instance = setmetatable({
		__props = props,
		__children = {},
		__attributes = {},
		__events = {},
	}, instanceMeta)
	table.insert(allInstances, instance)
	if parent then instance.Parent = parent end
	return instance
end

Instance = { new = newInstance }

typeof = function(value)
	if type(value) == "table" then
		if value.__isVector3 then return "Vector3" end
		if value.__isCFrame then return "CFrame" end
		if value.__isColor3 then return "Color3" end
		if value.__isVector2 then return "Vector2" end
		if value.__isUDim2 then return "UDim2" end
		if rawget(value, "ClassName") then return "Instance" end
	end
	return type(value)
end

-- ================================ services ================================
local services = {}
local function makeService(className, name)
	local service = newInstance(className)
	service.Name = name or className
	services[name or className] = service
	return service
end

workspace = makeService("Workspace", "Workspace")
workspace.FallenPartsDestroyHeight = -500
function workspace:Raycast() return nil end
function workspace:GetPartBoundsInRadius() return {} end

local ReplicatedStorageSvc = makeService("ReplicatedStorage", "ReplicatedStorage")
local ServerScriptServiceSvc = makeService("ServerScriptService", "ServerScriptService")
local LightingSvc = makeService("Lighting", "Lighting")
local TeamsSvc = makeService("Teams", "Teams")
local PlayersSvc = makeService("Players", "Players")
PlayersSvc.CharacterAutoLoads = true
PlayersSvc.RespawnTime = 5

local RunServiceSvc = makeService("RunService", "RunService")
function RunServiceSvc:IsServer() return true end
function RunServiceSvc:IsClient() return false end
function RunServiceSvc:IsStudio() return true end

local DataStoreServiceSvc = makeService("DataStoreService", "DataStoreService")
function DataStoreServiceSvc:GetDataStore()
	-- Reproduit Studio sans "API Services" : toute lecture echoue.
	return {
		GetAsync = function() error("DataStore indisponible (simulation)", 0) end,
		SetAsync = function() error("DataStore indisponible (simulation)", 0) end,
	}
end

local StarterPlayerSvc = makeService("StarterPlayer", "StarterPlayer")
local starterPlayerScripts = newInstance("StarterPlayerScripts")
starterPlayerScripts.Name = "StarterPlayerScripts"
starterPlayerScripts.Parent = StarterPlayerSvc
makeService("StarterGui", "StarterGui")
makeService("StarterPack", "StarterPack")
makeService("ServerStorage", "ServerStorage")

makeService("Debris", "Debris")
makeService("TweenService", "TweenService")
makeService("SoundService", "SoundService")

local playerList = {}
function PlayersSvc:GetPlayers() return table.clone(playerList) end
function PlayersSvc:GetPlayerFromCharacter(character)
	for _, player in ipairs(playerList) do
		if player.Character == character then return player end
	end
	return nil
end
function PlayersSvc:GetPlayerByUserId(id)
	for _, player in ipairs(playerList) do
		if player.UserId == id then return player end
	end
	return nil
end

function SIM.addPlayer(name, userId)
	local player = newInstance("Player")
	player.Name = name
	player.DisplayName = name
	player.UserId = userId
	player.Neutral = true
	player.Team = nil
	player.Character = nil
	local backpack = newInstance("Backpack")
	backpack.Name = "Backpack"
	backpack.Parent = player

	function player:LoadCharacter()
		if self.Character then self.Character:Destroy() end
		local character = newInstance("Model")
		character.Name = self.Name
		local root = newInstance("Part")
		root.Name = "HumanoidRootPart"
		root.AssemblyLinearVelocity = vec3(0, 0, 0)
		root.Parent = character
		local head = newInstance("Part")
		head.Name = "Head"
		head.Parent = character
		local humanoid = newInstance("Humanoid")
		humanoid.Name = "Humanoid"
		humanoid.Parent = character
		character.Parent = workspace
		self.Character = character
		local events = rawget(self, "__events")
		if events.CharacterAdded then events.CharacterAdded:Fire(character) end
		return character
	end

	player.Parent = PlayersSvc
	table.insert(playerList, player)
	local events = rawget(PlayersSvc, "__events")
	if events.PlayerAdded then events.PlayerAdded:Fire(player) end
	return player
end

game = {
	GetService = function(_, name)
		local service = services[name]
		if not service then
			service = makeService(name, name)
		end
		return service
	end,
	BindToClose = function() end,
	Workspace = workspace,
	Players = PlayersSvc,
}
setmetatable(game, { __index = function(_, key) return services[key] end })

-- =========================== require de modules ===========================
local moduleCache = {}
function require(target)
	if type(target) ~= "table" or not rawget(target, "__loader") then
		error("require() sur un objet qui n'est pas un ModuleScript : " .. tostring(target), 2)
	end
	if moduleCache[target] == nil then
		moduleCache[target] = { value = target.__loader(target) }
	end
	return moduleCache[target].value
end

local realWarn = warn
warn = function(...)
	local pieces = {}
	for index = 1, select("#", ...) do
		table.insert(pieces, tostring(select(index, ...)))
	end
	table.insert(SIM.warnings, table.concat(pieces, " "))
end

local realPrint = print
print = function(...)
	local pieces = {}
	for index = 1, select("#", ...) do
		table.insert(pieces, tostring(select(index, ...)))
	end
	table.insert(SIM.prints, table.concat(pieces, " "))
end

SIM.stepScheduler = stepScheduler
SIM.realPrint = realPrint
SIM.services = services
SIM.playerList = playerList
