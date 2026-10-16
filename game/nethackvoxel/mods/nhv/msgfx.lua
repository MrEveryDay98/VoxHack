-- Visual effects for things messages say you see: "Your sword glows blue
-- for a moment", "You are surrounded by a shimmering light", "You are
-- blinded by the flash!", a djinni emerging "in a cloud of smoke"... and
-- explosions (reported by NetHack as "explode <x> <y> <type>").
--
-- A message is matched against RULES (first match wins). What it's about
-- decides where the effect plays: your own things glow just in front of
-- your view, you yourself are wrapped in it (plus a tint at the screen's
-- edges), a monster named in the message gets it on its body, and an
-- altar, sink, fountain... you're standing on, at your feet.

local U = nhv.util
local nh = nhv.nh
local msgfx = {}
nhv.msgfx = msgfx

-- NetHack's colour words (longest first, so "light blue" beats "blue")
local COLORS = {
	{"light blue", "#80c0ff"}, {"sky blue", "#80d0ff"}, {"dark blue", "#2040c0"},
	{"amber", "#ffb020"}, {"black", "#000000"}, {"blue", "#3060ff"},
	{"golden", "#ffd030"}, {"gold", "#ffd030"}, {"silver", "#d8e0ff"},
	{"white", "#ffffff"}, {"red", "#ff3020"}, {"green", "#30e040"},
	{"orange", "#ff8020"}, {"purple", "#b040ff"}, {"violet", "#c060ff"},
	{"yellow", "#ffff40"}, {"brown", "#a06030"}, {"magenta", "#ff40ff"},
	{"cyan", "#40ffff"}, {"pink", "#ff80c0"}, {"indigo", "#5030c0"},
	{"gray", "#a0a0a0"}, {"grey", "#a0a0a0"}, {"dark", "#000000"},
}

-- (hallucinated colours - "puce", "ultraviolet"... - get any colour)
local function random_color()
	local h = math.random() * 6
	local i = math.floor(h)
	local f = h - i
	local rgb = ({{1, f, 0}, {1 - f, 1, 0}, {0, 1, f}, {0, 1 - f, 1}, {f, 0, 1}, {1, 0, 1 - f}})[i + 1]
	return ("#%02x%02x%02x"):format(rgb[1] * 255, rgb[2] * 255, rgb[3] * 255)
end

local function color_in(text, default)
	local t = text:lower()
	for _, c in ipairs(COLORS) do
		if t:find("%f[%a]" .. c[1] .. "%f[%A]") then
			return c[2]
		end
	end
	local snap = nh.snap
	if snap and snap.hero and U.has(snap.hero.flags, U.HERO.HALLU) then
		return random_color()
	end
	return default
end

local function is_dark(c)
	local r, g, b = tonumber(c:sub(2, 3), 16), tonumber(c:sub(4, 5), 16), tonumber(c:sub(6, 7), 16)
	return r + g + b < 120
end

-- ---------------------------------------------------------------- where
local function hero()
	return nhv.player.get()
end

-- just in front of your view, a little low: where a held thing would be
local function in_front()
	local p = hero()
	if not p then
		return
	end
	local eye = (p:get_properties().eye_height or 1.6)
	local dir = p:get_look_dir()
	local pos = vector.add(p:get_pos(), vector.new(0, eye - 0.45, 0))
	return vector.add(pos, vector.multiply(dir, 0.9))
end

local FEATURES = {"altar", "sink", "faucet", "fountain", "throne", "floor", "ground",
	"grave", "water", "pool"}

-- the monster a message names (nearest one shown with that name)
local function named_monster(subject)
	local s = subject:lower()
	local p = hero()
	local ppos = p and p:get_pos()
	local best, best_d
	for _, e in pairs(nhv.mobs.mons) do
		local pos = e.obj:get_pos()
		local name = pos and e.mon and e.mon.mndx and e.mon.mndx >= 0
			and core.nh_mon_name(e.mon.mndx)
		if name and name ~= "" and s:find(name:lower(), 1, true) then
			local d = ppos and vector.distance(pos, ppos) or 0
			if not best_d or d < best_d then
				best, best_d = e, d
			end
		end
	end
	return best
end

-- where = "you" (wrapped around you), "held" (in front of your view),
-- "feet" (the ground under you) or "mon" (with the monster entity)
local function subject_of(text)
	local t = text:lower()
	if t:find("^you ") or t:find("^you're ") or t:find(" surrounding you")
			or t:find(" around you") then
		return "you"
	end
	local subj = t:match("^(.-) glow") or t:match("^(.-) is ") or t:match("^(.-) are ")
		or t:match("^(.-) shines") or t:match("^(.-) flicker") or t:match("^(.-) sparkle")
		or t:match("^(.-) turns? ") or t:match("^(.-) crumbles?") or t
	if subj:find("^your ") then
		return "held"
	end
	for _, f in ipairs(FEATURES) do
		if subj:find("%f[%a]" .. f) then
			return "feet"
		end
	end
	local e = named_monster(subj)
	if e then
		return "mon", e
	end
	return "held"
end

local function where(kind, e)
	local p = hero()
	if kind == "mon" and e then
		local pos = e.obj:get_pos()
		return pos and vector.add(pos, vector.new(0, -(e.h or 1.5) * 0.5, 0)), e.h or 1.5
	elseif kind == "you" or kind == "feet" then
		return p and p:get_pos(), 1.8
	end
	return in_front(), nil
end

-- ---------------------------------------------------------------- shapes
local function tex(name, c)
	return ("nhvfx_%s.png^[multiply:%s"):format(name, c)
end

local function spawner(def, c)
	def.texture = {name = def.texture, alpha_tween = {1, 0},
		blend = is_dark(c) and "alpha" or "add"}
	def.glow = is_dark(c) and 0 or 14
	core.add_particlespawner(def)
end

-- a held thing glowing: a puff of light right in front of you
local function glow_held(pos, c, strong)
	local dark = is_dark(c)
	local cc = dark and "#301040" or c
	spawner({
		amount = strong and 60 or 30, time = strong and 0.6 or 0.35,
		pos = pos, radius = vector.new(0.12, 0.12, 0.12),
		vel = {min = vector.new(-0.4, -0.2, -0.4), max = vector.new(0.4, 0.6, 0.4)},
		exptime = {min = 0.4, max = 0.9}, size = {min = 0.4, max = 1.0},
		texture = tex("spark", cc),
	}, cc)
	spawner({
		amount = 6, time = 0.2, pos = pos, radius = vector.new(0.05, 0.05, 0.05),
		exptime = {min = 0.3, max = 0.6}, size = {min = 3, max = 5},
		texture = tex("dot", cc),
	}, cc)
end

-- light (or darkness) all around a body
local function aura(pos, h, c, strong)
	local dark = is_dark(c)
	local cc = dark and "#200830" or c
	local r = math.max(0.5, h * 0.35)
	spawner({
		amount = strong and 90 or 50, time = 0.7,
		pos = {min = vector.add(pos, vector.new(-r, 0, -r)), max = vector.add(pos, vector.new(r, h, r))},
		vel = {min = vector.new(-0.1, 0.2, -0.1), max = vector.new(0.1, 0.8, 0.1)},
		exptime = {min = 0.5, max = 1.2}, size = {min = 0.8, max = 2.0},
		texture = tex(dark and "dot" or "spark", cc),
	}, cc)
end

local function smoke(pos, h, c)
	local r = math.max(0.4, h * 0.3)
	core.add_particlespawner({
		amount = 40, time = 0.6,
		pos = {min = vector.add(pos, vector.new(-r, 0, -r)), max = vector.add(pos, vector.new(r, h * 0.6, r))},
		vel = {min = vector.new(-0.3, 0.4, -0.3), max = vector.new(0.3, 1.2, 0.3)},
		exptime = {min = 0.9, max = 1.8}, size = {min = 4, max = 8},
		texture = {name = tex("dot", c), alpha_tween = {0.8, 0}, blend = "alpha"},
		glow = 3,
	})
end

local function crackle(pos, h)
	for k = 0, 2 do
		core.after(k * 0.15, function()
			spawner({
				amount = 18, time = 0.08, pos = vector.add(pos, vector.new(0, h * 0.5, 0)),
				radius = vector.new(h * 0.3, h * 0.4, h * 0.3),
				vel = {min = vector.new(-3, -3, -3), max = vector.new(3, 3, 3)},
				exptime = {min = 0.08, max = 0.2}, size = {min = 0.6, max = 1.4},
				texture = tex("star", "#c0e0ff"),
			}, "#c0e0ff")
		end)
	end
end

local function dust(pos)
	core.add_particlespawner({
		amount = 40, time = 0.4, pos = pos, radius = vector.new(0.15, 0.1, 0.15),
		vel = {min = vector.new(-0.4, -0.2, -0.4), max = vector.new(0.4, 0.4, 0.4)},
		acc = vector.new(0, -4, 0),
		exptime = {min = 0.6, max = 1.2}, size = {min = 0.4, max = 0.9},
		collisiondetection = true, collision_removal = true,
		texture = {name = tex("dot", "#8a7050"), blend = "alpha"},
	})
end

local function sparkle(pos, h, c)
	local r = math.max(0.4, h * 0.3)
	spawner({
		amount = 30, time = 0.8,
		pos = {min = vector.add(pos, vector.new(-r, 0, -r)), max = vector.add(pos, vector.new(r, h, r))},
		exptime = {min = 0.2, max = 0.5}, size = {min = 0.6, max = 1.4},
		texture = tex("star", c),
	}, c)
end

local function burst(pos, h, c, radius, amount)
	local center = vector.add(pos, vector.new(0, h * 0.5, 0))
	local r = 0.3
	spawner({
		amount = amount or 50, time = 0.12,
		pos = center, radius = vector.new(r, r, r),
		attract = {kind = "point", origin = center,
			strength = {min = -radius * 2 / r, max = -radius * 4 / r}},
		exptime = {min = 0.3, max = 0.7}, size = {min = 2, max = 5},
		texture = tex("dot", c),
	}, c)
end

-- ---------------------------------------------------------------- rules
-- Each: a test on the lowercased message, then what to do. Messages that
-- aren't something seen (heard, smelled, felt; quoted writing) never play.
local function at_subject(text, fn, ...)
	local kind, e = subject_of(text)
	local pos, h = where(kind, e)
	if not pos then
		return
	end
	fn(kind, pos, h or 1.0, ...)
	return kind
end

local function tint(c, strength)
	nhv.hud.flash(is_dark(c) and "#000000" or c, strength)
end

local RULES = {
	-- flashes of light
	{function(t)
		return t:find("blinded by") and t:find("flash")
			or t:find("flash of light") or t:find("flashes brightly")
	end, function(text)
		local t = text:lower()
		if t:find("blind") or t:find("you are") then
			nhv.hud.flash("#ffffff", 1, true)
		end
		at_subject(text, function(_, pos, h)
			burst(pos, h, "#ffffff", 1.5)
		end)
	end},
	-- "There is a black flash as the dagger hits the altar."
	{function(t)
		return t:find("%a+ flash as ")
	end, function(text)
		local p = hero()
		if p then
			local c = color_in(text:match("(%a+) flash as") or "", "#ffffff")
			burst(p:get_pos(), 0.3, is_dark(c) and "#301040" or c, 1)
		end
	end},
	{function(t)
		return t:find("surrounded by darkness") or t:find("darkness surrounds")
	end, function(text)
		at_subject(text, function(kind, pos, h)
			smoke(pos, h, "#100018")
			if kind == "you" then
				tint("#000000", 1)
			end
		end)
	end},
	{function(t)
		return t:find("cloud of") and not t:find("cloud of gas") or t:find("puff of smoke")
			or t:find("plume of smoke") or t:find(" vapors? ") or t:find("smoke")
	end, function(text)
		local c = color_in(text, "#909090")
		if c == "#000000" then
			c = "#202020"
		end
		at_subject(text, function(_, pos, h)
			smoke(pos, h, c)
		end)
	end},
	{function(t)
		return t:find("cloud of gas") or t:find("cloud of poison")
	end, function(text)
		at_subject(text, function(_, pos, h)
			smoke(pos, h, "#70c050")
		end)
	end},
	{function(t)
		return t:find("crackles") or t:find("crackling with")
	end, function(text)
		at_subject(text, function(_, pos, h)
			crackle(pos, h)
		end)
	end},
	{function(t)
		return t:find("to dust") or t:find("crumbles")
	end, function(text)
		at_subject(text, function(_, pos)
			dust(pos)
		end)
	end},
	{function(t)
		return t:find("surrounded by") or t:find(" aura") or t:find("shimmering")
			or t:find("glow surrounding")
	end, function(text)
		local c = color_in(text, "#fff0c0")
		at_subject(text, function(kind, pos, h)
			if kind == "held" then
				glow_held(pos, c)
			else
				aura(pos, h, c)
			end
			if kind == "you" then
				tint(c, 0.6)
			end
		end)
	end},
	{function(t)
		return t:find("sparkl")
	end, function(text)
		local c = color_in(text, "#ffffff")
		at_subject(text, function(_, pos, h)
			sparkle(pos, h, c)
		end)
	end},
	{function(t)
		return t:find(" glow") or t:find(" shines?") or t:find(" flickers?")
	end, function(text)
		local t = text:lower()
		local c = color_in(text, "#fff0c0")
		local strong = t:find("violently") or t:find("brightly")
		local faint = t:find("flicker") or t:find("faint") or t:find("softly")
		at_subject(text, function(kind, pos, h)
			if kind == "held" then
				glow_held(pos, c, strong)
				tint(c, faint and 0.25 or 0.4)
			elseif kind == "you" then
				aura(pos, h, c, strong)
				tint(c, 0.6)
			elseif kind == "feet" then
				aura(pos, 0.6, c, strong)
			else
				aura(pos, h, c, strong)
			end
		end)
	end},
}

local NOT_SEEN = {"^you hear", "^you smell", "^you feel", "^you see here", "^you see no",
	"^there is .* here", "^things that are here", "^you read", "\"", "^you sense",
	"^you have a ", "^you are carrying", "^%a %- ", "^%a%a? %- "}

function msgfx.message(text)
	local t = text:lower()
	for _, pat in ipairs(NOT_SEEN) do
		if t:find(pat) then
			return
		end
	end
	for _, r in ipairs(RULES) do
		if r[1](t) then
			r[2](text)
			return true
		end
	end
end

-- ---------------------------------------------------------------- explosions
-- EXPL_DARK, NOXIOUS, MUDDY, WET, MAGICAL, FIERY, FROSTY
local EXPL_COLORS = {[0] = "#402060", "#70c040", "#806040", "#4080ff", "#c060ff", "#ff7020", "#a0e8ff"}

function msgfx.explode(tx, ty, kind)
	local c = EXPL_COLORS[kind] or "#ff7020"
	local pos = U.tile_center(tx, ty)
	-- (the blast covers the 3x3 squares around it)
	burst(pos, 1.2, c, U.TILE * 1.5, 120)
	burst(pos, 1.2, "#ffffff", U.TILE * 0.6, 30)
	smoke(pos, 2, kind == 5 and "#403028" or "#606060")
	local p = hero()
	if p and vector.distance(p:get_pos(), pos) < U.TILE * 2.5 then
		nhv.hud.flash(c, 0.8)
	end
end

nh.on_event(function(evs)
	for _, ev in ipairs(evs) do
		if ev.kind == "message" then
			msgfx.message(ev.text)
		elseif ev.kind == "combat" then
			local x, y, k = ev.text:match("^explode (%d+) (%d+) (%d+)")
			if x then
				msgfx.explode(tonumber(x), tonumber(y), tonumber(k))
			end
		end
	end
end)

return msgfx
