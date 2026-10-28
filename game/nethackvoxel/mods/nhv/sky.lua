-- The sky: Quake-style clouds - two scrolling layers, generated (layered
-- noise) or pictures, on one flat plane high overhead - over a plain colour
-- or the day and night sky (the sun, the moon and the stars, following the
-- real clock as NetHack's own night does). Drawn by the VoxHack build
-- of Luanti (client/shaders/nhv_sky_shader). Skies are made in the
-- editor's Sky tab and saved to mods/nhv_sky/skies.json, which also says
-- which sky each level gets; the file is re-read when it changes.
--
-- It's shown on levels that have the sky over them anywhere (terrain.lua's
-- has_sky: Medusa's island, Juiblex's swamp, the Big Rooms that can have
-- trees, and any level with a cell whose ceiling is open), not while you're
-- blind. Elsewhere there's no sky: just black.
--
-- skies.json:
--   skies:  {id, name, layers = {back, front}, horizon = {color, fade},
--            pixels (pixels per repeat: sharp; 0 smooth), fog_color,
--            daynight, sun, moon, stars, stars_always (by day too, or in
--            a plain sky), cloud_brightness (1: as drawn), lightning}
--     layer: kind ("generated" or "texture"), speed = {x, y} (repeats per
--            second), scale, opacity (0..1), tint ("#RRGGBB");
--            generated: coverage, softness (0..1), detail (1..6), shade
--            (the shadowed parts' colour); texture: texture (in
--            nhv_sky/textures), see_through_black
--   lightning: {on, rate (bolts a minute, on average), sound (thunder:
--            the hook sky_thunder, a moment after - longer the further off
--            the bolt)}: bolts across the sky now and then, high over you
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
	-- (the variant's own sky, else its family's: "medusa-2", "medusa"; the
	-- editor writes names in lower case - the quest's are "Arc-strt")
	for v in pairs(variants) do
		v = v:lower()
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

local function pairs_list(t)
	local out = {}
	for _, kv in ipairs(t) do
		out[#out + 1] = kv[1] .. "=" .. tostring(kv[2])
	end
	return table.concat(out, ",")
end

-- the engine's "nhv_sky" setting for sky s (see sky.cpp)
local function config(s)
	local parts = {}
	for i = 1, 2 do
		local l = s.layers and s.layers[i] or {}
		local sp = type(l.speed) == "table" and l.speed or {}
		local gen = l.kind == "generated"
		local r, g, b = rgb(l.tint)
		local sr, sg, sb = rgb(l.shade or "#666673")
		local kv = {{"kind", gen and "gen" or "tex"}, {"sx", num(sp[1], 0)}, {"sy", num(sp[2], 0)},
			{"scale", num(l.scale, 3)}, {"alpha", (gen or l.texture) and num(l.opacity, 1) or 0},
			{"r", r}, {"g", g}, {"b", b}}
		if gen then
			for _, e in ipairs({{"cover", num(l.coverage, 0.5)}, {"soft", num(l.softness, 0.15)},
					{"detail", num(l.detail, 4)}, {"shr", sr}, {"shg", sg}, {"shb", sb}}) do
				kv[#kv + 1] = e
			end
		else
			kv[#kv + 1] = {"tex", l.texture or ""}
			kv[#kv + 1] = {"key", l.see_through_black and 1 or 0}
		end
		parts[i] = pairs_list(kv)
	end
	local h = s.horizon or {}
	local r, g, b = rgb(h.color or "#000000")
	parts[3] = pairs_list({{"hr", r}, {"hg", g}, {"hb", b}, {"fade", num(h.fade, 0)},
		{"px", num(s.pixels, 0)}, {"dn", s.daynight and 1 or 0}, {"bright", num(s.cloud_brightness, 1)}})
	return table.concat(parts, ";")
end

-- the sky shown now (nil: none)
function sky.current()
	return sky.def
end

-- Luanti's own sky for the player (hud.apply_fog: fog as given): plain
-- black - or, while a sky is shown, its fog colour (over the whole level),
-- or the day and night sky with its sun, moon and stars.
function sky.apply(player, fog)
	local s = sky.def
	local base = s and nhv.terrain.open_sky and s.fog_color or "#000000"
	if s and s.daynight then
		player:set_sky({type = "regular", clouds = false, fog = fog})
	else
		player:set_sky({type = "plain", base_color = base, clouds = false, fog = fog})
	end
	local dn = s and s.daynight
	player:set_sun({visible = dn and s.sun ~= false or false, sunrise_visible = dn and s.sun ~= false or false})
	player:set_moon({visible = dn and s.moon ~= false or false})
	-- (stars all the time: by day too - full strength - and in a plain sky)
	local always = s and s.stars_always == true
	player:set_stars({visible = always or (dn and s.stars ~= false) or false, day_opacity = always and 1 or 0})
end

local function set(s)
	local cfg = s and config(s) or ""
	local changed = s ~= sky.def or (s and s.daynight) ~= sky.daynight_shown
		or (s and nhv.terrain.open_sky) ~= sky.open_shown
	if cfg ~= sky.shown then
		sky.shown = cfg
		core.settings:set("nhv_sky", cfg)
	end
	if changed then
		sky.def = s
		sky.daynight_shown = s and s.daynight
		sky.open_shown = s and nhv.terrain.open_sky
		local player = nhv.player.get()
		if player and nhv.hud.apply_fog then
			nhv.hud.apply_fog(player)
		end
	end
end

-- the day and night sky follows the real clock (as NetHack's night does)
local function real_time_of_day()
	local t = os.date("*t")
	return (t.hour * 3600 + t.min * 60 + t.sec) / 86400
end

function sky.update()
	local snap = nh.snap
	local hero = snap and snap.hero
	local s = hero and not U.has(hero.flags, U.HERO.BLIND) and nhv.terrain.has_sky() and sky.for_level()
	set(s or nil)
	if s and s.daynight then
		core.set_timeofday(real_time_of_day())
	end
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

-- ---------------------------------------------------------------- lightning
-- A sky with lightning: now and then (rate a minute, at random) a bolt
-- shoots across it, high over you somewhere round about, forking on its
-- way (lightning.lua draws it); the sky lights up for a moment, and the
-- thunder follows (when it has sound), later the further off it was. Not
-- while you're blind; only where the sky is shown.
local BOLT_H = {24, 40}     -- how high over you (nodes)
local BOLT_OFF = {12, 48}   -- how far off to the side its middle is
local BOLT_LEN = {18, 42}   -- how long

local function between(r)
	return r[1] + math.random() * (r[2] - r[1])
end

function sky.bolt(player)
	local p = player:get_pos()
	local a = math.random() * 2 * math.pi
	local off = between(BOLT_OFF)
	local mid = vector.new(p.x + math.cos(a) * off, p.y + between(BOLT_H), p.z + math.sin(a) * off)
	-- (across the sky, sloping down a little)
	local d = math.random() * 2 * math.pi
	local half = between(BOLT_LEN) / 2
	local dir = vector.new(math.cos(d) * half, -half * (0.1 + math.random() * 0.35), math.sin(d) * half)
	nhv.lightning.bolt(vector.subtract(mid, dir), vector.add(mid, dir),
		{width = 3.2, life = 0.14, flickers = 2 + math.random(0, 2), rough = 0.16, branches = 2})
	nhv.hud.flash("#DDE6FF", 0.25 + 0.2 * (1 - off / BOLT_OFF[2]), true, 0.35)
	local l = sky.def and sky.def.lightning
	if l and l.sound ~= false and nhv.sound then
		-- (sound is slower than light: a second or two for a far one)
		core.after(0.15 + vector.distance(p, mid) / 40, function()
			nhv.sound.hook("sky_thunder", {pos = mid})
		end)
	end
end

core.register_globalstep(function(dtime)
	local s = sky.def
	local l = s and s.lightning
	if not (l and l.on) then
		return
	end
	local player = nhv.player.get()
	local h = nh.snap and nh.snap.hero
	if not player or (h and U.has(h.flags, U.HERO.BLIND)) then
		return
	end
	if math.random() < dtime * (tonumber(l.rate) or 4) / 60 then
		sky.bolt(player)
	end
end)

-- (not left set for the next start: the game sets it as it needs it)
core.register_on_shutdown(function()
	core.settings:set("nhv_sky", "")
end)

return sky
