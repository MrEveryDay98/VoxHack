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

core.register_globalstep(function(dtime)
	local player = nhv.player.get()
	if not player or not nh.snap or not nh.ready() or nhv.ui.open then
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
	nhv.sim.push_states()
	if nhv.sim.dirty then
		nhv.sim.dirty = false
		nh.refresh()
	end
	if nh.ready() and nhv.clock.tick_due() then
		nh.act({{key = "#"}, {text = "nhvtick"}}, {kind = "tick"})
	end
end)
