--[[
	GameConfig
	Toutes les constantes de reglage du jeu Water Wars.
	Modifier ce fichier suffit pour re-equilibrer la partie : aucun autre
	module ne contient de valeur "en dur".
]]

local GameConfig = {}

-- ============================ SERVEUR / LOBBY =============================
GameConfig.MaxPlayers = 20
GameConfig.MinPlayersToStart = 1 -- 1 pour pouvoir tester seul, mettre 2 en production

-- ============================== DEROULE DE PARTIE =========================
GameConfig.IntermissionTime = 25 -- secondes entre deux manches (vote de map)
GameConfig.RoundTime = 300 -- duree d'une manche
GameConfig.PostRoundTime = 12 -- ecran de fin de manche
GameConfig.RespawnTime = 5
GameConfig.SpawnProtectionTime = 3 -- invulnerabilite apres apparition

-- Score necessaire pour terminer une manche avant la fin du temps
GameConfig.ScoreLimit = {
	TeamSoak = 60,
	FreeForAll = 25,
	KingOfTheHill = 300, -- points de zone
}

-- ============================== EQUIPES ===================================
GameConfig.Teams = {
	{ id = "Blue", name = "Aqua Blue", color = Color3.fromRGB(45, 135, 255), brickColor = BrickColor.new("Bright blue") },
	{ id = "Red", name = "Splash Red", color = Color3.fromRGB(255, 80, 70), brickColor = BrickColor.new("Bright red") },
}

-- ============================== COMBAT ====================================
GameConfig.MaxHealth = 100
GameConfig.WalkSpeed = 18
GameConfig.SprintSpeed = 26
GameConfig.JumpPower = 52
GameConfig.StaminaMax = 100
GameConfig.StaminaDrain = 22 -- par seconde en sprint
GameConfig.StaminaRegen = 16 -- par seconde au repos
GameConfig.StaminaSprintMin = 12 -- stamina requise pour relancer un sprint

-- Regeneration de vie (comme dans la plupart des shooters arcade)
GameConfig.RegenDelay = 6 -- secondes sans degats avant regen
GameConfig.RegenRate = 9 -- points de vie par seconde

-- Anti-triche : distance max entre le personnage et l'origine du tir declare
GameConfig.MaxFireOriginDistance = 14
GameConfig.FireRateTolerance = 0.85 -- 15 % de marge reseau sur la cadence
GameConfig.MaxActiveProjectiles = 420 -- garde-fou de performance serveur

-- Recompenses
GameConfig.Rewards = {
	Hit = 1,
	Splash = 2, -- points marques par elimination (mode TeamSoak)
	Kill = 12, -- pieces gagnees par elimination
	Assist = 5,
	RoundWin = 60,
	RoundLoss = 25,
	CaptureTick = 2, -- pieces par tick de zone controlee
	StartingCoins = 250,
}

GameConfig.KillstreakBonus = { [3] = 15, [5] = 35, [8] = 70, [12] = 140 }

-- ============================== BIDONS D'EAU ==============================
GameConfig.RefillRadius = 9 -- distance a une station pour se recharger
GameConfig.RefillRate = 45 -- unites d'eau par seconde
GameConfig.RefillHealRate = 12 -- soin par seconde a la station

-- ============================== BONUS AU SOL ==============================
GameConfig.PowerupRespawn = 30
GameConfig.Powerups = {
	{ id = "Speed", name = "Turbo", color = Color3.fromRGB(255, 225, 60), duration = 12 },
	{ id = "Damage", name = "Haute pression", color = Color3.fromRGB(255, 110, 40), duration = 12 },
	{ id = "Shield", name = "Impermeable", color = Color3.fromRGB(120, 230, 255), duration = 10 },
	{ id = "Refill", name = "Citerne", color = Color3.fromRGB(80, 255, 140), duration = 0 },
}
GameConfig.PowerupSpeedMultiplier = 1.35
GameConfig.PowerupDamageMultiplier = 1.5
GameConfig.PowerupShieldReduction = 0.5

-- ============================== VOTE DE MAP ===============================
GameConfig.MapVoteChoices = 3
GameConfig.MapVoteTime = 18

-- ============================== MODES DE JEU ==============================
GameConfig.GameModes = {
	{
		id = "TeamSoak",
		name = "Bataille d'equipes",
		description = "Deux equipes, le premier camp a atteindre le score gagne.",
		teamBased = true,
		friendlyFire = false,
	},
	{
		id = "FreeForAll",
		name = "Chacun pour soi",
		description = "Tout le monde contre tout le monde. Le meilleur trempeur gagne.",
		teamBased = false,
		friendlyFire = true,
	},
	{
		id = "KingOfTheHill",
		name = "Roi de la piscine",
		description = "Controlez la zone centrale pour marquer des points.",
		teamBased = true,
		friendlyFire = false,
	},
}

-- Rotation des modes : un mode est tire au sort dans cette liste chaque manche
GameConfig.ModeRotation = { "TeamSoak", "TeamSoak", "KingOfTheHill", "FreeForAll" }

-- ============================== ZONE DE CONTROLE ==========================
GameConfig.HillRadius = 22
GameConfig.HillTickRate = 1 -- secondes entre deux points
GameConfig.HillPointsPerTick = 2
GameConfig.HillContestedNeeded = 1 -- joueurs necessaires pour capturer

-- ============================== SAUVEGARDE ================================
GameConfig.DataStoreName = "WaterWars_PlayerData_v1"
GameConfig.AutosaveInterval = 120

-- ============================== SONS ======================================
-- Uniquement des sons livres avec le client Roblox (rbxasset://) : aucun
-- upload necessaire, et aucun risque d'ID modere. Mettre "" pour desactiver.
GameConfig.Sounds = {
	Shoot = "rbxasset://sounds/impact_water.mp3",
	Hit = "rbxasset://sounds/impact_water.mp3",
	Splash = "rbxasset://sounds/impact_water.mp3",
	Eliminate = "rbxasset://sounds/electronicpingshort.wav",
	Reload = "rbxasset://sounds/switch3.wav",
	Purchase = "rbxasset://sounds/electronicpingshort.wav",
	RoundStart = "rbxasset://sounds/electronicpingshort.wav",
}

-- ============================== INTERFACE =================================
GameConfig.UI = {
	Accent = Color3.fromRGB(60, 190, 255),
	AccentDark = Color3.fromRGB(20, 90, 150),
	Panel = Color3.fromRGB(18, 24, 34),
	PanelLight = Color3.fromRGB(30, 40, 54),
	Text = Color3.fromRGB(235, 245, 255),
	TextDim = Color3.fromRGB(150, 170, 190),
	Good = Color3.fromRGB(80, 230, 140),
	Bad = Color3.fromRGB(255, 90, 90),
	Warn = Color3.fromRGB(255, 200, 70),
	Font = Enum.Font.GothamMedium,
	FontBold = Enum.Font.GothamBold,
}

-- ============================== TOUCHES ===================================
GameConfig.Keys = {
	Sprint = Enum.KeyCode.LeftShift,
	Reload = Enum.KeyCode.R,
	Shop = Enum.KeyCode.B,
	Scoreboard = Enum.KeyCode.Tab,
	Inspect = Enum.KeyCode.F,
}

table.freeze(GameConfig)
return GameConfig
