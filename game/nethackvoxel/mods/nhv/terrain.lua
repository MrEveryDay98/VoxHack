-- Terrain: turns NetHack's map into nodes.
--
-- Each map square is a cell built from a prefab (see prefabs.lua) chosen
-- by its terrain type, door state, stairs etc., and rotated to fit (walls
-- and doors).
--
-- The whole level is built from what's really there, seen or not: there
-- is no fog of war on the world. Darkness hides it instead: lit rooms
-- glow (NetHack's lit flags), dark rooms and corridors are black but for
-- the light you carry, so a dark corridor comes out of the dark as you
-- walk instead of popping in square by square. Secret doors and
-- corridors are built as the wall / rock they look like until found;
-- traps and objects still only show once NetHack lets you see them (but
-- Sokoban's pits and holes, open from the start, are built whether seen or
-- not - behind boulders too; a pit trap elsewhere opens as you step on it),
-- and the overhead map still shows only what you've explored.

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

-- a corner gap (see carve_corners) while you can't squeeze through one:
-- invisible, but solid
reg("squeeze_block", {description = "Tight gap", drawtype = "airlike", walkable = true,
	pointable = false, sunlight_propagates = true, buildable_to = false})

-- the level's safety wall: an invisible box all round the level (its four
-- sides, over the top and under the bottom) that nothing can go through,
-- so you can never leave the level however you get past its own walls
reg("bounds", {description = "Edge of the level", drawtype = "airlike", walkable = true,
	pointable = false, diggable = false, sunlight_propagates = true, buildable_to = false,
	groups = {not_in_creative_inventory = 1}})

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
-- drawn by doors.lua: one picture stretched over each group of door blocks
reg("door_closed", {description = "Closed door", tiles = {"nhv_wall_door.png"}})

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

-- invisible light carried with the hero: just enough to see the squares
-- next to you, as in NetHack in the dark - brighter with a lit lamp or
-- candles (nhv:hero_light_<level>, see light_level)
reg("hero_light", {
	description = "Light", drawtype = "airlike", walkable = false,
	pointable = false, buildable_to = true, sunlight_propagates = true,
	light_source = 9, groups = {not_in_creative_inventory = 1, nhv_hero_light = 1},
})
for level = 10, 14 do
	reg("hero_light_" .. level, {
		description = "Light", drawtype = "airlike", walkable = false,
		pointable = false, buildable_to = true, sunlight_propagates = true,
		light_source = level, groups = {not_in_creative_inventory = 1, nhv_hero_light = 1},
	})
end
-- other light sources NetHack has on the level (a lamp on the floor, a
-- monster carrying one, one that glows): a light in their square
for level = 4, 14 do
	reg("ls_light_" .. level, {
		description = "Light", drawtype = "airlike", walkable = false,
		pointable = false, buildable_to = true, sunlight_propagates = true,
		light_source = level, groups = {not_in_creative_inventory = 1, nhv_ls_light = 1},
	})
end

-- how bright a light NetHack says reaches `range` squares is: light falls
-- off a level a node and a square is 3 nodes (a candle, 2 squares: 11; a
-- lamp, 3: 14)
local function light_level(range)
	return math.max(4, math.min(14, 5 + 3 * range))
end

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

-- Iron bars run along their line, as a wall does (the prefab's bars run
-- east-west at rotation 0, as a door's panel): along walls or other bars
-- either side; a lone bar across a passage spans it, blocking the way
-- through (walkable)
local walkable
local function bars_rot(map, tx, ty)
	local function solid(x, y)
		return walllike(map, x, y) or (U.in_map(x, y) and map.typ[U.idx(x, y)] == T.IRONBARS)
	end
	if solid(tx - 1, ty) or solid(tx + 1, ty) then
		return 0
	elseif solid(tx, ty - 1) or solid(tx, ty + 1) then
		return 1
	end
	return (walkable(map, tx, ty - 1) or walkable(map, tx, ty + 1)) and 0 or 1
end

-- Stairs and ladders face their way in: a prefab's front (the red block in
-- the prefab editor, north at rotation 0; each quarter turn moves it on
-- clockwise: east, south, west) goes to the side you can walk up to, so a
-- staircase built against a wall can still be climbed. The side that opens
-- most (the square in front, then the two beside it) wins; ties keep north.
local FACING = {{0, -1}, {1, 0}, {0, 1}, {-1, 0}} -- map dx, dy for rot 0..3
function walkable(map, tx, ty) -- (declared above, for bars_rot)
	if not U.in_map(tx, ty) then
		return false
	end
	local typ = map.typ[U.idx(tx, ty)]
	return typ ~= nil and typ >= T.DOOR and typ ~= T.LAVAPOOL and typ ~= T.WATER
		and typ ~= T.POOL and typ ~= T.MOAT
end

local function entrance_rot(map, tx, ty)
	local best, best_score = 0, -1
	for r = 0, 3 do
		local f = FACING[r + 1]
		local score = 0
		if walkable(map, tx + f[1], ty + f[2]) then
			score = 10
			-- (the squares either side of the one in front: facing into
			-- the room rather than along its wall)
			for _, side in ipairs({1, -1}) do
				local sx, sy = f[1] + side * f[2], f[2] - side * f[1]
				if walkable(map, tx + sx, ty + sy) then
					score = score + 1
				end
			end
		end
		if score > best_score then
			best, best_score = r, score
		end
	end
	return best
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
		return "iron_bars", bars_rot(map, tx, ty)
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
		return STAIR_SLOTS[memcmap], entrance_rot(map, tx, ty)
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
-- prefabs are built with the main walls; other levels swap in their own
local WALL_NODES = {["nhv:wall"] = true, ["nhv:brick"] = true}
local function styled_cid(name)
	if WALL_NODES[name] and terrain.wall_style ~= "main" then
		name = "nhv:wall_" .. terrain.wall_style
	end
	return cid(name)
end

-- Squeezing past a corner: NetHack lets you step diagonally between two
-- open squares that touch only at a corner (both squares in between solid),
-- but in 3D they'd meet along a single edge you can't fit through. Such
-- corners get their corner column carved out of both solid squares, which
-- leaves a one-block gap to slip through. Not next to a doorway with a door
-- in it (no diagonal moves through those in NetHack either). While NetHack
-- won't let you squeeze through (carrying over 600, too big, Sokoban) the
-- gap is filled with an invisible solid block instead (set_nosqueeze).
terrain.nosqueeze = false

local function diag_open(map, x, y)
	if not U.in_map(x, y) then
		return false
	end
	local i = U.idx(x, y)
	local typ = map.typ[i]
	if not typ or not open_typ(typ) then
		return false
	end
	-- (a door that isn't missing or broken: no diagonal moves)
	return not (typ == T.DOOR and (map.door[i] or 0) >= 2)
end

local function solid_at(map, x, y)
	if not U.in_map(x, y) then
		return true
	end
	local typ = map.typ[U.idx(x, y)]
	return not typ or not open_typ(typ)
end

local function carve_corners(data, area, sq)
	sq.corner = nil
	local map = terrain.map
	if not map or open_typ(sq.typ) then
		return
	end
	local ox, oz = U.tile_origin(sq.tx, sq.ty)
	local air = cid(terrain.nosqueeze and "nhv:squeeze_block" or "air")
	for _, sx in ipairs({-1, 1}) do
		for _, sy in ipairs({-1, 1}) do
			if diag_open(map, sq.tx + sx, sq.ty) and diag_open(map, sq.tx, sq.ty + sy)
					and solid_at(map, sq.tx + sx, sq.ty + sy) then
				-- (world z runs opposite to map y)
				local lx = sx > 0 and U.TILE - 1 or 0
				local lz = sy < 0 and U.TILE - 1 or 0
				for ly = prefabs.FLOOR + 1, prefabs.CEIL - 1 do
					data.ids[area:index(ox + lx, prefabs.Y0 + ly, oz + lz)] = air
				end
				sq.corner = true
			end
		end
	end
end

-- Levels open to the sky (their ceilings are taken off by hand, in the
-- prefab editor; this list gives them the sky, its fog colour and the ways
-- up built for the open sky): the Big Rooms
-- that can have trees (bigrm-6 has them in its map; the others can place
-- them at random), Juiblex's swamp and Medusa's island.
local OPEN_SKY = {
	["bigrm-1"] = true, ["bigrm-3"] = true, ["bigrm-4"] = true, ["bigrm-6"] = true,
	["bigrm-7"] = true, ["bigrm-8"] = true, ["bigrm-10"] = true,
	["juiblex"] = true,
	["medusa-1"] = true, ["medusa-2"] = true, ["medusa-3"] = true, ["medusa-4"] = true,
}
terrain.open_sky = false

local function level_open_sky()
	if nhv.EDITOR or not nhv.areas or not nhv.areas.level_variants then
		return false
	end
	for v in pairs(nhv.areas.level_variants()) do
		if OPEN_SKY[v] then
			return true
		end
	end
	return false
end

local function write_square(data, area, sq)
	if sq.area_cell then
		-- part of a hand-built area (a special level's fixed part; areas.lua)
		local ox, oz = U.tile_origin(sq.tx, sq.ty)
		prefabs.write_at(data, area, vector.new(ox, prefabs.Y0, oz), sq.area_cell.nodes, 0, true, cid)
	else
		prefabs.write(data, area, sq.tx, sq.ty, sq.slot, sq.rot, true, styled_cid)
		carve_corners(data, area, sq)
	end
	if sq.overlay then
		prefabs.write(data, area, sq.tx, sq.ty, sq.overlay, 0, false, styled_cid)
	end
	-- (the open-sky levels' ceilings aren't taken off here any more: they're
	-- built open in the prefab editor's areas)
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
	-- (the light you carry was in what got rebuilt: it's put back at once,
	-- instead of only when you next move)
	local hl = terrain.hero_light_pos
	if hl and hl.x >= minx and hl.x <= maxx and hl.z >= minz and hl.z <= maxz
			and hl.y >= y0 and hl.y <= y1 then
		terrain.hero_light_pos = nil
	end
	-- objects (props) placed by the prefabs get their sprites
	nhv.props.refresh(vector.new(minx, y0, minz), vector.new(maxx, y1, maxz))
	-- doors: one picture across each group of connected door blocks
	nhv.doors.refresh(vector.new(minx, y0, minz), vector.new(maxx, y1, maxz))
end

-- ---------------------------------------------------------------- sky
-- Does the level have the sky over any part of it? Open-sky levels (see
-- OPEN_SKY) do; so does one with a cell whose ceiling is open - a column
-- with nothing from the ceiling layer up. Not the cells that open it on
-- purpose for something else: traps (holes, trap doors...) and the ways up.
local NO_SKY_SLOT = {stairs_up = true, ladder_up = true, stairs_up_sky = true, ladder_up_sky = true}
local open_cache = setmetatable({}, {__mode = "k"}) -- nodes -> open?

local function nodes_open(nodes)
	local known = open_cache[nodes]
	if known ~= nil then
		return known
	end
	local open = false
	for lx = 0, U.TILE - 1 do
		for lz = 0, U.TILE - 1 do
			local clear = true
			for ly = prefabs.CEIL, prefabs.H - 1 do
				local nd = nodes[prefabs.index(lx, ly, lz)]
				if nd and nd.n ~= "air" and nd.n ~= "nhv:carve" then
					clear = false
					break
				end
			end
			if clear then
				open = true
			end
		end
	end
	open_cache[nodes] = open
	return open
end

local function square_open(sq)
	if not sq.seen and not sq.area_cell then
		return false
	end
	if sq.area_cell then
		return nodes_open(sq.area_cell.nodes)
	end
	local slot = sq.slot
	if not slot or NO_SKY_SLOT[slot] or slot:find("^trap_") then
		return false
	end
	return nodes_open(prefabs.get(slot).nodes)
end

-- ---------------------------------------------------------------- climbing
-- The way up a built cell (stairs...): its nhv:mpath blocks, placed where a
-- body's feet go on each step, each touching the next, up to the trigger.
-- As world feet positions, lowest first, one chain; nil if it has none.
-- (Monsters climb it to reach you up there: sim.lua.)
local path_cache = setmetatable({}, {__mode = "k"}) -- nodes -> {rot -> path}

function terrain.climb_path(tx, ty)
	local sq = U.in_map(tx, ty) and terrain.built[U.idx(tx, ty)]
	if not sq then
		return nil
	end
	local nodes, rot = nil, 0
	if sq.area_cell then
		nodes = sq.area_cell.nodes
	elseif sq.slot then
		nodes, rot = prefabs.get(sq.slot).nodes, sq.rot or 0
	end
	if not nodes then
		return nil
	end
	local byrot = path_cache[nodes]
	if not byrot then
		byrot = {}
		path_cache[nodes] = byrot
	end
	if byrot[rot] == nil then
		local blocks = {}
		for i, nd in pairs(nodes) do
			if nd.n == "nhv:mpath" then
				local lx, ly, lz = prefabs.unindex(i)
				local rx, rz = prefabs.rot_xz(lx, lz, rot)
				blocks[#blocks + 1] = {x = rx, y = ly, z = rz}
			end
		end
		-- (a chain: from the lowest, on to a touching block - the nearest
		-- sideways first, so it doesn't cut a corner past a landing, then
		-- the higher)
		table.sort(blocks, function(a, b) return a.y < b.y end)
		local chain, used = {}, {}
		local cur = blocks[1]
		while cur do
			chain[#chain + 1] = cur
			used[cur] = true
			local nxt, best
			for _, b in ipairs(blocks) do
				if not used[b] and math.abs(b.x - cur.x) <= 1 and math.abs(b.y - cur.y) <= 1
						and math.abs(b.z - cur.z) <= 1 then
					local score = (math.abs(b.x - cur.x) + math.abs(b.z - cur.z)) * 10 - b.y
					if not best or score < best then
						nxt, best = b, score
					end
				end
			end
			cur = nxt
		end
		byrot[rot] = #chain > 0 and chain or false
	end
	local chain = byrot[rot]
	if not chain then
		return nil
	end
	local ox, oz = U.tile_origin(tx, ty)
	local out = {}
	for k, b in ipairs(chain) do
		out[k] = vector.new(ox + b.x, prefabs.Y0 + b.y - 0.5, oz + b.z)
	end
	return out
end

-- is the sky over this level (anywhere)?
function terrain.has_sky()
	if terrain.open_sky then
		return true
	end
	for _, sq in pairs(terrain.built) do
		if sq.tx ~= 0 and square_open(sq) then
			return true
		end
	end
	return false
end

-- ---------------------------------------------------------------- updating
terrain.built = {}

-- you can (or can no longer) squeeze through tight corners: open or fill
-- every corner gap on the level
function terrain.set_nosqueeze(on)
	on = on and true or false
	if on == terrain.nosqueeze then
		return
	end
	terrain.nosqueeze = on
	local sqs = {}
	for _, sq in pairs(terrain.built) do
		if sq.corner then
			sqs[#sqs + 1] = sq
		end
	end
	write_squares(sqs)
end

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
	-- never seen: what's really there (stairs up or down, fountain...;
	-- NetHack leaves traps out of this)
	local back = map.back and map.back[i]
	if not memcmap and not seen and back and back ~= 255 then
		memcmap = nhv.cmap_name(back)
	end
	local lit = has_bit(map.flags[i], U.LOC_LIT)
	local sq = {tx = tx, ty = ty, typ = map.typ[i], seen = seen, lit = lit, memcmap = memcmap,
		cansee = has_bit(map.flags[i], U.LOC_CANSEE)}
	sq.slot, sq.rot = base_slot(map, i, tx, ty, memcmap)
	-- (a way up on a level open to the sky: its own cell, once built)
	if terrain.open_sky and (sq.slot == "stairs_up" or sq.slot == "ladder_up")
			and prefabs.custom(sq.slot .. "_sky") then
		sq.slot = sq.slot .. "_sky"
	end
	local fs = memcmap and terrain.feature_slot(memcmap)
	if fs and prefabs.SLOT_INFO[fs].kind == "overlay" then
		sq.overlay = fs
	end
	-- a trap you know of under objects (NetHack shows the top object there,
	-- not the trap): still built, a pit still a hole
	local trap = map.trap and map.trap[i]
	-- (128 + a symbol: a Sokoban pit or hole not seen yet - its hole in the
	-- ground is there all the same)
	if trap and trap ~= 255 and trap >= 128 then
		trap = trap - 128
	end
	if not sq.overlay and trap and trap ~= 255 then
		local ts = terrain.feature_slot(nhv.cmap_name(trap))
		if ts and prefabs.SLOT_INFO[ts].kind == "overlay" then
			sq.overlay = ts
		end
	end
	-- a special level's hand-built area covers it? (areas.lua)
	local cell, cell_id = nhv.areas.cell(tx, ty, sq.typ, map)
	if cell then
		sq.area_cell = cell
	end
	-- (seeing a square for the first time doesn't change what's built)
	sq.key = table.concat({sq.typ, lit and 1 or 0, sq.slot or "",
		sq.rot or 0, sq.overlay or "", cell_id or ""}, ":")
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
	-- (only where you can see it happen)
	if not (prev and sq.cansee) or prev.slot == sq.slot then
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
	local spawner = {
		amount = 90, time = 0.12,
		minpos = vector.new(ox - 0.4, U.FLOOR_Y + 0.6, oz - 0.4),
		maxpos = vector.new(ox + U.TILE - 0.6, U.CEIL_Y - 0.6, oz + U.TILE - 0.6),
		minvel = vector.new(-2.5, 0, -2.5), maxvel = vector.new(2.5, 3, 2.5),
		minacc = vector.new(0, -14, 0), maxacc = vector.new(0, -14, 0),
		minexptime = 0.8, maxexptime = 1.8, minsize = 1.2, maxsize = 3,
		collisiondetection = true, node = {name = node},
	}
	if nhv.doors and table.indexof(nhv.doors.NODES, node) > 0 then
		-- door blocks are invisible (doors.lua draws the door over them):
		-- splinters of the door's picture instead
		spawner.node = nil
		spawner.amount = 22
		for k = 0, 3 do
			spawner.texture = ("%s^[sheet:4x4:%d,%d"):format(nhv.doors.TEXTURE, k, (k * 3) % 4)
			core.add_particlespawner(table.copy(spawner))
		end
	else
		core.add_particlespawner(spawner)
	end
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
	-- (open to the sky or not: known once NetHack has said which level
	-- this is; it changing redraws everything)
	local open = level_open_sky()
	if open ~= terrain.open_sky then
		terrain.open_sky = open
		force = true
	end
	terrain.map = map
	local sqs, queued = {}, {}
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
				queued[i] = true
			end
		end
	end
	-- (a square that changed can open or close a corner squeeze next to it)
	if not force then
		for k = 1, #sqs do
			local sq = sqs[k]
			for dx = -1, 1 do
				for dy = -1, 1 do
					local x, y = sq.tx + dx, sq.ty + dy
					local j = U.in_map(x, y) and U.idx(x, y)
					if j and not queued[j] and terrain.built[j] then
						queued[j] = true
						sqs[#sqs + 1] = terrain.built[j]
					end
				end
			end
		end
	end
	write_squares(sqs)
	return #sqs
end

-- The safety wall round the whole level (columns 0..COLNO-1 and every
-- row, every layer of the cells): one node outside it on every side.
local function build_bounds()
	local x0, x1 = -1, U.COLNO * U.TILE
	local z0, z1 = -1, U.ROWNO * U.TILE
	local y0, y1 = prefabs.Y0 - 1, prefabs.Y0 + prefabs.H
	local vm = core.get_voxel_manip()
	local emin, emax = vm:read_from_map(vector.new(x0, y0, z0), vector.new(x1, y1, z1))
	local area = VoxelArea(emin, emax)
	local ids = vm:get_data()
	local b = cid("nhv:bounds")
	for z = z0, z1 do
		for y = y0, y1 do
			for x = x0, x1 do
				if x == x0 or x == x1 or z == z0 or z == z1 or y == y0 or y == y1 then
					ids[area:index(x, y, z)] = b
				end
			end
		end
	end
	vm:set_data(ids)
	vm:write_to_map(true)
end

-- The whole level's map blocks stay active, however far you are: the
-- monsters' entities (not saved) would be dropped out of inactive blocks,
-- and the ones you sense from afar (telepathy while blind) must exist.
-- About 160 blocks (16 across, 5 deep, 2 high), held while the game runs
-- (transient: not saved with the world).
core.after(0, function()
	local B = core.MAP_BLOCKSIZE or 16
	for x = -1, U.COLNO * U.TILE, B do
		for z = -1, U.ROWNO * U.TILE, B do
			for y = prefabs.Y0 - 1, prefabs.Y0 + prefabs.H, B do
				core.forceload_block(vector.new(x, y, z), true, -1)
			end
			core.forceload_block(vector.new(x, prefabs.Y0 + prefabs.H, z), true, -1)
		end
		core.forceload_block(vector.new(x, prefabs.Y0, U.ROWNO * U.TILE), true, -1)
	end
end)

-- Rebuild everything (level change, or prefabs changed).
function terrain.build_all(map)
	terrain.built = {}
	nhv.props.clear()
	nhv.doors.clear()
	terrain.wall_style = detect_wall_style(map) or "main"
	terrain.hero_light_pos = nil
	terrain.update(map, true)
	-- column 0 is never part of the map; fill it with rock
	local sqs = {}
	for ty = 0, U.ROWNO - 1 do
		sqs[#sqs + 1] = {tx = 0, ty = ty, seen = true, slot = "stone", rot = 0, typ = T.STONE}
	end
	write_squares(sqs)
	build_bounds()
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
-- the light you carry: what NetHack says lights you up (lamps, candles,
-- glowing), else the dim light to see the squares next to you
terrain.hero_light_node = "nhv:hero_light"
local function is_hero_light(name)
	local def = core.registered_nodes[name]
	return def and def.groups and def.groups.nhv_hero_light
end

function terrain.place_hero_light(pos)
	local p = vector.round(vector.new(pos.x, pos.y + 1.5, pos.z))
	local old = terrain.hero_light_pos
	local want = terrain.hero_light_node
	if old and vector.equals(old, p) and core.get_node(old).name == want then
		return
	end
	local here = core.get_node(p).name
	if here ~= "air" and not is_hero_light(here) then
		p = vector.offset(p, 0, -1, 0) -- head in a low ceiling or a block
	end
	-- light the new spot first, then put out the old one (no dark frame)
	local n = core.get_node(p).name
	local placed = n == "air" or is_hero_light(n)
	if placed then
		core.set_node(p, {name = want})
	end
	if old and not vector.equals(old, p) and is_hero_light(core.get_node(old).name) then
		core.set_node(old, {name = "air"})
	end
	terrain.hero_light_pos = placed and p or nil
end

-- NetHack's light sources: the brightest at the hero sets the light you
-- carry; the rest each light their own square (in the air at head height)
local ls_placed = {} -- "x,y,z" -> pos
function terrain.update_lights()
	local lights = core.nh_get_lights and core.nh_get_lights() or {}
	local carried = 0
	local want = {}
	for _, l in ipairs(lights) do
		if l.at_hero then
			carried = math.max(carried, l.range)
		elseif U.in_map(l.x, l.y) then
			local p = vector.round(U.tile_center(l.x, l.y, U.STAND_Y + 1.5))
			local k = p.x .. "," .. p.y .. "," .. p.z
			local level = light_level(l.range)
			if not want[k] or want[k].level < level then
				want[k] = {pos = p, level = level}
			end
		end
	end
	local level = carried > 0 and math.max(9, light_level(carried)) or 9
	terrain.hero_light_node = level > 9 and ("nhv:hero_light_" .. level) or "nhv:hero_light"
	for k, p in pairs(ls_placed) do
		local w = want[k]
		local n = core.get_node(p).name
		if not w and n:sub(1, 13) == "nhv:ls_light_" then
			core.set_node(p, {name = "air"})
		end
		if not w then
			ls_placed[k] = nil
		end
	end
	for k, w in pairs(want) do
		local name = "nhv:ls_light_" .. w.level
		local n = core.get_node(w.pos).name
		if n == "air" or (n ~= name and n:sub(1, 13) == "nhv:ls_light_") then
			core.set_node(w.pos, {name = name})
			ls_placed[k] = w.pos
		elseif n == name then
			ls_placed[k] = w.pos
		end
	end
end

-- Where something standing on square (tx, ty) rests: the floor, or the
-- bottom of a pit (or any hole) where there's no floor under its middle.
function terrain.stand_y(tx, ty)
	local c = U.tile_center(tx, ty)
	local function solid(y)
		local def = core.registered_nodes[core.get_node(vector.new(c.x, y, c.z)).name]
		return def and def.walkable
	end
	if solid(U.FLOOR_Y) then
		return U.STAND_Y
	end
	for y = U.FLOOR_Y - 1, prefabs.Y0, -1 do
		if solid(y) then
			return y + 0.5
		end
	end
	return U.STAND_Y
end

-- (the prefab editor's area plates are laid out the way the game would)
terrain.base_slot = base_slot

return terrain
