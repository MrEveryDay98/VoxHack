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

-- {mon = {[name] = factor}, feat = {[cmap] = factor}}
local data = {mon = {}, feat = {}}

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
	return (name and data.mon[name]) or 1
end

function scale.set_mon(name, f)
	data.mon[name] = (f and f ~= 1) and f or nil
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
	return data.feat[cmap] or 1
end

function scale.set_feat(cmap, f)
	data.feat[cmap] = (f and f ~= 1) and f or nil
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
			for k, v in pairs(data.mon) do
				list[#list + 1] = k .. " = " .. v
			end
			for k, v in pairs(data.feat) do
				list[#list + 1] = (scale.FEATURE_NAMES[k] or k) .. " = " .. v
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
