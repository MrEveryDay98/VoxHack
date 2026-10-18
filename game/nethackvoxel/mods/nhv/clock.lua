-- Game time, Superhot style.
--
-- Time runs only as the hero does: standing still it stops (MIN_SCALE,
-- 0 unless the setting nhv_time_min says otherwise), walking at full speed
-- it runs at 1. The rate eases toward its target so it never snaps (and
-- comes to a real stop, not a crawl).
--
-- Actions (attacks, using items) cost the NetHack time they really took
-- (a refused one, "You can't...", costs nothing). That time is paid from
-- what has built up toward the next turn first; the rest becomes "debt",
-- during which time runs at full rate (and no other action can start)
-- until it's paid. So game time never runs ahead of or behind the clock,
-- however fast you act.
--
-- Options > Time "Real time" (setting nhv_time_mode = realtime) turns the
-- Superhot part off: time always runs at the full rate. (Menus and prompts
-- still pause it, and the action wheel still slows it.)
--
-- Game time is measured in NetHack turns. At full rate RATE turns pass
-- per second, which matches walking one square per turn at speed 12.

local U = nhv.util
local nh = nhv.nh

local clock = {
	scale = 0,     -- current time rate (0..1)
	debt = 0,      -- turns an action still has to play out
	debt_total = 0, -- ... out of this many (for the cooldown bar)
	acc = 0,       -- turns accumulated toward the next tick
	game = 0,      -- total game time passed (turns)
}
nhv.clock = clock

clock.MIN_SCALE = tonumber(core.settings:get("nhv_time_min")) or 0
clock.RATE = 4 / 3          -- turns per second at full rate
clock.WALK = 4.0            -- nodes per second the hero walks at speed 12
clock.WHEEL_SLOW = 0.25     -- with the action wheel open, time runs this x the minimum
clock.FAST = 6              -- searching, or helpless: time runs this x the full rate

-- Searching passes time fast: while Search is held (one search after
-- another; hotbar.lua) and while a counted search (Ctrl+X) plays out, time
-- runs FAST x the full rate - the world (monsters walking...) keeps up
-- with NetHack - and you stand still. It drops back to the usual rate the
-- moment it ends. Getting hurt stops a held search (until pressed again).
clock.search_held = false
clock.fast_debt = false -- (paying a counted search's turns)
function clock.searching()
	return clock.search_held or (clock.fast_debt and clock.debt > 0)
end

function clock.realtime()
	return core.settings:get("nhv_time_mode") == "realtime"
end

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

-- NetHack's encumbrance slows you: Burdened 3/4, Stressed 1/2, Strained
-- 1/4, Overtaxed 1/8 of your speed; Overloaded you can't move at all
clock.ENCUMBRANCE = {[0] = 1, 0.75, 0.5, 0.25, 0.125, 0}

-- how fast the hero really moves (12 = normal), carrying what it carries
function clock.move_speed()
	local h = nh.snap and nh.snap.hero
	return clock.hero_speed() * (clock.ENCUMBRANCE[h and h.encumbrance or 0] or 1)
end

-- turns one hero action takes
function clock.action_turns()
	-- (carrying more, each action spans more turns, as in NetHack; even
	-- Overloaded, time still passes)
	return 12 / math.max(1.5, clock.move_speed())
end

function clock.busy()
	return clock.debt > 0
end

-- (capped: time owed can never pile up into a long stall)
clock.MAX_DEBT = 25
function clock.add_debt(turns)
	clock.debt = math.min(clock.debt + turns, clock.MAX_DEBT)
	clock.debt_total = clock.debt <= turns and clock.debt or math.max(clock.debt_total, clock.debt)
end

-- how much of the current action is left to play out (1 .. 0)
function clock.cooldown()
	if clock.debt <= 0 or clock.debt_total <= 0 then
		return 0
	end
	return math.min(1, clock.debt / clock.debt_total)
end

-- Advance the clock; returns game turns passed this step.
function clock.update(dtime, player)
	-- prompts, menus and the command line: paused
	local helpless = nh.helpless_wait()
	if not (nh.ready() or helpless) or nhv.ui.open or nhv.ui.chat_open or nhv.ui.menu_open then
		return 0
	end
	local v = player:get_velocity()
	local speed = math.sqrt(v.x * v.x + v.z * v.z)
	-- (walking flat out at the speed you can manage is full speed)
	local walk = math.max(0.1, clock.WALK * clock.move_speed() / 12)
	local target = clock.MIN_SCALE + (1 - clock.MIN_SCALE) * math.min(1, speed / walk)
	if clock.debt > 0 or clock.realtime() then
		target = 1
	end
	if nhv.wheel and nhv.wheel.is_open() then
		target = clock.MIN_SCALE * clock.WHEEL_SLOW -- choosing an action: nearly frozen
	end
	-- (searching, or helpless - asleep, frozen...: fast forward, the world
	-- keeping up, until it ends)
	local fast = clock.searching() or helpless
	if fast then
		target = clock.FAST
		clock.scale = clock.scale + (target - clock.scale) * math.min(1, dtime * 10)
	elseif clock.scale > 1 then
		clock.scale = target -- (searching just ended: straight back, no easing)
	else
		clock.scale = clock.scale + (target - clock.scale) * math.min(1, dtime * 10)
	end
	if target == 0 and clock.scale < 0.01 then
		clock.scale = 0 -- (stopped: no endless creeping toward 0)
	end
	local dtg = dtime * clock.scale * clock.RATE
	if clock.debt > 0 then
		clock.debt = clock.debt - dtg
		if clock.debt < 0 then
			clock.acc = clock.acc - clock.debt
			clock.debt = 0
		end
		if clock.debt <= 0 then
			clock.fast_debt = false
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

-- Do an action that takes game time (charged when its result arrives).
-- (aimed first: whatever it throws or zaps goes where the crosshair points;
-- see actions.aim)
local NO_AIM = {tick = true, wait = true, attack = true, swing = true, escape = true,
	search = true, search_count = true}
function clock.act(keys, info)
	local player = nhv.player.get()
	local aim = player and not (info and NO_AIM[info.kind]) and nhv.actions.aim_keys(player)
	if aim then
		if type(keys) == "string" then
			for c in keys:gmatch(".") do
				aim[#aim + 1] = {key = c}
			end
		else
			for _, k in ipairs(keys) do
				aim[#aim + 1] = k
			end
		end
		keys = aim
	end
	nh.act(keys, info)
end

-- An action's result: charge the turns it really took (multi-turn ones,
-- eating, digging..., take their full time; refused ones nothing).
nh.on_snapshot(function(snap, action)
	if not snap then
		return
	end
	local prev = clock.last_moves
	clock.last_moves = snap.hero.moves
	-- (hurt while holding Search: it stops, until pressed again)
	if clock.last_hp and snap.hero.hp < clock.last_hp then
		clock.search_held = false
	end
	clock.last_hp = snap.hero.hp
	if prev and action and action.kind ~= "tick" and action.kind ~= "hmove" then
		local passed = snap.hero.moves - prev
		if passed > 0 and passed < 1000 then -- (not a level change's jump)
			local owed = passed * 1.0
			local paid = math.min(clock.acc, owed)
			clock.acc = clock.acc - paid
			clock.add_debt(owed - paid)
			if action.kind == "search_count" and clock.debt > 0 then
				clock.fast_debt = true
			end
		end
	end
end)

return clock
