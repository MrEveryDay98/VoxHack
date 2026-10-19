-- Shop signs: a wooden sign over each shop's door, on the outside of the
-- block above the doorway, with the shop's name on it ("Asidonhopo's /
-- General Store"; just the kind of shop when it has no shopkeeper, as in
-- Orcish Town). Minetown's shops are NetHack shops too, so they get theirs.
--
-- A sign shows once you've seen the shop's door. The picture is
-- nhv_tiles/textures/nhv_wallWide_doorSign.png (one square wide, one block
-- high) drawn 3x as big, with the name in white letters (and a dark shadow)
-- in the game's pixel font, centred: textures/nhv_sf_<char code>.png and
-- nhv_sfs_<char code>.png (8x12 each). Options > NetHack options > "Signs
-- over shop doors" turns them off.

local nh = nhv.nh
local U = nhv.util

local signs = {ents = {}} -- key -> object
nhv.signs = signs

local SCALE = 3
local W, H = 48 * SCALE, 16 * SCALE
local CW, CH = 8, 12 -- (a letter's cell)
local LINE_GAP = 2
local MARGIN = SCALE -- (keeps the letters off the frame)
local MAX_COLS = math.floor((W - 2 * MARGIN) / CW)
local MAX_LINES = 3
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

local function wrap(text, lines)
	local line = ""
	for word in text:gmatch("%S+") do
		if line ~= "" and #line + 1 + #word > MAX_COLS then
			lines[#lines + 1] = line
			line = word
		else
			line = line == "" and word or line .. " " .. word
		end
	end
	if line ~= "" then
		lines[#lines + 1] = line
	end
	return lines
end

-- the shopkeeper's name on a line of its own, then the kind of shop
local function sign_lines(words)
	local lines = {}
	for _, part in ipairs(words) do
		wrap(part, lines)
	end
	while #lines > MAX_LINES do
		table.remove(lines)
	end
	for i, l in ipairs(lines) do
		lines[i] = l:sub(1, MAX_COLS)
	end
	return lines
end

-- the sign's picture with these words on it ({"Asidonhopo's", "General
-- Store"}: each starts a new line)
function signs.texture(words)
	local lines = sign_lines(words)
	local parts = {}
	local total = #lines * CH + (#lines - 1) * LINE_GAP
	local y0 = math.floor((H - total) / 2)
	for li, line in ipairs(lines) do
		local x0 = math.floor((W - #line * CW) / 2)
		local y = y0 + (li - 1) * (CH + LINE_GAP)
		for i = 1, #line do
			local c = line:byte(i)
			if c > 32 and c < 127 then
				local x = x0 + (i - 1) * CW
				parts[#parts + 1] = ("%d,%d=nhv_sfs_%d.png"):format(x + 1, y + 1, c)
				parts[#parts + 1] = ("%d,%d=nhv_sf_%d.png"):format(x, y, c)
			end
		end
	end
	local base = ("nhv_wallWide_doorSign.png^[resize:%dx%d"):format(W, H)
	if #parts == 0 then
		return base
	end
	return base .. ("^([combine:%dx%d:"):format(W, H) .. table.concat(parts, ":") .. ")"
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
