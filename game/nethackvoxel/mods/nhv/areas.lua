-- Area prefabs: hand-built special levels.
--
-- The parts of special levels that are always the same (Minetown's town,
-- the Oracle's centre, Medusa's island, the Castle, Sokoban, the Astral
-- Plane...) can be built by hand as one piece in the prefab editor
-- (/area). NetHack tells the game which variant each level is and where its
-- fixed regions are; there, the squares you built replace the usual
-- per-square prefabs. The rest of the level (random rooms, mazes, Fort
-- Ludios's maze around the fort...) is built as usual.
--
-- An area is a grid of cells, one per square, like the prefab cells. Only
-- squares you changed in the editor are saved; the others are built from
-- the usual prefabs in the game too. A square also goes back to its usual
-- prefab when the game changes it (a wall dug through, a fountain dried
-- up...): whenever its terrain no longer matches the level's template. Doors,
-- stairs, ladders and drawbridges always use their own prefabs (they open,
-- lead somewhere, move). Traps and feature sprites (fountains, altars...)
-- are drawn on top as everywhere.
--
-- splev_templates.txt (tools/make_splev_templates.py) has every variant's
-- fixed regions with their original terrain; the areas you build are saved
-- in mod_data/nhv/areas/.

local U = nhv.util
local T = U.TYP
local areas = {
	templates = {}, -- id ("minetn-3#1") -> {id, proto, n, x, y, w, h, typ = {}}
	list = {},      -- the templates in order
	data = {},      -- id -> {cells = {[k] = {nodes = ...}}} (loaded on demand)
}
nhv.areas = areas

-- what the variants are called
areas.NAMES = {
	["minetn-1"] = "Minetown: Frontier Town (or Orcish Town)", ["minetn-2"] = "Minetown: Town Square",
	["minetn-3"] = "Minetown: Alley Town", ["minetn-4"] = "Minetown: College Town",
	["minetn-5"] = "Minetown: Grotto", ["minetn-6"] = "Minetown: Bustling Town",
	["minetn-7"] = "Minetown: Bazaar Town", oracle = "The Oracle", castle = "The Castle",
	valley = "Valley of the Dead", sanctum = "Moloch's Sanctum", astral = "Astral Plane",
	earth = "Plane of Earth", fire = "Plane of Fire", knox = "Fort Ludios",
	wizard1 = "Wizard's Tower (bottom)", wizard2 = "Wizard's Tower (middle)",
	wizard3 = "Wizard's Tower (top)", fakewiz1 = "Fake Wizard's Tower 1",
	fakewiz2 = "Fake Wizard's Tower 2", tower1 = "Vlad's Tower (bottom)",
	tower2 = "Vlad's Tower (middle)", tower3 = "Vlad's Tower (top)",
	asmodeus = "Asmodeus's lair", baalz = "Baalzebub's lair", juiblex = "Juiblex's swamp",
	orcus = "Orcus Town",
}
local PREFIX_NAMES = {
	{"^medusa%-(%d+)$", "Medusa's Island %s"}, {"^bigrm%-(%d+)$", "Big Room %s"},
	{"^minend%-(%d+)$", "Mines' End %s"}, {"^soko(%d)%-(%d)$", "Sokoban level %s, version %s"},
	{"^(%a%a%a)%-strt$", "Quest home (%s)"}, {"^(%a%a%a)%-loca$", "Quest locate (%s)"},
	{"^(%a%a%a)%-goal$", "Quest goal (%s)"}, {"^tut%-(%d+)$", "Tutorial %s"},
}

-- The wall set a special level is drawn with in the game (NetHack's wall
-- sprites go by dungeon: the Gnomish Mines, Gehennom, Fort Ludios and
-- Sokoban have their own; Vlad's Tower, the Planes and the rest use the
-- main dungeon's). The prefab editor builds the area plates with it.
local GEHENNOM = {valley = true, sanctum = true, juiblex = true, orcus = true, asmodeus = true,
	baalz = true, wizard1 = true, wizard2 = true, wizard3 = true, fakewiz1 = true, fakewiz2 = true}
function areas.wall_style(t)
	local p = t.proto or ""
	if p:match("^minetn%-") or p:match("^minend%-") then
		return "mines"
	elseif GEHENNOM[p] then
		return "gehennom"
	elseif p == "knox" then
		return "knox"
	elseif p:match("^soko%d") then
		return "sokoban"
	end
	return "main"
end

-- how many fixed regions (parts) the level has; nearly always one
function areas.parts(t)
	local count = 0
	for _, o in ipairs(areas.list) do
		if o.proto == t.proto then
			count = count + 1
		end
	end
	return count
end

-- the id to show: the level's file name, with "#n" only when the level has
-- several parts (the id itself, in file names and storage, keeps it)
function areas.shown_id(t)
	return areas.parts(t) > 1 and t.id or t.proto
end

function areas.name(t)
	local name = areas.NAMES[t.proto]
	if not name then
		for _, p in ipairs(PREFIX_NAMES) do
			local a, b = t.proto:match(p[1])
			if a then
				name = p[2]:format(a, b)
				break
			end
		end
	end
	name = name or t.proto
	-- (levels with several fixed regions: which one)
	return areas.parts(t) > 1 and ("%s, part %d"):format(name, t.n) or name
end

-- ---------------------------------------------------------------- templates
do
	local path = core.get_modpath("nhv") .. DIR_DELIM .. "splev_templates.txt"
	local f = io.open(path, "r")
	if f then
		for line in f:lines() do
			local proto, n, x, y, w, h, cells = line:match("^(%S+) (%d+) (%d+) (%d+) (%d+) (%d+) (%S+)%s*$")
			if proto and not proto:match("^#") then
				local t = {id = proto .. "#" .. n, proto = proto, n = tonumber(n),
					x = tonumber(x), y = tonumber(y), w = tonumber(w), h = tonumber(h), typ = {}}
				for k = 1, #cells do
					t.typ[k] = cells:byte(k) - 48
				end
				if #t.typ == t.w * t.h then
					areas.templates[t.id] = t
					areas.list[#areas.list + 1] = t
				end
			end
		end
		f:close()
	end
end

-- terrain a template has at its square (cx, cy) (0-based, y going south)
function areas.template_typ(t, cx, cy)
	return t.typ[cy * t.w + cx + 1]
end

-- squares that always use their own prefabs
local OWN = {[T.DOOR] = true, [T.STAIRS] = true, [T.LADDER] = true,
	[T.DRAWBRIDGE_UP] = true, [T.DRAWBRIDGE_DOWN] = true, [T.DBWALL] = true}
function areas.own_prefab(typ)
	return OWN[typ] or false
end

-- ---------------------------------------------------------------- built areas
local DATA_DIR = core.get_mod_data_path() .. DIR_DELIM .. "areas"
local function file_of(id)
	return DATA_DIR .. DIR_DELIM .. id:gsub("[^%w%-]", "_") .. ".dat"
end
areas.file_of = file_of

-- The file: "NHVAREA 2", a palette line ("palette<TAB>name<TAB>name..."),
-- then a line per built square: "<k><TAB><node> <node> ...", each node
-- "<index>:<palette number>[:<param2>]". (Line by line, so it loads however
-- big the area is: a whole-level area as one serialized table - the Plane
-- of Fire, the Astral Plane - is too big for core.deserialize, which then
-- quietly gives nothing.)
local HEADER = "NHVAREA 2"

local function decode(text)
	local d = {cells = {}}
	local palette = {}
	for line in text:gmatch("[^\n]+") do
		local k, rest = line:match("^(%d+)\t(.*)$")
		if k then
			local nodes = {}
			for i, p, p2 in rest:gmatch("(%d+):(%d+):?(%d*)") do
				nodes[tonumber(i)] = {n = palette[tonumber(p)], p2 = tonumber(p2) or 0}
			end
			d.cells[tonumber(k)] = {nodes = nodes}
		elseif line:sub(1, 8) == "palette\t" then
			for name in line:sub(9):gmatch("[^\t]+") do
				palette[#palette + 1] = name
			end
		end
	end
	return d
end

local function encode(d)
	local names, pal, out = {}, {}, {HEADER, ""}
	local ks = {}
	for k in pairs(d.cells) do
		ks[#ks + 1] = k
	end
	table.sort(ks)
	for _, k in ipairs(ks) do
		local is = {}
		for i in pairs(d.cells[k].nodes or {}) do
			is[#is + 1] = i
		end
		table.sort(is)
		local ents = {}
		for _, i in ipairs(is) do
			local nd = d.cells[k].nodes[i]
			if not pal[nd.n] then
				names[#names + 1] = nd.n
				pal[nd.n] = #names
			end
			local p2 = tonumber(nd.p2) or 0
			ents[#ents + 1] = i .. ":" .. pal[nd.n] .. (p2 ~= 0 and (":" .. p2) or "")
		end
		out[#out + 1] = k .. "\t" .. table.concat(ents, " ")
	end
	out[2] = "palette\t" .. table.concat(names, "\t")
	return table.concat(out, "\n") .. "\n"
end

function areas.get(id)
	local d = areas.data[id]
	if d == nil then
		local f = io.open(file_of(id), "rb")
		if f then
			local text = f:read("*a")
			f:close()
			if text:sub(1, #HEADER) == HEADER then
				d = decode(text)
			elseif text ~= "" then
				-- (the old format: one serialized table)
				d = core.deserialize(text)
				if type(d) ~= "table" then
					core.log("error", "[nhv] area " .. id .. ": can't read " .. file_of(id))
					d = {unreadable = true}
				end
			end
		end
		d = d or {}
		d.cells = d.cells or {}
		areas.data[id] = d
	end
	return d
end

function areas.save(id)
	local d = areas.get(id)
	if d.unreadable then
		return false -- (never written over: what's in it would be lost)
	end
	core.mkdir(DATA_DIR)
	return core.safe_file_write(file_of(id), encode(d))
end

function areas.built(id)
	return next(areas.get(id).cells) ~= nil
end

-- ---------------------------------------------------------------- in the game
-- NetHack reports each special level's fixed regions when it builds the
-- level; they're kept per game and level (world mod storage).
local storage = core.get_mod_storage()
local active = {gid = nil, ledger = nil, regions = {}}

local function key(gid, ledger)
	return ("splev:%d:%d"):format(gid, ledger)
end

if not nhv.EDITOR then
	nhv.nh.on_event(function(evs)
		for _, ev in ipairs(evs) do
			if ev.kind == "splev" then
				local gid, ledger, proto, n, x, y, w, h, more = ev.text:match(
					"^(%-?%d+) (%d+) (%S+) (%d+) (%d+) (%d+) (%d+) (%d+)(.*)$")
				if gid then
					local k = key(tonumber(gid), tonumber(ledger))
					local list = core.deserialize(storage:get_string(k)) or {}
					-- (and how the level was flipped once built: top/bottom
					-- flip % 2, left/right flip >= 2, within minx..maxx etc.)
					local flip, x0, y0, x1, y1 = more:match("^ (%d+) (%d+) (%d+) (%d+) (%d+)")
					list[tonumber(n)] = {proto = proto, n = tonumber(n), x = tonumber(x),
						y = tonumber(y), w = tonumber(w), h = tonumber(h), flip = tonumber(flip),
						minx = tonumber(x0), miny = tonumber(y0), maxx = tonumber(x1), maxy = tonumber(y1)}
					storage:set_string(k, core.serialize(list))
					active.gid = nil -- (look again)
				end
			end
		end
	end)
end

-- the regions of the level you're on, with a built area for them
local function regions()
	local snap = nhv.nh.snap
	local ledger = snap and snap.hero and snap.hero.ledger
	if not ledger or not core.nh_game_id then
		return {}
	end
	local gid = core.nh_game_id()
	if not gid then
		return {} -- (no game running)
	end
	if active.gid ~= gid or active.ledger ~= ledger then
		active.gid, active.ledger, active.regions = gid, ledger, {}
		for _, r in pairs(core.deserialize(storage:get_string(key(gid, ledger))) or {}) do
			local t = areas.templates[r.proto .. "#" .. r.n]
			-- (only if it's laid out as the template is)
			if t and t.w == r.w and t.h == r.h and areas.built(t.id) then
				-- (where it is now: NetHack may have flipped the level)
				local x, y, f = r.x, r.y, r.flip or 0
				if f >= 2 then
					x = r.maxx - (r.x + r.w - 1) + r.minx
				end
				if f % 2 == 1 then
					y = r.maxy - (r.y + r.h - 1) + r.miny
				end
				active.regions[#active.regions + 1] = {t = t, x = x, y = y}
			end
		end
	end
	return active.regions
end

-- Is the level's hand-built area open to the sky (you built most of its
-- floor without a ceiling - a Big Room under the open sky - or with the
-- invisible Sky block)? Then rock you didn't build there stops at wall
-- height (terrain.lua).
local open_cache = {} -- template id -> boolean
local function area_open(t)
	if open_cache[t.id] == nil then
		local cells = areas.get(t.id).cells
		local floors, roofed = 0, 0
		for k, typ in pairs(t.typ) do
			local cell = cells[k]
			if (typ == T.ROOM or typ == T.ICE) and cell then
				floors = floors + 1
				for i, nd in pairs(cell.nodes or {}) do
					local _, ly = nhv.prefabs.unindex(i)
					if ly >= nhv.prefabs.CEIL and nd.n ~= "air" and nd.n ~= "nhv:sky" then
						roofed = roofed + 1
						break
					end
				end
			end
		end
		open_cache[t.id] = floors > 0 and roofed < floors / 2
	end
	return open_cache[t.id]
end
areas.area_open = area_open
function areas.open_to_sky()
	for _, r in ipairs(regions()) do
		if area_open(r.t) then
			return true
		end
	end
	return false
end

-- The special level variants the level you're on was built from (as NetHack
-- reported them: "bigrm-6", "medusa-2", ...), as a set; empty for an
-- ordinary level.
function areas.level_variants()
	local snap = nhv.nh.snap
	local ledger = snap and snap.hero and snap.hero.ledger
	local gid = ledger and core.nh_game_id and core.nh_game_id()
	local out = {}
	if not gid then
		return out
	end
	for _, r in pairs(core.deserialize(storage:get_string(key(gid, ledger))) or {}) do
		out[r.proto] = true
	end
	return out
end

-- Which way round the template is on this level: NetHack flips special
-- levels at random (left/right, top/bottom), and a template is as it was
-- the game it was taken from - so whichever of the four ways matches the
-- level best (0: as it is; + 1: top/bottom; + 2: left/right).
local function template_flip(r, map)
	local t = r.t
	local best, best_n = 0, -1
	for f = 0, 3 do
		local n = 0
		for ay = 0, t.h - 1 do
			for ax = 0, t.w - 1 do
				local cx = f >= 2 and t.w - 1 - ax or ax
				local cy = f % 2 == 1 and t.h - 1 - ay or ay
				if map.typ[U.idx(r.x + ax, r.y + ay)] == areas.template_typ(t, cx, cy) then
					n = n + 1
				end
			end
		end
		if n > best_n then
			best, best_n = f, n
		end
	end
	return best
end

-- a built square's nodes flipped as the level is (and the blocks that face
-- a way turned to match)
local FLIP_ROT = {[1] = {[0] = 2, [2] = 0}, [2] = {[1] = 3, [3] = 1}} -- z, x
local FLIP_WALL = {[1] = {[4] = 5, [5] = 4}, [2] = {[2] = 3, [3] = 2}}
local flipped = setmetatable({}, {__mode = "k"}) -- cell -> {[f] = cell}
local function flip_cell(cell, f)
	local by = flipped[cell] or {}
	flipped[cell] = by
	if by[f] then
		return by[f]
	end
	local prefabs = nhv.prefabs
	local W = prefabs.W
	local nodes = {}
	for i, nd in pairs(cell.nodes) do
		local lx, ly, lz = prefabs.unindex(i)
		if f >= 2 then
			lx = W - 1 - lx
		end
		if f % 2 == 1 then
			lz = W - 1 - lz
		end
		local p2 = nd.p2 or 0
		local def = core.registered_nodes[nd.n]
		local pt = def and def.paramtype2
		for _, bit in ipairs({1, 2}) do
			if (bit == 2 and f >= 2) or (bit == 1 and f % 2 == 1) then
				if pt == "facedir" or pt == "4dir" then
					local rot = p2 % 4
					p2 = p2 - rot + (FLIP_ROT[bit][rot] or rot)
				elseif pt == "wallmounted" then
					local d = p2 % 8
					p2 = p2 - d + (FLIP_WALL[bit][d] or d)
				end
			end
		end
		nodes[prefabs.index(lx, ly, lz)] = {n = nd.n, p2 = p2}
	end
	by[f] = {nodes = nodes}
	return by[f]
end

-- the hand-built region square (tx, ty) is in: the region, its flip (as
-- the level is laid out) and the template square there
local function region_at(tx, ty, map)
	for _, r in ipairs(regions()) do
		local ax, ay = tx - r.x, ty - r.y
		if ax >= 0 and ay >= 0 and ax < r.t.w and ay < r.t.h then
			if r.flip == nil and map then
				r.flip = template_flip(r, map)
			end
			local f = r.flip or 0
			local cx = f >= 2 and r.t.w - 1 - ax or ax
			local cy = f % 2 == 1 and r.t.h - 1 - ay or ay
			return r, f, cx, cy
		end
	end
	return nil
end

-- the built cell at template square (cx, cy) of region r, flipped as the
-- level is, and an id for it
local function built_at(r, f, cx, cy)
	local k = cy * r.t.w + cx + 1
	local cell = areas.get(r.t.id).cells[k]
	if cell and f ~= 0 then
		cell = flip_cell(cell, f)
	end
	return cell, cell and (r.t.id .. "@" .. k .. "~" .. f)
end

-- For a door at (tx, ty): is it in a hand-built area, and the square you
-- built at that very spot (a door, or wall where the door is elsewhere
-- this game) with an id - terrain.lua builds the door with what you built
-- from the lintel up. (true, nil: in an area, nothing built there.)
function areas.door_top(tx, ty, map)
	if nhv.EDITOR then
		return false
	end
	local r, f, cx, cy = region_at(tx, ty, map)
	if not r then
		return false
	end
	return true, built_at(r, f, cx, cy)
end

-- The hand-built cell for square (tx, ty) with terrain typ (map: the
-- level's map, to see which way round it is), and an id for it; nil if the
-- usual prefab is used there.
--
-- Some special levels put a door in a different place each game (the
-- Oracle's centre room has its door on any side): where the template has a
-- door and this game has wall, the wall you built beside it on the same
-- wall line is used.
--
-- Floor only changing (a Big Room's random ice patches, a corridor where
-- the template has room floor...): what you built stays, all but its floor,
-- which is the new terrain's (third result: true) - no ceiling of the usual
-- prefab's dropped into an area open to the sky.
local FLOOR = {[T.ROOM] = true, [T.CORR] = true, [T.ICE] = true}
function areas.cell(tx, ty, typ, map)
	if nhv.EDITOR or OWN[typ] then
		return nil
	end
	local r, f, cx, cy = region_at(tx, ty, map)
	if not r then
		return nil
	end
	local ttyp = areas.template_typ(r.t, cx, cy)
	if ttyp == typ then
		return built_at(r, f, cx, cy)
	end
	if FLOOR[ttyp] and FLOOR[typ] then
		local cell, id = built_at(r, f, cx, cy)
		if cell then
			return cell, id .. "+floor", true
		end
	end
	if ttyp == T.DOOR and typ >= T.VWALL and typ <= T.TRWALL then
		-- (along the wall line: a north-south wall's squares above and
		-- below it, an east-west wall's either side)
		local line = typ == T.VWALL and {{0, -1}, {0, 1}} or {{-1, 0}, {1, 0}}
		for _, d in ipairs(line) do
			local nx, ny = cx + d[1], cy + d[2]
			if nx >= 0 and ny >= 0 and nx < r.t.w and ny < r.t.h
					and areas.template_typ(r.t, nx, ny) == typ
					and areas.get(r.t.id).cells[ny * r.t.w + nx + 1] then
				return built_at(r, f, nx, ny)
			end
		end
	end
	-- (changed since the level was made: the usual prefab)
	return nil
end

return areas
