-- The sky: Quake-style, two scrolling texture layers on a flattened dome
-- (drawn by the NetHack Voxel build of Luanti; its shader is
-- client/shaders/nhv_sky_shader). Skies are made in the editor's Sky tab
-- and saved to mods/nhv_sky/skies.json, which also says which sky each
-- level gets; the file is re-read when it changes.
--
-- It's shown on levels that have the sky over them anywhere (terrain.lua's
-- has_sky: Medusa's island, Juiblex's swamp, the Big Rooms that can have
-- trees, and any level with a cell whose ceiling is open), not while you're
-- blind. Elsewhere there's no sky: just black.
--
-- skies.json:
--   skies:  {id, name, layers = {back, front}, horizon = {color, fade},
--            smooth, fog_color}
--     layer: texture (in nhv_sky/textures), speed = {x, y} (repeats per
--            second), scale (repeats across the dome), opacity (0..1),
--            tint ("#RRGGBB"), see_through_black (black is see-through)
--   levels: level -> sky id: a special level variant ("medusa-2"), or the
--           name before its "-" ("medusa", "bigrm"), or "default"

local U = nhv.util
local nh = nhv.nh
local sky = {data = {skies = {}, levels = {}}, shown = nil, fog = nil}
nhv.sky = sky

local MODPATH = core.get_modpath("nhv_sky")
local DATA = MODPATH and (MODPATH .. DIR_DELIM .. "skies.json")

local text_loaded
local function load()
	local f = DATA and io.open(DATA, "rb")
	if not f then
		return
	end
	local text = f:read("*a")
	f:close()
	if text == text_loaded then
		return
	end
	text_loaded = text
	local data = core.parse_json(text)
	if type(data) ~= "table" or type(data.skies) ~= "table" then
		core.log("warning", "[nhv] mods/nhv_sky/skies.json isn't valid")
		return
	end
	data.levels = type(data.levels) == "table" and data.levels or {}
	sky.data = data
	sky.shown = nil -- (show it again, as it is now)
end
load()

local function by_id(id)
	for _, s in ipairs(sky.data.skies) do
		if s.id == id then
			return s
		end
	end
end

-- the sky for the level you're on
function sky.for_level()
	local levels = sky.data.levels
	local variants = nhv.areas and nhv.areas.level_variants and nhv.areas.level_variants() or {}
	for v in pairs(variants) do
		local s = by_id(levels[v]) or by_id(levels[v:match("^([^-]+)") or v])
		if s then
			return s
		end
	end
	return by_id(levels.default) or sky.data.skies[1]
end

local function num(v, d)
	return tonumber(v) or d
end

local function rgb(c)
	c = type(c) == "string" and c:match("^#(%x%x%x%x%x%x)$")
	if not c then
		return 1, 1, 1
	end
	return tonumber(c:sub(1, 2), 16) / 255, tonumber(c:sub(3, 4), 16) / 255, tonumber(c:sub(5, 6), 16) / 255
end

-- the engine's "nhv_sky" setting for sky s
local function config(s)
	local parts = {}
	for i = 1, 2 do
		local l = s.layers and s.layers[i] or {}
		local sp = type(l.speed) == "table" and l.speed or {}
		local r, g, b = rgb(l.tint)
		parts[i] = table.concat({l.texture or "", num(sp[1], 0), num(sp[2], 0), num(l.scale, 1),
			l.texture and num(l.opacity, 1) or 0, r, g, b, l.see_through_black and 1 or 0}, "|")
	end
	local h = s.horizon or {}
	local r, g, b = rgb(h.color or "#000000")
	parts[3] = table.concat({r, g, b, num(h.fade, 0), s.smooth and 1 or 0}, "|")
	return table.concat(parts, ";")
end

-- fog colour while the sky is shown over the whole level (nil: black)
function sky.fog_color()
	return sky.fog
end

local function set(cfg, fog)
	if cfg ~= sky.shown then
		sky.shown = cfg
		core.settings:set("nhv_sky", cfg)
	end
	if fog ~= sky.fog then
		sky.fog = fog
		local player = nhv.player.get()
		if player and nhv.hud.apply_fog then
			nhv.hud.apply_fog(player)
		end
	end
end

function sky.update()
	local snap = nh.snap
	local hero = snap and snap.hero
	local s = hero and not U.has(hero.flags, U.HERO.BLIND) and nhv.terrain.has_sky() and sky.for_level()
	if not s then
		set("", nil)
		return
	end
	set(config(s), nhv.terrain.open_sky and s.fog_color or nil)
end

-- (checked now and then: a level change, a cell coming into view, an edit
-- saved in the editor)
local since = 0
core.register_globalstep(function(dtime)
	since = since + dtime
	if since > 0.5 then
		since = 0
		load()
		sky.update()
	end
end)

-- (not left set for the next start: the game sets it as it needs it)
core.register_on_shutdown(function()
	core.settings:set("nhv_sky", "")
end)

return sky
