-- Doors: connected door blocks show one picture stretched across them.
--
-- Door blocks (the game's closed door and the editor's "Door" building
-- block) are solid but invisible; for each group of door blocks touching
-- each other, a box the size of the group is drawn with the door texture
-- (nhv_tiles/textures/nhv_wall_door.png) stretched over its faces. A 3x3
-- wall of door blocks is one big door, a single block is a small one.
-- Groups that aren't a solid box are drawn block by block.

local doors = {ents = {}} -- key "x,y,z|sx,sy,sz" -> {obj=, minp=, maxp=}
nhv.doors = doors

doors.TEXTURE = "nhv_wall_door.png"
-- the door's edges: the darkest brown of the door texture
doors.EDGE = "[fill:1x1:#914700"
doors.NODES = {"nhv:door_closed", "nhv:b_door"}
local MAX_GROUP = 256

local is_door = {}
for _, n in ipairs(doors.NODES) do
	is_door[n] = true
end

core.register_entity("nhv:door_panel", {
	initial_properties = {
		visual = "cube", physical = false, pointable = false, static_save = false,
		textures = {doors.TEXTURE, doors.TEXTURE, doors.TEXTURE, doors.TEXTURE,
			doors.TEXTURE, doors.TEXTURE},
		visual_size = {x = 1, y = 1, z = 1}, shaded = true,
	},
})

-- door blocks are drawn by the panels, not as nodes
for _, n in ipairs(doors.NODES) do
	if core.registered_nodes[n] then
		local groups = table.copy(core.registered_nodes[n].groups or {})
		groups.nhv_door = 1
		core.override_item(n, {
			drawtype = "airlike", tiles = {doors.TEXTURE},
			inventory_image = doors.TEXTURE, wield_image = doors.TEXTURE,
			paramtype = "light", sunlight_propagates = true,
			walkable = true, pointable = true, groups = groups,
		})
	end
end

local function hash(p)
	return p.x .. "," .. p.y .. "," .. p.z
end

local function overlaps(a1, a2, b1, b2)
	return a1.x <= b2.x and a2.x >= b1.x and a1.y <= b2.y and a2.y >= b1.y
		and a1.z <= b2.z and a2.z >= b1.z
end

local function solid(pos)
	local def = core.registered_nodes[core.get_node(pos).name]
	return def and def.walkable and not (def.groups and def.groups.nhv_door)
end

-- which way a door faces: the axis it's thinnest along ("x" or "z"); a
-- door as thick as it is wide faces away from the walls beside it
local function facing(minp, size)
	if size.x ~= size.z then
		return size.x < size.z and "x" or "z"
	end
	if solid(vector.new(minp.x - 1, minp.y, minp.z)) or solid(vector.new(minp.x + size.x, minp.y, minp.z)) then
		return "z" -- walls to the east/west: the door spans x, faces z
	end
	return "x"
end

local function add_panel(minp, maxp)
	local size = vector.add(vector.subtract(maxp, minp), 1)
	local center = vector.multiply(vector.add(minp, maxp), 0.5)
	local obj = core.add_entity(center, "nhv:door_panel")
	if obj then
		-- cube faces: +y, -y, +x, -x, +z, -z; the picture goes on the two
		-- big faces, the edges are plain dark brown
		local P, D = doors.TEXTURE, doors.EDGE
		local tex = facing(minp, size) == "x" and {D, D, P, P, D, D} or {D, D, D, D, P, P}
		obj:set_properties({visual_size = size, textures = tex})
		doors.ents[hash(minp) .. "|" .. hash(size)] = {obj = obj, minp = minp, maxp = maxp}
	end
end

-- the group of door blocks touching start (6 directions)
local DIRS = {
	vector.new(1, 0, 0), vector.new(-1, 0, 0), vector.new(0, 1, 0),
	vector.new(0, -1, 0), vector.new(0, 0, 1), vector.new(0, 0, -1),
}
local function flood(start, seen)
	local list, stack = {}, {start}
	seen[hash(start)] = true
	while #stack > 0 and #list < MAX_GROUP do
		local p = table.remove(stack)
		list[#list + 1] = p
		for _, d in ipairs(DIRS) do
			local q = vector.add(p, d)
			local k = hash(q)
			if not seen[k] and is_door[core.get_node(q).name] then
				seen[k] = true
				stack[#stack + 1] = q
			end
		end
	end
	return list
end

local function draw_group(list)
	local minp, maxp = vector.copy(list[1]), vector.copy(list[1])
	for _, p in ipairs(list) do
		minp = vector.new(math.min(minp.x, p.x), math.min(minp.y, p.y), math.min(minp.z, p.z))
		maxp = vector.new(math.max(maxp.x, p.x), math.max(maxp.y, p.y), math.max(maxp.z, p.z))
	end
	local vol = (maxp.x - minp.x + 1) * (maxp.y - minp.y + 1) * (maxp.z - minp.z + 1)
	if vol == #list then
		add_panel(minp, maxp)
	else
		for _, p in ipairs(list) do -- not a solid box: one picture per block
			add_panel(p, p)
		end
	end
end

-- redraw the doors in (and touching) a box of nodes
function doors.refresh(minp, maxp)
	local seeds = core.find_nodes_in_area(minp, maxp, "group:nhv_door")
	-- panels drawn over this box go; their blocks get redrawn below
	for k, e in pairs(doors.ents) do
		if overlaps(e.minp, e.maxp, minp, maxp) then
			if e.obj:get_pos() then
				e.obj:remove()
			end
			doors.ents[k] = nil
			for _, p in ipairs(core.find_nodes_in_area(e.minp, e.maxp, "group:nhv_door")) do
				seeds[#seeds + 1] = p
			end
		end
	end
	local seen = {}
	for _, p in ipairs(seeds) do
		if not seen[hash(p)] then
			local list = flood(p, seen)
			-- a group reaching past the box may have a panel outside it too
			for k, e in pairs(doors.ents) do
				for _, q in ipairs(list) do
					if overlaps(e.minp, e.maxp, q, q) then
						if e.obj:get_pos() then
							e.obj:remove()
						end
						doors.ents[k] = nil
						break
					end
				end
			end
			draw_group(list)
		end
	end
end

-- around one changed block (placing / digging in the editor)
function doors.refresh_around(pos)
	local r = vector.new(1, 1, 1)
	doors.refresh(vector.subtract(pos, r), vector.add(pos, r))
end

function doors.clear()
	for k, e in pairs(doors.ents) do
		if e.obj:get_pos() then
			e.obj:remove()
		end
		doors.ents[k] = nil
	end
end

-- editor: placing or digging a block may join or split doors
core.register_on_placenode(function(pos)
	core.after(0, doors.refresh_around, pos)
end)
core.register_on_dignode(function(pos)
	core.after(0, doors.refresh_around, pos)
end)

-- map blocks loading: draw their doors (once per step, batched)
local pending = {}
core.register_lbm({
	name = "nhv:show_doors",
	nodenames = {"group:nhv_door"},
	run_at_every_load = true,
	action = function(pos)
		pending[#pending + 1] = pos
	end,
})
core.register_globalstep(function()
	if #pending == 0 then
		return
	end
	local list = pending
	pending = {}
	local minp, maxp = vector.copy(list[1]), vector.copy(list[1])
	for _, p in ipairs(list) do
		minp = vector.new(math.min(minp.x, p.x), math.min(minp.y, p.y), math.min(minp.z, p.z))
		maxp = vector.new(math.max(maxp.x, p.x), math.max(maxp.y, p.y), math.max(maxp.z, p.z))
	end
	doors.refresh(minp, maxp)
end)

return doors
