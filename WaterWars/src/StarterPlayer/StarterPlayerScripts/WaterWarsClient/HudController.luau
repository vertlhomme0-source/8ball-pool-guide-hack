--[[
	HudController
	Interface de jeu : vie, endurance, reservoir d'eau, viseur dynamique,
	chronometre, scores d'equipe, journal des eliminations, notifications,
	indicateurs de bonus et ecran de reapparition.

	Tout est construit en code, sans aucune image : le HUD s'affiche donc
	correctement des la premiere execution, sans asset a importer.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local WaterWars = ReplicatedStorage:WaitForChild("WaterWars")
local Config = WaterWars:WaitForChild("Config")
local Shared = WaterWars:WaitForChild("Shared")

local GameConfig = require(Config:WaitForChild("GameConfig"))
local Net = require(Shared:WaitForChild("Net"))
local Util = require(Shared:WaitForChild("Util"))

local ClientState = require(script.Parent:WaitForChild("ClientState"))
local UIKit = require(script.Parent:WaitForChild("UIKit"))
local WeaponController = require(script.Parent:WaitForChild("WeaponController"))

local HudController = {}

local Theme = UIKit.Theme
local localPlayer = Players.LocalPlayer

-- Références vers les éléments d'interface, remplies à la construction.
local ui: { [string]: any } = {}
local killFeedEntries = {}
local notifications = {}
local hitMarkerUntil = 0
local damageFlashUntil = 0
local crosshairSpread = 0
local respawnAt = 0

local NOTIFICATION_COLORS = {
	good = Theme.Good,
	bad = Theme.Bad,
	info = Theme.Accent,
}

-- ----------------------------------------------------------- construction

local function buildTopBar(screen)
	local bar = UIKit.Panel(screen, UDim2.fromOffset(430, 74), UDim2.new(0.5, 0, 0, 12), Vector2.new(0.5, 0))
	ui.topBar = bar

	ui.timer = UIKit.Label(bar, "0:00", UDim2.fromOffset(150, 40), UDim2.new(0.5, 0, 0, 4), {
		anchor = Vector2.new(0.5, 0),
		align = Enum.TextXAlignment.Center,
		font = Theme.FontBold,
		textSize = 34,
	})
	ui.modeLabel = UIKit.Label(bar, "", UDim2.fromOffset(410, 20), UDim2.new(0.5, 0, 0, 46), {
		anchor = Vector2.new(0.5, 0),
		align = Enum.TextXAlignment.Center,
		color = Theme.TextDim,
		textSize = 14,
	})

	ui.scoreBlue = UIKit.Label(bar, "0", UDim2.fromOffset(90, 46), UDim2.new(0, 10, 0, 6), {
		align = Enum.TextXAlignment.Center,
		font = Theme.FontBold,
		textSize = 30,
		color = GameConfig.Teams[1].color,
	})
	ui.scoreRed = UIKit.Label(bar, "0", UDim2.fromOffset(90, 46), UDim2.new(1, -100, 0, 6), {
		align = Enum.TextXAlignment.Center,
		font = Theme.FontBold,
		textSize = 30,
		color = GameConfig.Teams[2].color,
	})
end

local function buildVitals(screen)
	local panel = UIKit.Panel(screen, UDim2.fromOffset(300, 96), UDim2.new(0, 18, 1, -18), Vector2.new(0, 1))
	ui.vitals = panel

	UIKit.Label(panel, "SOAK", UDim2.fromOffset(60, 16), UDim2.fromOffset(12, 8), {
		color = Theme.TextDim, textSize = 12, font = Theme.FontBold,
	})
	ui.healthText = UIKit.Label(panel, "100", UDim2.fromOffset(70, 16), UDim2.new(1, -82, 0, 8), {
		color = Theme.TextDim, textSize = 12, align = Enum.TextXAlignment.Right, font = Theme.FontBold,
	})
	local _, healthFill = UIKit.Bar(panel, UDim2.new(1, -24, 0, 18), UDim2.fromOffset(12, 26), Theme.Good)
	ui.healthFill = healthFill

	UIKit.Label(panel, "ENDURANCE", UDim2.fromOffset(110, 14), UDim2.fromOffset(12, 50), {
		color = Theme.TextDim, textSize = 11, font = Theme.FontBold,
	})
	local _, staminaFill = UIKit.Bar(panel, UDim2.new(1, -24, 0, 10), UDim2.fromOffset(12, 66), Theme.Warn, { radius = 4 })
	ui.staminaFill = staminaFill

	ui.effects = Instance.new("Frame")
	ui.effects.Size = UDim2.fromOffset(300, 28)
	ui.effects.Position = UDim2.new(0, 18, 1, -124)
	ui.effects.AnchorPoint = Vector2.new(0, 1)
	ui.effects.BackgroundTransparency = 1
	ui.effects.Parent = screen
	UIKit.ListLayout(ui.effects, 6, Enum.FillDirection.Horizontal)
end

local function buildWeaponPanel(screen)
	local panel = UIKit.Panel(screen, UDim2.fromOffset(300, 96), UDim2.new(1, -18, 1, -18), Vector2.new(1, 1))
	ui.weaponPanel = panel

	ui.weaponName = UIKit.Label(panel, "Aucune arme", UDim2.new(1, -24, 0, 22), UDim2.fromOffset(12, 8), {
		font = Theme.FontBold, textSize = 18, align = Enum.TextXAlignment.Right,
	})
	ui.weaponCategory = UIKit.Label(panel, "", UDim2.new(1, -24, 0, 14), UDim2.fromOffset(12, 30), {
		color = Theme.TextDim, textSize = 12, align = Enum.TextXAlignment.Right,
	})
	local _, waterFill = UIKit.Bar(panel, UDim2.new(1, -24, 0, 16), UDim2.fromOffset(12, 50), Theme.Accent)
	ui.waterFill = waterFill
	ui.ammoText = UIKit.Label(panel, "0 / 0", UDim2.new(1, -24, 0, 18), UDim2.fromOffset(12, 70), {
		color = Theme.TextDim, textSize = 14, align = Enum.TextXAlignment.Right, font = Theme.FontBold,
	})
end

local function buildCrosshair(screen)
	local holder = Instance.new("Frame")
	holder.Name = "Crosshair"
	holder.Size = UDim2.fromOffset(120, 120)
	holder.Position = UDim2.fromScale(0.5, 0.5)
	holder.AnchorPoint = Vector2.new(0.5, 0.5)
	holder.BackgroundTransparency = 1
	holder.Parent = screen
	ui.crosshair = holder

	ui.crossLines = {}
	local directions = {
		{ anchor = Vector2.new(0.5, 1), pos = UDim2.new(0.5, 0, 0.5, 0), size = UDim2.fromOffset(2, 10), axis = "y", sign = -1 },
		{ anchor = Vector2.new(0.5, 0), pos = UDim2.new(0.5, 0, 0.5, 0), size = UDim2.fromOffset(2, 10), axis = "y", sign = 1 },
		{ anchor = Vector2.new(1, 0.5), pos = UDim2.new(0.5, 0, 0.5, 0), size = UDim2.fromOffset(10, 2), axis = "x", sign = -1 },
		{ anchor = Vector2.new(0, 0.5), pos = UDim2.new(0.5, 0, 0.5, 0), size = UDim2.fromOffset(10, 2), axis = "x", sign = 1 },
	}
	for _, definition in ipairs(directions) do
		local line = Instance.new("Frame")
		line.Size = definition.size
		line.AnchorPoint = definition.anchor
		line.Position = definition.pos
		line.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
		line.BorderSizePixel = 0
		line.Parent = holder
		table.insert(ui.crossLines, { frame = line, axis = definition.axis, sign = definition.sign })
	end

	local dot = Instance.new("Frame")
	dot.Size = UDim2.fromOffset(2, 2)
	dot.AnchorPoint = Vector2.new(0.5, 0.5)
	dot.Position = UDim2.fromScale(0.5, 0.5)
	dot.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	dot.BorderSizePixel = 0
	dot.Parent = holder

	-- Marqueur de touche : quatre traits en croix qui apparaissent brievement.
	ui.hitMarker = Instance.new("Frame")
	ui.hitMarker.Size = UDim2.fromOffset(28, 28)
	ui.hitMarker.AnchorPoint = Vector2.new(0.5, 0.5)
	ui.hitMarker.Position = UDim2.fromScale(0.5, 0.5)
	ui.hitMarker.BackgroundTransparency = 1
	ui.hitMarker.Visible = false
	ui.hitMarker.Parent = holder
	for _, rotation in ipairs({ 45, 135, 225, 315 }) do
		local tick = Instance.new("Frame")
		tick.Size = UDim2.fromOffset(2, 9)
		tick.AnchorPoint = Vector2.new(0.5, 0.5)
		tick.Position = UDim2.new(0.5, math.cos(math.rad(rotation)) * 11, 0.5, math.sin(math.rad(rotation)) * 11)
		tick.Rotation = rotation + 90
		tick.BackgroundColor3 = Color3.fromRGB(255, 90, 90)
		tick.BorderSizePixel = 0
		tick.Parent = ui.hitMarker
	end

	-- Barre de charge des armes a charge.
	local chargeBack = Instance.new("Frame")
	chargeBack.Size = UDim2.fromOffset(120, 6)
	chargeBack.AnchorPoint = Vector2.new(0.5, 0)
	chargeBack.Position = UDim2.new(0.5, 0, 0.5, 40)
	chargeBack.BackgroundColor3 = Color3.fromRGB(10, 14, 20)
	chargeBack.BackgroundTransparency = 0.3
	chargeBack.BorderSizePixel = 0
	chargeBack.Visible = false
	chargeBack.Parent = screen
	UIKit.Corner(chargeBack, 3)
	local chargeFill = Instance.new("Frame")
	chargeFill.Size = UDim2.fromScale(0, 1)
	chargeFill.BackgroundColor3 = Theme.Warn
	chargeFill.BorderSizePixel = 0
	chargeFill.Parent = chargeBack
	UIKit.Corner(chargeFill, 3)
	ui.chargeBack = chargeBack
	ui.chargeFill = chargeFill
end

local function buildFeeds(screen)
	ui.killFeed = Instance.new("Frame")
	ui.killFeed.Size = UDim2.fromOffset(360, 200)
	ui.killFeed.Position = UDim2.new(1, -18, 0, 100)
	ui.killFeed.AnchorPoint = Vector2.new(1, 0)
	ui.killFeed.BackgroundTransparency = 1
	ui.killFeed.Parent = screen
	local layout = UIKit.ListLayout(ui.killFeed, 4)
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Right

	ui.notifications = Instance.new("Frame")
	ui.notifications.Size = UDim2.fromOffset(460, 160)
	ui.notifications.Position = UDim2.new(0.5, 0, 0, 100)
	ui.notifications.AnchorPoint = Vector2.new(0.5, 0)
	ui.notifications.BackgroundTransparency = 1
	ui.notifications.Parent = screen
	local notificationLayout = UIKit.ListLayout(ui.notifications, 6)
	notificationLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center

	-- Vignette rouge quand on prend des degats.
	ui.damageFlash = Instance.new("Frame")
	ui.damageFlash.Size = UDim2.fromScale(1, 1)
	ui.damageFlash.BackgroundColor3 = Color3.fromRGB(180, 20, 30)
	ui.damageFlash.BackgroundTransparency = 1
	ui.damageFlash.BorderSizePixel = 0
	ui.damageFlash.ZIndex = 0
	ui.damageFlash.Parent = screen
end

local function buildOverlay(screen)
	ui.overlay = Instance.new("Frame")
	ui.overlay.Size = UDim2.fromScale(1, 1)
	ui.overlay.BackgroundColor3 = Color3.fromRGB(4, 8, 14)
	ui.overlay.BackgroundTransparency = 0.45
	ui.overlay.BorderSizePixel = 0
	ui.overlay.Visible = false
	ui.overlay.ZIndex = 5
	ui.overlay.Parent = screen

	ui.overlayTitle = UIKit.Label(ui.overlay, "", UDim2.new(1, 0, 0, 56), UDim2.new(0.5, 0, 0.42, 0), {
		anchor = Vector2.new(0.5, 0.5),
		align = Enum.TextXAlignment.Center,
		font = Theme.FontBold,
		textSize = 46,
	})
	ui.overlayTitle.ZIndex = 6
	ui.overlaySubtitle = UIKit.Label(ui.overlay, "", UDim2.new(1, 0, 0, 30), UDim2.new(0.5, 0, 0.42, 42), {
		anchor = Vector2.new(0.5, 0.5),
		align = Enum.TextXAlignment.Center,
		color = Theme.TextDim,
		textSize = 20,
	})
	ui.overlaySubtitle.ZIndex = 6
end

-- ----------------------------------------------------------- alimentation

local function pushNotification(message, kind)
	if type(message) ~= "string" or #message == 0 then
		return
	end
	local label = UIKit.Label(ui.notifications, message, UDim2.fromOffset(460, 26), nil, {
		align = Enum.TextXAlignment.Center,
		color = NOTIFICATION_COLORS[kind] or Theme.Text,
		font = Theme.FontBold,
		textSize = 18,
		stroke = true,
	})
	label.LayoutOrder = -math.floor(os.clock() * 100)
	table.insert(notifications, label)
	if #notifications > 5 then
		local oldest = table.remove(notifications, 1)
		if oldest then
			oldest:Destroy()
		end
	end
	task.delay(4, function()
		if label.Parent then
			TweenService:Create(label, TweenInfo.new(0.5), { TextTransparency = 1 }):Play()
			task.wait(0.5)
			local index = table.find(notifications, label)
			if index then
				table.remove(notifications, index)
			end
			label:Destroy()
		end
	end)
end

local function teamColor(teamId)
	for _, definition in ipairs(GameConfig.Teams) do
		if definition.id == teamId then
			return definition.color
		end
	end
	return Theme.Text
end

local function pushKillFeed(entry)
	if type(entry) ~= "table" then
		return
	end
	local killerText = entry.killer or "L'environnement"
	local weaponText = entry.weapon and (" [" .. entry.weapon .. "] ") or " a trempe "
	local frame = Instance.new("Frame")
	frame.Size = UDim2.fromOffset(360, 24)
	frame.BackgroundColor3 = Theme.Panel
	frame.BackgroundTransparency = 0.3
	frame.BorderSizePixel = 0
	frame.LayoutOrder = -math.floor(os.clock() * 100)
	frame.Parent = ui.killFeed
	UIKit.Corner(frame, 6)

	local label = UIKit.Label(frame, "", UDim2.new(1, -16, 1, 0), UDim2.fromOffset(8, 0), {
		align = Enum.TextXAlignment.Right,
		textSize = 14,
		richText = true,
	})
	local killerColor = teamColor(entry.killerTeam)
	local victimColor = teamColor(entry.victimTeam)
	label.Text = string.format(
		'<font color="#%s">%s</font>%s<font color="#%s">%s</font>',
		killerColor:ToHex(),
		killerText,
		weaponText,
		victimColor:ToHex(),
		entry.victim or "?"
	)

	table.insert(killFeedEntries, frame)
	if #killFeedEntries > 6 then
		local oldest = table.remove(killFeedEntries, 1)
		if oldest then
			oldest:Destroy()
		end
	end
	task.delay(7, function()
		local index = table.find(killFeedEntries, frame)
		if index then
			table.remove(killFeedEntries, index)
		end
		if frame.Parent then
			frame:Destroy()
		end
	end)
end

local function refreshMatch()
	local match = ClientState.match
	ui.timer.Text = Util.FormatTime(match.timeLeft or 0)
	ui.scoreBlue.Text = tostring((match.scores and match.scores.Blue) or 0)
	ui.scoreRed.Text = tostring((match.scores and match.scores.Red) or 0)

	local teamBased = match.mode and match.mode.teamBased
	ui.scoreBlue.Visible = teamBased == true
	ui.scoreRed.Visible = teamBased == true

	local pieces = {}
	if match.mode then
		table.insert(pieces, match.mode.name)
	end
	if match.map then
		table.insert(pieces, match.map.name)
	end
	ui.modeLabel.Text = table.concat(pieces, "  -  ")

	-- Bandeau plein ecran entre les manches.
	local state = match.state
	if state == "Active" then
		ui.overlay.Visible = false
	elseif state == "Waiting" then
		ui.overlay.Visible = true
		ui.overlayTitle.Text = "En attente de joueurs"
		ui.overlaySubtitle.Text = string.format(
			"%d / %d joueurs connectes",
			match.playerCount or 0,
			match.minPlayers or 1
		)
	elseif state == "Vote" then
		ui.overlay.Visible = false
	elseif state == "Loading" then
		ui.overlay.Visible = true
		ui.overlayTitle.Text = "Chargement du terrain"
		ui.overlaySubtitle.Text = match.map and match.map.name or ""
	elseif state == "Results" then
		ui.overlay.Visible = true
		local result = match.result
		ui.overlayTitle.Text = result and result.message or "Manche terminee"
		ui.overlaySubtitle.Text = result
			and string.format("%s  -  %d contre %d", result.mapName or "", result.scores.Blue, result.scores.Red)
			or ""
	end
end

local function refreshAmmo()
	local ammo = ClientState.ammo
	local weapon = ClientState.GetEquippedWeapon()
	if weapon then
		ui.weaponName.Text = weapon.name
		ui.weaponCategory.Text = string.format("%s  -  %s", weapon.rarityName, weapon.desc)
		ui.weaponName.TextColor3 = weapon.rarityColor
	else
		ui.weaponName.Text = "Aucune arme"
		ui.weaponCategory.Text = ""
		ui.weaponName.TextColor3 = Theme.TextDim
	end

	local ratio = 0
	if ammo.max > 0 then
		ratio = ammo.current / ammo.max
	end
	ui.waterFill.Size = UDim2.fromScale(math.clamp(ratio, 0, 1), 1)
	ui.waterFill.BackgroundColor3 = ratio < 0.25 and Theme.Bad or Theme.Accent
	if ammo.reloading then
		ui.ammoText.Text = "RECHARGEMENT..."
		ui.ammoText.TextColor3 = Theme.Warn
	else
		ui.ammoText.Text = string.format("%d / %d", math.floor(ammo.current), math.floor(ammo.max))
		ui.ammoText.TextColor3 = Theme.TextDim
	end
end

local function refreshEffects()
	for _, child in ipairs(ui.effects:GetChildren()) do
		if child:IsA("TextLabel") then
			child:Destroy()
		end
	end
	local character = localPlayer.Character
	if not character then
		return
	end
	local now = os.clock()
	local badges = {
		{ attribute = "SpeedBoostUntil", name = "TURBO", color = Color3.fromRGB(255, 225, 60) },
		{ attribute = "DamageBoostUntil", name = "PRESSION", color = Color3.fromRGB(255, 130, 60) },
		{ attribute = "ShieldUntil", name = "BOUCLIER", color = Color3.fromRGB(120, 230, 255) },
		{ attribute = "ProtectedUntil", name = "PROTEGE", color = Color3.fromRGB(160, 255, 170) },
		{ attribute = "SlowUntil", name = "GELE", color = Color3.fromRGB(150, 200, 255) },
	}
	for index, badge in ipairs(badges) do
		local value = character:GetAttribute(badge.attribute)
		if type(value) == "number" and value > now then
			local label = UIKit.Label(ui.effects, string.format("%s %.0fs", badge.name, value - now), UDim2.fromOffset(104, 24), nil, {
				align = Enum.TextXAlignment.Center,
				color = badge.color,
				font = Theme.FontBold,
				textSize = 13,
				backgroundTransparency = 0.25,
				backgroundColor = Theme.Panel,
				layoutOrder = index,
			})
			UIKit.Corner(label, 6)
		end
	end
end

local function updatePerFrame(deltaTime)
	local character = localPlayer.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")

	-- Vie
	local healthRatio = 0
	if humanoid and humanoid.MaxHealth > 0 then
		healthRatio = humanoid.Health / humanoid.MaxHealth
	end
	ui.healthFill.Size = UDim2.fromScale(math.clamp(healthRatio, 0, 1), 1)
	ui.healthFill.BackgroundColor3 = healthRatio > 0.5 and Theme.Good
		or (healthRatio > 0.25 and Theme.Warn or Theme.Bad)
	ui.healthText.Text = tostring(math.max(0, math.floor((humanoid and humanoid.Health or 0) + 0.5)))

	-- Endurance
	local stamina = character and character:GetAttribute("Stamina")
	local staminaRatio = type(stamina) == "number" and stamina / GameConfig.StaminaMax or 1
	ui.staminaFill.Size = UDim2.fromScale(math.clamp(staminaRatio, 0, 1), 1)

	-- Viseur : s'ouvre quand on bouge et selon la dispersion de l'arme.
	local weapon = ClientState.GetEquippedWeapon()
	local baseGap = 6
	if weapon then
		baseGap = 5 + weapon.spread * 1.6
	end
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local speed = root and (root :: BasePart).AssemblyLinearVelocity.Magnitude or 0
	local target = baseGap + math.min(18, speed * 0.45)
	if WeaponController.IsAiming() then
		target = target * 0.55
	end
	crosshairSpread = crosshairSpread + (target - crosshairSpread) * math.min(1, deltaTime * 10)
	for _, line in ipairs(ui.crossLines) do
		if line.axis == "y" then
			line.frame.Position = UDim2.new(0.5, 0, 0.5, line.sign * crosshairSpread)
		else
			line.frame.Position = UDim2.new(0.5, line.sign * crosshairSpread, 0.5, 0)
		end
	end
	ui.crosshair.Visible = humanoid ~= nil and humanoid.Health > 0

	-- Charge
	local charge = WeaponController.GetCharge()
	ui.chargeBack.Visible = charge > 0.02
	ui.chargeFill.Size = UDim2.fromScale(charge, 1)
	ui.chargeFill.BackgroundColor3 = charge >= 0.99 and Theme.Good or Theme.Warn

	-- Marqueur de touche et vignette de degats
	local now = os.clock()
	ui.hitMarker.Visible = now < hitMarkerUntil
	local flash = math.max(0, damageFlashUntil - now)
	ui.damageFlash.BackgroundTransparency = 1 - math.min(0.35, flash * 0.9)

	-- Ecran de reapparition
	if respawnAt > now and (not humanoid or humanoid.Health <= 0) then
		ui.overlay.Visible = true
		ui.overlayTitle.Text = "Vous etes trempe !"
		ui.overlaySubtitle.Text = string.format("Reapparition dans %.0f s", respawnAt - now)
	elseif respawnAt > 0 and now >= respawnAt then
		respawnAt = 0
		refreshMatch()
	end
end

function HudController.Start()
	local screen = UIKit.Screen("WaterWarsHud", 2)
	buildTopBar(screen)
	buildVitals(screen)
	buildWeaponPanel(screen)
	buildCrosshair(screen)
	buildFeeds(screen)
	buildOverlay(screen)

	ClientState.MatchChanged:Connect(refreshMatch)
	ClientState.AmmoChanged:Connect(refreshAmmo)
	refreshMatch()
	refreshAmmo()

	Net.Event("MatchState").OnClientEvent:Connect(ClientState.SetMatch)
	Net.Event("Scoreboard").OnClientEvent:Connect(ClientState.SetScoreboard)
	Net.Event("ProfileUpdate").OnClientEvent:Connect(ClientState.SetProfile)
	Net.Event("MapVote").OnClientEvent:Connect(ClientState.SetVote)
	Net.Event("Notify").OnClientEvent:Connect(pushNotification)
	Net.Event("KillFeed").OnClientEvent:Connect(pushKillFeed)

	Net.Event("HitMarker").OnClientEvent:Connect(function(_damage, killed)
		hitMarkerUntil = os.clock() + (killed and 0.35 or 0.16)
	end)

	Net.Event("Damaged").OnClientEvent:Connect(function()
		damageFlashUntil = os.clock() + 0.4
	end)

	Net.Event("MapReady").OnClientEvent:Connect(function(map)
		if type(map) == "table" and map.name then
			pushNotification(string.format("%s - %s", map.name, map.theme or ""), "info")
		end
	end)

	-- Detecte la mort pour afficher le compte a rebours de reapparition.
	local function watchCharacter(character)
		local humanoid = character:WaitForChild("Humanoid", 10)
		if humanoid and humanoid:IsA("Humanoid") then
			humanoid.Died:Connect(function()
				respawnAt = os.clock() + GameConfig.RespawnTime
			end)
		end
		-- Le changement d'arme met le panneau a jour.
		character.ChildAdded:Connect(function(child)
			if child:IsA("Tool") then
				task.defer(refreshAmmo)
			end
		end)
		character.ChildRemoved:Connect(function(child)
			if child:IsA("Tool") then
				task.defer(refreshAmmo)
			end
		end)
	end

	if localPlayer.Character then
		task.spawn(watchCharacter, localPlayer.Character)
	end
	localPlayer.CharacterAdded:Connect(function(character)
		respawnAt = 0
		task.spawn(watchCharacter, character)
	end)

	local effectAccumulator = 0
	RunService.RenderStepped:Connect(function(deltaTime)
		local ok, err = pcall(updatePerFrame, math.min(deltaTime, 0.1))
		if not ok then
			warn("[WaterWars] Erreur du HUD : " .. tostring(err))
		end
		effectAccumulator = effectAccumulator + deltaTime
		if effectAccumulator >= 0.4 then
			effectAccumulator = 0
			pcall(refreshEffects)
		end
	end)

	-- Le chronometre descend entre deux messages du serveur.
	task.spawn(function()
		while true do
			task.wait(0.25)
			local match = ClientState.match
			if type(match.timeLeft) == "number" and match.timeLeft > 0 then
				match.timeLeft = math.max(0, match.timeLeft - 0.25)
				ui.timer.Text = Util.FormatTime(match.timeLeft)
			end
		end
	end)
end

return HudController
