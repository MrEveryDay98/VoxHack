-- What's in your hands glowing, as NetHack says it does (the VoxHack
-- engine draws it: core.nhv_hand_fx - the light on it drawn towards the
-- glow's colour, pulsing):
--  * After a scroll of confuse monster (NetHack's u.umconf: hits left):
--    your hands glow red, pulsing slowly - brighter the more hits are left.
--  * Sting, Orcrist, Grimtooth glowing for the monsters they warn of: the
--    blade glows its colour across it, pulsing - faster the nearer the
--    nearest of them is.
-- Not while you're blind (you can't see it), nor in ASCII mode.
local U = nhv.util

local handglow = {}
nhv.handglow = handglow

local WARN_COLORS = { -- (NetHack's CLR_*: the warning artifacts' glows)
	[1] = {255, 60, 50},     -- red (Grimtooth)
	[12] = {185, 228, 255},  -- bright blue: light blue (Sting, Orcrist) - pale, as it's a tint over the blade
}
local CONF_COLOR = {255, 50, 40} -- (your hands glowing red)
local WARN_NEAR = 10 -- (how far off the nearest is counted, squares)
local WARN_HZ = {0.6, 1.2} -- (pulses a second: the nearest that far off, and next to you)

-- the glow now: {r, g, b, amount, hz}, or {} for none
function handglow.now(snap)
	local h = snap and snap.hero
	if not h or nhv_tiles.ascii or U.has(h.flags, U.HERO.BLIND) then
		return {}
	end
	local wc = (h.warn_cnt or 0) > 0 and WARN_COLORS[h.warn_color or -1]
	if wc then
		local d = (h.warn_dist or -1) >= 0 and h.warn_dist or WARN_NEAR
		local near = (WARN_NEAR - math.max(1, math.min(WARN_NEAR, d))) / (WARN_NEAR - 1)
		return {r = wc[1], g = wc[2], b = wc[3], amount = 0.75,
			hz = WARN_HZ[1] + (WARN_HZ[2] - WARN_HZ[1]) * near}
	elseif (h.umconf or 0) > 0 then
		return {r = CONF_COLOR[1], g = CONF_COLOR[2], b = CONF_COLOR[3],
			amount = math.min(0.85, 0.3 + h.umconf / 16), hz = 0.45}
	end
	return {}
end

local shown = nil
local since = 0
core.register_globalstep(function(dtime)
	since = since + dtime
	if since < 0.15 or not core.nhv_hand_fx then
		return
	end
	since = 0
	local fx = handglow.now(nhv.nh.snap)
	local key = core.serialize(fx)
	if key ~= shown then
		shown = key
		core.nhv_hand_fx(fx)
	end
end)

return handglow
