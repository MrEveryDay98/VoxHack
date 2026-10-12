-- Sizes of sprites: monsters and dungeon features.
--
-- A monster's sprite height comes from its NetHack size class; a
-- feature (tree, fountain, throne, ...) has its own base height. Either
-- can be multiplied by a scale set in the editor world's monster editor
-- (or with /scale in game). Scales are shared by all worlds.
-- A monster's body (hitbox) is the size of its sprite.

local scale = {}
nhv.scale = scale

-- sprite height in nodes for MZ_TINY .. MZ_GIGANTIC
scale.SIZE_H = {[0] = 1.1, 1.5, 2.0, 2.7, 3.5, 4.4}

-- base sprite heights for features, by cmap symbol name
scale.FEATURE_H = {
	S_tree = 4.2, S_fountain = 1.8, S_altar = 1.6, S_throne = 2.2,
	S_sink = 1.5, S_grave = 1.7,
}
scale.FEATURE_NAMES = {
	S_tree = "tree", S_fountain = "fountain", S_altar = "altar",
	S_throne = "throne", S_sink = "sink", S_grave = "grave",
}

local DATA_DIR = core.get_mod_data_path()
local DATA_PATH = DATA_DIR .. DIR_DELIM .. "scales.dat"

-- {mon = {[name] = setting}, feat = {[cmap] = setting}}, where a setting
-- is {f = factor, anchor = "floor"|"ceiling", off = nodes} (older files
-- stored just the factor)
local data = {mon = {}, feat = {}}

local function setting(tbl, key)
	local v = tbl[key]
	if type(v) == "number" then
		return {f = v, anchor = "floor", off = 0}
	elseif type(v) == "table" then
		return {f = v.f or 1, anchor = v.anchor or "floor", off = v.off or 0}
	end
	return {f = 1, anchor = "floor", off = 0}
end

local function store(tbl, key, st)
	if st.f == 1 and st.anchor == "floor" and st.off == 0 then
		tbl[key] = nil
	else
		tbl[key] = {f = st.f, anchor = st.anchor, off = st.off}
	end
end

-- full setting for a monster name / feature cmap
function scale.get(kind, key)
	return setting(kind == "feat" and data.feat or data.mon, key)
end

function scale.set(kind, key, st)
	store(kind == "feat" and data.feat or data.mon, key, st)
end

local function load()
	local f = io.open(DATA_PATH, "rb")
	if f then
		local d = core.deserialize(f:read("*a"))
		f:close()
		if type(d) == "table" then
			data.mon = d.mon or {}
			data.feat = d.feat or {}
		end
	end
end

function scale.save()
	core.mkdir(DATA_DIR)
	return core.safe_file_write(DATA_PATH, core.serialize(data))
end

load()

-- ---------------------------------------------------------------- monsters
function scale.mon_factor_by_name(name)
	return name and setting(data.mon, name).f or 1
end

function scale.set_mon(name, f)
	local st = setting(data.mon, name)
	st.f = f or 1
	store(data.mon, name, st)
end

function scale.factor(mndx)
	if not mndx or mndx < 0 then
		return 1
	end
	return scale.mon_factor_by_name(core.nh_mon_name(mndx))
end

function scale.height(size, mndx)
	return (scale.SIZE_H[size or 2] or scale.SIZE_H[2]) * scale.factor(mndx)
end

-- body radius in nodes (the sprite is as wide as it is tall; most of
-- the art fills a bit over half of that)
function scale.radius_for_height(h)
	return math.min(1.3, h * 0.3)
end

function scale.radius(size, mndx)
	return scale.radius_for_height(scale.height(size, mndx))
end

-- ---------------------------------------------------------------- features
function scale.feat_factor(cmap)
	return setting(data.feat, cmap).f
end

function scale.set_feat(cmap, f)
	local st = setting(data.feat, cmap)
	st.f = f or 1
	store(data.feat, cmap, st)
end

-- Height of the sprite's centre above ground, for a sprite `h` nodes tall,
-- given its anchor: floor = standing on the floor (raised by off),
-- ceiling = hanging from the ceiling (lowered by off).
function scale.center_y(kind, key, h, floor_top, ceiling_bottom)
	local st = setting(kind == "feat" and data.feat or data.mon, key)
	if st.anchor == "ceiling" then
		return ceiling_bottom - st.off - h / 2
	end
	return floor_top + st.off + h / 2
end

function scale.mon_center_y(mndx, h, floor_top, ceiling_bottom)
	local name = mndx and mndx >= 0 and core.nh_mon_name(mndx) or ""
	return scale.center_y("mon", name, h, floor_top, ceiling_bottom)
end

function scale.feature_height(cmap)
	local base = scale.FEATURE_H[cmap]
	if not base then
		return nil
	end
	return base * scale.feat_factor(cmap)
end

-- ---------------------------------------------------------------- command
core.register_chatcommand("scale", {
	params = "[<factor> <monster name>]",
	description = "Set the size of a kind of monster (1 = default)",
	func = function(_, param)
		if param == "" then
			local list = {}
			for k in pairs(data.mon) do
				list[#list + 1] = k .. " = " .. setting(data.mon, k).f
			end
			for k in pairs(data.feat) do
				list[#list + 1] = (scale.FEATURE_NAMES[k] or k) .. " = " .. setting(data.feat, k).f
			end
			table.sort(list)
			return true, #list == 0 and "No scales set." or table.concat(list, ", ")
		end
		local f, mon = param:match("^%s*([%d%.]+)%s+(.+)$")
		f = tonumber(f)
		if not f or f <= 0 or f > 5 then
			return false, "Usage: /scale <factor 0.1-5> <monster name>"
		end
		mon = mon:lower()
		scale.set_mon(mon, f)
		scale.save()
		if nhv.mobs then
			nhv.mobs.refresh_sizes()
		end
		return true, ("%s scale set to %s"):format(mon, f)
	end,
})

return scale
