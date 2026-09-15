--[[
	Net
	Point d'acces unique aux RemoteEvent / RemoteFunction du jeu.

	Le serveur appelle Net.Init() une seule fois au demarrage : tous les remotes
	declares ci-dessous sont crees dans ReplicatedStorage.WaterWarsRemotes.
	Le client les recupere avec Net.Event(nom) / Net.Function(nom).

	Toute faute de frappe sur un nom de remote leve immediatement une erreur
	claire au lieu de produire un "attempt to index nil".
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local FOLDER_NAME = "WaterWarsRemotes"

local Net = {}

-- Evenements client -> serveur et serveur -> client.
Net.EVENTS = {
	-- client -> serveur
	"FireWeapon",
	"RequestReload",
	"RequestEquip",
	"RequestPurchase",
	"CastMapVote",
	"SetSprint",
	-- serveur -> client
	"ProjectileSpawned",
	"ImpactEffect",
	"MatchState",
	"ProfileUpdate",
	"Scoreboard",
	"KillFeed",
	"Notify",
	"MapVote",
	"HitMarker",
	"Damaged",
	"AmmoUpdate",
	"EffectState",
	"MapReady",
}

-- Appels client -> serveur avec valeur de retour.
Net.FUNCTIONS = {
	"GetProfile",
}

local eventSet = {}
for _, name in ipairs(Net.EVENTS) do
	eventSet[name] = true
end

local functionSet = {}
for _, name in ipairs(Net.FUNCTIONS) do
	functionSet[name] = true
end

local isServer = RunService:IsServer()
local cache = {}

local function getFolder()
	local folder = ReplicatedStorage:FindFirstChild(FOLDER_NAME)
	if folder then
		return folder
	end
	if isServer then
		local created = Instance.new("Folder")
		created.Name = FOLDER_NAME
		created.Parent = ReplicatedStorage
		return created
	end
	return ReplicatedStorage:WaitForChild(FOLDER_NAME)
end

local function resolve(name, className, set, label)
	if not set[name] then
		error(string.format("Net : %s inconnu '%s' (verifiez Shared/Net.luau)", label, tostring(name)), 3)
	end
	local cached = cache[name]
	if cached and cached.Parent then
		return cached
	end
	local folder = getFolder()
	local instance = folder:FindFirstChild(name)
	if not instance then
		if not isServer then
			instance = folder:WaitForChild(name)
		else
			local created = Instance.new(className)
			created.Name = name
			created.Parent = folder
			instance = created
		end
	end
	cache[name] = instance
	return instance
end

--- Cree tous les remotes. A appeler une seule fois, cote serveur.
function Net.Init()
	assert(isServer, "Net.Init() ne peut etre appele que depuis le serveur")
	local folder = getFolder()
	for _, name in ipairs(Net.EVENTS) do
		if not folder:FindFirstChild(name) then
			local remote = Instance.new("RemoteEvent")
			remote.Name = name
			remote.Parent = folder
		end
	end
	for _, name in ipairs(Net.FUNCTIONS) do
		if not folder:FindFirstChild(name) then
			local remote = Instance.new("RemoteFunction")
			remote.Name = name
			remote.Parent = folder
		end
	end
	return folder
end

--- Renvoie le RemoteEvent portant ce nom.
function Net.Event(name): RemoteEvent
	return resolve(name, "RemoteEvent", eventSet, "evenement") :: RemoteEvent
end

--- Renvoie la RemoteFunction portant ce nom.
function Net.Function(name): RemoteFunction
	return resolve(name, "RemoteFunction", functionSet, "fonction") :: RemoteFunction
end

return Net
