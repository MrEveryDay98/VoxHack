-- Prefab editor drawing tools, as in a voxel editor: they work in the air
-- as well as against blocks.
--
--   /box [solid|hollow|walls] [block]
--       the Box tool in your hand. Hold left mouse and drag: a box of blocks;
--       hold right mouse and drag: a box carved out. It starts at the block
--       you point at (on its face, carving: the block itself) - or, pointing
--       at nothing, in the air in front of you - and is drawn flat along
--       that layer; hold Shift while dragging to pull it up or down. Let go
--       to build it.
--   /pencil [block]
--       the Pencil: left mouse puts a block, right mouse takes one away -
--       in the air too - and holding it down keeps drawing as you sweep.
--   /reach <n>
--       how far in front of you the tools reach into the air (default 5)
--   middle mouse
--       picks the block you point at to draw with
--
-- The block: the one in the hotbar slot just right of the tool, else the one
-- named, else the last block you placed. What they do is saved like hand
-- building, and /undo puts back the last box (or the pencil's last block).

local tools = nhv.editor_tools
local editor = nhv.editor

local draw = {}
nhv.editor_draw = draw

local RANGE = 20       -- how far they find blocks to start on
local reach = {}       -- player -> how far into the air (nodes)
local REACH = 5
local mode = {}        -- player -> "solid" | "hollow" | "walls"
local named = {}       -- player -> the block named with /box or /pencil
local stroke = {}      -- player -> what's being drawn: {kind, add, c1, c2, obj, last}

local ADD_TEX = "[fill:16x16:#40FF6060"
local CUT_TEX = "[fill:16x16:#FF404060"
local CURSOR_TEX = "[fill:16x16:#FFFFFF30"

-- ---------------------------------------------------------------- pointing
local function eye_of(player)
	return vector.add(player:get_pos(), vector.new(0, player:get_properties().eye_height or 1.625, 0))
end

-- the cell the tool points at: on the face of the block pointed at (adding)
-- or that block (carving); nothing within reach, the cell in the air ahead
local function target(player, add)
	local eye, dir = eye_of(player), player:get_look_dir()
	for pt in core.raycast(eye, vector.add(eye, vector.multiply(dir, RANGE)), false, false) do
		if pt.type == "node" then
			return add and pt.above or pt.under
		end
	end
	return vector.round(vector.add(eye, vector.multiply(dir, reach[player:get_player_name()] or REACH)))
end

-- where the view ray crosses the flat layer y (nil: it doesn't, ahead)
local function on_layer(player, y)
	local eye, dir = eye_of(player), player:get_look_dir()
	if math.abs(dir.y) < 1e-3 then
		return nil
	end
	local t = (y - eye.y) / dir.y
	if t <= 0 or t > 120 then
		return nil
	end
	local p = vector.add(eye, vector.multiply(dir, t))
	return vector.new(math.floor(p.x + 0.5), y, math.floor(p.z + 0.5))
end

-- the height the view ray points at above or below the column at p (a
-- wall through it, facing you)
local function on_column(player, p)
	local eye, dir = eye_of(player), player:get_look_dir()
	local n = vector.new(dir.x, 0, dir.z)
	local len = vector.length(n)
	if len < 1e-3 then
		return p.y
	end
	n = vector.divide(n, len)
	local t = vector.dot(vector.subtract(p, eye), n) / vector.dot(dir, n)
	if t <= 0 then
		return p.y
	end
	return math.floor(eye.y + dir.y * t + 0.5)
end

-- ---------------------------------------------------------------- the box shown
local function sorted(a, b)
	return vector.new(math.min(a.x, b.x), math.min(a.y, b.y), math.min(a.z, b.z)),
		vector.new(math.max(a.x, b.x), math.max(a.y, b.y), math.max(a.z, b.z))
end

local function show(st, minp, maxp, tex)
	if not (st.obj and st.obj:get_pos()) then
		st.obj = core.add_entity(minp, "nhv:selbox")
		if not st.obj then
			return
		end
		st.obj:set_properties({textures = {tex, tex, tex, tex, tex, tex}})
	end
	local size = vector.add(vector.subtract(maxp, minp), 1)
	st.obj:set_pos(vector.multiply(vector.add(minp, maxp), 0.5))
	st.obj:set_properties({visual_size = vector.add(size, 0.06)})
end

local function hide(st)
	if st and st.obj and st.obj:get_pos() then
		st.obj:remove()
	end
	if st then
		st.obj = nil
	end
end

-- ---------------------------------------------------------------- the block
local function material(player)
	local pname = player:get_player_name()
	local inv = player:get_inventory()
	local nxt = inv:get_stack("main", player:get_wield_index() + 1)
	local n = nxt and nxt:get_name()
	if n and n ~= "" and core.registered_nodes[n] then
		return n
	end
	return named[pname] or editor.last_placed
end

-- ---------------------------------------------------------------- doing
local function finish_box(player, st)
	local pname = player:get_player_name()
	local minp, maxp = sorted(st.c1, st.c2)
	hide(st)
	local id
	if st.add then
		local name = material(player)
		if not name then
			core.chat_send_player(pname, "Which block? Put one in the slot right of the tool, or /box <block>.")
			return
		end
		id = core.get_content_id(name)
	else
		id = core.CONTENT_AIR
	end
	local m = mode[pname] or "solid"
	local ok, msg = tools.apply(pname, minp, maxp, function(x, y, z)
		local edge_x, edge_z = x == minp.x or x == maxp.x, z == minp.z or z == maxp.z
		if m == "walls" and not (edge_x or edge_z) then
			return nil
		elseif m == "hollow" and not (edge_x or edge_z or y == minp.y or y == maxp.y) then
			return nil
		end
		return id, 0
	end)
	if not ok and msg then
		core.chat_send_player(pname, msg)
	end
end

local function pencil_at(player, st, p)
	local pname = player:get_player_name()
	local id = core.CONTENT_AIR
	if st.add then
		local name = material(player)
		if not name then
			core.chat_send_player(pname, "Which block? Put one in the slot right of the tool, or /pencil <block>.")
			st.state = "done"
			return
		end
		id = core.get_content_id(name)
	end
	tools.apply(pname, p, p, function()
		return id, 0
	end)
end

-- Each player's stroke: idle (the cursor shows where a stroke would start),
-- drawing (a button held: c1 where it began, c2 where it reaches), or done
-- (built; waiting for the buttons to be let go)
local function step(player)
	local pname = player:get_player_name()
	local item = player:get_wielded_item():get_name()
	local kind = item == "nhv:boxtool" and "box" or item == "nhv:pencil" and "pencil" or nil
	local st = stroke[pname]
	if st and st.kind ~= kind then
		hide(st)
		stroke[pname], st = nil, nil
	end
	if not kind then
		return
	end
	if not st then
		st = {kind = kind, state = "idle"}
		stroke[pname] = st
	end
	local ctl = player:get_player_control()
	local down = ctl.dig or ctl.place
	if st.state == "done" then
		if not down then
			st.state = "idle"
		end
		return
	end
	if st.state == "idle" then
		if not down then
			local p = target(player, true)
			show(st, p, p, CURSOR_TEX)
			return
		end
		-- (pressed: a stroke begins - left mouse adds, right mouse carves)
		hide(st)
		st.add = ctl.dig and true or false
		st.c1 = target(player, st.add)
		st.c2, st.last = st.c1, st.c1
		st.state = "drawing"
		if kind == "pencil" then
			pencil_at(player, st, st.c1)
			if st.state == "done" then
				return -- (no block to draw with)
			end
		end
	end
	local held = (st.add and ctl.dig) or (not st.add and ctl.place)
	if not held then
		if kind == "box" then
			finish_box(player, st)
		else
			hide(st)
		end
		st.state = down and "done" or "idle"
		return
	end
	if kind == "box" then
		if ctl.sneak then
			-- (Shift: up or down from the layer drawn so far)
			st.c2 = vector.new(st.c2.x, on_column(player, st.c2), st.c2.z)
		else
			local p = on_layer(player, st.c1.y) or target(player, st.add)
			st.c2 = vector.new(p.x, st.c2.y, p.z)
		end
		local minp, maxp = sorted(st.c1, st.c2)
		show(st, minp, maxp, st.add and ADD_TEX or CUT_TEX)
	else
		local p = target(player, st.add)
		if not vector.equals(p, st.last) then
			st.last = p
			pencil_at(player, st, p)
		end
		show(st, p, p, st.add and ADD_TEX or CUT_TEX)
	end
end

core.register_globalstep(function()
	for _, player in ipairs(core.get_connected_players()) do
		step(player)
	end
end)

core.register_on_leaveplayer(function(player)
	hide(stroke[player:get_player_name()])
	stroke[player:get_player_name()] = nil
end)

-- ---------------------------------------------------------------- the items
-- (the clicks themselves do nothing: the strokes are read from the mouse
-- buttons as they're held - step above)
local function noop()
	return nil
end
for name, def in pairs({
	["nhv:boxtool"] = {"Box tool\nDrag with left mouse: build a box, right mouse: carve one out"
		.. "\n(Shift while dragging: up or down)", "#40FF60"},
	["nhv:pencil"] = {"Pencil\nLeft mouse: put a block, right mouse: take one away (hold to keep drawing)",
		"#FFD040"},
}) do
	core.register_tool(name, {
		description = def[1],
		inventory_image = ("[fill:16x16:%s^[fill:10x10:3,3:#202020"):format(def[2]),
		groups = {not_in_creative_inventory = 1},
		range = RANGE,
		on_use = noop, on_place = noop, on_secondary_use = noop,
	})
end

local function hold(pname, item)
	local player = core.get_player_by_name(pname)
	if not player then
		return false
	end
	local inv = player:get_inventory()
	local i = player:get_wield_index()
	local list = inv:get_list("main")
	-- (put back what was in the hand if it was something else)
	if list[i] and not list[i]:is_empty() and list[i]:get_name() ~= item then
		inv:add_item("main", list[i])
	end
	inv:set_stack("main", i, ItemStack(item))
	return true
end

local function cmd(name, params, desc, fn)
	core.register_chatcommand(name, {params = params, description = desc, func = fn})
end

cmd("box", "[solid|hollow|walls] [block]", "Hold the Box tool: drag to build a box (left mouse) "
	.. "or carve one out (right mouse), in the air too", function(pname, param)
	for word in param:gmatch("%S+") do
		if word == "solid" or word == "hollow" or word == "walls" then
			mode[pname] = word
		else
			local b = tools.block(word)
			if not b or b == "air" then
				return false, ("No block called \"%s\"."):format(word)
			end
			named[pname] = b
		end
	end
	if not hold(pname, "nhv:boxtool") then
		return false
	end
	return true, ("Box tool (%s) in hand: drag with left mouse to build, right mouse to carve; "
		.. "Shift while dragging for height. The block: the slot right of the tool, else %s.")
		:format(mode[pname] or "solid", named[pname] or editor.last_placed or "the last one you placed")
end)

cmd("pencil", "[block]", "Hold the Pencil: put (left mouse) or take away (right mouse) single blocks, "
	.. "in the air too", function(pname, param)
	if param:match("%S") then
		local b = tools.block(param)
		if not b or b == "air" then
			return false, ("No block called \"%s\"."):format(param)
		end
		named[pname] = b
	end
	if not hold(pname, "nhv:pencil") then
		return false
	end
	return true, "Pencil in hand: left mouse puts a block, right mouse takes one away; hold to keep drawing."
end)

-- Middle mouse (the VoxHack build of Luanti sends "/nhvkey look"; in the
-- editor, the game's other keys do nothing): pick the block you point at -
-- holding the Box tool or the Pencil, into the slot right of it (what they
-- draw with), else into your hand
core.register_chatcommand("nhvkey", {
	description = "(VoxHack) a game key; in the editor, middle mouse picks a block",
	func = function(pname, param)
		local player = core.get_player_by_name(pname)
		if param ~= "look" or not player then
			return true
		end
		local eye, dir = eye_of(player), player:get_look_dir()
		local name
		for pt in core.raycast(eye, vector.add(eye, vector.multiply(dir, RANGE)), false, false) do
			if pt.type == "node" then
				name = core.get_node(pt.under).name
				break
			end
		end
		local def = name and core.registered_nodes[name]
		if not def or name:match("^nhv:editor_") then
			return true
		end
		local inv = player:get_inventory()
		local i = player:get_wield_index()
		local item = player:get_wielded_item():get_name()
		if item == "nhv:boxtool" or item == "nhv:pencil" then
			i = i + 1
		end
		if i > inv:get_size("main") then
			i = player:get_wield_index()
		end
		inv:set_stack("main", i, ItemStack(name))
		named[pname] = name
		return true, "Drawing with: " .. (def.description or name):match("^[^\n]*")
	end,
})

cmd("reach", "<n>", "How far the Box tool and Pencil reach into the air in front of you (1-30)",
	function(pname, param)
		local n = tonumber(param)
		if not n then
			return true, ("Reach: %d (/reach 1-30)"):format(reach[pname] or REACH)
		end
		reach[pname] = math.max(1, math.min(30, math.floor(n + 0.5)))
		return true, ("Reach: %d"):format(reach[pname])
	end)

return draw
