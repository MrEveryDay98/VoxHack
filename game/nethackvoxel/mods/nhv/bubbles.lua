-- The Plane of Water's air bubbles: round, see-through spheres, not holes
-- in blocks of water. The plane itself is open space over a floor of sky
-- (terrain.lua's sky_floor); NetHack makes each bubble's squares air and
-- moves the bubbles a square at a time every turn (mkmaze.c's
-- movebubbles). Each group of touching air squares is a bubble: a sphere
-- (models/nhv_bubble.obj, tools/make_bubble_mesh.py) as wide and deep as
-- its squares, gliding after them as they move.

local U = nhv.util
local T = U.TYP
local nh = nhv.nh

local bubbles = {list = {}}
nhv.bubbles = bubbles

local TINT = "[fill:16x16:#CFEFFF40"
local CENTER_Y = U.STAND_Y + 1.2 -- (chest height: you're inside the one you're in)

core.register_entity("nhv:bubble", {
	initial_properties = {
		visual = "mesh", mesh = "nhv_bubble.obj", visual_size = {x = 3, y = 3, z = 3},
		textures = {TINT}, use_texture_alpha = true, backface_culling = false,
		glow = 4, shaded = true,
		physical = false, pointable = false, static_save = false, collisionbox = {0, 0, 0, 0, 0, 0},
	},
	on_step = function(self)
		if not self.bubble then
			self.object:remove()
		end
	end,
})

-- the groups of touching air squares (side by side or corner to corner):
-- each {cx=, cy= (its middle, in squares), w=, h= (how many squares across)}
local function find(map)
	local seen, out = {}, {}
	for x = 1, U.COLNO - 1 do
		for y = 0, U.ROWNO - 1 do
			local i = U.idx(x, y)
			if map.typ[i] == T.AIR and not seen[i] then
				local stack, n, sx, sy = {{x, y}}, 0, 0, 0
				local x0, x1, y0, y1 = x, x, y, y
				seen[i] = true
				while #stack > 0 do
					local p = table.remove(stack)
					n, sx, sy = n + 1, sx + p[1], sy + p[2]
					x0, x1 = math.min(x0, p[1]), math.max(x1, p[1])
					y0, y1 = math.min(y0, p[2]), math.max(y1, p[2])
					for dx = -1, 1 do
						for dy = -1, 1 do
							local nx, ny = p[1] + dx, p[2] + dy
							if U.in_map(nx, ny) then
								local j = U.idx(nx, ny)
								if not seen[j] and map.typ[j] == T.AIR then
									seen[j] = true
									stack[#stack + 1] = {nx, ny}
								end
							end
						end
					end
				end
				out[#out + 1] = {cx = sx / n, cy = sy / n, w = x1 - x0 + 1, h = y1 - y0 + 1}
			end
		end
	end
	return out
end

-- where a bubble's middle is in the world, and how big its sphere is
local function placing(b)
	local a = U.tile_center(0, 0, CENTER_Y)
	local c = U.tile_center(1, 1, CENTER_Y)
	-- (squares to nodes: tile_center is linear in the square)
	local pos = vector.new(a.x + (c.x - a.x) * b.cx, CENTER_Y, a.z + (c.z - a.z) * b.cy)
	local wx, wz = b.w * U.TILE, b.h * U.TILE
	return pos, {x = wx, y = math.min(wx, wz), z = wz}
end

function bubbles.clear()
	for _, e in ipairs(bubbles.list) do
		e.obj:get_luaentity().bubble = nil
		e.obj:remove()
	end
	bubbles.list = {}
end

function bubbles.update(map)
	if not (nhv.terrain.sky_floor == "water" and map and map.typ) then
		if #bubbles.list > 0 then
			bubbles.clear()
		end
		return
	end
	local found = find(map)
	-- each bubble keeps its sphere: the nearest one of last turn's (a
	-- bubble moves a square a turn), or a new one
	local old, keep = bubbles.list, {}
	local used = {}
	for _, b in ipairs(found) do
		local best, best_d
		for k, e in ipairs(old) do
			if not used[k] then
				local d = math.abs(e.cx - b.cx) + math.abs(e.cy - b.cy)
				if d <= 3 and (not best_d or d < best_d) then
					best, best_d = k, d
				end
			end
		end
		local pos, size = placing(b)
		local e
		if best then
			used[best] = true
			e = old[best]
			e.obj:move_to(pos, true)
			if e.w ~= b.w or e.h ~= b.h then
				e.obj:set_properties({visual_size = size})
			end
		else
			local obj = core.add_entity(pos, "nhv:bubble")
			if obj then
				obj:set_properties({visual_size = size})
				obj:get_luaentity().bubble = true
				e = {obj = obj}
			end
		end
		if e then
			e.cx, e.cy, e.w, e.h = b.cx, b.cy, b.w, b.h
			keep[#keep + 1] = e
		end
	end
	for k, e in ipairs(old) do
		if not used[k] and e.obj:get_pos() then
			e.obj:get_luaentity().bubble = nil
			e.obj:remove()
		end
	end
	bubbles.list = keep
end

nh.on_snapshot(function(snap)
	bubbles.update(snap and snap.map)
end)

return bubbles
