--[[
	Water Wars - point d'entree client
	Demarre les controleurs dans l'ordre. Chaque controleur est isole : si
	l'un d'eux echoue, les autres continuent de fonctionner et l'erreur est
	affichee clairement dans la console.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

--- Attend une instance, mais previent au lieu de bloquer indefiniment en
--- silence : un client qui attend un dossier absent est impossible a
--- diagnostiquer sans ce message.
local function waitFor(parent, name, timeout)
	local found = parent:WaitForChild(name, timeout or 15)
	if found then
		return found
	end
	warn(string.format(
		"[WaterWars] '%s' n'est toujours pas apparu dans %s apres %d s."
			.. " Le serveur n'a probablement pas demarre : regardez la console du serveur.",
		name,
		parent:GetFullName(),
		timeout or 15
	))
	return parent:WaitForChild(name)
end

-- On attend que le serveur ait publie les remotes avant de brancher quoi que ce soit.
waitFor(ReplicatedStorage, "WaterWars")
waitFor(ReplicatedStorage, "WaterWarsRemotes")

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
