-- The Plane of Water, in 3D. The plane is open space over an invisible floor
-- (terrain.lua's sky_floor); its air bubbles - NetHack's own, each its
-- shape and size, moving a square a turn (mkmaze.c's movebubbles) - are
-- round, see-through spheres (models/nhv_bubble.obj, from
-- tools/make_bubble_mesh.py), gliding smoothly after them at the time's
-- rate (standing still in stopped time, they stop). Where they meet the
-- floor the VoxHack engine draws them (core.nhv_bubble_floor: its
-- nhv_bubble_shader): all the bubbles as one shape - where two meet, one
-- smooth outline round both - bright at its edge, fading toward the middle.
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
-- under the floor - so its widest is where it meets the floor: what you
-- see painted there is just where you're in it or not)
local CENTER_Y = U.FLOOR_Y + 0.53

core.register_entity("nhv:bubble", {
	initial_properties = {
		visual = "mesh", mesh = "nhv_bubble.obj", textures = {TINT},
		use_texture_alpha = true, backface_culling = true, glow = 4, shaded = true,
		physical = false, pointable = false, static_save = false, collisionbox = {0, 0, 0, 0, 0, 0},
	},
	on_step = function(self)
		if not self.bubble then
			self.object:remove()
		end
	end,
})

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

-- a bubble's middle in the world and its sphere's size
local function placing(b)
	local a = U.tile_center(b.x, b.y, CENTER_Y)
	local c = U.tile_center(b.x + b.w - 1, b.y + b.h - 1, CENTER_Y)
	local pos = vector.multiply(vector.add(a, c), 0.5)
	local wx, wz = b.w * U.TILE, b.h * U.TILE
	return pos, {x = wx, y = math.min(wx, wz), z = wz}
end

local function make(pos, size)
	local e = {at = pos, target = pos, vel = vector.zero()}
	e.obj = core.add_entity(pos, "nhv:bubble")
	if not e.obj then
		return nil
	end
	e.obj:get_luaentity().bubble = true
	e.obj:set_properties({visual_size = size})
	return e
end

local function remove(e)
	if e.obj and e.obj:get_pos() then
		e.obj:get_luaentity().bubble = nil
		e.obj:remove()
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
		local pos, size = placing(b)
		local e = old[k]
		if e and (e.w ~= b.w or e.h ~= b.h) then
			remove(e) -- (not the same bubble: NetHack's list changed)
			e = nil
		end
		if not e then
			e = make(pos, size)
		end
		if e then
			e.w, e.h, e.target = b.w, b.h, pos
			e.rx, e.rz = size.x / 2, size.z / 2
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

-- is p (on the floor) inside bubble e?
local function inside(e, p)
	if not (e.rx and e.rx > 0) then
		return false
	end
	local dx, dz = (p.x - e.at.x) / e.rx, (p.z - e.at.z) / e.rz
	return dx * dx + dz * dz <= 1
end

-- ---------------------------------------------------------------- the floor
-- where they are, and how fast they're going, for the engine to draw them
-- on the floor (gliding on between steps at that speed)
local FLOOR_TOP = U.FLOOR_Y + 0.51
local floor_shown = false
local function show_floor()
	if not core.nhv_bubble_floor then
		return
	end
	local list = {}
	for _, e in ipairs(bubbles.list) do
		if e.rx and e.rx > 0 then
			list[#list + 1] = {x = e.at.x, z = e.at.z, rx = e.rx, rz = e.rz, vx = e.vel.x, vz = e.vel.z}
		end
	end
	if #list > 0 or floor_shown then
		core.nhv_bubble_floor(list, FLOOR_TOP)
		floor_shown = #list > 0
	end
end

-- ---------------------------------------------------------------- moving
-- Each sphere glides toward where its bubble is now, a square a turn at the
-- time's rate (further behind, faster). The bubble your body is in carries
-- you along as fast; whether you're in one at all is said to NetHack.
local told -- (what NetHack was last told: true in air, false in water)
-- (the drift eases from one speed to the next: no jolts)
local drift_now = vector.zero()
-- (a slide: NetHack moved you a square or two - out of the water to safety
-- - and the body glides there: {v=, until=})
local slide = nil
function bubbles.slide(v, secs)
	slide = {v = v, ["until"] = core.get_us_time() + secs * 1e6}
end
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
		show_floor()
		return
	end
	local turns = nhv.clock.RATE * nhv.clock.scale
	local moved = false
	for _, e in ipairs(bubbles.list) do
		local d = vector.subtract(e.target, e.at)
		local left = vector.length(d)
		if left > 0.001 and turns > 0 and dtime > 0 then
			-- (steadily a square a turn; only well behind, faster)
			local go = math.min(left, U.TILE * turns * dtime * (left > U.TILE * 1.5 and left / U.TILE or 1))
			local step = vector.multiply(d, go / left)
			e.at = vector.add(e.at, step)
			e.vel = vector.divide(step, dtime)
			e.obj:move_to(e.at, true)
			moved = true
		else
			e.vel = vector.zero()
		end
	end
	show_floor()
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
		if inside(e, pos) then
			mine = e
			break
		end
	end
	local want = mine and vector.new(mine.vel.x, 0, mine.vel.z) or vector.zero()
	drift_now = vector.add(drift_now, vector.multiply(vector.subtract(want, drift_now), math.min(1, dtime * 4)))
	if vector.length(drift_now) < 0.02 then
		drift_now = vector.zero()
	end
	local v = drift_now
	if slide then
		if core.get_us_time() < slide["until"] then
			v = vector.add(v, slide.v)
		else
			slide = nil
		end
	end
	set_drift(v)
	local air = mine ~= nil
	if air ~= told and nh.ready() then
		told = air
		nh.act({{key = "#"}, {text = "nhvwater " .. (air and 1 or 0)}}, {kind = "info"})
	end
	bubbles.in_air = air
end)

-- is square (tx, ty) in a bubble, as the 3D world has it (its middle
-- inside a sphere)? - the big map shows the bubbles so (hud.lua)
function bubbles.air_at(tx, ty)
	local c = U.tile_center(tx, ty)
	for _, e in ipairs(bubbles.list) do
		if inside(e, c) then
			return true
		end
	end
	return false
end

-- ---------------------------------------------------------------- underwater
-- Outside the bubbles: the blue tint and the dark edges on the screen, and
-- bubbles rising round you (particles following you - they rise
-- smoothly); in one, its rim round the screen
local TINT_TEX = "[fill:16x16:#0A3C8C^[opacity:85"
local EDGE_TEX = "nhv_vignette.png^[multiply:#041838^[opacity:200"
local RISING_TEX = "nhvfx_ring.png^[multiply:#CFEFFF"
local RIM_TEX = "nhv_vignette.png^[multiply:#C8F6FF^[opacity:150"
local under = nil -- {hud = {ids}, spawner = id} while underwater
local rim = nil -- the HUD id of the bubble's rim, while in one

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
	if in_bubble and not rim then
		rim = player:hud_add({
			type = "image", position = {x = 0.5, y = 0.5}, alignment = {x = 0, y = 0},
			scale = {x = -100, y = -100}, text = RIM_TEX, z_index = -399,
		})
	elseif not in_bubble and rim then
		if player and player:is_player() then
			player:hud_remove(rim)
		end
		rim = nil
	end
end)

core.register_on_leaveplayer(function(player)
	if under then
		come_up(player)
	end
	rim = nil
end)

return bubbles
