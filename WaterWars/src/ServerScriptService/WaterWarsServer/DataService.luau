--[[
	DataService
	Sauvegarde persistante : pieces, armes debloquees, equipement, statistiques.

	Tout passe par pcall : si les DataStore sont indisponibles (Studio sans
	acces API, coupure Roblox), le jeu continue avec un profil en memoire au
	lieu de planter. C'est le comportement attendu d'un jeu en production.
]]

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local WaterWars = ReplicatedStorage:WaitForChild("WaterWars")
local Config = WaterWars:WaitForChild("Config")
local Shared = WaterWars:WaitForChild("Shared")

local GameConfig = require(Config:WaitForChild("GameConfig"))
local Weapons = require(Config:WaitForChild("Weapons"))
local Net = require(Shared:WaitForChild("Net"))
local Signal = require(Shared:WaitForChild("Signal"))
local Util = require(Shared:WaitForChild("Util"))

local DataService = {}

DataService.ProfileChanged = Signal.new("ProfileChanged")

local profiles = {}
local store = nil
local storeAvailable = false

local SAVE_RETRIES = 3

local function defaultProfile()
	local owned = {}
	for _, id in ipairs(Weapons.StarterIds) do
		owned[id] = true
	end
	return {
		version = 1,
		coins = GameConfig.Rewards.StartingCoins,
		owned = owned,
		loadout = {
			primary = Weapons.DefaultPrimary,
			secondary = Weapons.DefaultSecondary,
		},
		stats = {
			kills = 0,
			deaths = 0,
			wins = 0,
			rounds = 0,
			shots = 0,
			hits = 0,
			bestStreak = 0,
		},
	}
end

--- Repare un profil charge depuis le DataStore (migration douce).
local function sanitize(profile)
	local base = defaultProfile()
	if type(profile) ~= "table" then
		return base
	end
	profile.version = 1
	profile.coins = math.max(0, math.floor(tonumber(profile.coins) or base.coins))

	if type(profile.owned) ~= "table" then
		profile.owned = base.owned
	end
	-- On retire les armes qui n'existent plus et on garantit les armes de depart.
	for id in pairs(profile.owned) do
		if not Weapons.Exists(id) then
			profile.owned[id] = nil
		end
	end
	for _, id in ipairs(Weapons.StarterIds) do
		profile.owned[id] = true
	end

	if type(profile.loadout) ~= "table" then
		profile.loadout = base.loadout
	end
	for slot, fallback in pairs(base.loadout) do
		local current = profile.loadout[slot]
		if type(current) ~= "string" or not Weapons.Exists(current) or not profile.owned[current] then
			profile.loadout[slot] = fallback
		end
	end

	if type(profile.stats) ~= "table" then
		profile.stats = base.stats
	end
	for key, fallback in pairs(base.stats) do
		profile.stats[key] = math.max(0, math.floor(tonumber(profile.stats[key]) or fallback))
	end
	return profile
end

local function keyFor(player)
	return "player_" .. tostring(player.UserId)
end

local function loadProfile(player)
	if not storeAvailable or not store then
		return defaultProfile()
	end
	for attempt = 1, SAVE_RETRIES do
		local ok, result = pcall(function()
			return store:GetAsync(keyFor(player))
		end)
		if ok then
			if result == nil then
				return defaultProfile()
			end
			return sanitize(result)
		end
		warn(string.format("[WaterWars] Lecture du profil de %s echouee (essai %d) : %s", player.Name, attempt, tostring(result)))
		task.wait(attempt * 0.8)
	end
	return defaultProfile()
end

local function saveProfile(player, profile)
	if not storeAvailable or not store or profile == nil then
		return false
	end
	for attempt = 1, SAVE_RETRIES do
		local ok, err = pcall(function()
			store:SetAsync(keyFor(player), profile)
		end)
		if ok then
			return true
		end
		warn(string.format("[WaterWars] Sauvegarde du profil de %s echouee (essai %d) : %s", player.Name, attempt, tostring(err)))
		task.wait(attempt * 0.8)
	end
	return false
end

--- Envoie le profil au client concerne.
function DataService.Push(player)
	local profile = profiles[player]
	if not profile then
		return
	end
	Net.Event("ProfileUpdate"):FireClient(player, {
		coins = profile.coins,
		owned = profile.owned,
		loadout = profile.loadout,
		stats = profile.stats,
	})
end

function DataService.Get(player)
	return profiles[player]
end

--- Ajoute (ou retire) des pieces, puis previent le client.
function DataService.AddCoins(player, amount)
	local profile = profiles[player]
	if not profile then
		return 0
	end
	profile.coins = math.max(0, profile.coins + math.floor(amount))
	DataService.Push(player)
	return profile.coins
end

function DataService.Owns(player, weaponId)
	local profile = profiles[player]
	return profile ~= nil and profile.owned[weaponId] == true
end

--- Tente l'achat d'une arme. Renvoie (succes, message).
function DataService.Purchase(player, weaponId)
	local profile = profiles[player]
	if not profile then
		return false, "Profil indisponible"
	end
	local weapon = Weapons.Get(weaponId)
	if not weapon then
		return false, "Arme inconnue"
	end
	if profile.owned[weaponId] then
		return false, "Vous possedez deja cette arme"
	end
	if profile.coins < weapon.price then
		return false, string.format("Il vous manque %s pieces", Util.FormatNumber(weapon.price - profile.coins))
	end
	profile.coins = profile.coins - weapon.price
	profile.owned[weaponId] = true
	DataService.Push(player)
	DataService.ProfileChanged:Fire(player, profile)
	return true, string.format("%s debloque !", weapon.name)
end

--- Change une arme d'equipement. Renvoie (succes, message).
function DataService.SetLoadout(player, slot, weaponId)
	local profile = profiles[player]
	if not profile then
		return false, "Profil indisponible"
	end
	if slot ~= "primary" and slot ~= "secondary" then
		return false, "Emplacement invalide"
	end
	if not Weapons.Exists(weaponId) then
		return false, "Arme inconnue"
	end
	if not profile.owned[weaponId] then
		return false, "Arme non debloquee"
	end
	profile.loadout[slot] = weaponId
	DataService.Push(player)
	DataService.ProfileChanged:Fire(player, profile)
	return true, string.format("%s equipe", Weapons.Get(weaponId).name)
end

function DataService.AddStat(player, key, amount)
	local profile = profiles[player]
	if not profile or profile.stats[key] == nil then
		return
	end
	profile.stats[key] = profile.stats[key] + (amount or 1)
end

function DataService.SetBestStreak(player, streak)
	local profile = profiles[player]
	if profile and streak > profile.stats.bestStreak then
		profile.stats.bestStreak = streak
	end
end

local function onPlayerAdded(player)
	local profile = loadProfile(player)
	-- Le joueur a pu partir pendant le chargement.
	if not player.Parent then
		return
	end
	profiles[player] = profile
	DataService.Push(player)
	DataService.ProfileChanged:Fire(player, profile)
end

local function onPlayerRemoving(player)
	local profile = profiles[player]
	profiles[player] = nil
	if profile then
		saveProfile(player, profile)
	end
end

function DataService.Start()
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(GameConfig.DataStoreName)
	end)
	if ok and result then
		store = result
		-- On teste l'acces reel : en Studio sans "API Services", GetAsync echoue.
		local testOk = pcall(function()
			store:GetAsync("__connectivity_probe__")
		end)
		storeAvailable = testOk
	end
	if not storeAvailable then
		warn("[WaterWars] DataStore indisponible : les profils ne seront pas sauvegardes (normal en Studio sans acces API).")
	end

	Players.PlayerAdded:Connect(function(player)
		task.spawn(onPlayerAdded, player)
	end)
	for _, player in ipairs(Players:GetPlayers()) do
		task.spawn(onPlayerAdded, player)
	end
	Players.PlayerRemoving:Connect(onPlayerRemoving)

	game:BindToClose(function()
		for player, profile in pairs(profiles) do
			saveProfile(player, profile)
		end
		if not RunService:IsStudio() then
			task.wait(1)
		end
	end)

	-- Sauvegarde periodique : on ne perd jamais plus d'une poignee de minutes.
	task.spawn(function()
		while true do
			task.wait(GameConfig.AutosaveInterval)
			for player, profile in pairs(profiles) do
				saveProfile(player, profile)
			end
		end
	end)

	Net.Function("GetProfile").OnServerInvoke = function(player)
		local profile = profiles[player]
		if not profile then
			return nil
		end
		return {
			coins = profile.coins,
			owned = profile.owned,
			loadout = profile.loadout,
			stats = profile.stats,
		}
	end

	Net.Event("RequestPurchase").OnServerEvent:Connect(function(player, weaponId)
		if type(weaponId) ~= "string" then
			return
		end
		local success, message = DataService.Purchase(player, weaponId)
		Net.Event("Notify"):FireClient(player, message, success and "good" or "bad")
	end)
end

return DataService
