--!strict
-- Built-in content that ships inside the Roblox client. Every path below was verified
-- against the client file manifest (Roblox-Client-Tracker rbxManifest.txt, version
-- 0.742.0.7421053). The game uses no external asset ids except the optional sounds.

local Assets = {}

Assets.Textures = {
	Sparkles = "rbxasset://textures/particles/sparkles_main.dds",
	Smoke = "rbxasset://textures/particles/smoke_main.dds",
	Fire = "rbxasset://textures/particles/fire_main.dds",
	Glow = "rbxasset://textures/particles/forcefield_glow_main.dds",
	Shockwave = "rbxasset://textures/particles/explosion01_shockwave_main.dds",
	Square = "rbxasset://textures/particles/SquareParticle.png",
}

-- Font families from content/fonts/families (also verified in the manifest).
-- Cartoon fonts: Luckiest Guy for titles and big buttons, Fredoka One for numbers and
-- button labels. (Gotham is no longer shipped: Enum.Font.GothamBlack renders Montserrat.)
Assets.Fonts = {
	Display = "rbxasset://fonts/families/Michroma.json",
	UI = "rbxasset://fonts/families/BuilderSans.json",
	Mono = "rbxasset://fonts/families/RobotoMono.json",
	Title = "rbxasset://fonts/families/LuckiestGuy.json",
	Cartoon = "rbxasset://fonts/families/FredokaOne.json",
}

return Assets
