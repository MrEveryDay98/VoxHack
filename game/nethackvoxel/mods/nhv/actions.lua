-- Player actions and controls.
--
--   Left click        attack the monster in reach nearest your crosshair
--   Shift+left click  fire your quivered ammo where you look
--   Right click       tap: the obvious action for what you point at
--                     (open a door, take the stairs, pick up, chat...)
--                     hold: action wheel for it - move the mouse toward
--                     an action and let go
--   Shift+right click the same for yourself (search, pray, rest...)
--   Alt+right click   use an item (eat, quaff, read, zap, wear...)
--   Ctrl+right click  magic and abilities (cast, turn undead, ...)
--   E (aux1)          same, for your wielded weapon
--   1-5               the hotbar's action keys (hotbar.lua)
--   T                 NetHack command line (hotbar.lua)
--   Space (jump)      wait/search for one turn
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

function actions.run(a, info)
	if not a or busy() then
		return
	end
	if a.free then
		nh.act(a.keys, info or {kind = "info"})
	elseif not nhv.clock.busy() then -- (the last action has played out)
		actions.swing()
		nhv.clock.act(a.keys, info or {kind = "action"})
	end
end

-- One arm swing (right-click doesn't swing by itself; see hud.lua)
local swing_state = false
-- (dual wielding, the left hand follows a moment later: NetHack hits with
-- both weapons)
local off_swing_state = false
function actions.swing()
	local player = nhv.player.get()
	if player then
		swing_state = not swing_state
		player:hud_set_flags({nhv_swing = swing_state})
		local h = nhv.nh.snap and nhv.nh.snap.hero
		if h and U.has(h.flags, U.HERO.TWOWEAP) then
			core.after(0.15, function()
				if player:is_player() then
					off_swing_state = not off_swing_state
					player:hud_set_flags({nhv_off_swing = off_swing_state})
				end
			end)
		end
	end
end

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
				local a = angle_between(look, vector.subtract(body.pos, pos))
				if e.id == prefer_id then
					a = a - 0.3
				end
				if a < ATTACK_CONE and (not best_a or a < best_a) then
					best, best_a = e, a
				end
			end
		end
	end
	return best
end

-- With a polearm or lance: a monster 2 squares away (NetHack's applying
-- range: squared distance 4, 5 with skill, 8 at expert; NetHack itself
-- says "Too far!" when your skill doesn't reach), in the direction you aim
local function pole_target(player, prefer_id)
	local h = hero()
	if not U.has(h.flags, U.HERO.POLE) then
		return nil
	end
	local pos = player:get_pos()
	local look = player:get_look_dir()
	local best, best_a
	for _, e in pairs(nhv.mobs.mons) do
		local d2 = e.id and e.id > 0 and e.x and (e.x - h.x) ^ 2 + (e.y - h.y) ^ 2
		local p = d2 and d2 >= 4 and d2 <= 8 and e.obj:get_pos()
		if p then
			local a = angle_between(look, vector.subtract(p, pos))
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

function actions.attack(player, prefer_id)
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
		actions.swing()
		nhv.sound.hook("hero_swing")
		nhv.clock.act(ext("nhvattack " .. t.id), {kind = "attack"})
	elseif far then
		-- (out of arm's reach, in a polearm's or lance's)
		actions.swing()
		nhv.sound.hook("hero_swing")
		nhv.clock.act(ext("nhvpole " .. far.id), {kind = "attack"})
	elseif actions.try_dig(player) then -- luacheck: ignore 542
		-- (digging with the wielded pick-axe; it swings)
	else
		-- a swing at nothing still takes the time a swing takes
		actions.swing()
		nhv.sound.hook("hero_swing_miss_air")
		nhv.clock.act(ext("nhvtick"), {kind = "swing"})
	end
end

-- With a pick-axe or mattock in hand, attacking rock or a wall next to you
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
	if dk ~= ">" then
		local p = actions.pointed(player)
		local wx, wy = p.wx or p.tx, p.wy or p.ty
		if not wx or math.abs(wx - h.x) > 1 or math.abs(wy - h.y) > 1
				or (wx == h.x and wy == h.y) then
			return false
		end
		local typ = nh.snap.map.typ[U.idx(wx, wy)]
		local T = U.TYP
		if not (typ and typ < T.POOL and typ ~= T.IRONBARS and typ ~= T.DOOR and typ ~= T.TREE) then
			return false
		end
	end
	actions.swing()
	nhv.clock.act({{key = "a"}, {key = tool.invlet}}, {kind = "dig"})
	return true
end

function actions.attack_entity(player, ent)
	local e = nhv.mobs.mons[ent.nh_key]
	actions.attack(player, e and e.id)
end

function actions.fire(player)
	if busy() or nhv.clock.busy() then
		return
	end
	nhv.clock.act("f", {kind = "fire"})
end

-- ---------------------------------------------------------------- pointing
-- What the player is pointing at: {kind = "mon"|"square", tx, ty, mon}
function actions.pointed(player)
	local eye = vector.add(player:get_pos(), vector.new(0, 1.6, 0))
	local to = vector.add(eye, vector.multiply(player:get_look_dir(), 6))
	for pt in core.raycast(eye, to, true, false) do
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
-- along your look when that's your own square).
function actions.aim(player)
	local h = hero()
	if not (h and nh.snap) then
		return nil
	end
	local p = actions.pointed(player)
	local dx, dy = p.tx - h.x, p.ty - h.y
	if dx == 0 and dy == 0 then
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
function actions.aim_keys(player)
	local dx, dy = actions.aim(player)
	if not dx then
		return nil
	end
	return {{key = "#"}, {text = ("nhvaim %d %d"):format(math.floor(dx * 1000 + 0.5),
		math.floor(dy * 1000 + 0.5))}}
end

-- the same aim as a level world direction from `from` (for rays)
function actions.aim_world_dir(player, from)
	local dx, dy, p = actions.aim(player)
	if not dx then
		return nil
	end
	local h = hero()
	if p and (p.tx ~= h.x or p.ty ~= h.y) then
		local t = U.tile_center(p.tx, p.ty, from.y)
		local d = vector.new(t.x - from.x, 0, t.z - from.z)
		if vector.length(d) > 0.1 then
			return vector.normalize(d)
		end
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
	return {
		typ = map.typ[i], door = map.door[i],
		cmap = gi.kind == "cmap" and nhv.cmap_name(gi.index) or nil,
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
	local best, best_a
	for dx = -1, 1 do
		for dy = -1, 1 do
			local tx, ty = base.x + dx, base.y + dy
			local target
			if U.in_map(tx, ty) then
				local mon = (dx ~= 0 or dy ~= 0) and nhv.mobs.monster_at(tx, ty)
				local o = nhv.mobs.objs[U.idx(tx, ty)]
				if mon and mon.obj:get_pos() then
					target = mon.obj:get_pos()
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
				if ok and (not best_a or a < best_a) then
					best, best_a = {dx, dy}, a
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
	-- far away squares: act on your own square
	if math.abs(tx - h.x) > 1 or math.abs(ty - h.y) > 1 then
		if p.kind == "door" then
			return {}, nil, "The door is too far away: step up to it."
		end
		tx, ty = h.x, h.y
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
		add(act("Chat", ext("chat", {key = key})), peaceful)
		add(act("Fight", ext("nhvattack " .. (mon.id or 0))))
		add(act("Fire at it", "f" .. key))
		add(act("Throw at it", "t"))
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
			add(act("Pick up", ","), true)
			add(info_act("Look here", ":"))
		end
		local c = sq.cmap or ""
		if c == "S_fountain" then
			add(act("Drink", "q"), true)
			add(act("Dip", ext("dip")))
		elseif c == "S_sink" then
			add(act("Drink", "q"), true)
			add(act("Kick sink", "\4."))
		elseif c == "S_altar" then
			add(act("Offer", ext("offer")), true)
			add(act("Drop on altar", "D"))
		elseif c == "S_throne" then
			add(act("Sit on throne", ext("sit")), true)
		elseif c == "S_grave" then
			add(act("Dig up grave", "a"))
		end
		-- (things you do by yourself are on the Shift wheel)
		return list, primary
	end

	if sq.typ == U.TYP.DOOR then
		if door_closed(sq.door) then
			add(act("Open", "o" .. key), true)
			add(act("Kick", "\4" .. key))
			add(act("Force lock", ext("force")))
			add(act("Untrap", ext("untrap", {key = key})))
		elseif door_open(sq.door) then
			add(act("Close", "c" .. key), true)
			add(act("Kick", "\4" .. key))
		end
	end
	if sq.has_obj then
		add(act("Kick object", "\4" .. key))
	end
	add(act("Search", "s"))
	add(act("Kick", "\4" .. key))
	return list, primary
end

-- Shift + right click: things you do by yourself
function actions.self_context()
	local list = {
		act("Search", "s"),
		act("Rest 20 turns", "20s"),
		act("Pray", ext("pray")),
		act("Sit", ext("sit")),
		act("Engrave", "E"),
		act("Loot", ext("loot")),
		info_act("Look here", ":"),
		info_act("Attributes", "\24"),
		act("Save & quit", "S"),
	}
	return list, list[1] -- (a tap searches)
end

-- Alt + right click: use an item (NetHack asks which)
function actions.item_verbs()
	return {
		act("Eat", "e"), act("Quaff", "q"), act("Read", "r"), act("Zap", "z"),
		act("Apply", "a"), act("Wear", "W"), act("Take off", "T"), act("Put on", "P"),
		act("Remove", "R"), act("Wield", "w"),
		act("Swap weapons", "x"), act("Dual wield", ext("twoweapon")),
	}, nil -- (a tap does nothing: pick one)
end

-- Ctrl + right click: magic and abilities
function actions.magic()
	local list = {
		act("Cast a spell", "Z"),
		act("Turn undead", ext("turn")),
		act("Monster ability", ext("monster")),
		info_act("Enhance skills", ext("enhance")),
		act("Teleport", "\20"),
	}
	return list, list[1] -- (a tap casts)
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
		add("Fire", "f")
	elseif c == OC.ARMOR then
		add(worn and "Take off" or "Wear", (worn and "T" or "W") .. inv, true)
	elseif c == OC.RING or c == OC.AMULET then
		add(worn and "Remove" or "Put on", (worn and "R" or "P") .. inv, true)
	elseif c == OC.TOOL then
		add("Apply", "a" .. inv, true)
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
	add("Name type", {{key = "#"}, {text = "call"}, {menu = "o"}, {key = inv}})
	add("Adjust letter", {{key = "#"}, {text = "adjust"}, {key = inv}})
	return list, primary
end

-- legacy names used by the inventory screen
function actions.item_actions(o)
	return (actions.item_context(o))
end

function actions.do_item_action(player, o, a)
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
for i = 0, nhv_tiles.count - 1 do
	core.override_item(nhv_tiles.item(i), {
		on_use = on_use, on_place = noop, on_secondary_use = noop,
		on_drop = on_drop, range = 5,
	})
end

-- keys without item callbacks
local prev = {}
core.register_globalstep(function()
	local player = nhv.player.get()
	if not player then
		return
	end
	local ctl = player:get_player_control()
	local function pressed(k)
		return ctl[k] and not prev[k]
	end
	if pressed("jump") and actions.climb_out(player) then -- luacheck: ignore 542
		-- in a pit: Space climbs out at its edge
	elseif pressed("jump") and nh.ready() and not nhv.clock.busy() then
		nhv.clock.act({{key = "#"}, {text = "nhvtick"}}, {kind = "wait"})
	end
	if pressed("zoom") then
		nhv.hud.toggle_map()
	end
	-- holding the attack button keeps attacking, as fast as your actions
	-- play out (the press itself is the item's on_use; Shift is firing)
	if ctl.dig and prev.dig and not ctl.sneak and not nhv.ui.open
			and not (nhv.wheel and nhv.wheel.is_open())
			and nh.ready() and not nhv.clock.busy() then
		actions.attack(player)
	end
	prev = {jump = ctl.jump, zoom = ctl.zoom, dig = ctl.dig}
end)

return actions
