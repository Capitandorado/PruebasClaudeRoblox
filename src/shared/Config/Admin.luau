--!strict
-- Debug/admin tools (energy grants, time warp, item grants). Enabled in Roblox Studio and
-- for the user ids listed here. The experience owner is added automatically when the
-- game is owned by a user (game.CreatorType == User).

local Admin = {}

Admin.UserIds = {} :: { number }
Admin.AllowInStudio = true
Admin.AllowCreator = true

return Admin
