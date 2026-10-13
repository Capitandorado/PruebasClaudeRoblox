-- Plays named sound effects from Config/Sounds, honouring the player's SFX setting.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")

local Sounds = require(ReplicatedStorage:WaitForChild("Shared").Config.Sounds)
local Store = require(script.Parent.Store)

local Sound = {}

local cache: { [string]: Sound } = {}

function Sound.play(name: string, pitchVariation: number?)
	local profile = Store.profile
	if profile and profile.settings and profile.settings.sfx == false then
		return
	end
	local def = Sounds.Library[name]
	if not def then
		return
	end
	local sound = cache[name]
	if not sound then
		sound = Instance.new("Sound")
		sound.Name = "SFX_" .. name
		sound.SoundId = if def.id ~= "" then def.id else def.fallback
		sound.Volume = def.volume
		sound.Parent = SoundService
		cache[name] = sound
	end
	local variation = pitchVariation or 0
	sound.PlaybackSpeed = def.pitch * (1 + (math.random() * 2 - 1) * variation)
	sound.TimePosition = 0
	sound:Play()
end

return Sound
