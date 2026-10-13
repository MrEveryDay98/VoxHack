-- Game time, Superhot style.
--
-- Time always runs, but its rate follows the hero: standing still it
-- crawls at MIN_SCALE, walking at full speed it runs at 1. The rate
-- eases toward its target so it never snaps.
--
-- Actions (attacks, using items) cost NetHack time: they add "debt",
-- during which time runs at full rate until the action's cost is paid.
--
-- Game time is measured in NetHack turns. At full rate RATE turns pass
-- per second, which matches walking one square per turn at speed 12.

local U = nhv.util
local nh = nhv.nh

local clock = {
	scale = 0,     -- current time rate (0..1)
	debt = 0,      -- turns an action still has to play out
	acc = 0,       -- turns accumulated toward the next tick
	game = 0,      -- total game time passed (turns)
}
nhv.clock = clock

clock.MIN_SCALE = tonumber(core.settings:get("nhv_time_min")) or 0.12
clock.RATE = 4 / 3          -- turns per second at full rate
clock.WALK = 4.0            -- nodes per second the hero walks at speed 12
clock.WHEEL_SLOW = 0.25     -- with the action wheel open, time runs this x the minimum

-- NetHack speed of the hero (12 = normal)
function clock.hero_speed()
	local h = nh.snap and nh.snap.hero
	if not h then
		return 12
	end
	local s = 12
	if U.has(h.flags, U.HERO.VFAST) then
		s = 20
	elseif U.has(h.flags, U.HERO.FAST) then
		s = 16
	end
	if U.has(h.flags, U.HERO.POLY) and h.speed and h.speed > 0 then
		s = h.speed
	end
	return s
end

-- turns one hero action takes
function clock.action_turns()
	return 12 / clock.hero_speed()
end

function clock.busy()
	return clock.debt > 0
end

function clock.add_debt(turns)
	clock.debt = clock.debt + turns
end

-- Advance the clock; returns game turns passed this step.
function clock.update(dtime, player)
	if not nh.ready() or nhv.ui.open then
		return 0
	end
	local v = player:get_velocity()
	local speed = math.sqrt(v.x * v.x + v.z * v.z)
	local walk = clock.WALK * clock.hero_speed() / 12
	local target = clock.MIN_SCALE + (1 - clock.MIN_SCALE) * math.min(1, speed / walk)
	if clock.debt > 0 then
		target = 1
	end
	if nhv.wheel and nhv.wheel.is_open() then
		target = clock.MIN_SCALE * clock.WHEEL_SLOW -- choosing an action: nearly frozen
	end
	clock.scale = clock.scale + (target - clock.scale) * math.min(1, dtime * 10)
	local dtg = dtime * clock.scale * clock.RATE
	if clock.debt > 0 then
		clock.debt = clock.debt - dtg
		if clock.debt < 0 then
			clock.acc = clock.acc - clock.debt
			clock.debt = 0
		end
	else
		clock.acc = clock.acc + dtg
	end
	clock.game = clock.game + dtg
	return dtg
end

-- Is a plain "time passes" tick due? (consumes it)
function clock.tick_due()
	local a = clock.action_turns()
	if clock.acc >= a then
		clock.acc = clock.acc - a
		return true
	end
	return false
end

-- Do an action that costs one hero action of time (or `turns`).
function clock.act(keys, info, turns)
	clock.add_debt(turns or clock.action_turns())
	clock.acc = 0
	nh.act(keys, info)
end

-- multi-turn actions (eating, digging...) take their full time
nh.on_snapshot(function(snap, action)
	if not snap then
		return
	end
	local prev = clock.last_moves
	clock.last_moves = snap.hero.moves
	if prev and action and action.kind ~= "tick" and action.kind ~= "hmove" then
		local passed = snap.hero.moves - prev
		if passed > 1 then
			clock.add_debt(math.min(passed - 1, 20) * 1.0)
		end
	end
end)

return clock
