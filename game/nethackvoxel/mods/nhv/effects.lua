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
local U = nhv.util

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
	-- (see-through: big soft clouds)
	local op = tonumber(l.opacity) or 100
	if op < 100 then
		tex = "(" .. tex .. ")^[opacity:" .. math.floor(math.max(0, op) * 2.55 + 0.5)
	end
	return tex
end

local function range(r, d)
	r = type(r) == "table" and r or d
	return tonumber(r[1]) or d[1], tonumber(r[2]) or d[2]
end

-- one layer of particles around pos (the hero's / the event's feet);
-- looping, it never stops (at the same rate: amount per duration) until
-- core.delete_particlespawner(the id it returns)
local function spawn_layer(l, pos, looping)
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
			-- (fading out as it goes, in as it comes - or both: up and
			-- down again over its life)
			alpha_tween = (l.fade ~= false and l.fade_in) and {0, 1, style = "pulse", reps = 1}
				or l.fade ~= false and {1, 0} or l.fade_in and {0, 1} or nil,
			blend = l.additive ~= false and "add" or "alpha",
		},
		glow = math.max(0, math.min(14, tonumber(l.glow) or 10)),
		exptime = {min = e1, max = e2},
		size = {min = z1, max = z2},
		acc = vector.new(0, -g, 0),
		collisiondetection = l.collide == true,
		collision_removal = l.collide == true,
	}
	if looping then
		def.amount = math.max(1, def.amount / def.time) -- (per second, forever)
		def.time = 0
	end
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
	return core.add_particlespawner(def)
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
-- Hooks that move you somewhere else: their effects play where you arrive,
-- when your body gets there (the hook fires before you're moved - with
-- teleport control, before you've even chosen where; on another level,
-- once it's built); after a few seconds anyway. The same effect from two
-- of them at once plays once.
local ARRIVAL = {teleport = true, trap_teleportation_trap = true,
	trap_level_teleporter = true, trap_magic_portal = true}
local ARRIVAL_WAIT = 5
local arriving = {} -- effect id -> time it was asked for

local function arrive(eid)
	if arriving[eid] then
		arriving[eid] = nil
		local p = nhv.player.get()
		if p then
			effects.play(eid, p:get_pos())
		end
	end
end

-- your body was moved (player.lua): the effects waiting for that play now
function effects.arrived()
	for eid in pairs(arriving) do
		core.after(0.1, arrive, eid) -- (once the body is there)
	end
end

function effects.hook(id, opts)
	local ids = effects.by_hook[id]
	if not ids then
		return
	end
	if ARRIVAL[id] then
		for _, eid in ipairs(ids) do
			if not arriving[eid] then
				local asked = core.get_us_time()
				arriving[eid] = asked
				core.after(ARRIVAL_WAIT, function()
					if arriving[eid] == asked then
						arrive(eid)
					end
				end)
			end
		end
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

-- Loops: lasting things that the effects with their trigger (the editor's
-- "Loops" group) play on without a break while they last - NetHack's gas
-- clouds (a poison breath's, a scroll of stinking cloud's...): every square
-- the map shows inside one, near you (CLOUD_NEAR squares), as never-ending
-- spawners, removed when the gas goes (or the effect is edited)
local CLOUD_LOOPS = {S_poisoncloud = "cloud_poison_gas", S_cloud = "cloud_vapour"}
local CLOUD_NEAR = 20
local clouds = {} -- square index -> {eid=, e= (the effect as played), ids={spawner ids}}

local function cloud_stop(i)
	for _, id in ipairs(clouds[i].ids) do
		core.delete_particlespawner(id)
	end
	clouds[i] = nil
end

local cloud_scan = 0
core.register_globalstep(function(dtime)
	cloud_scan = cloud_scan - dtime
	if cloud_scan > 0 then
		return
	end
	cloud_scan = 0.25
	local snap = nhv.nh.snap
	local map, h = snap and snap.map, snap and snap.hero
	local live = {}
	if map and map.glyph and h and h.x then
		for x = math.max(1, h.x - CLOUD_NEAR), math.min(U.COLNO - 1, h.x + CLOUD_NEAR) do
			for y = math.max(0, h.y - CLOUD_NEAR), math.min(U.ROWNO - 1, h.y + CLOUD_NEAR) do
				local i = U.idx(x, y)
				local gi = nhv.glyph_info(map.glyph[i])
				local hook = gi.kind == "cmap" and CLOUD_LOOPS[nhv.cmap_name(gi.index)]
				local eid = hook and effects.by_hook[hook] and effects.by_hook[hook][1]
				local e = eid and effects.list[eid]
				if e then
					live[i] = true
					if clouds[i] and (clouds[i].eid ~= eid or clouds[i].e ~= e) then
						cloud_stop(i) -- (another cloud, or the effect was edited)
					end
					if not clouds[i] then
						local c = {eid = eid, e = e, ids = {}}
						local pos = U.tile_center(x, y, U.STAND_Y)
						for _, l in ipairs(e.layers or {}) do
							c.ids[#c.ids + 1] = spawn_layer(l, pos, true)
						end
						clouds[i] = c
					end
				end
			end
		end
	end
	for i in pairs(clouds) do
		if not live[i] then
			cloud_stop(i)
		end
	end
end)

return effects
