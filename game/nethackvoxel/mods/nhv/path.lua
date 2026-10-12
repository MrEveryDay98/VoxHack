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
function path.find(sx, sy, gx, gy, passable, is_door, max_nodes)
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
					ok = passable(cur.x + d[1], cur.y) and passable(cur.x, cur.y + d[2])
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

return path
