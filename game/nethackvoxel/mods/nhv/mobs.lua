-- Entities for what NetHack displays on top of the terrain: monsters,
-- objects and dungeon features (fountains, altars, traps, ...).
--
-- Every sprite is a NetHack tile rendered with visual = "wielditem",
-- which Luanti draws as an extruded voxel model.
--
-- Monster movement is tweened between the square a monster was on and
-- the square it moved to, driven by nhv.time.p (0..1), which advances
-- only while the hero moves or acts: stand still and everything freezes.

local U = nhv.util
local mobs = {
	mons = {},      -- key -> {obj=, from=, to=, tile=, flags=, wavy=}
	objs = {},      -- square index -> {obj=, tile=}
	feats = {},     -- square index -> {obj=, tile=}
}
nhv.mobs = mobs

nhv.time = {p = 1}

-- sprite height in nodes per monster size (MZ_TINY .. MZ_GIGANTIC)
local SIZE_H = {[0] = 1.1, 1.5, 2.0, 2.7, 3.5, 4.4}

local function sprite_props(tile, height)
	local s = height / 2
	return {
		wield_item = nhv_tiles.item(tile),
		visual_size = {x = s, y = s, z = s},
		selectionbox = {-s * 0.6, -s, -s * 0.6, s * 0.6, s, s * 0.6},
	}
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
	on_activate = function(self, staticdata)
		if staticdata == "" then
			-- only ever created by this mod at runtime
		end
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

local function mon_height(m)
	if m.size and SIZE_H[m.size] then
		return SIZE_H[m.size]
	end
	return SIZE_H[2]
end

local function mon_pos(tx, ty, height)
	return U.tile_center(tx, ty, U.STAND_Y + height / 2)
end

-- ---------------------------------------------------------------- monsters
local function update_monsters(snap)
	local seen = {}
	local hallu = U.has(snap.hero.flags, U.HERO.HALLU)
	for _, m in ipairs(snap.monsters) do
		local key = m.id > 0 and ("id" .. m.id) or ("at" .. m.x .. "," .. m.y)
		seen[key] = true
		local h = mon_height(m)
		local target = mon_pos(m.x, m.y, h)
		local e = mobs.mons[key]
		if e and not e.obj:get_pos() then
			e = nil
		end
		local wavy = hallu or U.has(m.flags, U.MON_INVIS) or U.has(m.flags, U.MON_DETECTED)
		if not e then
			local obj = core.add_entity(target, "nhv:mon")
			if obj then
				e = {obj = obj, from = target, to = target}
				obj:get_luaentity().nh_key = key
				mobs.mons[key] = e
			end
		else
			e.from = e.obj:get_pos()
			e.to = target
		end
		if e then
			e.x, e.y, e.mon = m.x, m.y, m
			e.wavy = wavy
			e.height = h
			if e.tile ~= m.tile or e.h ~= h then
				e.obj:set_properties(sprite_props(m.tile, h))
				e.tile, e.h = m.tile, h
			end
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

-- ---------------------------------------------------------------- objects
local OBJ_H = 0.8
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
				if gi.kind == "statue" then
					h = 2.0
				elseif name == "boulder" then
					h = BOULDER_H
				end
				local pos = U.tile_center(tx, ty, U.STAND_Y + h / 2)
				if not e then
					local obj = core.add_entity(pos, "nhv:obj")
					if obj then
						e = {obj = obj}
						mobs.objs[i] = e
					end
				end
				if e and (e.tile ~= map.mem_tile[i] or e.h ~= h) then
					e.obj:set_properties(sprite_props(map.mem_tile[i], h))
					e.obj:set_pos(pos)
					e.tile, e.h = map.mem_tile[i], h
					e.spin = (h == OBJ_H)
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
	S_fountain = false, S_engroom = true, S_engrcorr = true,
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
				if flat ~= nil then
					seen[i] = true
					local e = mobs.feats[i]
					if e and not e.obj:get_pos() then
						e = nil
					end
					local h = flat and 2.4 or 1.8
					local pos = U.tile_center(tx, ty,
						flat and (U.STAND_Y + 0.02) or (U.STAND_Y + h / 2))
					if not e then
						local obj = core.add_entity(pos, "nhv:feat")
						if obj then
							e = {obj = obj}
							mobs.feats[i] = e
						end
					end
					if e and e.tile ~= map.mem_tile[i] then
						local props = sprite_props(map.mem_tile[i], h)
						props.pointable = false
						e.obj:set_properties(props)
						e.obj:set_pos(pos)
						if flat then
							e.obj:set_rotation(vector.new(math.pi / 2, 0, 0))
						end
						e.tile, e.flat = map.mem_tile[i], flat
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

-- ---------------------------------------------------------------- per step
local clock = 0
core.register_globalstep(function(dtime)
	clock = clock + dtime
	local p = nhv.time.p
	local player = core.get_connected_players()[1]
	local ppos = player and player:get_pos()
	for _, e in pairs(mobs.mons) do
		local obj = e.obj
		if obj:get_pos() then
			local pos = vector.add(e.from, vector.multiply(vector.subtract(e.to, e.from), p))
			obj:move_to(pos, true)
			if ppos then
				local d = vector.subtract(ppos, pos)
				local yaw = math.atan2(d.z, d.x) - math.pi / 2
				if e.wavy then
					yaw = yaw + math.sin(clock * 5 + (e.x or 0)) * 0.35
					local s = (e.h or 2) / 2
					local w = 1 + 0.18 * math.sin(clock * 9 + (e.y or 0))
					obj:set_properties({visual_size = {x = s * w, y = s / w, z = s}})
				end
				obj:set_yaw(yaw)
			end
		end
	end
	for _, e in pairs(mobs.objs) do
		if e.spin and e.obj:get_pos() then
			e.obj:set_yaw((clock * 0.8) % (2 * math.pi))
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
