-- A* over NetHack's map squares, for monsters that can't see the hero.

local U = nhv.util
local path = {}
nhv.path = path

local DIRS = {
	{1, 0}, {-1, 0}, {0, 1}, {0, -1},
	{1, 1}, {1, -1}, {-1, 1}, {-1, -1},
}

-- passable(x, y) -> bool, is_door(x, y) -> bool
-- Returns a list of {x, y} squares from the one after start to goal, or nil.
-- squeeze: diagonal steps between two blocked squares are allowed (the
-- hero can squeeze past a corner, a boulder...; monsters can't)
function path.find(sx, sy, gx, gy, passable, is_door, max_nodes, squeeze)
	if sx == gx and sy == gy then
		return {}
	end
	max_nodes = max_nodes or 1500
	local function key(x, y) return x * 32 + y end
	local open = {{x = sx, y = sy, g = 0, f = 0}}
	local came, gscore = {}, {[key(sx, sy)] = 0}
	local closed = {}
	local expanded = 0
	while #open > 0 do
		-- pop lowest f (lists are small)
		local bi = 1
		for i = 2, #open do
			if open[i].f < open[bi].f then
				bi = i
			end
		end
		local cur = table.remove(open, bi)
		local ck = key(cur.x, cur.y)
		if cur.x == gx and cur.y == gy then
			local out = {}
			local k = ck
			while came[k] do
				table.insert(out, 1, {x = math.floor(k / 32), y = k % 32})
				k = came[k]
			end
			return out
		end
		if not closed[ck] then
			closed[ck] = true
			expanded = expanded + 1
			if expanded > max_nodes then
				return nil
			end
			for _, d in ipairs(DIRS) do
				local nx, ny = cur.x + d[1], cur.y + d[2]
				local nk = key(nx, ny)
				local ok = not closed[nk] and U.in_map(nx, ny)
					and (passable(nx, ny) or (nx == gx and ny == gy))
				if ok and d[1] ~= 0 and d[2] ~= 0 then
					-- no squeezing past corners or diagonally through doorways
					ok = (squeeze or (passable(cur.x + d[1], cur.y) and passable(cur.x, cur.y + d[2])))
						and not is_door(cur.x, cur.y) and not is_door(nx, ny)
				end
				if ok then
					local g = cur.g + ((d[1] ~= 0 and d[2] ~= 0) and 1.4 or 1)
					if not gscore[nk] or g < gscore[nk] then
						gscore[nk] = g
						came[nk] = ck
						local h = math.max(math.abs(gx - nx), math.abs(gy - ny))
						open[#open + 1] = {x = nx, y = ny, g = g, f = g + h}
					end
				end
			end
		end
	end
	return nil
end

-- ---------------------------------------------------------------- bodies
-- The way a body walks through squares block by block (travel: the hero's
-- body walking NetHack's route after it - player.lua). Only the squares'
-- blocks a body can stand in count - nothing solid at its height: not a
-- wall, a door's blocks, rock left at a corner -, and those beside
-- something solid cost more (it keeps to the middle of a corridor); the
-- shortest way from where it is to the last square's spot is rounded off
-- where it turns, as far as that keeps it clear of anything solid.
-- squares: {x=, y=} in order (where it is first); heights: square index ->
-- the height a body stands at there. A list of points (each at its
-- square's height), or nil if there's no way.
local BODY = 0.3 -- (half a body's width: what it keeps clear by)
local function key(nx, nz)
	return nx * 1000 + nz
end

function path.body_route(squares, from, to, heights)
	-- the squares it may walk in: the route's, and those beside them (the
	-- corner gaps left for going diagonally are in those), at the height
	-- of the route's square they're beside
	local height = {}
	for _, s in ipairs(squares) do
		height[U.idx(s.x, s.y)] = heights[U.idx(s.x, s.y)]
	end
	for _, s in ipairs(squares) do
		for dx = -1, 1 do
			for dy = -1, 1 do
				local x, y = s.x + dx, s.y + dy
				if U.in_map(x, y) and not height[U.idx(x, y)] then
					height[U.idx(x, y)] = heights[U.idx(s.x, s.y)]
				end
			end
		end
	end
	local free_cache = {}
	local function free(nx, nz)
		local k = key(nx, nz)
		local f = free_cache[k]
		if f == nil then
			local tx, ty = U.pos_to_tile(vector.new(nx, 0, nz))
			local h = U.in_map(tx, ty) and height[U.idx(tx, ty)]
			f = false
			if h then
				f = true
				for _, y in ipairs({math.floor(h + 1), math.floor(h + 2)}) do
					local def = core.registered_nodes[core.get_node(vector.new(nx, y, nz)).name]
					if not def or def.walkable then
						f = false
					end
				end
			end
			free_cache[k] = f
		end
		return f
	end
	local function round(v)
		return math.floor(v + 0.5)
	end
	-- (the blocks it starts and ends in - or the nearest free ones)
	local function nearest(p)
		local bx, bz = round(p.x), round(p.z)
		if free(bx, bz) then
			return bx, bz
		end
		for _, d in ipairs(DIRS) do
			if free(bx + d[1], bz + d[2]) then
				return bx + d[1], bz + d[2]
			end
		end
	end
	local sx, sz = nearest(from)
	local gx, gz = nearest(to)
	if not (sx and gx) then
		return nil
	end
	-- A* over the blocks (a heap: a route across the level has thousands)
	local function crowded(nx, nz)
		for _, d in ipairs(DIRS) do
			if not free(nx + d[1], nz + d[2]) then
				return true
			end
		end
		return false
	end
	local heap = {}
	local function push(f, k)
		heap[#heap + 1] = {f, k}
		local i = #heap
		while i > 1 do
			local up = math.floor(i / 2)
			if heap[up][1] <= heap[i][1] then
				break
			end
			heap[up], heap[i] = heap[i], heap[up]
			i = up
		end
	end
	local function pop()
		local top = heap[1]
		local last = table.remove(heap)
		if #heap > 0 then
			heap[1] = last
			local i = 1
			while true do
				local l, r, m = 2 * i, 2 * i + 1, i
				if heap[l] and heap[l][1] < heap[m][1] then
					m = l
				end
				if heap[r] and heap[r][1] < heap[m][1] then
					m = r
				end
				if m == i then
					break
				end
				heap[m], heap[i] = heap[i], heap[m]
				i = m
			end
		end
		return top[2]
	end
	local function hdist(nx, nz)
		local dx, dz = math.abs(nx - gx), math.abs(nz - gz)
		return math.max(dx, dz) + 0.414 * math.min(dx, dz)
	end
	local g, came, done = {[key(sx, sz)] = 0}, {}, {}
	push(hdist(sx, sz), key(sx, sz))
	local found = false
	local expanded = 0
	while #heap > 0 and expanded < 20000 do
		local k = pop()
		if not done[k] then
			done[k] = true
			expanded = expanded + 1
			local nx, nz = math.floor(k / 1000), k % 1000
			if nx == gx and nz == gz then
				found = true
				break
			end
			for _, d in ipairs(DIRS) do
				local mx, mz = nx + d[1], nz + d[2]
				local diag = d[1] ~= 0 and d[2] ~= 0
				-- (no cutting a solid block's corner going diagonally)
				if free(mx, mz) and not (diag and not (free(nx + d[1], nz) and free(nx, nz + d[2]))) then
					local mk = key(mx, mz)
					local cost = g[k] + (diag and 1.414 or 1) + (crowded(mx, mz) and 0.6 or 0)
					if not done[mk] and (not g[mk] or cost < g[mk]) then
						g[mk] = cost
						came[mk] = k
						push(cost + hdist(mx, mz), mk)
					end
				end
			end
		end
	end
	if not found then
		return nil
	end
	local blocks = {}
	local k = key(gx, gz)
	while k do
		table.insert(blocks, 1, {x = math.floor(k / 1000), z = k % 1000})
		k = came[k]
	end
	-- the line: from where it is, through the blocks' middles, to the spot
	local pts = {{x = from.x, z = from.z}}
	for i = 2, #blocks - 1 do
		pts[#pts + 1] = blocks[i]
	end
	pts[#pts + 1] = {x = to.x, z = to.z}
	-- (straight runs one line: the corners rounded off over a longer way)
	local runs = {pts[1]}
	for i = 2, #pts - 1 do
		local a, b, c = runs[#runs], pts[i], pts[i + 1]
		local cross = (b.x - a.x) * (c.z - b.z) - (b.z - a.z) * (c.x - b.x)
		if math.abs(cross) > 0.01 then
			runs[#runs + 1] = b
		end
	end
	runs[#runs + 1] = pts[#pts]
	pts = runs
	-- (is a body clear of anything solid all the way from a to b?)
	local function clear(a, b)
		local len = math.sqrt((b.x - a.x) ^ 2 + (b.z - a.z) ^ 2)
		local n = math.max(1, math.ceil(len / 0.2))
		for i = 0, n do
			local x, z = a.x + (b.x - a.x) * i / n, a.z + (b.z - a.z) * i / n
			for _, c in ipairs({{-BODY, -BODY}, {BODY, -BODY}, {-BODY, BODY}, {BODY, BODY}}) do
				if not free(round(x + c[1]), round(z + c[2])) then
					return false
				end
			end
		end
		return true
	end
	-- rounded off at its turns: each corner cut off some way along both
	-- its sides - as far as keeps clear (else less; else the corner stays)
	-- - then the new corners again, less each time
	local function towards(a, b, d)
		local len = math.sqrt((b.x - a.x) ^ 2 + (b.z - a.z) ^ 2)
		local f = len > 0 and math.min(0.45, d / len) or 0
		return {x = a.x + (b.x - a.x) * f, z = a.z + (b.z - a.z) * f}
	end
	for _, cuts in ipairs({{1.5, 1.0, 0.6, 0.35}, {0.5, 0.3}, {0.25, 0.15}}) do
		local out = {pts[1]}
		for i = 2, #pts - 1 do
			local cut = false
			for _, d in ipairs(cuts) do
				local p, q = towards(pts[i], pts[i - 1], d), towards(pts[i], pts[i + 1], d)
				if clear(p, q) then
					out[#out + 1] = p
					out[#out + 1] = q
					cut = true
					break
				end
			end
			if not cut then
				out[#out + 1] = pts[i]
			end
		end
		out[#out + 1] = pts[#pts]
		pts = out
	end
	-- (each point at its square's height)
	local res = {}
	for i, p in ipairs(pts) do
		local tx, ty = U.pos_to_tile(vector.new(p.x, 0, p.z))
		local h = U.in_map(tx, ty) and height[U.idx(tx, ty)]
		res[i] = vector.new(p.x, h or (i == 1 and from.y) or to.y, p.z)
	end
	res[1].y = from.y
	return res
end

return path
