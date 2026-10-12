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
local HALF = U.TILE / 2

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

-- keep the body inside the hero's square (just inside the edge nearest
-- to where it is now)
local function clamp_to_hero(player)
	local h = player_mod.hero
	local c = U.tile_center(h.x, h.y)
	local pos = player:get_pos()
	local lim = HALF - 0.4
	local x = math.max(c.x - lim, math.min(c.x + lim, pos.x))
	local z = math.max(c.z - lim, math.min(c.z + lim, pos.z))
	teleport(player, vector.new(x, pos.y, z))
end

local function step(player)
	local h = player_mod.hero
	if not h or not nh.ready() then
		return
	end
	if core.get_us_time() < player_mod.grace_until then
		return
	end
	local pos = player:get_pos()
	local tx, ty = U.pos_to_tile(pos)
	if tx == h.x and ty == h.y then
		return
	end
	if math.abs(tx - h.x) > 1 or math.abs(ty - h.y) > 1 or not U.in_map(tx, ty) then
		clamp_to_hero(player)
		return
	end
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
	elseif action and action.kind == "hmove" then
		if h.x == action.from_x and h.y == action.from_y then
			clamp_to_hero(player) -- refused
		elseif h.x ~= action.tx or h.y ~= action.ty then
			teleport(player, U.tile_center(h.x, h.y)) -- moved elsewhere
		end
	elseif prev.x ~= h.x or prev.y ~= h.y then
		local tx, ty = U.pos_to_tile(player:get_pos())
		if tx ~= h.x or ty ~= h.y then
			teleport(player, U.tile_center(h.x, h.y))
		end
	end
	terrain.place_hero_light(h.x, h.y)
end)

core.register_globalstep(function()
	local player = player_mod.get()
	if player and nh.snap then
		try_escape(player)
		step(player)
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
