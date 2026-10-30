-- Shadows: every monster and object standing up casts one on the floor, its
-- own picture laid flat behind it in black, see-through - one light high up
-- at an angle (SUN_*), the same for everything, VoxHack's own: nothing to do
-- with the sky or the time of day. A shadow is the floor's texture pixels,
-- whole ones: one pixel of the picture to one of the floor's (a 16th of a
-- block), lined up with them - the VoxHack engine keeps an object marked
-- "nhv:texel" on them as it moves (content_cao.h).
-- Setting nhv_shadows (Options > Shadows; default off) turns them on,
-- nhv_shadow_opacity (Options > Shadow opacity) sets how dark they are.

local shadows = {}
nhv.shadows = shadows

local U = nhv.util

local TEXEL = 16 -- (a block's texture pixels across)
local SUN_STRETCH = 0.75 -- (a shadow's length, for a thing's height: the sun's height)
local SUN_YAW = 0 -- (where the shadows point: 0 north, +z)

-- how dark shadows are (0-1): setting nhv_shadow_opacity, in percent
-- (Options > Shadow opacity; 60 by default)
function shadows.strength()
	local pct = tonumber(core.settings:get("nhv_shadow_opacity")) or 60
	return math.max(0, math.min(100, pct)) / 100
end

core.register_entity("nhv:shadow", {
	initial_properties = {
		visual = "upright_sprite", textures = {"blank.png", "blank.png"},
		physical = false, collide_with_objects = false, pointable = false,
		collisionbox = {0, 0, 0, 0, 0, 0}, selectionbox = {0, 0, 0, 0, 0, 0},
		use_texture_alpha = true, shaded = false, static_save = false,
		infotext = "nhv:texel",
	},
	on_activate = function(self)
		self.object:set_armor_groups({immortal = 1})
	end,
})

-- whole texture pixels, an even number of them (the middle on a pixel's edge)
local function texels(nodes)
	return math.max(2, 2 * math.floor(nodes * TEXEL / 2 + 0.5))
end

local cast = {} -- thing (mobs' e) -> {obj=, look=, pos=}

local function drop(e)
	local s = cast[e]
	if s then
		s.obj:remove()
		cast[e] = nil
	end
end

-- e's shadow where it is now (made the first time); ground: the floor's top
local function place(e, ground, alpha)
	local pos = e.obj:get_pos()
	local w, l = texels(e.h), texels(e.h * SUN_STRETCH)
	local look = ("%s^[resize:%dx%d^[transformFY^[multiply:#000000^[opacity:%d"):format(nhv_tiles.texture(e.tile), w, l, alpha)
	local s = cast[e]
	if not s or not s.obj:get_pos() then
		local obj = core.add_entity(pos, "nhv:shadow")
		if not obj then
			return
		end
		-- (lying flat; its picture upside down, the top away from the thing)
		obj:set_rotation(vector.new(math.pi / 2, SUN_YAW, 0))
		s = {obj = obj}
		cast[e] = s
	end
	if s.look ~= look then
		s.look = look
		s.obj:set_properties({textures = {look, look .. "^[transformFX"},
			visual_size = {x = w / TEXEL, y = l / TEXEL}})
	end
	local half = l / TEXEL / 2
	local at = vector.new(pos.x - math.sin(SUN_YAW) * half, ground, pos.z + math.cos(SUN_YAW) * half)
	if not s.pos or vector.distance(s.pos, at) > 1e-3 then
		s.pos = at
		s.obj:set_pos(at)
	end
end

core.register_globalstep(function()
	local mobs = nhv.mobs
	local on = core.settings:get_bool("nhv_shadows", false) and mobs
	local alpha = math.floor(shadows.strength() * 255 + 0.5)
	local keep = {}
	if on and alpha > 0 then
		for _, e in pairs(mobs.mons) do
			if e.h and e.tile and not e.ghost and not e.fuzz and e.obj:get_pos() then
				keep[e] = true
				place(e, e.ground_y or U.STAND_Y, alpha)
			end
		end
		for _, e in pairs(mobs.objs) do
			if e.h and e.tile and not e.flat and e.obj:get_pos() then
				keep[e] = true
				place(e, e.ground or U.STAND_Y, alpha)
			end
		end
	end
	for e in pairs(cast) do
		if not keep[e] then
			drop(e)
		end
	end
end)

return shadows
