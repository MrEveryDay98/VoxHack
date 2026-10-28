-- Prefabs: how each kind of map square is built out of nodes.
--
-- Every NetHack map square is a cell TILE x TILE nodes wide and H nodes
-- tall: the room space (floor to ceiling) plus extra layers below the
-- floor (for pits, stairs leading down) and above the ceiling (stairs
-- leading up). Cells are built by hand in the prefab editor world and
-- saved with /prefab save; squares without a saved build use the
-- defaults below.
--
-- Two kinds of slots:
--   base     the whole cell for a terrain type (wall, floor, door, ...)
--   overlay  added on top of a base (traps); air means "leave as is",
--            nhv:carve means "make this air"
-- Special nodes (only visible in the editor):
--   nhv:trigger  touching it uses the stairs/ladder of that square
--   nhv:mpath    path monsters follow to reach the trigger
--   nhv:carve    (overlays) force air

local U = nhv.util
local prefabs = {
	data = {},      -- slot -> {nodes = {[i] = {n=, p2=}}, custom = bool}
}
nhv.prefabs = prefabs

prefabs.W = U.TILE                 -- x and z size
-- height: tall enough for towers over the walls - 40 fills three map
-- blocks (y -9..30, with the level's invisible box round it -10..31). A
-- node's index doesn't depend on it (prefabs.index), so cells saved when
-- it was lower read the same.
prefabs.H = 40
prefabs.Y0 = U.FLOOR_Y - 8         -- world y of the cell's bottom layer
prefabs.FLOOR = 8                  -- layer index (0-based) of the floor
prefabs.CEIL = prefabs.FLOOR + U.WALL_H + 1

local W, H = prefabs.W, prefabs.H
local FL, CL = prefabs.FLOOR, prefabs.CEIL

function prefabs.index(lx, ly, lz)
	return (ly * W + lz) * W + lx + 1
end

function prefabs.unindex(i)
	i = i - 1
	local lx = i % W
	local lz = math.floor(i / W) % W
	local ly = math.floor(i / (W * W))
	return lx, ly, lz
end

-- ---------------------------------------------------------------- slots
-- name, kind, description (with the orientation to build it in)
prefabs.SLOTS = {
	{"stone", "base", "Solid rock (unexcavated)"},
	{"wall_straight", "base", "Wall running north-south (it is rotated for east-west)"},
	{"wall_corner", "base", "Wall corner joining east and south"},
	{"wall_tee", "base", "T wall joining west, east and south"},
	{"wall_cross", "base", "Wall crossing"},
	{"floor", "base", "Room floor"},
	{"corridor", "base", "Corridor"},
	{"doorway", "base", "Empty doorway (passage runs north-south)"},
	{"door_broken", "base", "Broken door (passage runs north-south)"},
	{"door_open", "base", "Open door (passage runs north-south)"},
	{"door_closed", "base", "Closed door (passage runs north-south)"},
	{"stairs_up", "base", "Staircase up - put an nhv:trigger where it leads"},
	{"stairs_down", "base", "Staircase down - put an nhv:trigger where it leads"},
	{"ladder_up", "base", "Ladder up - with an nhv:trigger"},
	{"ladder_down", "base", "Ladder down - with an nhv:trigger"},
	{"altar", "base", "Altar"},
	{"fountain", "base", "Fountain"},
	{"throne", "base", "Throne"},
	{"sink", "base", "Sink"},
	{"grave", "base", "Grave"},
	{"tree", "base", "Tree"},
	{"iron_bars", "base", "Iron bars"},
	{"pool", "base", "Pool / moat"},
	{"water", "base", "Wall of water (Plane of Water)"},
	{"lava", "base", "Molten lava"},
	{"lava_wall", "base", "Wall of lava"},
	{"ice", "base", "Ice"},
	{"drawbridge_down", "base", "Lowered drawbridge (runs north-south)"},
	{"air", "base", "Open air (Plane of Air)"},
	{"cloud", "base", "Cloud (Plane of Air)"},
}
local TRAPS = {
	"arrow_trap", "dart_trap", "falling_rock_trap", "squeaky_board",
	"bear_trap", "land_mine", "rolling_boulder_trap", "sleeping_gas_trap",
	"rust_trap", "fire_trap", "pit", "spiked_pit", "hole", "trap_door",
	"teleportation_trap", "level_teleporter", "magic_portal", "web",
	"statue_trap", "magic_trap", "anti_magic_trap", "polymorph_trap",
	"vibrating_square",
}
for _, t in ipairs(TRAPS) do
	table.insert(prefabs.SLOTS, {"trap_" .. t, "overlay", "Trap: " .. t:gsub("_", " ")})
end
-- the ways up on a level open to the sky (no ceiling to climb through:
-- a portal...); used there once hand-built, else the usual ones. (At the
-- end, so the editor's other plates keep their places.)
table.insert(prefabs.SLOTS, {"stairs_up_sky", "base",
	"Staircase up on a level open to the sky - put an nhv:trigger where it leads"})
table.insert(prefabs.SLOTS, {"ladder_up_sky", "base",
	"Ladder up on a level open to the sky - with an nhv:trigger"})
prefabs.SLOT_INFO = {}
for i, s in ipairs(prefabs.SLOTS) do
	prefabs.SLOT_INFO[s[1]] = {kind = s[2], desc = s[3], order = i}
end

-- ---------------------------------------------------------------- defaults
-- (the usual prefabs stop where cells used to: rock five layers over the
-- ceiling, not up to the top of the taller cells)
local DEFAULT_TOP = math.min(H - 1, CL + 5)
local function column(get)
	local nodes = {}
	for ly = 0, DEFAULT_TOP do
		local n = get(ly)
		if n and n ~= "air" then
			for lx = 0, W - 1 do
				for lz = 0, W - 1 do
					nodes[prefabs.index(lx, ly, lz)] = {n = n, p2 = 0}
				end
			end
		end
	end
	return nodes
end

local function solid(name)
	return column(function(ly)
		if ly >= FL and ly <= CL - 1 then
			return name
		end
		return "nhv:rock"
	end)
end

local function room(floor, mid)
	return column(function(ly)
		if ly < FL then
			return "nhv:rock"
		elseif ly == FL then
			return floor
		elseif ly < CL then
			return mid or "air"
		elseif ly == CL then
			return "nhv:ceiling"
		end
		return "nhv:rock"
	end)
end

local function door(panel)
	local nodes = room("nhv:doorway")
	for lx = 0, W - 1 do
		for lz = 0, W - 1 do
			nodes[prefabs.index(lx, CL - 1, lz)] = {n = "nhv:wall", p2 = 0} -- lintel
		end
	end
	if panel then
		for lx = 0, W - 1 do
			for ly = FL + 1, CL - 2 do
				nodes[prefabs.index(lx, ly, 1)] = {n = panel, p2 = 0}
			end
		end
	end
	return nodes
end

-- pits are real holes: the floor is taken away and you land two blocks
-- down (on spikes, in a spiked pit); Space at the edge climbs out
local function pit(spikes)
	local nodes = {}
	for lx = 0, W - 1 do
		for lz = 0, W - 1 do
			nodes[prefabs.index(lx, FL, lz)] = {n = "nhv:carve"}
			nodes[prefabs.index(lx, FL - 1, lz)] = {n = spikes and "nhv:x_spikes" or "nhv:carve"}
			nodes[prefabs.index(lx, FL - 2, lz)] = {n = "nhv:floor"}
		end
	end
	return nodes
end

-- a hole: the floor gone, a deep shaft into the dark (with a bottom, for
-- when NetHack lets you escape it: climb out as from a pit)
local function hole()
	local nodes = {}
	for ly = 2, FL do
		for lx = 0, W - 1 do
			for lz = 0, W - 1 do
				nodes[prefabs.index(lx, ly, lz)] = {n = "nhv:carve"}
			end
		end
	end
	return nodes
end

-- a trap door: a wooden hatch set into the floor (closed: it opens under you)
local function trap_door()
	local nodes = {}
	for lx = 0, W - 1 do
		for lz = 0, W - 1 do
			nodes[prefabs.index(lx, FL, lz)] = {n = "nhv:b_drawbridge"}
		end
	end
	nodes[prefabs.index(1, FL, 1)] = {n = "nhv:b_metal"} -- (its iron plate)
	return nodes
end

local DEFAULTS = {
	trap_pit = function() return pit(false) end,
	trap_spiked_pit = function() return pit(true) end,
	trap_hole = hole,
	trap_trap_door = trap_door,
	stone = function() return column(function() return "nhv:rock" end) end,
	wall_straight = function() return solid("nhv:wall") end,
	wall_corner = function() return solid("nhv:wall") end,
	wall_tee = function() return solid("nhv:wall") end,
	wall_cross = function() return solid("nhv:wall") end,
	floor = function() return room("nhv:floor") end,
	corridor = function() return room("nhv:corridor") end,
	doorway = function() return door(nil) end,
	door_broken = function() return door(nil) end,
	door_open = function() return door(nil) end,
	door_closed = function() return door("nhv:door_closed") end,
	stairs_up = function() return room("nhv:stairs_up") end,
	stairs_down = function() return room("nhv:stairs_down") end,
	ladder_up = function() return room("nhv:ladder_up") end,
	ladder_down = function() return room("nhv:ladder_down") end,
	altar = function() return room("nhv:floor") end,
	fountain = function() return room("nhv:floor") end,
	throne = function() return room("nhv:floor") end,
	sink = function() return room("nhv:floor") end,
	grave = function() return room("nhv:floor") end,
	-- the tree itself is a sprite; the barrier gives it NetHack's solidity
	tree = function() return room("nhv:floor", "nhv:b_barrier") end,
	iron_bars = function() return room("nhv:floor", "nhv:bars") end,
	pool = function() return room("nhv:water") end,
	water = function() return room("nhv:waterwall", "nhv:waterwall") end,
	lava = function() return room("nhv:lava") end,
	lava_wall = function() return solid("nhv:lavawall") end,
	ice = function() return room("nhv:ice") end,
	drawbridge_down = function() return room("nhv:drawbridge") end,
	air = function() return room("nhv:air_floor") end,
	cloud = function() return room("nhv:air_floor") end,
	-- (start as a copy of the usual way up, to build on)
	stairs_up_sky = function() return table.copy(prefabs.get("stairs_up").nodes) end,
	ladder_up_sky = function() return table.copy(prefabs.get("ladder_up").nodes) end,
}

-- (a default that changed gets a higher number: the prefab editor rebuilds
-- that cell, unless it was hand-built)
prefabs.DEFAULT_VERSION = {trap_hole = 2, trap_trap_door = 2}

function prefabs.default(slot)
	local f = DEFAULTS[slot]
	return {nodes = f and f() or {}, custom = false}
end

-- ---------------------------------------------------------------- load/save
-- (the mod data path is only available while mods load)
local DATA_DIR = core.get_mod_data_path()
local DATA_PATH = DATA_DIR .. DIR_DELIM .. "prefabs.dat"
prefabs.DATA_PATH = DATA_PATH

function prefabs.load()
	prefabs.data = {}
	local f = io.open(DATA_PATH, "rb")
	if f then
		local saved = core.deserialize(f:read("*a")) or {}
		f:close()
		-- only hand-built cells; the rest follow the current defaults
		for slot, d in pairs(saved) do
			if prefabs.SLOT_INFO[slot] and d.custom then
				prefabs.data[slot] = d
			end
		end
	end
end

function prefabs.save()
	core.mkdir(DATA_DIR)
	return core.safe_file_write(DATA_PATH, core.serialize(prefabs.data))
end

function prefabs.get(slot)
	local d = prefabs.data[slot]
	if not d then
		d = prefabs.default(slot)
		prefabs.data[slot] = d
	end
	return d
end

-- is this slot hand-built (then its sprite is not drawn on top)?
function prefabs.custom(slot)
	local d = prefabs.data[slot]
	return d and d.custom or false
end

-- ---------------------------------------------------------------- rotation
-- rotate a cell position r quarter turns clockwise (seen from above)
local function rot_xz(lx, lz, r)
	for _ = 1, r % 4 do
		local dx, dz = lx - 1, lz - 1
		lx, lz = 1 + dz, 1 - dx
	end
	return lx, lz
end
prefabs.rot_xz = rot_xz

-- Turning a cell turns the blocks in it too: their param2 facing.
-- facedir (all 24 ways: on its side and upside down as well) is worked out
-- from how the engine itself orients a facedir node (transformNodeBox in
-- mapnode.cpp): a turn about the node's own axis, then the axis tipped over.
local function rot90(v, plane, deg) -- irrlicht's rotateXZBy / XYBy / YZBy
	local c, sn = math.floor(math.cos(math.rad(deg)) + 0.5), math.floor(math.sin(math.rad(deg)) + 0.5)
	local x, y, z = v[1], v[2], v[3]
	if plane == "xz" then
		return {x * c - z * sn, y, x * sn + z * c}
	elseif plane == "xy" then
		return {x * c - y * sn, x * sn + y * c, z}
	end
	return {x, y * c - z * sn, y * sn + z * c} -- yz
end

local AXIS_TURN = {{"xz", 0}, {"yz", 90}, {"yz", -90}, {"xy", -90}, {"xy", 90}, {"xy", -180}}
local DIR_TURN = {0, -90, 180, 90}
local function facedir_apply(f, v)
	local axis, dir = math.floor(f / 4), f % 4
	v = rot90(v, "xz", DIR_TURN[dir + 1])
	return rot90(v, AXIS_TURN[axis + 1][1], AXIS_TURN[axis + 1][2])
end

-- where facedir f puts the node's x, y and z axes, as a string
local function facedir_key(f, turns)
	local out = {}
	for _, e in ipairs({{1, 0, 0}, {0, 1, 0}, {0, 0, 1}}) do
		local v = facedir_apply(f, e)
		for _ = 1, turns do
			v = rot90(v, "xz", -90) -- (a cell's quarter turn: +z goes to +x; see rot_xz)
		end
		-- (+ 0: a -0 would print as "-0" and not match "0")
		out[#out + 1] = (v[1] + 0) .. "," .. (v[2] + 0) .. "," .. (v[3] + 0)
	end
	return table.concat(out, ";")
end

-- FACEDIR_TURN[r][f]: facedir f after r quarter turns
local FACEDIR_TURN = {}
do
	local by_key = {}
	for f = 0, 23 do
		by_key[facedir_key(f, 0)] = f
	end
	for r = 1, 3 do
		FACEDIR_TURN[r] = {}
		for f = 0, 23 do
			FACEDIR_TURN[r][f] = by_key[facedir_key(f, r)] or f
		end
	end
end

-- wallmounted: 2 x+, 3 x-, 4 z+, 5 z- (one quarter turn: z+ -> x+ -> z-
-- -> x-); 0/1 (ceiling/floor) and 6/7 (the same, turned) swap on odd turns
local WALLMOUNTED_TURN = {[0] = 6, 7, 5, 4, 2, 3, 0, 1}

local rotatable = {}
local function rot_p2(name, p2, r)
	r = r % 4
	if r == 0 then
		return p2
	end
	local pt = rotatable[name]
	if pt == nil then
		local def = core.registered_nodes[name]
		pt = def and def.paramtype2 or ""
		rotatable[name] = pt
	end
	if pt == "facedir" or pt == "colorfacedir" then
		local f = p2 % 32
		return p2 - f + (f < 24 and FACEDIR_TURN[r][f] or f)
	elseif pt == "4dir" or pt == "color4dir" then
		return p2 - p2 % 4 + (p2 % 4 + r) % 4
	elseif pt == "wallmounted" or pt == "colorwallmounted" then
		local w = p2 % 8
		for _ = 1, r do
			w = WALLMOUNTED_TURN[w]
		end
		return p2 - p2 % 8 + w
	end
	return p2
end

prefabs.rot_p2 = rot_p2 -- (the editor's /paste turns blocks with it too)

-- ---------------------------------------------------------------- placing
-- Write a slot into VoxelManip data for square (tx, ty).
-- cid(name) -> content id. base=true replaces everything (missing = air);
-- otherwise only listed nodes are written.
function prefabs.write(data, area, tx, ty, slot, rot, base, cid)
	local ox, oz = U.tile_origin(tx, ty)
	prefabs.write_at(data, area, vector.new(ox, prefabs.Y0, oz), prefabs.get(slot).nodes,
		rot, base, cid)
end

-- The same with a cell's nodes, at a cell origin (its bottom south-west
-- node) anywhere: the prefab editor's area plates, area prefab cells.
function prefabs.write_at(data, area, o, nodes, rot, base, cid)
	local air = cid("air")
	if base then
		for ly = 0, H - 1 do
			for lx = 0, W - 1 do
				for lz = 0, W - 1 do
					data.ids[area:index(o.x + lx, o.y + ly, o.z + lz)] = air
					data.p2[area:index(o.x + lx, o.y + ly, o.z + lz)] = 0
				end
			end
		end
	end
	for i, nd in pairs(nodes) do
		local lx, ly, lz = prefabs.unindex(i)
		local rx, rz = rot_xz(lx, lz, rot or 0)
		local vi = area:index(o.x + rx, o.y + ly, o.z + rz)
		local name = nd.n
		if name == "nhv:carve" or not core.registered_nodes[name] then
			name = "air"
		end
		data.ids[vi] = cid(name)
		data.p2[vi] = rot_p2(name, nd.p2 or 0, rot or 0)
	end
end

-- The nodes of a cell built at origin o (non-air ones; the editor's room
-- lights aren't part of it: the game lights rooms itself).
function prefabs.read_at(o)
	local nodes = {}
	for ly = 0, H - 1 do
		for lx = 0, W - 1 do
			for lz = 0, W - 1 do
				local node = core.get_node(vector.new(o.x + lx, o.y + ly, o.z + lz))
				if node.name ~= "air" and node.name ~= "ignore" and node.name ~= "nhv:room_light"
						and node.name ~= "nhv:hero_light" then
					nodes[prefabs.index(lx, ly, lz)] = {n = node.name, p2 = node.param2}
				end
			end
		end
	end
	return nodes
end

-- Node positions of special markers of a slot placed at (tx, ty).
function prefabs.markers(slot, tx, ty, rot, marker)
	local d = prefabs.get(slot)
	local ox, oz = U.tile_origin(tx, ty)
	local out = {}
	for i, nd in pairs(d.nodes) do
		if nd.n == marker then
			local lx, ly, lz = prefabs.unindex(i)
			local rx, rz = rot_xz(lx, lz, rot or 0)
			out[#out + 1] = vector.new(ox + rx, prefabs.Y0 + ly, oz + rz)
		end
	end
	return out
end

-- Read a cell built in the editor (origin = its bottom south-west node).
function prefabs.capture(slot, origin)
	local info = prefabs.SLOT_INFO[slot]
	local nodes = {}
	for ly = 0, H - 1 do
		for lx = 0, W - 1 do
			for lz = 0, W - 1 do
				local node = core.get_node(vector.new(origin.x + lx, origin.y + ly, origin.z + lz))
				if node.name ~= "air" and node.name ~= "ignore" and node.name ~= "nhv:hero_light" then
					nodes[prefabs.index(lx, ly, lz)] = {n = node.name, p2 = node.param2}
				end
			end
		end
	end
	-- custom if it differs from the default build
	local def = prefabs.default(slot).nodes
	local custom = false
	for i, nd in pairs(nodes) do
		if not def[i] or def[i].n ~= nd.n or (def[i].p2 or 0) ~= (nd.p2 or 0) then
			custom = true
			break
		end
	end
	if not custom then
		for i in pairs(def) do
			if not nodes[i] then
				custom = true
				break
			end
		end
	end
	return {nodes = nodes, custom = custom, kind = info and info.kind}
end

prefabs.load()

return prefabs
