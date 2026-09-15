--[[
	VoteController
	Ecran de vote entre les manches : trois terrains proposes, un clic pour
	voter, le nombre de voix se met a jour en direct.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local WaterWars = ReplicatedStorage:WaitForChild("WaterWars")
local Shared = WaterWars:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"))

local ClientState = require(script.Parent:WaitForChild("ClientState"))
local UIKit = require(script.Parent:WaitForChild("UIKit"))

local VoteController = {}

local Theme = UIKit.Theme

local screen = nil
local cardsHolder = nil
local titleLabel = nil
local cards = {}
local lastRevision = nil

local CARD_COLORS = {
	Color3.fromRGB(46, 120, 200),
	Color3.fromRGB(180, 90, 200),
	Color3.fromRGB(210, 130, 60),
}

local function clearCards()
	for _, card in ipairs(cards) do
		card.frame:Destroy()
	end
	table.clear(cards)
end

local function refreshVotes()
	local counts = ClientState.vote.votes or {}
	for _, card in ipairs(cards) do
		local count = counts[card.id] or 0
		card.votes.Text = count == 1 and "1 voix" or string.format("%d voix", count)
		local chosen = ClientState.vote.choice == card.id
		card.frame.BackgroundTransparency = chosen and 0.05 or 0.3
		card.stroke.Transparency = chosen and 0 or 0.6
		card.stroke.Color = chosen and Theme.Good or Theme.Accent
	end
end

local function buildCards()
	clearCards()
	local options = ClientState.vote.options or {}
	for index, map in ipairs(options) do
		local frame = Instance.new("TextButton")
		frame.Size = UDim2.new(0, 250, 1, 0)
		frame.BackgroundColor3 = Theme.Panel
		frame.BackgroundTransparency = 0.3
		frame.BorderSizePixel = 0
		frame.Text = ""
		frame.AutoButtonColor = false
		frame.LayoutOrder = index
		frame.Parent = cardsHolder
		UIKit.Corner(frame, 12)
		local stroke = UIKit.Stroke(frame, Theme.Accent, 2, 0.6)

		local banner = Instance.new("Frame")
		banner.Size = UDim2.new(1, 0, 0, 96)
		banner.BackgroundColor3 = CARD_COLORS[((index - 1) % #CARD_COLORS) + 1]
		banner.BorderSizePixel = 0
		banner.Parent = frame
		UIKit.Corner(banner, 12)
		local gradient = Instance.new("UIGradient")
		gradient.Color = ColorSequence.new(
			banner.BackgroundColor3,
			banner.BackgroundColor3:Lerp(Color3.new(0, 0, 0), 0.55)
		)
		gradient.Rotation = 90
		gradient.Parent = banner

		UIKit.Label(banner, map.theme or "", UDim2.new(1, -20, 0, 20), UDim2.new(0, 10, 1, -26), {
			textSize = 13, color = Color3.fromRGB(240, 245, 255),
		})
		UIKit.Label(frame, map.name or "", UDim2.new(1, -20, 0, 26), UDim2.fromOffset(10, 104), {
			font = Theme.FontBold, textSize = 20,
		})
		local description = UIKit.Label(frame, map.description or "", UDim2.new(1, -20, 0, 70), UDim2.fromOffset(10, 132), {
			textSize = 13, color = Theme.TextDim, alignY = Enum.TextYAlignment.Top,
		})
		description.TextWrapped = true

		local votes = UIKit.Label(frame, "0 voix", UDim2.new(1, -20, 0, 22), UDim2.new(0, 10, 1, -30), {
			font = Theme.FontBold, textSize = 16, color = Theme.Warn,
		})

		frame.Activated:Connect(function()
			ClientState.vote.choice = map.id
			Net.Event("CastMapVote"):FireServer(map.id)
			refreshVotes()
		end)

		table.insert(cards, { id = map.id, frame = frame, votes = votes, stroke = stroke })
	end
	refreshVotes()
end

local function refresh()
	local vote = ClientState.vote
	local match = ClientState.match
	local shouldShow = vote.open and match.state == "Vote"
	screen.Enabled = shouldShow
	if shouldShow then
		titleLabel.Text = string.format("VOTEZ POUR LE PROCHAIN TERRAIN  -  %d s", math.ceil(match.timeLeft or 0))
	end
end

function VoteController.Start()
	screen = UIKit.Screen("WaterWarsVote", 3)
	screen.Enabled = false

	local panel = UIKit.Panel(screen, UDim2.fromOffset(820, 330), UDim2.new(0.5, 0, 1, -40), Vector2.new(0.5, 1))

	titleLabel = UIKit.Label(panel, "", UDim2.new(1, -24, 0, 26), UDim2.fromOffset(12, 10), {
		font = Theme.FontBold, textSize = 20, align = Enum.TextXAlignment.Center,
	})

	local holder = Instance.new("Frame")
	holder.Size = UDim2.new(1, -24, 1, -52)
	holder.Position = UDim2.fromOffset(12, 42)
	holder.BackgroundTransparency = 1
	holder.Parent = panel
	cardsHolder = holder
	local layout = UIKit.ListLayout(holder, 12, Enum.FillDirection.Horizontal)
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center

	ClientState.VoteChanged:Connect(function(vote)
		-- Chaque nouveau vote porte un numero : sans cela, deux votes
		-- successifs a trois terrains garderaient les anciennes cartes.
		if vote.open and vote.revision ~= lastRevision then
			lastRevision = vote.revision
			buildCards()
		else
			refreshVotes()
		end
		refresh()
	end)
	ClientState.MatchChanged:Connect(refresh)
end

return VoteController
