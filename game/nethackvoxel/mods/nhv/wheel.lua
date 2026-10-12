-- Action wheel.
--
-- Tap right click (or E) for the obvious action. Hold it and a wheel of
-- actions opens around the crosshair; move the mouse toward one and let
-- go to pick it (let go near the middle to cancel). The camera is put
-- back where it was when the wheel closes.

local nh = nhv.nh
local wheel = {}
nhv.wheel = wheel

local HOLD_US = 220000   -- held longer than this = open the wheel
local DEADZONE = 0.06    -- radians of mouse movement before anything is picked

local state = nil        -- {button=, t0=, yaw=, pitch=, list=, primary=, open=, sel=, hud={}}

local function angle_diff(a, b)
	local d = a - b
	while d > math.pi do d = d - 2 * math.pi end
	while d < -math.pi do d = d + 2 * math.pi end
	return d
end

local function entry_angle(k, n)
	-- first entry at the top, going clockwise (screen y grows downwards)
	return -math.pi / 2 + (k - 1) * 2 * math.pi / n
end

local function radius(n)
	return 70 + 14 * n
end

local function hud_remove(player)
	if state and state.hud then
		for _, id in ipairs(state.hud) do
			player:hud_remove(id)
		end
	end
	if state then
		state.hud = {}
	end
end

local function draw(player)
	hud_remove(player)
	local n = #state.list
	local r = radius(n)
	state.hud = {}
	for k, a in ipairs(state.list) do
		local ang = entry_angle(k, n)
		local ox, oy = math.cos(ang) * r, math.sin(ang) * r
		local sel = state.sel == k
		local w = math.max(90, #a.label * 9 + 20)
		state.hud[#state.hud + 1] = player:hud_add({
			type = "image", position = {x = 0.5, y = 0.5}, alignment = {x = 0, y = 0},
			offset = {x = ox, y = oy}, scale = {x = w, y = 30},
			text = sel and "[fill:1x1:#E0A020D0" or "[fill:1x1:#101018C0",
			z_index = 100,
		})
		state.hud[#state.hud + 1] = player:hud_add({
			type = "text", position = {x = 0.5, y = 0.5}, alignment = {x = 0, y = 0},
			offset = {x = ox, y = oy}, number = sel and 0x000000 or 0xFFFFFF,
			text = a.label, z_index = 101,
		})
	end
	state.hud[#state.hud + 1] = player:hud_add({
		type = "text", position = {x = 0.5, y = 0.5}, alignment = {x = 0, y = 0},
		offset = {x = 0, y = 0}, number = 0xC0C0C0,
		text = state.sel and "" or "(move to pick)", z_index = 101,
	})
end

local function pick(player)
	local dyaw = angle_diff(player:get_look_horizontal(), state.yaw)
	local dpitch = player:get_look_vertical() - state.pitch
	-- turning right decreases yaw; looking down increases pitch
	local dx, dy = -dyaw, dpitch
	if math.sqrt(dx * dx + dy * dy) < DEADZONE then
		return nil
	end
	local ang = math.atan2(dy, dx)
	local n = #state.list
	local best, bd
	for k = 1, n do
		local d = math.abs(angle_diff(ang, entry_angle(k, n)))
		if not bd or d < bd then
			best, bd = k, d
		end
	end
	return best
end

local function close(player, run)
	if not state then
		return
	end
	hud_remove(player)
	if state.open then
		player:set_look_horizontal(state.yaw)
		player:set_look_vertical(state.pitch)
	end
	local choice = run
	state = nil
	if choice then
		nhv.actions.run(choice, {kind = "wheel"})
	end
end

-- list, primary for a button
local function context_for(player, button)
	if button == "place" then
		return nhv.actions.context(player)
	end
	local invlet = player:get_wielded_item():get_meta():get_string("nhv_invlet")
	if invlet == "" then
		return nil
	end
	for _, o in ipairs(nh.snap.inventory) do
		if o.invlet == invlet then
			return nhv.actions.item_context(o)
		end
	end
end

core.register_globalstep(function()
	local player = nhv.player.get()
	if not player or not nh.snap then
		return
	end
	local ctl = player:get_player_control()
	if not state then
		local button = (ctl.place and "place") or (ctl.aux1 and "aux1") or nil
		if button and nh.ready() and not nhv.ui.open then
			local list, primary = context_for(player, button)
			if list and #list > 0 then
				state = {button = button, t0 = core.get_us_time(),
					yaw = player:get_look_horizontal(), pitch = player:get_look_vertical(),
					list = list, primary = primary, hud = {}}
			else
				state = {button = button, t0 = core.get_us_time(), list = {}, hud = {},
					yaw = player:get_look_horizontal(), pitch = player:get_look_vertical()}
			end
		end
		return
	end
	local held = ctl[state.button]
	if not held then
		if state.open then
			local k = pick(player)
			close(player, k and state.list[k])
		else
			-- a tap: the obvious action
			local primary = state.primary
			close(player, primary)
			if not primary then
				nhv.hud.message("(hold to choose an action)")
			end
		end
		return
	end
	if not state.open and #state.list > 0
			and core.get_us_time() - state.t0 > HOLD_US then
		state.open = true
		draw(player)
	end
	if state.open then
		local k = pick(player)
		if k ~= state.sel then
			state.sel = k
			draw(player)
		end
	end
end)

return wheel
