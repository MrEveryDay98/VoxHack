-- Dodgeable missiles.
--
-- When a monster throws or shoots something at you, NetHack hands the
-- missile over instead of resolving it on the grid. It flies from the
-- thrower toward where you were, at game-time speed (so it crawls while
-- you stand still - step out of the way!). What it touches decides what
-- happens:
--   * your body: NetHack rolls to hit; if that fails you dodged it after
--     all ("Dodged!") and it flies on,
--   * a monster's body: NetHack rolls for that monster,
--   * a wall, or the end of its range: it drops there.

local U = nhv.util
local nh = nhv.nh
local missiles = {
	list = {},      -- pid -> flying missile
	queue = {},     -- commands waiting for NetHack to be ready
}
nhv.missiles = missiles

missiles.SPEED = 15     -- nodes per game turn
local STEP = 0.25       -- collision check spacing (nodes)
local HERO_H = 1.8      -- hero body height

core.register_entity("nhv:missile", {
	initial_properties = {
		visual = "wielditem", wield_item = nhv_tiles.item(0),
		visual_size = {x = 0.35, y = 0.35, z = 0.35},
		physical = false, pointable = false, static_save = false,
	},
})

local function command(text)
	table.insert(missiles.queue, {{key = "#"}, {text = text}})
end

local function remove(m)
	if m.obj and m.obj:get_pos() then
		m.obj:remove()
	end
	missiles.list[m.pid] = nil
end

function missiles.clear()
	for _, m in pairs(missiles.list) do
		remove(m)
	end
	missiles.list = {}
	missiles.queue = {}
end

-- ---------------------------------------------------------------- launching
local function launch(info)
	local player = nhv.player.get()
	if not player then
		return
	end
	local body = nhv.sim.body(info.mon_id)
	local from
	if body then
		local h = nhv.scale.height(body.size, body.mndx)
		from = vector.new(body.pos.x, U.STAND_Y + h * 0.6, body.pos.z)
	else
		from = U.tile_center(info.x, info.y, U.STAND_Y + 1.2)
	end
	local target = vector.add(player:get_pos(), vector.new(0, 1.2, 0))
	local dir = vector.direction(from, target)
	-- start just outside the thrower's body
	local start = vector.add(from, vector.multiply(dir, body and (body.r + 0.2) or 0.5))
	local obj = core.add_entity(start, "nhv:missile")
	if obj then
		obj:set_properties(nhv_tiles.look(info.tile, 0.7))
		obj:set_yaw(math.atan2(dir.z, dir.x))
	end
	nhv.sound.hook("missile_launch", {pos = start})
	missiles.list[info.pid] = {
		pid = info.pid, obj = obj, pos = start, dir = dir, travelled = 0,
		range = (math.max(info.range, 1) + 1) * U.TILE, thrower = info.mon_id,
		passed = {}, waiting = false,
	}
end

nh.on_snapshot(function(snap)
	if not snap or not nh.ready() then
		return
	end
	for _, info in ipairs(core.nh_get_missiles() or {}) do
		launch(info)
	end
end)

-- ---------------------------------------------------------------- flying
local function solid_at(p)
	local node = core.get_node(vector.round(p))
	local def = core.registered_nodes[node.name]
	return def and def.walkable
end

local function hits_hero(p, hp)
	local dx, dz = p.x - hp.x, p.z - hp.z
	return dx * dx + dz * dz < (nhv.sim.HERO_R + 0.15) ^ 2
		and p.y >= hp.y and p.y <= hp.y + HERO_H
end

local function hits_body(p, e)
	local dx, dz = p.x - e.pos.x, p.z - e.pos.z
	if dx * dx + dz * dz >= (e.r + 0.15) ^ 2 then
		return false
	end
	local h = nhv.scale.height(e.size, e.mndx)
	return p.y >= U.STAND_Y and p.y <= U.STAND_Y + h
end

local function land(m, p)
	local tx, ty = U.pos_to_tile(p)
	command(("nhvmland %d %d %d"):format(m.pid, tx, ty))
	m.waiting = true
end

local function fly(m, dist, hp)
	while dist > 0 and not m.waiting do
		local d = math.min(STEP, dist)
		dist = dist - d
		local np = vector.add(m.pos, vector.multiply(m.dir, d))
		m.travelled = m.travelled + d
		if solid_at(np) or m.travelled > m.range then
			land(m, m.pos)
			return
		end
		m.pos = np
		if hp and not m.passed.hero and hits_hero(np, hp) then
			m.passed.hero = true
			m.waiting = true
			command(("nhvmhit %d"):format(m.pid))
			return
		end
		for id, e in pairs(nhv.sim.mons) do
			if not m.passed[id] and not (id == m.thrower and m.travelled < 1.5)
					and hits_body(np, e) then
				m.passed[id] = true
				m.waiting = true
				command(("nhvmhitm %d %d"):format(m.pid, id))
				return
			end
		end
	end
end

-- called by the game loop with the game time that passed
function missiles.update(dturns)
	local player = nhv.player.get()
	local hp = player and player:get_pos()
	for _, m in pairs(missiles.list) do
		if not m.waiting then
			fly(m, missiles.SPEED * dturns, hp)
			if m.obj and m.obj:get_pos() then
				m.obj:move_to(m.pos, true)
			end
		end
	end
	-- outcomes need NetHack; these take no game time
	while #missiles.queue > 0 and nh.ready() do
		nh.act(table.remove(missiles.queue, 1), {kind = "missile"})
	end
end

-- ---------------------------------------------------------------- outcomes
-- floating "Dodged!" that drifts up and fades
local floaters = {}
function missiles.float_text(text, color)
	local player = nhv.player.get()
	if not player then
		return
	end
	local id = player:hud_add({
		type = "text", position = {x = 0.5, y = 0.5}, alignment = {x = 0, y = 0},
		offset = {x = 0, y = -30}, number = color or 0x80FF80, text = text,
		size = {x = 2, y = 2}, z_index = 50,
	})
	table.insert(floaters, {id = id, t = 0})
end

core.register_globalstep(function(dtime)
	local player = nhv.player.get()
	if not player then
		return
	end
	for i = #floaters, 1, -1 do
		local f = floaters[i]
		f.t = f.t + dtime
		if f.t > 1.0 then
			player:hud_remove(f.id)
			table.remove(floaters, i)
		else
			player:hud_change(f.id, "offset", {x = 0, y = -30 - f.t * 80})
		end
	end
end)

nh.on_event(function(evs)
	for _, ev in ipairs(evs) do
		if ev.kind == "missile" then
			local what, pid = ev.text:match("^(%a+) (%d+)$")
			local m = pid and missiles.list[tonumber(pid)]
			if m then
				if what == "miss" then
					missiles.float_text("Dodged!")
					nhv.sound.hook("missile_dodged")
					m.waiting = false
				elseif what == "pass" then
					m.waiting = false
				else -- hit, stop, land
					if what == "hit" then
						nhv.sound.hook("missile_hit")
					elseif what == "land" then
						nhv.sound.hook("missile_land", {pos = m.pos})
					end
					remove(m)
				end
			end
		end
	end
end)

return missiles
