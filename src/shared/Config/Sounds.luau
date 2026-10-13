--!strict
-- Sound library. Every effect has:
--   id        your uploaded asset ("rbxassetid://123..."). Leave "" to use the fallback.
--   fallback  a sound that ships inside the Roblox client (verified against the client
--             file manifest: content/sounds/volume_slider.ogg and impact_explosion_03.mp3).
-- Original sound effects for every entry are in assets/sounds/<Name>.wav: upload them with
-- the Asset Manager and paste the resulting ids here (see docs/SOUNDS.md).

export type SoundDef = {
	id: string,
	fallback: string,
	volume: number,
	pitch: number,
}

local TICK = "rbxasset://sounds/volume_slider.ogg"
local BOOM = "rbxasset://sounds/impact_explosion_03.mp3"

local Sounds = {}

Sounds.Library = {
	UIClick = { id = "", fallback = TICK, volume = 0.35, pitch = 1.3 },
	Error = { id = "", fallback = TICK, volume = 0.5, pitch = 0.5 },
	BoxOpen = { id = "", fallback = TICK, volume = 0.6, pitch = 0.8 },
	RevealCommon = { id = "", fallback = TICK, volume = 0.6, pitch = 1.1 },
	RevealRare = { id = "", fallback = TICK, volume = 0.8, pitch = 1.6 },
	RevealLegendary = { id = "", fallback = BOOM, volume = 0.35, pitch = 1.7 },
	RevealDivine = { id = "", fallback = BOOM, volume = 0.4, pitch = 1.25 },
	RevealVoid = { id = "", fallback = BOOM, volume = 0.45, pitch = 0.65 },
	Purchase = { id = "", fallback = TICK, volume = 0.7, pitch = 1.9 },
	Upgrade = { id = "", fallback = TICK, volume = 0.7, pitch = 2.2 },
	Fusion = { id = "", fallback = BOOM, volume = 0.3, pitch = 2 },
	Unlock = { id = "", fallback = BOOM, volume = 0.35, pitch = 1.5 },
	Rebirth = { id = "", fallback = BOOM, volume = 0.6, pitch = 0.5 },
	Place = { id = "", fallback = TICK, volume = 0.5, pitch = 0.95 },
	QuestComplete = { id = "", fallback = TICK, volume = 0.7, pitch = 2.5 },
} :: { [string]: SoundDef }

return Sounds
