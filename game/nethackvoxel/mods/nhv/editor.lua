-- The prefab editor world (creative mode).
--
-- Every prefab slot has a build cell laid out in rows; a glowing plate
-- marks its footprint and a label floats above it. Build inside the cell
-- (the band between the two orange rails is floor-to-ceiling room space;
-- below and above it is extra room for pits and stairs), then:
--   /prefab save            save every cell (used by all game worlds)
--   /prefab reset <slot>    rebuild a cell from its default
--   /prefab goto <slot>     jump to a cell
--   /prefab list            list the slots
-- I opens the block palette. Placing never uses up blocks; digging is
-- instant.

local U = nhv.util
local prefabs = nhv.prefabs
local editor = {}
nhv.editor = editor

local W, H = prefabs.W, prefabs.H
local SPACING = 8      -- distance between cell origins (x)
local ROW_SPACING = 10 -- distance between rows (z)
local PER_ROW = 8
local BASE_Y = 0       -- world y of a cell's bottom layer

-- cell origin (bottom south-west node) for slot number n (1-based)
function editor.origin(n)
	local row = math.floor((n - 1) / PER_ROW)
	local col = (n - 1) % PER_ROW
	return vector.new(col * SPACING, BASE_Y, row * ROW_SPACING)
end

local function slot_origin(slot)
	local info = prefabs.SLOT_INFO[slot]
	return info and editor.origin(info.order)
end

-- ---------------------------------------------------------------- nodes
core.register_node("nhv:editor_plate", {
	description = "Cell footprint",
	tiles = {"[fill:16x16:#30A0FF"},
	paramtype = "light", light_source = 6,
	groups = {not_in_creative_inventory = 1}, drop = "",
	diggable = false, pointable = true,
})
core.register_node("nhv:editor_plate_front", {
	description = "Cell front (north)",
	tiles = {"[fill:16x16:#E02020"},
	paramtype = "light", light_source = 6,
	groups = {not_in_creative_inventory = 1}, drop = "",
	diggable = false, pointable = true,
})
core.register_node("nhv:editor_rail", {
	description = "Floor / ceiling level marker",
	drawtype = "nodebox", paramtype = "light", light_source = 4,
	tiles = {"[fill:16x16:#FF9020"},
	node_box = {type = "fixed", fixed = {-0.5, -0.06, -0.06, 0.5, 0.06, 0.06}},
	walkable = false, groups = {not_in_creative_inventory = 1}, drop = "",
	diggable = false, pointable = false,
})

core.register_node("nhv:editor_ground", {
	description = "Editor ground",
	tiles = {"[fill:16x16:#3A3F48^[fill:14x14:1,1:#33373F"},
	paramtype = "light", groups = {not_in_creative_inventory = 1}, drop = "",
	diggable = false,
})

core.register_entity("nhv:editor_label", {
	initial_properties = {
		visual = "sprite", textures = {"blank.png"}, visual_size = {x = 0, y = 0},
		pointable = false, physical = false, static_save = false,
		nametag_color = "#FFFFFF", nametag_bgcolor = "#000000A0",
	},
})

-- ---------------------------------------------------------------- layout
local function write_cell(slot)
	local o = slot_origin(slot)
	local d = prefabs.get(slot)
	for ly = 0, H - 1 do
		for lx = 0, W - 1 do
			for lz = 0, W - 1 do
				core.set_node(vector.new(o.x + lx, o.y + ly, o.z + lz), {name = "air"})
			end
		end
	end
	for i, nd in pairs(d.nodes) do
		local lx, ly, lz = prefabs.unindex(i)
		if core.registered_nodes[nd.n] then
			core.set_node(vector.new(o.x + lx, o.y + ly, o.z + lz), {name = nd.n, param2 = nd.p2 or 0})
		end
	end
end

local function decorate_cell(slot)
	local o = slot_origin(slot)
	-- footprint plate under the cell, with a one-node border
	for x = -1, W do
		for z = -1, W do
			core.set_node(vector.new(o.x + x, o.y - 1, o.z + z), {name = "nhv:editor_plate"})
		end
	end
	-- red block in the border: the cell's front, which faces north in the
	-- game (the orientation the cell descriptions refer to)
	core.set_node(vector.new(o.x + 1, o.y - 1, o.z + W), {name = "nhv:editor_plate_front"})
	-- floor and ceiling level rails on the outside corners
	for _, ly in ipairs({prefabs.FLOOR, prefabs.CEIL}) do
		for _, c in ipairs({{-1, -1}, {W, -1}, {-1, W}, {W, W}}) do
			core.set_node(vector.new(o.x + c[1], o.y + ly, o.z + c[2]), {name = "nhv:editor_rail"})
		end
	end
end

local function label_cell(slot)
	local o = slot_origin(slot)
	local info = prefabs.SLOT_INFO[slot]
	local obj = core.add_entity(vector.new(o.x + 1, o.y + H + 0.5, o.z + 1), "nhv:editor_label")
	if obj then
		obj:set_properties({nametag = slot .. (info.kind == "overlay" and " (overlay)" or "")
			.. "\n" .. info.desc})
	end
end

local storage = core.get_mod_storage()

local function area_bounds()
	local last = editor.origin(#prefabs.SLOTS)
	return vector.new(-52, BASE_Y - 4, -56),
		vector.new(PER_ROW * SPACING + 8, BASE_Y + H + 8, last.z + ROW_SPACING + 8)
end

-- a floor to walk on around the cells, below their bottom layer
local function lay_ground(minp, maxp)
	local vm = core.get_voxel_manip()
	local y = BASE_Y - 2
	local e1, e2 = vm:read_from_map(vector.new(minp.x, y, minp.z), vector.new(maxp.x, y, maxp.z))
	local area = VoxelArea(e1, e2)
	local data = vm:get_data()
	local ground = core.get_content_id("nhv:editor_ground")
	for z = minp.z, maxp.z do
		for x = minp.x, maxp.x do
			data[area:index(x, y, z)] = ground
		end
	end
	vm:set_data(data)
	vm:write_to_map(true)
end

-- feature cells show the sprite the game draws there (unless built)
local CELL_SPRITES = {
	tree = {"S_tree", 1290}, fountain = {"S_fountain", 1313}, altar = {"S_altar", 1307},
	throne = {"S_throne", 1311}, sink = {"S_sink", 1312}, grave = {"S_grave", 1310},
}
core.register_entity("nhv:editor_cellsprite", {
	initial_properties = {
		visual = "wielditem", wield_item = nhv_tiles.item(0), physical = false,
		pointable = false, static_save = false,
	},
})

local function sprite_cell(slot)
	local cs = CELL_SPRITES[slot]
	if not cs then
		return
	end
	local o = slot_origin(slot)
	local h = nhv.scale.feature_height(cs[1]) or 2
	local obj = core.add_entity(vector.new(o.x + 1, o.y + prefabs.FLOOR + 0.5 + h / 2, o.z + 1),
		"nhv:editor_cellsprite")
	if obj then
		obj:set_properties({wield_item = nhv_tiles.item(cs[2]),
			visual_size = {x = h / 2, y = h / 2, z = h / 2}})
	end
end

local function setup_world()
	lay_ground(area_bounds())
	for _, s in ipairs(prefabs.SLOTS) do
		sprite_cell(s[1])
		decorate_cell(s[1])
		if storage:get_string("built_" .. s[1]) == "" then
			write_cell(s[1])
			storage:set_string("built_" .. s[1], "1")
		end
	end
end


-- ---------------------------------------------------------------- palette
local palette = {}
local function build_palette()
	palette = {}
	for _, n in ipairs(nhv.blocks.names) do
		palette[#palette + 1] = n
	end
	for name, def in pairs(core.registered_nodes) do
		if name:match("^nhv:") and def.groups and def.groups.editor
				and not name:match("^nhv:b_") and name ~= "nhv:trigger"
				and name ~= "nhv:mpath" and name ~= "nhv:carve" then
			palette[#palette + 1] = name
		end
	end
	table.sort(palette, function(a, b)
		-- markers first, then building blocks, then terrain
		local function rank(n)
			if n == "nhv:trigger" or n == "nhv:mpath" or n == "nhv:carve" then return 0 end
			if n:match("^nhv:b_") then return 1 end
			return 2
		end
		if rank(a) ~= rank(b) then return rank(a) < rank(b) end
		return a < b
	end)
end

local function palette_formspec()
	local fs = {"formspec_version[6]size[17,11]",
		"label[0.4,0.5;Block palette - click to put in your hotbar slot. "
		.. "Red = stairs trigger, green = monster path, yellow = carve (overlays).]"}
	local cols = 16
	for i, name in ipairs(palette) do
		local x = 0.4 + ((i - 1) % cols) * 1.02
		local y = 1.0 + math.floor((i - 1) / cols) * 1.02
		fs[#fs + 1] = ("item_image_button[%f,%f;0.95,0.95;%s;pal_%d;]"):format(x, y, name, i)
		fs[#fs + 1] = ("tooltip[pal_%d;%s]"):format(i,
			core.formspec_escape(core.registered_nodes[name].description or name))
	end
	return table.concat(fs)
end

core.register_on_player_receive_fields(function(player, formname, fields)
	if formname ~= "" then
		return
	end
	for k in pairs(fields) do
		local n = k:match("^pal_(%d+)$")
		if n and palette[tonumber(n)] then
			local inv = player:get_inventory()
			local idx = player:get_wield_index()
			inv:set_stack("main", idx, ItemStack(palette[tonumber(n)] .. " 99"))
			return true
		end
	end
end)

-- ---------------------------------------------------------------- commands
core.register_chatcommand("prefab", {
	params = "save | reset <slot> | goto <slot> | list",
	description = "Prefab editor commands",
	func = function(name, param)
		local cmd, arg = param:match("^(%S*)%s*(.-)%s*$")
		if cmd == "save" then
			local customs = 0
			for _, s in ipairs(prefabs.SLOTS) do
				local d = prefabs.capture(s[1], slot_origin(s[1]))
				prefabs.data[s[1]] = d
				if d.custom then
					customs = customs + 1
				end
			end
			if prefabs.save() then
				return true, ("Saved %d prefabs (%d changed from default) to %s")
					:format(#prefabs.SLOTS, customs, prefabs.DATA_PATH)
			end
			return false, "Could not write " .. prefabs.DATA_PATH
		elseif cmd == "reset" then
			if not prefabs.SLOT_INFO[arg] then
				return false, "Unknown slot. /prefab list"
			end
			prefabs.data[arg] = prefabs.default(arg)
			write_cell(arg)
			return true, arg .. " reset to default (not saved yet)"
		elseif cmd == "goto" then
			local o = slot_origin(arg)
			if not o then
				return false, "Unknown slot. /prefab list"
			end
			local p = core.get_player_by_name(name)
			p:set_pos(vector.new(o.x + 1, BASE_Y - 1, o.z - 4))
			p:set_look_horizontal(0)
			return true
		elseif cmd == "list" or cmd == "" then
			local names = {}
			for _, s in ipairs(prefabs.SLOTS) do
				names[#names + 1] = s[1]
			end
			return true, table.concat(names, ", ")
		end
		return false, "Usage: /prefab save | reset <slot> | goto <slot> | list"
	end,
})

-- ---------------------------------------------------------------- player
core.register_on_joinplayer(function(player)
	local name = player:get_player_name()
	local privs = core.get_player_privs(name)
	privs.fly, privs.fast, privs.noclip, privs.give = true, true, true, true
	core.set_player_privs(name, privs)
	player:set_sky({type = "plain", base_color = "#202830", clouds = false})
	player:override_day_night_ratio(1)
	player:hud_set_hotbar_itemcount(10)
	local inv = player:get_inventory()
	inv:set_size("main", 32)
	build_palette()
	player:set_inventory_formspec(palette_formspec())
	core.chat_send_player(name, "Prefab editor. I = block palette, E = monster editor, K = toggle flying. "
		.. "/prefab save when done. /prefab list, /prefab goto <slot>, /prefab reset <slot>.")
	-- float until the editor area exists (nothing to stand on before)
	player:set_physics_override({gravity = 0})
	player:set_velocity(vector.zero())
	local minp, maxp = area_bounds()
	core.emerge_area(minp, maxp, function(_, _, remaining)
		if remaining == 0 then
			core.after(0, editor.on_ready, player)
		end
	end)
end)

local to_spawn

-- runs on the server thread once the editor area exists
function editor.on_ready(player)
	if not player:is_player() then
		return
	end
	local name = player:get_player_name()
	do
		do
			setup_world()
			if player:get_pos().y < BASE_Y - 4 then
				to_spawn(player)
			end
			player:set_physics_override({gravity = 1})
			player:set_sun({visible = false, sunrise_visible = false})
			player:set_moon({visible = false})
			core.log("action", ("[nhv] editor ready; %s at %s; cell 1 node: %s"):format(
				name, core.pos_to_string(player:get_pos()),
				core.get_node(vector.add(editor.origin(1), vector.new(1, prefabs.FLOOR, 1))).name))
		end
	end
end

-- hand: dig anything of ours instantly
core.override_item("", {
	range = 10,
	tool_capabilities = {
		full_punch_interval = 0.2, max_drop_level = 0,
		groupcaps = {editor = {times = {[1] = 0.15}, uses = 0}},
		damage_groups = {},
	},
})

-- placing never uses up blocks
core.register_on_placenode(function()
	return true
end)

-- which cell you're at, shown on screen
local hud_ids = {}
local function nearest_slot(pos)
	local best, bd
	for _, s in ipairs(prefabs.SLOTS) do
		local o = slot_origin(s[1])
		local d = (pos.x - (o.x + 1)) ^ 2 + (pos.z - (o.z + 1)) ^ 2
		if not bd or d < bd then
			best, bd = s[1], d
		end
	end
	return best
end

local label_t = 0
core.register_globalstep(function(dtime)
	label_t = label_t + dtime
	if label_t < 0.25 then
		return
	end
	label_t = 0
	for _, player in ipairs(core.get_connected_players()) do
		local name = player:get_player_name()
		local slot = nearest_slot(player:get_pos())
		local info = prefabs.SLOT_INFO[slot]
		local text = ("Cell: %s%s\n%s\n(red block in the base = north)"):format(slot,
			info.kind == "overlay" and "  (overlay: added on top of a floor)" or "", info.desc)
		if not hud_ids[name] then
			hud_ids[name] = player:hud_add({
				type = "text", position = {x = 0.5, y = 0}, alignment = {x = 0, y = 1},
				offset = {x = 0, y = 70}, number = 0xFFFFFF, text = text,
			})
		else
			player:hud_change(hud_ids[name], "text", text)
		end
	end
end)

core.register_on_leaveplayer(function(player)
	hud_ids[player:get_player_name()] = nil
end)

-- spawn / respawn in front of the first cell, and catch falls
function editor.spawn_pos()
	local o = editor.origin(1)
	return vector.new(o.x + 1, BASE_Y - 1, o.z - 4)
end

function to_spawn(player)
	player:set_pos(editor.spawn_pos())
	player:set_velocity(vector.zero())
end

core.register_on_newplayer(to_spawn)
core.register_on_respawnplayer(function(player)
	to_spawn(player)
	return true
end)

local fall_check = 0
core.register_globalstep(function(dtime)
	fall_check = fall_check + dtime
	if fall_check < 0.5 then
		return
	end
	fall_check = 0
	for _, player in ipairs(core.get_connected_players()) do
		if player:get_pos().y < BASE_Y - 10 then
			to_spawn(player)
		end
	end
end)

return editor

