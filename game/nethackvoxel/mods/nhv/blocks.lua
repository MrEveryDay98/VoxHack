-- Building blocks for prefabs, and the editor-only marker nodes.
--
-- Materials use NetHack's own tiles (or plain colours); each comes in a
-- few shapes. Markers are visible in the editor and invisible in game.

local blocks = {}
nhv.blocks = blocks

local function tile_tex(n)
	return "[fill:16x16:#000000^(" .. nhv_tiles.texture(n) .. ")"
end

-- name, description, texture, extra node fields
local MATERIALS = {
	{"stone", "Stone", tile_tex(1272)},
	{"brick", "Wall brick", "nhv_wall_main.png"},
	{"brick_dark", "Dark wall brick", "nhv_wall_main.png^[multiply:#808080"},
	{"door", "Door (joins with other door blocks into one picture)", "nhv_wall_door.png"},
	{"floor", "Room floor", tile_tex(1291)},
	{"corridor", "Corridor floor", tile_tex(1294)},
	{"stairs", "Stair steps", tile_tex(1298)},
	{"ladder", "Ladder", tile_tex(1300)},
	{"altar", "Altar stone", tile_tex(1307)},
	{"fountain", "Fountain basin", tile_tex(1313)},
	{"throne", "Throne", tile_tex(1311)},
	{"sink", "Sink", tile_tex(1312)},
	{"grave", "Grave", tile_tex(1310)},
	{"tree", "Tree", tile_tex(1290)},
	{"ice", "Ice", tile_tex(1315)},
	{"drawbridge", "Drawbridge planks", tile_tex(1319)},
	{"black", "Black", "[fill:16x16:#000000"},
	{"white", "White", "[fill:16x16:#E8E8E8"},
	{"gray", "Gray", "[fill:16x16:#707070"},
	{"red", "Red", "[fill:16x16:#B02020"},
	{"green", "Green", "[fill:16x16:#208030"},
	{"blue", "Blue", "[fill:16x16:#2040B0"},
	{"yellow", "Yellow", "[fill:16x16:#D0B020"},
	{"brown", "Brown", "[fill:16x16:#704020"},
	{"metal", "Metal", "[fill:16x16:#9098A8"},
}

local SHAPES = {
	{"block", "", nil},
	{"slab", " slab", {-0.5, -0.5, -0.5, 0.5, 0, 0.5}},
	{"stair", " stair", {{-0.5, -0.5, -0.5, 0.5, 0, 0.5}, {-0.5, 0, 0, 0.5, 0.5, 0.5}}},
	{"pane", " pane", {-0.5, -0.5, -0.0625, 0.5, 0.5, 0.0625}},
	{"post", " post", {-0.1875, -0.5, -0.1875, 0.1875, 0.5, 0.1875}},
}

blocks.names = {}

local editor_groups = {editor = 1, nhv_build = 1, not_in_creative_inventory = 1}

for _, m in ipairs(MATERIALS) do
	for _, sh in ipairs(SHAPES) do
		local name = "nhv:b_" .. m[1] .. (sh[1] == "block" and "" or ("_" .. sh[1]))
		local def = {
			description = m[2] .. sh[2],
			tiles = {m[3]},
			paramtype = "light",
			is_ground_content = false,
			groups = editor_groups,
			drop = "",
		}
		if sh[3] then
			def.drawtype = "nodebox"
			def.node_box = {type = "fixed", fixed = sh[3]}
			def.paramtype2 = "facedir"
			def.on_place = core.rotate_node
		end
		core.register_node(name, def)
		blocks.names[#blocks.names + 1] = name
	end
end

-- lights
for _, l in ipairs({{"lamp", "Lamp", 14, "#FFE0A0"}, {"lamp_dim", "Dim lamp", 8, "#A08060"}}) do
	local name = "nhv:b_" .. l[1]
	core.register_node(name, {
		description = l[2], tiles = {"[fill:16x16:" .. l[4]}, paramtype = "light",
		light_source = l[3], groups = editor_groups, drop = "", is_ground_content = false,
	})
	blocks.names[#blocks.names + 1] = name
end

-- invisible wall (collision without anything to see)
core.register_node("nhv:b_barrier", {
	description = "Invisible barrier",
	drawtype = nhv.EDITOR and "glasslike" or "airlike",
	tiles = {"[fill:16x16:#40FFFF40"},
	use_texture_alpha = "blend",
	paramtype = "light", sunlight_propagates = true,
	pointable = nhv.EDITOR, groups = editor_groups, drop = "",
})
blocks.names[#blocks.names + 1] = "nhv:b_barrier"

-- ---------------------------------------------------------------- markers
local function marker(name, desc, color)
	core.register_node(name, {
		description = desc,
		drawtype = nhv.EDITOR and "glasslike" or "airlike",
		tiles = {"[fill:16x16:" .. color},
		use_texture_alpha = "blend",
		paramtype = "light",
		sunlight_propagates = true,
		walkable = false,
		pointable = nhv.EDITOR,
		buildable_to = not nhv.EDITOR,
		groups = editor_groups,
		drop = "",
	})
	blocks.names[#blocks.names + 1] = name
end
marker("nhv:trigger", "Stairs trigger (touch to change level)", "#FF404080")
marker("nhv:mpath", "Monster path (to the trigger)", "#40FF4080")
marker("nhv:carve", "Carve (overlays: force air)", "#FFFF4060")

-- a lit room's light, placed by the game (not a building block)
core.register_node("nhv:room_light", {
	description = "Room light", drawtype = "airlike", paramtype = "light",
	sunlight_propagates = true, walkable = false, pointable = false,
	buildable_to = true, light_source = core.LIGHT_MAX,
	groups = {not_in_creative_inventory = 1}, drop = "",
})

-- ---------------------------------------------------------------- culling
-- Backface culling for every NetHack Voxel block: the back of a face is
-- never drawn (from inside a block you see out, not its inner walls).
core.register_on_mods_loaded(function()
	for name, def in pairs(core.registered_nodes) do
		if name:match("^nhv:") and def.tiles and def.drawtype ~= "airlike" then
			local tiles = {}
			for i, t in ipairs(def.tiles) do
				local tt = type(t) == "table" and table.copy(t) or {name = t}
				tt.backface_culling = true
				tiles[i] = tt
			end
			core.override_item(name, {tiles = tiles})
		end
	end
end)

return blocks
