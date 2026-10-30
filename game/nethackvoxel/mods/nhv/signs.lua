-- Shop signs: a wooden sign over each shop's door, on the outside of the
-- block above the doorway, with the shop's name on it ("Asidonhopo's /
-- General Store"; just the kind of shop when it has no shopkeeper, as in
-- Orcish Town). Minetown's shops are NetHack shops too, so they get theirs.
--
-- A sign shows once you've seen the shop's door. The picture is
-- nhv_tiles/textures/nhv_wallWide_doorSign.png (one square wide, one block
-- high) drawn 3x as big, with the name in white letters (and a dark shadow)
-- in the game's pixel font, centred: textures/nhv_sf_<char code>.png and
-- nhv_sfs_<char code>.png (8x12 each). Pause menu > NetHack Options > "Signs
-- over shop doors" turns them off.

local nh = nhv.nh
local U = nhv.util

local signs = {ents = {}} -- key -> object
nhv.signs = signs

-- the block over the doorway: the doorway is the floor's 4 blocks of wall
-- height less one
local SIGN_Y = U.FLOOR_Y + U.WALL_H
local OUT = 1.5 + 0.03 -- (from the square's middle to just off its face)

core.register_entity("nhv:shop_sign", {
	initial_properties = {
		visual = "upright_sprite", physical = false, pointable = false,
		static_save = false, visual_size = {x = 3, y = 1}, shaded = true,
		textures = {"blank.png", "blank.png"},
	},
})

local function title_case(s)
	return (s:gsub("(%a)([%w']*)", function(a, b) return a:upper() .. b end))
end

-- the sign's picture with these words on it (signart.lua)
function signs.texture(words)
	return nhv.signart.texture(words)
end

function signs.words(shop)
	local kind = title_case(shop.type or "")
	if shop.keeper and shop.keeper ~= "" then
		return {shop.keeper .. "'s", kind}
	end
	return {kind}
end

local function seen(map, x, y)
	local f = map and map.flags and map.flags[U.idx(x, y)]
	return f and f % 2 == 1
end

local function clear_all()
	for k, obj in pairs(signs.ents) do
		obj:remove()
		signs.ents[k] = nil
	end
end

function signs.update()
	local map = nhv.terrain.map
	local on = nhv.nhopts.get("shop_signs")
	local want = {}
	if on and map and core.nh_get_shops then
		for _, s in ipairs(core.nh_get_shops() or {}) do
			if U.in_map(s.door_x, s.door_y) and seen(map, s.door_x, s.door_y) then
				local words = signs.words(s)
				want[("%d,%d|%d,%d|%s"):format(s.door_x, s.door_y, s.in_x, s.in_y,
					table.concat(words, "/"))] = {s, words}
			end
		end
	end
	for k, obj in pairs(signs.ents) do
		if not want[k] or not obj:get_pos() then
			obj:remove()
			signs.ents[k] = nil
		end
	end
	for k, v in pairs(want) do
		if not signs.ents[k] then
			local s, words = v[1], v[2]
			-- outward: from the square inside the shop through the door
			-- (world z runs opposite to map y)
			local ox, oz = s.door_x - s.in_x, -(s.door_y - s.in_y)
			local c = U.tile_center(s.door_x, s.door_y, SIGN_Y)
			local pos = vector.new(c.x + ox * OUT, SIGN_Y, c.z + oz * OUT)
			local obj = core.add_entity(pos, "nhv:shop_sign")
			if obj then
				local tex = signs.texture(words)
				obj:set_properties({textures = {tex, tex}})
				-- (the sprite's face looks along -z at yaw 0)
				obj:set_yaw(math.atan2(ox, -oz))
				signs.ents[k] = obj
			end
		end
	end
end

nh.on_snapshot(function(snap)
	if not snap then
		clear_all()
		return
	end
	signs.update()
end)

return signs
