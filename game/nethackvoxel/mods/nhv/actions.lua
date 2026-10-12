-- Player actions and controls.
--
--   Left click        attack the monster in reach nearest your crosshair
--   Shift+left click  fire your quivered ammo where you look
--   Right click       interact: open/close doors, use stairs, pick up
--   Shift+right click list everything you can do on/at a square
--   E (aux1)          actions for the selected hotbar item
--   Q (drop)          drop the selected hotbar item
--   Space (jump)      wait/search for one turn
--   Z (zoom)          toggle the large overhead map
--   I                 inventory

local U = nhv.util
local nh = nhv.nh
local actions = {}
nhv.actions = actions

local OC = U.OCLASS

local function msg(t)
	nhv.hud.message(t)
end

local function hero()
	return nh.snap and nh.snap.hero
end

local function busy()
	if not nh.ready() then
		return true
	end
	return false
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
-- and closest to the crosshair
local function attack_target(player, prefer_id)
	local pos = player:get_pos()
	local look = player:get_look_dir()
	local best, best_a
	for _, e in pairs(nhv.mobs.mons) do
		local body = e.id and e.id > 0 and nhv.sim.body(e.id)
		if body then
			local d = vector.distance(vector.new(pos.x, 0, pos.z), body.pos)
			local reach = body.r + nhv.sim.HERO_R + nhv.sim.REACH + 0.6
			if d <= reach then
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

function actions.attack(player, prefer_id)
	if busy() or nhv.clock.busy() then
		return
	end
	local h = hero()
	if U.has(h.flags, U.HERO.SWALLOWED) then
		nhv.clock.act("Fl", {kind = "attack"})
		return
	end
	local t = attack_target(player, prefer_id)
	if t then
		nhv.clock.act({{key = "#"}, {text = "nhvattack " .. t.id}}, {kind = "attack"})
	else
		-- a swing at nothing still takes the time a swing takes
		nhv.clock.act({{key = "#"}, {text = "nhvtick"}}, {kind = "swing"})
	end
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

-- ---------------------------------------------------------------- squares
local function square_of_pointed(pointed)
	if pointed and pointed.type == "node" then
		-- the node you point at, nudged toward the face you hit
		local p = vector.multiply(vector.add(pointed.under, pointed.above), 0.5)
		return U.pos_to_tile(p)
	elseif pointed and pointed.type == "object" then
		local pos = pointed.ref:get_pos()
		if pos then
			return U.pos_to_tile(pos)
		end
	end
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

local function door_closed(door)
	return door % (U.D_CLOSED * 2) >= U.D_CLOSED or door % (U.D_LOCKED * 2) >= U.D_LOCKED
end

local function door_open(door)
	return door % (U.D_ISOPEN * 2) >= U.D_ISOPEN
end

local function stair_key(sq)
	local c = sq.cmap or ""
	if c:match("dnstair") or c:match("dnladder") then
		return ">"
	elseif c:match("upstair") or c:match("upladder") then
		return "<"
	end
end

-- everything you can do at a square: list of {label=, keys=}
local function square_actions(tx, ty)
	local h = hero()
	local sq = square_info(tx, ty)
	local acts = {}
	local function add(label, keys)
		acts[#acts + 1] = {label = label, keys = keys}
	end
	local dx, dy = tx - h.x, ty - h.y
	if dx == 0 and dy == 0 then
		local sk = stair_key(sq)
		if sk == ">" then
			add("Go down", ">")
		elseif sk == "<" then
			add("Go up", "<")
		end
		add("Pick up", ",")
		add("Look here", ":")
		local c = sq.cmap or ""
		if c == "S_fountain" then
			add("Drink from the fountain", "q")
			add("Dip into the fountain", {{key = "#"}, {text = "dip"}})
		elseif c == "S_sink" then
			add("Drink from the sink", "q")
			add("Kick the sink", "\4.")
		elseif c == "S_altar" then
			add("Offer a sacrifice", {{key = "#"}, {text = "offer"}})
			add("Drop items on the altar (identify B/U/C)", "D")
		elseif c == "S_throne" then
			add("Sit on the throne", {{key = "#"}, {text = "sit"}})
		end
		add("Search (1 turn)", "s")
		add("Rest (20 turns)", "20s")
		add("Sit", {{key = "#"}, {text = "sit"}})
		add("Pray", {{key = "#"}, {text = "pray"}})
		add("Loot a container here", {{key = "#"}, {text = "loot"}})
		add("Engrave", "E")
		add("Look at your surroundings (discoveries)", "\\")
		add("Show attributes (^X)", "\24")
		add("Save and quit", "S")
		return acts
	end
	if math.abs(dx) > 1 or math.abs(dy) > 1 then
		return acts
	end
	local key = U.dir_key(dx, dy)
	if sq.typ == U.TYP.DOOR then
		if door_closed(sq.door) then
			add("Open the door", "o" .. key)
			add("Kick the door", "\4" .. key)
			add("Force the lock", {{key = "#"}, {text = "force"}})
			add("Check for traps", {{key = "#"}, {text = "untrap"}, {key = key}})
		elseif door_open(sq.door) then
			add("Close the door", "c" .. key)
		end
	end
	if sq.mon then
		add("Fight", "F" .. key)
		add("Chat", {{key = "#"}, {text = "chat"}, {key = key}})
	end
	add("Kick", "\4" .. key)
	add("Search around you", "s")
	return acts
end

local function run_keys(keys, info, secs)
	nhv.clock.act(keys, info or {kind = "interact"})
end

-- Right click: the most likely action for what you point at.
function actions.interact(player, pointed, menu)
	if busy() then
		return
	end
	local h = hero()
	local tx, ty = square_of_pointed(pointed)
	if not tx then
		tx, ty = h.x, h.y
	end
	-- pointing at the floor of a far square while standing next to it is
	-- usually meant for the square you are on
	if math.abs(tx - h.x) > 1 or math.abs(ty - h.y) > 1 then
		tx, ty = h.x, h.y
	end
	if menu then
		actions.show_square_menu(tx, ty)
		return
	end
	local sq = square_info(tx, ty)
	if tx == h.x and ty == h.y then
		local sk = stair_key(sq)
		if sk then
			run_keys(sk, {kind = "stairs"})
		elseif sq.has_obj then
			run_keys(",", {kind = "pickup"})
		else
			actions.show_square_menu(tx, ty)
		end
		return
	end
	local key = U.dir_key(tx - h.x, ty - h.y)
	if sq.typ == U.TYP.DOOR and door_closed(sq.door) then
		run_keys("o" .. key, {kind = "door"})
	elseif sq.typ == U.TYP.DOOR and door_open(sq.door) and not sq.mon and not sq.has_obj then
		run_keys("c" .. key, {kind = "door"})
	elseif sq.mon then
		run_keys({{key = "#"}, {text = "chat"}, {key = key}}, {kind = "chat"})
	else
		actions.show_square_menu(tx, ty)
	end
end

function actions.show_square_menu(tx, ty)
	local acts = square_actions(tx, ty)
	if #acts == 0 then
		return
	end
	actions.square_acts = acts
	local E = core.formspec_escape
	local h = 1.6 + #acts * 0.8
	local fs = {("formspec_version[6]size[9,%f]bgcolor[#000000C0;true]"):format(h),
		"label[0.5,0.6;What do you want to do?]"}
	for k, a in ipairs(acts) do
		fs[#fs + 1] = ("button[0.5,%f;8,0.7;sq_%d;%s]"):format(1.1 + (k - 1) * 0.8, k, E(a.label))
	end
	local player = nhv.player.get()
	core.show_formspec(player:get_player_name(), "nhv:square", table.concat(fs))
end

core.register_on_player_receive_fields(function(player, formname, fields)
	if formname ~= "nhv:square" then
		return
	end
	for k in pairs(fields) do
		local n = k:match("^sq_(%d+)$")
		if n and actions.square_acts then
			local a = actions.square_acts[tonumber(n)]
			core.close_formspec(player:get_player_name(), "nhv:square")
			if a and nh.ready() then
				run_keys(a.keys, {kind = "square"})
			end
		end
	end
	return true
end)

-- ---------------------------------------------------------------- items
local function lname(o)
	return o.name:lower()
end

function actions.item_actions(o)
	local acts = {}
	local function add(label, keys)
		acts[#acts + 1] = {label = label, keys = keys}
	end
	local worn = U.has(o.flags, U.OBJ.WORN)
	local wielded = U.has(o.flags, U.OBJ.WIELDED)
	local c = o.oclass
	if c == OC.WEAPON then
		if not wielded then
			add("Wield", "w")
		end
		add("Throw (where you look)", "t")
		add("Put in quiver", "Q")
		add("Fire from quiver (where you look)", "f")
	elseif c == OC.ARMOR then
		add(worn and "Take off" or "Wear", worn and "T" or "W")
	elseif c == OC.RING or c == OC.AMULET then
		add(worn and "Remove" or "Put on", worn and "R" or "P")
	elseif c == OC.TOOL then
		add("Apply / use (where you look)", "a")
		if lname(o):match("blindfold") or lname(o):match("towel") or lname(o):match("lenses") then
			add(worn and "Remove" or "Put on", worn and "R" or "P")
		end
		if not wielded then
			add("Wield", "w")
		end
		if U.has(o.flags, U.OBJ.CONTAINER) then
			add("Look inside / put in / take out", "a")
		end
	elseif c == OC.FOOD then
		add("Eat", "e")
	elseif c == OC.POTION then
		add("Quaff", "q")
		add("Throw (where you look)", "t")
	elseif c == OC.SCROLL or c == OC.SPBOOK then
		add("Read", "r")
	elseif c == OC.WAND then
		add("Zap (where you look)", "z")
		add("Engrave with it", "E")
		add("Apply (break it!)", "a")
	elseif c == OC.GEM or c == OC.ROCK then
		add("Throw (where you look)", "t")
		add("Put in quiver", "Q")
	end
	if wielded then
		add("Stop wielding (bare hands)", {{key = "w"}, {key = "-"}})
	end
	add("Drop", "d")
	add("Name this type of object", {{key = "#"}, {text = "call"}})
	add("Adjust (change its letter)", {{key = "#"}, {text = "adjust"}})
	return acts
end

function actions.do_item_action(player, o, a)
	if not nh.ready() then
		return
	end
	local keys = a.keys
	if type(keys) == "string" then
		-- "w" + "-" style actions already carry their argument
		if keys == "f" then
			keys = {{key = "f"}}
		else
			keys = {{key = keys}, {key = o.invlet}}
		end
		if #a.keys > 1 then
			keys = {}
			for ch in a.keys:gmatch(".") do
				keys[#keys + 1] = {key = ch}
			end
			keys[#keys + 1] = {key = o.invlet}
		end
	else
		local k2 = {}
		for _, k in ipairs(keys) do
			k2[#k2 + 1] = k
		end
		-- extended commands that act on an item ask for it next
		if keys[1].key == "#" and (keys[2].text == "call" or keys[2].text == "adjust") then
			-- #call asks what kind of thing to name: answer "the type"
			if keys[2].text == "call" then
				k2[#k2 + 1] = {menu = "o"}
			end
			k2[#k2 + 1] = {key = o.invlet}
		end
		keys = k2
	end
	nhv.clock.act(keys, {kind = "item"})
end

-- ---------------------------------------------------------------- hooking up
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

local function on_place(itemstack, placer, pointed)
	if placer and placer:is_player() then
		actions.interact(placer, pointed, placer:get_player_control().sneak)
	end
	return nil
end

local function on_drop(itemstack, dropper)
	local invlet = itemstack:get_meta():get_string("nhv_invlet")
	if invlet ~= "" and nh.ready() then
		nhv.clock.act({{key = "d"}, {key = invlet}}, {kind = "drop"})
	end
	return itemstack
end

local overrides = {
	on_use = on_use,
	on_place = on_place,
	on_secondary_use = on_place,
	on_drop = on_drop,
	range = 5,
}

core.override_item("", {
	on_use = on_use,
	on_place = on_place,
	on_secondary_use = on_place,
	range = 5,
	tool_capabilities = {full_punch_interval = 0.3, max_drop_level = 0,
		groupcaps = {}, damage_groups = {}},
})
for i = 0, nhv_tiles.count - 1 do
	core.override_item(nhv_tiles.item(i), overrides)
end

-- keys without item callbacks: watch the controls for presses
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
	if pressed("aux1") then
		local st = player:get_wielded_item()
		local invlet = st:get_meta():get_string("nhv_invlet")
		if invlet ~= "" then
			nhv.ui.show_item_menu(invlet)
		end
	end
	if pressed("jump") and nh.ready() then
		nhv.clock.act({{key = "#"}, {text = "nhvtick"}}, {kind = "wait"})
	end
	if pressed("zoom") then
		nhv.hud.toggle_map()
	end
	prev = {aux1 = ctl.aux1, jump = ctl.jump, zoom = ctl.zoom}
end)

return actions
