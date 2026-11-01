-- Worms' bodies: segments snaking along behind their heads, each the long
-- worm tail's picture facing you (nhv_tiles/worm_bodies.lua:
-- tools/make_worm_bodies.py - for worms of other colours, a copy of it in
-- theirs).
--  * A long worm's body is its tail: NetHack shows it as a tail picture on
--    every square it covers; here the segments run from the head through
--    those squares, in order, to the tail's end. The squares' own pictures
--    are hidden meanwhile (mobs.lua); hitting a segment hits the tail on
--    its square.
--  * Other worms (purple worms, the babies) have no tail in NetHack: their
--    bodies only follow them, along the way they came, and are only for
--    looking at (hitting one hits the worm).
-- The body comes out from behind the head as you see it (the head's
-- picture always faces you). Not while you're hallucinating (what a worm
-- looks like then is NetHack's to say), nor in ASCII mode.
local U = nhv.util

local worms = {}
nhv.worms = worms

local BODIES = dofile(core.get_modpath("nhv_tiles") .. "/worm_bodies.lua")
local WIDTH = 0.26     -- a segment's picture next to the head, for the head's height
local TIP = 0.5        -- at the very end, for that
local BEHIND = 0.18    -- where it comes out: behind the head's middle, for its height
local LENGTH = 1.5     -- a body with no tail: how long, for the head's height
local SPACING = 0.45   -- from one segment to the next, for their size
local WAVE = 0.15      -- how far it snakes from side to side (nodes)
local WAVE_LEN = 7     -- (nodes from one bend to the next the same way)
local EASE = 6         -- how quickly segments follow where they're going
local SAMPLES = 8      -- (points along the curve from one square to the next)
local TRAIL_STEP = 0.4 -- (a body with no tail: a point of the way it came every so far)
local TRAIL_KEEP = 20  -- (seconds it keeps its shape out of sight)

-- a segment: its picture, facing you
core.register_entity("nhv:wormseg", {
	initial_properties = {
		visual = "sprite", textures = {"blank.png"},
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

-- drawn as bodies now (else as NetHack's pictures, square by square)
function worms.on(snap)
	return not nhv_tiles.ascii and not (snap and snap.hero and U.has(snap.hero.flags, U.HERO.HALLU))
end

-- a segment's picture: a NetHack tile's (the tail's), or a recoloured copy
local function texture_of(look)
	return look.texture or nhv_tiles.texture(look.tile)
end

-- ---------------------------------------------------------------- the bodies
local function adjacent(a, b)
	return math.max(math.abs(a.x - b.x), math.abs(a.y - b.y)) == 1
end

local function flat(p)
	return vector.new(p.x, 0, p.z)
end

-- where a head's body comes out: behind its middle, as you see it
local function anchor(head, eye)
	local hp = flat(head.obj:get_pos())
	local away = vector.subtract(hp, flat(eye))
	local l = vector.length(away)
	if l < 1e-3 then
		return hp
	end
	return vector.add(hp, vector.multiply(away, (head.h or 2) * BEHIND / l))
end

-- (is there a wall at (x, z), a block above the floor?)
local function wall_at(p)
	local tx, ty = U.pos_to_tile(p)
	if not U.in_map(tx, ty) then
		return true
	end
	local def = core.registered_nodes[core.get_node(vector.new(math.floor(p.x + 0.5),
		nhv.terrain.stand_y(tx, ty) + 0.5, math.floor(p.z + 0.5))).name]
	return def and def.walkable or false
end

-- A body with no tail: the way its worm came, newest first, as long as
-- the body. New (or the worm gone somewhere else at once): laid out
-- straight back from it, away from you and off to one side if there's
-- room, else the way with most room.
local trails = {} -- worm id -> {pts, len}
local function trail_of(id, head, eye)
	local hp = flat(head.obj:get_pos())
	local len = (head.h or 2) * LENGTH
	local t = trails[id]
	if t and vector.distance(t.pts[1], hp) > 3 * U.TILE then
		t = nil
	end
	if not t then
		local away = vector.subtract(hp, flat(eye))
		local base = math.atan2(away.z, away.x)
		local best, best_room = nil, -1
		-- (away from you and off to one side first - straight away, the head
		-- would hide it - then turning either way)
		for _, turn in ipairs({60, -60, 90, -90, 30, -30, 120, -120, 0, 180}) do
			local a = base + math.rad(turn)
			local dir = vector.new(math.cos(a), 0, math.sin(a))
			local room = 0
			while room < len and not wall_at(vector.add(hp, vector.multiply(dir, room + 0.5))) do
				room = room + 0.5
			end
			if room > best_room + 0.5 then
				best, best_room = dir, room
			end
			if room >= len then
				break
			end
		end
		t = {pts = {}, len = len}
		for d = 0, len, TRAIL_STEP do
			t.pts[#t.pts + 1] = vector.add(hp, vector.multiply(best, math.min(d, best_room)))
		end
		trails[id] = t
	end
	t.len = len
	if vector.distance(t.pts[1], hp) >= TRAIL_STEP then
		table.insert(t.pts, 1, hp)
	else
		t.pts[1] = hp
	end
	-- (as long as the body, no longer)
	local d = 0
	for i = 2, #t.pts do
		d = d + vector.distance(t.pts[i - 1], t.pts[i])
		if d > len then
			for j = #t.pts, i + 1, -1 do
				t.pts[j] = nil
			end
			break
		end
	end
	return t
end

-- Each worm's body as pieces: runs of points one after another (for a
-- tail, a square not seen breaks it), the first from behind its head if
-- that's seen. A point: {p = where (x, z), k = how far along (0: the
-- head; for a tail, its place in it), key = the mobs.mons key it hits}.
-- Each worm: {pieces, last (k at its end), look (worm_bodies.lua), h}.
local function bodies(mons, eye)
	local out = {}
	for key, e in pairs(mons) do
		if e.tail_of and e.mon and e.obj:get_pos() then
			local k = math.floor((e.mon.flags or 0) / 2 ^ U.MON_SEG_SHIFT)
			if k > 0 then
				local w = out[e.tail_of] or {segs = {}, last = 0, pieces = {}}
				out[e.tail_of] = w
				w.segs[k] = {p = flat(U.tile_center(e.x, e.y)), k = k, key = key, x = e.x, y = e.y}
				w.last = math.max(w.last, k)
				w.look, w.h = BODIES.tails[e.tile] or {tile = e.tile}, e.h
			end
		end
	end
	for id, w in pairs(out) do
		local head = mons["id" .. id]
		local cur = nil
		if head and head.obj:get_pos() and w.segs[1] and adjacent(head, w.segs[1]) then
			cur = {{p = anchor(head, eye), k = 0, key = "id" .. id}}
			w.pieces[1] = cur
			w.h, w.head = head.h or w.h, flat(head.obj:get_pos())
		end
		for k = 1, w.last do
			local s = w.segs[k]
			if not s then
				cur = nil
			else
				if not (cur and (cur[1].k == 0 and #cur == 1 or adjacent(cur[#cur], s))) then
					cur = {}
					w.pieces[#w.pieces + 1] = cur
				end
				cur[#cur + 1] = s
			end
		end
	end
	-- the worms with no tail
	local seen = {}
	for key, e in pairs(mons) do
		local look = e.id and e.mon and BODIES.bodies[e.tile]
		-- (not one only sensed, unseen, nor a black shape in the dark)
		if look and e.obj:get_pos() and not (e.silhouette or e.fuzz or U.has(e.mon.flags or 0, U.MON_UNSEEN)) then
			seen[e.id] = true
			local t = trail_of(e.id, e, eye)
			local piece = {{p = anchor(e, eye), k = 0, key = key}}
			local d, from = 0, nil
			for _, p in ipairs(t.pts) do
				d = d + (from and vector.distance(from, p) or 0)
				from = p
				-- (from behind the head on)
				if d > (e.h or 2) * BEHIND then
					piece[#piece + 1] = {p = p, k = 4 * d / t.len, key = key}
				end
			end
			out[e.id] = {pieces = {piece}, last = 4, look = look, h = e.h, head = flat(e.obj:get_pos())}
		end
	end
	-- (one out of sight a while keeps its body's shape: back in sight
	-- where it was, it isn't laid out afresh)
	local now = core.get_us_time()
	for id, t in pairs(trails) do
		if seen[id] then
			t.seen = now
		elseif now - (t.seen or now) > TRAIL_KEEP * 1e6 then
			trails[id] = nil
		end
	end
	return out
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

-- where each segment of a worm goes now: {pos, w, key}
local function targets(w, phase)
	local out = {}
	local w0 = (w.h or 2) * WIDTH
	for _, piece in ipairs(w.pieces) do
		local c = curve(piece)
		local len = c[#c].d
		local from_head = piece[1].k == 0
		local d = 0
		repeat
			local p, dir, s = along(c, d)
			-- (thinner over the last two squares' worth, to a point)
			local f = math.max(0, math.min(1, (s.k - (w.last - 2)) / 2))
			local wd = w0 * (1 + (TIP - 1) * f)
			-- (snaking from side to side - not where it leaves the head)
			local l = vector.length(dir)
			if l > 1e-4 then
				local side = vector.new(-dir.z / l, 0, dir.x / l)
				local reach = from_head and math.min(1, d / 1.5) or 1
				p = vector.add(p, vector.multiply(side, WAVE * reach * math.sin(phase - d * 2 * math.pi / WAVE_LEN)))
			end
			local tx, ty = U.pos_to_tile(p)
			local floor = U.in_map(tx, ty) and nhv.terrain.stand_y(tx, ty) or U.STAND_Y
			out[#out + 1] = {pos = vector.new(p.x, floor + wd / 2, p.z), w = wd, key = s.key}
			d = d + wd * SPACING
		until d > len + 1e-3
	end
	return out
end

-- ---------------------------------------------------------------- drawing
local drawn = {} -- worm id -> list of {obj, pos, w, tex, key, sent}

-- The bends: they move down the body only as the worm goes - each stays
-- where it is on the floor while the body slides through it, as a snake's
-- do; a worm standing still lies still. (How far each has gone.)
local travelled = {} -- worm id -> {at, d}
local function phase_of(id, w)
	local t = travelled[id]
	if not w.head then
		return t and t.d * 2 * math.pi / WAVE_LEN or 0
	end
	if not t then
		t = {at = w.head, d = 0}
		travelled[id] = t
	end
	local step = vector.distance(t.at, w.head)
	t.at = w.head
	if step < U.TILE then -- (not a jump: teleported)
		t.d = t.d + step
	end
	return t.d * 2 * math.pi / WAVE_LEN
end

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
	trails = {}
	travelled = {}
end

core.register_globalstep(function(dtime)
	local snap = nhv.nh and nhv.nh.snap
	local mobs = nhv.mobs
	local player = core.get_connected_players()[1]
	if not (snap and mobs and player and worms.on(snap)) then
		worms.clear()
		return
	end
	local all = bodies(mobs.mons, U.camera_pos(player))
	local ease = math.min(1, dtime * EASE)
	for id, list in pairs(drawn) do
		if not all[id] then
			remove(list, 1)
			drawn[id] = nil
			travelled[id] = nil
		end
	end
	for id, w in pairs(all) do
		local want = targets(w, phase_of(id, w))
		local list = drawn[id] or {}
		drawn[id] = list
		remove(list, #want + 1)
		for i, t in ipairs(want) do
			local s = list[i]
			if s and not s.obj:get_pos() then
				s = nil
			end
			if not s then
				local obj = core.add_entity(t.pos, "nhv:wormseg")
				if not obj then
					break
				end
				s = {obj = obj, pos = t.pos}
				list[i] = s
			end
			s.pos = vector.add(s.pos, vector.multiply(vector.subtract(t.pos, s.pos), ease))
			local wd = math.floor(t.w * 50 + 0.5) / 50
			if s.w ~= wd then
				s.w = wd
				local h = wd * 0.4
				s.obj:set_properties({visual_size = {x = wd, y = wd},
					selectionbox = {-h, -h, -h, h, h, h}})
			end
			local tex = texture_of(w.look)
			if s.tex ~= tex then
				s.tex = tex
				s.obj:set_properties({textures = {tex}})
			end
			if s.key ~= t.key then
				s.key = t.key
				local ent = s.obj:get_luaentity()
				if ent then
					ent.nh_key = t.key
				end
			end
		end
		-- (sent only when it's moved: most of them keep moving)
		for _, s in ipairs(list) do
			if not s.sent or vector.distance(s.sent, s.pos) > 0.01 then
				s.sent = s.pos
				s.obj:move_to(s.pos, true)
			end
		end
	end
end)

return worms
