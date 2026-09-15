--[[
	ShopController
	Boutique et vestiaire : parcourir les 25 armes par categorie, consulter
	leurs statistiques, les acheter avec les pieces gagnees en jeu, puis les
	equiper en arme principale ou secondaire.

	Touche par defaut : B (voir GameConfig.Keys.Shop).
]]

local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local WaterWars = ReplicatedStorage:WaitForChild("WaterWars")
local Config = WaterWars:WaitForChild("Config")
local Shared = WaterWars:WaitForChild("Shared")

local GameConfig = require(Config:WaitForChild("GameConfig"))
local Weapons = require(Config:WaitForChild("Weapons"))
local Net = require(Shared:WaitForChild("Net"))
local Util = require(Shared:WaitForChild("Util"))

local ClientState = require(script.Parent:WaitForChild("ClientState"))
local UIKit = require(script.Parent:WaitForChild("UIKit"))

local ShopController = {}

local Theme = UIKit.Theme

local screen = nil
local root = nil
local isOpen = false
local selectedCategory = Weapons.CategoryOrder[1]
local selectedWeapon = nil

-- Références vers les éléments d'interface, remplies à la construction.
local ui: { [string]: any } = {}
local categoryButtons = {}
local weaponButtons = {}

-- Bornes utilisees pour dessiner les barres de statistiques.
local STAT_RANGES = {
	{ key = "damage", label = "Degats", max = 60 },
	{ key = "fireRate", label = "Cadence", max = 20 },
	{ key = "dps", label = "Degats / s", max = 220 },
	{ key = "tankSize", label = "Reservoir", max = 300 },
	{ key = "speed", label = "Vitesse", max = 520 },
	{ key = "reloadTime", label = "Rechargement", max = 4.5, invert = true },
}

local function isOwned(weaponId)
	return ClientState.profile.owned[weaponId] == true
end

local function equippedSlot(weaponId)
	local loadout = ClientState.profile.loadout
	if loadout.primary == weaponId then
		return "primary"
	elseif loadout.secondary == weaponId then
		return "secondary"
	end
	return nil
end

-- ----------------------------------------------------------- construction

local function buildStatRow(parent, definition, order)
	local holder = Instance.new("Frame")
	holder.Size = UDim2.new(1, 0, 0, 30)
	holder.BackgroundTransparency = 1
	holder.LayoutOrder = order
	holder.Parent = parent

	UIKit.Label(holder, definition.label, UDim2.fromOffset(120, 14), UDim2.fromOffset(0, 0), {
		color = Theme.TextDim, textSize = 12,
	})
	local valueLabel = UIKit.Label(holder, "", UDim2.fromOffset(90, 14), UDim2.new(1, -90, 0, 0), {
		color = Theme.Text, textSize = 12, align = Enum.TextXAlignment.Right, font = Theme.FontBold,
	})
	local _, fill = UIKit.Bar(holder, UDim2.new(1, 0, 0, 8), UDim2.fromOffset(0, 18), Theme.Accent, { radius = 4 })
	return { value = valueLabel, fill = fill }
end

local function buildDetails(parent)
	local panel = Instance.new("Frame")
	panel.Size = UDim2.new(0, 330, 1, -16)
	panel.Position = UDim2.new(1, -8, 0, 8)
	panel.AnchorPoint = Vector2.new(1, 0)
	panel.BackgroundColor3 = Theme.PanelLight
	panel.BackgroundTransparency = 0.25
	panel.BorderSizePixel = 0
	panel.Parent = parent
	UIKit.Corner(panel, 10)
	ui.details = panel

	ui.detailName = UIKit.Label(panel, "", UDim2.new(1, -24, 0, 26), UDim2.fromOffset(12, 12), {
		font = Theme.FontBold, textSize = 22,
	})
	ui.detailRarity = UIKit.Label(panel, "", UDim2.new(1, -24, 0, 16), UDim2.fromOffset(12, 38), {
		textSize = 13, color = Theme.TextDim,
	})
	ui.detailDesc = UIKit.Label(panel, "", UDim2.new(1, -24, 0, 54), UDim2.fromOffset(12, 58), {
		textSize = 13, color = Theme.TextDim, alignY = Enum.TextYAlignment.Top,
	})
	ui.detailDesc.TextWrapped = true

	local stats = Instance.new("Frame")
	stats.Size = UDim2.new(1, -24, 0, 190)
	stats.Position = UDim2.fromOffset(12, 116)
	stats.BackgroundTransparency = 1
	stats.Parent = panel
	UIKit.ListLayout(stats, 4)

	ui.statRows = {}
	for index, definition in ipairs(STAT_RANGES) do
		ui.statRows[definition.key] = buildStatRow(stats, definition, index)
	end

	ui.buyButton = UIKit.Button(panel, "ACHETER", UDim2.new(1, -24, 0, 38), UDim2.new(0, 12, 1, -100), {
		color = Theme.AccentDark, textSize = 16,
	})
	ui.equipPrimary = UIKit.Button(panel, "PRINCIPALE", UDim2.new(0.5, -16, 0, 34), UDim2.new(0, 12, 1, -56), {
		color = Theme.Panel, textSize = 14,
	})
	ui.equipSecondary = UIKit.Button(panel, "SECONDAIRE", UDim2.new(0.5, -16, 0, 34), UDim2.new(1, -12, 1, -56), {
		anchor = Vector2.new(1, 0), color = Theme.Panel, textSize = 14,
	})
end

local function refreshDetails()
	local weapon = selectedWeapon
	if not weapon then
		ui.details.Visible = false
		return
	end
	ui.details.Visible = true
	ui.detailName.Text = weapon.name
	ui.detailName.TextColor3 = weapon.rarityColor
	ui.detailRarity.Text = string.format(
		"%s  -  %s",
		weapon.rarityName,
		Weapons.CategoryNames[weapon.category] or weapon.category
	)
	ui.detailDesc.Text = weapon.desc

	for _, definition in ipairs(STAT_RANGES) do
		local row = ui.statRows[definition.key]
		local value = weapon[definition.key] or 0
		local ratio = math.clamp(value / definition.max, 0, 1)
		if definition.invert then
			ratio = 1 - ratio
		end
		row.fill.Size = UDim2.fromScale(math.max(0.03, ratio), 1)
		row.fill.BackgroundColor3 = ratio > 0.66 and Theme.Good or (ratio > 0.33 and Theme.Warn or Theme.Bad)
		if definition.key == "reloadTime" then
			row.value.Text = string.format("%.1f s", value)
		elseif definition.key == "fireRate" then
			row.value.Text = string.format("%.1f /s", value)
		else
			row.value.Text = Util.FormatNumber(value)
		end
	end

	local owned = isOwned(weapon.id)
	local slot = equippedSlot(weapon.id)

	if owned then
		ui.buyButton.Text = "DEJA DEBLOQUEE"
		ui.buyButton.BackgroundColor3 = Theme.Panel
		ui.buyButton.TextColor3 = Theme.TextDim
	else
		local affordable = ClientState.profile.coins >= weapon.price
		ui.buyButton.Text = string.format("ACHETER  -  %s pieces", Util.FormatNumber(weapon.price))
		ui.buyButton.BackgroundColor3 = affordable and Theme.AccentDark or Theme.Panel
		ui.buyButton.TextColor3 = affordable and Theme.Text or Theme.Bad
	end

	ui.equipPrimary.Visible = owned
	ui.equipSecondary.Visible = owned
	ui.equipPrimary.BackgroundColor3 = slot == "primary" and Theme.AccentDark or Theme.Panel
	ui.equipSecondary.BackgroundColor3 = slot == "secondary" and Theme.AccentDark or Theme.Panel
	ui.equipPrimary.Text = slot == "primary" and "PRINCIPALE OK" or "PRINCIPALE"
	ui.equipSecondary.Text = slot == "secondary" and "SECONDAIRE OK" or "SECONDAIRE"
end

local function refreshWeaponList()
	for _, button in ipairs(weaponButtons) do
		button:Destroy()
	end
	table.clear(weaponButtons)

	local list = Weapons.ByCategory(selectedCategory)
	for index, weapon in ipairs(list) do
		local owned = isOwned(weapon.id)
		local slot = equippedSlot(weapon.id)
		local button = UIKit.Button(ui.weaponList, "", UDim2.new(1, -12, 0, 54), nil, {
			color = Theme.Panel,
			stroke = false,
			layoutOrder = index,
		})
		button.AutoButtonColor = true

		UIKit.Label(button, weapon.name, UDim2.new(1, -110, 0, 20), UDim2.fromOffset(10, 7), {
			font = Theme.FontBold, textSize = 16, color = weapon.rarityColor,
		})
		local subtitle = string.format("%d degats  -  %.1f tirs/s  -  %d DPS", weapon.damage, weapon.fireRate, weapon.dps)
		UIKit.Label(button, subtitle, UDim2.new(1, -110, 0, 16), UDim2.fromOffset(10, 28), {
			textSize = 12, color = Theme.TextDim,
		})

		local statusText, statusColor
		if slot then
			statusText = slot == "primary" and "EQUIPEE 1" or "EQUIPEE 2"
			statusColor = Theme.Good
		elseif owned then
			statusText = "POSSEDEE"
			statusColor = Theme.Accent
		else
			statusText = Util.FormatNumber(weapon.price)
			statusColor = ClientState.profile.coins >= weapon.price and Theme.Warn or Theme.Bad
		end
		UIKit.Label(button, statusText, UDim2.fromOffset(96, 20), UDim2.new(1, -104, 0, 17), {
			textSize = 13, color = statusColor, align = Enum.TextXAlignment.Right, font = Theme.FontBold,
		})

		local stripe = Instance.new("Frame")
		stripe.Size = UDim2.fromOffset(4, 54)
		stripe.Position = UDim2.fromOffset(0, 0)
		stripe.BackgroundColor3 = weapon.rarityColor
		stripe.BorderSizePixel = 0
		stripe.Parent = button

		button.Activated:Connect(function()
			selectedWeapon = weapon
			refreshDetails()
		end)

		table.insert(weaponButtons, button)
	end

	if not selectedWeapon or selectedWeapon.category ~= selectedCategory then
		selectedWeapon = list[1]
	end
	refreshDetails()
end

local function refreshCategories()
	for id, button in pairs(categoryButtons) do
		local selected = id == selectedCategory
		button.BackgroundColor3 = selected and Theme.AccentDark or Theme.Panel
		button.TextColor3 = selected and Theme.Text or Theme.TextDim
	end
end

local function refreshAll()
	ui.coins.Text = string.format("%s pieces", Util.FormatNumber(ClientState.profile.coins))
	refreshCategories()
	refreshWeaponList()
end

local function build()
	screen = UIKit.Screen("WaterWarsShop", 6)
	screen.Enabled = false

	local backdrop = Instance.new("Frame")
	backdrop.Size = UDim2.fromScale(1, 1)
	backdrop.BackgroundColor3 = Color3.fromRGB(2, 5, 10)
	backdrop.BackgroundTransparency = 0.45
	backdrop.BorderSizePixel = 0
	backdrop.Parent = screen

	root = UIKit.Panel(screen, UDim2.fromOffset(900, 540), UDim2.fromScale(0.5, 0.5), Vector2.new(0.5, 0.5))
	root.BackgroundTransparency = 0.02

	UIKit.Label(root, "ARSENAL", UDim2.fromOffset(260, 30), UDim2.fromOffset(18, 14), {
		font = Theme.FontBold, textSize = 26,
	})
	ui.coins = UIKit.Label(root, "0 pieces", UDim2.fromOffset(280, 24), UDim2.new(1, -60, 0, 18), {
		anchor = Vector2.new(1, 0), align = Enum.TextXAlignment.Right,
		font = Theme.FontBold, textSize = 18, color = Theme.Warn,
	})
	local close = UIKit.Button(root, "X", UDim2.fromOffset(34, 30), UDim2.new(1, -14, 0, 14), {
		anchor = Vector2.new(1, 0), color = Theme.Panel, textSize = 16,
	})
	close.Activated:Connect(function()
		ShopController.SetOpen(false)
	end)

	local body = Instance.new("Frame")
	body.Size = UDim2.new(1, -24, 1, -70)
	body.Position = UDim2.fromOffset(12, 58)
	body.BackgroundTransparency = 1
	body.Parent = root

	-- Colonne des categories
	local categories = Instance.new("Frame")
	categories.Size = UDim2.new(0, 150, 1, -16)
	categories.Position = UDim2.fromOffset(8, 8)
	categories.BackgroundTransparency = 1
	categories.Parent = body
	UIKit.ListLayout(categories, 6)

	for index, id in ipairs(Weapons.CategoryOrder) do
		local button = UIKit.Button(categories, Weapons.CategoryNames[id] or id, UDim2.new(1, 0, 0, 38), nil, {
			color = Theme.Panel, textSize = 13, stroke = false, layoutOrder = index,
		})
		button.Activated:Connect(function()
			selectedCategory = id
			selectedWeapon = nil
			refreshCategories()
			refreshWeaponList()
		end)
		categoryButtons[id] = button
	end

	-- Liste des armes
	local list = Instance.new("ScrollingFrame")
	list.Size = UDim2.new(1, -520, 1, -16)
	list.Position = UDim2.fromOffset(166, 8)
	list.BackgroundColor3 = Theme.Panel
	list.BackgroundTransparency = 0.5
	list.BorderSizePixel = 0
	list.ScrollBarThickness = 5
	list.ScrollBarImageColor3 = Theme.Accent
	list.CanvasSize = UDim2.new()
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.Parent = body
	UIKit.Corner(list, 10)
	local listLayout = UIKit.ListLayout(list, 6)
	listLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	local listPadding = Instance.new("UIPadding")
	listPadding.PaddingTop = UDim.new(0, 6)
	listPadding.PaddingBottom = UDim.new(0, 6)
	listPadding.Parent = list
	ui.weaponList = list

	buildDetails(body)

	ui.buyButton.Activated:Connect(function()
		if selectedWeapon and not isOwned(selectedWeapon.id) then
			Net.Event("RequestPurchase"):FireServer(selectedWeapon.id)
		end
	end)
	ui.equipPrimary.Activated:Connect(function()
		if selectedWeapon and isOwned(selectedWeapon.id) then
			Net.Event("RequestEquip"):FireServer("primary", selectedWeapon.id)
		end
	end)
	ui.equipSecondary.Activated:Connect(function()
		if selectedWeapon and isOwned(selectedWeapon.id) then
			Net.Event("RequestEquip"):FireServer("secondary", selectedWeapon.id)
		end
	end)
end

--- Le curseur n'est affiche que lorsqu'il y a quelque chose a cliquer :
--- boutique ouverte, ou entre deux manches (ecran de vote).
local function updateMouseIcon()
	local state = ClientState.match.state
	UserInputService.MouseIconEnabled = isOpen or state ~= "Active"
end

function ShopController.SetOpen(open)
	isOpen = open
	if screen then
		screen.Enabled = open
	end
	updateMouseIcon()
	if open then
		refreshAll()
	end
end

function ShopController.IsOpen()
	return isOpen
end

function ShopController.Start()
	build()

	ClientState.ProfileChanged:Connect(function()
		if isOpen then
			refreshAll()
		end
	end)
	ClientState.MatchChanged:Connect(updateMouseIcon)
	updateMouseIcon()

	UserInputService.InputBegan:Connect(function(input, processed)
		if processed then
			return
		end
		if input.KeyCode == GameConfig.Keys.Shop then
			ShopController.SetOpen(not isOpen)
		elseif input.KeyCode == Enum.KeyCode.Escape and isOpen then
			ShopController.SetOpen(false)
		end
	end)

	-- Premier chargement du profil.
	task.spawn(function()
		local ok, profile = pcall(function()
			return Net.Function("GetProfile"):InvokeServer()
		end)
		if ok and type(profile) == "table" then
			ClientState.SetProfile(profile)
		end
	end)
end

return ShopController
