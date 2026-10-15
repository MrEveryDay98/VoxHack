-- Rays: wands, spells and breath weapons as projectiles.
--
-- NetHack hands every ray over instead of tracing it along the grid. Here
-- it flies in a straight line - where you aim for your own zaps, at you
-- for a monster's - at game-time speed (so you can sidestep it), reaching
-- up to its NetHack range in squares and bouncing off walls up to
-- MAX_BOUNCES times. Bodies it passes through get NetHack's hit roll
-- (rays carry on through, like in NetHack; a reflection turns it around),
-- and every square it crosses is reported so fire still burns, cold still
-- freezes water, and so on.
--
-- Settings: nhv_ray_bounces (default 2), nhv_ray_range_scale (default 1).

local U = nhv.util
local nh = nhv.nh
local rays = {list = {}, queue = {}}
nhv.rays = rays

rays.SPEED = 45  -- nodes per game turn
rays.MAX_BOUNCES = tonumber(core.settings:get("nhv_ray_bounces")) or 2
rays.RANGE_SCALE = tonumber(core.settings:get("nhv_ray_range_scale")) or 1
local STEP = 0.3
local HEIGHT = 1.2   -- rays fly at chest height

-- colour per ray kind: magic missile, fire, cold, sleep, death,
-- lightning, poison gas, acid
local COLORS = {[0] = "#c8d0ff", "#ff7a20", "#80e8ff", "#c070ff", "#303030",
	"#ffffa0", "#70ff60", "#d0ff40"}

local function command(text)
	table.insert(rays.queue, {{key = "#"}, {text = text}})
end

local function tile_of(p)
	return U.pos_to_tile(p)
end

local function solid_at(p)
	local def = core.registered_nodes[core.get_node(vector.round(p)).name]
	return def and def.walkable
end

-- ---------------------------------------------------------------- launch
local function launch(info)
	local player = nhv.player.get()
	if not player then
		return
	end
	local from, dir
	if info.from_hero then
		from = vector.add(player:get_pos(), vector.new(0, HEIGHT, 0))
		local look = player:get_look_dir()
		dir = vector.normalize(vector.new(look.x, 0, look.z))
		if vector.length(dir) < 0.5 then -- looking straight up/down
			dir = vector.normalize(vector.new(info.dx, 0, -info.dy))
		end
		from = vector.add(from, vector.multiply(dir, 0.6))
	else
		if info.caster > 0 then
			nhv.mobs.flash(info.caster, "w", 0.12) -- (the caster attacks)
		end
		local body = info.caster > 0 and nhv.sim.body(info.caster)
		if body then
			from = vector.new(body.pos.x, U.STAND_Y + HEIGHT, body.pos.z)
		else
			from = U.tile_center(info.x, info.y, U.STAND_Y + HEIGHT)
		end
		local target = vector.add(player:get_pos(), vector.new(0, HEIGHT, 0))
		dir = vector.direction(from, target)
		dir = vector.normalize(vector.new(dir.x, 0, dir.z))
		from = vector.add(from, vector.multiply(dir, body and (body.r + 0.2) or 0.6))
	end
	local tx, ty = tile_of(from)
	rays.list[info.rid] = {
		rid = info.rid, kind = info.kind, pos = from, dir = dir,
		left = math.max(1, info.range) * U.TILE * rays.RANGE_SCALE,
		bounces = 0, from_hero = info.from_hero, caster = info.caster,
		travelled = 0, passed = {}, squares = {}, last_sq = tx .. "," .. ty,
		waiting = false,
	}
	nhv.sound.hook("ray_fire", {pos = from})
end

nh.on_snapshot(function(snap)
	if not snap or not nh.ready() then
		return
	end
	for _, info in ipairs(core.nh_get_rays() or {}) do
		launch(info)
	end
end)

-- ---------------------------------------------------------------- flying
local function flush_squares(r)
	while #r.squares > 0 do
		local chunk = {}
		for _ = 1, 7 do
			local sq = table.remove(r.squares, 1)
			if not sq then
				break
			end
			chunk[#chunk + 1] = sq[1] .. " " .. sq[2]
		end
		command(("nhvraysq %d %s"):format(r.rid, table.concat(chunk, " ")))
	end
end

local function finish(r)
	flush_squares(r)
	local tx, ty = tile_of(r.pos)
	command(("nhvrayend %d %d %d"):format(r.rid, tx, ty))
	rays.list[r.rid] = nil
end

local function trail(r, p)
	core.add_particle({
		pos = p, velocity = vector.zero(), expirationtime = 0.35,
		size = r.kind == 6 and 6 or 2.5, glow = 14,
		texture = "[fill:8x8:" .. (COLORS[r.kind] or "#ffffff"),
	})
end

local function hits_hero(p, hp)
	local dx, dz = p.x - hp.x, p.z - hp.z
	return dx * dx + dz * dz < (nhv.sim.HERO_R + 0.2) ^ 2
		and p.y >= hp.y and p.y <= hp.y + 1.9
end

local function hits_body(p, e)
	local dx, dz = p.x - e.pos.x, p.z - e.pos.z
	return dx * dx + dz * dz < (e.r + 0.2) ^ 2
end

local function fly(r, dist, hp)
	while dist > 0 and not r.waiting do
		local d = math.min(STEP, dist, r.left)
		dist = dist - d
		local np = vector.add(r.pos, vector.multiply(r.dir, d))
		if solid_at(np) then
			-- bounce: flip the component that ran into the wall
			r.bounces = r.bounces + 1
			if r.bounces > rays.MAX_BOUNCES then
				finish(r)
				return
			end
			local flipped = false
			if solid_at(vector.new(np.x, r.pos.y, r.pos.z)) then
				r.dir.x = -r.dir.x
				flipped = true
			end
			if solid_at(vector.new(r.pos.x, r.pos.y, np.z)) then
				r.dir.z = -r.dir.z
				flipped = true
			end
			if not flipped then
				r.dir = vector.multiply(r.dir, -1)
			end
			nhv.sound.hook("ray_bounce", {pos = r.pos})
		else
			r.pos = np
			r.left = r.left - d
			r.travelled = r.travelled + d
			trail(r, np)
			local tx, ty = tile_of(np)
			local key = tx .. "," .. ty
			if key ~= r.last_sq then
				r.last_sq = key
				table.insert(r.squares, {tx, ty})
			end
			if r.left <= 0 then
				finish(r)
				return
			end
			local now = core.get_us_time()
			if hp and (not r.from_hero or r.travelled > 1.5)
					and (not r.passed.hero or now > r.passed.hero) and hits_hero(np, hp) then
				r.passed.hero = now + 1e6
				r.waiting = true
				flush_squares(r)
				command(("nhvrayhit %d 0"):format(r.rid))
				return
			end
			for id, e in pairs(nhv.sim.mons) do
				if not (id == r.caster and r.travelled < 2)
						and (not r.passed[id] or now > r.passed[id]) and hits_body(np, e) then
					r.passed[id] = now + 1e6
					r.waiting = true
					flush_squares(r)
					command(("nhvrayhit %d %d"):format(r.rid, id))
					return
				end
			end
		end
	end
end

function rays.update(dturns)
	local player = nhv.player.get()
	local hp = player and player:get_pos()
	for _, r in pairs(rays.list) do
		if not r.waiting then
			fly(r, rays.SPEED * dturns, hp)
		end
	end
	while #rays.queue > 0 and nh.ready() do
		nh.act(table.remove(rays.queue, 1), {kind = "ray"})
	end
end

function rays.clear()
	rays.list = {}
	rays.queue = {}
end

nh.on_event(function(evs)
	for _, ev in ipairs(evs) do
		if ev.kind == "ray" then
			local what, rid = ev.text:match("^(%a+) (%d+)$")
			local r = rid and rays.list[tonumber(rid)]
			if r then
				r.waiting = false
				if what == "reflect" then
					r.dir = vector.multiply(r.dir, -1)
					r.passed = {}
				elseif what == "hit" then
					-- like NetHack, a hit costs the ray 2 squares of range
					r.left = r.left - 2 * U.TILE
					nhv.sound.hook("ray_hit", {pos = r.pos})
					if r.left <= 0 then
						finish(r)
					end
				elseif what == "stop" then
					finish(r)
				end
			end
		end
	end
end)

return rays
