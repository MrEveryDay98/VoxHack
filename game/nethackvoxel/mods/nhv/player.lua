-- The hero: free first-person movement mapped onto NetHack's grid.
--
-- * Walking out of the hero's square commits a NetHack move toward where
--   you are heading as soon as you leave the middle of the square, so the
--   world's reaction (monsters moving) plays out while you finish the step.
-- * Time only flows while you move or act: nhv.time.p advances with the
--   distance walked (one square of walking = one move) or, for actions
--   like attacks, over a short animation.
-- * NetHack is authoritative: if a move is refused (or you are teleported)
--   the player is put back where NetHack says the hero is.

local U = nhv.util
local nh = nhv.nh
local terrain = nhv.terrain

local player_mod = {
	hero = nil,        -- last hero snapshot
	last_pos = nil,
	travel = 0,        -- distance walked since the last action
	auto = 0,          -- time animation rate (p per second) for actions
	blocked = nil,     -- {dx, dy} of a refused move, until we back off
	frozen = false,
	ledger = nil,
}
nhv.player = player_mod

local COMMIT_R = 0.9      -- distance from the square's centre that commits a move
local HALF = (U.TILE - 1) / 2 + 0.5 -- half-width of a square in nodes
local WALK_SPEED = 1.0    -- physics multiplier at normal speed

function player_mod.get()
	return core.get_connected_players()[1]
end

local function hero_center()
	local h = player_mod.hero
	return U.tile_center(h.x, h.y)
end

-- look direction helpers --------------------------------------------------
function player_mod.look_dir(player)
	local dir = player:get_look_dir()
	return dir
end

-- NetHack direction key for where the player is looking (for "In what
-- direction?" prompts): steep up/down become '<' / '>'.
function player_mod.look_dir_key(player)
	local pitch = player:get_look_vertical() -- positive = looking down
	if pitch > 1.0 then
		return ">"
	elseif pitch < -1.0 then
		return "<"
	end
	local dx, dy = U.vec_to_dir(player:get_look_dir())
	return U.dir_key(dx, dy)
end

-- movement ---------------------------------------------------------------
local function set_speed(player)
	local h = player_mod.hero
	local speed = WALK_SPEED
	if h then
		if U.has(h.flags, U.HERO.VFAST) then
			speed = speed * 1.35
		elseif U.has(h.flags, U.HERO.FAST) then
			speed = speed * 1.2
		end
		speed = speed * (({[0] = 1, 0.85, 0.7, 0.55, 0.4, 0.25})[h.encumbrance] or 1)
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

local function commit_move(dx, dy)
	local h = player_mod.hero
	local tx, ty = h.x + dx, h.y + dy
	local m = nhv.mobs.monster_at(tx, ty)
	local key = U.dir_key(dx, dy)
	-- 'm' prefix: move without fighting or picking up. A pet needs a
	-- plain move so that you swap places with it.
	local keys = (m and U.has(m.mon.flags, U.MON_PET)) and key or ("m" .. key)
	player_mod.travel = 0
	nhv.time.p = 0
	player_mod.auto = 0
	nh.act(keys, {kind = "move", dx = dx, dy = dy, from_x = h.x, from_y = h.y})
end

local function commit_wait()
	player_mod.travel = 0
	nhv.time.p = 0
	player_mod.auto = 0
	nh.act("ms", {kind = "wait"})
end

-- Start a timed action (attack, item use): time flows for `secs`.
function player_mod.timed_action(keys, info, secs)
	player_mod.travel = 0
	nhv.time.p = 0
	player_mod.auto = 1 / (secs or 0.45)
	nh.act(keys, info)
end

local GRACE_US = 400000 -- ignore movement this long after we move the player

local function teleport(player, pos)
	player:set_pos(pos)
	player_mod.last_pos = pos
	player_mod.grace_until = core.get_us_time() + GRACE_US
end
player_mod.teleport = teleport

-- Put the player back inside the hero's square.
local function clamp_to_hero(player, hard)
	local c = hero_center()
	local pos = player:get_pos()
	if hard then
		teleport(player, c)
		return
	end
	local off = vector.subtract(pos, c)
	off.y = 0
	local lim = COMMIT_R * 0.7
	local len = vector.length(off)
	if len > lim then
		off = vector.multiply(off, lim / len)
	end
	teleport(player, vector.new(c.x + off.x, pos.y, c.z + off.z))
end

local function step(player, dtime)
	local h = player_mod.hero
	if not h then
		return
	end
	local pos = player:get_pos()
	local last = player_mod.last_pos or pos
	local moved = vector.distance(vector.new(pos.x, 0, pos.z), vector.new(last.x, 0, last.z))
	player_mod.last_pos = pos
	if moved > U.TILE then
		moved = 0 -- teleported
	end

	-- time flows with walking and with action animations
	local p = nhv.time.p + moved / U.TILE + player_mod.auto * dtime
	nhv.time.p = math.min(1, p)
	if nhv.time.p >= 1 then
		player_mod.auto = 0
	end

	if not nh.ready() then
		return
	end
	-- positions reported right after a teleport may be stale
	if core.get_us_time() < (player_mod.grace_until or 0) then
		return
	end
	local vel = player:get_velocity()
	local walking = math.sqrt(vel.x * vel.x + vel.z * vel.z) > 0.3
	player_mod.travel = player_mod.travel + moved

	local c = hero_center()
	local off = vector.new(pos.x - c.x, 0, pos.z - c.z)
	local tx, ty = U.pos_to_tile(pos)

	-- left the square entirely (fast motion): step toward where we are
	-- standing in a different square than the hero
	if tx ~= h.x or ty ~= h.y then
		local dx, dy = U.sign(tx - h.x), U.sign(ty - h.y)
		-- right after a committed move the player is still catching up
		-- with the hero's new square: only step if heading away from it
		local away = vel.x * dx - vel.z * dy > 0
		if math.abs(tx - h.x) > 1 or math.abs(ty - h.y) > 1 then
			clamp_to_hero(player, true)
			return
		end
		local b = player_mod.blocked
		if walking and away and not (b and b[1] == dx and b[2] == dy) then
			commit_move(dx, dy)
		end
		return
	end

	local dist = vector.length(off)
	local b = player_mod.blocked
	if b and dist < COMMIT_R * 0.5 then
		player_mod.blocked = nil
		b = nil
	end
	local outward = off.x * vel.x + off.z * vel.z > 0
	if dist > COMMIT_R and walking and outward then
		local dx, dy = U.vec_to_dir(off)
		local map = nh.snap.map
		-- diagonal into a wall corner or through a doorway: go straight
		if dx ~= 0 and dy ~= 0 and (not terrain.passable(map, h.x + dx, h.y + dy)
				or terrain.is_door(map, h.x, h.y)
				or terrain.is_door(map, h.x + dx, h.y + dy)) then
			if math.abs(off.x) > math.abs(off.z) then
				dy = 0
			else
				dx = 0
			end
		end
		if (dx ~= 0 or dy ~= 0) and terrain.passable(map, h.x + dx, h.y + dy)
				and not (b and b[1] == dx and b[2] == dy) then
			commit_move(dx, dy)
			return
		end
	end

	-- walking around inside one square still passes time
	if walking and player_mod.travel >= U.TILE then
		commit_wait()
	end
end

-- after NetHack resolved something ----------------------------------------
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
		player_mod.blocked = nil
	elseif action and action.kind == "move" then
		if h.x == action.from_x and h.y == action.from_y then
			-- refused: stay put and don't retry until we back off
			player_mod.blocked = {action.dx, action.dy}
			clamp_to_hero(player)
		elseif h.x ~= action.from_x + action.dx or h.y ~= action.from_y + action.dy then
			teleport(player, U.tile_center(h.x, h.y)) -- trap, teleport, ...
		else
			player_mod.blocked = nil
		end
	elseif prev and (prev.x ~= h.x or prev.y ~= h.y) then
		-- moved by something other than walking
		teleport(player, U.tile_center(h.x, h.y))
	end
	terrain.place_hero_light(h.x, h.y)

	-- a multi-turn action (eating, digging...) passed several turns
	if prev and h.moves - prev.moves > 1 and (not action or action.kind ~= "move") then
		nhv.time.p = 0
		player_mod.auto = 1 / math.min(2.0, 0.2 * (h.moves - prev.moves))
	end
end)

core.register_globalstep(function(dtime)
	local player = player_mod.get()
	if player and nh.snap then
		step(player, dtime)
	end
end)

core.register_on_joinplayer(function(player)
	player:set_physics_override({speed = WALK_SPEED, jump = 0})
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
