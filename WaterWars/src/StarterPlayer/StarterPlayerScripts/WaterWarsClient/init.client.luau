--[[
	Water Wars - point d'entree client
	Demarre les controleurs dans l'ordre. Chaque controleur est isole : si
	l'un d'eux echoue, les autres continuent de fonctionner et l'erreur est
	affichee clairement dans la console.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- On attend que le serveur ait publie les remotes avant de brancher quoi que ce soit.
ReplicatedStorage:WaitForChild("WaterWars")
ReplicatedStorage:WaitForChild("WaterWarsRemotes")

local ClientState = require(script:WaitForChild("ClientState"))
local EffectsController = require(script:WaitForChild("EffectsController"))
local HudController = require(script:WaitForChild("HudController"))
local ScoreboardController = require(script:WaitForChild("ScoreboardController"))
local ShopController = require(script:WaitForChild("ShopController"))
local SoundController = require(script:WaitForChild("SoundController"))
local VoteController = require(script:WaitForChild("VoteController"))
local WeaponController = require(script:WaitForChild("WeaponController"))

local CONTROLLERS = {
	{ name = "EffectsController", controller = EffectsController },
	{ name = "WeaponController", controller = WeaponController },
	{ name = "HudController", controller = HudController },
	{ name = "ScoreboardController", controller = ScoreboardController },
	{ name = "VoteController", controller = VoteController },
	{ name = "ShopController", controller = ShopController },
	{ name = "SoundController", controller = SoundController },
}

for _, entry in ipairs(CONTROLLERS) do
	local ok, err = pcall(entry.controller.Start)
	if not ok then
		warn(string.format("[WaterWars] Echec du demarrage de %s : %s", entry.name, tostring(err)))
	end
end

-- Etat initial : evite un HUD vide tant que le serveur n'a rien envoye.
ClientState.MatchChanged:Fire(ClientState.match)

print(string.format("[WaterWars] Client pret pour %s.", Players.LocalPlayer.DisplayName))
