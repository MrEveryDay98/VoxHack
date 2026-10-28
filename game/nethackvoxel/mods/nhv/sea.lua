-- The sea round a level: Medusa's island stands in an ocean and the Plane
-- of Fire in a sea of lava, going on past the level's edge (its invisible
-- walls: terrain.lua's bounds) as far as you can see, into the fog.
--
-- The sea is the level's own pool (or lava): the column of nodes built for
-- one of its squares nearest the edge (as made in the prefab editor - the
-- level's hand-built area's, or the usual prefab's), copied over every
-- square for SIZE nodes out on all four sides, column 0 included. In
-- ASCII mode it's '}' in the liquid's colour. Leaving the level, it's
-- cleared (and on starting up, if it was left built: mod storage).

local U = nhv.util
local T = U.TYP
local prefabs = nhv.prefabs
local terrain = nhv.terrain

local sea = {}
nhv.sea = sea

local storage = core.get_mod_storage()

-- the levels and what they stand in
local SEAS = {
	["medusa-1"] = "water", ["medusa-2"] = "water", ["medusa-3"] = "water", ["medusa-4"] = "water",
	["fire"] = "lava",
}
local LIQUID = {water = {[T.POOL] = true, [T.MOAT] = true}, lava = {[T.LAVAPOOL] = true}}
local ASCII_COLOR = {water = 4, lava = 1} -- (CLR_BLUE, CLR_RED)

-- how far out it goes (nodes): past the fog (hud.fog_distance) from the edge
local SIZE = 96

local X1, Z1 = U.COLNO * U.TILE, U.ROWNO * U.TILE -- (the level: 0..X1-1, 0..Z1-1)
local Y0, H = prefabs.Y0, prefabs.H

local function wanted()
	if nhv.EDITOR or not nhv.areas or not nhv.areas.level_variants then
		return nil
	end
	for v in pairs(nhv.areas.level_variants()) do
		if SEAS[v] then
			return SEAS[v], v
		end
	end
end

-- the column of one liquid square nearest the level's edge: {ly = name}
-- per layer, the same all across a square (its middle node's)
local function sample(map, kind)
	local best, best_d
	for tx = 1, U.COLNO - 1 do
		for ty = 0, U.ROWNO - 1 do
			local i = U.idx(tx, ty)
			local sq = terrain.built[i]
			if sq and LIQUID[kind][map.typ[i]] then
				local d = math.min(tx - 1, U.COLNO - 1 - tx, ty, U.ROWNO - 1 - ty)
				if not best_d or d < best_d then
					best, best_d = sq, d
				end
			end
		end
	end
	-- (lit like that square)
	sea.lit = best and best.lit or false
	local nodes = best and (best.area_cell and best.area_cell.nodes or prefabs.get(best.slot).nodes)
	local col = {}
	if nodes then
		for ly = 0, H - 1 do
			local nd = nodes[prefabs.index(1, ly, 1)]
			if nd and nd.n ~= "nhv:carve" and core.registered_nodes[nd.n] then
				col[ly] = nd.n
			end
		end
	end
	if not next(col) then
		-- (none built: the liquid on rock)
		for ly = 0, prefabs.FLOOR - 1 do
			col[ly] = "nhv:rock"
		end
		col[prefabs.FLOOR] = kind == "lava" and "nhv:lava" or "nhv:water"
	end
	-- (open to the sky: no ceiling, however the square was built)
	if terrain.open_sky then
		for ly = prefabs.CEIL, H - 1 do
			col[ly] = nil
		end
	end
	return col
end

local function ascii_column(kind)
	local col = {}
	for ly = 0, prefabs.FLOOR - 1 do
		col[ly] = nhv.ascii.block(32)
	end
	col[prefabs.FLOOR] = nhv.ascii.block(125, ASCII_COLOR[kind])
	return col
end

-- How bright the sea is: lit evenly, as it's written (working out the light
-- of a whole sea from its lights - lava glows - would hold everything up)
local LIGHT = {lava = 12, lit = 13, dark = 2}

-- every node from the level's edge out to SIZE: col's (nil: air), in four
-- strips round the level (north, south, west - with column 0 - and east),
-- one after another; gen: given up if another fill starts meanwhile (it
-- writes all of it again)
local gen = 0
-- (the highest layer the sea written last had: clearing it, no higher -
-- the cells are tall, the sea isn't; not known, all of them)
local written_top = tonumber(storage:get_string("sea_top")) or H - 1
local function fill(col, light)
	gen = gen + 1
	local my_gen = gen
	local top = -1
	for ly in pairs(col or {}) do
		top = math.max(top, ly)
	end
	local layers = math.max(top, written_top, prefabs.FLOOR)
	written_top = top
	storage:set_string("sea_top", tostring(top))
	-- (lit a little over its top too: what's over a face lights it)
	local y0, y1 = Y0, Y0 + math.min(H - 1, layers + 2)
	local strips = {
		{-SIZE, X1 - 1 + SIZE, -SIZE, -1}, {-SIZE, X1 - 1 + SIZE, Z1, Z1 - 1 + SIZE},
		{-SIZE, U.TILE - 1, 0, Z1 - 1}, {X1, X1 - 1 + SIZE, 0, Z1 - 1},
	}
	local function strip(k)
		local s = strips[k]
		if not s or my_gen ~= gen then
			return
		end
		local x0, x1, z0, z1 = s[1], s[2], s[3], s[4]
		local p0, p1 = vector.new(x0, y0, z0), vector.new(x1, y1, z1)
		core.emerge_area(p0, p1, function(_, _, left)
			if left > 0 or my_gen ~= gen then
				return
			end
			local vm = core.get_voxel_manip()
			local emin, emax = vm:read_from_map(p0, p1)
			local area = VoxelArea(emin, emax)
			local ids, p2 = vm:get_data(), vm:get_param2_data()
			local air, bounds = terrain.cid("air"), terrain.cid("nhv:bounds")
			for ly = 0, y1 - y0 do
				local id = col and col[ly] and terrain.cid(col[ly]) or air
				-- (the level's invisible walls, one node out, stay where the sea
				-- has nothing - over the liquid: it goes on under them)
				local edge = id == air and bounds or id
				local y = y0 + ly
				for z = z0, z1 do
					local inz = z >= 0 and z < Z1
					local zedge = z == -1 or z == Z1
					local vi = area:index(x0, y, z)
					for x = x0, x1 do
						-- (outside the level, and its column 0)
						if not inz or x < 0 or x >= X1 or (col and x < U.TILE) then
							local ring = x >= -1 and x <= X1 and z >= -1 and z <= Z1
								and (zedge or x == -1 or x == X1)
							ids[vi], p2[vi] = ring and edge or id, 0
						end
						vi = vi + 1
					end
				end
			end
			vm:set_data(ids)
			vm:set_param2_data(p2)
			-- (column 0 is the level's: its light comes from the level)
			local lx1 = k == 3 and -1 or x1
			vm:set_lighting({day = light, night = light}, p0, vector.new(lx1, y1, z1))
			vm:write_to_map(false)
			strip(k + 1)
		end)
	end
	strip(1)
end

local built = storage:get_string("sea") -- (what's there now: "" none)
local pending = nil -- {col=, light=}: to fill as soon as the level's on screen

-- The level's built again (a new one, or starting up): the sea is put
-- back too, whatever's there
local current = nil -- the column the level's sea is made of (nil: none)

-- the sea's column, on a level that stands in one: the rock round a special
-- level's map is built of it too (terrain.lua's write_outer)
function sea.column()
	return current
end

function sea.rebuild()
	current = nil
	if built ~= "" then
		built = "?" .. built
	end
end

-- Called after the terrain updates (terrain.lua): the sea as the level
-- wants it, built (or cleared) when that changes.
function sea.update(map)
	local kind, level = wanted()
	local key = kind and ("%s/%s/%s"):format(level, kind, nhv.ascii and nhv.ascii.on and "ascii" or "")
		or ""
	if key == built then
		return
	end
	built = key
	storage:set_string("sea", key)
	local col = kind and (nhv.ascii and nhv.ascii.on and ascii_column(kind) or sample(map, kind))
	-- (the squares round the level's map: the sea comes up to the island)
	if col ~= current then
		current = col
		terrain.rewrite_outer()
	end
	local light = not kind and 0 or kind == "lava" and LIGHT.lava
		or (sea.lit or (nhv.ascii and nhv.ascii.on)) and LIGHT.lit or LIGHT.dark
	-- (once the level is on the screen: it doesn't hold that up)
	pending = {col = col, light = light}
end

core.register_globalstep(function()
	if pending and not nhv.player.level_hold
			and (not core.nh_level_progress or core.nh_level_progress() >= 1) then
		local p = pending
		pending = nil
		fill(p.col, p.light)
	end
end)

return sea
