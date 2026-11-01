-- Long worms' tails. NetHack shows a long worm's tail as a tail picture on
-- every square it covers; here it's one body: voxel segments snaking from
-- the head through those squares, in order, to the tail's end, in the
-- worm's own colours (nhv_tiles/worm_colors.lua: tools/make_worm_colors.py
-- - its body, the stripe along its back, the shading underneath). The
-- squares' own pictures are hidden meanwhile (mobs.lua); hitting a
-- segment hits the tail on its square. Not while you're hallucinating
-- (what a tail looks like then is NetHack's to say), nor in ASCII mode.
local U = nhv.util

local worms = {}
nhv.worms = worms

local COLORS = dofile(core.get_modpath("nhv_tiles") .. "/worm_colors.lua")
local DEFAULT = {body = "#FFB691", accent = "#FF6C00", dark = "#000000"}
local WIDTH = 1.3      -- the body's thickness next to the head (nodes)
local TIP = 0.55       -- at the very end of the tail
local SPACING = 0.7    -- from one segment to the next, for their width
local OVERLAP = 1.25   -- (each a little longer than that: no gaps on bends)
local WAVE = 0.3       -- how far it snakes from side to side (nodes)
local WAVE_LEN = 7     -- (nodes from one bend to the next the same way)
local WAVE_SPEED = 2.2 -- (the bends running down it: radians a second)
local EASE = 8         -- how quickly segments follow where they're going
local SAMPLES = 8      -- (points along the curve from one square to the next)

-- a segment: a box, its length along its z
core.register_entity("nhv:wormseg", {
	initial_properties = {
		visual = "cube", textures = {"blank.png", "blank.png", "blank.png", "blank.png", "blank.png", "blank.png"},
		physical = false, pointable = true, static_save = false,
		collisionbox = {0, 0, 0, 0, 0, 0}, selectionbox = {-0.5, -0.5, -0.5, 0.5, 0.5, 0.5},
		shaded = true,
	},
	on_punch = function(self, puncher)
		if nhv.actions and self.nh_key then
			nhv.actions.attack_entity(puncher, self)
		end
		return true
	end,
})

-- drawn as voxel bodies now (else as NetHack's pictures, square by square)
function worms.on(snap)
	return not nhv_tiles.ascii and not (snap and snap.hero and U.has(snap.hero.flags, U.HERO.HALLU))
end

-- ---------------------------------------------------------------- colours
local function rgb(c)
	return tonumber(c:sub(2, 3), 16), tonumber(c:sub(4, 5), 16), tonumber(c:sub(6, 7), 16)
end

local function mix(a, b, t)
	local r1, g1, b1 = rgb(a)
	local r2, g2, b2 = rgb(b)
	return ("#%02X%02X%02X"):format(math.floor(r1 + (r2 - r1) * t + 0.5), math.floor(g1 + (g2 - g1) * t + 0.5),
		math.floor(b1 + (b2 - b1) * t + 0.5))
end

-- a segment's faces (top, bottom, the sides, the ends): 8x8 pixels - the
-- stripe along the back, shading underneath, a ring at one end
local textures_of = {}
local function textures(tile)
	if textures_of[tile] then
		return textures_of[tile]
	end
	local c = COLORS[tile] or DEFAULT
	local ring, under = mix(c.body, c.dark, 0.35), mix(c.body, c.dark, 0.5)
	local top = ("[fill:8x8:%s^[fill:4x8:2,0:%s^[fill:8x1:0,0:%s"):format(c.body, c.accent, ring)
	local side = ("[fill:8x8:%s^[fill:8x2:0,0:%s^[fill:8x1:0,7:%s^[fill:1x8:0,0:%s"):format(c.body, c.accent,
		under, ring)
	local bottom = ("[fill:8x8:%s"):format(under)
	local cap = ("[fill:8x8:%s^[fill:6x6:1,1:%s^[fill:4x2:2,0:%s"):format(ring, c.body, c.accent)
	textures_of[tile] = {top, bottom, side, side .. "^[transformFX", cap, cap}
	return textures_of[tile]
end

-- ---------------------------------------------------------------- the chain
local function adjacent(a, b)
	return math.max(math.abs(a.x - b.x), math.abs(a.y - b.y)) == 1
end

-- each worm's tail as pieces: runs of squares one after another (a square
-- not seen breaks it), the first from the head if that's seen next to it.
-- A point: {p = where (x, z), k = its place in the tail (0: the head),
-- key = its mobs.mons key, x, y}.
local function pieces_of(mons)
	local tails = {}
	for key, e in pairs(mons) do
		if e.tail_of and e.mon and e.obj:get_pos() then
			local k = math.floor((e.mon.flags or 0) / 2 ^ U.MON_SEG_SHIFT)
			if k > 0 then
				local t = tails[e.tail_of] or {segs = {}, last = 0}
				tails[e.tail_of] = t
				local c = U.tile_center(e.x, e.y)
				t.segs[k] = {p = vector.new(c.x, 0, c.z), k = k, key = key, x = e.x, y = e.y}
				t.last = math.max(t.last, k)
				t.tile = e.tile
			end
		end
	end
	for id, t in pairs(tails) do
		t.pieces = {}
		local head = mons["id" .. id]
		local hp = head and head.obj:get_pos()
		local cur = nil
		if hp and t.segs[1] and adjacent(head, t.segs[1]) then
			cur = {{p = vector.new(hp.x, 0, hp.z), k = 0, key = "id" .. id, x = head.x, y = head.y}}
			t.pieces[1] = cur
		end
		for k = 1, t.last do
			local s = t.segs[k]
			if not s then
				cur = nil
			else
				if not (cur and adjacent(cur[#cur], s)) then
					cur = {}
					t.pieces[#t.pieces + 1] = cur
				end
				cur[#cur + 1] = s
			end
		end
	end
	return tails
end

-- a smooth curve through a piece's points (Catmull-Rom): samples
-- {p, k (fractional), d (distance along it), key}
local function curve(pts)
	local out = {}
	local function at(i)
		return pts[math.max(1, math.min(#pts, i))].p
	end
	local d = 0
	local prev = nil
	for i = 1, math.max(1, #pts - 1) do
		local p0, p1, p2, p3 = at(i - 1), at(i), at(i + 1), at(i + 2)
		local last = i == #pts - 1 or #pts == 1
		for j = 0, (last and SAMPLES or SAMPLES - 1) do
			local t = #pts == 1 and 0 or j / SAMPLES
			local t2, t3 = t * t, t * t * t
			local function cr(a, b, c, e)
				return 0.5 * (2 * b + (c - a) * t + (2 * a - 5 * b + 4 * c - e) * t2 + (3 * b - a - 3 * c + e) * t3)
			end
			local p = vector.new(cr(p0.x, p1.x, p2.x, p3.x), 0, cr(p0.z, p1.z, p2.z, p3.z))
			if prev then
				d = d + vector.distance(prev, p)
			end
			local near = pts[math.min(#pts, i + (t >= 0.5 and 1 or 0))]
			out[#out + 1] = {p = p, k = pts[i].k + (#pts == 1 and 0 or t * (pts[math.min(#pts, i + 1)].k - pts[i].k)),
				d = d, key = near.key}
			prev = p
			if #pts == 1 then
				break
			end
		end
	end
	return out
end

-- where along a curve (distance d): the point, its direction, the sample
local function along(c, d)
	for i = 2, #c do
		if c[i].d >= d then
			local a, b = c[i - 1], c[i]
			local f = b.d > a.d and (d - a.d) / (b.d - a.d) or 0
			local dir = vector.subtract(b.p, a.p)
			return vector.add(a.p, vector.multiply(dir, f)), dir, f < 0.5 and a or b
		end
	end
	local n = #c
	local dir = n > 1 and vector.subtract(c[n].p, c[n - 1].p) or vector.new(0, 0, 1)
	return c[n].p, dir, c[n]
end

local function width_at(k, last)
	-- (thinner over its last two squares, to a point)
	local f = math.max(0, math.min(1, (k - (last - 2)) / 2))
	return WIDTH + (TIP - WIDTH) * f
end

-- where each segment of a worm goes now: {pos, w, key}
local function targets(t, phase)
	local out = {}
	for _, piece in ipairs(t.pieces) do
		local c = curve(piece)
		local len = c[#c].d
		local from_head = piece[1].k == 0
		local d = from_head and WIDTH * 0.3 or 0
		repeat
			local p, dir, s = along(c, d)
			local w = width_at(s.k, t.last)
			-- (snaking: bends running down it - none where it leaves the head)
			local l = vector.length(dir)
			if l > 1e-4 then
				local side = vector.new(-dir.z / l, 0, dir.x / l)
				local reach = from_head and math.min(1, d / 1.5) or 1
				p = vector.add(p, vector.multiply(side, WAVE * reach * math.sin(phase - d * 2 * math.pi / WAVE_LEN)))
			end
			local tx, ty = U.pos_to_tile(p)
			local floor = U.in_map(tx, ty) and nhv.terrain.stand_y(tx, ty) or U.STAND_Y
			out[#out + 1] = {pos = vector.new(p.x, floor + w / 2, p.z), w = w, key = s.key}
			d = d + w * SPACING
		until d > len + 1e-3
	end
	return out
end

-- ---------------------------------------------------------------- drawing
local drawn = {} -- worm id -> list of {obj, pos, w, tile, key}

local function remove(list, from)
	for i = #list, from, -1 do
		if list[i].obj:get_pos() then
			list[i].obj:remove()
		end
		list[i] = nil
	end
end

function worms.clear()
	for id, list in pairs(drawn) do
		remove(list, 1)
		drawn[id] = nil
	end
end

core.register_globalstep(function(dtime)
	local snap = nhv.nh and nhv.nh.snap
	local mobs = nhv.mobs
	if not (snap and mobs and worms.on(snap)) then
		worms.clear()
		return
	end
	local tails = pieces_of(mobs.mons)
	local phase = core.get_us_time() / 1e6 * WAVE_SPEED
	local ease = math.min(1, dtime * EASE)
	for id, list in pairs(drawn) do
		if not tails[id] then
			remove(list, 1)
			drawn[id] = nil
		end
	end
	for id, t in pairs(tails) do
		local want = targets(t, phase)
		local list = drawn[id] or {}
		drawn[id] = list
		remove(list, #want + 1)
		for i, w in ipairs(want) do
			local s = list[i]
			if s and not s.obj:get_pos() then
				s = nil
			end
			if not s then
				local obj = core.add_entity(w.pos, "nhv:wormseg")
				if not obj then
					break
				end
				s = {obj = obj, pos = w.pos}
				list[i] = s
			end
			s.pos = vector.add(s.pos, vector.multiply(vector.subtract(w.pos, s.pos), ease))
			-- (every other one a little thinner: rings, and no two faces
			-- in the same place to flicker)
			local wd = math.floor(w.w * (i % 2 == 0 and 0.9 or 1) * 50 + 0.5) / 50
			if s.w ~= wd then
				s.w = wd
				local len = wd * SPACING * OVERLAP
				local h = wd / 2
				s.obj:set_properties({visual_size = {x = wd, y = wd, z = len},
					selectionbox = {-h, -h, -len / 2, h, h, len / 2, rotate = true}})
			end
			if s.tile ~= t.tile then
				s.tile = t.tile
				s.obj:set_properties({textures = textures(t.tile)})
			end
			if s.key ~= w.key then
				s.key = w.key
				local ent = s.obj:get_luaentity()
				if ent then
					ent.nh_key = w.key
				end
			end
		end
		-- facing along the body: from the segment behind it to the one ahead
		for i, s in ipairs(list) do
			local a, b = list[i - 1] or s, list[i + 1] or s
			local dir = vector.subtract(a.pos, b.pos)
			dir.y = 0
			-- (sent only when it's changed: the bends keep most of them moving)
			if vector.length(dir) > 1e-3 then
				local rot = vector.dir_to_rotation(dir)
				if not s.rot or vector.distance(rot, s.rot) > 0.01 then
					s.rot = rot
					s.obj:set_rotation(rot)
				end
			end
			if not s.sent or vector.distance(s.sent, s.pos) > 0.01 then
				s.sent = s.pos
				s.obj:move_to(s.pos, true)
			end
		end
	end
end)

return worms
