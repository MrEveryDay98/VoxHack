-- The per-step game loop in free-movement mode:
--   1. advance the clock (its rate follows the hero's movement),
--   2. move every monster's body by that much game time,
--   3. tell NetHack who can reach the hero,
--   4. when a hero action's worth of time has built up, let NetHack take
--      a turn (#nhvtick): monsters attack, cast, use items; hunger, etc.

local nh = nhv.nh

core.register_globalstep(function(dtime)
	local player = nhv.player.get()
	if not player or not nh.snap or not nh.ready() or nhv.ui.open then
		return
	end
	local dturns = nhv.clock.update(dtime, player)
	nhv.sim.update(dturns)
	nhv.sim.push_states()
	if nhv.sim.dirty then
		nhv.sim.dirty = false
		nh.refresh()
	end
	if nh.ready() and nhv.clock.tick_due() then
		nh.act({{key = "#"}, {text = "nhvtick"}}, {kind = "tick"})
	end
end)
