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
--   /area                   list the special level areas
--   /area <name>            go to an area's build plate (see areas.lua)
--   /area reset <name>      start an area over from the usual prefabs
--   /area reload <name>     build an area's plate again from what's saved
--                           (after its file was changed outside the editor)
--   /area revert            start the area you're on over (all your changes gone)
--   /fullbright             see everything at full brightness (toggle)
-- I opens the block palette. Placing never uses up blocks; digging is
-- instant.

local U = nhv.util
local prefabs = nhv.prefabs
local editor = {}
nhv.editor = editor

local W, H = prefabs.W, prefabs.H
local T_STONE = U.TYP.STONE
-- terrain names, for the area squares
local TYP_NAMES = {}
for name, v in pairs(U.TYP) do
	TYP_NAMES[v] = name:lower():gsub("_", " ")
end
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
core.register_node("nhv:editor_plate_own", {
	description = "Area square built from its own prefab in the game (door, stairs...)",
	tiles = {"[fill:16x16:#E08020"},
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
	-- feature sprites face you, as in the game
	on_step = function(self)
		nhv.util.face_player(self.object)
	end,
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
		-- (built the first time, and again when its default changed and it
		-- isn't hand-built)
		local version = tostring(prefabs.DEFAULT_VERSION[s[1]] or 1)
		local built = storage:get_string("built_" .. s[1])
		local custom = prefabs.data[s[1]] and prefabs.data[s[1]].custom
		if built == "" or (built ~= version and not custom) then
			write_cell(s[1])
			storage:set_string("built_" .. s[1], version)
		end
	end
end


-- ---------------------------------------------------------------- palette
-- Tabs of blocks (I to open). Click one to put it in your hotbar slot.
local TABS = {
	{"markers", "Markers"}, {"blocks", "Blocks"}, {"shapes", "Slabs, stairs, panes"},
	{"terrain", "Terrain"}, {"custom", "Your blocks"}, {"objects", "Objects"},
}
local MARKERS = {["nhv:trigger"] = true, ["nhv:mpath"] = true, ["nhv:carve"] = true}
local palette = {}     -- tab id -> sorted node names
local tab_of = {}      -- player name -> tab index

local function category(name, def)
	if MARKERS[name] then
		return "markers"
	elseif def.groups and def.groups.nhv_prop then
		return "objects"
	elseif def.groups and def.groups.nhv_custom then
		return "custom" -- made in the block editor
	elseif name:match("^nhv:b_") then
		for _, shape in ipairs({"_slab$", "_stair$", "_pane$", "_post$"}) do
			if name:match(shape) then
				return "shapes"
			end
		end
		return "blocks"
	end
	return "terrain"
end

local function build_palette()
	palette = {}
	for _, t in ipairs(TABS) do
		palette[t[1]] = {}
	end
	for name, def in pairs(core.registered_nodes) do
		if name:match("^nhv:") and def.groups and def.groups.editor then
			local list = palette[category(name, def)]
			list[#list + 1] = name
		end
	end
	for _, list in pairs(palette) do
		table.sort(list)
	end
end

local function palette_formspec(pname)
	local ti = tab_of[pname] or 2
	if not TABS[ti] then
		ti = 2
	end
	local list = palette[TABS[ti][1]] or {}
	local names = {}
	for i, t in ipairs(TABS) do
		-- (commas in a tab name would split it into more tabs)
		names[i] = core.formspec_escape(("%s (%d)"):format(t[2], #(palette[t[1]] or {})))
	end
	local cols, step = 15, 1.05
	local rows = math.ceil(#list / cols)
	local view_h = 8.6
	local fs = {"formspec_version[6]size[17.2,11]",
		"tabheader[0.3,0.75;16.6,0.7;paltab;", table.concat(names, ","), ";", ti, ";false;true]",
		"label[0.4,1.15;Click a block to put it in your hotbar slot.",
		ti == 1 and " Red = stairs trigger, green = monster path, yellow = carve (overlays)." or "", "]",
		("scroll_container[0.3,1.6;16.0,%f;palscroll;vertical;0.1]"):format(view_h)}
	for i, name in ipairs(list) do
		local x = 0.1 + ((i - 1) % cols) * step
		local y = 0.05 + math.floor((i - 1) / cols) * step
		fs[#fs + 1] = ("item_image_button[%f,%f;0.95,0.95;%s;pal_%s;]"):format(x, y, name,
			name:gsub(":", "__"))
		fs[#fs + 1] = ("tooltip[pal_%s;%s]"):format(name:gsub(":", "__"),
			core.formspec_escape(core.registered_nodes[name].description or name))
	end
	fs[#fs + 1] = "scroll_container_end[]"
	local overflow = math.max(0, rows * step + 0.1 - view_h)
	fs[#fs + 1] = ("scrollbaroptions[max=%d;smallstep=10;largestep=60]"):format(math.ceil(overflow * 10))
	fs[#fs + 1] = ("scrollbar[16.45,1.6;0.4,%f;vertical;palscroll;0]"):format(view_h)
	if #list == 0 then
		fs[#fs + 1] = "label[0.5,2.2;Nothing here yet.]"
	end
	return table.concat(fs)
end

core.register_on_player_receive_fields(function(player, formname, fields)
	if formname ~= "" then
		return
	end
	local pname = player:get_player_name()
	if fields.paltab then
		local t = tonumber(fields.paltab)
		tab_of[pname] = (t and TABS[t]) and t or 2
		player:set_inventory_formspec(palette_formspec(pname))
		return true
	end
	for k in pairs(fields) do
		local id = k:match("^pal_(.+)$")
		if id then
			local name = id:gsub("__", ":")
			if core.registered_nodes[name] then
				local inv = player:get_inventory()
				inv:set_stack("main", player:get_wield_index(), ItemStack(name .. " 99"))
				return true
			end
		end
	end
end)

-- ---------------------------------------------------------------- commands
core.register_chatcommand("prefab", {
	params = "save | reset <slot> | swap <slot> <slot> | goto <slot> | list",
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
			editor.save({arg})
			return true, arg .. " reset to default"
		elseif cmd == "swap" then
			-- exchange two cells (e.g. up and down stairs built the wrong way round)
			local a, b = arg:match("^(%S+)%s+(%S+)$")
			if not (a and b and prefabs.SLOT_INFO[a] and prefabs.SLOT_INFO[b]) then
				return false, "Usage: /prefab swap <slot> <slot>  (see /prefab list)"
			end
			editor.save({a, b})
			prefabs.data[a], prefabs.data[b] = prefabs.data[b], prefabs.data[a]
			write_cell(a)
			write_cell(b)
			editor.save({a, b})
			return true, ("Swapped %s and %s"):format(a, b)
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
		return false, "Usage: /prefab save | reset <slot> | swap <slot> <slot> | goto <slot> | list"
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
	player:set_inventory_formspec(palette_formspec(name))
	core.chat_send_player(name, "Prefab editor. I = block palette, E = monster editor, K = toggle flying. "
		.. "Cells save automatically. /prefab list, /prefab goto <slot>, /prefab reset <slot>.")
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
			-- capture every cell as it stands (keeps earlier, unsaved builds)
			editor.save_all()
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

-- ---------------------------------------------------------------- areas
-- Special level areas (areas.lua): one build plate per fixed region of
-- each variant, laid out south of the cells. A plate starts out built from
-- the usual prefabs, as the game builds that region now; change it, and
-- the squares you changed are what the game builds there. Orange plate
-- squares (doors, stairs...) always use their own prefabs in the game.
local areas = nhv.areas
local AREA_Z0 = -200
local AREA_GAP = 16
local area_origin = {} -- id -> origin of its south-west square
do
	local z = AREA_Z0
	for _, t in ipairs(areas.list) do
		z = z - t.h * W - AREA_GAP
		area_origin[t.id] = vector.new(0, BASE_Y, z)
	end
end

local function square_origin(t, cx, cy)
	local o = area_origin[t.id]
	return vector.new(o.x + cx * W, o.y, o.z + (t.h - 1 - cy) * W)
end

-- the area and square (cx, cy) at pos
local function area_at(pos, any_height)
	for _, t in ipairs(areas.list) do
		local o = area_origin[t.id]
		if pos.x >= o.x and pos.x < o.x + t.w * W and pos.z >= o.z and pos.z < o.z + t.h * W
				and (any_height or (pos.y >= o.y and pos.y < o.y + H)) then
			return t, math.floor((pos.x - o.x) / W), t.h - 1 - math.floor((pos.z - o.z) / W)
		end
	end
end

-- the template as a map, for laying it out the way the game would
local function template_map(t)
	local map = {typ = {}, door = {}, flags = {}}
	for tx = 0, U.COLNO - 1 do
		for ty = 0, U.ROWNO - 1 do
			map.typ[U.idx(tx, ty)] = T_STONE
			map.door[U.idx(tx, ty)] = 0
		end
	end
	for cy = 0, t.h - 1 do
		for cx = 0, t.w - 1 do
			map.typ[U.idx(t.x + cx, t.y + cy)] = areas.template_typ(t, cx, cy)
		end
	end
	return map
end

-- lay out an area's plate (and, the first time or after a reset, build it)
local function build_area(t, build, done)
	local o = area_origin[t.id]
	local minp = vector.new(o.x - 3, BASE_Y - 2, o.z - 6)
	local maxp = vector.new(o.x + t.w * W + 2, BASE_Y + H + 1, o.z + t.h * W + 2)
	core.emerge_area(minp, maxp, function(_, _, remaining)
		if remaining > 0 then
			return
		end
		local vm = core.get_voxel_manip()
		local e1, e2 = vm:read_from_map(minp, maxp)
		local va = VoxelArea(e1, e2)
		local data = {ids = vm:get_data(), p2 = vm:get_param2_data()}
		local cid = nhv.terrain.cid
		for z = minp.z, maxp.z do
			for x = minp.x, maxp.x do
				data.ids[va:index(x, BASE_Y - 2, z)] = cid("nhv:editor_ground")
			end
		end
		local map = template_map(t)
		local d = areas.get(t.id)
		-- (the usual prefabs with the level's own walls - the Mines' in
		-- Minetown, Gehennom's in Orcus Town... - as the game builds them;
		-- squares you built are as you built them, there too)
		local styled = nhv.terrain.styled_cid_for(areas.wall_style(t))
		-- (the squares you haven't built are as the game builds them: in an
		-- area open to the sky - most of its floor built without a roof -
		-- none of them has a ceiling, nor water on a level open to the sky;
		-- terrain.lua's describe)
		areas.forget_open(t.id)
		local open_area = areas.area_open(t)
		local open_level = nhv.terrain.OPEN_SKY[t.proto]
		for cy = 0, t.h - 1 do
			for cx = 0, t.w - 1 do
				local so = square_origin(t, cx, cy)
				local typ = areas.template_typ(t, cx, cy)
				local plate = areas.own_prefab(typ) and "nhv:editor_plate_own" or "nhv:editor_plate"
				for x = 0, W - 1 do
					for z = 0, W - 1 do
						data.ids[va:index(so.x + x, BASE_Y - 1, so.z + z)] = cid(plate)
					end
				end
				-- (squares you built: the first time and after a reset only;
				-- the others, the usual prefabs, are built again every time,
				-- so they always show what the game builds - its current
				-- prefabs, with the level's walls)
				local k = cy * t.w + cx + 1
				if build or not d.cells[k] then
					local tx, ty = t.x + cx, t.y + cy
					if d.cells[k] then
						prefabs.write_at(data, va, so, d.cells[k].nodes, 0, true, cid)
					else
						local slot, rot = nhv.terrain.base_slot(map, U.idx(tx, ty), tx, ty, nil)
						prefabs.write_at(data, va, so, prefabs.get(slot).nodes, rot, true, styled)
						-- (a door: its lintel, not its ceiling, as in the game)
						if nhv.terrain.DOOR_SLOTS[slot] then
							nhv.terrain.clear_over_lintel(data, va, so)
						elseif (open_area or (open_level and nhv.terrain.OPEN_LIQUID[typ]))
								and not nhv.terrain.ROOF_KEPT[slot] then
							nhv.terrain.clear_over_lintel(data, va, so)
						end
					end
				end
				-- a light under the ceiling of open squares, as the game puts
				-- in lit rooms (not saved with the area: the game adds its own)
				if typ >= U.TYP.POOL and typ ~= U.TYP.IRONBARS and typ ~= U.TYP.LAVAWALL then
					local vi = va:index(so.x + 1, so.y + prefabs.CEIL - 1, so.z + 1)
					if data.ids[vi] == cid("air") then
						data.ids[vi] = cid("nhv:room_light")
					end
				end
			end
		end
		-- north side: a red row along the plate's north edge
		for x = o.x, o.x + t.w * W - 1 do
			data.ids[va:index(x, BASE_Y - 1, o.z + t.h * W)] = cid("nhv:editor_plate_front")
		end
		vm:set_data(data.ids)
		vm:set_param2_data(data.p2)
		vm:write_to_map(true)
		local label = core.add_entity(vector.new(o.x + 1, BASE_Y + H + 0.5, o.z + t.h * W - 1),
			"nhv:editor_label")
		if label then
			label:set_properties({nametag = areas.name(t) .. "\n" .. areas.shown_id(t)})
		end
		if done then
			done()
		end
	end)
end

-- find areas by id, or by part of the name / level file
local function find_areas(q)
	q = q:lower()
	for _, t in ipairs(areas.list) do
		if t.id:lower() == q or areas.shown_id(t):lower() == q then
			return {t}
		end
	end
	local out = {}
	for _, t in ipairs(areas.list) do
		if t.id:lower():find(q, 1, true) or areas.name(t):lower():find(q, 1, true) then
			out[#out + 1] = t
		end
	end
	return out
end

local function area_list(ts)
	local lines = {}
	for _, t in ipairs(ts) do
		lines[#lines + 1] = ("%-14s %s (%dx%d)%s"):format(areas.shown_id(t), areas.name(t), t.w, t.h,
			areas.built(t.id) and "  [built]" or "")
	end
	return table.concat(lines, "\n")
end

local save_areas -- (below: the area squares changed, saved now)

core.register_chatcommand("area", {
	params = "[reset | reload] [<name>] | revert",
	description = "Special level areas: list them, go to one, start one over (revert: the one you're on), "
		.. "build one again from its saved file (reload)",
	func = function(pname, param)
		local player = core.get_player_by_name(pname)
		if param:match("^%s*revert%s*$") then
			-- (on the plate, or just beside it - /area <name> puts you at its edge)
			local t
			if player then
				local p = player:get_pos()
				t = area_at(p, true)
				for _, d in ipairs({{0, 4}, {0, -4}, {4, 0}, {-4, 0}}) do
					t = t or area_at(vector.offset(p, d[1], 0, d[2]), true)
				end
			end
			if not t then
				return false, "Stand on (or next to) an area's plate to revert it."
			end
			if not editor.revert_area(t) then
				return true, areas.name(t) .. " has no changes: it's already the usual prefabs."
			end
			build_area(t, true, function()
				storage:set_string("area_laid_" .. t.id, "1")
			end)
			return true, "Reverted " .. areas.name(t) .. ": every change gone, back to the usual prefabs."
		end
		local reset = param:match("^%s*reset%s+(.-)%s*$")
		local reload = param:match("^%s*reload%s+(.-)%s*$")
		local q = reset or reload or param:match("^%s*(.-)%s*$")
		if q == "" then
			return true, "Areas (/area <name> to go to one):\n" .. area_list(areas.list)
		end
		local found = find_areas(q)
		if #found == 0 then
			return false, "No area matches \"" .. q .. "\". /area lists them."
		elseif #found > 1 then
			return true, "Which one?\n" .. area_list(found)
		end
		local t = found[1]
		local first = storage:get_string("area_laid_" .. t.id) == ""
		-- (what you just changed - anywhere - is saved before any plate is
		-- built again: a square not saved yet would be built over)
		save_areas()
		if reset then
			areas.get(t.id).cells = {}
			areas.save(t.id)
		elseif reload then
			-- (what you just changed saved first, then the file read again)
			save_areas()
			areas.data[t.id] = nil
		end
		build_area(t, first or reset ~= nil or reload ~= nil, function()
			storage:set_string("area_laid_" .. t.id, "1")
			if player and player:is_player() then
				local o = area_origin[t.id]
				player:set_pos(vector.new(o.x + t.w * W / 2, BASE_Y - 1, o.z - 3))
				player:set_look_horizontal(0)
			end
		end)
		return true, (reset and "Starting over: " or reload and "Built again from its file: "
			or "Going to: ") .. areas.name(t)
	end,
})

-- ---------------------------------------------------------------- saving
-- Cells save themselves: any block placed or dug in a cell is written to
-- prefabs.dat a moment later (and everything is captured when the editor
-- opens and when it closes), so the game always uses what you built.
local dirty = {}
local dirty_areas = {} -- id -> {[k] = true}
local save_at = nil

local function slot_at(pos)
	for _, s in ipairs(prefabs.SLOTS) do
		local o = slot_origin(s[1])
		if pos.x >= o.x and pos.x < o.x + W and pos.z >= o.z and pos.z < o.z + W
				and pos.y >= o.y and pos.y < o.y + H then
			return s[1]
		end
	end
end

function editor.save(slots)
	for _, slot in ipairs(slots or {}) do
		prefabs.data[slot] = prefabs.capture(slot, slot_origin(slot))
	end
	return prefabs.save()
end

local function all_slots()
	local out = {}
	for _, s in ipairs(prefabs.SLOTS) do
		out[#out + 1] = s[1]
	end
	return out
end

function editor.save_all()
	return editor.save(all_slots())
end

local function changed(pos)
	local slot = slot_at(pos)
	if slot then
		dirty[slot] = true
		save_at = core.get_us_time() + 800000
		return
	end
	local t, cx, cy = area_at(pos)
	if t then
		dirty_areas[t.id] = dirty_areas[t.id] or {}
		dirty_areas[t.id][cy * t.w + cx + 1] = true
		save_at = core.get_us_time() + 800000
	end
end

-- everything in the box minp..maxp changed (the editor tools): the cells
-- and area squares it touches are saved
function editor.mark_box(minp, maxp)
	local function overlap(a1, a2, b1, b2)
		return a1 <= b2 and b1 <= a2
	end
	for _, s in ipairs(prefabs.SLOTS) do
		local o = slot_origin(s[1])
		if overlap(minp.x, maxp.x, o.x, o.x + W - 1) and overlap(minp.y, maxp.y, o.y, o.y + H - 1)
				and overlap(minp.z, maxp.z, o.z, o.z + W - 1) then
			dirty[s[1]] = true
		end
	end
	for _, t in ipairs(areas.list) do
		local o = area_origin[t.id]
		local x2, z2 = o.x + t.w * W - 1, o.z + t.h * W - 1
		if overlap(minp.x, maxp.x, o.x, x2) and overlap(minp.y, maxp.y, o.y, o.y + H - 1)
				and overlap(minp.z, maxp.z, o.z, z2) then
			dirty_areas[t.id] = dirty_areas[t.id] or {}
			local cx1 = math.floor((math.max(minp.x, o.x) - o.x) / W)
			local cx2 = math.floor((math.min(maxp.x, x2) - o.x) / W)
			local cz1 = math.floor((math.max(minp.z, o.z) - o.z) / W)
			local cz2 = math.floor((math.min(maxp.z, z2) - o.z) / W)
			for cx = cx1, cx2 do
				for cz = cz1, cz2 do
					dirty_areas[t.id][(t.h - 1 - cz) * t.w + cx + 1] = true
				end
			end
		end
	end
	save_at = core.get_us_time() + 800000
end

-- the area plate at pos (any height): its template and the box it covers
-- (cells are W x H x W nodes; a plate's squares sit side by side)
function editor.area_box(pos)
	local t = area_at(pos, true)
	if not t then
		return nil
	end
	local o = area_origin[t.id]
	return t, o, vector.new(o.x + t.w * W - 1, o.y + H - 1, o.z + t.h * W - 1)
end

-- Start an area over: every square you built (this session and before)
-- is dropped, so the game builds it from the usual prefabs again; the
-- caller rebuilds the plate. False if there was nothing to drop.
function editor.revert_area(t)
	local d = areas.get(t.id)
	if not next(d.cells) and not dirty_areas[t.id] then
		return false
	end
	dirty_areas[t.id] = nil -- (changes not saved yet: dropped too)
	d.cells = {}
	areas.save(t.id)
	return true
end

-- the area squares that were changed, as they're built now
function save_areas()
	for id, ks in pairs(dirty_areas) do
		local t = areas.templates[id]
		local d = areas.get(id)
		for k in pairs(ks) do
			local cx, cy = (k - 1) % t.w, math.floor((k - 1) / t.w)
			d.cells[k] = {nodes = prefabs.read_at(square_origin(t, cx, cy))}
		end
		if not areas.save(id) then
			core.chat_send_all("Could not save area " .. id)
		end
	end
	dirty_areas = {}
end

core.register_globalstep(function()
	if save_at and core.get_us_time() > save_at then
		save_at = nil
		local slots = {}
		for slot in pairs(dirty) do
			slots[#slots + 1] = slot
		end
		dirty = {}
		if #slots > 0 and not editor.save(slots) then
			core.chat_send_all("Could not save prefabs to " .. prefabs.DATA_PATH)
		end
		save_areas()
	end
end)

core.register_on_shutdown(function()
	if next(dirty) then
		editor.save(all_slots())
	end
	save_areas()
end)

-- placing never uses up blocks (the last one placed is /fill's default)
core.register_on_placenode(function(pos, newnode)
	changed(pos)
	editor.last_placed = newnode and newnode.name
	return true
end)
core.register_on_dignode(changed)

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
		local text
		local t, cx, cy = area_at(player:get_pos(), true)
		if t then
			local typ = areas.template_typ(t, cx, cy)
			text = ("Area: %s (%s)\nSquare %d,%d: %s%s\n(red row = north side)"):format(
				areas.name(t), t.id, t.x + cx, t.y + cy, TYP_NAMES[typ] or "?",
				areas.own_prefab(typ) and "  - built from its own prefab in the game" or "")
		else
			local slot = nearest_slot(player:get_pos())
			local info = prefabs.SLOT_INFO[slot]
			text = ("Cell: %s%s\n%s\n(red block in the base = north)"):format(slot,
				info.kind == "overlay" and "  (overlay: added on top of a floor)" or "", info.desc)
		end
		text = text .. "\nK fly - H noclip (while flying) - hold Ctrl: 4x speed - /fullbright"
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
	-- (put out the light you carried)
	local p = nhv.terrain.hero_light_pos
	if p and core.get_node(p).name == "nhv:hero_light" then
		core.set_node(p, {name = "air"})
	end
	nhv.terrain.hero_light_pos = nil
end)

-- /fullbright: see everything at full brightness (the VoxHack build
-- of Luanti draws blocks and objects without light or shadow)
core.register_chatcommand("fullbright", {
	description = "Toggle seeing everything at full brightness",
	func = function(pname)
		local player = core.get_player_by_name(pname)
		if not player then
			return false
		end
		local on = not player:hud_get_flags().nhv_fullbright
		player:hud_set_flags({nhv_fullbright = on})
		return true, on and "Full brightness on (/fullbright to turn it off)." or "Full brightness off."
	end,
})

-- Quit in the pause menu sends "/nhvtitle" (the game's title screen); the
-- editor has none, so it just closes (everything is saved on the way out)
core.register_chatcommand("nhvtitle", {
	description = "(VoxHack) leave the editor",
	func = function(pname)
		core.disconnect_player(pname, "nhv:quit")
		return true
	end,
})

-- holding Ctrl moves you (flying or walking) at four times the speed; a light
-- goes with you, as in the game (never saved into a cell or area)
local ctrl_held = {}
core.register_globalstep(function()
	for _, player in ipairs(core.get_connected_players()) do
		nhv.terrain.place_hero_light(player:get_pos())
		local name = player:get_player_name()
		local ctrl = player:get_player_control().nhv_ctrl or false
		if ctrl ~= (ctrl_held[name] or false) then
			ctrl_held[name] = ctrl
			player:set_physics_override({speed = ctrl and 4 or 1})
		end
	end
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

