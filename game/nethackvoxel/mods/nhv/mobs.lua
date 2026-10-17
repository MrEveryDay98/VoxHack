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

-- ---------------------------------------------------------------- fading
-- Monsters, objects and features NetHack starts or stops showing fade in
-- and out instead of popping, as flat sprites (through transparency). 3D
-- models can't be see-through: they just appear and go.
local FADE_S = 0.35
local fading = {} -- {e=, t0=, out=}

local function fade_apply(e, a)
	if not (e.obj:get_pos() and e.tile and e.h) then
		return
	end
	a = math.max(0.02, math.min(1, a))
	if nhv_tiles.flat() then
		local tex = nhv_tiles.texture(e.tile) .. ("^[opacity:%d"):format(math.floor(a * 255))
		e.obj:set_properties({textures = {tex, tex .. "^[transformFX"}, use_texture_alpha = a < 1})
	else
		local sz = nhv_tiles.size(e.h)
		e.obj:set_properties({visual_size = {x = sz.x * a, y = sz.y * a, z = sz.z * a}})
	end
end

local function fade_in(e)
	if not nhv_tiles.flat() then
		return
	end
	fading[#fading + 1] = {e = e, t0 = core.get_us_time()}
	fade_apply(e, 0)
end

-- (the entity is taken out of its table; it's removed when it has faded)
local function fade_out(e)
	if not e.obj:get_pos() then
		return
	end
	if not nhv_tiles.flat() then
		e.obj:remove()
		return
	end
	e.obj:set_properties({pointable = false})
	fading[#fading + 1] = {e = e, t0 = core.get_us_time(), out = true}
end

local function update_fades()
	local now = core.get_us_time()
	for i = #fading, 1, -1 do
		local f = fading[i]
		local t = (now - f.t0) / (FADE_S * 1e6)
		if not f.e.obj:get_pos() then
			table.remove(fading, i)
		elseif t >= 1 then
			table.remove(fading, i)
			if f.out then
				f.e.obj:remove()
			else
				fade_apply(f.e, 1)
				f.e.obj:set_properties(nhv_tiles.look(f.e.tile, f.e.h)) -- (back to normal)
			end
		else
			fade_apply(f.e, f.out and 1 - t or t)
		end
	end
end

local function remove_all(tbl)
	for k, e in pairs(tbl) do
		if e.obj and e.obj:get_pos() then
			e.obj:remove()
		end
		tbl[k] = nil
	end
end

function mobs.clear()
	for _, f in ipairs(fading) do
		if f.e.obj:get_pos() then
			f.e.obj:remove()
		end
	end
	fading = {}
	remove_all(mobs.mons)
	remove_all(mobs.objs)
	for _, pile in pairs(mobs.piles or {}) do
		remove_all(pile.extras)
	end
	mobs.piles = {}
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
-- the top of a block a body could stand on (nil: not one); shaped blocks
-- (slabs, stair blocks) by their collision or node box
local function block_top(y, nd)
	local def = core.registered_nodes[nd.name]
	if not (def and def.walkable) then
		return nil
	end
	local box = def.collision_box or def.node_box
	if box and box.type == "fixed" and type(box.fixed) == "table" then
		local boxes = type(box.fixed[1]) == "table" and box.fixed or {box.fixed}
		local top = -0.5
		for _, b in ipairs(boxes) do
			top = math.max(top, b[5] or 0.5)
		end
		return y + top
	end
	return y + 0.5
end

-- The ground under a body at (x, z), standing at about from_y now: the
-- highest standable block top at most a step above (a block it could
-- climb: stairs, a raised floor) - not a wall, which has no room above it
-- - down to a few blocks below. nil: nothing found.
local function ground_at(x, z, from_y)
	local rx, rz = math.floor(x + 0.5), math.floor(z + 0.5)
	for y = math.floor(from_y + 1.1), math.floor(from_y - 3), -1 do
		local nd = core.get_node(vector.new(rx, y, rz))
		local top = block_top(y, nd)
		if top and not block_top(y + 1, core.get_node(vector.new(rx, y + 1, rz))) then
			return top
		end
	end
	return nil
end

local function mon_draw_pos(e)
	local body = e.id and e.id > 0 and nhv.sim.body(e.id)
	local base
	if body and body.x == e.x and body.y == e.y then
		base = body.pos
	else
		base = U.tile_center(e.x, e.y)
	end
	-- the ground it walks on: built steps and raised floors carry it up (a
	-- step at a time, eased); a trap square's hole only when it's in it
	local floor = U.STAND_Y
	local map = nhv.nh.snap and nhv.nh.snap.map
	local trap = map and map.trap and e.x and U.in_map(e.x, e.y) and (map.trap[U.idx(e.x, e.y)] or 0) > 0
	if e.mon and U.has(e.mon.flags, U.MON_IN_PIT) then
		floor = nhv.terrain.stand_y(e.x, e.y)
	else
		local g = ground_at(base.x, base.z, e.ground_y or U.STAND_Y)
		if g and not (trap and g < U.STAND_Y) then
			floor = g
		end
	end
	e.ground_y = e.ground_y and (e.ground_y + (floor - e.ground_y) * 0.35) or floor
	local y = scale.mon_center_y(e.mon and e.mon.mndx, e.h, e.ground_y, U.CEIL_Y - 0.5)
	return vector.new(base.x, y, base.z)
end

local function apply_sprite(e, m)
	local h = scale.height(m.size, m.mndx)
	-- a solid body the size of the sprite (Luanti only collides with
	-- "physical" objects); pets stay passable, as you swap places with them
	local solid = m.id > 0 and not U.has(m.flags, U.MON_PET)
	-- a shopkeeper in its shop fills its whole square, so standing inside
	-- the door it really blocks the way out, as in NetHack
	local shk = solid and U.has(m.flags, U.MON_SHOPKEEPER)
	if e.tile ~= m.tile or e.h ~= h or e.solid ~= solid or e.shk ~= shk then
		local props = sprite_props(m.tile, h)
		local w = shk and U.TILE * 0.48 or scale.radius(m.size, m.mndx)
		props.physical = solid
		props.collide_with_objects = solid
		props.collisionbox = solid and {-w, -h / 2, -w, w, h / 2, w} or {0, 0, 0, 0, 0, 0}
		e.obj:set_properties(props)
		e.tile, e.h, e.solid, e.shk = m.tile, h, solid, shk
	end
end

local function update_monsters(snap)
	local seen = {}
	local hallu = U.has(snap.hero.flags, U.HERO.HALLU)
	for _, m in ipairs(snap.monsters) do
		if U.has(m.flags, U.MON_ENGULFING) or U.has(m.flags, U.MON_SELF)
				or U.has(m.flags, U.MON_STEED) then
			goto continue -- (you're inside it: holds.lua; you, your steed: avatar.lua)
		end
		local key = m.id > 0 and ("id" .. m.id) or ("at" .. m.x .. "," .. m.y)
		seen[key] = true
		local e = mobs.mons[key]
		if e and not e.obj:get_pos() then
			e = nil
		end
		local fresh = false
		if not e then
			local obj = core.add_entity(U.tile_center(m.x, m.y), "nhv:mon")
			if obj then
				e = {obj = obj}
				obj:get_luaentity().nh_key = key
				mobs.mons[key] = e
				fresh = true
			end
		end
		if e then
			e.x, e.y, e.mon, e.id = m.x, m.y, m, m.id
			e.wavy = hallu or U.has(m.flags, U.MON_INVIS) or U.has(m.flags, U.MON_DETECTED)
			apply_sprite(e, m)
			e.obj:set_pos(mon_draw_pos(e))
			if fresh then
				fade_in(e)
			end
		end
		::continue::
	end
	for key, e in pairs(mobs.mons) do
		if not seen[key] then
			fade_out(e)
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

-- how an object glyph is drawn: height, lies flat, object name
local function obj_shape(gi)
	local name = core.nh_obj_name(gi.index) or ""
	local flat = gi.kind == "body"
	local h = OBJ_H
	if gi.kind == "statue" then
		h = 2.0
	elseif name == "boulder" then
		h = BOULDER_H
	elseif flat then
		h = 1.4 -- corpses lie on the floor
	elseif BILLBOARD[name] then
		h = 1.4
	end
	return h, flat, name
end

local function is_obj_glyph(g)
	local kind = nhv.glyph_info(g).kind
	return kind == "obj" or kind == "body" or kind == "statue"
end

-- An object that's now a square away (a pushed boulder, ...) glides there
-- instead of going and appearing again: its entity moves to the new square.
local function match_moves(map)
	local moved = {}
	for j, e in pairs(mobs.objs) do
		if e.tile and e.x and map.mem_tile[j] ~= e.tile and e.obj:get_pos() then
			for dx = -1, 1 do
				for dy = -1, 1 do
					local kx, ky = e.x + dx, e.y + dy
					local k = U.in_map(kx, ky) and U.idx(kx, ky)
					local there = k and mobs.objs[k]
					if k and k ~= j and not moved[k] and map.mem_tile[k] == e.tile
							and is_obj_glyph(map.mem[k]) and not (there and there.tile == e.tile) then
						moved[k] = {e = e, from = j, x = kx, y = ky}
						goto next_entity
					end
				end
			end
		end
		::next_entity::
	end
	for k, m in pairs(moved) do
		local displaced = mobs.objs[k]
		if mobs.objs[m.from] == m.e then
			-- (whatever was on the new square takes the old one, or goes)
			mobs.objs[m.from] = nil
			if displaced and is_obj_glyph(map.mem[m.from]) then
				mobs.objs[m.from] = displaced
			elseif displaced then
				fade_out(displaced)
			end
			mobs.objs[k] = m.e
			local from = m.e.obj:get_pos()
			m.e.glide = {from = from, to = U.tile_center(m.x, m.y, from.y), t0 = core.get_us_time()}
			m.e.x, m.e.y = m.x, m.y
		end
	end
end

-- A boulder's solid box is narrower than its picture: in NetHack you can
-- squeeze diagonally between a boulder and a wall (or another boulder), and
-- the box leaves room at the corners for that. Not when NetHack wouldn't
-- let you (carrying over 600, too big, in Sokoban), nor beside a doorway
-- with a door in it (no diagonal moves through those): full width then.
local BOULDER_SQUEEZE_W = 0.6 -- (0.9 nodes either side of it in its square)
local function boulder_w(map, tx, ty, h, hero)
	if hero and U.has(hero.flags, U.HERO.NOSQUEEZE) then
		return h * 0.45
	end
	for _, d in ipairs({{1, 0}, {-1, 0}, {0, 1}, {0, -1}}) do
		local x, y = tx + d[1], ty + d[2]
		if U.in_map(x, y) and map.typ[U.idx(x, y)] == U.TYP.DOOR
				and (map.door[U.idx(x, y)] or 0) >= 2 then
			return h * 0.45
		end
	end
	-- narrow only beside a corner passage: two open squares next to it
	-- that meet at a corner, with something solid in the other corner -
	-- the diagonal step between them squeezes past the boulder. Anywhere
	-- else (a straight corridor...) it fills the way: push it or go round.
	local function open(x, y)
		return U.in_map(x, y) and nhv.terrain.passable(map, x, y)
	end
	for _, dx in ipairs({-1, 1}) do
		for _, dy in ipairs({-1, 1}) do
			if open(tx + dx, ty) and open(tx, ty + dy) and not open(tx + dx, ty + dy) then
				return BOULDER_SQUEEZE_W
			end
		end
	end
	return h * 0.45
end

local function update_objects(snap)
	local map = snap.map
	local seen = {}
	match_moves(map)
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
				local h, flat, name = obj_shape(gi)
				-- (in a pit: at its bottom)
				local ground = nhv.terrain.stand_y(tx, ty)
				local pos = U.tile_center(tx, ty, flat and (ground + 0.03) or (ground + h / 2))
				local fresh = false
				if not e then
					local obj = core.add_entity(pos, "nhv:obj")
					if obj then
						e = {obj = obj}
						mobs.objs[i] = e
						fresh = true
					end
				end
				local bw = name == "boulder" and boulder_w(map, tx, ty, h, snap.hero) or nil
				if e and (e.tile ~= map.mem_tile[i] or e.h ~= h or e.bw ~= bw or e.ground ~= ground) then
					local props = sprite_props(map.mem_tile[i], h)
					e.bw = bw
					if name == "boulder" then
						-- boulders are solid; pushing into one tries to roll it
						local w = bw
						props.physical = true
						props.collide_with_objects = true
						props.collisionbox = {-w, -h / 2, -w, w, h / 2, w}
					else
						props.physical = false
						props.collide_with_objects = false
						props.collisionbox = {0, 0, 0, 0, 0, 0}
					end
					e.obj:set_properties(props)
					if not e.glide then
						e.obj:set_pos(pos)
					end
					e.tile, e.h, e.ground = map.mem_tile[i], h, ground
					-- small items spin; chests and boxes face you; corpses lie flat
					e.flat = flat
					e.spin = (h == OBJ_H) and not BILLBOARD[name]
					if flat then
						e.obj:set_rotation(vector.new(math.pi / 2, math.random() * math.pi * 2, 0))
					end
				end
				if e then
					e.x, e.y, e.boulder = tx, ty, name == "boulder"
					if fresh then
						fade_in(e)
					end
				end
			end
		end
	end
	for i, e in pairs(mobs.objs) do
		if not seen[i] then
			fade_out(e)
			mobs.objs[i] = nil
		end
	end
	mobs.update_piles(snap)
end

-- ---------------------------------------------------------------- piles
-- Several objects on one square: the top one is drawn in the middle (as
-- above) and up to PILE_MAX - 1 more close around it. What lies under the
-- top object is only known on squares you can see (and your own); other
-- squares keep the pile you last saw there while their top stays the same.
local PILE_MAX = 5
local PILE_OFS = {{0.6, 0.4}, {-0.55, 0.5}, {0.45, -0.6}, {-0.6, -0.45}}
mobs.piles = {} -- square index -> {top = tile, items = {{tile=, glyph=}}, extras = {entity...}}

local function set_extra(e, item, tx, ty, k)
	local gi = nhv.glyph_info(item.glyph)
	local h, flat = obj_shape(gi)
	local ox, oz = PILE_OFS[k][1], PILE_OFS[k][2]
	local ground = nhv.terrain.stand_y(tx, ty) -- (in a pit: its bottom)
	local c = U.tile_center(tx, ty, flat and (ground + 0.03 + k * 0.01) or (ground + h / 2))
	local pos = vector.new(c.x + ox, c.y, c.z + oz)
	if e.tile ~= item.tile or e.h ~= h or not vector.equals(e.pos or pos, pos) then
		local props = sprite_props(item.tile, h)
		props.physical = false
		props.collisionbox = {0, 0, 0, 0, 0, 0}
		e.obj:set_properties(props)
		e.obj:set_pos(pos)
		e.tile, e.h, e.pos, e.flat = item.tile, h, pos, flat
		e.spin = (h == OBJ_H) and gi.kind == "obj"
		if flat then
			e.obj:set_rotation(vector.new(math.pi / 2, math.random() * math.pi * 2, 0))
		end
	end
end

function mobs.update_piles(snap)
	local map, hero = snap.map, snap.hero
	for i, top in pairs(mobs.objs) do
		local pile = mobs.piles[i]
		local items
		local visible = U.has(map.flags[i], U.LOC_CANSEE) or (hero.x == top.x and hero.y == top.y)
		if top.boulder then
			items = {} -- (a boulder hides what's under it)
		elseif visible then
			items = {}
			for k, o in ipairs(core.nh_get_floor_objects(top.x, top.y) or {}) do
				if k > 1 and #items < PILE_MAX - 1 then
					items[#items + 1] = {tile = o.tile, glyph = o.glyph}
				end
			end
		elseif pile and pile.top == top.tile then
			items = pile.items -- (as last seen)
		else
			items = {}
		end
		pile = pile or {extras = {}}
		pile.top, pile.items = top.tile, items
		mobs.piles[i] = pile
		for k, item in ipairs(items) do
			local e = pile.extras[k]
			if e and not e.obj:get_pos() then
				e = nil
			end
			local fresh = false
			if not e then
				local obj = core.add_entity(U.tile_center(top.x, top.y), "nhv:obj")
				if obj then
					e = {obj = obj}
					pile.extras[k] = e
					fresh = true
				end
			end
			if e then
				set_extra(e, item, top.x, top.y, k)
				if fresh then
					fade_in(e)
				end
			end
		end
		for k = #items + 1, #pile.extras do
			fade_out(pile.extras[k])
			pile.extras[k] = nil
		end
	end
	for i, pile in pairs(mobs.piles) do
		if not mobs.objs[i] then
			for _, e in pairs(pile.extras) do
				fade_out(e)
			end
			mobs.piles[i] = nil
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

-- a feature's picture when objects hide it: the last one seen for that
-- kind of feature, or the tile named after it
local feature_tiles = {}
local function feature_tile(name)
	if feature_tiles[name] then
		return feature_tiles[name]
	end
	local plain = name:gsub("^S_", ""):gsub("_", " ")
	for t = 0, 6000 do
		local n = nhv_tiles.name(t)
		if n and (n == plain or n:sub(-#plain - 1) == " " .. plain) then
			feature_tiles[name] = t
			return t
		end
	end
	return 0
end

local function update_features(snap)
	local map = snap.map
	local seen = {}
	for tx = 1, U.COLNO - 1 do
		for ty = 0, U.ROWNO - 1 do
			local i = U.idx(tx, ty)
			local gi = nhv.glyph_info(map.mem[i])
			local name = gi.kind == "cmap" and nhv.cmap_name(gi.index)
			local tile = map.mem_tile[i]
			if name and FEATURES[name] == false then
				feature_tiles[name] = tile
			end
			-- NetHack remembers only the top thing on a square: an altar,
			-- fountain... with objects on it is still there once seen
			if not name and U.has(map.flags[i], U.LOC_SEEN) and map.back and map.back[i] ~= 255 then
				local real = nhv.cmap_name(map.back[i])
				if FEATURES[real] == false then
					name = real
					tile = feature_tile(real)
				end
			end
			if name then
				local flat = FEATURES[name]
				if flat == nil and is_trap(name, gi) then
					flat = true
				end
				-- a hand-built prefab replaces the sprite; so does a trap's
				-- default one that has blocks (the pits' holes). (An altar's,
				-- fountain's... default is just the room around it.)
				local fslot = nhv.terrain.feature_slot(name)
				local info = fslot and nhv.prefabs.SLOT_INFO[fslot]
				if fslot and (nhv.prefabs.custom(fslot) or (info and info.kind ~= "base"
						and next(nhv.prefabs.get(fslot).nodes))) then
					flat = nil
				end
				if flat ~= nil then
					seen[i] = true
					local e = mobs.feats[i]
					if e and not e.obj:get_pos() then
						e = nil
					end
					local h = flat and 2.4 or (nhv.scale.feature_height(name) or 1.8)
					-- (a pit's trap sprite lies at its bottom)
					local pos = U.tile_center(tx, ty, flat and (nhv.terrain.stand_y(tx, ty) + 0.02)
						or scale.center_y("feat", name, h, U.STAND_Y, U.CEIL_Y - 0.5))
					local fresh = false
					if not e then
						local obj = core.add_entity(pos, "nhv:feat")
						if obj then
							e = {obj = obj}
							mobs.feats[i] = e
							fresh = true
						end
					end
					if e and (e.tile ~= tile or e.h ~= h or not vector.equals(e.pos or pos, pos)) then
						e.pos = pos
						local props = sprite_props(tile, h)
						props.pointable = false
						e.obj:set_properties(props)
						e.obj:set_pos(pos)
						if flat then
							e.obj:set_rotation(vector.new(math.pi / 2, 0, 0))
						end
						e.tile, e.flat, e.h = tile, flat, h
					end
					if fresh and e then
						fade_in(e)
					end
				end
			end
		end
	end
	for i, e in pairs(mobs.feats) do
		if not seen[i] then
			fade_out(e)
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
	if kind == "r" then
		mobs.blood(e)
	end
end

-- a spray of red particles from a monster that was hurt
function mobs.blood(e)
	local pos = e.obj:get_pos()
	if not pos then
		return
	end
	local h = e.h or 1.5
	local w = h * 0.3
	core.add_particlespawner({
		amount = math.floor(14 + h * 8), time = 0.08,
		minpos = vector.offset(pos, -w, -h * 0.25, -w), maxpos = vector.offset(pos, w, h * 0.3, w),
		minvel = vector.new(-2.2, 0.5, -2.2), maxvel = vector.new(2.2, 3.5, 2.2),
		minacc = vector.new(0, -12, 0), maxacc = vector.new(0, -12, 0),
		minexptime = 0.35, maxexptime = 0.8, minsize = 0.8, maxsize = 2.0,
		collisiondetection = true, collision_removal = true,
		texture = "[fill:2x2:#b01010", glow = 2,
	})
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
			-- a monster died (even from one hit): blood where its body was
			local dead = kind == "die" and mobs.mons["id" .. a]
			if dead and dead.obj:get_pos() then
				mobs.blood(dead)
			end
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

-- ---------------------------------------------------------------- rolling boulders
-- A rolling boulder trap's boulder (NetHack's "roll" event: tile, from,
-- to, gone) slides along the ground from where it started to where it
-- stopped, at ROLL_SPEED (facing you, like any boulder - not turning over);
-- the boulder NetHack already put there
-- stays hidden until it arrives. One that fell into a pit or a hole ends
-- in a puff of dust.
local ROLL_SPEED = 12 -- nodes per second
local rolls = {}

core.register_entity("nhv:roller", {
	initial_properties = {
		visual = "wielditem", wield_item = nhv_tiles.item(0),
		visual_size = {x = 0.5, y = 0.5, z = 0.5},
		physical = false, pointable = false, static_save = false,
		collisionbox = {0, 0, 0, 0, 0, 0}, shaded = true,
	},
})

local function dust(pos)
	core.add_particlespawner({
		amount = 30, time = 0.15, pos = pos, radius = vector.new(0.8, 0.2, 0.8),
		vel = {min = vector.new(-1.5, 0.3, -1.5), max = vector.new(1.5, 2, 1.5)},
		acc = vector.new(0, -3, 0), exptime = {min = 0.5, max = 1.1}, size = {min = 2, max = 4},
		texture = {name = "[fill:2x2:#8a8070", alpha_tween = {0.9, 0}, blend = "alpha"},
	})
end

local function start_roll(tile, x0, y0, x1, y1, gone)
	local y = U.STAND_Y + BOULDER_H / 2
	local from, to = U.tile_center(x0, y0, y), U.tile_center(x1, y1, y)
	local obj = core.add_entity(from, "nhv:roller")
	if not obj then
		return
	end
	obj:set_properties(nhv_tiles.look(tile, BOULDER_H))
	local d = vector.distance(from, to)
	rolls[#rolls + 1] = {obj = obj, from = from, to = to, t0 = core.get_us_time(),
		dur = math.max(0.1, d / ROLL_SPEED), gone = gone, dest = U.idx(x1, y1)}
end

local function update_rolls(now)
	for k = #rolls, 1, -1 do
		local r = rolls[k]
		local t = (now - r.t0) / 1e6 / r.dur
		-- (the real one at the end: out of sight until this gets there)
		local there = mobs.objs[r.dest]
		if t < 1 and there and there.obj:get_pos() and not there.rolled_in then
			there.rolled_in = true
			there.obj:set_properties({is_visible = false})
		end
		if t >= 1 or not r.obj:get_pos() then
			if r.obj:get_pos() then
				r.obj:remove()
			end
			if there and there.rolled_in and there.obj:get_pos() then
				there.rolled_in = nil
				there.obj:set_properties({is_visible = true})
			end
			if r.gone then
				dust(r.to)
			end
			table.remove(rolls, k)
		else
			local pos = vector.add(r.from, vector.multiply(vector.subtract(r.to, r.from), t))
			r.obj:move_to(pos, true)
			-- (facing you, as boulders do)
			local player = core.get_connected_players()[1]
			local pp = player and player:get_pos()
			if pp then
				r.obj:set_yaw(math.atan2(pp.z - pos.z, pp.x - pos.x) - math.pi / 2)
			end
		end
	end
end

nhv.nh.on_event(function(evs)
	for _, ev in ipairs(evs) do
		if ev.kind == "combat" then
			local tile, x0, y0, x1, y1, gone = ev.text:match("^roll (%d+) (%d+) (%d+) (%d+) (%d+) (%d)")
			if tile then
				start_roll(tonumber(tile), tonumber(x0), tonumber(y0), tonumber(x1), tonumber(y1), gone == "1")
			end
		end
	end
end)

core.register_globalstep(function()
	if #rolls > 0 then
		update_rolls(core.get_us_time())
	end
end)

-- ---------------------------------------------------------------- asleep
-- A sleeping monster you can see breathes out Z's: one every so often,
-- drifting up and away from its head, growing and fading.
local Z_EVERY = 1.1 -- seconds between Z's (per monster, give or take)
local z_next = {}   -- monster id -> time of its next Z
local function sleep_zs()
	local now = core.get_us_time() / 1e6
	local MF = nhv.sim and nhv.sim.MF
	if not MF then
		return
	end
	for id, b in pairs(nhv.sim.mons) do
		local e = mobs.mons["id" .. id]
		local pos = e and e.obj:get_pos()
		if pos and U.has(b.flags or 0, MF.ASLEEP) and U.has(b.flags or 0, MF.VISIBLE) then
			if not z_next[id] then
				z_next[id] = now + math.random() * Z_EVERY -- (not all in step)
			elseif now >= z_next[id] then
				z_next[id] = now + Z_EVERY * (0.8 + math.random() * 0.4)
				local h = e.h or 1.5
				local side = (math.random() - 0.5) * 0.6
				core.add_particle({
					pos = vector.offset(pos, side * 0.5, h * 0.45 + 0.15, side * 0.5),
					velocity = vector.new(side, 0.55, (math.random() - 0.5) * 0.6),
					expirationtime = 2.2,
					size = 1.6,
					texture = {name = "nhv_z.png^[multiply:#E8F0FF", alpha_tween = {1, 0},
						scale_tween = {0.6, 1.5}},
					glow = 10,
				})
			end
		else
			z_next[id] = nil
		end
	end
	for id in pairs(z_next) do
		if not nhv.sim.mons[id] then
			z_next[id] = nil -- (gone: died, left the level)
		end
	end
end
core.register_globalstep(sleep_zs)

-- ---------------------------------------------------------------- per step
-- objects that moved a square (a pushed boulder) slide there, slowing at
-- the end
local GLIDE_S = 0.35
local function update_glides(now)
	for _, e in pairs(mobs.objs) do
		local g = e.glide
		if g then
			local t = (now - g.t0) / (GLIDE_S * 1e6)
			if not e.obj:get_pos() then
				e.glide = nil
			elseif t >= 1 then
				e.glide = nil
				e.obj:set_pos(g.to)
			else
				local k = t * (2 - t)
				e.obj:move_to(vector.add(g.from, vector.multiply(vector.subtract(g.to, g.from), k)), true)
			end
		end
	end
end

local clock_t = 0
core.register_globalstep(function(dtime)
	clock_t = clock_t + dtime
	update_fades()
	update_glides(core.get_us_time())
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
	-- small items spin, the rest face you, corpses lie still
	local function turn_obj(e)
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
	for _, e in pairs(mobs.objs) do
		turn_obj(e)
	end
	for _, pile in pairs(mobs.piles) do
		for _, e in pairs(pile.extras) do
			turn_obj(e)
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
