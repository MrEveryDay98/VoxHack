-- The HUD's skin: pictures you can draw your own of, in nhv_tiles/textures
-- (tools/make_ui_skin.py made the first ones) -
--   ui_frame.png  the boxes: your portrait, your numbers, what you wear,
--                 your ailments, the map, what's said, the inventory,
--                 what's on the ground, the keys' hints (the side bars:
--                 sidebars.lua; the portrait, hud.lua)
--   ui_slot.png   the slots: what you wear, your weapons and quiver, the
--                 hotbar's (hotbar.lua)
-- Each 24x24, a 3x3 grid of 8x8 pieces: the corners as they are, the edges
-- repeated along the sides, the middle stretched over the rest - drawn
-- twice their size, as the bars' bricks are. What's in a box starts
-- skin.INSET in from its edge: keep a frame's border in its pieces' outer
-- 3 pixels.

local skin = {}
nhv.skin = skin

skin.FRAME = "ui_frame.png"
skin.SLOT = "ui_slot.png"
local K = 2          -- (the pictures' size on the HUD: twice their own)
skin.INSET = 3 * K   -- (a box's border)
local RING = 3       -- (a lit slot's ring: its width)

-- (piece cx, cy of the 3x3 grid, w x h - written to go inside [combine)
local function piece(tex, cx, cy, w, h)
	return ("%s\\^[sheet\\:3x3\\:%d,%d\\^[resize\\:%dx%d"):format(tex, cx, cy, w, h)
end

local made = {} -- (texture strings made: the same box asked for again)

-- a w x h picture of tex's nine pieces
function skin.nine(tex, w, h)
	w, h = math.max(2, math.floor(w)), math.max(2, math.floor(h))
	local key = tex .. w .. "x" .. h
	if made[key] then
		return made[key]
	end
	-- (a piece's size: smaller in a box too small for two)
	local P = math.max(1, math.min(8 * K, math.floor(math.min(w, h) / 2)))
	local t = {("[combine:%dx%d"):format(w, h)}
	local function put(x, y, cx, cy, pw, ph)
		t[#t + 1] = (":%d,%d=%s"):format(x, y, piece(tex, cx, cy, pw, ph))
	end
	if w > 2 * P and h > 2 * P then
		put(P, P, 1, 1, w - 2 * P, h - 2 * P)
	end
	-- (the edges: the last of each runs on under the corner, drawn over it)
	for x = P, w - P - 1, P do
		put(x, 0, 1, 0, P, P)
		put(x, h - P, 1, 2, P, P)
	end
	for y = P, h - P - 1, P do
		put(0, y, 0, 1, P, P)
		put(w - P, y, 2, 1, P, P)
	end
	put(0, 0, 0, 0, P, P)
	put(w - P, 0, 2, 0, P, P)
	put(0, h - P, 0, 2, P, P)
	put(w - P, h - P, 2, 2, P, P)
	made[key] = table.concat(t)
	return made[key]
end

-- a box, w x h
function skin.box(w, h)
	return skin.nine(skin.FRAME, w, h)
end

-- a slot, size x size; lit: a ring of that colour round it (the weapon in
-- your hand, a key pressed)
function skin.slot(size, lit)
	size = math.floor(size)
	local tex = skin.nine(skin.SLOT, size, size)
	if lit then
		local r = RING
		tex = tex .. ("^[fill:%dx%d:0,0:%s^[fill:%dx%d:0,%d:%s^[fill:%dx%d:0,0:%s^[fill:%dx%d:%d,0:%s"):format(
			size, r, lit, size, r, size - r, lit, r, size, lit, r, size, size - r, lit)
	end
	return tex
end

return skin
