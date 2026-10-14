-- Shared constants and coordinate helpers.
--
-- One NetHack map square ("tile") is TILE x TILE nodes. NetHack's (x, y)
-- has y growing downwards (south); Luanti's +z is north, so rows are
-- flipped to keep the map's orientation.

local U = {}
nhv.util = U

U.TILE = 3
U.COLNO = 80
U.ROWNO = 21
U.FLOOR_Y = -1     -- floor nodes (so open space starts at y = 0 and
                   -- world-aligned textures line up with doors)
U.WALL_H = 4       -- wall height above the floor
U.CEIL_Y = U.FLOOR_Y + U.WALL_H + 1
U.STAND_Y = U.FLOOR_Y + 0.5 -- player feet

-- levl[][].typ values (include/rm.h, NetHack 3.7)
U.TYP = {
	STONE = 0, VWALL = 1, HWALL = 2, TLCORNER = 3, TRCORNER = 4,
	BLCORNER = 5, BRCORNER = 6, CROSSWALL = 7, TUWALL = 8, TDWALL = 9,
	TLWALL = 10, TRWALL = 11, DBWALL = 12, TREE = 13, SDOOR = 14,
	SCORR = 15, POOL = 16, MOAT = 17, WATER = 18, DRAWBRIDGE_UP = 19,
	LAVAPOOL = 20, LAVAWALL = 21, IRONBARS = 22, DOOR = 23, CORR = 24,
	ROOM = 25, STAIRS = 26, LADDER = 27, FOUNTAIN = 28, THRONE = 29,
	SINK = 30, GRAVE = 31, ALTAR = 32, ICE = 33, DRAWBRIDGE_DOWN = 34,
	AIR = 35, CLOUD = 36,
}

-- doormask bits
U.D_BROKEN = 0x01
U.D_ISOPEN = 0x02
U.D_CLOSED = 0x04
U.D_LOCKED = 0x08

-- nhv_loc.flags
U.LOC_SEEN = 0x01
U.LOC_CANSEE = 0x02
U.LOC_LIT = 0x04
U.LOC_WASLIT = 0x08

-- nhv_mon.flags
U.MON_PET = 0x01
U.MON_PEACEFUL = 0x02
U.MON_INVIS = 0x04
U.MON_DETECTED = 0x08
U.MON_WARNING = 0x10
U.MON_SHOPKEEPER = 0x20 -- (in its own shop)

-- nhv_hero.flags
U.HERO = {
	BLIND = 0x0001, HALLU = 0x0002, LEVITATE = 0x0004, FLYING = 0x0008,
	INVIS = 0x0010, STUN = 0x0020, CONF = 0x0040, UNDERWATER = 0x0080,
	SWALLOWED = 0x0100, TRAPPED = 0x0200, POLY = 0x0400, DEAD = 0x0800,
	RIDING = 0x1000, FAST = 0x2000, VFAST = 0x4000, INSHOP = 0x8000,
	INTEMPLE = 0x10000, OWES = 0x20000, -- (owes the shop it's in)
}

-- nhv_obj.flags
U.OBJ = {
	WORN = 0x01, WIELDED = 0x02, QUIVERED = 0x04, CURSED_KNOWN = 0x08,
	BLESSED_KNOWN = 0x10, ALTWEP = 0x20, CONTAINER = 0x40, LIT = 0x80,
}

-- object classes (include/objclass.h)
U.OCLASS = {
	ILLOBJ = 1, WEAPON = 2, ARMOR = 3, RING = 4, AMULET = 5, TOOL = 6,
	FOOD = 7, POTION = 8, SCROLL = 9, SPBOOK = 10, WAND = 11, COIN = 12,
	GEM = 13, ROCK = 14, BALL = 15, CHAIN = 16, VENOM = 17,
}

function U.idx(x, y)
	return x * U.ROWNO + y + 1
end

-- node position of the south-west bottom corner of a tile's column
-- turn a sprite entity to face the nearest player (billboarding)
function U.face_player(obj)
	local pos = obj:get_pos()
	local best, bd
	for _, p in ipairs(core.get_connected_players()) do
		local d = vector.distance(p:get_pos(), pos)
		if not bd or d < bd then
			best, bd = p, d
		end
	end
	if best then
		local d = vector.subtract(best:get_pos(), pos)
		obj:set_yaw(math.atan2(d.z, d.x) - math.pi / 2)
	end
end

function U.tile_origin(tx, ty)
	return tx * U.TILE, (U.ROWNO - 1 - ty) * U.TILE
end

function U.tile_center(tx, ty, y)
	local ox, oz = U.tile_origin(tx, ty)
	local h = (U.TILE - 1) / 2
	return vector.new(ox + h, y or U.STAND_Y, oz + h)
end

-- the tile a world position is in
function U.pos_to_tile(pos)
	local tx = math.floor((pos.x + 0.5) / U.TILE)
	local tz = math.floor((pos.z + 0.5) / U.TILE)
	return tx, U.ROWNO - 1 - tz
end

function U.in_map(tx, ty)
	return tx >= 1 and tx < U.COLNO and ty >= 0 and ty < U.ROWNO
end

-- NetHack movement keys (number_pad off) indexed by dx, dy
U.DIR_KEYS = {
	[-1] = {[-1] = "y", [0] = "h", [1] = "b"},
	[0] = {[-1] = "k", [0] = ".", [1] = "j"},
	[1] = {[-1] = "u", [0] = "l", [1] = "n"},
}

function U.dir_key(dx, dy)
	return U.DIR_KEYS[dx][dy]
end

-- NetHack direction (dx, dy) from a horizontal world vector.
-- World +x = NetHack +x; world +z = NetHack -y.
function U.vec_to_dir(v)
	if math.abs(v.x) < 1e-6 and math.abs(v.z) < 1e-6 then
		return 0, 0
	end
	local ang = math.atan2(-v.z, v.x) -- NetHack frame, y down
	local oct = math.floor(ang / (math.pi / 4) + 0.5) % 8
	local dirs = {
		[0] = {1, 0}, {1, 1}, {0, 1}, {-1, 1},
		{-1, 0}, {-1, -1}, {0, -1}, {1, -1},
	}
	return dirs[oct][1], dirs[oct][2]
end

function U.sign(v)
	return v > 0 and 1 or (v < 0 and -1 or 0)
end

function U.has(flags, bit)
	return flags and (flags % (bit * 2)) >= bit
end

return U
