--[[
	SoundController
	Habillage sonore. On n'utilise que des sons livres avec le client Roblox
	(rbxasset://...) : aucun upload, aucun ID a moderer. Pour mettre vos
	propres sons, remplacez simplement les valeurs de GameConfig.Sounds.
]]

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local SoundService = game:GetService("SoundService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local WaterWars = ReplicatedStorage:WaitForChild("WaterWars")
local Config = WaterWars:WaitForChild("Config")
local Shared = WaterWars:WaitForChild("Shared")

local GameConfig = require(Config:WaitForChild("GameConfig"))
local Weapons = require(Config:WaitForChild("Weapons"))
local Net = require(Shared:WaitForChild("Net"))

local SoundController = {}

local localPlayer = Players.LocalPlayer
local MAX_DISTANCE = 220

--- Son non positionnel (interface, marqueur de touche).
local function play2D(assetId, volume, pitch)
	if type(assetId) ~= "string" or #assetId == 0 then
		return
	end
	local sound = Instance.new("Sound")
	sound.SoundId = assetId
	sound.Volume = volume or 0.5
	sound.PlaybackSpeed = pitch or 1
	sound.Parent = SoundService
	sound:Play()
	Debris:AddItem(sound, 4)
end

--- Son positionne dans le monde.
local function play3D(assetId, position, volume, pitch)
	if type(assetId) ~= "string" or #assetId == 0 then
		return
	end
	local camera = workspace.CurrentCamera
	if camera and (camera.CFrame.Position - position).Magnitude > MAX_DISTANCE then
		return
	end
	local anchor = Instance.new("Part")
	anchor.Size = Vector3.new(0.2, 0.2, 0.2)
	anchor.CFrame = CFrame.new(position)
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.CastShadow = false
	anchor.Transparency = 1
	anchor.Parent = workspace

	local sound = Instance.new("Sound")
	sound.SoundId = assetId
	sound.Volume = volume or 0.5
	sound.PlaybackSpeed = pitch or 1
	sound.RollOffMaxDistance = MAX_DISTANCE
	sound.RollOffMinDistance = 12
	sound.Parent = anchor
	sound:Play()
	Debris:AddItem(anchor, 4)
end

function SoundController.Start()
	local sounds = GameConfig.Sounds

	Net.Event("ProjectileSpawned").OnClientEvent:Connect(function(shooter, weaponId, origin)
		local weapon = Weapons.Get(weaponId)
		if not weapon or typeof(origin) ~= "Vector3" then
			return
		end
		-- Les armes tres rapides ne jouent qu'un son sur trois : sinon le
		-- melange sature des qu'un minigun tire.
		if weapon.fireRate > 10 and math.random() > 0.34 then
			return
		end
		local pitch = 0.85 + math.random() * 0.3
		if shooter == localPlayer then
			play2D(sounds.Shoot, 0.35, pitch)
		else
			play3D(sounds.Shoot, origin, 0.5, pitch)
		end
	end)

	Net.Event("ImpactEffect").OnClientEvent:Connect(function(position, _normal, weaponId, hitCharacter)
		local weapon = Weapons.Get(weaponId)
		if not weapon or typeof(position) ~= "Vector3" then
			return
		end
		if not hitCharacter and math.random() > 0.3 then
			return
		end
		play3D(sounds.Splash, position, hitCharacter and 0.55 or 0.3, 1 + math.random() * 0.25)
	end)

	Net.Event("HitMarker").OnClientEvent:Connect(function(_damage, killed)
		if killed then
			play2D(sounds.Eliminate, 0.55, 1)
		else
			play2D(sounds.Hit, 0.3, 1.5)
		end
	end)

	Net.Event("AmmoUpdate").OnClientEvent:Connect(function(_weaponId, _current, _max, reloading)
		if reloading then
			play2D(sounds.Reload, 0.4, 1)
		end
	end)

	Net.Event("MapReady").OnClientEvent:Connect(function()
		play2D(sounds.RoundStart, 0.5, 1)
	end)
end

return SoundController
