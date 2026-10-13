-- The per-step game loop in free-movement mode:
--   1. advance the clock (its rate follows the hero's movement),
--   2. move every monster's body by that much game time,
--   3. tell NetHack who can reach the hero,
--   4. when a hero action's worth of time has built up, let NetHack take
--      a turn (#nhvtick): monsters attack, cast, use items; hunger, etc.

local nh = nhv.nh

-- Testing aid: the setting nhv_test_input ("|"-separated) is sent once
-- when the game first waits for a command. "#name" = extended command,
-- "=text" = text answer, anything else = keys.
local test_input = core.settings:get("nhv_test_input")

-- Watchdog: the game must never sit paused with nothing on screen. If
-- it thinks a dialog is open but Luanti shows no menu, the question is
-- shown again (or the stale state cleared); a long pause is logged with
-- what it's waiting for, to find the cause.
local paused_since, logged = nil, false
local function watchdog()
	local ui = nhv.ui
	if nh.state ~= "waiting" and nh.state ~= "busy" then
		paused_since = nil
		return
	end
	local paused = not nh.ready() or ui.open or ui.chat_open or ui.menu_open
	if not paused then
		paused_since, logged = nil, false
		return
	end
	local now = core.get_us_time()
	if ui.menu_open or ui.chat_open then
		paused_since = nil -- (a menu or the command line is open: that's a real pause)
		return
	end
	paused_since = paused_since or now
	local secs = (now - paused_since) / 1e6
	if secs > 1.5 then
		if ui.reshow() then
			core.log("warning", "[nhv] watchdog: NetHack was asking something with nothing on screen; shown again")
			paused_since = now
		elseif ui.open then
			core.log("warning", "[nhv] watchdog: stale dialog state " .. tostring(ui.open) .. " cleared")
			ui.open = nil
			nhv.player.freeze(false)
			paused_since = now
		end
	end
	if secs > 5 and not logged then
		logged = true
		local r = nh.req or {}
		core.log("warning", ("[nhv] watchdog: paused %.0fs: nethack=%s request=%s/%s %q ui.open=%s chat=%s menu=%s"):format(
			secs, tostring(nh.state), tostring(r.kind), tostring(r.for_command), tostring(r.prompt),
			tostring(ui.open), tostring(ui.chat_open), tostring(ui.menu_open)))
	end
end

core.register_globalstep(function(dtime)
	watchdog()
	local player = nhv.player.get()
	if not player or not nh.snap or not nh.ready() or nhv.ui.open or nhv.ui.chat_open
			or nhv.ui.menu_open then
		return
	end
	if test_input and test_input ~= "" then
		local keys = {}
		for part in test_input:gmatch("[^|]+") do
			if part:sub(1, 1) == "#" then
				keys[#keys + 1] = {key = "#"}
				keys[#keys + 1] = {text = part:sub(2)}
			elseif part:sub(1, 1) == "=" then
				keys[#keys + 1] = {text = part:sub(2)}
			else
				for c in part:gmatch(".") do
					keys[#keys + 1] = {key = c}
				end
			end
		end
		test_input = nil
		nh.act(keys, {kind = "test"})
		return
	end
	local dturns = nhv.clock.update(dtime, player)
	nhv.sim.update(dturns)
	nhv.missiles.update(dturns)
	nhv.rays.update(dturns)
	nhv.sim.push_states()
	if nhv.sim.dirty then
		nhv.sim.dirty = false
		nh.refresh()
	end
	if nh.ready() and nhv.clock.tick_due() then
		nh.act({{key = "#"}, {text = "nhvtick"}}, {kind = "tick"})
	end
end)
