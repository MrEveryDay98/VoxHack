-- Dodgeable missiles.
--
-- When a monster throws or shoots something at you, NetHack hands the
-- missile over instead of resolving it on the grid. It flies from the
-- thrower toward where you were, at game-time speed (so it crawls while
-- you stand still - step out of the way!). What it touches decides what
-- happens:
--   * your body: NetHack rolls to hit; if that fails you dodged it after
--     all ("Dodged!") and it flies on,
--   * a monster's body: NetHack rolls for that monster,
--   * a wall, or the end of its range: it drops there.
--
-- A boulder a rolling boulder trap sets rolling goes the same way: it rolls
-- along the ground at game-time speed, NetHack saying what happens as it
-- rolls into each square (monsters, traps, doors, walls), and it can only
-- hit you if its body reaches yours - step aside, or jump over it.

local U = nhv.util
local nh = nhv.nh
local missiles = {
	list = {},      -- pid -> flying missile
	rolls = {},     -- pid -> rolling boulder
	queue = {},     -- commands waiting for NetHack to be ready
}
nhv.missiles = missiles

missiles.SPEED = 15     -- nodes per game turn
local STEP = 0.25       -- collision check spacing (nodes)
local HERO_H = 1.8      -- hero body height

core.register_entity("nhv:missile", {
	initial_properties = {
		visual = "wielditem", wield_item = nhv_tiles.item(0),
		visual_size = {x = 0.35, y = 0.35, z = 0.35},
		physical = false, pointable = false, static_save = false,
	},
})

local function command(text)
	table.insert(missiles.queue, {{key = "#"}, {text = text}})
end

local function remove(m)
	if m.obj and m.obj:get_pos() then
		m.obj:remove()
	end
	missiles.list[m.pid] = nil
end

local function remove_roll(r)
	if r.obj and r.obj:get_pos() then
		r.obj:remove()
	end
	if r.hidden and r.hidden:get_pos() then
		r.hidden:set_properties({is_visible = true})
	end
	missiles.rolls[r.pid] = nil
	missiles.map_moved = true -- (off the map: missiles.update)
end

function missiles.clear()
	for _, m in pairs(missiles.list) do
		remove(m)
	end
	for _, r in pairs(missiles.rolls) do
		remove_roll(r)
	end
	missiles.list = {}
	missiles.rolls = {}
	missiles.queue = {}
end

-- ---------------------------------------------------------------- launching
local function launch(info)
	local player = nhv.player.get()
	if not player then
		return
	end
	local body = nhv.sim.body(info.mon_id)
	local from
	if info.mon_id and info.mon_id > 0 then
		nhv.mobs.flash(info.mon_id, "w", 0.12) -- (the thrower attacks)
	end
	if body then
		local h = nhv.scale.height(body.size, body.mndx)
		from = vector.new(body.pos.x, U.STAND_Y + h * 0.6, body.pos.z)
	else
		from = U.tile_center(info.x, info.y, U.STAND_Y + 1.2)
	end
	local target = vector.add(player:get_pos(), vector.new(0, 1.2, 0))
	local dir = vector.direction(from, target)
	-- start just outside the thrower's body
	local start = vector.add(from, vector.multiply(dir, body and (body.r + 0.2) or 0.5))
	local obj = core.add_entity(start, "nhv:missile")
	if obj then
		obj:set_properties(nhv_tiles.look(info.tile, 0.7))
		obj:set_yaw(math.atan2(dir.z, dir.x))
	end
	nhv.sound.hook("missile_launch", {pos = start})
	missiles.list[info.pid] = {
		pid = info.pid, obj = obj, pos = start, dir = dir, travelled = 0,
		range = (math.max(info.range, 1) + 1) * U.TILE, thrower = info.mon_id,
		passed = {}, waiting = false,
	}
end

-- ---------------------------------------------------------------- rolling boulders
missiles.ROLL_SPEED = 9 -- nodes per game turn (12 a second at full rate)
local BOULDER_H = 2.6   -- (as mobs.lua draws boulders)
local ROLL_R = 1.2      -- its body's radius (nodes): most of a square

core.register_entity("nhv:rolling", {
	initial_properties = {
		visual = "wielditem", wield_item = nhv_tiles.item(0),
		visual_size = {x = 0.5, y = 0.5, z = 0.5},
		physical = false, pointable = false, static_save = false,
		collisionbox = {0, 0, 0, 0, 0, 0}, shaded = true,
	},
})

local function dust(pos)
	core.add_particlespawner({
		amount = 30, time = 0.15, pos = pos, radius = vector.new(0.8, 0.2, 0.8),
		vel = {min = vector.new(-1.5, 0.3, -1.5), max = vector.new(1.5, 2, 1.5)},
		acc = vector.new(0, -3, 0), exptime = {min = 0.5, max = 1.1}, size = {min = 2, max = 4},
		texture = {name = "[fill:2x2:#8a8070", alpha_tween = {0.9, 0}, blend = "alpha"},
	})
end

local function roll_y()
	return U.STAND_Y + BOULDER_H / 2
end

local function start_roll(info)
	local pos = U.tile_center(info.x, info.y, roll_y())
	local obj = core.add_entity(pos, "nhv:rolling")
	if obj then
		-- (facing the camera, as boulders do: the engine turns it - mobs.lua)
		local props = nhv_tiles.look(info.tile, BOULDER_H)
		props.infotext = "nhv:billboard"
		obj:set_properties(props)
	end
	local dir = vector.direction(pos, U.tile_center(info.x + info.dx, info.y + info.dy, roll_y()))
	missiles.rolls[info.pid] = {pid = info.pid, obj = obj, pos = pos, dir = dir, tile = info.tile,
		x = info.x, y = info.y, dx = info.dx, dy = info.dy, waiting = false}
end

nh.on_snapshot(function(snap)
	if not snap or not nh.ready() then
		return
	end
	for _, info in ipairs(core.nh_get_missiles() or {}) do
		launch(info)
	end
	for _, info in ipairs(core.nh_get_rolls and core.nh_get_rolls() or {}) do
		start_roll(info)
	end
end)

-- ---------------------------------------------------------------- flying
local function solid_at(p)
	local node = core.get_node(vector.round(p))
	local def = core.registered_nodes[node.name]
	return def and def.walkable
end

local function hits_hero(p, hp)
	local dx, dz = p.x - hp.x, p.z - hp.z
	return dx * dx + dz * dz < (nhv.sim.HERO_R + 0.15) ^ 2
		and p.y >= hp.y and p.y <= hp.y + HERO_H
end

local function hits_body(p, e)
	local dx, dz = p.x - e.pos.x, p.z - e.pos.z
	if dx * dx + dz * dz >= (e.r + 0.15) ^ 2 then
		return false
	end
	local h = nhv.scale.height(e.size, e.mndx)
	return p.y >= U.STAND_Y and p.y <= U.STAND_Y + h
end

local function land(m, p)
	local tx, ty = U.pos_to_tile(p)
	command(("nhvmland %d %d %d"):format(m.pid, tx, ty))
	m.waiting = true
end

local function fly(m, dist, hp)
	while dist > 0 and not m.waiting do
		local d = math.min(STEP, dist)
		dist = dist - d
		local np = vector.add(m.pos, vector.multiply(m.dir, d))
		m.travelled = m.travelled + d
		if solid_at(np) or m.travelled > m.range then
			land(m, m.pos)
			return
		end
		m.pos = np
		if hp and not m.passed.hero and hits_hero(np, hp) then
			m.passed.hero = true
			m.waiting = true
			command(("nhvmhit %d"):format(m.pid))
			return
		end
		for id, e in pairs(nhv.sim.mons) do
			if not m.passed[id] and not (id == m.thrower and m.travelled < 1.5)
					and hits_body(np, e) then
				m.passed[id] = true
				m.waiting = true
				command(("nhvmhitm %d %d"):format(m.pid, id))
				return
			end
		end
	end
end

-- its body against yours (yours above its top - jumping over it - misses),
-- and only in the square it's rolling through: its path, as NetHack's. (A
-- square's 3 nodes across: beside its path - next to a diagonal one,
-- where squares touch at their corners - the two bodies could still meet.)
-- Never one rolling away from you: a boulder you pushed onto a rolling
-- boulder trap starts right in front of you, rolling off.
local function roll_touches(r, hp)
	local dx, dz = r.pos.x - hp.x, r.pos.z - hp.z
	if dx * dx + dz * dz >= (ROLL_R + nhv.sim.HERO_R) ^ 2 or hp.y >= r.pos.y + BOULDER_H / 2
			or -dx * r.dir.x - dz * r.dir.z <= 0 then
		return false
	end
	local rx, ry = U.pos_to_tile(r.pos)
	local hx, hy = U.pos_to_tile(hp)
	return rx == hx and ry == hy
end

-- The rolling boulders where they are, for the map (hud.lua): square index
-- -> {tile, pos} (NetHack's own boulder is off its map till it stops)
function missiles.rolling()
	local out = {}
	for _, r in pairs(missiles.rolls) do
		if r.obj and r.tile then
			local x, y = U.pos_to_tile(r.pos)
			if U.in_map(x, y) then
				out[U.idx(x, y)] = {tile = r.tile, pos = r.pos, pid = r.pid}
			end
		end
	end
	return out
end

-- on along the ground; into the next square: NetHack says what happens
-- there (#nhvbroll) - it waits for that. Stopped or gone: on to where,
-- then done.
local function roll(r, dist, hp)
	if hp and not r.touched and roll_touches(r, hp) then
		r.touched = true
		command(("nhvbhit %d"):format(r.pid))
	end
	if r.waiting then
		return
	end
	local goal = r.stop_at or U.tile_center(r.x + r.dx, r.y + r.dy, roll_y())
	local left = vector.distance(r.pos, goal)
	-- (into the next square: half way to its middle)
	local edge = r.stop_at and 0 or left - U.TILE * math.sqrt(r.dx * r.dx + r.dy * r.dy) / 2
	if not r.stop_at and dist >= edge then
		r.pos = vector.add(r.pos, vector.multiply(r.dir, math.max(0, edge)))
		r.waiting = true
		command(("nhvbroll %d"):format(r.pid))
		return
	end
	if dist >= left then
		r.pos = goal
		if r.gone then
			dust(goal)
		end
		remove_roll(r)
		return
	end
	r.pos = vector.add(r.pos, vector.multiply(r.dir, dist))
end

-- called by the game loop with the game time that passed
function missiles.update(dturns)
	local player = nhv.player.get()
	local hp = player and player:get_pos()
	for _, m in pairs(missiles.list) do
		if not m.waiting then
			fly(m, missiles.SPEED * dturns, hp)
			if m.obj and m.obj:get_pos() then
				m.obj:move_to(m.pos, true)
			end
		end
	end
	for _, r in pairs(missiles.rolls) do
		roll(r, missiles.ROLL_SPEED * dturns, hp)
		-- (into another square: the map shows it there - hud.lua)
		local sx, sy = U.pos_to_tile(r.pos)
		if r.sq ~= sx .. "," .. sy then
			r.sq, missiles.map_moved = sx .. "," .. sy, true
		end
		if r.obj and r.obj:get_pos() then
			r.obj:move_to(r.pos, true)
		end
	end
	if missiles.map_moved then
		missiles.map_moved = false
		nhv.hud.redraw_map()
	end
	-- outcomes need NetHack; these take no game time
	while #missiles.queue > 0 and nh.ready() do
		nh.act(table.remove(missiles.queue, 1), {kind = "missile"})
	end
end

-- ---------------------------------------------------------------- outcomes
-- floating "Dodged!" that drifts up and fades
local floaters = {}
function missiles.float_text(text, color)
	local player = nhv.player.get()
	if not player then
		return
	end
	local id = player:hud_add({
		type = "text", position = {x = 0.5, y = 0.5}, alignment = {x = 0, y = 0},
		offset = {x = 0, y = -30}, number = color or 0x80FF80, text = text,
		size = {x = 2, y = 2}, z_index = 50,
	})
	table.insert(floaters, {id = id, t = 0})
end

core.register_globalstep(function(dtime)
	local player = nhv.player.get()
	if not player then
		return
	end
	for i = #floaters, 1, -1 do
		local f = floaters[i]
		f.t = f.t + dtime
		if f.t > 1.0 then
			player:hud_remove(f.id)
			table.remove(floaters, i)
		else
			player:hud_change(f.id, "offset", {x = 0, y = -30 - f.t * 80})
		end
	end
end)

-- what NetHack said of a rolling boulder: "roll <what> <pid> <x> <y>"
local function rolled(what, r, x, y)
	if what == "on" then
		r.x, r.y, r.waiting = x, y, false
	elseif what == "stop" or what == "gone" then
		-- (on to the middle of that square, then done; the boulder NetHack
		-- put there stays out of sight until this one's there)
		r.stop_at, r.gone, r.waiting = U.tile_center(x, y, roll_y()), what == "gone", false
		r.dir = vector.direction(r.pos, r.stop_at)
		local there = what == "stop" and nhv.mobs.objs and nhv.mobs.objs[U.idx(x, y)]
		if there and there.obj and there.obj:get_pos() then
			r.hidden = there.obj
			r.hidden:set_properties({is_visible = false})
		end
		nhv.sound.hook("missile_land", {pos = r.pos})
	elseif what == "miss" then
		missiles.float_text("Dodged!")
		nhv.sound.hook("missile_dodged")
	elseif what == "hit" then
		nhv.sound.hook("missile_hit")
	end
end

nh.on_event(function(evs)
	for _, ev in ipairs(evs) do
		local rwhat, rpid, x, y
		if ev.kind == "missile" then
			rwhat, rpid, x, y = ev.text:match("^roll (%a+) (%d+) (%-?%d+) (%-?%d+)$")
		end
		local r = rpid and missiles.rolls[tonumber(rpid)]
		if r then
			rolled(rwhat, r, tonumber(x), tonumber(y))
		elseif ev.kind == "missile" and not rwhat then
			local what, pid = ev.text:match("^(%a+) (%d+)$")
			local m = pid and missiles.list[tonumber(pid)]
			if m then
				if what == "miss" then
					missiles.float_text("Dodged!")
					nhv.sound.hook("missile_dodged")
					m.waiting = false
				elseif what == "pass" then
					m.waiting = false
				else -- hit, stop, land
					if what == "hit" then
						nhv.sound.hook("missile_hit")
					elseif what == "land" then
						nhv.sound.hook("missile_land", {pos = m.pos})
					end
					remove(m)
				end
			end
		end
	end
end)

return missiles
