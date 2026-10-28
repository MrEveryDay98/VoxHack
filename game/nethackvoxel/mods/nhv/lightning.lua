-- Lightning, drawn: a jagged, branching bolt made new each time (midpoint
-- displacement) of tiny glowing particles - a white-hot core in a blue
-- glow - that flickers (drawn again, a different shape, a moment later)
-- and is gone.
--
--   lightning.bolt(a, b, opts)   a bolt from a to b
--   lightning.strike(pos)        one coming down out of the sky onto pos
--
-- Struck by it: the Plane of Air's thunderstorms (a bolt comes down onto
-- each cloud struck and runs on from it: the hooks storm_lightning and
-- storm_lightning_end, timeout.c's do_storms), Mjollnir's and other
-- lightning artifacts' hits (the hook artifact_lightning), and lightning
-- rays crackle along their way (rays.lua).

local lightning = {}
nhv.lightning = lightning

local CORE = "[fill:2x2:#FFFFFF"
local GLOW = "[fill:2x2:#9FC4FF^[opacity:90"
local DOT = 0.2 -- (nodes between the particles drawn along a bolt)

-- the bolt's points from a to b: the middle of each stretch pushed aside
-- at random, a bit less each time it's halved
local function points(a, b, rough)
	local pts = {a, b}
	local len = vector.distance(a, b)
	local amp = len * (rough or 0.18)
	for _ = 1, math.max(2, math.min(6, math.ceil(math.log(len / 0.4 + 1) / math.log(2)))) do
		local out = {pts[1]}
		for i = 1, #pts - 1 do
			local p, q = pts[i], pts[i + 1]
			local m = vector.multiply(vector.add(p, q), 0.5)
			m = vector.add(m, vector.new((math.random() - 0.5) * amp, (math.random() - 0.5) * amp,
				(math.random() - 0.5) * amp))
			out[#out + 1] = m
			out[#out + 1] = q
		end
		pts = out
		amp = amp * 0.55
	end
	return pts
end

local function draw(pts, life, width)
	for i = 1, #pts - 1 do
		local p, q = pts[i], pts[i + 1]
		local n = math.max(1, math.ceil(vector.distance(p, q) / DOT))
		for k = 0, n - 1 do
			local at = vector.add(p, vector.multiply(vector.subtract(q, p), k / n))
			core.add_particle({pos = at, velocity = vector.zero(), expirationtime = life,
				size = 1.1 * width, glow = 14, texture = CORE})
			if k % 3 == 0 then
				core.add_particle({pos = at, velocity = vector.zero(), expirationtime = life * 0.8,
					size = 2.2 * width, glow = 14, texture = GLOW})
			end
		end
	end
end

-- one shape of the bolt, with its branches
local function shape(a, b, life, width, rough, depth)
	local pts = points(a, b, rough)
	draw(pts, life, width)
	-- branches: forks off the way down, shorter and thinner
	if depth > 0 then
		for i = 3, #pts - 2, math.max(2, math.floor(#pts / 4)) do
			if math.random() < 0.45 then
				local from = pts[i]
				local rest = vector.subtract(b, from)
				local dir = vector.add(vector.multiply(rest, 0.35 + math.random() * 0.25),
					vector.new((math.random() - 0.5) * 3, (math.random() - 0.5) * 1.5, (math.random() - 0.5) * 3))
				shape(from, vector.add(from, dir), life * 0.8, width * 0.6, rough * 1.3, depth - 1)
			end
		end
	end
end

-- a bolt from a to b (opts: width, life - seconds each flicker shows,
-- flickers, rough, branches - how deep the forks go)
function lightning.bolt(a, b, opts)
	opts = opts or {}
	local life = opts.life or 0.12
	local flickers = opts.flickers or 3
	local width = opts.width or 1
	for k = 0, flickers - 1 do
		local function go()
			shape(a, b, life, width, opts.rough or 0.18, opts.branches or 2)
		end
		if k == 0 then
			go()
		else
			core.after(k * life * 0.9, go)
		end
	end
end

local SKY = 26 -- (how high over its target a strike comes down from)

-- a bolt down out of the sky onto pos, with a flash and sparks where it hits
function lightning.strike(pos, opts)
	local top = vector.add(pos, vector.new((math.random() - 0.5) * 6, SKY, (math.random() - 0.5) * 6))
	lightning.bolt(top, pos, {width = (opts and opts.width) or 1.6, flickers = 3, life = 0.13,
		rough = 0.14, branches = 2})
	core.add_particlespawner({
		amount = 30, time = 0.08, pos = pos,
		minvel = vector.new(-3, 0.5, -3), maxvel = vector.new(3, 4, 3), minacc = vector.new(0, -9, 0),
		maxacc = vector.new(0, -9, 0), minexptime = 0.25, maxexptime = 0.5, minsize = 0.8, maxsize = 1.6,
		texture = CORE, glow = 14,
	})
end

-- a hook happened (sound.lua): lightning artifacts strike whoever they hit;
-- a thunderstorm's strike comes down onto its cloud, and its bolt runs on
-- to where the next hook says
local storm_at
function lightning.hook(id, opts)
	local pos = opts and opts.pos
	if id == "storm_lightning" and pos then
		storm_at = pos
		lightning.strike(pos)
	elseif id == "storm_lightning_end" and pos and storm_at then
		if vector.distance(storm_at, pos) > 0.5 then
			lightning.bolt(storm_at, pos, {width = 1.1, life = 0.15, flickers = 3, rough = 0.12,
				branches = 2})
		end
		storm_at = nil
	elseif id == "artifact_lightning" then
		if not pos then
			local p = nhv.player.get()
			pos = p and vector.add(p:get_pos(), vector.new(0, 1, 0))
		end
		if pos then
			lightning.strike(pos, {width = 1.2})
		end
	end
end

return lightning
