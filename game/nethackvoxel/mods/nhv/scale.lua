-- Monster sizes.
--
-- A monster's sprite height comes from its NetHack size class, times an
-- optional per-monster scale you can set in game:
--   /scale                 list the scales you have set
--   /scale <factor> <name> set e.g. "/scale 1.5 jackal" (1 = default)
-- Its body (hitbox) is the size of its sprite.

local storage = core.get_mod_storage()
local scale = {}
nhv.scale = scale

-- sprite height in nodes for MZ_TINY .. MZ_GIGANTIC
scale.SIZE_H = {[0] = 1.1, 1.5, 2.0, 2.7, 3.5, 4.4}

local overrides = core.deserialize(storage:get_string("scales")) or {}

local function save()
	storage:set_string("scales", core.serialize(overrides))
end

function scale.factor(mndx)
	if not mndx or mndx < 0 then
		return 1
	end
	local name = core.nh_mon_name(mndx)
	return (name and overrides[name]) or 1
end

-- sprite height in nodes
function scale.height(size, mndx)
	return (scale.SIZE_H[size or 2] or scale.SIZE_H[2]) * scale.factor(mndx)
end

-- body radius in nodes (the sprite is as wide as it is tall; most of
-- the art fills a bit over half of that)
function scale.radius(size, mndx)
	return math.min(1.3, scale.height(size, mndx) * 0.3)
end

core.register_chatcommand("scale", {
	params = "[<factor> <monster name>]",
	description = "Set the size of a kind of monster (1 = default)",
	func = function(name, param)
		if param == "" then
			local list = {}
			for k, v in pairs(overrides) do
				list[#list + 1] = k .. " = " .. v
			end
			table.sort(list)
			return true, #list == 0 and "No monster scales set." or table.concat(list, ", ")
		end
		local f, mon = param:match("^%s*([%d%.]+)%s+(.+)$")
		f = tonumber(f)
		if not f or f <= 0 or f > 5 then
			return false, "Usage: /scale <factor 0.1-5> <monster name>"
		end
		mon = mon:lower()
		overrides[mon] = (f ~= 1) and f or nil
		save()
		if nhv.mobs then
			nhv.mobs.refresh_sizes()
		end
		return true, ("%s scale set to %s"):format(mon, f)
	end,
})

return scale
