-- Shadows: every monster and object standing up casts one on the floor:
-- its model's (an extruded sprite's, thick; a flat one's), turned as it is,
-- from one light high up at an angle (SUN_*), the same for everything,
-- VoxHack's own - nothing to do with the sky or the time of day - black,
-- see-through. The VoxHack engine casts an object marked "nhv:shadow" so
-- (content_cao.h, nhv_shadow_shader) on the floor's texture pixels, whole
-- ones: a 16th of a block in it or not.
-- Setting nhv_shadows (Options > Shadows; default off) turns them on,
-- nhv_shadow_opacity (Options > Shadow opacity) sets how dark they are.

local shadows = {}
nhv.shadows = shadows

local U = nhv.util

local SUN_ELEVATION = math.rad(53) -- (how high the light is: a shadow 0.75 of its thing's height)
local SUN_YAW = 0 -- (where the shadows point: 0 north, +z)
local EXTRUDED_THICK = 0.1 -- (an extruded sprite's thickness, for its width: wieldmesh's)

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
		infotext = "nhv:shadow",
	},
	on_activate = function(self)
		self.object:set_armor_groups({immortal = 1})
	end,
})

local cast = {} -- thing (mobs' e) -> {obj=, look=, pos=, yaw=}

local function drop(e)
	local s = cast[e]
	if s then
		s.obj:remove()
		cast[e] = nil
	end
end

-- e's shadow where it is now (made the first time); ground: the floor's top;
-- billboard: e is turned to the camera by the engine (and its shadow so)
local function place(e, ground, alpha, billboard)
	local pos = e.obj:get_pos()
	local tex = (e.texture or nhv_tiles.texture(e.tile)) .. "^[multiply:#000000" .. ("^[opacity:%d"):format(alpha)
	-- (an extruded sprite's shadow is a voxel model's, as thick as it is)
	local thick = nhv_tiles.flat() and 0 or e.h * EXTRUDED_THICK
	local s = cast[e]
	if not s or not s.obj:get_pos() then
		local obj = core.add_entity(pos, "nhv:shadow")
		if not obj then
			return
		end
		if billboard then
			obj:set_properties({infotext = "nhv:shadow_billboard"})
		end
		s = {obj = obj}
		cast[e] = s
	end
	if s.look ~= tex or s.h ~= e.h or s.thick ~= thick then
		s.look, s.h, s.thick = tex, e.h, thick
		s.obj:set_properties({textures = {tex, tex}, visual_size = {x = e.h, y = e.h, z = thick}})
	end
	local at = vector.new(pos.x, ground, pos.z)
	if not s.pos or vector.distance(s.pos, at) > 1e-3 then
		s.pos = at
		s.obj:set_pos(at)
	end
	local yaw = e.obj:get_yaw() or 0
	if s.yaw ~= yaw then
		s.yaw = yaw
		s.obj:set_rotation(vector.new(SUN_ELEVATION, yaw, SUN_YAW))
	end
end

core.register_globalstep(function()
	local mobs = nhv.mobs
	local on = core.settings:get_bool("nhv_shadows", false)
	local alpha = math.floor(shadows.strength() * 255 + 0.5)
	local keep = {}
	-- (the opening's trees and figures: turned to the camera by the engine,
	-- their shadows with them)
	if on and alpha > 0 and nhv.intro_blocks then
		for _, sp in ipairs(nhv.intro_blocks.standing()) do
			keep[sp] = true
			place(sp, sp.ground, alpha, true)
		end
	end
	if on and alpha > 0 and mobs then
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
