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
-- walls: one per NetHack wall set, with seamless textures made from its
-- sprite (tools/make_wall_textures.py; nhv_tiles/textures/nhv_wall_*.png)
terrain.WALL_STYLES = {"main", "mines", "gehennom", "knox", "sokoban"}
reg("wall", {description = "Wall", tiles = {"nhv_wall_main.png"}, paramtype = "none"})
for _, style in ipairs(terrain.WALL_STYLES) do
	if style ~= "main" then
		reg("wall_" .. style, {description = "Wall (" .. style .. ")",
			tiles = {"nhv_wall_" .. style .. ".png"}, paramtype = "none"})
	end
end
reg("ceiling", {description = "Ceiling", tiles = {tile_tex(1272) .. "^[multiply:#606060"},
	paramtype = "none"})
-- one 48x48 picture over the whole 3x3 doorway (nhv_tiles/textures/nhv_wall_door.png)
reg("door_closed", {description = "Closed door",
	tiles = {{name = "nhv_wall_door.png", align_style = "world", scale = U.TILE}}})

-- floors (the NetHack tile on each node's top face, so 3x3 per square)
local function floor_node(name, desc, top)
	reg(name, {description = desc, tiles = {top, BLACK, BLACK}})
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
-- Flowing water: two frames, the tile and its mirror image, one second each.
local function escape_combine(t)
	return (t:gsub("%^", "\\^"):gsub(":", "\\:"))
end
local function flowing(tex, opacity)
	local frames = ("[combine:16x32:0,0=%s:0,16=%s"):format(
		escape_combine(tex), escape_combine(tex .. "^[transformFX"))
	return {
		name = frames .. "^[opacity:" .. opacity,
		animation = {type = "vertical_frames", aspect_w = 16, aspect_h = 16, length = 2.0},
	}
end
terrain.flowing = flowing

liquid_node("water", "Water", flowing(tile_tex(1314), 200), nil)
liquid_node("lava", "Molten lava", flowing(tile_tex(1316), 255), 10)
liquid_node("void_liquid", "Unexplored", BLACK, nil)
liquid_node("waterwall", "Wall of water", flowing(tile_tex(1324), 180), nil)
reg("lavawall", {description = "Wall of lava", tiles = {flowing(tile_tex(1317), 255)},
	light_source = 8})

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

-- prefabs are built with the main walls; other levels swap in their own
local WALL_NODES = {["nhv:wall"] = true, ["nhv:brick"] = true}
local function styled_cid(name)
	if WALL_NODES[name] and terrain.wall_style ~= "main" then
		name = "nhv:wall_" .. terrain.wall_style
	end
	return cid(name)
end

local function write_square(data, area, sq)
	if not sq.seen then
		write_void(data, area, sq.tx, sq.ty, sq.typ)
		return
	end
	prefabs.write(data, area, sq.tx, sq.ty, sq.slot, sq.rot, true, styled_cid)
	if sq.overlay then
		prefabs.write(data, area, sq.tx, sq.ty, sq.overlay, 0, false, styled_cid)
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
	-- objects (props) placed by the prefabs get their sprites
	nhv.props.refresh(vector.new(minx, y0, minz), vector.new(maxx, y1, maxz))
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

-- The level's wall set (main dungeon, mines, gehennom, knox, sokoban), from
-- the wall sprites NetHack shows for it.
terrain.wall_style = "main"
local function detect_wall_style(map)
	for i, typ in pairs(map.typ) do
		if typ >= 1 and typ <= T.DBWALL and map.flags[i] % 2 == 1 then
			local name = nhv_tiles.name(map.mem_tile[i]) or ""
			local style = name:match("^(%a+) walls ")
			if style then
				return style
			end
		end
	end
	return nil
end

-- ---------------------------------------------------------------- debris
-- squares whose solid part gets destroyed (a door broken, rock or wall dug
-- out, a tree cut down, bars melted) burst into pieces of what was there
local SOLID_SLOTS = {
	stone = true, wall_straight = true, wall_corner = true, wall_tee = true,
	wall_cross = true, tree = true, iron_bars = true,
}
local DOOR_SLOTS = {door_closed = true, door_open = true}

local function destroyed(prev, sq)
	if not (prev and prev.seen and sq.seen) or prev.slot == sq.slot then
		return false
	end
	if DOOR_SLOTS[prev.slot] then
		return sq.slot == "door_broken" or sq.slot == "doorway"
	end
	return SOLID_SLOTS[prev.slot] and not SOLID_SLOTS[sq.slot]
end

-- the most common block in the part of a prefab you'd see (above the floor)
local function main_node(slot)
	local counts, best, bn = {}, nil, 0
	for i, nd in pairs(prefabs.get(slot).nodes) do
		local _, ly = prefabs.unindex(i)
		if ly > prefabs.FLOOR and ly < prefabs.CEIL - 1 and nd.n ~= "air" then
			counts[nd.n] = (counts[nd.n] or 0) + 1
			if counts[nd.n] > bn then
				best, bn = nd.n, counts[nd.n]
			end
		end
	end
	if best and (best == "nhv:wall" or best == "nhv:brick") and terrain.wall_style ~= "main" then
		best = "nhv:wall_" .. terrain.wall_style
	end
	return best
end

local function debris(prev)
	local node = main_node(prev.slot)
	if not node or not core.registered_nodes[node] then
		return
	end
	local ox, oz = U.tile_origin(prev.tx, prev.ty)
	core.add_particlespawner({
		amount = 90, time = 0.12,
		minpos = vector.new(ox - 0.4, U.FLOOR_Y + 0.6, oz - 0.4),
		maxpos = vector.new(ox + U.TILE - 0.6, U.CEIL_Y - 0.6, oz + U.TILE - 0.6),
		minvel = vector.new(-2.5, 0, -2.5), maxvel = vector.new(2.5, 3, 2.5),
		minacc = vector.new(0, -14, 0), maxacc = vector.new(0, -14, 0),
		minexptime = 0.8, maxexptime = 1.8, minsize = 1.2, maxsize = 3,
		collisiondetection = true, node = {name = node},
	})
	if nhv.sound then
		nhv.sound.hook("block_destroyed", {pos = vector.new(ox + 1, U.FLOOR_Y + 2, oz + 1)})
	end
end

function terrain.update(map, force)
	local style = detect_wall_style(map)
	if style and style ~= terrain.wall_style then
		terrain.wall_style = style
		force = true -- redraw what's already built with this level's walls
	end
	local sqs = {}
	for tx = 1, U.COLNO - 1 do
		for ty = 0, U.ROWNO - 1 do
			local i, sq = describe(map, tx, ty)
			local prev = terrain.built[i]
			if force or not prev or prev.key ~= sq.key then
				if not force and destroyed(prev, sq) then
					debris(prev)
				end
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
	nhv.props.clear()
	terrain.wall_style = detect_wall_style(map) or "main"
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

-- Move the hero's light to where the player's head is. It follows the
-- body node by node (not square by square), and smooth lighting blends
-- the steps, so walking into the dark fades instead of jumping.
function terrain.place_hero_light(pos)
	local p = vector.round(vector.new(pos.x, pos.y + 1.5, pos.z))
	local old = terrain.hero_light_pos
	if old and vector.equals(old, p) then
		return
	end
	if core.get_node(p).name ~= "air" then
		p = vector.offset(p, 0, -1, 0) -- head in a low ceiling or a block
	end
	-- light the new spot first, then put out the old one (no dark frame)
	local placed = core.get_node(p).name == "air"
	if placed then
		core.set_node(p, {name = "nhv:hero_light"})
	end
	if old and not vector.equals(old, p) and core.get_node(old).name == "nhv:hero_light" then
		core.set_node(old, {name = "air"})
	end
	terrain.hero_light_pos = placed and p or nil
end

return terrain
