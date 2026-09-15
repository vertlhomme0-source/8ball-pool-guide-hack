--[[
	TeamService
	Creation des equipes et repartition equilibree des 20 joueurs.
	En mode "chacun pour soi" les equipes sont videes et tout le monde devient
	neutre, ce qui desactive automatiquement la protection alliee.
]]

local Players = game:GetService("Players")
local Teams = game:GetService("Teams")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local WaterWars = ReplicatedStorage:WaitForChild("WaterWars")
local GameConfig = require(WaterWars:WaitForChild("Config"):WaitForChild("GameConfig"))

local TeamService = {}

local teamInstances = {}
local teamEnabled = true

function TeamService.Start()
	for _, definition in ipairs(GameConfig.Teams) do
		local existing = Teams:FindFirstChild(definition.name)
		local team
		if existing and existing:IsA("Team") then
			team = existing
		else
			team = Instance.new("Team")
			team.Name = definition.name
			team.Parent = Teams
		end
		team.TeamColor = definition.brickColor
		team.AutoAssignable = false
		teamInstances[definition.id] = team
	end
end

function TeamService.GetTeam(teamId)
	return teamInstances[teamId]
end

--- Identifiant logique ("Blue" / "Red") de l'equipe d'un joueur, ou nil.
function TeamService.GetTeamId(player)
	if player.Neutral or not player.Team then
		return nil
	end
	for id, team in pairs(teamInstances) do
		if team == player.Team then
			return id
		end
	end
	return nil
end

function TeamService.CountPlayers(teamId)
	local team = teamInstances[teamId]
	if not team then
		return 0
	end
	local count = 0
	for _, player in ipairs(Players:GetPlayers()) do
		if player.Team == team then
			count = count + 1
		end
	end
	return count
end

--- Place un joueur dans l'equipe la moins remplie.
function TeamService.Assign(player)
	if not teamEnabled then
		player.Neutral = true
		player.Team = nil
		return nil
	end
	local bestId, bestCount = nil, math.huge
	for _, definition in ipairs(GameConfig.Teams) do
		local count = TeamService.CountPlayers(definition.id)
		if count < bestCount then
			bestId, bestCount = definition.id, count
		end
	end
	if bestId then
		player.Neutral = false
		player.Team = teamInstances[bestId]
	end
	return bestId
end

--- Active ou desactive le jeu en equipes (selon le mode de la manche).
function TeamService.SetTeamMode(enabled)
	teamEnabled = enabled
	if not enabled then
		for _, player in ipairs(Players:GetPlayers()) do
			player.Neutral = true
			player.Team = nil
		end
		return
	end
	-- Reequilibrage complet : on vide puis on redistribue en alternance.
	local players = Players:GetPlayers()
	table.sort(players, function(a, b)
		return a.UserId < b.UserId
	end)
	for index, player in ipairs(players) do
		local definition = GameConfig.Teams[((index - 1) % #GameConfig.Teams) + 1]
		player.Neutral = false
		player.Team = teamInstances[definition.id]
	end
end

--- true si `a` et `b` sont dans la meme equipe (jamais en mode neutre).
function TeamService.AreAllies(a, b)
	if not teamEnabled then
		return false
	end
	if a == b then
		return true
	end
	local teamA = TeamService.GetTeamId(a)
	local teamB = TeamService.GetTeamId(b)
	return teamA ~= nil and teamA == teamB
end

function TeamService.IsTeamMode()
	return teamEnabled
end

function TeamService.GetTeamColor(teamId)
	for _, definition in ipairs(GameConfig.Teams) do
		if definition.id == teamId then
			return definition.color
		end
	end
	return Color3.fromRGB(200, 200, 200)
end

return TeamService
