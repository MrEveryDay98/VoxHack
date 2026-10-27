-- Dying: a last look at yourself.
--
-- The moment NetHack says you've died (the hero's DIED flag; time has
-- stopped - NetHack is asking its last questions), the camera goes out
-- behind you and circles round and round, your body lies there as a corpse
-- (your sprite gone: avatar.lua), the edges of the screen darken
-- and "You die..." stands in red in the middle of the screen (the hook
-- "death" plays: sound.lua). NetHack's first question, "Do you want your
-- possessions identified?", waits a few seconds and then fades in; the
-- rest come as usual. Your gravestone (ui.show_death) shows over it, the
-- camera still circling; it ends as you leave for the title screen - or,
-- saved by an amulet of life saving, as you come back.

local nh = nhv.nh
local U = nhv.util

local death = {active = false}
nhv.death = death

local SPIN = math.rad(18)  -- the camera's turn, a second
local PITCH = 0.18          -- looking a little down (radians)
local ASK_AFTER = 3         -- seconds before the question shows
local FADE = 1              -- seconds it takes to fade in
local FADE_STEPS = 10

local CORPSE_H = 1.4        -- the corpse's size (nodes)

local scene = nil -- {t=, yaw=, pitch=, hud={}, ask=req, shown=steps, corpse=obj}

core.register_entity("nhv:death_corpse", {
	initial_properties = {
		visual = "wielditem", wield_item = nhv_tiles.item(0),
		physical = false, pointable = false, static_save = false,
		collisionbox = {0, 0, 0, 0, 0, 0},
	},
	on_step = function(self)
		if not (scene and scene.corpse == self.object) then
			self.object:remove()
		end
	end,
})

-- NetHack's corpse picture (the object's: a corpse of anything)
local corpse_tile
local function find_corpse_tile()
	if corpse_tile == nil then
		corpse_tile = false
		for t = 0, nhv_tiles.count - 1 do
			if nhv_tiles.name(t) == "corpse" then
				corpse_tile = t
				break
			end
		end
	end
	return corpse_tile or nil
end

-- your corpse, lying at your feet
local function lay_corpse(player)
	local tile = find_corpse_tile()
	if not tile then
		return
	end
	local p = player:get_pos()
	local obj = core.add_entity(vector.new(p.x, p.y + 0.05, p.z), "nhv:death_corpse")
	if not obj then
		return
	end
	scene.corpse = obj
	obj:set_properties(nhv_tiles.look(tile, CORPSE_H))
	-- (lying flat, as you fell)
	obj:set_rotation(vector.new(math.pi / 2, scene.yaw, 0))
end

local function start(player)
	death.active = true
	scene = {t = 0, yaw = player:get_look_horizontal(), pitch = player:get_look_vertical(), hud = {}}
	nhv.player.freeze(true)
	player:set_velocity(vector.zero())
	player:set_camera({mode = "third"})
	-- your corpse instead of you
	lay_corpse(player)
	nhv.avatar.refresh()
	-- the screen's edges darkened, and "You die..." front and centre
	scene.hud[#scene.hud + 1] = player:hud_add({
		type = "image", position = {x = 0.5, y = 0.5}, alignment = {x = 0, y = 0},
		scale = {x = -100, y = -100}, text = "nhv_vignette.png^[multiply:#200000^[opacity:210", z_index = 50,
	})
	scene.text = {}
	for _, l in ipairs({{0x000000, 4}, {0xE02020, 0}}) do
		scene.text[#scene.text + 1] = player:hud_add({
			type = "text", position = {x = 0.5, y = 0.32}, alignment = {x = 0, y = 0},
			offset = {x = l[2], y = l[2]}, size = {x = 4, y = 0}, number = l[1], text = "You die...",
			z_index = 51,
		})
	end
end

-- your gravestone shows (ui.show_death): "You die..." goes (it would be in
-- the way); the camera keeps circling your corpse behind it
function death.to_grave()
	local player = nhv.player.get()
	if scene and player then
		for _, id in ipairs(scene.text or {}) do
			player:hud_remove(id)
		end
		scene.text = {}
	end
end

function death.finish()
	local s = scene
	scene = nil
	death.active = false
	if not s then
		return
	end
	if s.corpse then
		s.corpse:remove()
	end
	nhv.avatar.refresh()
	local player = nhv.player.get()
	if player and player:is_player() then
		for _, id in ipairs(s.hud) do
			player:hud_remove(id)
		end
		for _, id in ipairs(s.text or {}) do
			player:hud_remove(id)
		end
		player:set_look_horizontal(s.yaw)
		player:set_look_vertical(s.pitch)
		player:set_camera({mode = "first"})
		core.after(0.2, function()
			if player:is_player() and not death.active then
				player:set_camera({mode = "any"})
			end
		end)
	end
end

-- NetHack's question, if it's the one the scene asks itself (ui.lua): kept
-- until it's time to show it
function death.take(req)
	if scene and req.kind == "yn" and req.prompt:find("possessions identified", 1, true) then
		scene.ask, scene.shown = req, 0
		-- (the last question - wizard mode's "Die?" - goes meanwhile)
		local player = nhv.player.get()
		if player and nhv.ui.open == "nhv:req" then
			core.close_formspec(player:get_player_name(), "nhv:req")
			nhv.ui.open = nil
		end
		return true
	end
	return false
end

-- the question, a step further faded in
local function show_ask(player, step)
	local req = scene.ask
	nhv.ui.open = "nhv:req"
	core.show_formspec(player:get_player_name(), "nhv:req", nhv.ui.yn_fading(req, step / FADE_STEPS))
	if step == 1 then
		nhv.sound.hook("dialog_open")
	end
end

core.register_globalstep(function(dtime)
	if not scene then
		return
	end
	local player = nhv.player.get()
	if not player then
		death.finish()
		return
	end
	scene.t = scene.t + dtime
	player:set_look_horizontal(scene.yaw + SPIN * scene.t)
	player:set_look_vertical(PITCH)
	-- the question, once it's been asked and it's time: fading in a step at a
	-- time (answered meanwhile - a key: it's gone)
	local req = scene.ask
	if req and nh.req == req and scene.t >= ASK_AFTER and scene.shown < FADE_STEPS then
		local step = math.min(FADE_STEPS, math.floor((scene.t - ASK_AFTER) / FADE * FADE_STEPS) + 1)
		if step > scene.shown then
			scene.shown = step
			show_ask(player, step)
		end
	end
end)

nh.on_snapshot(function(snap)
	local h = snap and snap.hero
	local dead = h and U.has(h.flags, U.HERO.DIED) or false
	if dead and not scene then
		local player = nhv.player.get()
		if player then
			start(player)
		end
	elseif not dead and scene and h then
		death.finish() -- (life saved)
	end
end)

return death
