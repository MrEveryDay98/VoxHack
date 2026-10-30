-- The opening's forest: its blocks (the intro editor builds it with them -
-- intro_editor.lua - and the game puts it up to play the opening in -
-- intro_play.lua).
--
--   grass (three kinds) over dirt: nhv_tiles/textures/worldbuilding_sprites.png
--   trees: NetHack's tree, a sprite as monsters and objects are - extruded or
--     flat (Options > Sprites), always turned to you (the VoxHack engine
--     turns an object marked "nhv:billboard" to the camera itself). The
--     block is just where one stands: intro_blocks.trees() puts them up.
--   a monster or person: any NetHack monster's sprite, the same - its block
--     too is just where it stands (which, how tall: the editor's settings)
--   a camera point and a sign: what the intro editor puts the camera's way
--     and the signs with (the game's copy doesn't have them: intro_play.lua
--     takes them out, and puts the signs up itself)

local SHEET = "worldbuilding_sprites.png"
local function cell(x, y)
	return ("%s^[sheet:4x4:%d,%d"):format(SHEET, x, y)
end

local DIRT = cell(0, 3)
local DIG = {crumbly = 3, oddly_breakable_by_hand = 3}

core.register_node(":nhv:intro_dirt", {
	description = "Forest dirt", tiles = {DIRT}, groups = DIG, is_ground_content = false,
})
for i = 1, 3 do
	core.register_node(":nhv:intro_grass" .. (i > 1 and i or ""), {
		description = "Forest grass" .. (i > 1 and (" " .. i) or ""),
		tiles = {cell(0, i - 1), DIRT, DIRT}, groups = DIG, is_ground_content = false,
		drop = "nhv:intro_grass",
	})
end

local TREE_TILE = 1290
local TREE_H = 3 -- (blocks tall)
core.register_node(":nhv:intro_tree", {
	description = "Forest tree", drawtype = "airlike", paramtype = "light",
	sunlight_propagates = true, walkable = false, inventory_image = nhv_tiles.texture(TREE_TILE),
	wield_image = nhv_tiles.texture(TREE_TILE), groups = {snappy = 3, oddly_breakable_by_hand = 3},
	selection_box = {type = "fixed", fixed = {-0.3, -0.5, -0.3, 0.3, TREE_H - 0.5, 0.3}},
	is_ground_content = false,
})

core.register_node(":nhv:intro_figure", {
	description = "Monster or person", drawtype = "airlike", paramtype = "light",
	sunlight_propagates = true, walkable = false, inventory_image = nhv_tiles.texture(0),
	wield_image = nhv_tiles.texture(0), groups = {dig_immediate = 3},
	selection_box = {type = "fixed", fixed = {-0.3, -0.5, -0.3, 0.3, 1.3, 0.3}},
	is_ground_content = false,
})

-- the editor's: a camera point (a yellow box, its view in its settings) and
-- a sign's place on a wall (thin, against the wall it was put on)
core.register_node(":nhv:intro_cam", {
	description = "Camera point", drawtype = "nodebox", paramtype = "light",
	tiles = {"[fill:16x16:#FFC800"}, light_source = 4, walkable = false, sunlight_propagates = true,
	node_box = {type = "fixed", fixed = {-0.2, -0.2, -0.2, 0.2, 0.2, 0.2}},
	groups = {dig_immediate = 3}, is_ground_content = false,
})
core.register_node(":nhv:intro_sign", {
	description = "Sign", drawtype = "nodebox", paramtype = "light", paramtype2 = "wallmounted",
	tiles = {"[fill:16x16:#8B5A2B"}, walkable = false, sunlight_propagates = true,
	node_box = {type = "wallmounted", wall_side = {-0.5, -0.4, -0.4, -0.45, 0.4, 0.4},
		wall_top = {-0.4, 0.45, -0.4, 0.4, 0.5, 0.4}, wall_bottom = {-0.4, -0.5, -0.4, 0.4, -0.45, 0.4}},
	groups = {dig_immediate = 3}, is_ground_content = false,
})

-- a sign's picture, three blocks wide, on the wall a sign block was put on
-- (pos: the sign block; dir: from it to the wall)
core.register_entity(":nhv:intro_sign_board", {
	initial_properties = {
		visual = "upright_sprite", physical = false, pointable = false, static_save = false,
		visual_size = {x = 3, y = 1}, shaded = true, textures = {"blank.png", "blank.png"},
	},
})
local intro_blocks = {}
nhv.intro_blocks = intro_blocks

core.register_entity(":nhv:intro_sprite", {
	initial_properties = {
		visual = "wielditem", wield_item = nhv_tiles.item(TREE_TILE), physical = false,
		pointable = false, static_save = false, collisionbox = {0, 0, 0, 0, 0, 0},
		infotext = "nhv:billboard",
	},
})

-- a tree on a tree block (pos: the block)
function intro_blocks.tree(pos)
	return {pos = pos, tile = TREE_TILE, h = TREE_H}
end

-- a NetHack tile by its name ("watchman", "gnome leader"; a monster that
-- has two, male and female: the male one), or nil
function intro_blocks.tile_named(name)
	name = (name or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
	local want = {[name] = true, [name .. ",male"] = true, [name .. " (male)"] = true}
	for t = 0, nhv_tiles.count - 1 do
		if want[nhv_tiles.name(t)] then
			return t
		end
	end
end

-- The sprites standing ({pos= (their blocks), tile=, h= (blocks tall)}):
-- put up where there isn't one (or it's changed), taken down where it isn't
-- wanted any more; returns how many stand.
local standing = {} -- "x,y,z" -> {obj=, look=}
function intro_blocks.sprites(list)
	local want = {}
	local flat = nhv_tiles.flat()
	for _, sp in ipairs(list) do
		local k = sp.pos.x .. "," .. sp.pos.y .. "," .. sp.pos.z
		want[k] = true
		local look = sp.tile .. "/" .. sp.h .. "/" .. tostring(flat)
		local st = standing[k]
		if not (st and st.obj:get_pos() and st.look == look) then
			if st and st.obj:get_pos() then
				st.obj:remove()
			end
			local obj = core.add_entity(vector.new(sp.pos.x, sp.pos.y - 0.5 + sp.h / 2, sp.pos.z), "nhv:intro_sprite")
			if obj then
				local props = nhv_tiles.look(sp.tile, sp.h)
				props.infotext = "nhv:billboard"
				obj:set_properties(props)
				-- (how far round from facing the camera: mobs.lua's way)
				obj:set_yaw(nhv_tiles.facing_turn())
				standing[k] = {obj = obj, look = look}
			else
				standing[k] = nil
			end
		end
	end
	local n = 0
	for k, st in pairs(standing) do
		if want[k] then
			n = n + 1
		else
			if st.obj:get_pos() then
				st.obj:remove()
			end
			standing[k] = nil
		end
	end
	return n
end

function intro_blocks.board(pos, dir, text)
	local words = {}
	for line in (text or ""):gmatch("[^\n]+") do
		words[#words + 1] = line
	end
	local at = vector.add(pos, vector.multiply(dir, 0.43)) -- (in front of the sign block's plate)
	local obj = core.add_entity(at, "nhv:intro_sign_board")
	if obj then
		local tex = nhv.signart.texture(words)
		obj:set_properties({textures = {tex, tex}})
		-- (its face away from the wall)
		obj:set_yaw(math.atan2(dir.x, -dir.z))
	end
	return obj
end

return intro_blocks
