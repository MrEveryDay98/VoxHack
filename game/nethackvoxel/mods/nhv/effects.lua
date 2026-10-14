-- Particle effects made in the editor's Effects tab.
--
-- mods/nhv_effects/effects.json lists effects, each a few layers of
-- particles, and the hooks that play them: the same hooks sounds attach
-- to (traps going off, reading a scroll, zapping...; see the sound
-- editor's catalog). An effect plays where its hook happened, or at the
-- hero. The file is re-read when it changes, so edits apply while playing.
--
-- Layer shapes:
--   burst    flies outward from the middle in every direction
--   ring     the same, but flat (along the ground)
--   implode  is pulled in from around the middle
--   rise     floats up from the ground area
--   rain     comes down from above

local effects = {list = {}, by_hook = {}}
nhv.effects = effects

local MODPATH = core.get_modpath("nhv_effects")
local DATA = MODPATH and (MODPATH .. DIR_DELIM .. "effects.json")

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
	if type(data) ~= "table" or type(data.effects) ~= "table" then
		core.log("warning", "[nhv] mods/nhv_effects/effects.json isn't valid")
		return
	end
	effects.list, effects.by_hook = {}, {}
	for _, e in ipairs(data.effects) do
		if type(e) == "table" and e.id then
			effects.list[e.id] = e
			for _, h in ipairs(e.triggers or {}) do
				effects.by_hook[h] = effects.by_hook[h] or {}
				table.insert(effects.by_hook[h], e.id)
			end
		end
	end
end
load()

-- (edits from the editor show up while playing)
local since = 0
core.register_globalstep(function(dtime)
	since = since + dtime
	if since > 2 then
		since = 0
		load()
	end
end)

local function texture(l)
	local t = l.texture or {}
	local tex
	if t.builtin then
		tex = "nhvfx_" .. t.builtin .. ".png"
	elseif t.file then
		tex = t.file
	elseif t.sheet then
		tex = nhv_tiles.sheet_texture(tonumber(t.sheet) or 0)
	else
		tex = "nhvfx_dot.png"
	end
	local c = l.color or "#FFFFFF"
	if c:upper() ~= "#FFFFFF" then
		tex = "(" .. tex .. ")^[multiply:" .. c
	end
	return tex
end

local function range(r, d)
	r = type(r) == "table" and r or d
	return tonumber(r[1]) or d[1], tonumber(r[2]) or d[2]
end

-- one layer of particles around pos (the hero's / the event's feet)
local function spawn_layer(l, pos)
	local center = vector.add(pos, vector.new(0, tonumber(l.height) or 1, 0))
	local s1, s2 = range(l.speed, {1, 3})
	local e1, e2 = range(l.life, {0.5, 1.2})
	local z1, z2 = range(l.size, {1, 2})
	local spread = math.max(0.05, tonumber(l.spread) or 0.4)
	local g = tonumber(l.gravity) or 0
	local def = {
		amount = math.max(1, math.floor(tonumber(l.amount) or 30)),
		time = math.max(0.05, tonumber(l.duration) or 0.3),
		texture = {
			name = texture(l),
			alpha_tween = l.fade ~= false and {1, 0} or nil,
			blend = l.additive ~= false and "add" or "alpha",
		},
		glow = math.max(0, math.min(14, tonumber(l.glow) or 10)),
		exptime = {min = e1, max = e2},
		size = {min = z1, max = z2},
		acc = vector.new(0, -g, 0),
		collisiondetection = l.collide == true,
		collision_removal = l.collide == true,
	}
	local shape = l.shape or "burst"
	if shape == "burst" or shape == "ring" then
		-- start on a small shell and get pushed straight out of it: the
		-- push is (strength x distance), so strength = speed / distance
		local r = math.max(0.05, spread * 0.5)
		local c = r / math.sqrt(shape == "ring" and 2 or 3)
		def.pos = center
		def.radius = vector.new(c, shape == "ring" and 0 or c, c)
		def.attract = {kind = "point", origin = center, strength = {min = -s2 / r, max = -s1 / r}}
	elseif shape == "implode" then
		local c = spread / math.sqrt(3)
		def.pos = center
		def.radius = vector.new(c, c, c)
		def.attract = {kind = "point", origin = center, die_on_contact = true,
			strength = {min = s1 / spread, max = s2 / spread}}
	elseif shape == "rain" then
		def.pos = {min = vector.add(center, vector.new(-spread, 1.5, -spread)),
			max = vector.add(center, vector.new(spread, 2.0, spread))}
		def.vel = {min = vector.new(0, -s2, 0), max = vector.new(0, -s1, 0)}
	else -- rise
		def.pos = {min = vector.add(center, vector.new(-spread, 0, -spread)),
			max = vector.add(center, vector.new(spread, 0.2, spread))}
		def.vel = {min = vector.new(-0.15 * s1, s1, -0.15 * s1), max = vector.new(0.15 * s1, s2, 0.15 * s1)}
	end
	core.add_particlespawner(def)
end

function effects.play(id, pos)
	local e = effects.list[id]
	if not e or not pos then
		return
	end
	for _, l in ipairs(e.layers or {}) do
		spawn_layer(l, pos)
	end
end

-- a hook happened (called from sound.hook): play what's attached to it
function effects.hook(id, opts)
	local ids = effects.by_hook[id]
	if not ids then
		return
	end
	local pos = opts and opts.pos
	if not pos then
		local p = nhv.player.get()
		pos = p and p:get_pos()
	end
	for _, eid in ipairs(ids) do
		effects.play(eid, pos)
	end
end

return effects
