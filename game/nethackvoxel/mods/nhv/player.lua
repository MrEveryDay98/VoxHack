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

local function teleport(player, pos)
	player:set_pos(pos)
	player_mod.grace_until = core.get_us_time() + GRACE_US
end
player_mod.teleport = teleport

local function stuck(h)
	return U.has(h.flags, U.HERO.TRAPPED) or U.has(h.flags, U.HERO.SWALLOWED)
end

local function set_speed(player)
	local h = player_mod.hero
	local speed = nhv.clock.hero_speed() / 12
	if h then
		speed = speed * (({[0] = 1, 0.85, 0.7, 0.55, 0.4, 0.25})[h.encumbrance] or 1)
		if stuck(h) then
			speed = 0
		end
	end
	if player_mod.frozen then
		speed = 0
	end
	player:set_physics_override({speed = speed, jump = 0, sneak_glitch = false,
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
			local w = e.h * 0.45
			-- gap between the player's body and the boulder's box
			local gx = math.max(0, math.abs(bp.x - pos.x) - w - 0.35)
			local gz = math.max(0, math.abs(bp.z - pos.z) - w - 0.35)
			local to = vector.normalize(vector.new(bp.x - pos.x, 0, bp.z - pos.z))
			if gx < 0.15 and gz < 0.15 and vector.dot(to, dir) > 0.6 then
				push_next = core.get_us_time() + 400000
				nh.act({{key = "#"}, {text = ("nhvmove %d %d"):format(e.x, e.y)}},
					{kind = "push", tx = e.x, ty = e.y, from_x = h.x, from_y = h.y})
				return true
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
	-- more than one square away (e.g. after waiting): step toward it
	tx = h.x + U.sign(tx - h.x)
	ty = h.y + U.sign(ty - h.y)
	nh.act({{key = "#"}, {text = ("nhvmove %d %d"):format(tx, ty)}},
		{kind = "hmove", tx = tx, ty = ty, from_x = h.x, from_y = h.y})
end

-- escape attempts while stuck in a trap: walking costs a real move
local escape_next = 0
local function try_escape(player)
	local h = player_mod.hero
	if not h or not U.has(h.flags, U.HERO.TRAPPED) or not nh.ready() then
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
	local dir = player:get_look_dir()
	if c.down then
		dir = vector.multiply(dir, -1)
	end
	local dx, dy = U.vec_to_dir(dir)
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
	local level_changed = player_mod.ledger ~= h.ledger
	player_mod.ledger = h.ledger

	if level_changed or not prev then
		teleport(player, U.tile_center(h.x, h.y))
	elseif action and action.kind == "push" then
		if h.x == action.tx and h.y == action.ty then
			nhv.sound.hook("boulder_push")
			player_mod.ahead = {from_x = action.from_x, from_y = action.from_y,
				t_end = core.get_us_time() + 1500000}
		end
	elseif action and action.kind == "hmove" then
		if h.x == action.from_x and h.y == action.from_y then
			-- refused: no teleporting the body back; retry later
			player_mod.retry_at = core.get_us_time() + 500000
		elseif h.x ~= action.tx or h.y ~= action.ty then
			teleport(player, U.tile_center(h.x, h.y)) -- moved elsewhere
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
	if key then
		in_trigger = true
		nhv.clock.act(key, {kind = "stairs"})
	end
end

core.register_globalstep(function()
	local player = player_mod.get()
	if player and nh.snap then
		try_escape(player)
		step(player)
		check_trigger(player)
		terrain.place_hero_light(player:get_pos())
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
