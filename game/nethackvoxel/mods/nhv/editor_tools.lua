-- Prefab editor tools: box selections and what to do with them.
--
--   /sel                    the selector in your hand: left-click a block for
--                           corner 1, right-click one for corner 2
--   /fill [block]           fill the box (default: the last block you placed)
--   /clear                  empty it
--   /replace <from> [<to>]  swap one block for another (or for air)
--   /replace                the block you're looking at for the one in
--                           your hand (or for air, with an empty hand)
--   /walls [block]          the box's four sides only
--   /cutaway ceiling        the ceiling (and everything above it) off every
--                           square of the area you're on - or, with a box
--                           selected there, of the squares in the box
--   /copy                   remember the box's blocks (from corner 1)
--   /paste [rotate 90|180|270] [flip x|z] [noair]
--                           put them down with corner 1 on the block you're
--                           looking at, turned (clockwise, seen from above)
--                           and/or mirrored; noair: the copy's air doesn't
--                           clear what's there
--   /undo                   put back what the last tool changed
--   /desel                  forget the box
-- Block names can be short: "stone" finds "nhv:stone" etc. Everything the
-- tools change is saved like hand building. (Drawing with the mouse - the
-- Box tool and the Pencil: editor_draw.lua.)

local prefabs = nhv.prefabs
local editor = nhv.editor
local W, H = prefabs.W, prefabs.H

local tools = {sel = {}, undo = {}}
nhv.editor_tools = tools

local MAX_NODES = 4000000 -- (a whole Astral Plane area is about 1.7 million)

-- the editor's own blocks (plates, ground, rails) are never changed
local PROTECTED = {}
for _, n in ipairs({"nhv:editor_plate", "nhv:editor_plate_front", "nhv:editor_plate_own",
		"nhv:editor_ground", "nhv:editor_rail"}) do
	if core.registered_nodes[n] then
		PROTECTED[core.get_content_id(n)] = true
	end
end

-- ---------------------------------------------------------------- selection
core.register_entity("nhv:selbox", {
	initial_properties = {
		visual = "cube", physical = false, pointable = false, static_save = false,
		collisionbox = {0, 0, 0, 0, 0, 0}, use_texture_alpha = true, glow = 14,
		shaded = false, backface_culling = false,
		textures = {"[fill:16x16:#40A0FF50", "[fill:16x16:#40A0FF50", "[fill:16x16:#40A0FF50",
			"[fill:16x16:#40A0FF50", "[fill:16x16:#40A0FF50", "[fill:16x16:#40A0FF50"},
	},
})

local function box(pname)
	local s = tools.sel[pname]
	if not (s and s.p1 and s.p2) then
		return nil
	end
	return vector.new(math.min(s.p1.x, s.p2.x), math.min(s.p1.y, s.p2.y), math.min(s.p1.z, s.p2.z)),
		vector.new(math.max(s.p1.x, s.p2.x), math.max(s.p1.y, s.p2.y), math.max(s.p1.z, s.p2.z))
end

local function show_box(pname)
	local s = tools.sel[pname] or {}
	if s.obj and s.obj:get_pos() then
		s.obj:remove()
	end
	s.obj = nil
	local a = s.p1 or s.p2
	local minp, maxp = box(pname)
	if not minp and a then
		minp, maxp = a, a
	end
	if minp then
		local size = vector.add(vector.subtract(maxp, minp), 1)
		local obj = core.add_entity(vector.multiply(vector.add(minp, maxp), 0.5), "nhv:selbox")
		if obj then
			-- (a hair bigger than the blocks, so its faces show around them)
			obj:set_properties({visual_size = vector.add(size, 0.04)})
			s.obj = obj
		end
	end
end

local function set_corner(pname, which, pointed)
	if not pointed or pointed.type ~= "node" then
		return
	end
	tools.sel[pname] = tools.sel[pname] or {}
	tools.sel[pname][which] = pointed.under
	show_box(pname)
	local minp, maxp = box(pname)
	local msg = ("Corner %d: %s"):format(which == "p1" and 1 or 2, core.pos_to_string(pointed.under))
	if minp then
		local s = vector.add(vector.subtract(maxp, minp), 1)
		msg = msg .. ("  (box %dx%dx%d)"):format(s.x, s.y, s.z)
	end
	core.chat_send_player(pname, msg)
end

core.register_tool("nhv:selector", {
	description = "Selector\nLeft-click: corner 1, right-click: corner 2",
	inventory_image = "[fill:16x16:#40A0FF^[fill:10x10:3,3:#103050",
	groups = {not_in_creative_inventory = 1},
	range = 20,
	on_use = function(_, user, pointed)
		if user then
			set_corner(user:get_player_name(), "p1", pointed)
		end
		return nil
	end,
	on_place = function(_, user, pointed)
		if user then
			set_corner(user:get_player_name(), "p2", pointed)
		end
		return nil
	end,
	on_secondary_use = function()
		return nil
	end,
})

-- ---------------------------------------------------------------- doing
-- a block name from what was typed ("stone" -> "nhv:stone", "air")
local function block(name)
	name = (name or ""):match("^%s*(.-)%s*$")
	if name == "" then
		return nil
	end
	if name == "air" or core.registered_nodes[name] then
		return name
	end
	local hits = {}
	for n in pairs(core.registered_nodes) do
		if n:match(":" .. name:gsub("%p", "%%%0") .. "$") then
			hits[#hits + 1] = n
		end
	end
	table.sort(hits)
	return hits[1]
end

-- change every node in minp..maxp: fn(x, y, z, id, p2) -> new id, p2 (or nil
-- to leave it); keeps what was there for /undo
local function apply(pname, minp, maxp, fn)
	local s = vector.add(vector.subtract(maxp, minp), 1)
	if s.x * s.y * s.z > MAX_NODES then
		return false, ("That's %d blocks; the tools do up to %d at a time."):format(s.x * s.y * s.z, MAX_NODES)
	end
	local vm = core.get_voxel_manip()
	local e1, e2 = vm:read_from_map(minp, maxp)
	local va = VoxelArea(e1, e2)
	local ids, p2s = vm:get_data(), vm:get_param2_data()
	local before = {minp = minp, maxp = maxp, ids = {}, p2 = {}}
	local count = 0
	for z = minp.z, maxp.z do
		for y = minp.y, maxp.y do
			local vi = va:index(minp.x, y, z)
			for x = minp.x, maxp.x do
				local id, p2
				if not PROTECTED[ids[vi]] then
					id, p2 = fn(x, y, z, ids[vi], p2s[vi])
				end
				if id and (id ~= ids[vi] or (p2 or 0) ~= p2s[vi]) then
					before.ids[vi], before.p2[vi] = ids[vi], p2s[vi]
					ids[vi], p2s[vi] = id, p2 or 0
					count = count + 1
				end
				vi = vi + 1
			end
		end
	end
	if count == 0 then
		return true, "Nothing to change."
	end
	vm:set_data(ids)
	vm:set_param2_data(p2s)
	vm:write_to_map(true)
	before.e1, before.e2 = e1, e2
	tools.undo[pname] = before
	editor.mark_box(minp, maxp)
	return true, ("Changed %d blocks. (/undo puts them back)"):format(count)
end

tools.apply, tools.block = apply, block

local function need_box(pname)
	local minp, maxp = box(pname)
	if not minp then
		return nil, nil, "Select a box first: /sel, then left- and right-click its corners."
	end
	return minp, maxp
end

local AIR = core.CONTENT_AIR

local function cmd(name, params, desc, fn)
	core.register_chatcommand(name, {params = params, description = desc, func = fn})
end

cmd("sel", "", "Hold the selector (left-click: corner 1, right-click: corner 2)", function(pname)
	local player = core.get_player_by_name(pname)
	if not player then
		return false
	end
	local inv = player:get_inventory()
	local i = player:get_wield_index()
	local list = inv:get_list("main")
	-- (put back what was in the hand if it was something else)
	if list[i] and not list[i]:is_empty() and list[i]:get_name() ~= "nhv:selector" then
		inv:add_item("main", list[i])
	end
	inv:set_stack("main", i, ItemStack("nhv:selector"))
	return true, "Selector in hand: left-click a block for corner 1, right-click for corner 2."
end)

cmd("desel", "", "Forget the selected box", function(pname)
	local s = tools.sel[pname]
	if s and s.obj and s.obj:get_pos() then
		s.obj:remove()
	end
	tools.sel[pname] = {}
	return true, "Selection cleared."
end)

cmd("fill", "[block]", "Fill the selected box (default: the last block you placed)", function(pname, param)
	local minp, maxp, err = need_box(pname)
	if not minp then
		return false, err
	end
	local name = block(param) or (param == "" and editor.last_placed)
	if not name then
		return false, param == "" and "Which block? /fill <block> (or place one first)."
			or ("No block called \"%s\"."):format(param)
	end
	local id = core.get_content_id(name)
	return apply(pname, minp, maxp, function()
		return id, 0
	end)
end)

cmd("clear", "", "Empty the selected box", function(pname)
	local minp, maxp, err = need_box(pname)
	if not minp then
		return false, err
	end
	return apply(pname, minp, maxp, function()
		return AIR, 0
	end)
end)

-- the block the player is looking at (within reach), and the one in hand
local function looked_at(player)
	local eye = vector.add(player:get_pos(), vector.new(0, player:get_properties().eye_height or 1.625, 0))
	local to = vector.add(eye, vector.multiply(player:get_look_dir(), 20))
	for pt in core.raycast(eye, to, false, false) do
		if pt.type == "node" then
			return core.get_node(pt.under).name
		end
	end
end

local function in_hand(player)
	local n = player:get_wielded_item():get_name()
	return core.registered_nodes[n] and n or "air"
end

cmd("replace", "[<from> [<to>]]", "In the selected box, swap one block for another (or for air); "
	.. "with nothing after it: the block you're looking at for the one in your hand",
	function(pname, param)
		local minp, maxp, err = need_box(pname)
		if not minp then
			return false, err
		end
		local from, to, b
		if param:match("^%s*$") then
			local player = core.get_player_by_name(pname)
			from = player and looked_at(player)
			to = player and in_hand(player)
			if not from then
				return false, "Look at a block of the kind to replace (and hold the new one), or /replace <from> [<to>]."
			end
		else
			local a
			a, b = param:match("^%s*(%S+)%s*(%S*)%s*$")
			from, to = block(a), (b and b ~= "") and block(b) or "air"
		end
		if not from then
			return false, "Which block? /replace <from> [<to>]"
		elseif not to then
			return false, ("No block called \"%s\"."):format(b)
		elseif from == to then
			return false, "That's the same block."
		end
		local fid, tid = core.get_content_id(from), core.get_content_id(to)
		return apply(pname, minp, maxp, function(_, _, _, id, p2)
			if id == fid then
				return tid, to == "air" and 0 or p2
			end
		end)
	end)

cmd("walls", "[block]", "Build the selected box's four sides (default: the last block you placed)",
	function(pname, param)
		local minp, maxp, err = need_box(pname)
		if not minp then
			return false, err
		end
		local name = block(param) or (param == "" and editor.last_placed)
		if not name then
			return false, "Which block? /walls <block> (or place one first)."
		end
		local id = core.get_content_id(name)
		return apply(pname, minp, maxp, function(x, _, z)
			if x == minp.x or x == maxp.x or z == minp.z or z == maxp.z then
				return id, 0
			end
		end)
	end)

cmd("cutaway", "ceiling", "Take the ceiling off the area you're on (or the selected squares of it)",
	function(pname, param)
		if param:match("^%s*(.-)%s*$") ~= "ceiling" then
			return false, "/cutaway ceiling (more kinds can come later)"
		end
		local player = core.get_player_by_name(pname)
		local t, o, top = player and editor.area_box(player:get_pos())
		if not t then
			return false, "Stand on an area's plate first (/area <name>)."
		end
		-- the ceiling layer and everything above it
		local minp = vector.new(o.x, o.y + prefabs.CEIL, o.z)
		local maxp = vector.new(top.x, o.y + H - 1, top.z)
		local bmin, bmax = box(pname)
		if bmin then
			-- (only the squares the selected box covers)
			local function snap(v, lo, hi, from)
				return math.max(lo, math.min(hi, from + math.floor((v - from) / W) * W))
			end
			minp.x, minp.z = snap(bmin.x, o.x, top.x, o.x), snap(bmin.z, o.z, top.z, o.z)
			maxp.x = math.min(top.x, snap(bmax.x, o.x, top.x, o.x) + W - 1)
			maxp.z = math.min(top.z, snap(bmax.z, o.z, top.z, o.z) + W - 1)
		end
		return apply(pname, minp, maxp, function()
			return AIR, 0
		end)
	end)

-- ---------------------------------------------------------------- copy, paste
-- The clipboard: each block of the copied box as an offset from corner 1
-- (where you left-clicked), its name and param2. Pasting puts corner 1 on the
-- block you're looking at; turned and mirrored blocks that face a way
-- (stairs, doors...) are turned and mirrored to match.
tools.clip = {}

-- the block the player is looking at: its position
local function looked_at_pos(player)
	local eye = vector.add(player:get_pos(), vector.new(0, player:get_properties().eye_height or 1.625, 0))
	local to = vector.add(eye, vector.multiply(player:get_look_dir(), 20))
	for pt in core.raycast(eye, to, false, false) do
		if pt.type == "node" then
			return pt.under
		end
	end
end

cmd("copy", "", "Remember the selected box's blocks (from corner 1)", function(pname)
	local minp, maxp, err = need_box(pname)
	if not minp then
		return false, err
	end
	local s = vector.add(vector.subtract(maxp, minp), 1)
	if s.x * s.y * s.z > MAX_NODES then
		return false, ("That's %d blocks; up to %d at a time."):format(s.x * s.y * s.z, MAX_NODES)
	end
	local p1 = tools.sel[pname].p1
	local vm = core.get_voxel_manip()
	local e1, e2 = vm:read_from_map(minp, maxp)
	local va = VoxelArea(e1, e2)
	local ids, p2s = vm:get_data(), vm:get_param2_data()
	local list, solid = {}, 0
	for z = minp.z, maxp.z do
		for y = minp.y, maxp.y do
			local vi = va:index(minp.x, y, z)
			for x = minp.x, maxp.x do
				-- (the editor's own plates aren't copied)
				if not PROTECTED[ids[vi]] then
					list[#list + 1] = {x - p1.x, y - p1.y, z - p1.z,
						core.get_name_from_content_id(ids[vi]), p2s[vi]}
					if ids[vi] ~= AIR then
						solid = solid + 1
					end
				end
				vi = vi + 1
			end
		end
	end
	tools.clip[pname] = list
	return true, ("Copied %dx%dx%d (%d blocks, %d of them air). /paste puts it down "
		.. "with corner 1 on the block you're looking at."):format(s.x, s.y, s.z, #list, #list - solid)
end)

-- mirroring a block that faces a way (as areas.lua flips cells): facedir /
-- 4dir turns 0<->2 across z, 1<->3 across x; wallmounted 4<->5, 2<->3
local MIRROR_ROT = {z = {[0] = 2, [2] = 0}, x = {[1] = 3, [3] = 1}}
local MIRROR_WALL = {z = {[4] = 5, [5] = 4}, x = {[2] = 3, [3] = 2}}
local function mirror_p2(name, p2, axis)
	local def = core.registered_nodes[name]
	local pt = def and def.paramtype2 or ""
	if pt == "facedir" or pt == "colorfacedir" or pt == "4dir" or pt == "color4dir" then
		local r = p2 % 4
		return p2 - r + (MIRROR_ROT[axis][r] or r)
	elseif pt == "wallmounted" or pt == "colorwallmounted" then
		local w = p2 % 8
		return p2 - w + (MIRROR_WALL[axis][w] or w)
	end
	return p2
end

cmd("paste", "[rotate 90|180|270] [flip x|z] [noair]",
	"Put down what /copy remembered, corner 1 on the block you're looking at "
	.. "(turned clockwise seen from above, mirrored; noair: its air doesn't clear anything)",
	function(pname, param)
		local list = tools.clip[pname]
		if not list then
			return false, "Nothing copied yet: select a box and /copy."
		end
		local player = core.get_player_by_name(pname)
		local at = player and looked_at_pos(player)
		if not at then
			return false, "Look at the block where corner 1 should go."
		end
		local turns = 0
		local deg = param:match("rotate%s+(%d+)")
		if deg then
			if deg ~= "90" and deg ~= "180" and deg ~= "270" then
				return false, "Rotate by 90, 180 or 270."
			end
			turns = tonumber(deg) / 90
		end
		local flip = param:match("flip%s+([xz])")
		if param:match("flip") and not flip then
			return false, "Flip x (east-west) or z (north-south)."
		end
		local noair = param:match("noair") ~= nil
		-- where each block goes: mirrored, then turned (a quarter turn
		-- clockwise from above: x, z -> z, -x, as prefabs turn)
		local put, minp, maxp = {}, nil, nil
		for _, b in ipairs(list) do
			local dx, dy, dz, name, p2 = b[1], b[2], b[3], b[4], b[5]
			if flip == "x" then
				dx = -dx
			elseif flip == "z" then
				dz = -dz
			end
			for _ = 1, turns do
				dx, dz = dz, -dx
			end
			if flip and name ~= "air" then
				p2 = mirror_p2(name, p2, flip)
			end
			if turns > 0 and name ~= "air" then
				p2 = prefabs.rot_p2(name, p2, turns)
			end
			if not (noair and name == "air") then
				local pos = vector.new(at.x + dx, at.y + dy, at.z + dz)
				put[core.hash_node_position(pos)] = {core.get_content_id(name), p2}
				if not minp then
					minp, maxp = vector.copy(pos), vector.copy(pos)
				else
					minp = vector.new(math.min(minp.x, pos.x), math.min(minp.y, pos.y), math.min(minp.z, pos.z))
					maxp = vector.new(math.max(maxp.x, pos.x), math.max(maxp.y, pos.y), math.max(maxp.z, pos.z))
				end
			end
		end
		if not minp then
			return true, "Nothing to put down (it's all air, and noair)."
		end
		return apply(pname, minp, maxp, function(x, y, z)
			local v = put[core.hash_node_position(vector.new(x, y, z))]
			if v then
				return v[1], v[2]
			end
		end)
	end)

cmd("undo", "", "Put back what the last tool changed", function(pname)
	local u = tools.undo[pname]
	if not u then
		return false, "Nothing to undo."
	end
	local vm = core.get_voxel_manip()
	local e1, e2 = vm:read_from_map(u.minp, u.maxp)
	if not (vector.equals(e1, u.e1) and vector.equals(e2, u.e2)) then
		return false, "Can't undo that any more."
	end
	local ids, p2s = vm:get_data(), vm:get_param2_data()
	for vi, id in pairs(u.ids) do
		ids[vi], p2s[vi] = id, u.p2[vi]
	end
	vm:set_data(ids)
	vm:set_param2_data(p2s)
	vm:write_to_map(true)
	tools.undo[pname] = nil
	editor.mark_box(u.minp, u.maxp)
	return true, "Put back."
end)

core.register_on_leaveplayer(function(player)
	local s = tools.sel[player:get_player_name()]
	if s and s.obj and s.obj:get_pos() then
		s.obj:remove()
	end
	tools.sel[player:get_player_name()] = nil
end)

return tools
