-- Player actions and controls.
--
--   Left click        attack the monster in reach nearest your crosshair
--   Shift+left click  fire your quivered ammo where you look
--   Right click       tap: the obvious action for what you point at
--                     (open a door, take the stairs, chat...)
--                     hold: action wheel for it - move the mouse toward
--                     an action and let go
--   Shift+right click the same for yourself (pray, rest, engrave...)
--   R                 pick up what is here (hotbar.lua)
--   Alt+right click   use an item (quaff, read, apply, wear...)
--                     (what the hotbar does - fire, kick, zap, cast, eat,
--                     search, pay - is left off these wheels)
--   Ctrl+right click  magic and abilities (turn undead, invoke, ...)
--   E (aux1)          same, for your wielded weapon
--   1-5               the hotbar's action keys (hotbar.lua)
--   T                 NetHack command line (hotbar.lua)
--   Space (jump)      tap: wait a turn; hold: jump (jump.lua)
--   Z (zoom)          toggle the large overhead map
--   I                 inventory and equipment

local U = nhv.util
local nh = nhv.nh
local actions = {}
nhv.actions = actions

local OC = U.OCLASS

local function hero()
	return nh.snap and nh.snap.hero
end

local function busy()
	return not nh.ready()
end

-- an action: {label=, keys=} where keys are what nh.act() takes
local function act(label, keys)
	return {label = label, keys = keys}
end

local function ext(name, ...)
	local k = {{key = "#"}, {text = name}}
	for _, extra in ipairs({...}) do
		k[#k + 1] = extra
	end
	return k
end

-- actions that only show information take no game time
local function info_act(label, keys)
	return {label = label, keys = keys, free = true}
end

-- An action asked for while the last one is still playing out (or NetHack
-- is busy) waits for it rather than being dropped: chosen from a menu (the
-- inventory, a wheel - time stands still while those are open) for a few
-- seconds, a key press only for a moment. One waits at a time: the latest.
local WAIT_US = {item = 5000000, wheel = 5000000}
local WAIT_KEY_US = 600000
local waiting -- {a=, info=, until_t=}

local function run_now(a, info)
	-- (answers it gives to NetHack's questions on the way, each to the
	-- question it's for: ui.lua's queued answers)
	for _, ans in ipairs(a.answers or {}) do
		table.insert(nhv.ui.auto_answers, {pattern = ans.pattern, menu = ans.menu, key = ans.key,
			t = core.get_us_time()})
	end
	if a.free then
		nh.act(a.keys, info or {kind = "info"})
	else
		if not actions.kick_start(a.keys) then
			actions.swing()
		end
		nhv.clock.act(a.keys, info or {kind = "action"})
	end
end

local function ready_for(a)
	return not busy() and (a.free or not nhv.clock.busy())
end

function actions.run(a, info)
	if not a or (nhv.cutscene and nhv.cutscene.active) then
		return
	end
	-- (not a NetHack command - the wiki, a question first - picked on a
	-- wheel: done at once)
	if a.func then
		return a.func(nhv.player.get(), a.obj)
	end
	if ready_for(a) then
		waiting = nil
		run_now(a, info)
	else
		local kind = info and info.kind
		waiting = {a = a, info = info,
			until_t = core.get_us_time() + (WAIT_US[kind] or WAIT_KEY_US)}
	end
end

core.register_globalstep(function()
	if not waiting then
		return
	end
	if core.get_us_time() > waiting.until_t then
		waiting = nil
	elseif ready_for(waiting.a) then
		local w = waiting
		waiting = nil
		run_now(w.a, w.info)
	end
end)

-- ---------------------------------------------------------------- kicks
-- A kick isn't an arm swing: both hands drop out of view and come back
-- (your body moved), and the view shakes; when it lands - NetHack says it
-- hit something (a door, a box, a monster, a wall) - dust puffs from what
-- you kicked too.
local kick = nil -- {x, y, t}: the square kicked, until NetHack has said
local hands_down_state, shake_state = false, false

local function kick_shake(player)
	shake_state = not shake_state
	player:hud_set_flags({nhv_shake = shake_state})
end

-- the square a kick's keys aim at (nil: not a kick)
local function kick_square(keys)
	local h = nh.snap and nh.snap.hero
	if not h or type(keys) ~= "table" then
		return nil
	end
	local bx, by = h.x, h.y
	for k, item in ipairs(keys) do
		local mx, my = (item.text or ""):match("^nhvmove (%d+) (%d+)")
		if mx then
			bx, by = tonumber(mx), tonumber(my) -- (kicking from where the body is)
		end
		if (item.text or ""):match("^nhvkickhere") then
			return bx, by -- (what's on your own square)
		end
		if item.key == "\4" then
			local d = keys[k + 1] and keys[k + 1].key
			for dx = -1, 1 do
				for dy = -1, 1 do
					if d and (dx ~= 0 or dy ~= 0) and U.dir_key(dx, dy) == d then
						return bx + dx, by + dy
					end
				end
			end
			return bx, by
		end
	end
	return nil
end

-- (a kick's keys: start its look; false if they aren't a kick)
function actions.kick_start(keys)
	if type(keys) == "string" then
		local t = {}
		for c in keys:gmatch(".") do
			t[#t + 1] = {key = c}
		end
		keys = t
	end
	local x, y = kick_square(keys)
	if not x then
		return false
	end
	local player = nhv.player.get()
	if player then
		hands_down_state = not hands_down_state
		player:hud_set_flags({nhv_hands_down = hands_down_state})
		nhv.sound.hook("hero_swing_miss_air") -- (the whoosh of the kick going out)
		-- (the view shakes as the kick goes out, hit or not)
		core.after(0.15, function()
			if player:is_player() then
				kick_shake(player)
			end
		end)
	end
	kick = {x = x, y = y, t = core.get_us_time()}
	return true
end

local KICK_MISS = {"empty space", "strain a muscle", "dumb move", "you miss", "kick at nothing",
	"you kick at"}
local KICK_HIT = {"whamm", "thump", "thud", "crash", "you kick", "ouch", "breaks open",
	"bursts open", "shatter", "flies", "kick the", "kicks", "klunk", "budge", "slam"}

local function kick_landed(_, k)
	local c = U.tile_center(k.x, k.y, U.STAND_Y + 0.6)
	core.add_particlespawner({
		amount = 26, time = 0.1,
		pos = {min = vector.offset(c, -0.6, -0.4, -0.6), max = vector.offset(c, 0.6, 0.5, 0.6)},
		vel = {min = vector.new(-1.6, 0.2, -1.6), max = vector.new(1.6, 1.4, 1.6)},
		acc = vector.new(0, -1.5, 0),
		exptime = {min = 0.4, max = 0.9},
		size = {min = 1.2, max = 3},
		texture = {name = "[fill:4x4:#8A7A66", alpha_tween = {0.9, 0}, scale_tween = {0.6, 1.4}},
		collisiondetection = true,
	})
end

nh.on_event(function(evs)
	if not kick then
		return
	end
	if core.get_us_time() - kick.t > 1500000 then
		kick = nil -- (NetHack never said: a refused kick)
		return
	end
	for _, ev in ipairs(evs) do
		if ev.kind == "message" then
			local m = ev.text:lower()
			local miss, hit = false, false
			for _, w in ipairs(KICK_MISS) do
				if m:find(w, 1, true) then
					miss = true
				end
			end
			for _, w in ipairs(KICK_HIT) do
				if m:find(w, 1, true) then
					hit = true
				end
			end
			local player = nhv.player.get()
			if miss then
				kick = nil
				return
			elseif hit and player then
				kick_landed(player, kick)
				kick = nil
				return
			end
		end
	end
end)

-- One arm swing (right-click doesn't swing by itself; see hud.lua)
local swing_state = false
local off_swing_state = false
local stab_state = false
function actions.swing()
	local player = nhv.player.get()
	if player then
		swing_state = not swing_state
		player:hud_set_flags({nhv_swing = swing_state})
	end
end

-- the left hand's swing (dual wielding, a Monk's second fist)
local function off_swing(player)
	off_swing_state = not off_swing_state
	player:hud_set_flags({nhv_off_swing = off_swing_state})
end

-- Melee swings as NetHack makes them: it reports each one it rolls
-- ("uswing <hand>", 0 right / 1 left) - two dual wielding or with a
-- martial artist's double punch, several for a polymorphed form's attacks
-- - and each is a quick swing in turn. Dual wielding the hands go as
-- NetHack says (primary, secondary...); a Monk's fists take turns from one
-- attack to the next too; otherwise it's the right hand every time.
local SWING_GAP = 0.18 -- seconds between quick swings (each fully seen)
local swing_queue, swing_at = {}, 0
local fist_next = 0 -- (a Monk's next fist)

-- play one swing with hand (0 right, 1 left): the left only when it holds
-- something (dual wielding, a Monk's fist); a Monk's fists take turns -
-- right, left, right... - whatever NetHack says, punching the air too
local function play_swing(hand)
	local player = nhv.player.get()
	if not player then
		return false
	end
	local h = nh.snap and nh.snap.hero
	local left_shown = h and (U.has(h.flags, U.HERO.TWOWEAP) or U.has(h.flags, U.HERO.TWOFISTS))
	if h and U.has(h.flags, U.HERO.TWOFISTS) then
		hand = fist_next
		fist_next = 1 - fist_next
	end
	if hand == 1 and left_shown then
		off_swing(player)
	else
		actions.swing()
	end
	return true
end

-- a stab with the wielded item: a polearm's (or Snickersnee's) hit from
-- a distance, as NetHack makes it (free: Snickersnee's free hit, which
-- sounds different)
function actions.stab(free)
	local player = nhv.player.get()
	if player then
		stab_state = not stab_state
		player:hud_set_flags({nhv_stab = stab_state})
		nhv.sound.hook("hero_swing", {free = free})
	end
end

-- the wielded item, when #invoke does something with it (Q invokes it)
function actions.invokable()
	for _, o in ipairs((nh.snap and nh.snap.inventory) or {}) do
		if U.has(o.flags, U.OBJ.WIELDED) and U.has(o.flags, U.OBJ.INVOKE) then
			return o
		end
	end
end

-- what NetHack's #monster would do now ("Breathe", "Spit", "Hide"...),
-- nil when nothing: your form's special ability (Q uses it)
function actions.monster_ability()
	local a = nh.snap and nh.snap.hero and nh.snap.hero.ability
	return a ~= "" and a or nil
end

-- a melee swing, after any still to play (one at a time, never two at once)
function actions.melee_swing(hand)
	swing_queue[#swing_queue + 1] = hand or 0
end

nh.on_event(function(evs)
	for _, ev in ipairs(evs) do
		if ev.kind == "combat" then
			local hand = ev.text:match("^uswing (%d+)")
			if hand then
				actions.melee_swing(tonumber(hand))
			elseif ev.text:match("^upole ") then
				actions.stab(ev.text:match("^upole 1 ") ~= nil)
			end
		end
	end
end)

core.register_globalstep(function()
	if #swing_queue == 0 then
		return
	end
	local now = core.get_us_time()
	if now < swing_at then
		return
	end
	if play_swing(table.remove(swing_queue, 1)) then
		swing_at = now + SWING_GAP * 1e6
	end
end)

-- ---------------------------------------------------------------- pits
-- Down in a pit (a hole below the floor), Space climbs out onto the square
-- you're facing, if you're at that edge. Returns true when you're in a pit.
function actions.climb_out(player)
	local pos = player:get_pos()
	if pos.y > U.STAND_Y - 1 then
		return false
	end
	local look = player:get_look_dir()
	local dir = vector.normalize(vector.new(look.x, 0, look.z))
	local target = vector.add(pos, vector.multiply(dir, 0.9))
	local tx, ty = U.pos_to_tile(pos)
	local nx, ny = U.pos_to_tile(target)
	if (nx == tx and ny == ty) or not nh.snap
			or not nhv.terrain.passable(nh.snap.map, nx, ny) then
		nhv.hud.message("Walk to the edge of the pit and face out of it to climb out.")
		return true
	end
	local spot = nhv.player.free_spot(vector.new(target.x, U.STAND_Y + 0.05, target.z))
	nhv.player.teleport(player, spot)
	nhv.sound.hook("climb_out")
	return true
end

-- ---------------------------------------------------------------- attacking
local function angle_between(a, b)
	local la, lb = math.sqrt(a.x * a.x + a.z * a.z), math.sqrt(b.x * b.x + b.z * b.z)
	if la < 1e-6 or lb < 1e-6 then
		return math.pi
	end
	local d = (a.x * b.x + a.z * b.z) / (la * lb)
	return math.acos(math.max(-1, math.min(1, d)))
end

local ATTACK_CONE = 0.6 -- radians either side of the crosshair

-- how far off the crosshair monster body `body` is, for your swing. A body
-- touching yours counts as straight ahead: you can walk into one you can't
-- see (nothing to bump into), and then its middle is beside or behind you,
-- or right where you stand (no direction at all) - it's hit wherever you look
local function swing_angle(look, body, pos)
	local dx, dz = body.pos.x - pos.x, body.pos.z - pos.z
	if math.sqrt(dx * dx + dz * dz) < (body.r or 0.4) + nhv.sim.HERO_R then
		return 0
	end
	return angle_between(look, vector.subtract(body.pos, pos))
end

-- the perceived monster your swing would hit: within reach of your body
-- (the same reach monsters have on you: sim.in_reach) and closest to the
-- crosshair
local function attack_target(player, prefer_id)
	local pos = player:get_pos()
	local look = player:get_look_dir()
	local best, best_a
	for _, e in pairs(nhv.mobs.mons) do
		local body = e.id and e.id > 0 and nhv.sim.body(e.id)
		if body then
			if nhv.sim.in_reach(e.id, pos) then
				local a = swing_angle(look, body, pos)
				if e.id == prefer_id then
					a = a - 0.3
				end
				if a < ATTACK_CONE and (not best_a or a < best_a) then
					best, best_a = e, a
				end
			end
		end
	end
	-- a long worm's tail segment next to you (its square: NetHack hits the
	-- tail there, and may cut the worm in two), if it's nearer the
	-- crosshair than the worm's head
	local h = hero()
	for _, e in pairs(nhv.mobs.mons) do
		if e.tail_of and math.max(math.abs(e.x - h.x), math.abs(e.y - h.y)) == 1 then
			local a = swing_angle(look, {pos = U.tile_center(e.x, e.y, pos.y), r = 0.45 * U.TILE}, pos)
			if e.tail_of == prefer_id then
				a = a - 0.3
			end
			if a < ATTACK_CONE and (not best_a or a < best_a) then
				best, best_a = {id = e.tail_of, tx = e.x, ty = e.y}, a
			end
		end
	end
	if best then
		return best
	end
	-- nothing you can see or sense there: a monster you can't see (you're
	-- blind, it's invisible, it's dark) is still hit if it's where you
	-- swing, as NetHack's attack in its direction hits it ("You hit it.")
	local perceived = {}
	for _, e in pairs(nhv.mobs.mons) do
		if e.id then
			perceived[e.id] = true
		end
	end
	for id, body in pairs(nhv.sim.mons) do
		if not perceived[id] and nhv.sim.in_reach(id, pos) then
			local a = swing_angle(look, body, pos)
			if a < ATTACK_CONE and (not best_a or a < best_a) then
				best, best_a = {id = id}, a
			end
		end
	end
	return best
end

-- With a polearm or lance: a monster out of your arm's reach but within
-- the polearm's - your melee reach (sim.in_reach) times POLE_REACH, by your
-- skill with it, as NetHack's applying range grows with it (2 squares
-- straight; skilled, a knight's move; expert, 2 diagonally) - in the
-- direction you aim. (NetHack takes VoxHack's word for the distance.)
local POLE_REACH = {basic = 9, skilled = 10, expert = 13}
local function pole_target(player, prefer_id)
	local h = hero()
	if not U.has(h.flags, U.HERO.POLE) then
		return nil
	end
	local mult = U.has(h.flags, U.HERO.POLE8) and POLE_REACH.expert
		or U.has(h.flags, U.HERO.POLE5) and POLE_REACH.skilled or POLE_REACH.basic
	local pos = player:get_pos()
	local look = player:get_look_dir()
	local best, best_a
	for _, e in pairs(nhv.mobs.mons) do
		local body = e.id and e.id > 0 and nhv.sim.body(e.id)
		if body and nhv.sim.in_reach(e.id, pos, mult) then
			local a = swing_angle(look, body, pos)
			if e.id == prefer_id then
				a = a - 0.3
			end
			if a < ATTACK_CONE and (not best_a or a < best_a) then
				best, best_a = e, a
			end
		end
	end
	return best
end

-- (anything waiting to run is dropped: a cutscene started)
function actions.drop_waiting()
	waiting = nil
end

function actions.attack(player, prefer_id)
	if nhv.cutscene and nhv.cutscene.active then
		return
	end
	-- a readied spell: the click casts it
	if nhv.spells.release(player) then
		return
	end
	if busy() or nhv.clock.busy() then
		return
	end
	local h = hero()
	if U.has(h.flags, U.HERO.SWALLOWED) then
		nhv.clock.act("Fl", {kind = "attack"})
		return
	end
	local t = attack_target(player, prefer_id)
	local far = not t and pole_target(player, prefer_id)
	if t then
		-- (the arm swings as NetHack reports each swing: above)
		nhv.sound.hook("hero_swing")
		nhv.clock.act(ext("nhvattack " .. t.id .. (t.tx and (" " .. t.tx .. " " .. t.ty) or "")),
			{kind = "attack"})
	elseif far then
		-- (out of arm's reach, in a polearm's or lance's: it stabs as
		-- NetHack reports the hit, below)
		nhv.clock.act(ext("nhvpole " .. far.id), {kind = "attack"})
	elseif actions.try_dig(player) then -- luacheck: ignore 542
		-- (digging with the wielded pick-axe; it swings)
	else
		-- a swing at nothing still takes the time a swing takes
		actions.melee_swing(0)
		nhv.sound.hook("hero_swing_miss_air")
		nhv.clock.act(ext("nhvtick"), {kind = "swing"})
	end
end

-- With a pick-axe or mattock in hand, attacking rock, a wall or a boulder next to you
-- digs into it, and attacking while looking down digs down (NetHack's
-- apply; its direction is where you look).
local DIGGERS = {["pick-axe"] = true, ["dwarvish mattock"] = true}
function actions.try_dig(player)
	local h = hero()
	local tool
	for _, o in ipairs((nh.snap and nh.snap.inventory) or {}) do
		local name = (o.name or ""):lower()
		if (o.worn or 0) % 0x200 >= 0x100 then -- (wielded)
			for d in pairs(DIGGERS) do
				if name:find(d, 1, true) then
					tool = o
				end
			end
		end
	end
	if not tool then
		return false
	end
	local dk = actions.pointed_dir_key(player, "dig")
	if dk ~= ">" and dk ~= "<" then
		local p = actions.pointed(player)
		local wx, wy = p.wx or p.tx, p.wy or p.ty
		if not wx or math.abs(wx - h.x) > 1 or math.abs(wy - h.y) > 1
				or (wx == h.x and wy == h.y) then
			return false
		end
		local typ = nh.snap.map.typ[U.idx(wx, wy)]
		local T = U.TYP
		-- (rock or a wall; or a boulder there: digging breaks it up, as
		-- NetHack's apply does - "the boulder falls apart")
		local boulder = nhv.mobs.objs[U.idx(wx, wy)]
		if not (typ and typ < T.POOL and typ ~= T.IRONBARS and typ ~= T.DOOR and typ ~= T.TREE)
				and not (boulder and boulder.boulder) then
			return false
		end
	end
	actions.swing()
	nhv.clock.act({{key = "a"}, {key = tool.invlet}}, {kind = "dig"})
	return true
end

function actions.attack_entity(player, ent)
	local e = nhv.mobs.mons[ent.nh_key]
	actions.attack(player, e and (e.id or e.tail_of))
end

function actions.fire(player)
	if busy() or nhv.clock.busy() then
		return
	end
	nhv.clock.act("f", {kind = "fire"})
end

-- ---------------------------------------------------------------- pointing
-- An open door next to you that you look through (the leaf swung back out
-- of the way, nothing of it to point at): its square, and how far off
-- (nodes) its doorway starts - so it can still be closed
local function doorway(player)
	local h = hero()
	local map = h and nh.snap and nh.snap.map
	local look = player:get_look_dir()
	local flat = vector.new(look.x, 0, look.z)
	if not map or vector.length(flat) < 0.3 then
		return nil -- (looking steeply down or up: not through it)
	end
	flat = vector.normalize(flat)
	local base = player:get_pos()
	local bx, by = U.pos_to_tile(base)
	for d = 0.25, U.TILE * 1.5, 0.25 do
		local tx, ty = U.pos_to_tile(vector.add(base, vector.multiply(flat, d)))
		if tx ~= bx or ty ~= by then
			local i = U.idx(tx, ty)
			if math.abs(tx - h.x) <= 1 and math.abs(ty - h.y) <= 1
					and (tx ~= h.x or ty ~= h.y) and U.in_map(tx, ty)
					and map.typ[i] == U.TYP.DOOR and U.has(map.door[i], U.D_ISOPEN) then
				return {kind = "door", tx = tx, ty = ty}, d
			end
			return nil
		end
	end
	return nil
end

-- What the player is pointing at: {kind = "mon"|"square", tx, ty, mon}
function actions.pointed(player)
	local eye = vector.add(player:get_pos(), vector.new(0, 1.6, 0))
	local to = vector.add(eye, vector.multiply(player:get_look_dir(), 6))
	local door, door_d = doorway(player)
	for pt in core.raycast(eye, to, true, false) do
		-- (anything past an open doorway you look through: that door)
		if door and pt.intersection_point and (pt.type == "node" or pt.ref ~= player) then
			local d = pt.intersection_point - eye
			if math.sqrt(d.x * d.x + d.z * d.z) > door_d then
				return door
			end
		end
		if pt.type == "object" and pt.ref ~= player then
			local ent = pt.ref:get_luaentity()
			if ent and ent.name == "nhv:mon" and ent.nh_key then
				local e = nhv.mobs.mons[ent.nh_key]
				if e then
					return {kind = "mon", tx = e.x, ty = e.y, mon = e}
				end
			elseif ent and ent.name == "nhv:obj" then
				local tx, ty = U.pos_to_tile(pt.ref:get_pos())
				return {kind = "square", tx = tx, ty = ty}
			end
		elseif pt.type == "node" then
			-- an object block (a ladder...): the square it stands in
			local def = core.registered_nodes[core.get_node(pt.under).name]
			-- a door: its own square (the face you see lies on the border
			-- with the square in front of it)
			if def and def.groups and def.groups.nhv_door then
				local tx, ty = U.pos_to_tile(pt.under)
				return {kind = "door", tx = tx, ty = ty}
			end
			if def and def.groups and def.groups.nhv_prop then
				local tx, ty = U.pos_to_tile(pt.under)
				return {kind = "prop", tx = tx, ty = ty, pos = pt.under}
			end
			local p = vector.multiply(vector.add(pt.under, pt.above), 0.5)
			local tx, ty = U.pos_to_tile(p)
			-- (wx, wy: the square of the block itself, e.g. the wall)
			local wx, wy = U.pos_to_tile(pt.under)
			return {kind = "square", tx = tx, ty = ty, wx = wx, wy = wy}
		end
	end
	if door then
		return door
	end
	local h = hero()
	return {kind = "square", tx = h.x, ty = h.y}
end

-- Answer for "In what direction?": the square you point at (an
-- adjacent one gives its direction, your own gives '.'); looking steeply
-- up or down gives '<' / '>' (zapping, digging, ...).
-- ---------------------------------------------------------------- aiming
-- Throwing, firing and zapping go where the crosshair points, at any angle
-- (not just NetHack's 8 directions): "#nhvaim dx dy" before the action
-- gives NetHack the line, from your square to the square you point at (or
-- along your look when that's your own square). free: straight along your
-- look whatever you point at (zaps and spells: not locked to squares).
function actions.aim(player, free)
	local h = hero()
	if not (h and nh.snap) then
		return nil
	end
	local p = actions.pointed(player)
	local dx, dy = p.tx - h.x, p.ty - h.y
	if free or (dx == 0 and dy == 0) then
		local look = player:get_look_dir()
		dx, dy = look.x, -look.z
	end
	local m = math.max(math.abs(dx), math.abs(dy))
	if m < 1e-3 then
		return nil
	end
	return dx / m, dy / m, p
end

-- the keys that set the aim (nil: no aim)
function actions.aim_keys(player, free)
	local dx, dy = actions.aim(player, free)
	if not dx then
		return nil
	end
	return {{key = "#"}, {text = ("nhvaim %d %d"):format(math.floor(dx * 1000 + 0.5),
		math.floor(dy * 1000 + 0.5))}}
end

-- the same aim as a level world direction (for rays: straight where you
-- look, not at the middle of a square)
function actions.aim_world_dir(player)
	local dx, dy = actions.aim(player, true)
	if not dx then
		return nil
	end
	return vector.normalize(vector.new(dx, 0, -dy))
end

-- spells you'd mostly cast on yourself: unless you aim at a monster (to
-- heal your pet, say), they go to '.'
local SELF_SPELLS = {"healing"} -- (also matches "extra healing")

local function self_spell()
	local m = nh.last_menu
	if not (m and m.prompt:find(nhv.spells.PROMPT)) then
		return false
	end
	-- (the spell's name only: "cure sickness" is in the healing school)
	local name = nhv.spells.row_name(m.chosen):lower()
	for _, s in ipairs(SELF_SPELLS) do
		if name:find(s, 1, true) then
			return true
		end
	end
	return false
end

-- (no_self: the direction is where you aim, whatever spell it's for)
function actions.pointed_dir_key(player, prompt, no_self)
	local pitch = player:get_look_vertical()
	local h = hero()
	local p = actions.pointed(player)
	if p.kind ~= "mon" and not no_self and self_spell() then
		return "."
	end
	-- looking steeply up or down: up or down, where that can mean something
	-- (zapping, casting, applying - a pick-axe digs down, a wand of digging
	-- digs through the floor or brings rock down from the ceiling) -
	-- before the square under your crosshair, which looking down at the
	-- floor or up at the ceiling may well be the next one
	local cmd = nh.last_cmd or ""
	local vertical = (prompt and (prompt:find("dig") or prompt:find("zap")))
		or cmd == "z" or cmd == "Z" or cmd == "a"
	if vertical and p.kind ~= "mon" then
		if pitch > 1.0 then
			return ">"
		elseif pitch < -1.0 then
			return "<"
		end
	end
	local dx, dy = p.tx - h.x, p.ty - h.y
	-- a wall face on the edge of your own square: the wall's square
	if dx == 0 and dy == 0 and p.wx and pitch <= 1.0
			and math.abs(p.wx - h.x) <= 1 and math.abs(p.wy - h.y) <= 1 then
		dx, dy = p.wx - h.x, p.wy - h.y
	end
	if math.abs(dx) <= 1 and math.abs(dy) <= 1 and (dx ~= 0 or dy ~= 0) then
		return U.dir_key(dx, dy)
	end
	if pitch > 1.0 then
		-- your own square: '.' unless it can mean "down" here
		if prompt and (prompt:find("dig") or prompt:find("zap")) then
			return ">"
		end
		return "."
	elseif pitch < -1.0 then
		return "<"
	end
	-- something further away: the nearest of the 8 directions to where it
	-- lies (not just the signs: 6 east and 1 north is east, not north-east)
	-- (world +z is NetHack -y)
	local ddx, ddy = U.vec_to_dir(vector.new(dx, 0, -dy))
	if ddx == 0 and ddy == 0 then
		ddx, ddy = U.vec_to_dir(player:get_look_dir())
	end
	if ddx == 0 and ddy == 0 then
		return "."
	end
	return U.dir_key(ddx, ddy)
end

local function square_info(tx, ty)
	local map = nh.snap.map
	local i = U.idx(tx, ty)
	local gi = nhv.glyph_info(map.mem[i])
	local cmap = gi.kind == "cmap" and nhv.cmap_name(gi.index) or nil
	-- objects lying on a throne, altar, fountain...: NetHack shows the top
	-- one there, but what's under them (on a square you've seen) is what
	-- you act on first - sitting on the throne, not picking up
	local back = map.back and map.back[i]
	if not cmap and back and back ~= 255 and map.flags[i] % 2 == 1 then
		cmap = nhv.cmap_name(back)
	end
	return {
		typ = map.typ[i], door = map.door[i],
		cmap = cmap,
		has_obj = nhv.mobs.objs[i] ~= nil,
		mon = nhv.mobs.monster_at(tx, ty),
	}
end

local function has_bit(v, b)
	return v % (b * 2) >= b
end

local function door_closed(door)
	return has_bit(door, U.D_CLOSED) or has_bit(door, U.D_LOCKED)
end

local function door_open(door)
	return has_bit(door, U.D_ISOPEN)
end

-- The keys for a kick: at the kickable thing around you (a monster, an
-- object such as a chest or boulder, a closed door) nearest to where you
-- look, within about 65 degrees; otherwise straight where you face.
-- Forgiving on purpose: aiming the crosshair exactly at a small chest is
-- fiddly. An object on your own square (you can stand right beside a chest
-- that's "on" your square) is kicked away from you.
local KICK_CONE = math.rad(65)
function actions.kick_keys(player)
	local h = hero()
	local pos = player:get_pos()
	local look = player:get_look_dir()
	local fwd = vector.normalize(vector.new(look.x, 0, look.z))
	local keys = {}
	-- kick from where the body really is: NetHack's square catches up first
	-- (no jumping back to a square the body has left)
	local bx, by = U.pos_to_tile(pos)
	local base = {x = h.x, y = h.y}
	if (bx ~= h.x or by ~= h.y) and math.abs(bx - h.x) <= 1 and math.abs(by - h.y) <= 1
			and nhv.terrain.passable(nh.snap.map, bx, by) then
		keys[#keys + 1] = {key = "#"}
		keys[#keys + 1] = {text = ("nhvmove %d %d"):format(bx, by)}
		base = {x = bx, y = by}
	end
	local function angle_to(target)
		local to = vector.new(target.x - pos.x, 0, target.z - pos.z)
		local d = vector.length(to)
		if d < 0.01 then
			return nil, d
		end
		return math.acos(math.max(-1, math.min(1, vector.dot(fwd, to) / d))), d
	end
	-- (a monster in the kick's arc is kicked before any objects: on its
	-- square NetHack kicks it, not what's under it, and one a little off
	-- the crosshair still wins over a pile of items right ahead)
	local best, best_a, best_mon
	for dx = -1, 1 do
		for dy = -1, 1 do
			local tx, ty = base.x + dx, base.y + dy
			local target, is_mon
			if U.in_map(tx, ty) then
				-- (on your own square too: one sharing it with you)
				local mon = nhv.mobs.monster_at(tx, ty)
				local o = nhv.mobs.objs[U.idx(tx, ty)]
				if mon and mon.obj:get_pos() then
					target, is_mon = mon.obj:get_pos(), true
				elseif o and o.obj:get_pos() then
					target = o.obj:get_pos() -- (a chest... even on your own square)
				elseif dx ~= 0 or dy ~= 0 then
					local sq = square_info(tx, ty)
					if sq.typ == U.TYP.DOOR and door_closed(sq.door) then
						target = U.tile_center(tx, ty)
					end
				end
			end
			if target then
				local a, d = angle_to(target)
				-- (on your own square it must be right in front of you)
				local ok = a and a <= KICK_CONE and (dx ~= 0 or dy ~= 0 or d < 2.2)
				if ok and ((is_mon and not best_mon) or ((is_mon or not best_mon)
						and (not best_a or a < best_a))) then
					best, best_a, best_mon = {dx, dy}, a, best_mon or is_mon
				end
			end
		end
	end
	local fx, fy = U.vec_to_dir(fwd)
	if best and best[1] == 0 and best[2] == 0 then
		-- NetHack can't kick what's on your own square: kick it away from you
		keys[#keys + 1] = {key = "#"}
		keys[#keys + 1] = {text = ("nhvkickhere %d %d"):format(fx, fy)}
		return keys
	end
	keys[#keys + 1] = {key = "\4"}
	keys[#keys + 1] = {key = best and U.dir_key(best[1], best[2]) or U.dir_key(fx, fy)}
	return keys
end


local function stair_key(sq)
	local c = sq.cmap or ""
	if c:match("dnstair") or c:match("dnladder") then
		return ">"
	elseif c:match("upstair") or c:match("upladder") then
		return "<"
	end
end

-- Actions for what is pointed at: returns list, primary (may be nil)
function actions.context(player)
	local h = hero()
	local p = actions.pointed(player)
	local tx, ty = p.tx, p.ty
	-- an object (a ladder...) in a stairs or ladder square: a tap climbs it,
	-- stepping onto its square first if you're next to it
	if p.kind == "prop" and math.abs(tx - h.x) <= 1 and math.abs(ty - h.y) <= 1 then
		local key = stair_key(square_info(tx, ty))
		if not key then
			local slot = nhv.terrain.slot_at(tx, ty) or ""
			key = (slot:match("_up$") and "<") or (slot:match("_down$") and ">") or nil
		end
		if key then
			local keys = {{key = key}}
			if tx ~= h.x or ty ~= h.y then
				keys = {{key = "#"}, {text = ("nhvmove %d %d"):format(tx, ty)}, {key = key}}
			end
			local a = act(key == "<" and "Climb up" or "Climb down", keys)
			return {a}, a
		end
	end
	-- a monster you point at (within reach: actions.pointed) is the one you
	-- act on, wherever NetHack has its square: in free movement it can stand
	-- right in front of you two squares away, or share your own square.
	-- Chat goes to it by id, not by a direction it may have left.
	local pm = p.kind == "mon" and p.mon
	if pm and pm.id and pm.id > 0 then
		local peaceful = pm.mon and U.has(pm.mon.flags, U.MON_PEACEFUL)
		local list = {act("Chat", ext("nhvchat " .. pm.id)), act("Fight", ext("nhvattack " .. pm.id)),
			act("Throw at it", "t"), act("Apply at it", "a")}
		return list, peaceful and list[1] or nil
	end
	-- far away squares: act on your own square
	if math.abs(tx - h.x) > 1 or math.abs(ty - h.y) > 1 then
		if p.kind == "door" then
			return {}, nil, "The door is too far away: step up to it."
		end
		tx, ty = h.x, h.y
	elseif p.kind == "door" and tx == h.x and ty == h.y then
		return {}, nil, "You're standing in the doorway: step out of it first."
	end
	local sq = square_info(tx, ty)
	local list, primary = {}, nil
	local function add(a, is_primary)
		list[#list + 1] = a
		if is_primary and not primary then
			primary = a
		end
	end
	local key = U.dir_key(tx - h.x, ty - h.y)
	local mon = p.kind == "mon" and p.mon or sq.mon

	if mon and (tx ~= h.x or ty ~= h.y) then
		local peaceful = mon.mon and U.has(mon.mon.flags, U.MON_PEACEFUL)
		add(act("Chat", mon.id and mon.id > 0 and ext("nhvchat " .. mon.id) or ext("chat", {key = key})),
			peaceful)
		-- (a long worm's tail: that segment)
		add(act("Fight", ext(mon.tail_of and ("nhvattack %d %d %d"):format(mon.tail_of, tx, ty)
			or ("nhvattack " .. (mon.id or 0)))))
		add(act("Throw at it", "t"))
		add(act("Apply at it", "a"))
		return list, primary
	end

	-- chests, boxes and bags on the square (yours or next to you): a tap opens them
	for _, o in ipairs(core.nh_get_floor_objects(tx, ty) or {}) do
		if nhv.containers.is_container(o) then
			local name = o.name:gsub("^an? ", "")
			add(act("Open " .. (#name > 28 and name:sub(1, 26) .. ".." or name),
				ext("nhvloot " .. o.id)), true)
		end
	end

	if tx == h.x and ty == h.y then
		local sk = stair_key(sq)
		if sk == ">" then
			add(act("Go down", ">"), true)
		elseif sk == "<" then
			add(act("Go up", "<"), true)
		end
		if sq.has_obj then
			-- (picking up is F, or a tap - below)
			add(info_act("Look here", ":"))
		end
		local c = sq.cmap or ""
		if c == "S_fountain" then
			add(act("Drink", "q"), true)
			add(act("Dip", ext("dip")))
		elseif c == "S_sink" then
			add(act("Drink", "q"), true)
			add(act("Dip", ext("dip")))
		elseif c == "S_altar" then
			add(act("Offer", ext("offer")), true)
			add(act("Drop on altar", "D"))
		elseif c == "S_throne" then
			add(act("Sit on throne", ext("sit")), true)
		elseif c == "S_grave" then
			add(act("Dig up grave", "a"))
		end
		-- things lying here and nothing else to do with this square (no
		-- stairs, fountain, altar, box, grave...): a tap picks them up (it
		-- isn't on the wheel: picking up is F)
		if sq.has_obj and not primary and c ~= "S_grave" then
			primary = act("Pick up", ",")
		end
		-- (things you do by yourself are on the Shift wheel)
		return list, primary
	end

	if sq.typ == U.TYP.DOOR then
		if door_closed(sq.door) then
			add(act("Open", "o" .. key), true)
			add(act("Unlock", "a"))
		elseif door_open(sq.door) then
			add(act("Close", "c" .. key), true)
		end
	end
	-- (kicking and searching are on the hotbar)
	add(act("Untrap", ext("untrap", {key = key})))
	return list, primary
end

-- Shift + right click: things you do by yourself
function actions.self_context()
	local list = {
		act("Drop by type", "D"), -- (NetHack's kinds first: all cursed things...)
		act("Rest 20 turns", "20s"),
		act("Pray", ext("pray")),
		act("Sit", ext("sit")),
		act("Engrave", "E"),
		act("Loot", ext("loot")),
		act("Jump", ext("jump")),
		info_act("Look here", ":"),
		info_act("Attributes", "\24"),
		act("Save & quit", "S"),
	}
	-- (picking up is F, searching X: a tap does nothing - pick one)
	return list, nil
end

-- dropping several things at once: NetHack's D, every kind of item listed
-- to tick (its first question, which kinds, answered "All types")
local DROP_MANY = {label = "Drop", keys = "D",
	answers = {{pattern = "^Drop what type of items", menu = "a"}}}

-- Alt + right click: use an item (NetHack asks which)
function actions.item_verbs()
	-- (eating and zapping are on the hotbar)
	return {
		act("Quaff", "q"), act("Read", "r"), DROP_MANY, act("Throw", "t"),
		act("Apply", "a"), act("Wear", "W"), act("Take off", "T"), act("Put on", "P"),
		act("Remove", "R"), act("Wield", "w"),
		act("Swap weapons", "x"), act("Dual wield", ext("twoweapon")),
	}, nil -- (a tap does nothing: pick one)
end

-- Ctrl + right click: magic and abilities
function actions.magic()
	local list = {
		info_act("Known spells", "+"),
		act("Turn undead", ext("turn")),
		act("Monster ability", ext("monster")),
		act("Invoke", ext("invoke")),
		info_act("Enhance skills", ext("enhance")),
		act("Teleport", "\20"),
	}
	return list, nil -- (a tap does nothing: casting is on the hotbar)
end

-- ---------------------------------------------------------------- items
local function lname(o)
	return o.name:lower()
end

-- item actions: list, primary
function actions.item_context(o)
	local list, primary = {}, nil
	local function add(label, keys, is_primary)
		local a = act(label, keys)
		list[#list + 1] = a
		if is_primary and not primary then
			primary = a
		end
	end
	local worn = U.has(o.flags, U.OBJ.WORN)
	local wielded = U.has(o.flags, U.OBJ.WIELDED)
	local alt = U.has(o.flags, U.OBJ.ALTWEP)
	local c = o.oclass
	local inv = o.invlet
	if nhv.containers.is_container(o) then
		add("Open", ext("nhvloot " .. o.id), true)
	end
	if wielded or alt then
		add("Swap weapons", "x", true)
	end
	if c == OC.WEAPON then
		if not wielded then
			add("Wield", "w" .. inv, true)
		end
		add("Throw", "t" .. inv)
		add("Quiver", "Q" .. inv)
	elseif c == OC.ARMOR then
		add(worn and "Take off" or "Wear", (worn and "T" or "W") .. inv, true)
	elseif c == OC.RING or c == OC.AMULET then
		add(worn and "Remove" or "Put on", (worn and "R" or "P") .. inv, true)
	elseif c == OC.TOOL then
		add("Apply", "a" .. inv, true)
		-- tools that ask which way (a stethoscope, mirror, camera, horn -
		-- not a unicorn horn, which is always for you): at yourself, as
		-- looking straight down would
		local n = lname(o)
		if (n:match("stethoscope") or n:match("mirror") or n:match("looking glass")
				or n:match("camera") or n:match("horn")) and not n:match("unicorn") then
			list[#list + 1] = {label = "Apply to yourself", keys = "a" .. inv,
				answers = {{pattern = "[Dd]irection", key = "."}}}
		end
		if lname(o):match("blindfold") or lname(o):match("towel") or lname(o):match("lenses") then
			add(worn and "Remove" or "Put on", (worn and "R" or "P") .. inv)
		end
		if not wielded then
			add("Wield", "w" .. inv)
		end
	elseif c == OC.FOOD then
		add("Eat", "e" .. inv, true)
	elseif c == OC.POTION then
		add("Quaff", "q" .. inv, true)
		add("Throw", "t" .. inv)
	elseif c == OC.SCROLL or c == OC.SPBOOK then
		add("Read", "r" .. inv, true)
	elseif c == OC.WAND then
		add("Zap", "z" .. inv, true)
		-- (looking down zaps the floor: this zaps you)
		add("Zap yourself", {{key = "z"}, {key = inv}, {key = "."}})
		add("Engrave", "E" .. inv)
		add("Break", "a" .. inv)
	elseif c == OC.GEM or c == OC.ROCK then
		add("Throw", "t" .. inv, true)
		add("Quiver", "Q" .. inv)
	end
	if wielded then
		add("Unwield", "w-")
	end
	add("Drop", "d" .. inv)
	-- (some of a stack: how many is asked first - ui.lua)
	if (o.quan or 1) > 1 then
		list[#list + 1] = {label = "Drop some...", obj = o, func = function(_, obj)
			nhv.ui.show_drop_count(obj)
		end}
	end
	add("Name type", {{key = "#"}, {text = "call"}, {menu = "o"}, {key = inv}})
	add("Adjust letter", {{key = "#"}, {text = "adjust"}, {key = inv}})
	-- (its NetHackWiki page: as far as you know what it is - wiki.lua)
	list[#list + 1] = {label = "Wiki", obj = o, func = function(_, obj)
		nhv.wiki.open(nhv.wiki.title_for_object(obj))
	end}
	return list, primary
end

-- legacy names used by the inventory screen
function actions.item_actions(o)
	return (actions.item_context(o))
end

function actions.do_item_action(player, o, a)
	if a.func then
		return a.func(player, o) -- (not a NetHack command: the wiki...)
	end
	actions.run(a, {kind = "item"})
end

-- ---------------------------------------------------------------- hooking up
-- left click: attack (right click and E are handled by the wheel)
local function on_use(itemstack, user, pointed)
	if user and user:is_player() then
		if user:get_player_control().sneak then
			actions.fire(user)
		elseif pointed and pointed.type == "object" and pointed.ref:get_luaentity()
				and pointed.ref:get_luaentity().nh_key then
			actions.attack_entity(user, pointed.ref:get_luaentity())
		else
			actions.attack(user)
		end
	end
	return nil
end

local function noop()
	return nil
end

-- Q does nothing (it would drop your weapon); drop from the inventory
local function on_drop(itemstack)
	return itemstack
end

-- (bare-handed, your hand is a fist: nhv_tiles/textures/nhv_weapon_Fist.png,
-- drawn like a wielded weapon's sprite instead of the engine's plain block)
core.override_item("", {
	wield_image = "nhv_weapon_Fist.png", inventory_image = "nhv_weapon_Fist.png",
	on_use = on_use, on_place = noop, on_secondary_use = noop, range = 5,
	tool_capabilities = {full_punch_interval = 0.3, max_drop_level = 0,
		groupcaps = {}, damage_groups = {}},
})
-- (a fist in gloves is held as nhv:fist: it acts as the bare hand)
core.override_item("nhv:fist", {
	on_use = on_use, on_place = noop, on_secondary_use = noop, on_drop = on_drop, range = 5,
	tool_capabilities = {full_punch_interval = 0.3, max_drop_level = 0,
		groupcaps = {}, damage_groups = {}},
})
for i = 0, nhv_tiles.count - 1 do
	core.override_item(nhv_tiles.item(i), {
		on_use = on_use, on_place = noop, on_secondary_use = noop,
		on_drop = on_drop, range = 5,
	})
end

-- keys without item callbacks
local prev = {}
-- holding the attack button repeats only once it's really held: a click
-- that lasts a little longer than a quick attack mustn't attack twice
local HOLD_REPEAT_US = 450000
local attack_down_since = nil
core.register_globalstep(function()
	local player = nhv.player.get()
	if not player then
		return
	end
	local ctl = player:get_player_control()
	local function pressed(k)
		return ctl[k] and not prev[k]
	end
	if pressed("dig") then
		attack_down_since = core.get_us_time()
	elseif not ctl.dig then
		attack_down_since = nil
	end
	if pressed("jump") and actions.climb_out(player) then -- luacheck: ignore 542
		-- in a pit: Space climbs out at its edge
	elseif pressed("jump") and nh.ready() and not nhv.clock.busy() then
		nhv.jump.press() -- (a tap waits a turn; held, it aims a jump: jump.lua)
	end
	nhv.jump.update(player, ctl.jump)
	if pressed("zoom") then
		nhv.hud.toggle_map()
	end
	-- holding the attack button keeps attacking, as fast as your actions
	-- play out (the press itself is the item's on_use; Shift is firing)
	if ctl.dig and prev.dig and attack_down_since
			and core.get_us_time() - attack_down_since >= HOLD_REPEAT_US
			and not ctl.sneak and not nhv.ui.open
			and not (nhv.wheel and nhv.wheel.is_open())
			and nh.ready() and not nhv.clock.busy() then
		actions.attack(player)
	end
	prev = {jump = ctl.jump, zoom = ctl.zoom, dig = ctl.dig}
end)

return actions
