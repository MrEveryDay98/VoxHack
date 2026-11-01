-- Light from lit rooms, cast in straight lines. A lit room is lit through
-- and through, evenly; out of it the light goes only where a straight
-- line from the room reaches - through a doorway, out into the hall, in a
-- widening shaft with straight edges where the door's sides cut it off -
-- dimming as it goes. Not Luanti's light, spreading out round corners in
-- soft diamonds: the room's light isn't a light block any more
-- (terrain.light_square), it's worked out here and written into the
-- blocks' light. (Lamps, candles, lava: still Luanti's.)
--
-- It's worked out on the level as built, at standing height: what's solid
-- there (walls, closed doors) blocks it; what's open (doorways, iron bars)
-- lets it through. Again whenever squares are built again (a door opened
-- or closed, more of the level seen), or a lamp's put out.

local U = nhv.util
local nh = nhv.nh

local lightcast = {}
nhv.lightcast = lightcast

local FULL = 14   -- a lit room's light
local FALL = 2    -- nodes the cast light goes for each level it loses (it fades)
local RANGE = 24  -- how far it reaches (nodes): 8 squares
local DIM = 3     -- below this, none (the dark's own)

local X1, Z1 = U.COLNO * U.TILE, U.ROWNO * U.TILE
local due = nil -- (us) when to work it out again

local function idx(x, z)
	return z * X1 + x + 1
end

-- worked out again soon: squares built again (the light there Luanti's
-- own again), the sea round the level put in, a lamp put out
function lightcast.redo()
	due = core.get_us_time() + 250000
end

-- which content ids block the light: solid and drawn (not airlike - iron
-- bars, the level's invisible edge - nor see-through leaves and glass)
local blocking = {}
local function blocks(id)
	local b = blocking[id]
	if b == nil then
		local def = core.registered_nodes[core.get_name_from_content_id(id)]
		b = def and def.walkable ~= false and def.drawtype ~= "airlike" and def.drawtype ~= "allfaces"
			and def.drawtype ~= "allfaces_optional" and def.drawtype ~= "glasslike"
			and def.drawtype ~= "plantlike" or false
		blocking[id] = b
	end
	return b
end

-- and how much light they give (lamps, lava)
local emitting = {}
local function emits(id)
	local e = emitting[id]
	if e == nil then
		local def = core.registered_nodes[core.get_name_from_content_id(id)]
		e = def and def.light_source or 0
		emitting[id] = e
	end
	return e
end

local function work_out()
	local map = nh.snap and nh.snap.map
	if not map then
		return
	end
	local y = U.FLOOR_Y + 1
	local vm = core.get_voxel_manip()
	local emin, emax = vm:read_from_map(vector.new(0, y, 0), vector.new(X1 - 1, y, Z1 - 1))
	local area = VoxelArea(emin, emax)
	local ids = vm:get_data()
	-- what's open, and what's lit room (not its doorways: the light goes
	-- out through them, from the room)
	local solid, room = {}, {}
	for z = 0, Z1 - 1 do
		for x = 0, X1 - 1 do
			local i = idx(x, z)
			solid[i] = blocks(ids[area:index(x, y, z)])
			if not solid[i] then
				local tx, ty = U.pos_to_tile(vector.new(x, 0, z))
				local m = U.in_map(tx, ty) and U.idx(tx, ty)
				room[i] = m and U.has(map.flags[m] or 0, U.LOC_LIT) and map.typ[m] ~= U.TYP.DOOR or false
			end
		end
	end
	-- the light: full in the room; cast out from its edge - every cell of
	-- it beside the open dark - in straight lines, all round
	local light = {}
	local rays = math.floor(8 * RANGE)
	local dirs = {}
	for r = 0, rays - 1 do
		local a = r / rays * 2 * math.pi
		dirs[r + 1] = {math.cos(a), math.sin(a)}
	end
	for z = 0, Z1 - 1 do
		for x = 0, X1 - 1 do
			local i = idx(x, z)
			if room[i] then
				light[i] = FULL
				local edge = false
				for _, d in ipairs({{1, 0}, {-1, 0}, {0, 1}, {0, -1}}) do
					local nx, nz = x + d[1], z + d[2]
					if nx >= 0 and nx < X1 and nz >= 0 and nz < Z1 then
						local j = idx(nx, nz)
						if not solid[j] and not room[j] then
							edge = true
						end
					end
				end
				if edge then
					for _, d in ipairs(dirs) do
						local t = 0.5
						while t <= RANGE do
							local cx = math.floor(x + d[1] * t + 0.5)
							local cz = math.floor(z + d[2] * t + 0.5)
							if cx < 0 or cx >= X1 or cz < 0 or cz >= Z1 then
								break
							end
							local j = idx(cx, cz)
							-- (back into the room: what's past it, the room's
							-- other edges cast to)
							if solid[j] or (room[j] and t > 1) then
								break
							end
							if not room[j] then
								local v = FULL - math.floor(t / FALL)
								if v < DIM then
									break
								end
								if (light[j] or 0) < v then
									light[j] = v
								end
							end
							t = t + 0.5
						end
					end
				end
			end
		end
	end
	-- The level's light worked out afresh, all of it - Luanti's own, left
	-- as it is, spreads the cast light round corners again whenever it
	-- relights anything near it (a lamp put out, a square built): the cast
	-- light from the floor to the ceiling; lamps, lava and the like
	-- spreading as Luanti spreads them; and the cast light spreading on
	-- only above and below (over the walls' tops, down into pits), never
	-- back into the shadows beside it.
	local y0, y1 = U.FLOOR_Y + 1, U.CEIL_Y - 1
	local Y0, Y1 = U.FLOOR_Y - 6, U.CEIL_Y + 2
	vm = core.get_voxel_manip()
	emin, emax = vm:read_from_map(vector.new(0, Y0, 0), vector.new(X1 - 1, Y1, Z1 - 1))
	area = VoxelArea(emin, emax)
	ids = vm:get_data()
	local lt = vm:get_light_data()
	local ys, zs = area.ystride, area.zstride
	local ex, ey, ez = emin.x, emin.y, emin.z
	local src, cast = {}, {}
	local src_q, cast_q = {}, {}
	for l = 1, 15 do
		src_q[l], cast_q[l] = {}, {}
	end
	for z = 0, Z1 - 1 do
		for yy = Y0, Y1 do
			local vi = area:index(0, yy, z)
			for x = 0, X1 - 1 do
				local id = ids[vi]
				local s = emits(id)
				if s > 0 then
					src[vi] = s
					local q = src_q[s]
					q[#q + 1] = vi
				end
				if yy >= y0 and yy <= y1 and not blocks(id) then
					local v = light[idx(x, z)]
					if v then
						cast[vi] = v
						local q = cast_q[v]
						q[#q + 1] = vi
					end
				end
				vi = vi + 1
			end
		end
	end
	-- (brightest first, a level less each block on; the cast light not into
	-- the band it was cast in)
	local function spread(lv, queues, band)
		for l = 15, 2, -1 do
			local q = queues[l]
			local i = 1
			while q[i] do
				local vi = q[i]
				i = i + 1
				if lv[vi] == l then
					local rel = vi - 1
					local x = rel % ys + ex
					local yy = math.floor(rel / ys) % (zs / ys) + ey
					local z = math.floor(rel / zs) + ez
					for n = 1, 6 do
						local nx, ny, nz, ni = x, yy, z, vi
						if n == 1 then nx, ni = x + 1, vi + 1
						elseif n == 2 then nx, ni = x - 1, vi - 1
						elseif n == 3 then nz, ni = z + 1, vi + zs
						elseif n == 4 then nz, ni = z - 1, vi - zs
						elseif n == 5 then ny, ni = yy + 1, vi + ys
						else ny, ni = yy - 1, vi - ys end
						if nx >= 0 and nx < X1 and nz >= 0 and nz < Z1 and ny >= Y0 and ny <= Y1
								and not (band and ny >= y0 and ny <= y1)
								and (lv[ni] or 0) < l - 1 and not blocks(ids[ni]) then
							lv[ni] = l - 1
							local nq = queues[l - 1]
							nq[#nq + 1] = ni
						end
					end
				end
			end
		end
	end
	spread(src, src_q, false)
	spread(cast, cast_q, true)
	-- (written into what isn't solid; the day's light - sunlight - kept, the
	-- night's the one shown)
	for z = 0, Z1 - 1 do
		for yy = Y0, Y1 do
			local vi = area:index(0, yy, z)
			for x = 0, X1 - 1 do
				local id = ids[vi]
				if not blocks(id) or src[vi] then
					local night = math.max(src[vi] or 0, cast[vi] or 0)
					local day = lt[vi] % 16
					lt[vi] = (day == 15 and 15 or night) + night * 16
				end
				vi = vi + 1
			end
		end
	end
	vm:set_light_data(lt)
	vm:write_to_map(false)
end

core.register_globalstep(function()
	if not due or core.get_us_time() < due then
		return
	end
	-- (once the level's all there: its blocks still coming, wait)
	if nhv.player and nhv.player.level_hold then
		return
	end
	if core.nh_level_progress and core.nh_level_progress() < 1 then
		return
	end
	due = nil
	local t0 = core.get_us_time()
	work_out()
	lightcast.last_ms = (core.get_us_time() - t0) / 1000
end)

return lightcast
