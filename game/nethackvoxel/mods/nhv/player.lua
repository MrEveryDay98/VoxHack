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
	-- (NetHack put you there - arriving, a teleport: any trap there has
	-- gone off already; the body landing on its pad isn't stepping on it)
	local tx, ty = U.pos_to_tile(pos)
	player_mod.trap_done = tx .. "," .. ty
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

-- NetHack moved the hero from square (fx, fy) to h without your walking
-- there: the body is put there (the Plane of Water's bubbles don't carry
-- the hero: their drift carries the body, and it walks - bubbles.lua)
local function moved_by_nethack(player, h)
	teleport(player, U.tile_center(h.x, h.y))
end

-- NetHack saying you're falling to the level below (through a hole or a
-- trap door, a hole dug in the floor): the level change that follows
-- drops you in from above
local FALLING = {"opens up under you", "gaping hole under you", "down a .*shaft",
	"deliberately drop down", "swoop down through"}
nh.on_event(function(evs)
	for _, ev in ipairs(evs) do
		if ev.kind == "message" then
			for _, pat in ipairs(FALLING) do
				if ev.text:find(pat) then
					player_mod.falling_until = core.get_us_time() + 3000000
				end
			end
		end
	end
end)

-- A level change isn't instant. NetHack has already moved you, but its
-- snapshot is held back (nh.lua) while the view freezes and fades to black;
-- the new level is built under the black, you're held still while its
-- blocks reach the screen (all of them: core.nh_level_progress), and it
-- fades back in. Falling through a hole
-- or trap door, you first drop into it on this level for half a second (a
-- trap door's hatch opening under you), fading as you fall; on the new level
-- you then drop in from above as it fades in.
local FALL_S = 0.5
local FADE_OUT_S, FADE_IN_S = 0.3, 0.4
-- black at least this long, and at most this long if the level's blocks
-- are slow to come
local BLACK_MIN_S, BLACK_MAX_S = 0.15, 5
nh.hold_level_change = function(old)
	local falling = core.get_us_time() < (player_mod.falling_until or 0)
	local p = player_mod.get()
	local h = old and old.hero
	if not (p and h) then
		return 0
	end
	if not falling then
		-- (still while the view fades: the new level, when it comes,
		-- freezes you again where you arrive)
		local now = core.get_us_time()
		player_mod.level_hold = {t0 = now, t_end = now + (FADE_OUT_S + 1) * 1e6, pos = p:get_pos()}
		nhv.hud.fade(1, FADE_OUT_S)
		return FADE_OUT_S
	end
	nhv.hud.fade(1, FALL_S)
	-- the floor of the square gives way (the new level replaces it all anyway)
	local c = U.tile_center(h.x, h.y)
	local half = math.floor(U.TILE / 2)
	for dx = -half, half do
		for dz = -half, half do
			for y = U.FLOOR_Y - 6, U.FLOOR_Y do
				local pos = vector.new(c.x + dx, y, c.z + dz)
				local def = core.registered_nodes[core.get_node(pos).name]
				if def and def.walkable then
					core.set_node(pos, {name = "air"})
				end
			end
		end
	end
	p:add_velocity(vector.new(0, -5, 0))
	return FALL_S
end

-- pet id -> time until which it counts as in the way (it wouldn't swap)
player_mod.unswappable = {}

local function stuck(h)
	return U.has(h.flags, U.HERO.TRAPPED) or U.has(h.flags, U.HERO.SWALLOWED)
		or U.has(h.flags, U.HERO.HELD) or U.has(h.flags, U.HERO.HELPLESS)
end

-- levitating: you float a little over the ground (hover, below) - and on
-- the Planes of Air and Water, in thin air or open water with no ground at
-- all, you do too (off the ground the engine doesn't bob the view and the
-- weapon as you walk)
local function levitating(h)
	return h and (U.has(h.flags, U.HERO.LEVITATE) or (nhv.terrain and nhv.terrain.sky_floor)) or false
end

local function set_speed(player)
	local h = player_mod.hero
	-- NetHack speed, slowed by what you carry (see clock.move_speed) - and
	-- in the Plane of Air's thin air (clock.walk_speed)
	local speed = nhv.clock.walk_speed() / 12
	if h and stuck(h) then
		speed = 0
	end
	if player_mod.frozen or nhv.clock.searching() or (nhv.cutscene and nhv.cutscene.active) then
		speed = 0 -- (a prompt is up; searching; a cutscene)
	end
	-- Only the walking speeds change: the engine's "speed" also scales how
	-- fast you speed up AND slow down, so at 0 you'd keep sliding at
	-- whatever speed you had (caught in a web mid-step...) forever.
	-- (no sneaking: Shift is for the action wheel and firing, and must not
	-- stop you walking off ledges into pits)
	player:set_physics_override({speed = 1, speed_walk = speed, speed_fast = speed,
		speed_crouch = speed, jump = 0, sneak = false, sneak_glitch = false,
		new_move = true, gravity = ((h and not levitating(h)) and 1 or 0) * (player_mod.hop_g or 1)})
end

-- A jump (hold Space: jump.lua): the body hops to where NetHack landed
-- you - fast, a short arc (gravity turned up for it, so it's quick and
-- still clears the floor), then set down exactly on the square
local HOP_S, HOP_G = 0.42, 3
function player_mod.hop(player, to)
	local tx, ty = U.pos_to_tile(to)
	player_mod.trap_done = tx .. "," .. ty -- (NetHack set off any trap there)
	local from = player:get_pos()
	local g = (tonumber(core.settings:get("movement_gravity")) or 9.81) * HOP_G
	local v = vector.new((to.x - from.x) / HOP_S, g * HOP_S / 2 + (to.y - from.y) / HOP_S,
		(to.z - from.z) / HOP_S)
	player_mod.hop_g = HOP_G
	set_speed(player)
	player:add_velocity(vector.subtract(v, player:get_velocity()))
	player_mod.grace_until = core.get_us_time() + (HOP_S + 0.3) * 1e6
	core.after(HOP_S + 0.1, function()
		player_mod.hop_g = nil
		if player:is_player() then
			set_speed(player)
			local p = player:get_pos()
			if math.abs(p.x - to.x) + math.abs(p.z - to.z) > 0.4 then
				player:set_pos(player_mod.free_spot(vector.new(to.x, math.max(p.y, to.y), to.z)))
			end
		end
	end)
end

-- (walking speed worked out again: a cutscene started or ended)
function player_mod.refresh_speed()
	local p = player_mod.get()
	if p then
		set_speed(p)
	end
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
	-- (no feet on the ground: no steps)
	local h = player_mod.hero
	if h and (U.has(h.flags, U.HERO.LEVITATE) or U.has(h.flags, U.HERO.FLYING)) then
		step_last, step_dist = pos, 0
		return
	end
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
	-- someone whose square you can't walk into: you share squares with
	-- monsters (#nhvmove moves you in among them), but a shopkeeper stands
	-- where it does to bar the way
	local function blocker_at(x, y)
		local e = nhv.mobs.monster_at(x, y)
		return e and e.id and e.id > 0 and U.has(e.mon and e.mon.flags or 0, U.MON_SHOPKEEPER) or false
	end
	-- a pet that wouldn't swap places a moment ago: share its square instead
	local function stubborn_pet_at(x, y)
		local e = nhv.mobs.monster_at(x, y)
		return e and e.id and e.id > 0 and U.has(e.mon and e.mon.flags or 0, U.MON_PET)
			and (player_mod.unswappable[e.id] or 0) > core.get_us_time() or false
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
		-- (past a whole line of them: every square to the first free one)
		local k = 1
		while past and past[k] and blocker_at(past[k].x, past[k].y) and k < 7 do
			k = k + 1
		end
		if past and k > 1 and past[k] and not blocker_at(past[k].x, past[k].y) then
			local to, sq = past[k], {}
			for j = 1, k do
				sq[#sq + 1] = ("%d %d"):format(past[j].x, past[j].y)
			end
			nh.act({{key = "#"}, {text = "nhvpass " .. table.concat(sq, " ")}},
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
	nh.act({{key = "#"}, {text = ("nhvmove %d %d%s"):format(tx, ty, stubborn_pet_at(tx, ty) and " 1" or "")}},
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
	local was = player_mod.nosqueeze
	player_mod.nosqueeze = nosq
	terrain.set_nosqueeze(nosq)
	if nosq and not was then
		-- (standing in a corner gap just as it filled: step out of it - only
		-- then, and only out of the gap's own block, not off stairs or a
		-- step you stand on)
		local p = player:get_pos()
		local in_gap = false
		for _, dy in ipairs({0.1, 1.0}) do
			if core.get_node(vector.round(vector.offset(p, 0, dy, 0))).name == "nhv:squeeze_block" then
				in_gap = true
			end
		end
		if in_gap then
			player:set_pos(player_mod.free_spot(p))
		end
	end
	-- confused / stunned: the VoxHack build of Luanti scrambles the
	-- controls (rotated / reversed walking, inverted looking up and down)
	-- (and the screen waves; hallucinating, it waves and its colours drift)
	local conf, stun = U.has(h.flags, U.HERO.CONF), U.has(h.flags, U.HERO.STUN)
	-- (NetHack options > Hallucination effects off: no waves or colours)
	local hallu = U.has(h.flags, U.HERO.HALLU) and nhv.nhopts.get("hallu_effects")
	if conf ~= player_mod.confused or stun ~= player_mod.stunned or hallu ~= player_mod.hallu then
		player_mod.confused, player_mod.stunned, player_mod.hallu = conf, stun, hallu
		player:hud_set_flags({nhv_confused = conf, nhv_stunned = stun, nhv_hallu = hallu})
	end
	local level_changed = player_mod.ledger ~= h.ledger
	player_mod.ledger = h.ledger

	if level_changed or not prev then
		-- (the new level is built now: black, held still, then fade in)
		nhv.hud.fade(1, 0)
		player_mod.level_hold = {t0 = core.get_us_time(), t_end = core.get_us_time() + BLACK_MAX_S * 1e6,
			loading = true}
	end
	if level_changed and prev and core.get_us_time() < (player_mod.falling_until or 0) then
		-- fell through a hole or a trap door: you drop in from above (just
		-- under the ceiling) onto the new level as it fades in
		player_mod.falling_until = nil
		teleport(player, U.tile_center(h.x, h.y, U.CEIL_Y - 2.4))
	elseif level_changed or not prev then
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
	elseif action and action.kind == "jump" then
		-- (you jumped: the body hops to where NetHack landed you - perhaps
		-- short of where you aimed, stopped by something on the way)
		if action.from_x and (h.x ~= action.from_x or h.y ~= action.from_y) then
			player_mod.hop(player, U.tile_center(h.x, h.y, terrain.stand_y(h.x, h.y)))
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
				moved_by_nethack(player, h) -- moved elsewhere
			end
		end
	elseif prev.x ~= h.x or prev.y ~= h.y then
		local tx, ty = U.pos_to_tile(player:get_pos())
		if tx ~= h.x or ty ~= h.y then
			moved_by_nethack(player, h)
		end
	end
end)

-- touching an nhv:trigger node uses the stairs/ladder it belongs to
local TRIGGER_KEYS = {
	stairs_down = ">", ladder_down = ">", stairs_up = "<", ladder_up = "<",
	stairs_up_sky = "<", ladder_up_sky = "<",
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

-- Traps go off when the body touches them, not when it crosses into their
-- square (walking there doesn't set them off: nhv_walking in NetHack): a
-- trap is a pad TRAP_PAD x TRAP_PAD in the middle of its square, found or
-- not, and the middle of your body coming onto it sets it off - once, until
-- you've been off it again. So cutting the corner of a trap's square,
-- stepping diagonally past it, doesn't. An open pit or hole - its floor
-- gone across the whole square, seen or a Sokoban one - is the whole
-- square: being over it at all is falling in, not just its middle.
local TRAP_PAD = 1.0
local OPEN_HOLE_NAMES = {S_hole = true, S_pit = true, S_spiked_pit = true}
local on_trap = nil -- "x,y" of the trap pad the body is on
local function check_traps(player)
	local h = player_mod.hero
	local map = nh.snap and nh.snap.map
	if not (h and map) then
		return
	end
	local i = U.idx(h.x, h.y)
	local known = map.trap and map.trap[i]
	if not U.has(map.flags[i] or 0, U.LOC_TRAP) then
		on_trap = nil
		return
	end
	local pos, c = player:get_pos(), U.tile_center(h.x, h.y)
	local here = h.x .. "," .. h.y
	if player_mod.trap_done then
		on_trap = player_mod.trap_done == here and here or on_trap
		player_mod.trap_done = nil
	end
	local pad = (known and known ~= 255 and OPEN_HOLE_NAMES[nhv.cmap_name(known % 128)]) and U.TILE or TRAP_PAD
	if math.abs(pos.x - c.x) > pad / 2 or math.abs(pos.z - c.z) > pad / 2 then
		if on_trap == here then
			on_trap = nil -- (off it again: it can go off again)
		end
		return
	end
	if on_trap == here or not nh.ready() then
		return
	end
	on_trap = here
	nh.act({{key = "#"}, {text = ("nhvtrap %d %d"):format(h.x, h.y)}}, {kind = "info"})
end

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

-- Helpless (asleep, frozen, fainted...), or searching for a number of
-- turns (Ctrl+X): the camera goes behind you, so you see what's happening
-- to you, and straight back to first person when you can act again (then
-- it's yours to change again). Asleep, you breathe out Z's, as sleeping
-- monsters do (mobs.lua).
local camera_out = false
local z_next = 0
local function helpless_view(player)
	local h = player_mod.hero
	local helpless = h and U.has(h.flags, U.HERO.HELPLESS) or nh.repeating or false
	if helpless ~= camera_out then
		camera_out = helpless
		player:set_camera({mode = helpless and "third" or "first"})
		if not helpless then
			-- (back in first person: free to change it again)
			core.after(0.2, function()
				if player:is_player() and not camera_out then
					player:set_camera({mode = "any"})
				end
			end)
		end
	end
	if h and U.has(h.flags, U.HERO.ASLEEP) then
		local now = core.get_us_time() / 1e6
		if now >= z_next then
			z_next = now + 1.1 * (0.8 + math.random() * 0.4)
			local side = (math.random() - 0.5) * 0.6
			core.add_particle({
				pos = vector.offset(player:get_pos(), side * 0.5, 1.9, side * 0.5),
				velocity = vector.new(side, 0.55, (math.random() - 0.5) * 0.6),
				expirationtime = 2.2,
				size = 1.6,
				texture = {name = "nhv_z.png^[multiply:#E8F0FF", alpha_tween = {1, 0},
					scale_tween = {0.6, 1.5}},
				glow = 10,
			})
		end
	end
end

-- Levitating: no gravity; you're held HOVER_H over the highest ground
-- under you, never lower than the floor - over a pit, water or the way down
-- you stay up at floor height (NetHack: you can't reach the stairs down),
-- while a staircase up lifts you with its steps. Off the ground there are
-- no footsteps and no view bobbing (the engine bobs only while you touch
-- the ground). A slow bob up and down shows you're floating.
local HOVER_H = 0.6
local function solid_at(x, y, z)
	local n = core.get_node(vector.new(x, y, z))
	local def = core.registered_nodes[n.name]
	return def and def.walkable and n.name ~= "nhv:squeeze_block"
end

-- the highest surface you could stand on (two free blocks over it: not a
-- wall's side) under you or just ahead of where you're going, at most a
-- step above your feet; never under the floor
local function ground_below(pos, vel)
	local best = U.STAND_Y
	local pts = {{0, 0}}
	local sp = math.sqrt(vel.x * vel.x + vel.z * vel.z)
	if sp > 0.1 then
		pts[2] = {vel.x / sp * 0.6, vel.z / sp * 0.6}
	end
	for _, d in ipairs(pts) do
		local x, z = math.floor(pos.x + d[1] + 0.5), math.floor(pos.z + d[2] + 0.5)
		for y = math.floor(pos.y + 1.2), math.floor(U.FLOOR_Y), -1 do
			if solid_at(x, y, z) then
				if not solid_at(x, y + 1, z) and not solid_at(x, y + 2, z) then
					best = math.max(best, y + 0.5)
				end
				break
			end
		end
	end
	return best
end

-- Struggling in the Plane of Air's thin air (neither flying nor
-- levitating; NetHack: "You tumble in place."): the float is clumsy - an
-- uneven bob that dips, the way forward stalling and lurching to the side
-- now and then, and the view rolling from side to side (the VoxHack
-- engine's core.nhv_camera_roll), harder as you try to go
local function struggling(h)
	return h and nhv.terrain and nhv.terrain.sky_floor == "air" and not U.has(h.flags, U.HERO.LEVITATE)
		and not U.has(h.flags, U.HERO.FLYING) or false
end
local flail = {next = 0, kick = 0, stall_until = 0}

local function hover(player)
	if not levitating(player_mod.hero) or player_mod.frozen then
		return
	end
	local pos = player:get_pos()
	local t = core.get_us_time() / 1e6
	local v = player:get_velocity()
	local bob = 0.06 * math.sin(t * 2.2)
	if struggling(player_mod.hero) then
		bob = 0.14 * math.sin(t * 3.1) + 0.07 * math.sin(t * 7.3 + 1.0) - 0.12 * math.max(0, math.sin(t * 1.3)) ^ 6
		-- (going somewhere: now and then the way forward stalls - a step
		-- that didn't take - or lurches to one side)
		local hv = vector.new(v.x, 0, v.z)
		local sp = vector.length(hv)
		if sp > 0.2 and t > flail.next then
			flail.next = t + 0.5 + math.random() * 0.9
			if math.random() < 0.6 then
				flail.stall_until = t + 0.2 + math.random() * 0.2
			else
				local side = vector.new(-hv.z / sp, 0, hv.x / sp)
				local k = (math.random() < 0.5 and -1 or 1) * (0.8 + math.random() * 0.8)
				player:add_velocity(vector.multiply(side, k))
				flail.kick = flail.kick + k * 6
			end
		end
		if t < flail.stall_until and sp > 0.05 then
			player:add_velocity(vector.multiply(hv, -0.6))
		end
	end
	-- (the Plane of Water: held level, no bob - and only set right when
	-- it's really off, so the view stays still)
	local water = nhv.terrain.sky_floor == "water" and not U.has(player_mod.hero.flags, U.HERO.LEVITATE)
	if water then
		bob = 0
	end
	local target = ground_below(pos, v) + HOVER_H + bob
	local want = math.max(-4, math.min(4, (target - pos.y) * 6))
	if water and math.abs(target - pos.y) < 0.08 then
		want = 0
	end
	if math.abs(want - v.y) > 0.05 then
		player:add_velocity(vector.new(0, want - v.y, 0))
	end
end

-- the view's roll while struggling (0 otherwise)
local roll_set = 0
core.register_globalstep(function(dtime)
	if not core.nhv_camera_roll then
		return
	end
	local player = player_mod.get()
	local roll = 0
	if player and struggling(player_mod.hero) and not player_mod.frozen
			and not (nhv.cutscene and nhv.cutscene.active) then
		local t = core.get_us_time() / 1e6
		local v = player:get_velocity()
		local moving = math.min(1, math.sqrt(v.x * v.x + v.z * v.z) / 0.6)
		roll = (2 + 3 * moving) * math.sin(t * 1.7) + (1 + 1.5 * moving) * math.sin(t * 4.1 + 0.7) + flail.kick
	end
	flail.kick = flail.kick * math.max(0, 1 - dtime * 3)
	if math.abs(roll - roll_set) > 0.05 then
		roll_set = roll
		core.nhv_camera_roll(roll)
	end
end)

local was_searching, was_dragging = false
core.register_globalstep(function()
	local player = player_mod.get()
	-- (searching started or ended: stand still / walk again)
	local searching = nhv.clock.searching()
	-- (or started or stopped dragging the iron ball: slower / faster)
	local dragging = nhv.mobs.dragging or false
	if player and (searching ~= was_searching or dragging ~= was_dragging) then
		was_searching, was_dragging = searching, dragging
		set_speed(player)
	end
	-- a new level is reaching the screen under the black: hold still (once
	-- the arrival spot is settled), then fade in
	local fz = player and player_mod.level_hold
	if fz then
		local now = core.get_us_time()
		-- (the new level: until all of it is on the screen)
		local loaded = fz.loading and now - fz.t0 > BLACK_MIN_S * 1e6
			and (not core.nh_level_progress or core.nh_level_progress() >= 1)
		if now < fz.t_end and not loaded then
			if not fz.pos and now - fz.t0 > 150000 then
				fz.pos = player:get_pos()
			end
			if fz.pos then
				player:set_pos(fz.pos)
			end
			player:add_velocity(vector.multiply(player:get_velocity(), -1))
			return
		end
		player_mod.level_hold = nil
		nhv.hud.fade(0, FADE_IN_S)
	end
	-- wizard mode, flying free (wizard.lua): the hero stays where it is;
	-- coming back down, you're back with it
	if player and nhv.wizard then
		local free = nhv.wizard.detached()
		if free then
			player_mod.detached = true
			return
		elseif player_mod.detached then
			player_mod.detached = nil
			local h = player_mod.hero
			if h then
				teleport(player, U.tile_center(h.x, h.y))
			end
		end
	end
	if player and nh.snap then
		try_escape(player)
		if not hold_still(player) then
			step(player)
		end
		hover(player)
		check_gap(player)
		check_trigger(player)
		check_traps(player)
		helpless_view(player)
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
