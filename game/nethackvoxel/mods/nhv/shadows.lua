-- Hard shadows: every monster, object and (in third person) you cast a
-- shadow - its own sprite, blacked out and lying on the floor at its feet,
-- stretched away from one light high up at an angle (SUN_*), the same for
-- everything. Flat things (corpses, traps) don't; nor does what you only
-- sense (ghosts), see through (invisible ones: their fuzz), or can't see
-- at all. A floating or flying monster's shadow is on the floor under it.
-- A sprite is a flat picture standing up, turned to face you (wobbling
-- when you hallucinate), and its shadow is exactly that picture projected
-- along the light onto the floor: its bottom edge where it stands, its top
-- pushed out along the light - slanting as the sprite turns, down to a
-- sliver when it's edge on to the light. (Drawn as a rectangle lying along
-- the sprite's bottom edge, the slant made by shifting each row of pixels
-- sideways in the texture: whole pixels, as the pixel art itself.)
-- Its base is the sprite's bottom edge, corner to corner, wherever it turns.
-- Setting nhv_shadows (Options > Shadows; default on) turns them off,
-- nhv_shadow_opacity (Options > Shadow opacity) sets how dark they are.

local U = nhv.util
local shadows = {}
nhv.shadows = shadows

local SUN_ELEVATION = math.rad(55) -- (higher: shorter shadows)
local SUN_AZIMUTH = math.rad(200) -- (where the shadows point, round from +z)
local LIFT = 0.02 -- (above the floor, so it doesn't flicker into it)

local STRETCH = 1 / math.tan(SUN_ELEVATION)
local DIR = vector.new(math.sin(SUN_AZIMUTH), 0, math.cos(SUN_AZIMUTH))

core.register_entity("nhv:shadow", {
	initial_properties = {
		visual = "upright_sprite", textures = {"blank.png", "blank.png"},
		physical = false, pointable = false, static_save = false,
		collisionbox = {0, 0, 0, 0, 0, 0}, use_texture_alpha = true,
		shaded = false, backface_culling = false,
	},
})

local cast = {} -- owner table (a monster's, an object's, you) -> {obj=, tile=, h=, pos=}

local function drop(owner)
	local s = cast[owner]
	if s and s.obj:get_pos() then
		s.obj:remove()
	end
	cast[owner] = nil
end

local PX = 16 -- (a tile's pixels)

-- how dark shadows are (0-255): setting nhv_shadow_opacity, in percent
-- (Options > Shadow opacity; 60 by default)
function shadows.alpha()
	local pct = tonumber(core.settings:get("nhv_shadow_opacity")) or 60
	return math.floor(math.max(0, math.min(100, pct)) * 2.55 + 0.5)
end

-- the sprite, blacked out, each row of pixels shifted: row r (0 = the top)
-- `shift(r)` pixels right, on a canvas `width` pixels wide
local function sheared(tile, width, shift)
	local base = nhv_tiles.texture(tile)
	local parts = {("[combine:%dx%d"):format(width, PX)}
	for r = 0, PX - 1 do
		local row = ("%s^[sheet:1x%d:0,%d^[colorize:#000000:255"):format(base, PX, r)
		parts[#parts + 1] = ("%d,%d="):format(shift(r), r) .. (row:gsub("[%^:]", "\\%0"))
	end
	return table.concat(parts, ":") .. ("^[opacity:%d"):format(shadows.alpha())
end

-- owner's shadow: tile `tile`, `w` nodes wide and `h` tall, standing on the
-- floor at feet, turned to yaw (its picture's left-to-right along
-- (cos yaw, sin yaw), as an upright sprite's). With `body` (you: your
-- player), it's attached to it - moving exactly with it, and shown only
-- when your body is (not in first person) - feet being where it stands.
local function show(owner, tile, w, h, feet, yaw, body)
	local s = cast[owner]
	if s and not s.obj:get_pos() then
		s = nil
	end
	if not s then
		local obj = core.add_entity(feet, "nhv:shadow")
		if not obj then
			return
		end
		s = {obj = obj}
		cast[owner] = s
	end
	local W = vector.new(math.cos(yaw), 0, math.sin(yaw))
	local U = vector.multiply(DIR, h * STRETCH) -- (where the top lands)
	-- Lying flat along the sprite's bottom edge, right along W and up along
	-- N, across it. It turns with the sprite and never turns round: when
	-- the light moves to the other side of the edge the shadow shrinks to
	-- a line one pixel thin and grows out on that side, its picture upside down (from
	-- this side), swapped while it's that line - so it never jumps
	local N = vector.new(-W.z, 0, W.x)
	local az = math.atan2(N.x, N.z)
	local ux, uy = vector.dot(U, W), vector.dot(U, N)
	-- (the slant, in pixels from bottom row to top)
	local slant = math.floor(math.abs(ux) / w * PX + 0.5)
	local key = ("%d/%d/%s/%s/%d"):format(tile, slant, tostring(ux < 0), tostring(uy < 0), shadows.alpha())
	-- (all of a change in one go, so no frame shows half of it)
	local props = {}
	if s.key ~= key then
		local function shift(r)
			local k = math.floor(slant * (PX - 0.5 - r) / PX + 0.5) -- (0 at the bottom)
			return ux < 0 and slant - k or k
		end
		local tex = sheared(tile, PX + slant, shift) .. (uy < 0 and "^[transformFY" or "")
		props.textures = {tex, tex}
		s.key = key
	end
	-- (never thinner than one of the sprite's pixels)
	local size = {x = w * (PX + slant) / PX, y = math.max(h / PX, math.abs(uy)), z = h}
	if not (s.size and math.abs(s.size.x - size.x) < 0.005 and math.abs(s.size.y - size.y) < 0.005) then
		props.visual_size = size
		s.size = size
	end
	if next(props) then
		s.obj:set_properties(props)
	end
	-- (the parallelogram's middle: halfway to where the top lands)
	local mid = vector.multiply(U, 0.5)
	if body then
		-- in the body's own turned frame (attachments turn with it; offsets
		-- in tenths of a node, angles in degrees - and an attachment's yaw
		-- and pitch turn the other way from set_rotation's, which the engine
		-- inverts)
		local by = body:get_look_horizontal()
		local c, sn = math.cos(by), math.sin(by)
		local off = vector.new((mid.x * c + mid.z * sn) * 10, LIFT * 10, (-mid.x * sn + mid.z * c) * 10)
		local rot = vector.new(90, math.deg(az + by), 0)
		if not (s.body == body and s.off and vector.distance(s.off, off) < 0.05
				and math.abs(s.rot.y - rot.y) < 0.5) then
			s.obj:set_attach(body, "", off, rot)
			s.body, s.off, s.rot = body, off, rot
		end
		return
	end
	if s.az ~= az then
		s.obj:set_rotation(vector.new(-math.pi / 2, -az, 0))
		s.az = az
	end
	local pos = vector.add(feet, mid)
	pos.y = feet.y + LIFT
	if not (s.pos and vector.distance(s.pos, pos) < 0.01) then
		-- (gliding there, as the monster it belongs to does: not in jumps)
		s.obj:move_to(pos, true)
		s.pos = pos
	end
end

local function feet_of(e)
	local pos = e.obj:get_pos()
	if not (pos and e.h) then
		return nil
	end
	-- (a monster stands on ground_y, even flying; the rest are drawn with
	-- their middle half their height up)
	return vector.new(pos.x, e.ground_y or (pos.y - e.h / 2), pos.z)
end

core.register_globalstep(function()
	local live = {}
	local mobs = nhv.mobs
	if core.settings:get_bool("nhv_shadows", true) and mobs then
		local function add(owner, tile, h, feet, yaw, w, body)
			if tile and feet then
				live[owner] = true
				show(owner, tile, w or h, h, feet, yaw or 0, body)
			end
		end
		-- (how wide e's sprite is drawn now: wobbling, a hallucination's)
		local function width(e)
			if e.wavy then
				local vs = e.obj:get_properties().visual_size
				local s = nhv_tiles.size(e.h)
				return e.h * vs.x / s.x
			end
			return e.h
		end
		for _, e in pairs(mobs.mons) do
			local m = e.mon
			if m and not e.ghost and not e.fuzz and m.id and m.id > 0
					and not U.has(m.flags, U.MON_WARNING) then
				add(e, e.tile, e.h, feet_of(e), e.obj:get_yaw(), width(e))
			end
		end
		local function obj(e)
			if not e.flat then
				add(e, e.tile, e.h, feet_of(e), e.obj:get_yaw())
			end
		end
		for _, e in pairs(mobs.objs) do
			obj(e)
		end
		for _, pile in pairs(mobs.piles) do
			for _, e in pairs(pile.extras) do
				obj(e)
			end
		end
		-- you, in third person (attached to you, it's only shown then, as
		-- your sprite is) - unless you're invisible
		local me = nhv.avatar and nhv.avatar.self()
		local player = nhv.player.get()
		if me and player and not me.fuzz then
			-- (your sprite faces the camera behind you: your look, turned round)
			add(me, me.tile, me.h, player:get_pos(), player:get_look_horizontal() + math.pi, nil, player)
		end
	end
	for owner in pairs(cast) do
		if not live[owner] then
			drop(owner)
		end
	end
end)

return shadows
