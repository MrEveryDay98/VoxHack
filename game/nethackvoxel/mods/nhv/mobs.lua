-- Entities for what NetHack displays on top of the terrain: monsters,
-- objects and dungeon features (fountains, altars, traps, ...).
--
-- Every sprite is a NetHack tile, drawn as an extruded voxel model or, with
-- the "flat sprites" graphics option, as a flat sprite (nhv_tiles.look).
--
-- Monsters are drawn where their bodies are in nhv.sim (continuous
-- positions); only the ones NetHack says the hero perceives are shown.
-- Their hitbox matches their sprite and is solid to the player.

local U = nhv.util
local scale = nhv.scale
local mobs = {
	mons = {},      -- key -> {obj=, tile=, h=, x=, y=, mon=, id=}
	objs = {},      -- square index -> {obj=, tile=}
	feats = {},     -- square index -> {obj=, tile=}
}
nhv.mobs = mobs

local function sprite_props(tile, height)
	local s = height / 2
	local props = nhv_tiles.look(tile, height)
	props.selectionbox = {-s * 0.6, -s, -s * 0.6, s * 0.6, s, s * 0.6}
	return props
end

local function base_props()
	return {
		physical = false,
		collide_with_objects = false,
		pointable = true,
		visual = "wielditem",
		wield_item = nhv_tiles.item(0),
		visual_size = {x = 0.5, y = 0.5, z = 0.5},
		collisionbox = {0, 0, 0, 0, 0, 0},
		static_save = false,
		shaded = true,
	}
end

core.register_entity("nhv:mon", {
	initial_properties = base_props(),
	on_punch = function(self, puncher)
		if nhv.actions and self.nh_key then
			nhv.actions.attack_entity(puncher, self)
		end
		return true
	end,
})

core.register_entity("nhv:obj", {
	initial_properties = base_props(),
	on_punch = function() return true end,
})

core.register_entity("nhv:feat", {
	initial_properties = base_props(),
	on_punch = function() return true end,
})

local function remove_all(tbl)
	for k, e in pairs(tbl) do
		if e.obj and e.obj:get_pos() then
			e.obj:remove()
		end
		tbl[k] = nil
	end
end

function mobs.clear()
	remove_all(mobs.mons)
	remove_all(mobs.objs)
	remove_all(mobs.feats)
	-- stray entities from an earlier session
	for _, obj in ipairs(core.get_objects_in_area(vector.new(-10, -10, -10),
			vector.new(U.COLNO * U.TILE + 10, U.CEIL_Y + 10, U.ROWNO * U.TILE + 10))) do
		local ent = obj:get_luaentity()
		if ent and (ent.name == "nhv:mon" or ent.name == "nhv:obj" or ent.name == "nhv:feat") then
			obj:remove()
		end
	end
end

-- ---------------------------------------------------------------- monsters
-- where to draw a perceived monster: its body if we simulate it, else
-- the middle of its square (remembered 'I's, warnings)
local function mon_draw_pos(e)
	local body = e.id and e.id > 0 and nhv.sim.body(e.id)
	local base
	if body and body.x == e.x and body.y == e.y then
		base = body.pos
	else
		base = U.tile_center(e.x, e.y)
	end
	local y = scale.mon_center_y(e.mon and e.mon.mndx, e.h, U.STAND_Y, U.CEIL_Y - 0.5)
	return vector.new(base.x, y, base.z)
end

local function apply_sprite(e, m)
	local h = scale.height(m.size, m.mndx)
	-- a solid body the size of the sprite (Luanti only collides with
	-- "physical" objects); pets stay passable, as you swap places with them
	local solid = m.id > 0 and not U.has(m.flags, U.MON_PET)
	if e.tile ~= m.tile or e.h ~= h or e.solid ~= solid then
		local props = sprite_props(m.tile, h)
		local w = scale.radius(m.size, m.mndx)
		props.physical = solid
		props.collide_with_objects = solid
		props.collisionbox = solid and {-w, -h / 2, -w, w, h / 2, w} or {0, 0, 0, 0, 0, 0}
		e.obj:set_properties(props)
		e.tile, e.h, e.solid = m.tile, h, solid
	end
end

local function update_monsters(snap)
	local seen = {}
	local hallu = U.has(snap.hero.flags, U.HERO.HALLU)
	for _, m in ipairs(snap.monsters) do
		local key = m.id > 0 and ("id" .. m.id) or ("at" .. m.x .. "," .. m.y)
		seen[key] = true
		local e = mobs.mons[key]
		if e and not e.obj:get_pos() then
			e = nil
		end
		if not e then
			local obj = core.add_entity(U.tile_center(m.x, m.y), "nhv:mon")
			if obj then
				e = {obj = obj}
				obj:get_luaentity().nh_key = key
				mobs.mons[key] = e
			end
		end
		if e then
			e.x, e.y, e.mon, e.id = m.x, m.y, m, m.id
			e.wavy = hallu or U.has(m.flags, U.MON_INVIS) or U.has(m.flags, U.MON_DETECTED)
			apply_sprite(e, m)
			e.obj:set_pos(mon_draw_pos(e))
		end
	end
	for key, e in pairs(mobs.mons) do
		if not seen[key] then
			if e.obj:get_pos() then
				e.obj:remove()
			end
			mobs.mons[key] = nil
		end
	end
end

-- re-apply sizes after /scale
function mobs.refresh_sizes()
	for _, e in pairs(mobs.mons) do
		if e.mon and e.obj:get_pos() then
			e.tile = nil
			apply_sprite(e, e.mon)
		end
	end
	-- objects and features are redrawn too (e.g. after switching flat sprites)
	for _, tbl in ipairs({mobs.objs, mobs.feats}) do
		for _, e in pairs(tbl) do
			e.tile = nil
		end
	end
	nhv.sim.sync()
	if nhv.nh.snap then
		mobs.update(nhv.nh.snap, false)
	end
end

-- only refresh which monsters are perceived (cheap, every step a
-- monster changed squares)
function mobs.update_monsters_only(snap)
	update_monsters(snap)
end

-- ---------------------------------------------------------------- objects
local OBJ_H = 0.8
-- objects that face you instead of spinning
local BILLBOARD = {["chest"] = true, ["large box"] = true, ["ice box"] = true}
local BOULDER_H = 2.6

local function update_objects(snap)
	local map = snap.map
	local seen = {}
	for tx = 1, U.COLNO - 1 do
		for ty = 0, U.ROWNO - 1 do
			local i = U.idx(tx, ty)
			local g = map.mem[i]
			local gi = nhv.glyph_info(g)
			if gi.kind == "obj" or gi.kind == "body" or gi.kind == "statue" then
				seen[i] = true
				local e = mobs.objs[i]
				if e and not e.obj:get_pos() then
					e = nil
				end
				local h = OBJ_H
				local name = core.nh_obj_name(gi.index) or ""
				local flat = gi.kind == "body"
				if gi.kind == "statue" then
					h = 2.0
				elseif name == "boulder" then
					h = BOULDER_H
				elseif flat then
					h = 1.4 -- corpses lie on the floor
				elseif BILLBOARD[name] then
					h = 1.4
				end
				local pos = U.tile_center(tx, ty, flat and (U.STAND_Y + 0.03) or (U.STAND_Y + h / 2))
				if not e then
					local obj = core.add_entity(pos, "nhv:obj")
					if obj then
						e = {obj = obj}
						mobs.objs[i] = e
					end
				end
				if e and (e.tile ~= map.mem_tile[i] or e.h ~= h) then
					local props = sprite_props(map.mem_tile[i], h)
					if name == "boulder" then
						-- boulders are solid; pushing into one tries to roll it
						local w = h * 0.45
						props.physical = true
						props.collide_with_objects = true
						props.collisionbox = {-w, -h / 2, -w, w, h / 2, w}
					else
						props.physical = false
						props.collide_with_objects = false
						props.collisionbox = {0, 0, 0, 0, 0, 0}
					end
					e.obj:set_properties(props)
					e.obj:set_pos(pos)
					e.tile, e.h = map.mem_tile[i], h
					-- small items spin; chests and boxes face you; corpses lie flat
					e.flat = flat
					e.spin = (h == OBJ_H) and not BILLBOARD[name]
					if flat then
						e.obj:set_rotation(vector.new(math.pi / 2, math.random() * math.pi * 2, 0))
					end
				end
				if e then
					e.x, e.y, e.boulder = tx, ty, name == "boulder"
				end
			end
		end
	end
	for i, e in pairs(mobs.objs) do
		if not seen[i] then
			if e.obj:get_pos() then
				e.obj:remove()
			end
			mobs.objs[i] = nil
		end
	end
end

-- ---------------------------------------------------------------- features
-- remembered cmap glyphs drawn as sprites; true = lies flat (traps)
local FEATURES = {
	S_altar = false, S_grave = false, S_throne = false, S_sink = false,
	S_fountain = false, S_tree = false, S_engroom = true, S_engrcorr = true,
}
-- traps are the '^' cmap symbols (plus webs)
local function is_trap(name, gi)
	return gi.sym == 94 or name == "S_web"
end

local function update_features(snap)
	local map = snap.map
	local seen = {}
	for tx = 1, U.COLNO - 1 do
		for ty = 0, U.ROWNO - 1 do
			local i = U.idx(tx, ty)
			local gi = nhv.glyph_info(map.mem[i])
			if gi.kind == "cmap" then
				local name = nhv.cmap_name(gi.index)
				local flat = FEATURES[name]
				if flat == nil and is_trap(name, gi) then
					flat = true
				end
				-- a hand-built prefab replaces the sprite
				local fslot = nhv.terrain.feature_slot(name)
				if fslot and nhv.prefabs.custom(fslot) then
					flat = nil
				end
				if flat ~= nil then
					seen[i] = true
					local e = mobs.feats[i]
					if e and not e.obj:get_pos() then
						e = nil
					end
					local h = flat and 2.4 or (nhv.scale.feature_height(name) or 1.8)
					local pos = U.tile_center(tx, ty, flat and (U.STAND_Y + 0.02)
						or scale.center_y("feat", name, h, U.STAND_Y, U.CEIL_Y - 0.5))
					if not e then
						local obj = core.add_entity(pos, "nhv:feat")
						if obj then
							e = {obj = obj}
							mobs.feats[i] = e
						end
					end
					if e and (e.tile ~= map.mem_tile[i] or e.h ~= h or not vector.equals(e.pos or pos, pos)) then
						e.pos = pos
						local props = sprite_props(map.mem_tile[i], h)
						props.pointable = false
						e.obj:set_properties(props)
						e.obj:set_pos(pos)
						if flat then
							e.obj:set_rotation(vector.new(math.pi / 2, 0, 0))
						end
						e.tile, e.flat, e.h = map.mem_tile[i], flat, h
					end
				end
			end
		end
	end
	for i, e in pairs(mobs.feats) do
		if not seen[i] then
			if e.obj:get_pos() then
				e.obj:remove()
			end
			mobs.feats[i] = nil
		end
	end
end

function mobs.update(snap, level_changed)
	if level_changed then
		mobs.clear()
	end
	update_monsters(snap)
	update_objects(snap)
	update_features(snap)
end

-- monster displayed on a square, if any
function mobs.monster_at(tx, ty)
	for _, e in pairs(mobs.mons) do
		if e.x == tx and e.y == ty then
			return e
		end
	end
end

-- ---------------------------------------------------------------- combat
-- Flash a monster's sprite: "w" = faint white (attacking), "r" = red (hurt)
function mobs.flash(id, kind, secs)
	local e = mobs.mons["id" .. id]
	if not e or not e.tile or not e.obj:get_pos() then
		return
	end
	e.flash_until = core.get_us_time() + (secs or 0.15) * 1e6
	e.obj:set_properties(nhv_tiles.look(e.tile, e.h, kind))
end

-- a quick swipe in front of an attacking monster, toward its target
local function swipe(e, target)
	local pos = e.obj:get_pos()
	if not pos or not target then
		return
	end
	local dir = vector.direction(pos, target)
	local front = vector.add(pos, vector.multiply(dir, math.min(1.2, (e.h or 2) * 0.4)))
	core.add_particle({
		pos = front, velocity = vector.multiply(dir, 2),
		expirationtime = 0.18, size = 6 * math.min(2, (e.h or 2) / 2),
		texture = "nhv_swipe.png", glow = 10,
	})
end

nhv.nh.on_event(function(evs)
	for _, ev in ipairs(evs) do
		if ev.kind == "combat" then
			local kind, a, b, melee = ev.text:match("^(%a+) (%d+) (%d+) (%d)")
			if kind == "attack" then
				a, b = tonumber(a), tonumber(b)
				mobs.flash(a, "w", 0.12)
				local e = mobs.mons["id" .. a]
				if e and melee == "1" then
					local target
					if b == 0 then
						local p = core.get_connected_players()[1]
						target = p and vector.add(p:get_pos(), vector.new(0, 1.2, 0))
					else
						local t = mobs.mons["id" .. b]
						target = t and t.obj:get_pos()
					end
					swipe(e, target)
				end
			end
		end
	end
end)

-- ---------------------------------------------------------------- per step
local clock_t = 0
core.register_globalstep(function(dtime)
	clock_t = clock_t + dtime
	local player = core.get_connected_players()[1]
	local ppos = player and player:get_pos()
	local now = core.get_us_time()
	for _, e in pairs(mobs.mons) do
		local obj = e.obj
		if e.flash_until and now > e.flash_until and obj:get_pos() then
			e.flash_until = nil
			obj:set_properties(nhv_tiles.look(e.tile, e.h))
		end
		if obj:get_pos() and e.h then
			local pos = mon_draw_pos(e)
			obj:move_to(pos, true)
			if ppos then
				local d = vector.subtract(ppos, pos)
				local yaw = math.atan2(d.z, d.x) - math.pi / 2
				if e.wavy then
					yaw = yaw + math.sin(clock_t * 5 + (e.x or 0)) * 0.35
					local w = 1 + 0.18 * math.sin(clock_t * 9 + (e.y or 0))
					obj:set_properties({visual_size = nhv_tiles.size(e.h, w)})
				end
				obj:set_yaw(yaw)
			end
		end
	end
	for _, e in pairs(mobs.objs) do
		if e.flat then -- luacheck: ignore 542
			-- lies still
		elseif e.spin and e.obj:get_pos() then
			e.obj:set_yaw((clock_t * 0.8) % (2 * math.pi))
		elseif e.obj:get_pos() and ppos then
			local pos = e.obj:get_pos()
			local d = vector.subtract(ppos, pos)
			e.obj:set_yaw(math.atan2(d.z, d.x) - math.pi / 2)
		end
	end
	for _, e in pairs(mobs.feats) do
		if not e.flat and e.obj:get_pos() and ppos then
			local pos = e.obj:get_pos()
			local d = vector.subtract(ppos, pos)
			e.obj:set_yaw(math.atan2(d.z, d.x) - math.pi / 2)
		end
	end
end)

return mobs
