--[[
	Water Wars - point d'entree serveur
	Ce script demarre tous les services dans l'ordre. Rien d'autre n'est
	necessaire : la map, les armes, l'interface et les manches sont generees
	a l'execution.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

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

-- Reglages globaux du serveur.
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

for _, entry in ipairs(START_ORDER) do
	local ok, err = pcall(entry.service.Start)
	if not ok then
		warn(string.format("[WaterWars] Echec du demarrage de %s : %s", entry.name, tostring(err)))
	end
end

print(string.format(
	"[WaterWars] Serveur pret - %d armes, %d maps, %d joueurs max.",
	Weapons.Count,
	Maps.Count,
	GameConfig.MaxPlayers
))
