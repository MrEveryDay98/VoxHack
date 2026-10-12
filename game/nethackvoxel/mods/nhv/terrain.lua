-- Terrain: turns NetHack's map into nodes.
--
-- Each map square is a cell built from a prefab (see prefabs.lua) chosen
-- by its terrain type, door state, stairs etc., and rotated to fit (walls
-- and doors). Collision follows the true terrain so you can't walk
-- through walls you haven't seen yet; squares the hero has never seen are
-- drawn as black void.

local U = nhv.util
local T = U.TYP
local prefabs = nhv.prefabs
local terrain = {}
nhv.terrain = terrain

local function tile_tex(n)
	return "[fill:16x16:#000000^(" .. nhv_tiles.texture(n) .. ")"
end

local BLACK = "[fill:16x16:#000000"

local function reg(name, def)
	def.paramtype = def.paramtype or "light"
	def.is_ground_content = false
	def.groups = def.groups or {editor = 1, not_in_creative_inventory = 1}
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
reg("door_closed", {description = "Closed door",
	tiles = {{name = tile_tex(1288), align_style = "world", scale = U.TILE}}})
reg("lavawall", {description = "Wall of lava", tiles = {tile_tex(1317)},
	light_source = 8})

-- floors (top face shows the NetHack tile across the whole square)
local function floor_node(name, desc, top)
	reg(name, {description = desc,
		tiles = {{name = top, align_style = "world", scale = U.TILE}, BLACK, BLACK}})
end
floor_node("void_floor", "Unexplored", BLACK)
floor_node("floor", "Floor", tile_tex(1291))
floor_node("corridor", "Corridor", tile_tex(1294))
floor_node("doorway", "Doorway", tile_tex(1284))
floor_node("stairs_up", "Staircase up", tile_tex(1297))
floor_node("stairs_down", "Staircase down", tile_tex(1298))
floor_node("ladder_up", "Ladder up", tile_tex(1299))
floor_node("ladder_down", "Ladder down", tile_tex(1300))
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
		use_texture_alpha = "blend", walkable = false, pointable = nhv.EDITOR,
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
	light_source = 9, groups = {not_in_creative_inventory = 1},
})

-- content ids, looked up lazily (prefabs may use any registered node)
local cids = {}
local function cid(name)
	local id = cids[name]
	if not id then
		id = core.registered_nodes[name] and core.get_content_id(name)
			or core.get_content_id("air")
		cids[name] = id
	end
	return id
end
terrain.cid = cid

-- ---------------------------------------------------------------- choosing
local STAIR_SLOTS = {
	S_upstair = "stairs_up", S_dnstair = "stairs_down",
	S_upladder = "ladder_up", S_dnladder = "ladder_down",
	S_brupstair = "stairs_up", S_brdnstair = "stairs_down",
	S_brupladder = "ladder_up", S_brdnladder = "ladder_down",
}
local FEATURE_SLOTS = {
	S_altar = "altar", S_fountain = "fountain", S_throne = "throne",
	S_sink = "sink", S_grave = "grave",
}

-- prefab slot drawn for a remembered cmap glyph (features and traps)
function terrain.feature_slot(cmapname)
	if FEATURE_SLOTS[cmapname] then
		return FEATURE_SLOTS[cmapname]
	end
	local trap = "trap_" .. cmapname:gsub("^S_", "")
	if prefabs.SLOT_INFO[trap] then
		return trap
	end
end

-- wall connection sets -> {slot, rotation (quarter turns clockwise)}
local WALLS = {
	[T.VWALL] = {"wall_straight", 0}, [T.HWALL] = {"wall_straight", 1},
	[T.DBWALL] = {"wall_straight", 0},
	[T.TLCORNER] = {"wall_corner", 0}, [T.TRCORNER] = {"wall_corner", 1},
	[T.BRCORNER] = {"wall_corner", 2}, [T.BLCORNER] = {"wall_corner", 3},
	[T.TDWALL] = {"wall_tee", 0}, [T.TLWALL] = {"wall_tee", 1},
	[T.TUWALL] = {"wall_tee", 2}, [T.TRWALL] = {"wall_tee", 3},
	[T.CROSSWALL] = {"wall_cross", 0},
}

local function walllike(map, tx, ty)
	if not U.in_map(tx, ty) then
		return false
	end
	local typ = map.typ[U.idx(tx, ty)]
	return (typ >= 1 and typ <= T.DBWALL) or typ == T.SDOOR or typ == T.DOOR
end

-- doors/drawbridges: 0 if the wall runs east-west (passage north-south)
local function passage_rot(map, tx, ty)
	if walllike(map, tx - 1, ty) or walllike(map, tx + 1, ty) then
		return 0
	end
	return 1
end

local function has_bit(v, b)
	return v % (b * 2) >= b
end

-- slot, rotation for a seen square
local function base_slot(map, i, tx, ty, memcmap)
	local typ = map.typ[i]
	if typ == T.STONE or typ == T.SCORR then
		return "stone", 0
	elseif WALLS[typ] then
		return WALLS[typ][1], WALLS[typ][2]
	elseif typ == T.SDOOR then
		return "wall_straight", passage_rot(map, tx, ty) == 0 and 1 or 0
	elseif typ == T.TREE then
		return "tree", 0
	elseif typ == T.IRONBARS then
		return "iron_bars", 0
	elseif typ == T.LAVAWALL then
		return "lava_wall", 0
	elseif typ == T.POOL or typ == T.MOAT or typ == T.DRAWBRIDGE_UP then
		return "pool", 0
	elseif typ == T.WATER then
		return "water", 0
	elseif typ == T.LAVAPOOL then
		return "lava", 0
	elseif typ == T.ICE then
		return "ice", 0
	elseif typ == T.DRAWBRIDGE_DOWN then
		return "drawbridge_down", passage_rot(map, tx, ty)
	elseif typ == T.AIR then
		return "air", 0
	elseif typ == T.CLOUD then
		return "cloud", 0
	elseif typ == T.DOOR then
		local d = map.door[i]
		local slot
		if has_bit(d, U.D_BROKEN) then
			slot = "door_broken"
		elseif has_bit(d, U.D_ISOPEN) then
			slot = "door_open"
		elseif has_bit(d, U.D_CLOSED) or has_bit(d, U.D_LOCKED) then
			slot = "door_closed"
		else
			slot = "doorway"
		end
		return slot, passage_rot(map, tx, ty)
	elseif typ == T.CORR then
		return "corridor", 0
	elseif (typ == T.STAIRS or typ == T.LADDER) and STAIR_SLOTS[memcmap] then
		return STAIR_SLOTS[memcmap], 0
	elseif FEATURE_SLOTS[memcmap] then
		return FEATURE_SLOTS[memcmap], 0
	elseif typ == T.FOUNTAIN then
		return "fountain", 0
	elseif typ == T.THRONE then
		return "throne", 0
	elseif typ == T.SINK then
		return "sink", 0
	elseif typ == T.GRAVE then
		return "grave", 0
	elseif typ == T.ALTAR then
		return "altar", 0
	end
	return "floor", 0
end

local function open_typ(typ)
	return typ >= T.POOL and typ ~= T.IRONBARS and typ ~= T.LAVAWALL
end

-- ---------------------------------------------------------------- writing
-- unseen square: black, solid where the real terrain is solid
local function write_void(data, area, tx, ty, typ)
	local ox, oz = U.tile_origin(tx, ty)
	local rock, void = cid("nhv:rock"), cid("nhv:void")
	local liquid = typ >= T.POOL and typ <= T.LAVAPOOL and typ ~= T.IRONBARS
		and typ ~= T.LAVAWALL and typ ~= T.DOOR
	local walk = open_typ(typ)
	for ly = 0, prefabs.H - 1 do
		local id
		if ly < prefabs.FLOOR or ly > prefabs.CEIL then
			id = rock
		elseif ly == prefabs.FLOOR then
			id = liquid and cid("nhv:void_liquid") or (walk and cid("nhv:void_floor") or void)
		elseif ly == prefabs.CEIL then
			id = void
		else
			id = walk and cid("air") or void
		end
		for lx = 0, U.TILE - 1 do
			for lz = 0, U.TILE - 1 do
				local vi = area:index(ox + lx, prefabs.Y0 + ly, oz + lz)
				data.ids[vi] = id
				data.p2[vi] = 0
			end
		end
	end
end

local function write_square(data, area, sq)
	if not sq.seen then
		write_void(data, area, sq.tx, sq.ty, sq.typ)
		return
	end
	prefabs.write(data, area, sq.tx, sq.ty, sq.slot, sq.rot, true, cid)
	if sq.overlay then
		prefabs.write(data, area, sq.tx, sq.ty, sq.overlay, 0, false, cid)
	end
	if sq.lit and open_typ(sq.typ) then
		local c = U.tile_center(sq.tx, sq.ty, U.CEIL_Y - 1)
		local vi = area:index(c.x, c.y, c.z)
		if data.ids[vi] == cid("air") then
			data.ids[vi] = cid("nhv:room_light")
		end
	end
end

local function write_squares(sqs)
	if #sqs == 0 then
		return
	end
	local minx, minz, maxx, maxz = math.huge, math.huge, -math.huge, -math.huge
	for _, sq in ipairs(sqs) do
		local ox, oz = U.tile_origin(sq.tx, sq.ty)
		minx, minz = math.min(minx, ox), math.min(minz, oz)
		maxx, maxz = math.max(maxx, ox + U.TILE - 1), math.max(maxz, oz + U.TILE - 1)
	end
	local y0, y1 = prefabs.Y0, prefabs.Y0 + prefabs.H - 1
	local vm = core.get_voxel_manip()
	local emin, emax = vm:read_from_map(vector.new(minx, y0, minz), vector.new(maxx, y1, maxz))
	local area = VoxelArea(emin, emax)
	local data = {ids = vm:get_data(), p2 = vm:get_param2_data()}
	for _, sq in ipairs(sqs) do
		write_square(data, area, sq)
	end
	vm:set_data(data.ids)
	vm:set_param2_data(data.p2)
	vm:write_to_map(true)
end

-- ---------------------------------------------------------------- updating
terrain.built = {}

local function memcmap_of(map, i)
	local gi = nhv.glyph_info(map.mem[i])
	if gi.kind == "cmap" then
		return nhv.cmap_name(gi.index)
	end
	return nil
end

local function describe(map, tx, ty)
	local i = U.idx(tx, ty)
	local memcmap = memcmap_of(map, i)
	local prev = terrain.built[i]
	if not memcmap and prev and prev.memcmap and map.typ[i] == prev.typ then
		memcmap = prev.memcmap -- an object lying on the stairs etc.
	end
	local seen = map.flags[i] % 2 == 1
	local lit = seen and has_bit(map.flags[i], U.LOC_LIT)
	local sq = {tx = tx, ty = ty, typ = map.typ[i], seen = seen, lit = lit, memcmap = memcmap}
	if seen then
		sq.slot, sq.rot = base_slot(map, i, tx, ty, memcmap)
		local fs = memcmap and terrain.feature_slot(memcmap)
		if fs and prefabs.SLOT_INFO[fs].kind == "overlay" then
			sq.overlay = fs
		end
	end
	sq.key = table.concat({sq.typ, seen and 1 or 0, lit and 1 or 0, sq.slot or "",
		sq.rot or 0, sq.overlay or ""}, ":")
	return i, sq
end

function terrain.update(map, force)
	local sqs = {}
	for tx = 1, U.COLNO - 1 do
		for ty = 0, U.ROWNO - 1 do
			local i, sq = describe(map, tx, ty)
			local prev = terrain.built[i]
			if force or not prev or prev.key ~= sq.key then
				terrain.built[i] = sq
				sqs[#sqs + 1] = sq
			end
		end
	end
	write_squares(sqs)
	return #sqs
end

-- Rebuild everything (level change, or prefabs changed).
function terrain.build_all(map)
	terrain.built = {}
	terrain.hero_light_pos = nil
	terrain.update(map, true)
	-- column 0 is never part of the map; fill it with rock
	local sqs = {}
	for ty = 0, U.ROWNO - 1 do
		sqs[#sqs + 1] = {tx = 0, ty = ty, seen = true, slot = "stone", rot = 0, typ = T.STONE}
	end
	write_squares(sqs)
end

-- slot built at a square (or nil)
function terrain.slot_at(tx, ty)
	local sq = terrain.built[U.idx(tx, ty)]
	return sq and sq.slot, sq and sq.rot
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
		if has_bit(door, U.D_CLOSED) or has_bit(door, U.D_LOCKED) then
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
	local p = vector.round(U.tile_center(tx, ty, U.FLOOR_Y + 3))
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
