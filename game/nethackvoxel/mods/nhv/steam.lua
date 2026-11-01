-- Steam, in the Steam build (the VoxHack engine's nhv_steam: core.nhv_steam*
-- - nothing, everywhere else):
--   * achievements: each one unlocked (achievements.lua) unlocked on Steam
--     too, under its own id (the API names set up in Steamworks:
--     steam/ACHIEVEMENTS.md); those unlocked before - a save brought over
--     from the itch build - sent once when the game starts
--   * rich presence: what your friends see you doing - "Alex the Aspirant,
--     Dlvl 4 (Gnomish Mines)", or at the title screen (the strings:
--     steam/rich_presence.vdf, uploaded in Steamworks)

local steam = {}
nhv.steam = steam

function steam.on()
	return core.nhv_steam ~= nil and core.nhv_steam()
end

function steam.achieve(id)
	if steam.on() then
		core.nhv_steam_achieve(id)
	end
end

-- (those already unlocked, once)
core.after(0, function()
	if not steam.on() then
		return
	end
	local ach = nhv.achievements
	for id in pairs(ach.by_id) do
		if ach.unlocked(id) then
			core.nhv_steam_achieve(id)
		end
	end
end)

-- ---------------------------------------------------------------- presence
local shown = nil
local function want()
	if nhv.title and nhv.title.open then
		return "#Title", nil
	end
	local h = nhv.nh.snap and nhv.nh.snap.hero
	if not (h and h.name) then
		return "#Title", nil
	end
	local who = h.name .. (h.rank and h.rank ~= "" and (" the " .. h.rank) or "")
	local where = (h.level_desc or ""):gsub("Dlvl:", "Dlvl ")
	if h.dungeon_name and h.dungeon_name ~= "" and h.dungeon_name ~= "The Dungeons of Doom" then
		where = where .. " (" .. h.dungeon_name .. ")"
	end
	return "#Playing", where ~= "" and (who .. ", " .. where) or who
end

local t = 0
core.register_globalstep(function(dtime)
	t = t + dtime
	if t < 2 or not steam.on() then
		return
	end
	t = 0
	local display, status = want()
	local key = display .. "|" .. (status or "")
	if key ~= shown then
		shown = key
		core.nhv_steam_presence("status", status or "")
		core.nhv_steam_presence("steam_display", display)
	end
end)

return steam
