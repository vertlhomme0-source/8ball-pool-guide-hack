--[[
	MatchService
	Chef d'orchestre de la partie : vote de map, lancement de la manche,
	decompte, scores, eliminations, fin de manche et recompenses.

	Cycle : Attente -> Vote -> Chargement -> Manche -> Resultats -> Vote ...
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local WaterWars = ReplicatedStorage:WaitForChild("WaterWars")
local Config = WaterWars:WaitForChild("Config")
local Shared = WaterWars:WaitForChild("Shared")

local GameConfig = require(Config:WaitForChild("GameConfig"))
local Weapons = require(Config:WaitForChild("Weapons"))
local Net = require(Shared:WaitForChild("Net"))
local Util = require(Shared:WaitForChild("Util"))

local ServerEvents = require(script.Parent:WaitForChild("ServerEvents"))
local CombatService = require(script.Parent:WaitForChild("CombatService"))
local DataService = require(script.Parent:WaitForChild("DataService"))
local MapService = require(script.Parent:WaitForChild("MapService"))
local PickupService = require(script.Parent:WaitForChild("PickupService"))
local PlayerService = require(script.Parent:WaitForChild("PlayerService"))
local TeamService = require(script.Parent:WaitForChild("TeamService"))

local MatchService = {}

local STATE = {
	Waiting = "Waiting",
	Vote = "Vote",
	Loading = "Loading",
	Active = "Active",
	Results = "Results",
}

local state = STATE.Waiting
local stateEndsAt = 0
local currentMode = GameConfig.GameModes[1]
local currentMap = nil
local modeIndex = 0
local lastMapId = nil

local teamScores = { Blue = 0, Red = 0 }
local roundStats = {}
local damageLog = {} -- damageLog[victim] = { [attacker] = degats }

local voteOptions = {}
local votes = {}

local rng = Random.new(os.time() + 11)
local hillAccumulator = 0
local scoreboardAccumulator = 0
local lastResult = nil

-- ------------------------------------------------------------- utilitaires

local function statsFor(player)
	local stats = roundStats[player]
	if not stats then
		stats = { kills = 0, deaths = 0, score = 0, streak = 0, assists = 0 }
		roundStats[player] = stats
	end
	return stats
end

local function modeById(id)
	for _, mode in ipairs(GameConfig.GameModes) do
		if mode.id == id then
			return mode
		end
	end
	return GameConfig.GameModes[1]
end

local function scoreLimit()
	return GameConfig.ScoreLimit[currentMode.id] or 50
end

local function timeLeft()
	return math.max(0, stateEndsAt - os.clock())
end

--- Vue envoyee au client a chaque changement d'etat et chaque seconde.
local function buildStatePayload()
	return {
		state = state,
		timeLeft = timeLeft(),
		mode = {
			id = currentMode.id,
			name = currentMode.name,
			description = currentMode.description,
			teamBased = currentMode.teamBased,
		},
		map = currentMap and MapService.Describe(currentMap) or nil,
		scores = { Blue = teamScores.Blue, Red = teamScores.Red },
		scoreLimit = scoreLimit(),
		playerCount = #Players:GetPlayers(),
		minPlayers = GameConfig.MinPlayersToStart,
		result = lastResult,
	}
end

local function broadcastState()
	Net.Event("MatchState"):FireAllClients(buildStatePayload())
end

local function broadcastScoreboard()
	local rows = {}
	for _, player in ipairs(Players:GetPlayers()) do
		local stats = statsFor(player)
		table.insert(rows, {
			userId = player.UserId,
			name = player.DisplayName,
			team = TeamService.GetTeamId(player),
			kills = stats.kills,
			deaths = stats.deaths,
			assists = stats.assists,
			score = stats.score,
			streak = stats.streak,
		})
	end
	table.sort(rows, function(a, b)
		if a.score == b.score then
			return a.kills > b.kills
		end
		return a.score > b.score
	end)
	Net.Event("Scoreboard"):FireAllClients(rows)
end

local function setState(newState, duration)
	state = newState
	stateEndsAt = os.clock() + duration
	broadcastState()
end

local function notifyAll(message, kind)
	Net.Event("Notify"):FireAllClients(message, kind or "info")
end

-- ------------------------------------------------------------------ vote

local function startVote()
	currentMap = nil
	lastResult = nil
	table.clear(votes)
	voteOptions = MapService.PickRandom(GameConfig.MapVoteChoices, lastMapId, rng)

	modeIndex = modeIndex + 1
	local rotation = GameConfig.ModeRotation
	currentMode = modeById(rotation[((modeIndex - 1) % #rotation) + 1])

	local payload = {}
	for _, map in ipairs(voteOptions) do
		table.insert(payload, MapService.Describe(map))
	end

	setState(STATE.Vote, GameConfig.MapVoteTime)
	Net.Event("MapVote"):FireAllClients({
		phase = "open",
		options = payload,
		duration = GameConfig.MapVoteTime,
		votes = {},
		mode = currentMode.name,
	})
end

local function broadcastVotes()
	local counts = {}
	for _, mapId in pairs(votes) do
		counts[mapId] = (counts[mapId] or 0) + 1
	end
	Net.Event("MapVote"):FireAllClients({ phase = "update", votes = counts })
end

local function resolveVote()
	local counts = {}
	for _, mapId in pairs(votes) do
		counts[mapId] = (counts[mapId] or 0) + 1
	end
	local bestMap, bestCount = nil, -1
	for _, map in ipairs(voteOptions) do
		local count = counts[map.id] or 0
		if count > bestCount then
			bestMap, bestCount = map, count
		end
	end
	if not bestMap then
		bestMap = Util.Pick(MapService.GetAll(), rng)
	end
	return bestMap
end

-- ------------------------------------------------------------- manche

local function resetRound()
	teamScores.Blue = 0
	teamScores.Red = 0
	table.clear(roundStats)
	table.clear(damageLog)
	for _, player in ipairs(Players:GetPlayers()) do
		statsFor(player)
	end
end

local function startRound(map)
	currentMap = map
	lastMapId = map.id
	resetRound()

	setState(STATE.Loading, 3)
	CombatService.SetRoundActive(false)
	PlayerService.SetRespawnEnabled(false)
	MapService.Load(map)
	PickupService.Setup(map)
	TeamService.SetTeamMode(currentMode.teamBased)
	Net.Event("MapReady"):FireAllClients(MapService.Describe(map))

	task.wait(2)

	PlayerService.SetRespawnEnabled(true)
	PlayerService.SpawnAll()
	CombatService.SetRoundActive(true)

	setState(STATE.Active, GameConfig.RoundTime)
	notifyAll(string.format("%s - %s", currentMode.name, map.name), "good")
	broadcastScoreboard()
	ServerEvents.RoundStarted:Fire(map, currentMode)
end

local function winnerText()
	if currentMode.teamBased then
		if teamScores.Blue == teamScores.Red then
			return "Egalite parfaite !", nil
		end
		local winnerId = teamScores.Blue > teamScores.Red and "Blue" or "Red"
		for _, definition in ipairs(GameConfig.Teams) do
			if definition.id == winnerId then
				return definition.name .. " remporte la manche !", winnerId
			end
		end
	end

	local bestPlayer, bestScore = nil, -1
	for player, stats in pairs(roundStats) do
		if stats.score > bestScore then
			bestPlayer, bestScore = player, stats.score
		end
	end
	if bestPlayer then
		return string.format("%s remporte la manche avec %d points !", bestPlayer.DisplayName, bestScore), nil
	end
	return "Manche terminee", nil
end

local function payRewards(winnerTeamId)
	for _, player in ipairs(Players:GetPlayers()) do
		local stats = statsFor(player)
		local reward = 0
		if currentMode.teamBased then
			local teamId = TeamService.GetTeamId(player)
			if winnerTeamId and teamId == winnerTeamId then
				reward = GameConfig.Rewards.RoundWin
				DataService.AddStat(player, "wins", 1)
			else
				reward = GameConfig.Rewards.RoundLoss
			end
		else
			reward = GameConfig.Rewards.RoundLoss + stats.score
		end
		DataService.AddStat(player, "rounds", 1)
		if reward > 0 then
			DataService.AddCoins(player, reward)
		end
	end
end

local function endRound()
	CombatService.SetRoundActive(false)
	PlayerService.SetRespawnEnabled(false)

	local message, winnerTeamId = winnerText()
	payRewards(winnerTeamId)

	local ranking = {}
	for player, stats in pairs(roundStats) do
		table.insert(ranking, {
			name = player.DisplayName,
			kills = stats.kills,
			deaths = stats.deaths,
			score = stats.score,
			team = TeamService.GetTeamId(player),
		})
	end
	table.sort(ranking, function(a, b)
		return a.score > b.score
	end)

	lastResult = {
		message = message,
		winner = winnerTeamId,
		scores = { Blue = teamScores.Blue, Red = teamScores.Red },
		ranking = ranking,
		mapName = currentMap and currentMap.name or "",
	}

	setState(STATE.Results, GameConfig.PostRoundTime)
	notifyAll(message, "good")
	broadcastScoreboard()
	ServerEvents.RoundEnded:Fire(lastResult)

	task.wait(GameConfig.PostRoundTime)

	-- La map reste chargee : entre deux manches les joueurs continuent de
	-- s'echauffer dessus au lieu de fixer un ecran vide. Elle sera remplacee
	-- par MapService.Load() au debut de la manche suivante.
	PickupService.Clear()
end

-- --------------------------------------------------------- roi de la piscine

local function updateHill(deltaTime)
	if currentMode.id ~= "KingOfTheHill" or not currentMap then
		return
	end
	hillAccumulator = hillAccumulator + deltaTime
	if hillAccumulator < GameConfig.HillTickRate then
		return
	end
	hillAccumulator = 0

	local center = currentMap.controlPoint
	local counts = { Blue = 0, Red = 0 }
	for _, player in ipairs(Players:GetPlayers()) do
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if root and humanoid and humanoid.Health > 0 then
			if ((root :: BasePart).Position - center).Magnitude <= GameConfig.HillRadius then
				local teamId = TeamService.GetTeamId(player)
				if teamId and counts[teamId] then
					counts[teamId] = counts[teamId] + 1
				end
			end
		end
	end

	local holder = nil
	if counts.Blue >= GameConfig.HillContestedNeeded and counts.Blue > counts.Red then
		holder = "Blue"
	elseif counts.Red >= GameConfig.HillContestedNeeded and counts.Red > counts.Blue then
		holder = "Red"
	end

	if holder then
		teamScores[holder] = teamScores[holder] + GameConfig.HillPointsPerTick
		MapService.SetHillColor(TeamService.GetTeamColor(holder), 0.72)
		for _, player in ipairs(Players:GetPlayers()) do
			local character = player.Character
			local root = character and character:FindFirstChild("HumanoidRootPart")
			if root and TeamService.GetTeamId(player) == holder then
				if ((root :: BasePart).Position - center).Magnitude <= GameConfig.HillRadius then
					statsFor(player).score = statsFor(player).score + GameConfig.HillPointsPerTick
					DataService.AddCoins(player, GameConfig.Rewards.CaptureTick)
				end
			end
		end
	elseif counts.Blue > 0 and counts.Red > 0 then
		MapService.SetHillColor(Color3.fromRGB(255, 220, 90), 0.72) -- zone disputee
	else
		MapService.SetHillColor(Color3.fromRGB(230, 230, 230), 0.86)
	end
end

-- ------------------------------------------------------------ eliminations

local function onPlayerKilled(victim, killer, weaponId)
	if state ~= STATE.Active then
		return
	end
	local victimStats = statsFor(victim)
	victimStats.deaths = victimStats.deaths + 1
	victimStats.streak = 0
	DataService.AddStat(victim, "deaths", 1)

	local weapon = weaponId and Weapons.Get(weaponId) or nil

	if killer and killer ~= victim then
		local killerStats = statsFor(killer)
		killerStats.kills = killerStats.kills + 1
		killerStats.streak = killerStats.streak + 1
		killerStats.score = killerStats.score + GameConfig.Rewards.Splash
		DataService.AddStat(killer, "kills", 1)
		DataService.SetBestStreak(killer, killerStats.streak)

		local coins = GameConfig.Rewards.Kill
		local bonus = GameConfig.KillstreakBonus[killerStats.streak]
		if bonus then
			coins = coins + bonus
			Net.Event("Notify"):FireClient(killer, string.format("Serie de %d ! +%d pieces", killerStats.streak, bonus), "good")
		end
		DataService.AddCoins(killer, coins)

		if currentMode.teamBased then
			local teamId = TeamService.GetTeamId(killer)
			if teamId and teamScores[teamId] then
				teamScores[teamId] = teamScores[teamId] + GameConfig.Rewards.Splash
			end
		end
	end

	-- Assistances : tout joueur ayant inflige au moins 25 degats a la victime.
	local log = damageLog[victim]
	if log then
		for attacker, amount in pairs(log) do
			if attacker ~= killer and attacker ~= victim and amount >= 25 and attacker.Parent then
				local assistStats = statsFor(attacker)
				assistStats.assists = assistStats.assists + 1
				assistStats.score = assistStats.score + 1
				DataService.AddCoins(attacker, GameConfig.Rewards.Assist)
			end
		end
		damageLog[victim] = nil
	end

	Net.Event("KillFeed"):FireAllClients({
		killer = killer and killer.DisplayName or nil,
		killerTeam = killer and TeamService.GetTeamId(killer) or nil,
		victim = victim.DisplayName,
		victimTeam = TeamService.GetTeamId(victim),
		weapon = weapon and weapon.name or nil,
	})
	broadcastState()
	broadcastScoreboard()
end

local function onPlayerDamaged(victim, attacker, amount)
	if not attacker or attacker == victim then
		return
	end
	local log = damageLog[victim]
	if not log then
		log = {}
		damageLog[victim] = log
	end
	log[attacker] = (log[attacker] or 0) + amount
end

-- --------------------------------------------------------- fin de manche ?

local function shouldEndRound()
	if timeLeft() <= 0 then
		return true
	end
	local limit = scoreLimit()
	if currentMode.teamBased then
		return teamScores.Blue >= limit or teamScores.Red >= limit
	end
	for _, stats in pairs(roundStats) do
		if stats.kills >= limit then
			return true
		end
	end
	return false
end

-- ------------------------------------------------------------ boucle

local function gameLoop()
	-- Un terrain est charge des le demarrage du serveur : les premiers joueurs
	-- arrivent dans un decor, pas dans le vide.
	if not MapService.GetCurrentMap() then
		local first = Util.Pick(MapService.GetAll(), rng)
		pcall(MapService.Load, first)
	end

	while true do
		if #Players:GetPlayers() < GameConfig.MinPlayersToStart then
			setState(STATE.Waiting, 1)
			PlayerService.SetRespawnEnabled(true)
			PlayerService.SpawnAll()
			repeat
				task.wait(1)
				broadcastState()
			until #Players:GetPlayers() >= GameConfig.MinPlayersToStart
		end

		-- Echauffement : tout le monde est vivant et peut tirer, mais rien
		-- n'est compte au score (voir onPlayerKilled).
		PlayerService.SetRespawnEnabled(true)
		CombatService.SetRoundActive(true)
		PlayerService.SpawnAll()

		startVote()
		local voteEnd = os.clock() + GameConfig.MapVoteTime
		while os.clock() < voteEnd do
			task.wait(1)
			broadcastState()
		end

		local map = resolveVote()
		Net.Event("MapVote"):FireAllClients({ phase = "closed", chosen = MapService.Describe(map) })

		local ok, err = pcall(startRound, map)
		if not ok then
			warn("[WaterWars] Impossible de demarrer la manche : " .. tostring(err))
			MapService.Unload()
			task.wait(3)
		else
			while state == STATE.Active and not shouldEndRound() do
				task.wait(0.5)
				broadcastState()
			end
			local endedOk, endErr = pcall(endRound)
			if not endedOk then
				warn("[WaterWars] Erreur de fin de manche : " .. tostring(endErr))
				PlayerService.DespawnAll()
				PickupService.Clear()
				MapService.Unload()
			end
		end
	end
end

-- ------------------------------------------------------------ interface

function MatchService.GetState()
	return state
end

function MatchService.IsRoundActive()
	return state == STATE.Active
end

function MatchService.Start()
	ServerEvents.PlayerKilled:Connect(onPlayerKilled)
	ServerEvents.PlayerDamaged:Connect(onPlayerDamaged)

	ServerEvents.CharacterSpawned:Connect(function(player)
		damageLog[player] = nil
	end)

	Net.Event("CastMapVote").OnServerEvent:Connect(function(player, mapId)
		if state ~= STATE.Vote or type(mapId) ~= "string" then
			return
		end
		for _, map in ipairs(voteOptions) do
			if map.id == mapId then
				votes[player] = mapId
				broadcastVotes()
				return
			end
		end
	end)

	Players.PlayerAdded:Connect(function(player)
		statsFor(player)
		TeamService.Assign(player)
		task.wait(0.5)
		broadcastState()
		broadcastScoreboard()
		-- Un joueur qui arrive entre directement en jeu, sauf pendant le
		-- chargement d'un terrain (il apparaitrait dans le vide).
		if state ~= STATE.Loading then
			task.spawn(PlayerService.Spawn, player)
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		roundStats[player] = nil
		damageLog[player] = nil
		votes[player] = nil
		broadcastScoreboard()
	end)

	for _, player in ipairs(Players:GetPlayers()) do
		statsFor(player)
		TeamService.Assign(player)
	end

	RunService.Heartbeat:Connect(function(deltaTime)
		if state ~= STATE.Active then
			return
		end
		local ok, err = pcall(updateHill, deltaTime)
		if not ok then
			warn("[WaterWars] Erreur de la zone de controle : " .. tostring(err))
		end
		scoreboardAccumulator = scoreboardAccumulator + deltaTime
		if scoreboardAccumulator >= 3 then
			scoreboardAccumulator = 0
			broadcastScoreboard()
		end
	end)

	task.spawn(function()
		local ok, err = pcall(gameLoop)
		if not ok then
			warn("[WaterWars] La boucle de partie s'est arretee : " .. tostring(err))
		end
	end)
end

return MatchService
