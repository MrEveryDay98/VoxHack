-- The Plane of Water, in 3D. The plane is open space over an invisible floor
-- (terrain.lua's sky_floor); its air bubbles - NetHack's own, each its
-- shape and size, moving a square a turn (mkmaze.c's movebubbles) - are
-- round, see-through spheres (models/nhv_bubble.obj), gliding smoothly
-- after them at the time's rate (standing still in stopped time, they
-- stop), with a ring where each meets the floor: its edge, fading toward
-- the middle, in pieces (models/nhv_bubble_ring_NN.obj, both from
-- tools/make_bubble_mesh.py) - a piece inside another bubble is left out,
-- so where two meet is clear.
--
-- The 3D world says whether you're in a bubble, not NetHack's squares (a
-- turn behind the spheres, and jagged): your body inside a sphere is in
-- air, else in the water - NetHack is told (#nhvwater; it makes the
-- hero's square match: nhv_free.c). The bubble you're in carries you
-- along with it, on the engine's side (core.nhv_player_drift), on top of
-- your own moving. Outside the bubbles you're underwater: the screen
-- tinted the water's deep blue, darker at its edges, bubbles rising round
-- you; in one, its rim shows round the screen.

local U = nhv.util
local T = U.TYP
local nh = nhv.nh

local bubbles = {list = {}}
nhv.bubbles = bubbles

local TINT = "[fill:16x16:#CFEFFF40"
-- (each sphere's middle is on the floor - half of it below, going on
-- under the floor - so its widest is its ring: what you see on the floor is
-- just where you're in it or not)
local RING_Y = U.FLOOR_Y + 0.53   -- (just over the floor's top)
local CENTER_Y = RING_Y
local SECTORS = 24
-- the ring's bands, its edge in (tools/make_bubble_mesh.py's BANDS)
local BAND_TEX = {}
for k, op in ipairs({235, 150, 90, 45, 15}) do
	BAND_TEX[k] = ("[fill:16x16:#C8F6FF^[opacity:%d"):format(op)
end

local function entity(name, def)
	def.physical, def.pointable, def.static_save = false, false, false
	def.collisionbox = {0, 0, 0, 0, 0, 0}
	core.register_entity(name, {
		initial_properties = def,
		on_step = function(self)
			if not self.bubble then
				self.object:remove()
			end
		end,
	})
end
entity("nhv:bubble", {visual = "mesh", mesh = "nhv_bubble.obj", textures = {TINT},
	use_texture_alpha = true, backface_culling = true, glow = 4, shaded = true})
-- (the ring's pieces hang off this, which carries them along: it shows
-- nothing itself - see-through, not hidden: what hangs off a hidden one is
-- hidden with it)
local BLANK = "blank.png"
entity("nhv:bubble_ring", {visual = "cube", textures = {BLANK, BLANK, BLANK, BLANK, BLANK, BLANK},
	use_texture_alpha = true, visual_size = {x = 1, y = 1, z = 1}})
entity("nhv:bubble_piece", {visual = "mesh", mesh = "nhv_bubble_ring_00.obj", textures = BAND_TEX,
	use_texture_alpha = true, backface_culling = false, glow = 12, shaded = false})

-- NetHack's bubbles: {x, y (their top left square), w, h}, in its order -
-- the same bubble at the same place in it, turn after turn. (Without the
-- VoxHack engine's core.nh_get_bubbles: each group of air squares.)
local function find(map)
	if core.nh_get_bubbles then
		return core.nh_get_bubbles()
	end
	local seen, out = {}, {}
	for x = 1, U.COLNO - 1 do
		for y = 0, U.ROWNO - 1 do
			local i = U.idx(x, y)
			if map.typ[i] == T.AIR and not seen[i] then
				local stack = {{x, y}}
				local x0, x1, y0, y1 = x, x, y, y
				seen[i] = true
				while #stack > 0 do
					local p = table.remove(stack)
					x0, x1 = math.min(x0, p[1]), math.max(x1, p[1])
					y0, y1 = math.min(y0, p[2]), math.max(y1, p[2])
					for dx = -1, 1 do
						for dy = -1, 1 do
							local nx, ny = p[1] + dx, p[2] + dy
							local j = U.in_map(nx, ny) and U.idx(nx, ny)
							if j and not seen[j] and map.typ[j] == T.AIR then
								seen[j] = true
								stack[#stack + 1] = {nx, ny}
							end
						end
					end
				end
				out[#out + 1] = {x = x0, y = y0, w = x1 - x0 + 1, h = y1 - y0 + 1}
			end
		end
	end
	return out
end

-- a bubble's middle in the world, its sphere's size, its ring's size (as
-- wide as the sphere: its middle is on the floor)
local function placing(b)
	local a = U.tile_center(b.x, b.y, CENTER_Y)
	local c = U.tile_center(b.x + b.w - 1, b.y + b.h - 1, CENTER_Y)
	local pos = vector.multiply(vector.add(a, c), 0.5)
	local wx, wz = b.w * U.TILE, b.h * U.TILE
	return pos, {x = wx, y = math.min(wx, wz), z = wz}, {x = wx, y = 1, z = wz}
end

local function ring_at(pos)
	return vector.new(pos.x, RING_Y, pos.z)
end

local function make(pos, size, ring_size)
	local e = {at = pos, target = pos, vel = vector.zero(), pieces = {}, shown = {}}
	e.obj = core.add_entity(pos, "nhv:bubble")
	if not e.obj then
		return nil
	end
	e.obj:get_luaentity().bubble = true
	e.obj:set_properties({visual_size = size})
	e.ring = core.add_entity(ring_at(pos), "nhv:bubble_ring")
	if e.ring then
		e.ring:get_luaentity().bubble = true
		for k = 0, SECTORS - 1 do
			local p = core.add_entity(ring_at(pos), "nhv:bubble_piece")
			if p then
				p:get_luaentity().bubble = true
				p:set_properties({mesh = ("nhv_bubble_ring_%02d.obj"):format(k), visual_size = ring_size})
				p:set_attach(e.ring)
				e.pieces[k] = p
				e.shown[k] = true
			end
		end
	end
	return e
end

local function remove(e)
	local objs = {e.obj, e.ring}
	for _, p in pairs(e.pieces) do
		objs[#objs + 1] = p
	end
	for _, o in ipairs(objs) do
		if o and o:get_pos() then
			o:get_luaentity().bubble = nil
			o:remove()
		end
	end
end

function bubbles.clear()
	for _, e in ipairs(bubbles.list) do
		remove(e)
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
	local old, keep = bubbles.list, {}
	for k, b in ipairs(found) do
		local pos, size, ring_size = placing(b)
		local e = old[k]
		if e and (e.w ~= b.w or e.h ~= b.h) then
			remove(e) -- (not the same bubble: NetHack's list changed)
			e = nil
		end
		if not e then
			e = make(pos, size, ring_size)
		end
		if e then
			e.w, e.h, e.target = b.w, b.h, pos
			e.rx, e.rz = ring_size.x / 2, ring_size.z / 2
			keep[k] = e
		end
	end
	for k = #found + 1, #old do
		remove(old[k])
	end
	bubbles.list = keep
end

nh.on_snapshot(function(snap)
	bubbles.update(snap and snap.map)
end)

-- is p (on the floor) inside bubble e's ring?
local function inside_ring(e, p)
	if not (e.rx and e.rx > 0) then
		return false
	end
	local dx, dz = (p.x - e.at.x) / e.rx, (p.z - e.at.z) / e.rz
	return dx * dx + dz * dz <= 1
end

-- (each ring's pieces inside another bubble's ring are left out)
local function show_pieces()
	for _, e in ipairs(bubbles.list) do
		for k, p in pairs(e.pieces) do
			local a = 2 * math.pi * (k + 0.5) / SECTORS
			local at = vector.new(e.at.x + e.rx * math.cos(a), 0, e.at.z + e.rz * math.sin(a))
			local covered = false
			for _, o in ipairs(bubbles.list) do
				if o ~= e and inside_ring(o, at) then
					covered = true
					break
				end
			end
			if covered == e.shown[k] then
				e.shown[k] = not covered
				p:set_properties({is_visible = not covered})
			end
		end
	end
end

-- ---------------------------------------------------------------- moving
-- Each sphere glides toward where its bubble is now, a square a turn at the
-- time's rate (further behind, faster). The bubble your body is in carries
-- you along as fast; whether you're in one at all is said to NetHack.
local told -- (what NetHack was last told: true in air, false in water)
-- (arriving, nothing is said until the body has settled on the hero's
-- square: till then NetHack's own say stands)
local settled = false
local drift_set = vector.zero()
local function set_drift(v)
	if not vector.equals(v, drift_set) then
		drift_set = v
		if core.nhv_player_drift then
			core.nhv_player_drift(v)
		end
	end
end

core.register_globalstep(function(dtime)
	if #bubbles.list == 0 then
		set_drift(vector.zero())
		told, settled = nil, false
		return
	end
	local turns = nhv.clock.RATE * nhv.clock.scale
	local moved = false
	for _, e in ipairs(bubbles.list) do
		local d = vector.subtract(e.target, e.at)
		local left = vector.length(d)
		if left > 0.001 and turns > 0 and dtime > 0 then
			local go = math.min(left, U.TILE * turns * dtime * math.max(1, left / U.TILE))
			local step = vector.multiply(d, go / left)
			e.at = vector.add(e.at, step)
			e.vel = vector.divide(step, dtime)
			e.obj:move_to(e.at, true)
			if e.ring and e.ring:get_pos() then
				e.ring:move_to(ring_at(e.at), true)
			end
			moved = true
		else
			e.vel = vector.zero()
		end
	end
	if moved then
		show_pieces()
	end
	local player = nhv.player.get()
	local h = nh.snap and nh.snap.hero
	if not (player and h) then
		return
	end
	local pos = player:get_pos()
	-- (wizard mode, flying free of the hero: the body isn't where it is)
	if nhv.wizard and nhv.wizard.detached() then
		set_drift(vector.zero())
		settled = false
		return
	end
	if not settled then
		local tx, ty = U.pos_to_tile(pos)
		if nhv.player.level_hold or tx ~= h.x or ty ~= h.y then
			bubbles.in_air = not U.has(h.flags, U.HERO.UNDERWATER)
			return
		end
		settled = true
		told = bubbles.in_air
	end
	-- in a bubble (the 3D world's say): carried along with it
	local mine
	for _, e in ipairs(bubbles.list) do
		if inside_ring(e, pos) then
			mine = e
			break
		end
	end
	set_drift(mine and vector.new(mine.vel.x, 0, mine.vel.z) or vector.zero())
	local air = mine ~= nil
	if air ~= told and nh.ready() then
		told = air
		nh.act({{key = "#"}, {text = "nhvwater " .. (air and 1 or 0)}}, {kind = "info"})
	end
	bubbles.in_air = air
end)

-- ---------------------------------------------------------------- underwater
-- Outside the bubbles: the blue tint and the dark edges on the screen, and
-- bubbles rising round you (particles following you - they rise
-- smoothly); in one, its rim round the screen
local TINT_TEX = "[fill:16x16:#0A3C8C^[opacity:85"
local EDGE_TEX = "nhv_vignette.png^[multiply:#041838^[opacity:200"
local RISING_TEX = "nhvfx_ring.png^[multiply:#CFEFFF"
local RIM_TEX = "nhv_vignette.png^[multiply:#C8F6FF^[opacity:150"
local under = nil -- {hud = {ids}, spawner = id} while underwater
local inside = nil -- the HUD id of the bubble's rim, while in one

local function go_under(player)
	under = {hud = {}}
	for k, tex in ipairs({TINT_TEX, EDGE_TEX}) do
		under.hud[#under.hud + 1] = player:hud_add({
			type = "image", position = {x = 0.5, y = 0.5}, alignment = {x = 0, y = 0},
			scale = {x = -100, y = -100}, text = tex, z_index = -400 + k,
		})
	end
	under.spawner = core.add_particlespawner({
		amount = 14, time = 0, attached = player, playername = player:get_player_name(),
		minpos = vector.new(-2.5, -0.5, -2.5), maxpos = vector.new(2.5, 1.2, 2.5),
		minvel = vector.new(-0.15, 0.8, -0.15), maxvel = vector.new(0.15, 1.8, 0.15),
		minacc = vector.new(-0.2, 0.3, -0.2), maxacc = vector.new(0.2, 0.6, 0.2),
		minexptime = 1.5, maxexptime = 3, minsize = 1.2, maxsize = 3.5,
		texture = {name = RISING_TEX, alpha_tween = {1, 0}}, glow = 8,
	})
end

local function come_up(player)
	if player and player:is_player() then
		for _, id in ipairs(under.hud) do
			player:hud_remove(id)
		end
	end
	if under.spawner then
		core.delete_particlespawner(under.spawner)
	end
	under = nil
end

core.register_globalstep(function()
	local player = nhv.player.get()
	local here = player and nhv.terrain.sky_floor == "water" and #bubbles.list > 0
		and not (nhv.cutscene and nhv.cutscene.active) or false
	local want = here and not bubbles.in_air or false
	if want and not under then
		go_under(player)
	elseif not want and under then
		come_up(player)
	end
	local in_bubble = here and bubbles.in_air or false
	if in_bubble and not inside then
		inside = player:hud_add({
			type = "image", position = {x = 0.5, y = 0.5}, alignment = {x = 0, y = 0},
			scale = {x = -100, y = -100}, text = RIM_TEX, z_index = -399,
		})
	elseif not in_bubble and inside then
		if player and player:is_player() then
			player:hud_remove(inside)
		end
		inside = nil
	end
end)

core.register_on_leaveplayer(function(player)
	if under then
		come_up(player)
	end
	inside = nil
end)

return bubbles
