--[[
	Weapons
	Catalogue des 25 armes a eau du jeu.

	Chaque arme herite des valeurs par defaut de sa categorie (CATEGORY_DEFAULTS)
	puis applique ses propres reglages. Toutes les armes exposent donc exactement
	le meme jeu de champs, ce qui evite les "nil" cote serveur comme cote client.

	Champs :
	  damage           degats par goutte touchee
	  fireRate         tirs par seconde
	  autoFire         true = maintenir le clic tire en rafale
	  burst            nombre de gouttes tirees par appui (rafale)
	  tankSize         capacite du reservoir
	  tankCost         eau consommee par tir
	  reloadTime       duree du rechargement
	  speed            vitesse du projectile en studs/seconde
	  gravity          multiplicateur de gravite applique au projectile
	  lifetime         duree de vie max du projectile
	  spread           dispersion en degres
	  pellets          nombre de gouttes par tir
	  radius           rayon visuel de la goutte
	  splashRadius     rayon des degats de zone (0 = aucun)
	  splashDamage     degats de zone au centre
	  slow             ralentissement inflige (0..1)
	  slowTime         duree du ralentissement
	  heal             soin applique a un coequipier touche
	  chargeTime       temps de charge max (0 = pas de charge)
	  chargeBonus      multiplicateur de degats a pleine charge
	  headshot         multiplicateur de degats a la tete
	  walkSpeedMul     multiplicateur de vitesse quand l'arme est equipee
	  zoom             champ de vision en vise (0 = pas de vise)
	  model            dimensions du modele procedural
]]

local Weapons = {}

local RARITY = {
	Starter = { name = "Depart", color = Color3.fromRGB(170, 180, 195) },
	Common = { name = "Commun", color = Color3.fromRGB(120, 220, 130) },
	Rare = { name = "Rare", color = Color3.fromRGB(80, 170, 255) },
	Epic = { name = "Epique", color = Color3.fromRGB(190, 110, 255) },
	Legendary = { name = "Legendaire", color = Color3.fromRGB(255, 180, 60) },
}
Weapons.Rarity = RARITY

local CATEGORY_DEFAULTS = {
	Pistol = {
		damage = 14, fireRate = 4.5, autoFire = false, burst = 1,
		tankSize = 72, tankCost = 4, reloadTime = 1.4,
		speed = 200, gravity = 0.45, lifetime = 1.6, spread = 1.1, pellets = 1,
		radius = 0.34, headshot = 1.6, walkSpeedMul = 1.05, zoom = 0,
		model = { barrel = 1.5, thick = 0.42, tank = 0.8 },
	},
	SMG = {
		damage = 9, fireRate = 11, autoFire = true, burst = 1,
		tankSize = 120, tankCost = 3, reloadTime = 1.9,
		speed = 195, gravity = 0.5, lifetime = 1.5, spread = 3.0, pellets = 1,
		radius = 0.3, headshot = 1.3, walkSpeedMul = 1.02, zoom = 0,
		model = { barrel = 2.0, thick = 0.46, tank = 1.0 },
	},
	Rifle = {
		damage = 17, fireRate = 6.5, autoFire = true, burst = 1,
		tankSize = 110, tankCost = 5, reloadTime = 2.1,
		speed = 235, gravity = 0.35, lifetime = 2.0, spread = 1.6, pellets = 1,
		radius = 0.34, headshot = 1.7, walkSpeedMul = 1.0, zoom = 55,
		model = { barrel = 2.8, thick = 0.5, tank = 1.1 },
	},
	Shotgun = {
		damage = 8, fireRate = 1.2, autoFire = false, burst = 1,
		tankSize = 56, tankCost = 8, reloadTime = 2.6,
		speed = 165, gravity = 0.8, lifetime = 0.9, spread = 7.5, pellets = 8,
		radius = 0.3, headshot = 1.2, walkSpeedMul = 0.98, zoom = 0,
		model = { barrel = 2.4, thick = 0.62, tank = 1.1 },
	},
	Sniper = {
		damage = 62, fireRate = 0.85, autoFire = false, burst = 1,
		tankSize = 30, tankCost = 6, reloadTime = 2.8,
		speed = 420, gravity = 0.08, lifetime = 3.0, spread = 0.0, pellets = 1,
		radius = 0.28, headshot = 2.0, walkSpeedMul = 0.92, zoom = 24,
		model = { barrel = 4.2, thick = 0.44, tank = 0.9 },
	},
	Heavy = {
		damage = 11, fireRate = 13, autoFire = true, burst = 1,
		tankSize = 260, tankCost = 3, reloadTime = 4.2,
		speed = 200, gravity = 0.55, lifetime = 1.4, spread = 4.5, pellets = 1,
		radius = 0.36, headshot = 1.15, walkSpeedMul = 0.85, zoom = 0,
		model = { barrel = 3.2, thick = 0.8, tank = 1.7 },
	},
	Launcher = {
		damage = 18, fireRate = 0.9, autoFire = false, burst = 1,
		tankSize = 24, tankCost = 6, reloadTime = 2.9,
		speed = 110, gravity = 1.6, lifetime = 4.0, spread = 0.6, pellets = 1,
		radius = 0.8, splashRadius = 12, splashDamage = 45,
		headshot = 1.0, walkSpeedMul = 0.94, zoom = 0,
		model = { barrel = 3.0, thick = 0.9, tank = 1.3 },
	},
	Special = {
		damage = 12, fireRate = 6, autoFire = true, burst = 1,
		tankSize = 110, tankCost = 4, reloadTime = 2.2,
		speed = 180, gravity = 0.4, lifetime = 1.5, spread = 2.0, pellets = 1,
		radius = 0.36, headshot = 1.3, walkSpeedMul = 1.0, zoom = 0,
		model = { barrel = 2.4, thick = 0.6, tank = 1.2 },
	},
}
Weapons.CategoryDefaults = CATEGORY_DEFAULTS

Weapons.CategoryNames = {
	Pistol = "Pistolets",
	SMG = "Mitraillettes",
	Rifle = "Fusils",
	Shotgun = "Fusils a pompe",
	Sniper = "Snipers",
	Heavy = "Armes lourdes",
	Launcher = "Lanceurs",
	Special = "Speciales",
}

Weapons.CategoryOrder = { "Pistol", "SMG", "Rifle", "Shotgun", "Sniper", "Heavy", "Launcher", "Special" }

-- Valeurs communes a toutes les armes, appliquees en dernier recours.
local BASE = {
	damage = 10, fireRate = 3, autoFire = false, burst = 1,
	tankSize = 80, tankCost = 5, reloadTime = 2,
	speed = 180, gravity = 0.5, lifetime = 2, spread = 2, pellets = 1,
	radius = 0.35, splashRadius = 0, splashDamage = 0,
	slow = 0, slowTime = 0, heal = 0,
	chargeTime = 0, chargeBonus = 1,
	headshot = 1.5, walkSpeedMul = 1, zoom = 0,
	price = 0, rarity = "Common",
	color = Color3.fromRGB(90, 190, 255),
	accent = Color3.fromRGB(240, 250, 255),
	trail = Color3.fromRGB(150, 225, 255),
}

-- Definition brute : uniquement ce qui differe des defauts.
local RAW = {
	-- ------------------------------- PISTOLETS ---------------------------
	{
		id = "squirt_pistol", name = "Pistolet Eclaboussure", category = "Pistol",
		rarity = "Starter", price = 0,
		desc = "Le grand classique de la cour de recreation. Fiable, leger, gratuit.",
		damage = 14, fireRate = 4.5,
		color = Color3.fromRGB(255, 190, 60), accent = Color3.fromRGB(255, 240, 190),
	},
	{
		id = "pocket_blaster", name = "Blaster de Poche", category = "Pistol",
		rarity = "Common", price = 450,
		desc = "Minuscule mais tres rapide. Parfait en duel rapproche.",
		damage = 11, fireRate = 7.2, tankSize = 60, tankCost = 3, reloadTime = 1.1,
		walkSpeedMul = 1.12, spread = 2.2,
		color = Color3.fromRGB(120, 255, 210), accent = Color3.fromRGB(30, 60, 70),
		model = { barrel = 1.1, thick = 0.38, tank = 0.6 },
	},
	{
		id = "drencher_45", name = "Drencher .45", category = "Pistol",
		rarity = "Epic", price = 2600,
		desc = "Gros calibre a eau : trois gouttes lourdes par appui.",
		damage = 13, fireRate = 2.4, burst = 3, tankSize = 72, tankCost = 4,
		speed = 250, spread = 1.4, headshot = 1.8,
		color = Color3.fromRGB(40, 45, 60), accent = Color3.fromRGB(255, 200, 80),
		model = { barrel = 1.8, thick = 0.5, tank = 0.9 },
	},

	-- ------------------------------ MITRAILLETTES ------------------------
	{
		id = "tidal_smg", name = "Tidal SMG", category = "SMG",
		rarity = "Common", price = 800,
		desc = "Cadence elevee, reservoir genereux. Le couteau suisse.",
		color = Color3.fromRGB(70, 130, 220), accent = Color3.fromRGB(200, 230, 255),
	},
	{
		id = "splash_smg", name = "Micro-Splash", category = "SMG",
		rarity = "Rare", price = 1500,
		desc = "Chaque goutte eclabousse legerement autour de l'impact.",
		damage = 8, fireRate = 12, splashRadius = 4.5, splashDamage = 5,
		tankSize = 132, spread = 3.4,
		color = Color3.fromRGB(255, 120, 190), accent = Color3.fromRGB(70, 20, 50),
	},
	{
		id = "hydro_uzi", name = "Hydro Uzi", category = "SMG",
		rarity = "Epic", price = 2900,
		desc = "La cadence la plus folle de sa categorie. Videz le chargeur.",
		damage = 8, fireRate = 16, tankSize = 150, tankCost = 3, reloadTime = 2.2,
		spread = 4.2, walkSpeedMul = 1.06,
		color = Color3.fromRGB(35, 40, 48), accent = Color3.fromRGB(120, 255, 255),
		model = { barrel = 1.7, thick = 0.44, tank = 1.0 },
	},

	-- --------------------------------- FUSILS ----------------------------
	{
		id = "stream_rifle", name = "Fusil a Jet", category = "Rifle",
		rarity = "Starter", price = 0,
		desc = "Arme de dotation : precise, polyvalente, sans surprise.",
		color = Color3.fromRGB(60, 160, 240), accent = Color3.fromRGB(230, 245, 255),
	},
	{
		id = "aqua_carbine", name = "Carabine Aqua", category = "Rifle",
		rarity = "Common", price = 950,
		desc = "Plus legere et plus rapide que le fusil de base.",
		damage = 15, fireRate = 8, spread = 2.0, walkSpeedMul = 1.06,
		color = Color3.fromRGB(150, 200, 90), accent = Color3.fromRGB(40, 60, 30),
		model = { barrel = 2.4, thick = 0.46, tank = 1.0 },
	},
	{
		id = "hydro_ar", name = "Hydro AR", category = "Rifle",
		rarity = "Rare", price = 2100,
		desc = "Rafales de trois gouttes tres precises a moyenne distance.",
		damage = 16, fireRate = 3.2, burst = 3, tankSize = 120, tankCost = 4,
		speed = 265, spread = 0.9,
		color = Color3.fromRGB(50, 55, 65), accent = Color3.fromRGB(90, 200, 255),
	},
	{
		id = "pulse_repeater", name = "Repeteur a Impulsion", category = "Rifle",
		rarity = "Epic", price = 3400,
		desc = "Projectiles a haute pression qui ignorent presque la gravite.",
		damage = 21, fireRate = 5.5, speed = 320, gravity = 0.12,
		tankSize = 100, tankCost = 6, splashRadius = 5, splashDamage = 8,
		color = Color3.fromRGB(120, 60, 220), accent = Color3.fromRGB(230, 200, 255),
		trail = Color3.fromRGB(200, 150, 255),
		model = { barrel = 3.0, thick = 0.54, tank = 1.2 },
	},

	-- ----------------------------- FUSILS A POMPE ------------------------
	{
		id = "splash_shotgun", name = "Fusil a Eclaboussures", category = "Shotgun",
		rarity = "Common", price = 1100,
		desc = "Huit gouttes d'un coup. Devastateur au contact.",
		color = Color3.fromRGB(180, 70, 60), accent = Color3.fromRGB(255, 220, 180),
	},
	{
		id = "bucket_blaster", name = "Lance-Seau", category = "Shotgun",
		rarity = "Rare", price = 2200,
		desc = "Balance un seau entier : douze gouttes en cone serre.",
		damage = 7, pellets = 12, spread = 6.5, fireRate = 1.0,
		tankSize = 60, tankCost = 10, reloadTime = 2.9,
		color = Color3.fromRGB(255, 150, 40), accent = Color3.fromRGB(60, 35, 10),
		model = { barrel = 2.0, thick = 0.85, tank = 1.3 },
	},
	{
		id = "wave_breaker", name = "Brise-Vague", category = "Shotgun",
		rarity = "Epic", price = 3800,
		desc = "Double detente : deux salves coup sur coup, puis rechargement.",
		damage = 9, pellets = 9, spread = 8.0, fireRate = 2.4, burst = 1,
		tankSize = 32, tankCost = 16, reloadTime = 3.1, splashRadius = 3.5, splashDamage = 4,
		color = Color3.fromRGB(30, 90, 130), accent = Color3.fromRGB(180, 255, 250),
		model = { barrel = 2.6, thick = 0.7, tank = 1.2 },
	},

	-- --------------------------------- SNIPERS ---------------------------
	{
		id = "precision_dripper", name = "Goutte de Precision", category = "Sniper",
		rarity = "Common", price = 1400,
		desc = "Sniper d'entree de gamme : leger, rapide a recharger.",
		damage = 48, fireRate = 1.2, reloadTime = 2.2, tankSize = 36, zoom = 30,
		walkSpeedMul = 0.96,
		color = Color3.fromRGB(90, 110, 90), accent = Color3.fromRGB(200, 220, 200),
	},
	{
		id = "hydro_sniper", name = "Hydro Sniper", category = "Sniper",
		rarity = "Rare", price = 2500,
		desc = "Un tir a la tete, un adversaire trempe. Le grand classique.",
		color = Color3.fromRGB(45, 55, 70), accent = Color3.fromRGB(120, 220, 255),
	},
	{
		id = "longshot_soaker", name = "Longue Portee", category = "Sniper",
		rarity = "Legendary", price = 5200,
		desc = "Projectile quasi rectiligne et charge : un coup, une elimination.",
		damage = 55, fireRate = 0.6, speed = 520, gravity = 0.02, lifetime = 4,
		tankSize = 24, tankCost = 8, reloadTime = 3.2, zoom = 18,
		chargeTime = 0.9, chargeBonus = 1.9, walkSpeedMul = 0.88,
		color = Color3.fromRGB(25, 28, 36), accent = Color3.fromRGB(255, 190, 60),
		trail = Color3.fromRGB(255, 210, 120),
		model = { barrel = 5.0, thick = 0.48, tank = 1.0 },
	},

	-- ------------------------------ ARMES LOURDES ------------------------
	{
		id = "torrent_minigun", name = "Minigun Torrent", category = "Heavy",
		rarity = "Epic", price = 4200,
		desc = "Un mur d'eau continu. Lourd, mais rien ne lui resiste de face.",
		color = Color3.fromRGB(70, 75, 85), accent = Color3.fromRGB(255, 160, 60),
	},
	{
		id = "fire_hose", name = "Lance a Incendie", category = "Heavy",
		rarity = "Rare", price = 2700,
		desc = "Jet continu qui repousse : degats faibles mais ininterrompus.",
		damage = 7, fireRate = 20, tankSize = 300, tankCost = 2, reloadTime = 3.6,
		speed = 150, gravity = 0.9, lifetime = 1.0, spread = 3.0,
		slow = 0.3, slowTime = 0.6, walkSpeedMul = 0.9,
		color = Color3.fromRGB(220, 60, 50), accent = Color3.fromRGB(255, 230, 200),
		model = { barrel = 2.6, thick = 0.7, tank = 1.8 },
	},
	{
		id = "pressure_cannon", name = "Canon a Pression", category = "Heavy",
		rarity = "Legendary", price = 5600,
		desc = "Charge une bulle geante qui explose en pluie a l'impact.",
		damage = 30, fireRate = 1.1, tankSize = 60, tankCost = 15, reloadTime = 3.8,
		speed = 175, gravity = 0.5, lifetime = 2.5, spread = 0.4, radius = 1.2,
		splashRadius = 16, splashDamage = 55, chargeTime = 1.1, chargeBonus = 1.6,
		walkSpeedMul = 0.82,
		color = Color3.fromRGB(40, 60, 90), accent = Color3.fromRGB(120, 255, 230),
		trail = Color3.fromRGB(150, 255, 240),
		model = { barrel = 3.6, thick = 1.0, tank = 2.0 },
	},

	-- -------------------------------- LANCEURS ---------------------------
	{
		id = "balloon_launcher", name = "Lance-Ballons", category = "Launcher",
		rarity = "Common", price = 1300,
		desc = "Envoie des ballons d'eau en cloche. Ideal derriere un mur.",
		color = Color3.fromRGB(255, 100, 140), accent = Color3.fromRGB(255, 235, 245),
	},
	{
		id = "bucket_bomb", name = "Bombe-Seau", category = "Launcher",
		rarity = "Rare", price = 2400,
		desc = "Un seau piege qui inonde toute la zone d'impact.",
		damage = 22, splashRadius = 17, splashDamage = 62, fireRate = 0.7,
		speed = 95, gravity = 1.9, tankSize = 18, tankCost = 6, reloadTime = 3.2,
		color = Color3.fromRGB(150, 90, 40), accent = Color3.fromRGB(230, 200, 150),
	},
	{
		id = "geyser_mortar", name = "Mortier Geyser", category = "Launcher",
		rarity = "Legendary", price = 6000,
		desc = "Tir en cloche tres haut : un geyser jaillit au point de chute.",
		damage = 20, splashRadius = 22, splashDamage = 70, fireRate = 0.5,
		speed = 130, gravity = 2.4, lifetime = 6, tankSize = 12, tankCost = 4,
		reloadTime = 4.0, radius = 1.0, walkSpeedMul = 0.88,
		color = Color3.fromRGB(60, 70, 60), accent = Color3.fromRGB(140, 255, 180),
		trail = Color3.fromRGB(160, 255, 200),
		model = { barrel = 3.4, thick = 1.1, tank = 1.4 },
	},

	-- ------------------------------- SPECIALES ---------------------------
	{
		id = "frost_ray", name = "Rayon Glace", category = "Special",
		rarity = "Legendary", price = 6500,
		desc = "De l'eau glacee qui ralentit fortement les adversaires touches.",
		damage = 9, fireRate = 9, speed = 260, gravity = 0.1,
		slow = 0.55, slowTime = 2.0, tankSize = 140, tankCost = 3, reloadTime = 2.6,
		color = Color3.fromRGB(180, 240, 255), accent = Color3.fromRGB(40, 90, 120),
		trail = Color3.fromRGB(210, 250, 255),
	},
	{
		id = "rainbow_sprayer", name = "Pulverisateur Arc-en-Ciel", category = "Special",
		rarity = "Epic", price = 3900,
		desc = "Blesse les adversaires et soigne les coequipiers touches.",
		damage = 11, fireRate = 8, heal = 9, tankSize = 130, tankCost = 3,
		splashRadius = 4, splashDamage = 4,
		color = Color3.fromRGB(255, 120, 255), accent = Color3.fromRGB(255, 255, 160),
		trail = Color3.fromRGB(255, 180, 255),
	},
	{
		id = "steam_vent", name = "Souffleur de Vapeur", category = "Special",
		rarity = "Rare", price = 2300,
		desc = "Cone de vapeur brulante, redoutable au corps a corps.",
		damage = 6, fireRate = 14, pellets = 3, spread = 11, speed = 95,
		gravity = 0.15, lifetime = 0.35, tankSize = 180, tankCost = 3,
		reloadTime = 2.4, radius = 0.55, walkSpeedMul = 1.04,
		color = Color3.fromRGB(200, 205, 215), accent = Color3.fromRGB(255, 120, 60),
		trail = Color3.fromRGB(240, 240, 240),
		model = { barrel = 1.8, thick = 0.75, tank = 1.4 },
	},
}

-- ------------------------- CONSTRUCTION DU CATALOGUE ----------------------

local function merge(target, source)
	for key, value in pairs(source) do
		if target[key] == nil then
			target[key] = value
		end
	end
end

Weapons.List = {}
Weapons.ById = {}

for index, raw in ipairs(RAW) do
	local weapon = table.clone(raw)
	local categoryDefaults = CATEGORY_DEFAULTS[raw.category]
	assert(categoryDefaults, "Categorie inconnue pour l'arme " .. tostring(raw.id))

	-- Le modele est un sous-tableau : on le fusionne separement.
	local model = table.clone(weapon.model or {})
	merge(model, categoryDefaults.model)
	merge(model, { barrel = 2.2, thick = 0.5, tank = 1.0 })
	weapon.model = model

	merge(weapon, categoryDefaults)
	merge(weapon, BASE)

	weapon.order = index
	weapon.rarityColor = RARITY[weapon.rarity].color
	weapon.rarityName = RARITY[weapon.rarity].name
	-- Degats theoriques par seconde, affiches dans la boutique.
	weapon.dps = math.floor(weapon.damage * weapon.pellets * weapon.fireRate * weapon.burst + 0.5)

	assert(Weapons.ById[weapon.id] == nil, "Identifiant d'arme duplique : " .. weapon.id)
	Weapons.ById[weapon.id] = weapon
	table.insert(Weapons.List, weapon)
end

-- Armes possedees des la premiere connexion.
Weapons.StarterIds = { "squirt_pistol", "stream_rifle" }
Weapons.DefaultPrimary = "stream_rifle"
Weapons.DefaultSecondary = "squirt_pistol"

function Weapons.Get(id)
	return Weapons.ById[id]
end

function Weapons.Exists(id)
	return Weapons.ById[id] ~= nil
end

function Weapons.IsStarter(id)
	return table.find(Weapons.StarterIds, id) ~= nil
end

function Weapons.ByCategory(category)
	local result = {}
	for _, weapon in ipairs(Weapons.List) do
		if weapon.category == category then
			table.insert(result, weapon)
		end
	end
	return result
end

Weapons.Count = #Weapons.List

return Weapons
