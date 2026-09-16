--[[
	Water Wars - point d'entree serveur

	Ce script est volontairement tolerant sur l'installation : que le contenu
	ait ete ouvert comme une place complete ou insere n'importe ou comme un
	modele, il retrouve ses morceaux et les remet a leur place tout seul.

	Regle de conduite : on n'attend jamais indefiniment en silence. Si quelque
	chose manque, on le dit clairement dans la fenetre Output.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local ServerStorage = game:GetService("ServerStorage")
local StarterGui = game:GetService("StarterGui")
local StarterPack = game:GetService("StarterPack")
local StarterPlayer = game:GetService("StarterPlayer")

local SHARED_NAME = "WaterWars"
local CLIENT_NAME = "WaterWarsClient"

--- Endroits ou le contenu peut avoir ete depose par erreur.
local function searchRoots()
	return { workspace, ServerScriptService, ServerStorage, StarterPlayer, StarterGui, StarterPack, ReplicatedStorage }
end

local function findDescendant(root, predicate)
	for _, descendant in ipairs(root:GetDescendants()) do
		if predicate(descendant) then
			return descendant
		end
	end
	return nil
end

--- Retrouve le dossier partage et le replace dans ReplicatedStorage.
local function ensureSharedFolder()
	local existing = ReplicatedStorage:FindFirstChild(SHARED_NAME)
	if existing and existing:FindFirstChild("Config") then
		return existing
	end

	for _, root in ipairs(searchRoots()) do
		local found = findDescendant(root, function(instance)
			return instance.Name == SHARED_NAME
				and instance:IsA("Folder")
				and instance:FindFirstChild("Config") ~= nil
				and instance:FindFirstChild("Shared") ~= nil
		end)
		if found then
			found.Parent = ReplicatedStorage
			warn(string.format(
				"[WaterWars] Le dossier partage etait dans %s : il a ete deplace vers ReplicatedStorage.",
				root.Name
			))
			return found
		end
	end
	return nil
end

--- Replace le script client dans StarterPlayerScripts (sans quoi il ne
--- s'execute jamais : un LocalScript ne tourne que dans certains conteneurs).
local function ensureClientScript()
	local starterScripts = StarterPlayer:FindFirstChildOfClass("StarterPlayerScripts")
	if not starterScripts then
		warn("[WaterWars] StarterPlayerScripts est introuvable : l'interface ne pourra pas demarrer.")
		return
	end
	if starterScripts:FindFirstChild(CLIENT_NAME) then
		return
	end

	local found = nil
	for _, root in ipairs(searchRoots()) do
		found = findDescendant(root, function(instance)
			return instance.Name == CLIENT_NAME and instance:IsA("LocalScript")
		end)
		if found then
			break
		end
	end
	if not found then
		warn(string.format(
			"[WaterWars] Le script client '%s' est introuvable : le jeu tournera sans interface.",
			CLIENT_NAME
		))
		return
	end

	found.Parent = starterScripts
	warn("[WaterWars] Le script client a ete deplace vers StarterPlayer.StarterPlayerScripts.")

	-- Les joueurs deja connectes ont recu leur copie de StarterPlayerScripts
	-- avant ce deplacement : on leur injecte le script a la main.
	for _, player in ipairs(Players:GetPlayers()) do
		pcall(function()
			local playerScripts = player:FindFirstChild("PlayerScripts")
			if playerScripts and not playerScripts:FindFirstChild(CLIENT_NAME) then
				local copy = found:Clone()
				copy.Parent = playerScripts
			end
		end)
	end
end

--- Si le script a ete insere dans Workspace avec le modele, il se range.
local function tidySelf()
	if script.Parent == ServerScriptService then
		return
	end
	local installer = script.Parent
	pcall(function()
		script.Parent = ServerScriptService
	end)
	-- Le dossier d'installation vide n'a plus de raison d'exister.
	if installer and installer ~= ServerScriptService and #installer:GetChildren() == 0 then
		pcall(function()
			installer:Destroy()
		end)
	end
end

-- ========================== installation ==================================

if not ensureSharedFolder() then
	error(
		"[WaterWars] Installation incomplete : le dossier 'WaterWars' (avec Config et Shared) est introuvable.\n"
			.. "  - Si vous avez ouvert WaterWars.rbxlx : utilisez Fichier > Ouvrir, pas 'Insert from File'.\n"
			.. "  - Si vous avez insere WaterWars.rbxmx : verifiez que le dossier insere est complet.",
		0
	)
end

ensureClientScript()
tidySelf()

-- ========================== demarrage des services ========================

-- A ce stade le dossier est garanti present dans ReplicatedStorage : on y
-- accede par son chemin litteral, ce qui permet aussi aux outils d'analyse
-- de resoudre les modules.
local WaterWars = ReplicatedStorage:WaitForChild("WaterWars")
local Config = WaterWars:WaitForChild("Config")
local Shared = WaterWars:WaitForChild("Shared")

local GameConfig = require(Config:WaitForChild("GameConfig"))
local Maps = require(Config:WaitForChild("Maps"))
local Weapons = require(Config:WaitForChild("Weapons"))
local Net = require(Shared:WaitForChild("Net"))

-- Les remotes doivent exister avant que le moindre client ne les attende.
Net.Init()

local CombatService = require(script:WaitForChild("CombatService"))
local DataService = require(script:WaitForChild("DataService"))
local MatchService = require(script:WaitForChild("MatchService"))
local PickupService = require(script:WaitForChild("PickupService"))
local PlayerService = require(script:WaitForChild("PlayerService"))
local TeamService = require(script:WaitForChild("TeamService"))
local WeaponService = require(script:WaitForChild("WeaponService"))

Players.RespawnTime = GameConfig.RespawnTime
workspace.FallenPartsDestroyHeight = -500

local START_ORDER = {
	{ name = "DataService", service = DataService },
	{ name = "TeamService", service = TeamService },
	{ name = "WeaponService", service = WeaponService },
	{ name = "PlayerService", service = PlayerService },
	{ name = "CombatService", service = CombatService },
	{ name = "PickupService", service = PickupService },
	{ name = "MatchService", service = MatchService },
}

local failures = 0
for _, entry in ipairs(START_ORDER) do
	local ok, err = pcall(entry.service.Start)
	if not ok then
		failures = failures + 1
		warn(string.format("[WaterWars] Echec du demarrage de %s : %s", entry.name, tostring(err)))
	end
end

if failures > 0 then
	warn(string.format("[WaterWars] %d service(s) n'ont pas demarre : le jeu sera degrade.", failures))
end

print(string.format(
	"[WaterWars] Serveur pret - %d armes, %d maps, %d joueurs max.",
	Weapons.Count,
	Maps.Count,
	GameConfig.MaxPlayers
))
