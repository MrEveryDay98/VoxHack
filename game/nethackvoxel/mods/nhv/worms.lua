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
-- picture always faces you).
-- Swallowed by one, you're inside its body: NetHack has it on your square
-- (not drawn, mobs.lua); here its head is out ahead of you, the way it
-- last went, you where its body is about your size, and the segments
-- round you your size. Not while you're hallucinating (what a worm
-- looks like then is NetHack's to say), nor in ASCII mode.
local U = nhv.util

local worms = {}
nhv.worms = worms

local BODIES = dofile(core.get_modpath("nhv_tiles") .. "/worm_bodies.lua")
-- (a tail square showing something else - the moment a worm's cut in two,
-- its new head's picture: a tail's all the same)
local TAIL_LOOK
for tile, look in pairs(BODIES.tails) do
	if not TAIL_LOOK or tile < TAIL_LOOK.tile then
		TAIL_LOOK = {tile = tile, look = look}
	end
end
TAIL_LOOK = TAIL_LOOK and TAIL_LOOK.look or {tile = 0}
local WIDTH = 0.9      -- a segment's picture next to the head, for the head's height
local TIP = 0.13       -- at the very end of the tail, for that
local BEHIND = 0.18    -- where it comes out: behind the head's middle, for its height
local LENGTH = 4       -- a body with no tail: how long, for the head's height
local SPACING = 0.45   -- from one segment to the next, for their size
local WAVE = 0.15      -- how far it snakes from side to side (nodes)
local WAVE_LEN = 7     -- (nodes from one bend to the next the same way)
local EASE = 6         -- how quickly segments follow where they're going
local SAMPLES = 8      -- (points along the curve from one square to the next)
local TRAIL_STEP = 0.4 -- (a body with no tail: a point of the way it came every so far)
local TRAIL_KEEP = 20  -- (seconds it keeps its shape out of sight)
local HERO_W = 2.2     -- swallowed: the segments round you (nodes)
local BULGE = 1.5      -- (and how far along it they swell to that)

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

-- the head of the worm you're inside (mobs.lua doesn't draw it: it's on
-- your square)
core.register_entity("nhv:wormhead", {
	initial_properties = {
		visual = "wielditem", wield_item = nhv_tiles.item(0), visual_size = {x = 0.5, y = 0.5, z = 0.5},
		physical = false, pointable = false, static_save = false,
		collisionbox = {0, 0, 0, 0, 0, 0}, shaded = true,
	},
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
-- (which side it's on, for the map's colours: hud.lua)
local function side_of(flags)
	return U.has(flags or 0, U.MON_PET) and "pet" or U.has(flags or 0, U.MON_PEACEFUL) and "peaceful"
		or "monster"
end

local function adjacent(a, b)
	return math.max(math.abs(a.x - b.x), math.abs(a.y - b.y)) == 1
end

local function flat(p)
	return vector.new(p.x, 0, p.z)
end

-- where a head's body comes out: behind its middle (hp, a head h tall),
-- as you see it
local function anchor_at(hp, h, eye)
	local away = vector.subtract(hp, flat(eye))
	local l = vector.length(away)
	if l < 1e-3 then
		return hp
	end
	return vector.add(hp, vector.multiply(away, h * BEHIND / l))
end

local function anchor(head, eye)
	return anchor_at(flat(head.obj:get_pos()), head.h or 2, eye)
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
local function trail_of(id, hp, len, eye)
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
local function bodies(mons, eye, inside, hero_pos)
	local out = {}
	for key, e in pairs(mons) do
		if e.tail_of and e.mon and e.obj:get_pos() then
			local k = math.floor((e.mon.flags or 0) / 2 ^ U.MON_SEG_SHIFT)
			if k > 0 then
				local w = out[e.tail_of] or {segs = {}, last = 0, pieces = {}}
				out[e.tail_of] = w
				w.segs[k] = {p = flat(U.tile_center(e.x, e.y)), k = k, key = key, x = e.x, y = e.y}
				w.last = math.max(w.last, k)
				w.look, w.h = BODIES.tails[e.tile] or w.look or TAIL_LOOK, e.h
			end
		end
	end
	for id, w in pairs(out) do
		local head = mons["id" .. id]
		local cur = nil
		if head and head.obj:get_pos() and w.segs[1] and adjacent(head, w.segs[1]) then
			cur = {{p = anchor(head, eye), k = 0, key = "id" .. id}}
			w.pieces[1] = cur
			w.h, w.head, w.head_e = head.h or w.h, flat(head.obj:get_pos()), head
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
			local t = trail_of(e.id, flat(e.obj:get_pos()), (e.h or 2) * LENGTH, eye)
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
			out[e.id] = {pieces = {piece}, last = 4, look = look, h = e.h, head = flat(e.obj:get_pos()),
				only_looks = true, side = side_of(e.mon.flags), x = e.x, y = e.y, head_e = e}
		end
	end
	-- the one you're inside
	local m = inside
	if m then
		seen[m.id] = true
		local h = nhv.scale.height(m.size, m.mndx)
		local len = h * LENGTH
		-- (you: where it's about your size - that far back from its head)
		local f = math.max(0.15, math.min(0.85, (WIDTH - HERO_W / h) / (WIDTH - TIP)))
		local hp = flat(hero_pos)
		local t = trail_of(m.id, hp, len * (1 - f), eye)
		-- its head ahead of you, the way it last went (not into a wall)
		local dir = t.pts[2] and vector.subtract(t.pts[1], t.pts[2])
		if not dir or vector.length(dir) < 1e-3 then
			dir = vector.subtract(hp, flat(eye))
			if vector.length(dir) < 1e-3 then
				dir = vector.new(0, 0, 1)
			end
		end
		dir = vector.normalize(dir)
		local ahead = 0
		while ahead < len * f and not wall_at(vector.add(hp, vector.multiply(dir, ahead + 0.5))) do
			ahead = ahead + 0.25
		end
		local head = vector.add(hp, vector.multiply(dir, ahead))
		local a = anchor_at(head, h, eye)
		local key = "id" .. m.id
		local piece = {{p = a, k = 0, key = key}}
		local d0 = vector.distance(a, hp)
		piece[2] = {p = hp, k = 4 * f, key = key}
		local d, from = d0, hp
		for i = 2, #t.pts do
			d = d + vector.distance(from, t.pts[i])
			from = t.pts[i]
			piece[#piece + 1] = {p = t.pts[i], k = 4 * math.min(1, f + (1 - f) * (d - d0) / math.max(0.1, len * (1 - f))),
				key = key}
		end
		out[m.id] = {pieces = {piece}, last = 4, look = BODIES.bodies[m.tile], h = h, head = hp,
			bulge = d0, inside_head = {pos = head, tile = m.tile, mndx = m.mndx, h = h},
			only_looks = true, side = side_of(m.flags), x = m.x, y = m.y}
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
	local h = w.h or 2
	for _, piece in ipairs(w.pieces) do
		local c = curve(piece)
		local len = c[#c].d
		local from_head = piece[1].k == 0
		local d = 0
		repeat
			local p, dir, s = along(c, d)
			-- (the head's size next to it, thinner all the way to the tip)
			local f = math.max(0, math.min(1, s.k / math.max(1, w.last)))
			local wd = h * (WIDTH + (TIP - WIDTH) * f)
			-- (swallowed: your size round you)
			if w.bulge and from_head then
				local b = math.max(0, 1 - math.abs(d - w.bulge) / BULGE)
				wd = wd + (HERO_W - wd) * b
			end
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

-- For the maps (hud.lua): every segment drawn, where it is, its size and
-- picture - {key, pos, w, tex} - and the heads they're behind, to draw
-- over them - {key (its mobs.mons key), pos, tile}; the squares a worm
-- covers (NetHack's pictures not drawn there: the segments and head are)
-- - square index -> true; and
-- the squares of the bodies NetHack knows nothing of (worms with no tail),
-- for the small map's colours - square index -> {tex, side} (not the
-- worm's own square).
worms.segments = {}
worms.heads = {}
worms.covered = {}
worms.squares = {}

-- Hurt (or attacking), a worm's sprite flashes (mobs.flash): its whole
-- body with it. worm id -> {kind (nhv_tiles.FLASH), until}
local flashing = {}
function worms.flash(id, kind, secs)
	if id and nhv_tiles.FLASH[kind] then
		flashing[id] = {kind = kind, ["until"] = core.get_us_time() + (secs or 0.15) * 1e6}
	end
end

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

-- what has swallowed you, if it's a worm with a body
local function swallower(snap)
	if not U.has(snap.hero.flags or 0, U.HERO.SWALLOWED) then
		return nil
	end
	for _, m in ipairs(snap.monsters or {}) do
		if U.has(m.flags or 0, U.MON_ENGULFING) and (m.id or 0) > 0 and BODIES.bodies[m.tile] then
			return m
		end
	end
end

-- Are you inside a worm's body now (swallowed by one that has one, drawn)?
-- Then you aren't drawn (avatar.lua), nor, seen from outside you, the
-- engulf frame (holds.lua).
function worms.inside(snap)
	return snap and snap.hero and worms.on(snap) and swallower(snap) ~= nil or false
end

-- its head, out ahead of you: {obj, tile, h}
local inside_head = nil
local function set_inside_head(want)
	if inside_head and not (want and inside_head.obj:get_pos()) then
		if inside_head.obj:get_pos() then
			inside_head.obj:remove()
		end
		inside_head = nil
	end
	if not want then
		return
	end
	local tx, ty = U.pos_to_tile(want.pos)
	local floor = U.in_map(tx, ty) and nhv.terrain.stand_y(tx, ty) or U.STAND_Y
	local pos = vector.new(want.pos.x, nhv.scale.mon_center_y(want.mndx, want.h, floor, U.CEIL_Y - 0.5),
		want.pos.z)
	if not inside_head then
		local obj = core.add_entity(pos, "nhv:wormhead")
		if not obj then
			return
		end
		inside_head = {obj = obj}
	end
	if inside_head.tile ~= want.tile or inside_head.h ~= want.h or inside_head.kind ~= want.kind then
		inside_head.tile, inside_head.h, inside_head.kind = want.tile, want.h, want.kind
		local props = nhv_tiles.look(want.tile, want.h, want.kind)
		props.infotext = "nhv:billboard" -- (facing you: the engine turns it)
		inside_head.obj:set_properties(props)
	end
	inside_head.obj:move_to(pos, true)
end

function worms.clear()
	for id, list in pairs(drawn) do
		remove(list, 1)
		drawn[id] = nil
	end
	trails = {}
	travelled = {}
	set_inside_head(nil)
	worms.segments, worms.heads, worms.covered, worms.squares = {}, {}, {}, {}
end

core.register_globalstep(function(dtime)
	local snap = nhv.nh and nhv.nh.snap
	local mobs = nhv.mobs
	local player = core.get_connected_players()[1]
	if not (snap and mobs and player and worms.on(snap)) then
		worms.clear()
		return
	end
	local inside = swallower(snap)
	-- (you: your body - flying free of the hero in wizard mode, the hero's square)
	local hero_pos = player:get_pos()
	if nhv.wizard and nhv.wizard.detached() and snap.hero.x then
		hero_pos = U.tile_center(snap.hero.x, snap.hero.y)
	end
	local all = bodies(mobs.mons, U.camera_pos(player), inside, hero_pos)
	local now = core.get_us_time()
	for id, f in pairs(flashing) do
		if now >= f["until"] then
			flashing[id] = nil
		end
	end
	local ih = inside and all[inside.id] and all[inside.id].inside_head
	if ih then
		ih.kind = flashing[inside.id] and flashing[inside.id].kind
	end
	set_inside_head(ih)
	for id, list in pairs(drawn) do
		if not all[id] then
			remove(list, 1)
			drawn[id] = nil
			travelled[id] = nil
		end
	end
	local segments, heads, covered, squares = {}, {}, {}, {}
	for id, w in pairs(all) do
		local want = targets(w, phase_of(id, w))
		local tex = texture_of(w.look) .. (flashing[id] and nhv_tiles.FLASH[flashing[id].kind] or "")
		for _, s in pairs(w.segs or {}) do
			covered[U.idx(s.x, s.y)] = true
		end
		local he = w.head_e
		if he and he.obj:get_pos() and he.x then
			covered[U.idx(he.x, he.y)] = true
			heads[#heads + 1] = {key = "id" .. id, pos = he.obj:get_pos(), tile = he.tile}
		end
		if w.only_looks then
			for _, t in ipairs(want) do
				local tx, ty = U.pos_to_tile(t.pos)
				if U.in_map(tx, ty) and not (tx == w.x and ty == w.y) then
					squares[U.idx(tx, ty)] = {tex = texture_of(w.look), side = w.side}
				end
			end
		end
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
			-- (easing to where it goes - the ones by the head at once: lagging,
			-- they'd come out in front of it as you go round it)
			local ease = math.min(1, dtime * EASE * (1 + 8 / i))
			s.pos = vector.add(s.pos, vector.multiply(vector.subtract(t.pos, s.pos), ease))
			local wd = math.floor(t.w * 50 + 0.5) / 50
			if s.w ~= wd then
				s.w = wd
				local h = wd * 0.4
				s.obj:set_properties({visual_size = {x = wd, y = wd},
					selectionbox = {-h, -h, -h, h, h, h}})
			end
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
		for i, s in ipairs(list) do
			segments[#segments + 1] = {key = "wseg" .. id .. "_" .. i, pos = s.pos, w = s.w, tex = s.tex}
			if not s.sent or vector.distance(s.sent, s.pos) > 0.01 then
				s.sent = s.pos
				s.obj:move_to(s.pos, true)
			end
		end
	end
	worms.segments, worms.heads, worms.covered, worms.squares = segments, heads, covered, squares
end)

return worms
