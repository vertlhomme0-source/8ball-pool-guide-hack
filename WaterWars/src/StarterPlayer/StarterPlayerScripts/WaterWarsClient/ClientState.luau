--[[
	ClientState
	Etat local partage entre les controleurs du client (match en cours, profil,
	munitions, equipe...). Chaque changement emet un signal : le HUD, la
	boutique et le tableau des scores s'y abonnent sans se connaitre.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local WaterWars = ReplicatedStorage:WaitForChild("WaterWars")
local Shared = WaterWars:WaitForChild("Shared")
local Config = WaterWars:WaitForChild("Config")

local Signal = require(Shared:WaitForChild("Signal"))
local Weapons = require(Config:WaitForChild("Weapons"))

local ClientState = {}

ClientState.match = {
	state = "Waiting",
	timeLeft = 0,
	mode = { id = "TeamSoak", name = "Bataille d'equipes", teamBased = true },
	map = nil,
	scores = { Blue = 0, Red = 0 },
	scoreLimit = 50,
	playerCount = 0,
	minPlayers = 1,
	result = nil,
}

ClientState.profile = {
	coins = 0,
	owned = {},
	loadout = { primary = Weapons.DefaultPrimary, secondary = Weapons.DefaultSecondary },
	stats = {},
}

ClientState.ammo = { weaponId = nil, current = 0, max = 0, reloading = false }
ClientState.scoreboard = {}
ClientState.vote = { options = {}, votes = {}, open = false, choice = nil, revision = 0 }

ClientState.MatchChanged = Signal.new("MatchChanged")
ClientState.ProfileChanged = Signal.new("ProfileChanged")
ClientState.AmmoChanged = Signal.new("AmmoChanged")
ClientState.ScoreboardChanged = Signal.new("ScoreboardChanged")
ClientState.VoteChanged = Signal.new("VoteChanged")

function ClientState.SetMatch(payload)
	if type(payload) ~= "table" then
		return
	end
	ClientState.match = payload
	ClientState.MatchChanged:Fire(payload)
end

function ClientState.SetProfile(payload)
	if type(payload) ~= "table" then
		return
	end
	ClientState.profile = payload
	ClientState.ProfileChanged:Fire(payload)
end

function ClientState.SetAmmo(weaponId, current, max, reloading)
	ClientState.ammo = {
		weaponId = weaponId,
		current = current or 0,
		max = max or 0,
		reloading = reloading == true,
	}
	ClientState.AmmoChanged:Fire(ClientState.ammo)
end

function ClientState.SetScoreboard(rows)
	if type(rows) ~= "table" then
		return
	end
	ClientState.scoreboard = rows
	ClientState.ScoreboardChanged:Fire(rows)
end

function ClientState.SetVote(payload)
	if type(payload) ~= "table" then
		return
	end
	if payload.phase == "open" then
		local revision = (ClientState.vote.revision or 0) + 1
		ClientState.vote = {
			options = payload.options or {},
			votes = {},
			open = true,
			choice = nil,
			revision = revision,
		}
	elseif payload.phase == "update" then
		ClientState.vote.votes = payload.votes or {}
	elseif payload.phase == "closed" then
		ClientState.vote.open = false
		ClientState.vote.chosen = payload.chosen
	end
	ClientState.VoteChanged:Fire(ClientState.vote)
end

--- Arme actuellement tenue (d'apres l'outil equipe), ou nil.
function ClientState.GetEquippedWeapon()
	local player = game:GetService("Players").LocalPlayer
	local character = player.Character
	if not character then
		return nil
	end
	local tool = character:FindFirstChildOfClass("Tool")
	if not tool then
		return nil
	end
	local id = tool:GetAttribute("WeaponId")
	if type(id) ~= "string" then
		return nil
	end
	return Weapons.Get(id), tool
end

return ClientState
