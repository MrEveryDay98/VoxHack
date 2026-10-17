-- Continuous monster movement.
--
-- Every monster on the level has a real position here. NetHack decides
-- what monsters want (fight, flee, follow, use items, cast) and rolls the
-- dice; this module moves their bodies:
--   * a hostile monster that can see you walks straight at you,
--   * one that can't follows a path over the map squares toward where it
--     thinks you are,
--   * pets follow you and go after nearby hostiles, peacefuls wander.
-- When a body crosses into another square NetHack is told
-- (core.nh_move_monster), which handles doors, traps and items and may
-- refuse the square (it's occupied, too narrow, ...).
--
-- Each step we also report who can reach the hero in melee; NetHack uses
-- that instead of "adjacent on the grid" when monsters take their turns.

local U = nhv.util
local nh = nhv.nh
local scale = nhv.scale

local sim = {
	mons = {},        -- id -> monster body
	dirty = false,    -- a monster changed squares (refresh the display)
}
nhv.sim = sim

local TILE = U.TILE
sim.HERO_R = 0.35        -- hero body radius (nodes)
sim.REACH = 0.6          -- melee reach beyond touching (nodes)
local REPATH = 1.5       -- turns between path recomputations
local MF = {
	TAME = 0x001, PEACEFUL = 0x002, FLEE = 0x004, CANMOVE = 0x008,
	SEES_U = 0x010, GRID = 0x020, VISIBLE = 0x040, CONFUSED = 0x080,
	HIDER = 0x100, HIDDEN = 0x200, KEEPAWAY = 0x400, ASLEEP = 0x800,
}
sim.MF = MF

local function has(f, b) return U.has(f, b) end

local function hero_pos()
	local p = nhv.player.get()
	return p and p:get_pos()
end

local function flat_dist(a, b)
	local dx, dz = a.x - b.x, a.z - b.z
	return math.sqrt(dx * dx + dz * dz)
end

-- ---------------------------------------------------------------- terrain
local function square_passable(map, tx, ty)
	if not U.in_map(tx, ty) then
		return false
	end
	local typ = map.typ[U.idx(tx, ty)]
	local T = U.TYP
	-- walls, stone, trees, bars, lava walls; water and closed doors are
	-- left for NetHack to decide when the monster tries to enter
	return not (typ < T.POOL or typ == T.IRONBARS or typ == T.LAVAWALL)
end

local function is_door(map, tx, ty)
	return U.in_map(tx, ty) and map.typ[U.idx(tx, ty)] == U.TYP.DOOR
end

-- does a body of radius r at p overlap a square it can't stand in?
local function hits_terrain(e, map, p, r)
	for _, ox in ipairs({-r, r}) do
		for _, oz in ipairs({-r, r}) do
			local tx, ty = U.pos_to_tile(vector.new(p.x + ox, 0, p.z + oz))
			if not square_passable(map, tx, ty) then
				return true
			end
			local b = e.blocked[tx * 32 + ty]
			if b and b > nhv.clock.game then
				return true
			end
		end
	end
	return false
end

-- ---------------------------------------------------------------- sync
local function center_of(x, y)
	local c = U.tile_center(x, y)
	return vector.new(c.x, 0, c.z)
end

-- Bring our bodies in line with NetHack's list of monsters.
function sim.sync()
	local all = core.nh_get_all_monsters() or {}
	local seen = {}
	for _, m in ipairs(all) do
		seen[m.id] = true
		local e = sim.mons[m.id]
		if not e then
			e = {id = m.id, pos = center_of(m.x, m.y), blocked = {},
				path = nil, repath = 0, wander = nil}
			sim.mons[m.id] = e
		elseif e.x ~= m.x or e.y ~= m.y then
			-- NetHack moved it itself (teleport, displacement, dodging, a grid
			-- mover): a step to the next square glides there, a jump snaps
			local adj = math.abs(e.x - m.x) <= 1 and math.abs(e.y - m.y) <= 1
			if adj then
				e.glide = center_of(m.x, m.y)
			else
				e.pos = center_of(m.x, m.y)
				e.glide = nil
			end
			e.path = nil
		end
		e.x, e.y = m.x, m.y
		e.mndx, e.size, e.speed, e.flags = m.mndx, m.size, m.speed, m.flags
		e.mux, e.muy = m.mux, m.muy
		-- took damage since last time: flash red
		if e.hp and m.hp and m.hp < e.hp and nhv.mobs then
			nhv.mobs.flash(m.id, "r", 0.22)
		end
		e.hp = m.hp
		e.r = scale.radius(m.size, m.mndx)
	end
	for id in pairs(sim.mons) do
		if not seen[id] then
			sim.mons[id] = nil
		end
	end
end

-- ---------------------------------------------------------------- moving
-- try to move body e by (dx, dz) nodes; returns true if it moved
local function try_move(e, map, dx, dz, hp)
	local np = vector.new(e.pos.x + dx, 0, e.pos.z + dz)
	if hits_terrain(e, map, np, e.r) then
		return false
	end
	-- other bodies (and the hero) are solid
	if hp and flat_dist(np, hp) < e.r + sim.HERO_R
			and flat_dist(np, hp) < flat_dist(e.pos, hp) then
		return false
	end
	for _, o in pairs(sim.mons) do
		if o ~= e then
			local d = flat_dist(np, o.pos)
			if d < e.r + o.r and d < flat_dist(e.pos, o.pos) then
				return false
			end
		end
	end
	local tx, ty = U.pos_to_tile(np)
	local h = nh.snap and nh.snap.hero
	if tx ~= e.x or ty ~= e.y then
		if math.abs(tx - e.x) > 1 or math.abs(ty - e.y) > 1 then
			return false
		end
		-- your square: its body may come in to reach you (as yours may go
		-- into a monster's), while in NetHack it stays on its own square,
		-- next to yours. Other monsters' squares it keeps out of.
		if h and tx == h.x and ty == h.y then
			e.pos = np
			return true
		end
		local r = core.nh_move_monster(e.id, tx, ty)
		if r == 1 then
			e.x, e.y = tx, ty
			sim.dirty = true
		elseif r == -2 or r == -3 then
			-- NetHack is busy, or someone stands there: wait at the edge
			-- (not a wall: the path stays)
			return false
		else
			-- refused: treat that square as a wall for a while
			e.blocked[tx * 32 + ty] = nhv.clock.game + 2
			e.path = nil
			if r < 0 then
				sim.dirty = true
			end
			return false
		end
	end
	e.pos = np
	return true
end

-- move toward a point, sliding along walls
local function move_toward(e, map, target, dist, stop, hp)
	local d = flat_dist(e.pos, target)
	if d <= (stop or 0.05) then
		return
	end
	local step = math.min(dist, d - (stop or 0))
	local ux, uz = (target.x - e.pos.x) / d, (target.z - e.pos.z) / d
	if not try_move(e, map, ux * step, uz * step, hp) then
		if math.abs(ux) > 0.2 and try_move(e, map, U.sign(ux) * step, 0, hp) then
			return
		end
		if math.abs(uz) > 0.2 then
			try_move(e, map, 0, U.sign(uz) * step, hp)
		end
	end
end

-- a boulder sits there (monsters don't push them: a path goes round)
local function boulder_at(x, y)
	local o = nhv.mobs and nhv.mobs.objs[U.idx(x, y)]
	return o and o.boulder
end

-- follow a square path toward goal square gx, gy
local function follow_path(e, map, gx, gy, dist, hp)
	local now = nhv.clock.game
	if not e.path or e.path_goal ~= gx * 32 + gy or now > e.repath then
		e.path = nhv.path.find(e.x, e.y, gx, gy,
			function(x, y) return square_passable(map, x, y)
				and not (e.blocked[x * 32 + y] and e.blocked[x * 32 + y] > now)
				and not boulder_at(x, y) end,
			function(x, y) return is_door(map, x, y) end)
		e.path_goal = gx * 32 + gy
		e.repath = now + REPATH
	end
	if not e.path or #e.path == 0 then
		return false
	end
	local wp = center_of(e.path[1].x, e.path[1].y)
	if e.x == e.path[1].x and e.y == e.path[1].y and flat_dist(e.pos, wp) < 0.9 then
		table.remove(e.path, 1)
		if #e.path == 0 then
			return true
		end
		wp = center_of(e.path[1].x, e.path[1].y)
	end
	move_toward(e, map, wp, dist, 0, hp)
	return true
end

local function wander(e, map, dist, hp)
	local now = nhv.clock.game
	if not e.wander or now > e.wander.t_end then
		for _ = 1, 8 do
			local gx, gy = e.x + math.random(-4, 4), e.y + math.random(-3, 3)
			if square_passable(map, gx, gy) then
				e.wander = {x = gx, y = gy, t_end = now + 4 + math.random() * 4}
				break
			end
		end
		if not e.wander then
			return
		end
	end
	if e.x == e.wander.x and e.y == e.wander.y then
		return -- idle until it's time to pick somewhere else
	end
	follow_path(e, map, e.wander.x, e.wander.y, dist * 0.6, hp)
end

-- nearest hostile monster to e within `within` nodes
local function nearest_hostile(e, within)
	local best, bd
	for _, o in pairs(sim.mons) do
		if o ~= e and not has(o.flags, MF.TAME) and not has(o.flags, MF.PEACEFUL) then
			local d = flat_dist(e.pos, o.pos)
			if d <= within and (not bd or d < bd) then
				best, bd = o, d
			end
		end
	end
	return best, bd
end

-- one monster's movement for this step
local function think(e, map, dturns, hp, hero)
	e.target = nil
	if e.glide then
		-- NetHack already put it there: slide straight in, quickly (at
		-- least a square per turn), through anything in the way
		local d = flat_dist(e.pos, e.glide)
		local step = math.min(d, math.max((e.speed or 12) / 12, 1.5) * dturns * TILE)
		if d > 0 then
			e.pos = vector.add(e.pos, vector.multiply(vector.direction(e.pos, e.glide), step))
			e.pos.y = 0
		end
		if flat_dist(e.pos, e.glide) < 0.05 then
			e.pos, e.glide = e.glide, nil
		end
		return
	end
	if not has(e.flags, MF.CANMOVE) or has(e.flags, MF.HIDDEN) then
		return
	end
	local dist = (e.speed or 12) / 12 * dturns * TILE
	if dist <= 0 then
		return
	end
	if has(e.flags, MF.GRID) then
		return
	end
	if has(e.flags, MF.CONFUSED) and math.random() < 0.5 then
		local a = math.random() * math.pi * 2
		try_move(e, map, math.cos(a) * dist, math.sin(a) * dist, hp)
		return
	end
	local touch = e.r + sim.HERO_R
	if has(e.flags, MF.TAME) then
		local foe, fd = nearest_hostile(e, 4 * TILE)
		if foe then
			if fd <= e.r + foe.r + sim.REACH then
				e.target = foe.id
			else
				move_toward(e, map, foe.pos, dist, e.r + foe.r + sim.REACH * 0.6, hp)
			end
			return
		end
		if hp and flat_dist(e.pos, hp) > 2.2 * TILE then
			if not follow_path(e, map, hero.x, hero.y, dist, hp) then
				move_toward(e, map, hp, dist, touch + 1.0, hp)
			end
		end
		return
	end
	if has(e.flags, MF.PEACEFUL) then
		wander(e, map, dist, hp)
		return
	end
	if has(e.flags, MF.FLEE) and hp then
		local away = vector.add(e.pos, vector.multiply(vector.direction(hp, e.pos), 3))
		move_toward(e, map, away, dist, 0, hp)
		return
	end
	if has(e.flags, MF.SEES_U) and hp and has(e.flags, MF.KEEPAWAY) then
		-- archers and the like hang back, between about 2.5 and 4.5 squares
		local d = flat_dist(e.pos, hp)
		if d < 2.5 * TILE then
			local away = vector.add(e.pos, vector.multiply(vector.direction(hp, e.pos), 3))
			move_toward(e, map, away, dist, 0, hp)
		elseif d > 4.5 * TILE then
			move_toward(e, map, hp, dist, 4 * TILE, hp)
		end
		return
	end
	if has(e.flags, MF.SEES_U) and hp then
		local stop = touch + sim.REACH * 0.6
		if (e.stuck or 0) < 1 then
			-- straight at you...
			local before = e.pos
			move_toward(e, map, hp, dist, stop, hp)
			if e.pos == before and flat_dist(e.pos, hp) > stop + 0.1 then
				e.stuck = (e.stuck or 0) + dturns
			else
				e.stuck = 0
			end
			return
		end
		-- ...unless that got nowhere (a boulder, a pillar in between):
		-- round by the squares for a while, or, with no way round, wander
		-- (as NetHack's monsters do) instead of pressing against it
		e.detour = (e.detour or 0) + dturns
		if e.detour > 6 then
			e.stuck, e.detour = 0, 0 -- (try straight at you again)
		end
		if not follow_path(e, map, hero.x, hero.y, dist, hp) then
			wander(e, map, dist, hp)
		end
		return
	end
	if e.mux and e.mux > 0 and not (e.x == e.mux and e.y == e.muy) then
		if follow_path(e, map, e.mux, e.muy, dist, hp) then
			return
		end
	end
	wander(e, map, dist, hp)
end

-- Move everything by dturns of game time.
function sim.update(dturns)
	local snap = nh.snap
	if not snap or dturns <= 0 then
		return
	end
	local hp = hero_pos()
	local hero = snap.hero
	for _, e in pairs(sim.mons) do
		think(e, snap.map, dturns, hp, hero)
	end
end

-- is the way from a to b clear of walls (no reaching round a corner)?
local function clear_line(map, a, b)
	local d = flat_dist(a, b)
	local n = math.max(1, math.ceil(d / 0.5))
	for k = 1, n - 1 do
		local p = vector.new(a.x + (b.x - a.x) * k / n, 0, a.z + (b.z - a.z) * k / n)
		local tx, ty = U.pos_to_tile(p)
		if not square_passable(map, tx, ty) then
			return false
		end
	end
	return true
end

-- Tell NetHack who can reach the hero / what pets are fighting: a body
-- close enough to touch you plus an arm's reach (REACH), with nothing
-- solid in between - not merely in the next square.
function sim.push_states()
	local hp = hero_pos()
	local map = nh.snap and nh.snap.map
	local states = {}
	for id, e in pairs(sim.mons) do
		local reach = hp and flat_dist(e.pos, hp) <= e.r + sim.HERO_R + sim.REACH
			and (not map or clear_line(map, e.pos, hp))
		states[#states + 1] = {id = id, in_reach = reach and true or false, target = e.target or 0}
	end
	core.nh_set_monstates(states)
end

-- body for a monster id (for rendering)
function sim.body(id)
	return sim.mons[id]
end

function sim.clear()
	sim.mons = {}
end

return sim
