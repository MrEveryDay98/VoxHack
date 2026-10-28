-- Casting spells.
--
-- NetHack's "Choose which spell to cast" menu is drawn as rows with the
-- spellbook's picture and buttons for how to cast it:
--   Cast    a spell with no direction (light, detect monsters...): now
--   Self    a directional one at yourself (healing...): now
--   Target  a directional one at something: the spell is readied in your
--           hand (it glows) for READY_S seconds; move and aim freely, then
--           left-click to release it where you aim. Readying costs nothing:
--           NetHack only casts it when it's released.
-- Wands work the same way: NetHack's "What do you want to zap?" becomes a
-- list of your wands, each with Self (zap it at yourself, now) and Target
-- (ready it; left-click zaps it where you aim). A wand that needs no
-- direction (light, create monster...) just zaps with either.

local U = nhv.util
local nh = nhv.nh
local E = core.formspec_escape

local spells = {
	ready = nil, -- {sel=, name=, until_us=, spawner=}
}
nhv.spells = spells

spells.READY_S = 6
spells.PROMPT = "^Choose which spell to cast"

-- the spell name at the start of a menu row ("force bolt     1 attack ...")
function spells.row_name(text)
	return (text or ""):match("^%s*(.-)%s%s+%d") or (text or ""):match("^%s*(%S.-)%s*$") or ""
end

function spells.is_menu(req)
	return req and req.kind == "menu" and (req.prompt or ""):find(spells.PROMPT) ~= nil
end

-- what NetHack says about the spells you know, by name
local function known()
	local by_name = {}
	for _, s in ipairs(core.nh_get_spells and core.nh_get_spells() or {}) do
		by_name[s.name:lower()] = s
	end
	return by_name
end

-- ---------------------------------------------------------------- the menu
function spells.dialog(req, head)
	local info = known()
	local rows = {}
	for _, it in ipairs(req.items or {}) do
		if it.selectable and it.sel ~= "" then
			rows[#rows + 1] = it
		end
	end
	local view = math.min(#rows, 8)
	local RH = 1.1
	local h = 2.9 + view * RH
	local fs = {head(15, h), ("label[0.5,0.6;%s]"):format(E(req.prompt))}
	fs[#fs + 1] = ("scroll_container[0.4,1.1;14.2,%f;spellscroll;vertical]"):format(view * RH)
	for k, it in ipairs(rows) do
		local y = (k - 1) * RH
		local name = spells.row_name(it.text)
		local s = info[name:lower()]
		-- the rest of the row: level, school, fail, retention
		local rest = (it.text or ""):sub(#name + 1):gsub("^%s+", ""):gsub("%s+", "  ")
		fs[#fs + 1] = ("box[0,%f;14.1,%f;#00000040]"):format(y, RH - 0.1)
		if s and s.tile >= 0 then
			fs[#fs + 1] = ("item_image[0.1,%f;0.9,0.9;%s]"):format(y + 0.05, nhv_tiles.item(s.tile))
		end
		fs[#fs + 1] = ("label[1.2,%f;%s]"):format(y + 0.3, E(it.sel .. " - " .. name))
		fs[#fs + 1] = ("label[1.2,%f;%s]"):format(y + 0.72, nhv.theme.dim(E(rest)))
		local b = it.sel:byte()
		if s and s.directional then
			fs[#fs + 1] = ("button[8.4,%f;2.6,0.8;spself_%d;Self]"):format(y + 0.1, b)
			fs[#fs + 1] = ("button[11.2,%f;2.8,0.8;spaim_%d;Target]"):format(y + 0.1, b)
		else
			fs[#fs + 1] = ("button[11.2,%f;2.8,0.8;spcast_%d;Cast]"):format(y + 0.1, b)
		end
	end
	fs[#fs + 1] = "scroll_container_end[]"
	if #rows > 8 then
		fs[#fs + 1] = ("scrollbaroptions[max=%d]"):format(math.ceil((#rows - 8) * RH * 10))
		fs[#fs + 1] = ("scrollbar[14.6,1.1;0.3,%f;vertical;spellscroll;0]"):format(view * RH)
	else
		fs[#fs + 1] = "scrollbar[-10,-10;0.1,0.1;vertical;spellscroll;0]"
	end
	fs[#fs + 1] = ("button[11.6,%f;3,0.9;menu_cancel;Cancel]"):format(h - 1.3)
	return table.concat(fs)
end

-- ---------------------------------------------------------------- wands
spells.ZAP_PROMPT = "want to zap"

function spells.is_zap(req)
	-- (it comes as a key or a y/n style question: "[f or ?*]")
	return req and (req.kind == "key" or req.kind == "yn")
		and (req.prompt or ""):find(spells.ZAP_PROMPT, 1, true) ~= nil
end

local function wands()
	local list = {}
	for _, o in ipairs(nh.snap and nh.snap.inventory or {}) do
		if o.oclass == U.OCLASS.WAND then
			list[#list + 1] = o
		end
	end
	return list
end

function spells.wand_dialog(req, head)
	local rows = wands()
	local view = math.max(1, math.min(#rows, 8))
	local RH = 1.1
	local h = 2.9 + view * RH
	local fs = {head(15, h), ("label[0.5,0.6;%s]"):format(E(req.prompt))}
	fs[#fs + 1] = ("scroll_container[0.4,1.1;14.2,%f;spellscroll;vertical]"):format(view * RH)
	for k, o in ipairs(rows) do
		local y = (k - 1) * RH
		fs[#fs + 1] = ("box[0,%f;14.1,%f;#00000040]"):format(y, RH - 0.1)
		fs[#fs + 1] = ("item_image[0.1,%f;0.9,0.9;%s]"):format(y + 0.05, nhv_tiles.item(o.tile))
		local name = o.name
		if #name > 34 then
			name = name:sub(1, 32) .. ".."
		end
		fs[#fs + 1] = ("label[1.2,%f;%s]"):format(y + 0.5, E(o.invlet .. " - " .. name))
		fs[#fs + 1] = ("tooltip[1.2,%f;7,0.9;%s]"):format(y, E(o.name))
		local b = o.invlet:byte()
		fs[#fs + 1] = ("button[8.4,%f;2.6,0.8;wdself_%d;Self]"):format(y + 0.1, b)
		fs[#fs + 1] = ("button[11.2,%f;2.8,0.8;wdaim_%d;Target]"):format(y + 0.1, b)
	end
	if #rows == 0 then
		fs[#fs + 1] = "label[0.2,0.4;You have no wands.]"
	end
	fs[#fs + 1] = "scroll_container_end[]"
	if #rows > 8 then
		fs[#fs + 1] = ("scrollbaroptions[max=%d]"):format(math.ceil((#rows - 8) * RH * 10))
		fs[#fs + 1] = ("scrollbar[14.6,1.1;0.3,%f;vertical;spellscroll;0]"):format(view * RH)
	else
		fs[#fs + 1] = "scrollbar[-10,-10;0.1,0.1;vertical;spellscroll;0]"
	end
	fs[#fs + 1] = ("button[11.6,%f;3,0.9;menu_cancel;Cancel]"):format(h - 1.3)
	return table.concat(fs)
end

-- A button in the wand list. Returns true when it was one of ours.
-- (answer_key(key) answers NetHack's question; queue(pattern, key) queues
-- an answer for the direction question that may follow)
function spells.wand_fields(fields, answer_key, queue)
	for k in pairs(fields) do
		local how, b = k:match("^wd(%a+)_(%d+)$")
		if how then
			local invlet = string.char(tonumber(b))
			if how == "self" then
				queue("direction", ".")
				answer_key(invlet)
			else
				local name = ""
				for _, o in ipairs(wands()) do
					if o.invlet == invlet then
						name = o.name
					end
				end
				answer_key(27) -- (nothing is zapped yet: no time passes)
				spells.make_ready(nil, name, invlet)
			end
			return true
		end
	end
	return false
end

-- A button in the menu. Returns true when it was one of ours.
-- (answer_menu(sels) answers NetHack's menu; queue(pattern, key) queues an
-- answer for the question that follows)
function spells.fields(fields, req, answer_menu, queue)
	for k in pairs(fields) do
		local how, b = k:match("^sp(%a+)_(%d+)$")
		if how then
			local sel = string.char(tonumber(b))
			if how == "self" then
				queue("direction", ".")
				answer_menu(sel)
			elseif how == "cast" then
				answer_menu(sel)
			elseif how == "aim" then
				local name = ""
				for _, it in ipairs(req.items or {}) do
					if it.sel == sel then
						name = spells.row_name(it.text)
					end
				end
				answer_menu("") -- (nothing is cast yet: no time passes)
				spells.make_ready(sel, name)
			end
			return true
		end
	end
	return false
end

-- ---------------------------------------------------------------- readied
local function stop_glow()
	local r = spells.ready
	if r and r.spawner then
		core.delete_particlespawner(r.spawner)
		r.spawner = nil
	end
end

-- (wand = its inventory letter, when it's a wand being readied)
function spells.make_ready(sel, name, wand)
	stop_glow()
	local player = nhv.player.get()
	spells.ready = {sel = sel, name = name, wand = wand,
		until_us = core.get_us_time() + spells.READY_S * 1e6}
	if player then
		-- a glow around your hand (relative to you, turning with you)
		spells.ready.spawner = core.add_particlespawner({
			amount = 30 * spells.READY_S, time = spells.READY_S,
			attached = player,
			minpos = vector.new(0.15, 1.05, 0.35), maxpos = vector.new(0.5, 1.35, 0.6),
			minvel = vector.new(-0.15, 0.1, -0.15), maxvel = vector.new(0.15, 0.5, 0.15),
			minexptime = 0.25, maxexptime = 0.6, minsize = 0.4, maxsize = 1.0,
			texture = "[fill:2x2:#90C8FF", glow = 14,
			playername = player:get_player_name(),
		})
	end
	if wand then
		nhv.hud.message(("You ready %s. (Left-click to zap it where you aim.)"):format(
			name ~= "" and name or "the wand"))
	else
		nhv.hud.message(("You ready %s. (Left-click to cast it where you aim.)"):format(
			name ~= "" and name or "the spell"))
	end
end

function spells.cancel(quiet)
	if spells.ready then
		local wand = spells.ready.wand ~= nil
		stop_glow()
		spells.ready = nil
		if not quiet then
			nhv.hud.message(wand and "You lower the wand." or "The spell fades from your hand.")
		end
	end
end

-- Left-click with a spell readied: cast it where you aim. Returns true when
-- the click was used for that.
function spells.release(player)
	local r = spells.ready
	if not r then
		return false
	end
	if not nh.ready() or nhv.clock.busy() then
		return true -- (still busy: keep holding it)
	end
	stop_glow()
	spells.ready = nil
	local now = core.get_us_time()
	-- NetHack's direction: the nearest of its 8 to where you look (the zap
	-- itself flies along your look - see clock.act; up, down and yourself
	-- stay as they are)
	local function look_dir(dir)
		if dir == "<" or dir == ">" or dir == "." then
			return dir
		end
		local dx, dy = U.vec_to_dir(player:get_look_dir())
		return (dx ~= 0 or dy ~= 0) and U.dir_key(dx, dy) or dir
	end
	if r.wand then
		-- (looking straight down zaps down, never at yourself: that's Self)
		local dir = look_dir(nhv.actions.pointed_dir_key(player, "zap", true))
		table.insert(nhv.ui.auto_answers, {pattern = "direction", key = dir, t = now})
		nhv.actions.swing()
		nhv.clock.act({{key = "z"}, {key = r.wand}}, {kind = "zap"})
		return true
	end
	-- (looking down means down for dig, but yourself for anything else)
	local dir = look_dir(nhv.actions.pointed_dir_key(player, r.name == "dig" and "dig" or r.name, true))
	table.insert(nhv.ui.auto_answers, {pattern = spells.PROMPT, menu = r.sel, t = now})
	table.insert(nhv.ui.auto_answers, {pattern = "direction", key = dir, t = now})
	nhv.actions.swing()
	nhv.clock.act({{key = "Z"}}, {kind = "spell"})
	return true
end

core.register_globalstep(function()
	local r = spells.ready
	if r and core.get_us_time() > r.until_us then
		spells.cancel()
	end
end)

-- a new level or a game that ended: nothing stays readied
nh.on_snapshot(function(snap)
	if not snap or (spells.ready and snap.hero and U.has(snap.hero.flags, U.HERO.DEAD)) then
		spells.cancel(true)
	end
end)

-- ---------------------------------------------------------------- bolts
-- Beams that NetHack only works out square by square (force bolt,
-- striking, slow / speed monster, healing someone, knock, dig, polymorph,
-- teleport away...) fly as a quick glowing bolt from your hand to where
-- the beam ended, with a burst there. (Rays like magic missile and sleep
-- have their own; see rays.lua.)
local BOLT_SPEED = 25 -- nodes per second

-- colour by what was zapped (the spell's or wand's name contains...)
local BOLT_COLORS = {
	{"heal", "#60FF80"}, {"slow", "#B070FF"}, {"speed", "#FFE040"},
	{"haste", "#FFE040"}, {"knock", "#FFC040"}, {"opening", "#FFC040"},
	{"lock", "#FFC040"}, {"dig", "#C08040"}, {"polymorph", "#FF60E0"},
	{"teleport", "#40E0FF"}, {"cancel", "#E0E0E0"}, {"undead", "#FFF0A0"},
	{"invisib", "#A0A0C0"}, {"probing", "#6090FF"}, {"stone", "#D0B080"},
	{"striking", "#C0D8FF"}, {"force", "#C0D8FF"},
}
local function bolt_color(otyp)
	local name = (core.nh_obj_name and core.nh_obj_name(otyp) or ""):lower()
	for _, c in ipairs(BOLT_COLORS) do
		if name:find(c[1], 1, true) then
			return c[2]
		end
	end
	return "#90C8FF"
end

local function burst(pos, color, amount)
	core.add_particlespawner({
		amount = amount, time = 0.05, pos = pos,
		minvel = vector.new(-2.5, -1.5, -2.5), maxvel = vector.new(2.5, 2.5, 2.5),
		minexptime = 0.2, maxexptime = 0.45, minsize = 0.6, maxsize = 1.4,
		texture = "[fill:2x2:" .. color, glow = 14,
	})
end

core.register_entity("nhv:bolt", {
	initial_properties = {
		visual = "sprite", visual_size = {x = 0.45, y = 0.45},
		textures = {"[fill:4x4:#FFFFFF"}, glow = 14, physical = false,
		pointable = false, static_save = false, collisionbox = {0, 0, 0, 0, 0, 0},
	},
	on_step = function(self, dtime)
		self.left = (self.left or 0) - dtime
		if self.left <= 0 then
			if self.target then
				self.object:set_pos(self.target)
				burst(self.target, self.color or "#90C8FF", 18)
			end
			self.object:remove()
		end
	end,
})

-- (texture: an object's picture instead of a glowing bolt)
local function fly_bolt(otyp, x0, y0, x1, y1, texture)
	local player = nhv.player.get()
	local color = texture and "#C0C0C0" or bolt_color(otyp)
	local from
	if player then
		-- (from your hand: a little ahead, right and below your eyes)
		local p = player:get_pos()
		local yaw = player:get_look_horizontal()
		local fwd = vector.new(-math.sin(yaw), 0, math.cos(yaw))
		local right = vector.new(math.cos(yaw), 0, math.sin(yaw))
		from = vector.add(vector.add(p, vector.new(0, 1.25, 0)),
			vector.add(vector.multiply(fwd, 0.6), vector.multiply(right, 0.3)))
	else
		from = U.tile_center(x0, y0, U.STAND_Y + 1.25)
	end
	local to = U.tile_center(x1, y1, U.STAND_Y + 1.1)
	local dist = vector.distance(from, to)
	local obj = core.add_entity(from, "nhv:bolt")
	if not obj or dist < 0.1 then
		return
	end
	local t = dist / BOLT_SPEED
	if texture then
		obj:set_properties({textures = {texture}, visual_size = {x = 0.7, y = 0.7}, glow = 0})
	else
		obj:set_properties({textures = {"[fill:4x4:" .. color}})
	end
	obj:set_velocity(vector.multiply(vector.direction(from, to), BOLT_SPEED))
	local ent = obj:get_luaentity()
	ent.left, ent.target, ent.color = t, to, color
	-- a trail behind it
	core.add_particlespawner({
		amount = math.max(8, math.floor(dist * 6)), time = t, attached = obj,
		minpos = vector.new(-0.08, -0.08, -0.08), maxpos = vector.new(0.08, 0.08, 0.08),
		minvel = vector.new(-0.3, -0.3, -0.3), maxvel = vector.new(0.3, 0.3, 0.3),
		minexptime = 0.15, maxexptime = 0.3, minsize = 0.5, maxsize = 0.9,
		texture = "[fill:2x2:" .. color, glow = 14,
	})
	burst(from, color, 6)
end

nh.on_event(function(evs)
	for _, ev in ipairs(evs) do
		if ev.kind == "combat" then
			local otyp, x0, y0, x1, y1 = ev.text:match("^beam (%d+) (%d+) (%d+) (%d+) (%d+)")
			if otyp then
				fly_bolt(tonumber(otyp), tonumber(x0), tonumber(y0), tonumber(x1), tonumber(y1))
			end
			local tile, tx0, ty0, tx1, ty1 = ev.text:match("^thrown (%d+) (%d+) (%d+) (%d+) (%d+)")
			if tile then
				fly_bolt(0, tonumber(tx0), tonumber(ty0), tonumber(tx1), tonumber(ty1),
					nhv_tiles.texture(tonumber(tile)))
			end
		end
	end
end)

return spells
