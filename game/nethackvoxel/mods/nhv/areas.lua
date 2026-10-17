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
	local count = 0
	for _, o in ipairs(areas.list) do
		if o.proto == t.proto then
			count = count + 1
		end
	end
	return count > 1 and ("%s, part %d"):format(name, t.n) or name
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

function areas.get(id)
	local d = areas.data[id]
	if d == nil then
		local f = io.open(file_of(id), "rb")
		if f then
			d = core.deserialize(f:read("*a")) or {}
			f:close()
		end
		d = d or {}
		d.cells = d.cells or {}
		areas.data[id] = d
	end
	return d
end

function areas.save(id)
	core.mkdir(DATA_DIR)
	return core.safe_file_write(file_of(id), core.serialize(areas.get(id)))
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
				local gid, ledger, proto, n, x, y, w, h = ev.text:match(
					"^(%-?%d+) (%d+) (%S+) (%d+) (%d+) (%d+) (%d+) (%d+)")
				if gid then
					local k = key(tonumber(gid), tonumber(ledger))
					local list = core.deserialize(storage:get_string(k)) or {}
					list[tonumber(n)] = {proto = proto, n = tonumber(n), x = tonumber(x),
						y = tonumber(y), w = tonumber(w), h = tonumber(h)}
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
				active.regions[#active.regions + 1] = {t = t, x = r.x, y = r.y}
			end
		end
	end
	return active.regions
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

-- The hand-built cell for square (tx, ty) with terrain typ, and an id for
-- it; nil if the usual prefab is used there.
function areas.cell(tx, ty, typ)
	if nhv.EDITOR or OWN[typ] then
		return nil
	end
	for _, r in ipairs(regions()) do
		local cx, cy = tx - r.x, ty - r.y
		if cx >= 0 and cy >= 0 and cx < r.t.w and cy < r.t.h then
			-- (changed since the level was made: the usual prefab)
			if areas.template_typ(r.t, cx, cy) ~= typ then
				return nil
			end
			local k = cy * r.t.w + cx + 1
			local cell = areas.get(r.t.id).cells[k]
			return cell, cell and (r.t.id .. "@" .. k)
		end
	end
	return nil
end

return areas
