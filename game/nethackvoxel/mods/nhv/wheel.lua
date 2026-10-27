-- Action wheel.
--
-- Tap right click (or E) for the obvious action. Hold it and a wheel of
-- actions opens around the crosshair; move the mouse toward one and let
-- go to pick it (let go near the middle to cancel). While it's open the
-- view stays still (the mouse only moves the selection) and time slows.
--
-- Every wheel ends in "More...": rest on it (or let go on it) and a ring of
-- groups opens - Items, Gear, Magic... - and each of those opens its
-- commands (cmdtable.lua), with "< Back" at the top. Let go on a group and
-- the wheel stays open by itself: move to a command and click (right
-- click or E) to do it, or click in the middle to close it.

local nh = nhv.nh
local wheel = {}
nhv.wheel = wheel

local HOLD_US = 220000   -- held longer than this = open the wheel
local DWELL_US = 350000  -- resting on a group this long opens it
local STICKY_US = 30000000 -- a wheel left open by itself closes after this
local DEADZONE = 0.06    -- radians of mouse movement before anything is picked
local PX_PER_RAD = 700   -- the pointer arrow: pixels it stretches per radian moved
local DOTS = 7           -- its trail, from the middle to its head
local ARROW_STEPS = 32   -- its head: one of these pictures (tools/make_map_arrow.py)

local BACK = {label = "< Back", back = true}

-- {button=, t0=, yaw=, pitch= (the view, put back after), ref_yaw=,
-- ref_pitch= (where picking is measured from), list=, primary=, open=,
-- sel=, sel_t=, stack= (the rings it came from), sticky=, armed=, hud={}}
local state = nil
local blocked = false    -- closed with a click: nothing until it's let go

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

-- where entry k of n is drawn (an ellipse, wider than tall, so the labels
-- of a full ring don't run into each other)
local function entry_pos(k, n)
	local ang, r = entry_angle(k, n), radius(n)
	-- (a full ring wider still: its bottom and top entries side by side)
	local wide = 1.3 + 0.05 * math.max(0, n - 8)
	return math.cos(ang) * r * wide, math.sin(ang) * r * 0.85
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
	state.hud = {}
	for k, a in ipairs(state.list) do
		local ox, oy = entry_pos(k, n)
		local sel = state.sel == k
		local w = math.max(90, #a.label * 9 + 20)
		local bg = sel and "#E0A020D0" or (a.sub or a.back) and "#202838C8" or "#101018C0"
		state.hud[#state.hud + 1] = player:hud_add({
			type = "image", position = {x = 0.5, y = 0.5}, alignment = {x = 0, y = 0},
			offset = {x = ox, y = oy}, scale = {x = w, y = 30},
			text = "[fill:1x1:" .. bg, z_index = 100,
		})
		state.hud[#state.hud + 1] = player:hud_add({
			type = "text", position = {x = 0.5, y = 0.5}, alignment = {x = 0, y = 0},
			offset = {x = ox, y = oy}, number = sel and 0x000000 or 0xFFFFFF,
			text = a.label, z_index = 101,
		})
	end
	-- the pointer: a trail of dots out to an arrowhead (update_arrow)
	state.arrow = {dots = {}}
	for _ = 1, DOTS do
		local id = player:hud_add({
			type = "image", position = {x = 0.5, y = 0.5}, alignment = {x = 0, y = 0},
			offset = {x = 0, y = 0}, scale = {x = 0, y = 0},
			text = "[fill:1x1:#FFD040C0", z_index = 102,
		})
		state.hud[#state.hud + 1] = id
		table.insert(state.arrow.dots, id)
	end
	state.arrow.head = player:hud_add({
		type = "image", position = {x = 0.5, y = 0.5}, alignment = {x = 0, y = 0},
		offset = {x = 0, y = 0}, scale = {x = 0, y = 0},
		text = "nhv_map_arrow_00.png", z_index = 103,
	})
	state.hud[#state.hud + 1] = state.arrow.head
	-- (in the middle: the ring's name, or how to use it)
	local mid = ""
	if not state.sel then
		mid = state.title or "(move to pick)"
		if state.sticky then
			mid = mid .. "\n(click to pick)"
		end
	end
	state.hud[#state.hud + 1] = player:hud_add({
		type = "text", position = {x = 0.5, y = 0.5}, alignment = {x = 0, y = 0},
		offset = {x = 0, y = 0}, number = 0xC0C0C0, text = mid, z_index = 101,
	})
end

-- how far the mouse has moved from the middle (radians: x right, y down)
local function pointer(player)
	local dyaw = angle_diff(player:get_look_horizontal(), state.ref_yaw)
	local dpitch = player:get_look_vertical() - state.ref_pitch
	-- turning right decreases yaw; looking down increases pitch
	return -dyaw, dpitch
end

-- The pointer arrow follows the mouse from the middle, stretching out as
-- far as the ring (hidden until the mouse has moved enough to pick)
local function update_arrow(player)
	local ar = state.arrow
	if not ar then
		return
	end
	local dx, dy = pointer(player)
	local d = math.sqrt(dx * dx + dy * dy)
	local len = 0
	if d >= DEADZONE then
		len = math.min(d * PX_PER_RAD, radius(#state.list) * 0.75)
	end
	if ar.len == len and ar.dx == dx and ar.dy == dy then
		return
	end
	ar.len, ar.dx, ar.dy = len, dx, dy
	local ux, uy = 0, 0
	if len > 0 then
		ux, uy = dx / d, dy / d
	end
	for i, id in ipairs(ar.dots) do
		local t = len * i / (DOTS + 1)
		player:hud_change(id, "offset", {x = ux * t, y = uy * t})
		-- (smaller towards the middle)
		local sz = len > 0 and (3 + 3 * i / DOTS) or 0
		player:hud_change(id, "scale", {x = sz, y = sz})
	end
	-- (its head turned the way it points: clockwise from up)
	local k = math.floor(math.deg(math.atan2(uy, ux) + math.pi / 2) / (360 / ARROW_STEPS) + 0.5) % ARROW_STEPS
	player:hud_change(ar.head, "text", ("nhv_map_arrow_%02d.png"):format(k))
	player:hud_change(ar.head, "offset", {x = ux * len, y = uy * len})
	local sc = len > 0 and 1.5 or 0
	player:hud_change(ar.head, "scale", {x = sc, y = sc})
end

local function pick(player)
	local dx, dy = pointer(player)
	if math.sqrt(dx * dx + dy * dy) < DEADZONE then
		return nil
	end
	local ang = math.atan2(dy, dx)
	local n = #state.list
	local best, bd
	for k = 1, n do
		local ex, ey = entry_pos(k, n)
		local d = math.abs(angle_diff(ang, math.atan2(ey, ex)))
		if not bd or d < bd then
			best, bd = k, d
		end
	end
	return best
end

function wheel.is_open()
	return state ~= nil and state.open == true
end

local function close(player, run)
	if not state then
		return
	end
	hud_remove(player)
	if state.open then
		player:set_look_horizontal(state.yaw)
		player:set_look_vertical(state.pitch)
		player:hud_set_flags({nhv_camera_lock = false})
	end
	local choice = run
	state = nil
	blocked = true
	if choice then
		nhv.sound.hook("wheel_select")
		nhv.actions.run(choice, {kind = "wheel"})
	end
end

-- (picking starts again from the middle, wherever the mouse got to)
local function recentre(player)
	state.ref_yaw, state.ref_pitch = player:get_look_horizontal(), player:get_look_vertical()
	state.sel, state.sel_t = nil, core.get_us_time()
end

-- into a group (or the groups), or back out of one
local function enter(player, entry)
	if entry.back then
		local prev = table.remove(state.stack)
		if not prev then
			return
		end
		state.list, state.title = prev.list, prev.title
	else
		table.insert(state.stack, {list = state.list, title = state.title})
		local sub = entry.sub == "groups" and nhv.cmdtable.group_ring() or entry.sub
		state.list = {BACK}
		for _, a in ipairs(sub) do
			state.list[#state.list + 1] = a
		end
		state.title = entry.sub == "groups" and "More" or entry.label:gsub(" >$", "")
	end
	nhv.sound.hook("wheel_open")
	recentre(player)
	draw(player)
end

-- what picking entry k does: open it, go back, or do it
local function choose(player, k)
	local entry = k and state.list[k]
	if entry and (entry.sub or entry.back) then
		enter(player, entry)
		return true
	end
	close(player, entry)
	return false
end

-- list, primary for a button. Right click picks the wheel by the modifier
-- held (Shift = yourself, Alt = use an item, Ctrl = magic; the NetHack
-- Voxel build of Luanti sends Alt and Ctrl); E is for the wielded weapon.
local function context_for(player, button)
	if button == "place" then
		local ctl = player:get_player_control()
		if ctl.sneak then
			return nhv.actions.self_context(player)
		elseif ctl.nhv_alt then
			return nhv.actions.item_verbs(player)
		elseif ctl.nhv_ctrl then
			return nhv.actions.magic(player)
		end
		local list, primary, why = nhv.actions.context(player)
		if why then
			nhv.hud.message(why)
		end
		return list, primary
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
	local now = core.get_us_time()
	if not state then
		if blocked then
			blocked = ctl.place or ctl.aux1
			return
		end
		local button = (ctl.place and "place") or (ctl.aux1 and "aux1") or nil
		if button and nh.ready() and not nhv.ui.open and not nhv.cutscene.active then
			local found, primary = context_for(player, button)
			-- (every wheel ends in More...: all the other commands)
			local list = {}
			for _, a in ipairs(found or {}) do
				list[#list + 1] = a
			end
			list[#list + 1] = nhv.cmdtable.MORE
			state = {button = button, t0 = now,
				yaw = player:get_look_horizontal(), pitch = player:get_look_vertical(),
				list = list, primary = primary, hud = {}, stack = {}}
			state.ref_yaw, state.ref_pitch = state.yaw, state.pitch
		end
		return
	end
	-- (something else came up meanwhile - a question, a menu: it closes)
	if nhv.ui.open or nhv.cutscene.active then
		close(player, nil)
		return
	end
	local held = ctl.place or ctl.aux1
	if state.sticky then
		-- open by itself: a click picks (once the last one is let go)
		if not held then
			state.armed = true
		elseif state.armed then
			state.armed = false
			state.t0 = now
			choose(player, pick(player))
			return
		end
		if now - state.t0 > STICKY_US then
			close(player, nil)
			return
		end
	elseif not ctl[state.button] then
		if state.open then
			-- let go on a group: it opens, and stays open
			if choose(player, pick(player)) then
				state.sticky, state.armed, state.t0 = true, false, now
				draw(player)
			end
		else
			-- a tap: the obvious action
			local primary = state.primary
			close(player, primary)
			blocked = false
			if not primary then
				nhv.hud.message("(hold to choose an action)")
			end
		end
		return
	end
	if not state.open and now - state.t0 > HOLD_US then
		nhv.sound.hook("wheel_open")
		state.open = true
		player:hud_set_flags({nhv_camera_lock = true})
		draw(player)
	end
	if state.open then
		local k = pick(player)
		if k ~= state.sel then
			state.sel, state.sel_t = k, now
			draw(player)
		elseif k and now - state.sel_t > DWELL_US then
			-- resting on a group (or Back) opens it
			local entry = state.list[k]
			if entry.sub or entry.back then
				enter(player, entry)
			end
		end
		-- (after any redraw: its new pointer is placed at once)
		update_arrow(player)
	end
end)

return wheel
