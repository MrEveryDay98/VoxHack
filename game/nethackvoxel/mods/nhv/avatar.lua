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
	if p.y ~= y then
		-- (attachment offsets are in tenths of a node; turned round, so
		-- the sprite's front faces the camera behind you)
		p.obj:set_attach(player, "", vector.new(0, y * 10, 0), vector.new(0, 180, 0))
		p.y = y
	end
	return h
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
	-- (invisible, and you can't see invisible: you can't see yourself)
	if me and not U.has(me.flags, U.MON_HIDDEN) then
		show(player, "self", me, seat)
	else
		drop("self")
	end
end

-- your see-through self's fuzz crawls (as monsters' do: mobs.lua)
core.register_globalstep(function()
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
