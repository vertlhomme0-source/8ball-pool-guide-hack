--[[
	UIKit
	Petits assistants pour construire l'interface en code. Aucune image n'est
	utilisee : tout le HUD est fait de Frames, de coins arrondis et de degrades,
	ce qui garantit qu'il s'affiche correctement sans aucun asset a uploader.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GameConfig = require(ReplicatedStorage:WaitForChild("WaterWars"):WaitForChild("Config"):WaitForChild("GameConfig"))

local UIKit = {}

UIKit.Theme = GameConfig.UI

function UIKit.Corner(parent, radius)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius or 8)
	corner.Parent = parent
	return corner
end

function UIKit.Stroke(parent, color, thickness, transparency)
	local stroke = Instance.new("UIStroke")
	stroke.Color = color or UIKit.Theme.Accent
	stroke.Thickness = thickness or 1
	stroke.Transparency = transparency or 0.4
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = parent
	return stroke
end

function UIKit.Padding(parent, amount)
	local padding = Instance.new("UIPadding")
	local offset = UDim.new(0, amount or 8)
	padding.PaddingTop = offset
	padding.PaddingBottom = offset
	padding.PaddingLeft = offset
	padding.PaddingRight = offset
	padding.Parent = parent
	return padding
end

function UIKit.ListLayout(parent, padding, direction)
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, padding or 6)
	layout.FillDirection = direction or Enum.FillDirection.Vertical
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = parent
	return layout
end

--- Panneau de fond standard du HUD.
function UIKit.Panel(parent, size, position, anchor)
	local frame = Instance.new("Frame")
	frame.Size = size
	frame.Position = position
	frame.AnchorPoint = anchor or Vector2.new(0, 0)
	frame.BackgroundColor3 = UIKit.Theme.Panel
	frame.BackgroundTransparency = 0.18
	frame.BorderSizePixel = 0
	frame.Parent = parent
	UIKit.Corner(frame, 10)
	UIKit.Stroke(frame, UIKit.Theme.AccentDark, 1.5, 0.35)
	return frame
end

function UIKit.Label(parent, text, size, position, options)
	options = options or {}
	local label = Instance.new("TextLabel")
	label.Size = size
	label.Position = position or UDim2.fromOffset(0, 0)
	label.AnchorPoint = options.anchor or Vector2.new(0, 0)
	label.BackgroundTransparency = options.backgroundTransparency or 1
	label.BackgroundColor3 = options.backgroundColor or UIKit.Theme.PanelLight
	label.BorderSizePixel = 0
	label.Text = text
	label.TextColor3 = options.color or UIKit.Theme.Text
	label.Font = options.font or UIKit.Theme.Font
	label.TextSize = options.textSize or 16
	label.TextScaled = options.scaled or false
	label.TextXAlignment = options.align or Enum.TextXAlignment.Left
	label.TextYAlignment = options.alignY or Enum.TextYAlignment.Center
	label.TextTransparency = options.transparency or 0
	label.RichText = options.richText or false
	label.LayoutOrder = options.layoutOrder or 0
	label.Parent = parent
	if options.stroke then
		local stroke = Instance.new("UIStroke")
		stroke.Color = Color3.fromRGB(0, 0, 0)
		stroke.Thickness = 1.5
		stroke.Transparency = 0.45
		stroke.Parent = label
	end
	return label
end

function UIKit.Button(parent, text, size, position, options)
	options = options or {}
	local button = Instance.new("TextButton")
	button.Size = size
	button.Position = position or UDim2.fromOffset(0, 0)
	button.AnchorPoint = options.anchor or Vector2.new(0, 0)
	button.BackgroundColor3 = options.color or UIKit.Theme.PanelLight
	button.BackgroundTransparency = options.transparency or 0
	button.BorderSizePixel = 0
	button.AutoButtonColor = true
	button.Text = text
	button.TextColor3 = options.textColor or UIKit.Theme.Text
	button.Font = options.font or UIKit.Theme.FontBold
	button.TextSize = options.textSize or 16
	button.TextScaled = options.scaled or false
	button.LayoutOrder = options.layoutOrder or 0
	button.Parent = parent
	UIKit.Corner(button, options.radius or 8)
	if options.stroke ~= false then
		UIKit.Stroke(button, options.strokeColor or UIKit.Theme.Accent, 1.2, 0.55)
	end
	return button
end

--- Barre de progression (vie, eau, endurance).
function UIKit.Bar(parent, size, position, color, options)
	options = options or {}
	local background = Instance.new("Frame")
	background.Size = size
	background.Position = position
	background.AnchorPoint = options.anchor or Vector2.new(0, 0)
	background.BackgroundColor3 = options.backgroundColor or Color3.fromRGB(12, 16, 24)
	background.BackgroundTransparency = 0.25
	background.BorderSizePixel = 0
	background.Parent = parent
	UIKit.Corner(background, options.radius or 6)

	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.fromScale(1, 1)
	fill.BackgroundColor3 = color
	fill.BorderSizePixel = 0
	fill.Parent = background
	UIKit.Corner(fill, options.radius or 6)

	local gradient = Instance.new("UIGradient")
	gradient.Color = ColorSequence.new(color, color:Lerp(Color3.new(1, 1, 1), 0.35))
	gradient.Rotation = 90
	gradient.Parent = fill

	return background, fill
end

--- Cree le ScreenGui racine d'un controleur.
function UIKit.Screen(name, displayOrder)
	local player = game:GetService("Players").LocalPlayer
	local playerGui = player:WaitForChild("PlayerGui")
	local existing = playerGui:FindFirstChild(name)
	if existing then
		existing:Destroy()
	end
	local screen = Instance.new("ScreenGui")
	screen.Name = name
	screen.ResetOnSpawn = false
	screen.IgnoreGuiInset = true
	screen.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screen.DisplayOrder = displayOrder or 1
	screen.Parent = playerGui
	return screen
end

return UIKit
