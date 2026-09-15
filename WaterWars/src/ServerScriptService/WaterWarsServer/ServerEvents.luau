--[[
	ServerEvents
	Bus d'evenements interne au serveur. Il evite les dependances circulaires
	entre les services : personne n'a besoin de connaitre MatchService pour lui
	signaler une elimination.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("WaterWars"):WaitForChild("Shared")
local Signal = require(Shared:WaitForChild("Signal"))

local ServerEvents = {}

-- (victime, tueur | nil, arme | nil)
ServerEvents.PlayerKilled = Signal.new("PlayerKilled")
-- (victime, attaquant | nil, degats, estTeteTouchee)
ServerEvents.PlayerDamaged = Signal.new("PlayerDamaged")
-- (joueur, personnage)
ServerEvents.CharacterSpawned = Signal.new("CharacterSpawned")
-- (map, mode)
ServerEvents.RoundStarted = Signal.new("RoundStarted")
-- (resultat)
ServerEvents.RoundEnded = Signal.new("RoundEnded")
-- (joueur, points)
ServerEvents.ScoreChanged = Signal.new("ScoreChanged")

return ServerEvents
