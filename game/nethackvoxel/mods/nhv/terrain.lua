-- Terrain: turns NetHack's map into nodes.
--
-- Collision follows the true terrain (levl[][].typ) so you can't walk
-- through walls you haven't seen yet; appearance follows what the hero
-- has seen: squares never seen are drawn as black void.
--
-- Each map square is a TILE x TILE column of nodes from y = FLOOR_Y - 1
-- (bedrock) to CEIL_Y (ceiling).

local U = nhv.util
local T = U.TYP
local terrain = {}
nhv.terrain = terrain

local function tile_tex(n)
	return "[fill:16x16:#000000^" .. nhv_tiles.texture(n)
end

local BLACK = "[fill:16x16:#000000"

local function reg(name, def)
	def.paramtype = def.paramtype or "light"
	def.is_ground_content = false
	def.diggable = false
	def.groups = def.groups or {not_in_creative_inventory = 1}
	def.drop = ""
	def.on_blast = function() end
	core.register_node("nhv:" .. name, def)
end

-- solid, opaque
reg("void", {description = "Unexplored", tiles = {BLACK}, paramtype = "none"})
reg("rock", {description = "Stone", tiles = {tile_tex(1272)}, paramtype = "none"})
reg("wall", {description = "Wall", tiles = {tile_tex(1274)}, paramtype = "none"})
reg("ceiling", {description = "Ceiling", tiles = {{name = tile_tex(1272) .. "^[multiply:#606060",
	align_style = "world", scale = U.TILE}}, paramtype = "none"})
reg("ceiling_lit", {description = "Ceiling", tiles = {{name = tile_tex(1272) .. "^[multiply:#909090",
	align_style = "world", scale = U.TILE}}, light_source = core.LIGHT_MAX})
reg("door_closed", {description = "Closed door",
	tiles = {{name = tile_tex(1288), align_style = "world", scale = U.TILE}}})
reg("lavawall", {description = "Wall of lava", tiles = {tile_tex(1317)},
	light_source = 8})

-- floors (top face shows the NetHack tile, sides are plain)
local function floor_node(name, desc, top, extra)
	-- the top texture spans the whole square (TILE x TILE nodes)
	local def = {description = desc,
		tiles = {{name = top, align_style = "world", scale = U.TILE}, BLACK, BLACK}}
	for k, v in pairs(extra or {}) do
		def[k] = v
	end
	reg(name, def)
end
floor_node("void_floor", "Unexplored", BLACK)
floor_node("floor", "Floor", tile_tex(1291))
floor_node("corridor", "Corridor", tile_tex(1294))
floor_node("doorway", "Doorway", tile_tex(1284))
floor_node("stairs_up", "Staircase up", tile_tex(1297))
floor_node("stairs_down", "Staircase down", tile_tex(1298))
floor_node("ladder_up", "Ladder up", tile_tex(1299))
floor_node("ladder_down", "Ladder down", tile_tex(1300))
floor_node("brstairs_up", "Branch staircase up", tile_tex(1301))
floor_node("brstairs_down", "Branch staircase down", tile_tex(1302))
floor_node("ice", "Ice", tile_tex(1315))
floor_node("drawbridge", "Lowered drawbridge", tile_tex(1319))
floor_node("air_floor", "Air", tile_tex(1322))

-- see-through solids
reg("tree", {description = "Tree", drawtype = "allfaces", tiles = {nhv_tiles.texture(1290)},
	use_texture_alpha = "clip", sunlight_propagates = true})
reg("bars", {description = "Iron bars", drawtype = "allfaces", tiles = {nhv_tiles.texture(1289)},
	use_texture_alpha = "clip", sunlight_propagates = true})

-- liquids: not walkable, you sink into them; NetHack decides what happens
local function liquid_node(name, desc, tex, light)
	reg(name, {
		description = desc, drawtype = "glasslike", tiles = {tex},
		use_texture_alpha = "blend", walkable = false, pointable = false,
		light_source = light, post_effect_color = {a = 120, r = 20, g = 40, b = 120},
	})
end
liquid_node("water", "Water", tile_tex(1314) .. "^[opacity:200", nil)
liquid_node("lava", "Molten lava", tile_tex(1316), 10)
liquid_node("void_liquid", "Unexplored", BLACK, nil)
liquid_node("waterwall", "Wall of water", tile_tex(1324) .. "^[opacity:180", nil)

-- invisible light carried with the hero
reg("hero_light", {
	description = "Light", drawtype = "airlike", walkable = false,
	pointable = false, buildable_to = true, sunlight_propagates = true,
	light_source = 9,
})

local C = {}
for _, n in ipairs({"void", "rock", "wall", "ceiling", "ceiling_lit", "door_closed",
		"lavawall", "void_floor", "floor", "corridor", "doorway", "stairs_up",
		"stairs_down", "ladder_up", "ladder_down", "brstairs_up", "brstairs_down",
		"ice", "drawbridge", "air_floor", "tree", "bars", "water", "lava",
		"void_liquid", "waterwall", "hero_light"}) do
	C[n] = core.get_content_id("nhv:" .. n)
end
local C_AIR = core.get_content_id("air")
C.air = C_AIR
terrain.cid = C

-- cmap names of remembered glyphs that decide the floor texture
local STAIR_NODES = {
	S_upstair = "stairs_up", S_dnstair = "stairs_down",
	S_upladder = "ladder_up", S_dnladder = "ladder_down",
	S_brupstair = "brstairs_up", S_brdnstair = "brstairs_down",
	S_brupladder = "ladder_up", S_brdnladder = "ladder_down",
}

-- Column of node ids for one square, from y = FLOOR_Y - 1 up to CEIL_Y.
-- Returns the list and a cache key describing it.
local function column_for(typ, seen, door, lit, memcmap)
	local col = {}
	local n = U.CEIL_Y - U.FLOOR_Y + 2
	local ceiling = (lit and seen) and C.ceiling_lit or C.ceiling
	local function fill(id)
		for i = 1, n do
			col[i] = id
		end
	end
	-- index: 1 = bedrock, 2 = floor, 3..n-1 = open space, n = ceiling
	local function room(floor_id, mid_id)
		col[1] = C.rock
		col[2] = floor_id
		for i = 3, n - 1 do
			col[i] = mid_id or C_AIR
		end
		col[n] = seen and ceiling or C.void
	end

	if typ == T.STONE or typ == T.SCORR then
		fill(C.rock)
	elseif typ <= T.DBWALL or typ == T.SDOOR then
		fill(seen and C.wall or C.void)
		col[1] = C.rock
	elseif typ == T.TREE then
		room(seen and C.floor or C.void_floor, seen and C.tree or C.void)
	elseif typ == T.IRONBARS then
		room(seen and C.floor or C.void_floor, seen and C.bars or C.void)
	elseif typ == T.LAVAWALL then
		fill(seen and C.lavawall or C.void)
	elseif typ == T.POOL or typ == T.MOAT or typ == T.DRAWBRIDGE_UP then
		room(seen and C.water or C.void_liquid)
	elseif typ == T.WATER then
		room(seen and C.waterwall or C.void_liquid, seen and C.waterwall or C.void_liquid)
	elseif typ == T.LAVAPOOL then
		room(seen and C.lava or C.void_liquid)
	elseif typ == T.DOOR then
		local closed = door % (U.D_CLOSED * 2) >= U.D_CLOSED
			or door % (U.D_LOCKED * 2) >= U.D_LOCKED
		room(seen and C.doorway or C.void_floor)
		for i = 3, n - 1 do
			col[i] = closed and (seen and C.door_closed or C.void) or C_AIR
		end
		col[n - 1] = seen and C.wall or C.void -- lintel
	else
		local floor
		if not seen then
			floor = C.void_floor
		elseif typ == T.CORR then
			floor = C.corridor
		elseif typ == T.ICE then
			floor = C.ice
		elseif typ == T.DRAWBRIDGE_DOWN then
			floor = C.drawbridge
		elseif typ == T.AIR or typ == T.CLOUD then
			floor = C.air_floor
		elseif (typ == T.STAIRS or typ == T.LADDER) and STAIR_NODES[memcmap] then
			floor = C[STAIR_NODES[memcmap]]
		else
			floor = C.floor
		end
		room(floor)
	end
	return col
end

-- per-square cache of what was last built
terrain.built = {}

local function square_key(map, i, memcmap)
	local seen = map.flags[i] % 2 == 1
	local lit = map.flags[i] % (U.LOC_LIT * 2) >= U.LOC_LIT
	return map.typ[i] .. ":" .. (seen and 1 or 0) .. ":" .. map.door[i] .. ":"
		.. (lit and 1 or 0) .. ":" .. (memcmap or ""), seen, lit
end

local function memcmap_of(map, i)
	local mg = map.mem[i]
	local gi = nhv.glyph_info(mg)
	if gi.kind == "cmap" then
		return nhv.cmap_name(gi.index)
	end
	-- an object on top hides the terrain glyph; keep stairs visible by
	-- remembering what we drew before
	return nil
end

-- Write a set of squares {tx, ty, col} using one VoxelManip.
local function write_columns(cols)
	if #cols == 0 then
		return
	end
	local minx, minz, maxx, maxz = math.huge, math.huge, -math.huge, -math.huge
	for _, c in ipairs(cols) do
		local ox, oz = U.tile_origin(c.tx, c.ty)
		minx = math.min(minx, ox)
		minz = math.min(minz, oz)
		maxx = math.max(maxx, ox + U.TILE - 1)
		maxz = math.max(maxz, oz + U.TILE - 1)
	end
	local y0, y1 = U.FLOOR_Y - 1, U.CEIL_Y
	local vm = core.get_voxel_manip()
	local emin, emax = vm:read_from_map(vector.new(minx, y0, minz), vector.new(maxx, y1, maxz))
	local area = VoxelArea(emin, emax)
	local data = vm:get_data()
	for _, c in ipairs(cols) do
		local ox, oz = U.tile_origin(c.tx, c.ty)
		for dx = 0, U.TILE - 1 do
			for dz = 0, U.TILE - 1 do
				for k, id in ipairs(c.col) do
					data[area:index(ox + dx, y0 + k - 1, oz + dz)] = id
				end
			end
		end
	end
	vm:set_data(data)
	vm:write_to_map(true)
end

-- Rebuild everything (level change).
function terrain.build_all(map)
	terrain.built = {}
	terrain.hero_light_pos = nil
	terrain.update(map, true)
	-- column 0 is never part of the map; wall it off
	local cols = {}
	for ty = 0, U.ROWNO - 1 do
		local col = {}
		for k = 1, U.CEIL_Y - U.FLOOR_Y + 2 do
			col[k] = C.rock
		end
		cols[#cols + 1] = {tx = 0, ty = ty, col = col}
	end
	write_columns(cols)
end

-- Rebuild squares whose state changed since the last call.
function terrain.update(map, force)
	local cols = {}
	for tx = 1, U.COLNO - 1 do
		for ty = 0, U.ROWNO - 1 do
			local i = U.idx(tx, ty)
			local memcmap = memcmap_of(map, i)
			local prev = terrain.built[i]
			if not memcmap and prev and prev.memcmap and map.typ[i] == prev.typ then
				memcmap = prev.memcmap -- object lying on the stairs etc.
			end
			local key, seen, lit = square_key(map, i, memcmap)
			if force or not prev or prev.key ~= key then
				terrain.built[i] = {key = key, typ = map.typ[i], memcmap = memcmap}
				cols[#cols + 1] = {
					tx = tx, ty = ty,
					col = column_for(map.typ[i], seen, map.door[i], lit, memcmap),
				}
			end
		end
	end
	write_columns(cols)
	return #cols
end

-- Is the square physically passable (for movement prediction)?
function terrain.passable(map, tx, ty)
	if not U.in_map(tx, ty) then
		return false
	end
	local i = U.idx(tx, ty)
	local typ = map.typ[i]
	if typ < T.POOL or typ == T.IRONBARS or typ == T.LAVAWALL then
		return false
	end
	if typ == T.DOOR then
		local door = map.door[i]
		if door % (U.D_CLOSED * 2) >= U.D_CLOSED or door % (U.D_LOCKED * 2) >= U.D_LOCKED then
			return false
		end
	end
	return true
end

function terrain.is_door(map, tx, ty)
	return U.in_map(tx, ty) and map.typ[U.idx(tx, ty)] == T.DOOR
end

-- Move the hero's light to a square.
function terrain.place_hero_light(tx, ty)
	local p = U.tile_center(tx, ty, U.FLOOR_Y + 3)
	p = vector.round(p)
	local old = terrain.hero_light_pos
	if old and vector.equals(old, p) then
		return
	end
	if old and core.get_node(old).name == "nhv:hero_light" then
		core.set_node(old, {name = "air"})
	end
	if core.get_node(p).name == "air" then
		core.set_node(p, {name = "nhv:hero_light"})
		terrain.hero_light_pos = p
	else
		terrain.hero_light_pos = nil
	end
end

return terrain
