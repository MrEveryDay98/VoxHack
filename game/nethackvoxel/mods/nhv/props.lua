-- Props: placeable objects drawn as extruded voxel sprites.
--
-- Every nhv_object_<name>.png in nhv_tiles/textures becomes a block,
-- "nhv:prop_<name>", in the editor's palette. It is drawn as an extruded
-- sprite one node tall standing in the middle of its node, facing the way
-- it was placed (not turning toward you), and it rotates with the prefab.
--
-- The node itself is invisible; an entity draws the sprite. Entities are
-- added when a prop is placed, when the map around it loads, and when the
-- game builds a square (terrain calls props.refresh for what it wrote).

local props = {objs = {}}
nhv.props = props

local TEX_DIR = core.get_modpath("nhv_tiles") .. DIR_DELIM .. "textures"

local function key(pos)
	return pos.x .. "," .. pos.y .. "," .. pos.z
end

-- yaw of a prop from its node's param2 (facedir, rotation part)
local function yaw_of(p2)
	return -((p2 or 0) % 4) * math.pi / 2
end

core.register_entity("nhv:prop", {
	initial_properties = {
		visual = "wielditem", wield_item = "air", visual_size = {x = 0.5, y = 0.5, z = 0.5},
		physical = false, pointable = false, static_save = false, shaded = true,
	},
})

function props.remove(pos)
	local k = key(pos)
	local obj = props.objs[k]
	if obj and obj:get_pos() then
		obj:remove()
	end
	props.objs[k] = nil
end

-- (re)draw the prop at pos, if the node there is one
function props.show(pos)
	local node = core.get_node(pos)
	local def = core.registered_nodes[node.name]
	if not (def and def.groups and def.groups.nhv_prop) then
		props.remove(pos)
		return
	end
	local k = key(pos)
	local obj = props.objs[k]
	if not (obj and obj:get_pos()) then
		obj = core.add_entity(pos, "nhv:prop")
		props.objs[k] = obj
	end
	if obj then
		obj:set_properties({wield_item = node.name})
		obj:set_pos(pos)
		obj:set_yaw(yaw_of(node.param2))
	end
end

-- props in a box of nodes (after terrain wrote it)
function props.refresh(minp, maxp)
	for k, obj in pairs(props.objs) do
		local p = obj:get_pos()
		if not p or (p.x >= minp.x and p.x <= maxp.x and p.y >= minp.y and p.y <= maxp.y
				and p.z >= minp.z and p.z <= maxp.z) then
			if p then
				obj:remove()
			end
			props.objs[k] = nil
		end
	end
	for _, pos in ipairs(core.find_nodes_in_area(minp, maxp, "group:nhv_prop")) do
		props.show(pos)
	end
end

function props.clear()
	for k, obj in pairs(props.objs) do
		if obj:get_pos() then
			obj:remove()
		end
		props.objs[k] = nil
	end
end

-- ---------------------------------------------------------------- nodes
props.names = {}

-- an object block: node name, texture, description; extra = more node
-- fields (walkable, climbable, light_source, ...) from the block editor
function props.register(node, tex, desc, extra)
	local groups = {editor = 1, nhv_prop = 1, not_in_creative_inventory = 1}
	local def = {
		description = desc,
		drawtype = "airlike",
		inventory_image = tex, wield_image = tex, -- the entity draws it extruded
		paramtype = "light", paramtype2 = "facedir", sunlight_propagates = true,
		walkable = false, pointable = true, buildable_to = false,
		selection_box = {type = "fixed", fixed = {-0.4, -0.5, -0.4, 0.4, 0.5, 0.4}},
		is_ground_content = false, drop = "",
		groups = groups,
		on_place = core.rotate_node,
		on_construct = function(pos) core.after(0, props.show, pos) end,
		after_destruct = function(pos) props.remove(pos) end,
		on_rotate = function(pos) core.after(0, props.show, pos) end,
	}
	for k, v in pairs(extra or {}) do
		if k == "groups" then
			for g, n in pairs(v) do
				groups[g] = n
			end
		else
			def[k] = v
		end
	end
	core.register_node(":" .. node, def)
	props.names[#props.names + 1] = node
end

for _, f in ipairs(core.get_dir_list(TEX_DIR, false) or {}) do
	local name = f:match("^nhv_object_([%w_]+)%.png$")
	if name then
		props.register("nhv:prop_" .. name:lower(), f, "Object: " .. name:gsub("_", " "))
	end
end

-- props in map blocks that load (entities aren't saved with the map)
core.register_lbm({
	name = "nhv:show_props",
	nodenames = {"group:nhv_prop"},
	run_at_every_load = true,
	action = function(pos)
		props.show(pos)
	end,
})

return props
