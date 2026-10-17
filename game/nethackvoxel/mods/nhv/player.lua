-- The hero's body.
--
-- You move freely; NetHack only needs to know which square you are in.
-- Crossing into another square sends "#nhvmove x y", which costs no time
-- (time flows through the clock). If NetHack refuses the square (a
-- monster is there, you're stuck, ...) you are put back; if NetHack moves
-- the hero somewhere else (trap door, teleport) the body follows.

local U = nhv.util
local nh = nhv.nh
local terrain = nhv.terrain

local player_mod = {
	hero = nil,
	frozen = false,
	ledger = nil,
	grace_until = 0,
}
nhv.player = player_mod

local GRACE_US = 400000 -- after we move the body, ignore stale positions

function player_mod.get()
	return core.get_connected_players()[1]
end

function player_mod.look_dir_key(player)
	local pitch = player:get_look_vertical()
	if pitch > 1.0 then
		return ">"
	elseif pitch < -1.0 then
		return "<"
	end
	local dx, dy = U.vec_to_dir(player:get_look_dir())
	return U.dir_key(dx, dy)
end

-- Is a node something you can't stand inside? (unloaded = blocked)
local function solid(p)
	local def = core.registered_nodes[core.get_node(p).name]
	return not def or def.walkable
end

-- The nearest place a body fits (two open nodes, feet and head) to pos,
-- preferring ones with something to stand on: so being placed on a square
-- whose prefab has a pillar or furniture in the middle doesn't put you
-- inside it. Returns pos itself when that's already free.
function player_mod.free_spot(pos)
	local fy = math.floor(pos.y + 0.5) -- node your feet are in
	local function fits(x, y, z)
		return not solid(vector.new(x, y, z)) and not solid(vector.new(x, y + 1, z))
	end
	local cx, cz = math.floor(pos.x + 0.5), math.floor(pos.z + 0.5)
	if fits(cx, fy, cz) then
		return pos
	end
	local best, bd
	for r = 1, 4 do
		for dx = -r, r do
			for dz = -r, r do
				if math.max(math.abs(dx), math.abs(dz)) == r then
					for _, dy in ipairs({0, 1, -1}) do
						local x, y, z = cx + dx, fy + dy, cz + dz
						if fits(x, y, z) then
							local d = dx * dx + dz * dz + dy * dy * 2
								+ (solid(vector.new(x, y - 1, z)) and 0 or 6) -- floor under you
							if not bd or d < bd then
								best, bd = vector.new(x, y - 0.5, z), d
							end
						end
					end
				end
			end
		end
		if best then
			return best
		end
	end
	return pos
end

local function teleport(player, pos)
	player:set_pos(player_mod.free_spot(pos))
	if nhv.effects then
		nhv.effects.arrived() -- (teleport effects play where you arrive)
	end
	-- on a new level the blocks are built just after this: check again then
	core.after(0.1, function()
		if player:is_player() then
			local p = player:get_pos()
			local f = player_mod.free_spot(p)
			if not vector.equals(f, p) then
				player:set_pos(f)
			end
		end
	end)
	player_mod.grace_until = core.get_us_time() + GRACE_US
end
player_mod.teleport = teleport

-- pet id -> time until which it counts as in the way (it wouldn't swap)
player_mod.unswappable = {}

local function stuck(h)
	return U.has(h.flags, U.HERO.TRAPPED) or U.has(h.flags, U.HERO.SWALLOWED)
		or U.has(h.flags, U.HERO.HELD)
end

local function set_speed(player)
	local h = player_mod.hero
	-- NetHack speed, slowed by what you carry (see clock.move_speed)
	local speed = nhv.clock.move_speed() / 12
	if h and stuck(h) then
		speed = 0
	end
	if player_mod.frozen or nhv.clock.searching() then
		speed = 0 -- (a prompt is up; searching)
	end
	-- Only the walking speeds change: the engine's "speed" also scales how
	-- fast you speed up AND slow down, so at 0 you'd keep sliding at
	-- whatever speed you had (caught in a web mid-step...) forever.
	-- (no sneaking: Shift is for the action wheel and firing, and must not
	-- stop you walking off ledges into pits)
	player:set_physics_override({speed = 1, speed_walk = speed, speed_fast = speed,
		speed_crouch = speed, jump = 0, sneak = false, sneak_glitch = false,
		new_move = true, gravity = h and 1 or 0})
end

function player_mod.freeze(on)
	if player_mod.frozen ~= on then
		player_mod.frozen = on
		local p = player_mod.get()
		if p then
			set_speed(p)
		end
	end
end

-- direction the player is trying to walk (from the movement keys)
local function intended_dir(player)
	local c = player:get_player_control()
	local f = (c.up and 1 or 0) - (c.down and 1 or 0)
	local r = (c.right and 1 or 0) - (c.left and 1 or 0)
	if f == 0 and r == 0 then
		return nil
	end
	local yaw = player:get_look_horizontal()
	local fx, fz = -math.sin(yaw), math.cos(yaw)
	local rx, rz = math.cos(yaw), math.sin(yaw)
	local v = vector.new(fx * f + rx * r, 0, fz * f + rz * r)
	return vector.normalize(v)
end

-- Why you can't squeeze through, in NetHack's order (cant_squeeze_thru):
-- too big a form, carrying too much, Sokoban. what = "corner" (a gap
-- between two walls: NetHack's own words) or "boulder".
local SQUEEZE_MSG = {
	corner = {big = "Your body is too large to fit through.",
		heavy = "You are carrying too much to get through.",
		soko = "You cannot pass that way."},
	boulder = {big = "Your body is too large to squeeze past the boulder.",
		heavy = "You are carrying too much to squeeze past the boulder.",
		soko = "You cannot squeeze past the boulder here."},
}
function player_mod.squeeze_reason(snap, what)
	local carried = 0
	for _, o in ipairs(snap and snap.inventory or {}) do
		carried = carried + (o.weight or 0)
	end
	local h = snap and snap.hero
	local soko = h and (h.dungeon_name or ""):find("Sokoban") ~= nil
	local why = "big"
	if carried > 600 then
		why = "heavy"
	elseif soko then
		why = "soko"
	end
	return SQUEEZE_MSG[what or "corner"][why]
end

-- (said when you press against it, now and then; not while you keep on)
local squeeze_told = 0
local function tell_squeeze(what)
	if core.get_us_time() > squeeze_told then
		nhv.hud.message(player_mod.squeeze_reason(nh.snap, what))
	end
	squeeze_told = core.get_us_time() + 3000000
end

-- walking into a corner gap that's closed (you can't squeeze through)
local function check_gap(player)
	if not player_mod.nosqueeze then
		return
	end
	local dir = intended_dir(player)
	if not dir then
		return
	end
	local p = vector.add(player:get_pos(), vector.new(dir.x * 0.5, 1, dir.z * 0.5))
	if core.get_node(vector.round(p)).name == "nhv:squeeze_block" then
		tell_squeeze("corner")
	end
end

-- Walking into a boulder (which is solid) tries to push it.
local push_next = 0
local function try_push(player)
	local dir = intended_dir(player)
	if not dir or core.get_us_time() < push_next then
		return false
	end
	local h = player_mod.hero
	local pos = player:get_pos()
	for _, e in pairs(nhv.mobs.objs) do
		if e.boulder and e.x and math.abs(e.x - h.x) <= 1 and math.abs(e.y - h.y) <= 1
				and not (e.x == h.x and e.y == h.y) and e.obj:get_pos() then
			local bp = e.obj:get_pos()
			local w = e.bw or e.h * 0.45
			-- gap between the player's body and the boulder's box
			local gx = math.max(0, math.abs(bp.x - pos.x) - w - 0.35)
			local gz = math.max(0, math.abs(bp.z - pos.z) - w - 0.35)
			local to = vector.normalize(vector.new(bp.x - pos.x, 0, bp.z - pos.z))
			if core.settings:get_bool("nhv_debug") then
				core.log("action", ("[nhv] push? gap %.2f,%.2f dot(to body) %.2f boulder %d,%d hero %d,%d"):format(
					gx, gz, vector.dot(to, dir), e.x, e.y, h.x, h.y))
			end
			-- walking the way NetHack would push it (from your square to its
			-- square: the line through the squares, not to the boulder's
			-- middle, so where along its side you touch it doesn't matter);
			-- squeezing past it at an angle doesn't push it. A boulder
			-- diagonally ahead (a corridor bending diagonally) can't be
			-- squeezed past, and walls keep you from reaching it: more reach
			local diag = e.x ~= h.x and e.y ~= h.y
			local reach = diag and 0.6 or 0.15
			-- (rock, a wall or bars beyond it: it can't roll there, so you're
			-- squeezing past it, not pushing; a boulder beyond is still tried:
			-- NetHack shows it then)
			local bx, by = 2 * e.x - h.x, 2 * e.y - h.y
			local beyond = U.in_map(bx, by) and nh.snap and nh.snap.map.typ[U.idx(bx, by)]
			if not beyond or beyond < U.TYP.POOL or beyond == U.TYP.IRONBARS then
				reach = -1
			end
			local push_dir = vector.normalize(vector.new(e.x - h.x, 0, -(e.y - h.y)))
			if gx < reach and gz < reach and vector.dot(push_dir, dir) > 0.86
					and vector.dot(to, dir) > 0 then
				push_next = core.get_us_time() + 400000
				core.log("action", ("[nhv] push: boulder %d,%d from %d,%d"):format(e.x, e.y, h.x, h.y))
				nh.act({{key = "#"}, {text = ("nhvmove %d %d"):format(e.x, e.y)}},
					{kind = "push", tx = e.x, ty = e.y, from_x = h.x, from_y = h.y})
				return true
			end
			-- (pressing against its side, trying to get past it, when you
			-- can't squeeze past: say why)
			if player_mod.nosqueeze and gx < 0.15 and gz < 0.15 and vector.dot(to, dir) > 0.3 then
				tell_squeeze("boulder")
			end
		end
	end
	return false
end

local step_dist, step_last = 0, nil
local function footsteps(player)
	local pos = player:get_pos()
	if step_last then
		local d = math.sqrt((pos.x - step_last.x) ^ 2 + (pos.z - step_last.z) ^ 2)
		if d < 2 then
			step_dist = step_dist + d
		end
	end
	step_last = pos
	if step_dist >= 1.6 then
		step_dist = 0
		nhv.sound.hook("footstep")
	end
end

local function step(player)
	local h = player_mod.hero
	footsteps(player)
	if not h or not nh.ready() then
		return
	end
	if core.get_us_time() < player_mod.grace_until then
		return
	end
	if try_push(player) then
		return
	end
	local pos = player:get_pos()
	local tx, ty = U.pos_to_tile(pos)
	if tx == h.x and ty == h.y then
		player_mod.ahead = nil
		return
	end
	-- after pushing a boulder the hero is a square ahead of the body;
	-- give the body a moment to walk in before syncing back
	local ahead = player_mod.ahead
	if ahead and tx == ahead.from_x and ty == ahead.from_y
			and core.get_us_time() < ahead.t_end then
		return
	end
	player_mod.ahead = nil
	if not U.in_map(tx, ty) then
		return
	end
	-- NetHack refused that square a moment ago (someone is standing in
	-- it, ...): the body just stays where it is; try again shortly
	if player_mod.retry_at and core.get_us_time() < player_mod.retry_at then
		return
	end
	player_mod.retry_at = nil
	local far = math.max(math.abs(tx - h.x), math.abs(ty - h.y)) > 1
	-- the body got away from the hero (NetHack kept refusing, or the
	-- path back is gone): put it back, so the two never part for good
	if far and (player_mod.refusals or 0) >= 2 then
		player_mod.refusals = 0
		teleport(player, U.tile_center(h.x, h.y))
		return
	end
	-- the body only grazes a boulder's square (its solid part is narrower
	-- than the square, to squeeze past it): that's no push (try_push does
	-- those, walking into it head-on); wait for the body to come out
	local function boulder_at(x, y)
		local e = nhv.mobs.objs[U.idx(x, y)]
		return e and e.boulder
	end
	-- someone NetHack won't let you step onto: not a pet you swap places
	-- with - unless it just wouldn't swap (eating, trapped, ...)
	local function blocker_at(x, y)
		local e = nhv.mobs.monster_at(x, y)
		if not (e and e.id and e.id > 0) then
			return false
		end
		if U.has(e.mon and e.mon.flags or 0, U.MON_PET) then
			return (player_mod.unswappable[e.id] or 0) > core.get_us_time()
		end
		return true
	end
	-- (the body is beside a boulder or walking past someone, in their
	-- square: wait for it to come out the other side)
	if boulder_at(tx, ty) or blocker_at(tx, ty) then
		return
	end
	-- catch up a square at a time along a path NetHack allows: around
	-- boulders (squeezing past them diagonally is fine) and monsters, no
	-- diagonal steps into or out of a doorway with a door (e.g. a shop's)
	local map = nh.snap and nh.snap.map
	local function find(around_monsters)
		return map and nhv.path.find(h.x, h.y, tx, ty,
			function(x, y)
				return terrain.passable(map, x, y) and not boulder_at(x, y)
					and not (around_monsters and blocker_at(x, y))
			end,
			function(x, y)
				return terrain.is_door(map, x, y) and (map.door[U.idx(x, y)] or 0) >= 2
			end, 300, not U.has(h.flags, U.HERO.NOSQUEEZE))
	end
	local route = find(true)
	if not (route and route[1]) then
		-- someone in the way (a 1-wide corridor): you walked past them in
		-- 3D, so NetHack moves you two squares at once, over them
		local past = find(false)
		if past and past[2] and blocker_at(past[1].x, past[1].y) then
			local to = past[2]
			nh.act({{key = "#"}, {text = ("nhvpass %d %d"):format(to.x, to.y)}},
				{kind = "hmove", tx = to.x, ty = to.y, from_x = h.x, from_y = h.y})
			return
		end
	end
	if route and route[1] then
		tx, ty = route[1].x, route[1].y
	elseif far then
		player_mod.refusals = 2 -- (no way back: put the body back next step)
		return
	else
		tx = h.x + U.sign(tx - h.x)
		ty = h.y + U.sign(ty - h.y)
	end
	nh.act({{key = "#"}, {text = ("nhvmove %d %d"):format(tx, ty)}},
		{kind = "hmove", tx = tx, ty = ty, from_x = h.x, from_y = h.y})
end

-- escape attempts while stuck in a trap or held by a monster: walking
-- costs a real move (NetHack decides whether you get free)
local escape_next = 0
local function try_escape(player)
	local h = player_mod.hero
	if not h or not nh.ready()
			or not (U.has(h.flags, U.HERO.TRAPPED) or U.has(h.flags, U.HERO.HELD)) then
		return
	end
	local c = player:get_player_control()
	if not (c.up or c.down or c.left or c.right) or nhv.clock.busy() then
		return
	end
	if core.get_us_time() < escape_next then
		return
	end
	escape_next = core.get_us_time() + 300000
	-- (the way the movement keys point: walking backwards or sideways
	-- away from a mimic tries to pull free; toward it attacks it, as in
	-- NetHack)
	local dir = intended_dir(player)
	local dx, dy = 0, 0
	if dir then
		dx, dy = U.vec_to_dir(dir)
	end
	if dx ~= 0 or dy ~= 0 then
		nhv.clock.act(U.dir_key(dx, dy), {kind = "escape"})
	end
end

-- after NetHack resolved something
nh.on_snapshot(function(snap, action)
	if not snap then
		return
	end
	local player = player_mod.get()
	local h = snap.hero
	local prev = player_mod.hero
	player_mod.hero = h
	if not player then
		return
	end
	set_speed(player)
	-- squeezing past boulders and through tight corners: while it isn't
	-- possible boulders get their full width and corner gaps close (what
	-- stops you is said when you try)
	local nosq = U.has(h.flags, U.HERO.NOSQUEEZE)
	player_mod.nosqueeze = nosq
	terrain.set_nosqueeze(nosq)
	if nosq then
		-- (standing in a corner gap as it filled: step out of it)
		local p = player:get_pos()
		local f = player_mod.free_spot(p)
		if not vector.equals(f, p) then
			player:set_pos(f)
		end
	end
	-- confused / stunned: the NetHack Voxel build of Luanti scrambles the
	-- controls (rotated / reversed walking, inverted looking up and down)
	-- (and the screen waves; hallucinating, it waves and its colours drift)
	local conf, stun = U.has(h.flags, U.HERO.CONF), U.has(h.flags, U.HERO.STUN)
	local hallu = U.has(h.flags, U.HERO.HALLU)
	if conf ~= player_mod.confused or stun ~= player_mod.stunned or hallu ~= player_mod.hallu then
		player_mod.confused, player_mod.stunned, player_mod.hallu = conf, stun, hallu
		player:hud_set_flags({nhv_confused = conf, nhv_stunned = stun, nhv_hallu = hallu})
	end
	local level_changed = player_mod.ledger ~= h.ledger
	player_mod.ledger = h.ledger

	if level_changed or not prev then
		teleport(player, U.tile_center(h.x, h.y))
	elseif action and action.kind == "push" then
		if h.x == action.tx and h.y == action.ty then
			-- (its sound: NetHack's boulder_push hook)
			player_mod.ahead = {from_x = action.from_x, from_y = action.from_y,
				t_end = core.get_us_time() + 1500000}
		else
			-- (what's really beyond it: terrain and objects, seen or not)
			local bx, by = 2 * action.tx - h.x, 2 * action.ty - h.y
			local beyond = "off the map"
			if U.in_map(bx, by) then
				local names = {}
				for _, o in ipairs(core.nh_get_floor_objects(bx, by) or {}) do
					names[#names + 1] = o.name
				end
				beyond = ("terrain %s, objects: %s"):format(tostring(snap.map.typ[U.idx(bx, by)]),
					#names > 0 and table.concat(names, "; ") or "none")
			end
			core.log("action", ("[nhv] push refused: boulder %d,%d, hero %d,%d; beyond (%d,%d): %s"):format(
				action.tx, action.ty, h.x, h.y, bx, by, beyond))
		end
	elseif action and action.kind == "hmove" then
		if h.x == action.from_x and h.y == action.from_y then
			-- (a pet there that wouldn't swap places - eating, trapped...: for
			-- a while it's in the way like anyone else, and walking past it
			-- moves you over it)
			local pet = nhv.mobs.monster_at(action.tx, action.ty)
			local by_pet = pet and pet.id and pet.id > 0 and U.has(pet.mon and pet.mon.flags or 0, U.MON_PET)
			if by_pet then
				player_mod.unswappable[pet.id] = core.get_us_time() + 4000000
			end
			-- refused: no teleporting the body back; retry later (step()
			-- puts it back if it keeps being refused while it walks off -
			-- not for the pet: you're moved over it instead)
			player_mod.retry_at = core.get_us_time() + 500000
			if not by_pet then
				player_mod.refusals = (player_mod.refusals or 0) + 1
			end
		else
			player_mod.refusals = 0
			if h.x ~= action.tx or h.y ~= action.ty then
				teleport(player, U.tile_center(h.x, h.y)) -- moved elsewhere
			end
		end
	elseif prev.x ~= h.x or prev.y ~= h.y then
		local tx, ty = U.pos_to_tile(player:get_pos())
		if tx ~= h.x or ty ~= h.y then
			teleport(player, U.tile_center(h.x, h.y))
		end
	end
end)

-- touching an nhv:trigger node uses the stairs/ladder it belongs to
local TRIGGER_KEYS = {
	stairs_down = ">", ladder_down = ">", stairs_up = "<", ladder_up = "<",
}
local in_trigger = false
local function check_trigger(player)
	local pos = player:get_pos()
	local touching = false
	for _, dy in ipairs({0.1, 0.9, 1.6}) do
		if core.get_node(vector.round(vector.new(pos.x, pos.y + dy, pos.z))).name == "nhv:trigger" then
			touching = true
			break
		end
	end
	if not touching then
		in_trigger = false
		return
	end
	if in_trigger or not nh.ready() then
		return
	end
	local h = player_mod.hero
	local slot = terrain.slot_at(h.x, h.y)
	local key = slot and TRIGGER_KEYS[slot]
	-- level 1's up stairs leave the dungeon (and end the game), which NetHack
	-- asks about; walking into the trigger never does that (right-click does)
	local snap_hero = nh.snap and nh.snap.hero
	if key == "<" and snap_hero and snap_hero.depth == 1 then
		key = nil
	end
	if key then
		in_trigger = true
		nhv.clock.act(key, {kind = "stairs"})
	end
end

-- Down in a pit (the body below the floor): NetHack is told, so the bottom
-- can be reached (picking things up there) - it doesn't trap you, climbing
-- out is ours (Space at the edge: actions.climb_out)
local pit_told = nil
local function tell_pit(player)
	local down = player:get_pos().y < U.STAND_Y - 1
	if down ~= pit_told and nh.ready() then
		pit_told = down
		nh.act({{key = "#"}, {text = "nhvpit " .. (down and 1 or 0)}}, {kind = "info"})
	end
end
nh.on_snapshot(function(snap)
	if not snap then
		pit_told = nil -- (a new game: tell it again)
	end
end)

-- Stuck (a trap, held by a monster, swallowed): the body is pinned in the
-- hero's square - where it is, if it's in it; else the nearest spot
-- inside it (the body may be a step ahead: walking into a mimic's square
-- before NetHack said it was one, onto a web it caught you in...).
local held_at = nil
local function hold_still(player)
	local h = player_mod.hero
	if not h or not stuck(h) then
		held_at = nil
		player_mod.held_at = nil
		return false
	end
	local pos = player:get_pos()
	-- (NetHack moved you while stuck - an engulfer carrying you along: the
	-- spot moves into your new square)
	if held_at and (held_at.tx ~= h.x or held_at.ty ~= h.y) then
		held_at = nil
	end
	if not held_at then
		local c = U.tile_center(h.x, h.y, pos.y)
		-- (the body stays inside the square; caught in a trap, near the
		-- middle of it, where the trap is)
		local m = U.has(h.flags, U.HERO.TRAPPED) and 0.5 or (U.TILE / 2 - 0.35)
		local function clamp(v)
			return math.max(-m, math.min(m, v))
		end
		held_at = vector.new(c.x + clamp(pos.x - c.x), pos.y, c.z + clamp(pos.z - c.z))
		held_at.tx, held_at.ty = h.x, h.y
	end
	player_mod.held_at = held_at
	if math.abs(pos.x - held_at.x) + math.abs(pos.z - held_at.z) > 0.03 then
		player:set_pos(vector.new(held_at.x, pos.y, held_at.z))
	end
	return true
end

local was_searching = false
core.register_globalstep(function()
	local player = player_mod.get()
	-- (searching started or ended: stand still / walk again)
	local searching = nhv.clock.searching()
	if player and searching ~= was_searching then
		was_searching = searching
		set_speed(player)
	end
	if player and nh.snap then
		try_escape(player)
		if not hold_still(player) then
			step(player)
		end
		check_gap(player)
		check_trigger(player)
		terrain.place_hero_light(player:get_pos())
		tell_pit(player)
	end
end)

core.register_on_joinplayer(function(player)
	player:set_physics_override({speed = 1, jump = 0})
	player:set_properties({
		eye_height = 1.6,
		collisionbox = {-0.35, 0, -0.35, 0.35, 1.75, 0.35},
		visual_size = {x = 0, y = 0},
		makes_footstep_sound = false,
	})
	player:set_sky({
		type = "plain", base_color = "#000000", clouds = false,
		fog = {fog_distance = 90, fog_start = 0.3},
	})
	player:set_sun({visible = false, sunrise_visible = false})
	player:set_moon({visible = false})
	player:set_stars({visible = false})
	player:set_clouds({density = 0})
	player:override_day_night_ratio(0)
	player:set_lighting({shadows = {intensity = 0}, saturation = 1})
end)

return player_mod
