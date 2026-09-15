--[[
	ScoreboardController
	Tableau des scores affiche tant que la touche Tab est maintenue.
	Les joueurs sont regroupes par equipe en mode par equipes, et classes par
	score en chacun pour soi.
]]

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local WaterWars = ReplicatedStorage:WaitForChild("WaterWars")
local GameConfig = require(WaterWars:WaitForChild("Config"):WaitForChild("GameConfig"))

local ClientState = require(script.Parent:WaitForChild("ClientState"))
local UIKit = require(script.Parent:WaitForChild("UIKit"))

local ScoreboardController = {}

local Theme = UIKit.Theme
local localPlayer = Players.LocalPlayer

local screen = nil
local rowsHolder = nil
local headerLabel = nil
local rowFrames = {}

local function teamColor(teamId)
	for _, definition in ipairs(GameConfig.Teams) do
		if definition.id == teamId then
			return definition.color
		end
	end
	return Theme.TextDim
end

local function clearRows()
	for _, frame in ipairs(rowFrames) do
		frame:Destroy()
	end
	table.clear(rowFrames)
end

local function addHeaderRow(text, color, order)
	local frame = Instance.new("Frame")
	frame.Size = UDim2.new(1, 0, 0, 26)
	frame.BackgroundTransparency = 1
	frame.LayoutOrder = order
	frame.Parent = rowsHolder
	UIKit.Label(frame, text, UDim2.new(1, 0, 1, 0), nil, {
		font = Theme.FontBold, textSize = 16, color = color,
	})
	table.insert(rowFrames, frame)
end

local function addPlayerRow(row, order)
	local frame = Instance.new("Frame")
	frame.Size = UDim2.new(1, 0, 0, 28)
	frame.BackgroundColor3 = row.userId == localPlayer.UserId and Theme.AccentDark or Theme.Panel
	frame.BackgroundTransparency = row.userId == localPlayer.UserId and 0.25 or 0.55
	frame.BorderSizePixel = 0
	frame.LayoutOrder = order
	frame.Parent = rowsHolder
	UIKit.Corner(frame, 6)

	UIKit.Label(frame, row.name, UDim2.new(0.45, 0, 1, 0), UDim2.fromOffset(12, 0), {
		textSize = 15, color = teamColor(row.team),
	})
	local columns = {
		{ value = row.score, width = 0.16 },
		{ value = row.kills, width = 0.13 },
		{ value = row.assists, width = 0.13 },
		{ value = row.deaths, width = 0.13 },
	}
	local offset = 0.45
	for _, column in ipairs(columns) do
		UIKit.Label(frame, tostring(column.value or 0), UDim2.new(column.width, 0, 1, 0), UDim2.fromScale(offset, 0), {
			textSize = 15, align = Enum.TextXAlignment.Center, font = Theme.FontBold,
		})
		offset = offset + column.width
	end
	table.insert(rowFrames, frame)
end

local function refresh()
	if not screen or not screen.Enabled then
		return
	end
	clearRows()

	local match = ClientState.match
	local rows = ClientState.scoreboard
	headerLabel.Text = string.format(
		"%s  -  %s",
		match.mode and match.mode.name or "",
		match.map and match.map.name or "Vestiaire"
	)

	local order = 0
	if match.mode and match.mode.teamBased then
		for _, definition in ipairs(GameConfig.Teams) do
			local teamRows = {}
			for _, row in ipairs(rows) do
				if row.team == definition.id then
					table.insert(teamRows, row)
				end
			end
			order = order + 1
			addHeaderRow(
				string.format("%s  -  %d", definition.name, (match.scores and match.scores[definition.id]) or 0),
				definition.color,
				order
			)
			for _, row in ipairs(teamRows) do
				order = order + 1
				addPlayerRow(row, order)
			end
		end
		-- Joueurs sans equipe (viennent de se connecter).
		local neutral = {}
		for _, row in ipairs(rows) do
			if row.team == nil then
				table.insert(neutral, row)
			end
		end
		if #neutral > 0 then
			order = order + 1
			addHeaderRow("Spectateurs", Theme.TextDim, order)
			for _, row in ipairs(neutral) do
				order = order + 1
				addPlayerRow(row, order)
			end
		end
	else
		order = order + 1
		addHeaderRow("Classement", Theme.Accent, order)
		for _, row in ipairs(rows) do
			order = order + 1
			addPlayerRow(row, order)
		end
	end
end

local function build()
	screen = UIKit.Screen("WaterWarsScoreboard", 4)
	screen.Enabled = false

	local panel = UIKit.Panel(screen, UDim2.fromOffset(660, 480), UDim2.fromScale(0.5, 0.5), Vector2.new(0.5, 0.5))

	UIKit.Label(panel, "TABLEAU DES SCORES", UDim2.new(1, -24, 0, 26), UDim2.fromOffset(16, 12), {
		font = Theme.FontBold, textSize = 22,
	})
	headerLabel = UIKit.Label(panel, "", UDim2.new(1, -24, 0, 18), UDim2.fromOffset(16, 38), {
		textSize = 14, color = Theme.TextDim,
	})

	local columns = Instance.new("Frame")
	columns.Size = UDim2.new(1, -24, 0, 18)
	columns.Position = UDim2.fromOffset(12, 62)
	columns.BackgroundTransparency = 1
	columns.Parent = panel
	UIKit.Label(columns, "JOUEUR", UDim2.new(0.45, 0, 1, 0), UDim2.fromOffset(12, 0), {
		textSize = 12, color = Theme.TextDim, font = Theme.FontBold,
	})
	local headers = { "SCORE", "ELIM.", "ASSIST.", "MORTS" }
	local widths = { 0.16, 0.13, 0.13, 0.13 }
	local offset = 0.45
	for index, title in ipairs(headers) do
		UIKit.Label(columns, title, UDim2.new(widths[index], 0, 1, 0), UDim2.fromScale(offset, 0), {
			textSize = 12, color = Theme.TextDim, align = Enum.TextXAlignment.Center, font = Theme.FontBold,
		})
		offset = offset + widths[index]
	end

	local scroll = Instance.new("ScrollingFrame")
	scroll.Size = UDim2.new(1, -24, 1, -100)
	scroll.Position = UDim2.fromOffset(12, 86)
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.ScrollBarThickness = 4
	scroll.ScrollBarImageColor3 = Theme.Accent
	scroll.CanvasSize = UDim2.new()
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.Parent = panel
	UIKit.ListLayout(scroll, 4)
	rowsHolder = scroll
end

function ScoreboardController.SetVisible(visible)
	if screen then
		screen.Enabled = visible
		if visible then
			refresh()
		end
	end
end

function ScoreboardController.Start()
	build()

	ClientState.ScoreboardChanged:Connect(refresh)
	ClientState.MatchChanged:Connect(refresh)

	UserInputService.InputBegan:Connect(function(input, processed)
		if not processed and input.KeyCode == GameConfig.Keys.Scoreboard then
			ScoreboardController.SetVisible(true)
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if input.KeyCode == GameConfig.Keys.Scoreboard then
			ScoreboardController.SetVisible(false)
		end
	end)
end

return ScoreboardController
