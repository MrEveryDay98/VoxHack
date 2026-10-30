-- You, seen from outside: in third person your NetHack sprite stands where
-- you are, and what you're riding is drawn under you. Both are attached to
-- the player, and the engine shows things attached to you only when the
-- camera isn't first person - so in first person neither is in the way.
-- (NetHack lists you and your steed among the monsters with MON_SELF and
-- MON_STEED; mobs.lua leaves them to this.)

local U = nhv.util
local nh = nhv.nh
local scale = nhv.scale
local avatar = {}
nhv.avatar = avatar

core.register_entity("nhv:avatar", {
	initial_properties = {
		visual = "wielditem", wield_item = nhv_tiles.item(0),
		visual_size = {x = 0.5, y = 0.5, z = 0.5},
		physical = false, pointable = false, static_save = false,
		collisionbox = {0, 0, 0, 0, 0, 0}, shaded = true,
	},
	on_step = function(self)
		-- (left behind: the player it belonged to is gone)
		if not self.object:get_attach() then
			self.object:remove()
		end
	end,
})

local parts = {} -- "self" / "steed" -> {obj=, tile=, h=, y=}

local function drop(key)
	local p = parts[key]
	if p and p.obj:get_pos() then
		p.obj:remove()
	end
	parts[key] = nil
end

-- which way round your sprites are on you (degrees, turned from your
-- facing) so their fronts face the camera: behind you, turned right round;
-- in front of you (third person, from the front), as you face
local function facing(player)
	local cam, pos = U.camera_pos(player), player:get_pos()
	local d = cam and vector.subtract(cam, pos)
	if not d or d.x * d.x + d.z * d.z < 0.09 then
		return 180 -- (first person: not seen anyway)
	end
	-- (its back to the camera: mobs.lua's FACING)
	local yaw = math.atan2(d.z, d.x) + math.pi / 2 - player:get_look_horizontal()
	return math.floor(math.deg(yaw) % 360 + 0.5)
end

-- the sprite `key` with tile m.tile, its middle y nodes above your feet
-- (invisible but seen - See_invisible: see-through, nhv_tiles.fuzz_look)
local function show(player, key, m, y)
	local p = parts[key]
	if p and (not p.obj:get_pos() or p.obj:get_attach() ~= player) then
		drop(key)
		p = nil
	end
	if not p then
		local obj = core.add_entity(player:get_pos(), "nhv:avatar")
		if not obj then
			return
		end
		p = {obj = obj}
		parts[key] = p
	end
	local h = scale.height(m.size, m.mndx)
	local fuzz = U.has(m.flags, U.MON_SEEINVIS)
	if p.tile ~= m.tile or p.h ~= h or p.fuzz ~= fuzz then
		if fuzz then
			p.obj:set_properties(nhv_tiles.fuzz_look(m.tile, h))
			p.fuzz_frame = nhv_tiles.fuzz_frame()
		else
			-- (back from see-through: a solid voxel model again)
			local props = nhv_tiles.look(m.tile, h)
			props.use_texture_alpha = false
			p.obj:set_properties(props)
		end
		p.tile, p.h, p.fuzz = m.tile, h, fuzz
	end
	y = y + h / 2
	local rot = facing(player)
	if p.y ~= y or p.rot ~= rot then
		-- (attachment offsets are in tenths of a node; turned so the
		-- sprite's front faces the camera)
		p.obj:set_attach(player, "", vector.new(0, y * 10, 0), vector.new(0, rot, 0))
		p.y, p.rot = y, rot
	end
	return h
end

-- draw your sprite (and your steed's) again, whatever it was (ASCII mode
-- turned on or off: ascii.lua)
function avatar.refresh()
	for _, p in pairs(parts) do
		p.tile = nil
	end
	if nhv.nh.snap then
		avatar.update(nhv.nh.snap)
	end
end

-- your sprite as drawn now ({obj=, tile=, h=, fuzz=}), or nil (shadows.lua)
function avatar.self()
	local p = parts.self
	return p and p.obj:get_pos() and p or nil
end

function avatar.update(snap)
	local player = nhv.player.get()
	if not player or not snap then
		drop("self")
		drop("steed")
		return
	end
	local me, steed
	for _, m in ipairs(snap.monsters or {}) do
		if U.has(m.flags, U.MON_SELF) then
			me = m
		elseif U.has(m.flags, U.MON_STEED) then
			steed = m
		end
	end
	-- (riding: you sit on its back, about half way up it)
	local seat = 0
	if steed then
		local sh = show(player, "steed", steed, 0)
		seat = (sh or 0) * 0.55
	else
		drop("steed")
	end
	-- (invisible, and you can't see invisible: you can't see yourself;
	-- dead, your corpse lies there instead - death.lua; ascended, you're
	-- gone into the light - cutscene.lua)
	if me and not U.has(me.flags, U.MON_HIDDEN) and not (nhv.death and nhv.death.active)
			and not (nhv.cutscene and nhv.cutscene.hide_self) then
		show(player, "self", me, seat)
	else
		drop("self")
	end
end

-- your see-through self's fuzz crawls (as monsters' do: mobs.lua); your
-- sprites keep facing the camera as it moves round you
core.register_globalstep(function()
	local player = nhv.player.get()
	if player then
		local rot = facing(player)
		for _, part in pairs(parts) do
			if part.rot ~= rot and part.y and part.obj:get_pos() then
				part.obj:set_attach(player, "", vector.new(0, part.y * 10, 0), vector.new(0, rot, 0))
				part.rot = rot
			end
		end
	end
	local p = parts.self
	if p and p.fuzz and p.obj:get_pos() then
		local frame = nhv_tiles.fuzz_frame()
		if p.fuzz_frame ~= frame then
			p.fuzz_frame = frame
			p.obj:set_properties({textures = nhv_tiles.fuzz_textures(p.tile, frame)})
		end
	end
end)

nh.on_snapshot(function(snap)
	avatar.update(snap)
end)

core.register_on_leaveplayer(function()
	drop("self")
	drop("steed")
end)

return avatar
