-- The hotbar and the command line.
--
-- Hotbar (drawn by the game; Luanti's own hotbar is hidden and nothing on
-- it can be selected):
--   [primary weapon] [alternate weapon]   [1] [2] [3] [4] [5]
-- The weapon you're wielding has a green frame. Keys 1-5 do the actions in
-- ACTIONS (the VoxHack build of Luanti sends them as "/nhvkey <n>"); with
-- Shift held they use your quick items, with Ctrl they cast your quick
-- spells ("/nhvkey s<n>", "c<n>": quick.lua) - the slots show those while
-- it's held, and a line over the hotbar says what the keys and the mouse
-- do.
-- Your hand always holds the wielded weapon.
--
-- Chat (T) is a NetHack command line: type a command and press Enter. The
-- game pauses while it's open, and while any menu or prompt is on screen.
--   #pray, #loot ...   extended commands (the # can be left out: "pray")
--   s, 20s, Ea ...     keys, as you'd type them in NetHack (^D = Ctrl+D)

local nh = nhv.nh
local U = nhv.util
local hotbar = {}
nhv.hotbar = hotbar

-- the five action keys: label, NetHack keys (directions come from where
-- you look, like everywhere else)
hotbar.ACTIONS = {
	{"Fire", "f"},
	{"Kick", "\4", aim = "kick"}, -- (the keys come from actions.kick_keys)
	{"Zap", "z"},
	{"Spell", "Z"},
	{"Eat", "e"},
}
-- X and P (the VoxHack build of Luanti sends "/nhvkey search" and
-- "/nhvkey pay"; paying only works in a shop)
hotbar.SEARCH = {"Search", "s"}
hotbar.PAY = {"Pay", "p", shop = true}
-- F picks up (the VoxHack build of Luanti sends "/nhvkey pickup")
hotbar.PICKUP = {"Pick up", ","}

local W = {WEP = 0x100, SWAPWEP = 0x400}
local SLOT, GAP, Y   -- slot size, gap and height on screen (pixels; see measure)
local hud = {}       -- element ids
local cooldown_w     -- the cooldown bar's width shown now (pixels)

-- slots grow with Graphics > Text size so their labels fit, as far as
-- the window's width allows
local function measure(player)
	SLOT = math.floor(64 * nhv.theme.box_scale())
	GAP = 6
	local info = player and core.get_player_window_information(player:get_player_name())
	if info and info.size and info.real_hud_scaling then
		-- (7 slots, 6 gaps and the half-slot gap, in HUD pixels)
		local room = 0.96 * info.size.x / info.real_hud_scaling
		SLOT = math.max(48, math.min(SLOT, math.floor((room - 6 * GAP) / 7.5)))
	end
	Y = -SLOT / 2 - 8
end
measure()

local function has_mask(o, m)
	return (o.worn or 0) % (m * 2) >= m
end

local function weapons(inv)
	local wep, alt
	for _, o in ipairs(inv or {}) do
		if has_mask(o, W.WEP) then
			wep = o
		elseif has_mask(o, W.SWAPWEP) then
			alt = o
		end
	end
	return wep, alt
end

-- ---------------------------------------------------------------- drawing
-- x offset (from the screen centre) of slot k: 1-2 weapons, 3-7 actions
-- (with the side bars, the weapons are in the left one: the actions alone,
-- in the middle)
local function slot_x(k)
	if nhv.sidebars and nhv.sidebars.on() then
		local total = 5 * (SLOT + GAP) - GAP
		return (k - 3) * (SLOT + GAP) - total / 2 + SLOT / 2
	end
	local x = (k - 1) * (SLOT + GAP)
	if k >= 3 then
		x = x + SLOT / 2 -- a gap between the weapons and the actions
	end
	local total = 7 * (SLOT + GAP) + SLOT / 2 - GAP
	return x - total / 2 + SLOT / 2
end

local function add(player, def)
	def.position = {x = 0.5, y = 1}
	def.alignment = def.alignment or {x = 0, y = 0}
	def.z_index = def.z_index or 50
	return player:hud_add(def)
end

-- a slot (skin.lua's), the grey of an unlit one or ringed in color
local function frame(color, size)
	return nhv.skin.slot(size or SLOT, color ~= "#50505A" and color or nil)
end
local wep_size -- (the weapons' slots' size, in the side bars; nil: the hotbar's)

local SEARCH_DIM = 0x90C8C8C8 -- (see-through grey: the alpha byte is first)
-- (the keys' hints: X, P, G - see-through over the view; in the side bars'
-- box solid, and always there, darker while the key would do nothing)
local hint_shown = {} -- (their text and colour now: pay_text=, pay_color=...)
local function idle()
	return nhv.sidebars and nhv.sidebars.on() and 0xFFC8C8C8 or SEARCH_DIM
end
local layer, layer_sig = "actions", nil -- (what the action slots show: refresh_layer)
local HINT_LIT = 0xFFFFD080

local function build(player)
	measure(player)
	if nhv.hud.place_status then
		nhv.hud.place_status(player, SLOT + 50) -- (the status line sits above, over the hints)
	end
	local g = nhv.sidebars and nhv.sidebars.geometry(player)
	wep_size = g and g.weapons.size or nil
	for k = 1, 7 do
		if g and k <= 2 then
			-- (in the left bar: the wielded one, and the other down and right)
			local at, S = g.weapons[k], g.weapons.size
			hud["bg" .. k] = player:hud_add({type = "image", position = {x = 0, y = 0},
				alignment = {x = 1, y = 1}, offset = {x = at.x, y = at.y},
				scale = {x = 1, y = 1}, text = frame("#50505A", S), z_index = 50})
			hud["icon" .. k] = player:hud_add({type = "image", position = {x = 0, y = 0},
				alignment = {x = 0, y = 0}, offset = {x = at.x + S / 2, y = at.y + S / 2},
				scale = {x = (S - 12) / 16, y = (S - 12) / 16}, text = "blank.png", z_index = 51})
		else
			hud["bg" .. k] = add(player, {type = "image", offset = {x = slot_x(k), y = Y},
				scale = {x = 1, y = 1}, text = frame("#50505A"), z_index = 50})
			hud["icon" .. k] = add(player, {type = "image", offset = {x = slot_x(k), y = Y - 4},
				scale = {x = 2.5 * SLOT / 64, y = 2.5 * SLOT / 64}, text = "blank.png", z_index = 51})
		end
	end
	for k = 3, 7 do
		local a = hotbar.ACTIONS[k - 2]
		hud["key" .. k] = add(player, {type = "text", offset = {x = slot_x(k) - SLOT / 2 + 9 * SLOT / 64, y = Y - SLOT / 2 + 10 * SLOT / 64},
			number = 0xFFD080, text = tostring(k - 2), z_index = 52})
		hud["label" .. k] = add(player, {type = "text", offset = {x = slot_x(k), y = Y + 2},
			number = 0xFFFFFF, text = a and a[1] or "", z_index = 52})
	end
	-- X searches: a faint hint beside the hotbar (lights up when used);
	-- in a shop "P  Pay Shop" goes under it (see update_pay)
	local hx = slot_x(7) + SLOT / 2 + 14
	hud.search = add(player, {type = "text", offset = {x = hx, y = Y - SLOT * 0.2},
		alignment = {x = 1, y = 0}, number = idle(), text = "X  Search", z_index = 52})
	hud.pay = add(player, {type = "text", offset = {x = hx, y = Y + SLOT * 0.2},
		alignment = {x = 1, y = 0}, number = idle(), text = "", z_index = 52})
	hint_shown = {}
	-- on the other side, "G  Enhance Skills" while a skill can be advanced
	-- (see update_enhance)
	hud.enhance = add(player, {type = "text", offset = {x = slot_x(g and 3 or 1) - SLOT / 2 - 14, y = Y},
		alignment = {x = -1, y = 0}, number = idle(), text = "", z_index = 52})
	-- (the side bars: these hints at the bottom of the right one, a line
	-- each - the second is Q's, hud.lua)
	if g then
		for i, key in pairs({[1] = "search", [3] = "pay", [4] = "enhance"}) do
			player:hud_change(hud[key], "position", {x = 1, y = 0})
			player:hud_change(hud[key], "alignment", {x = 1, y = 1})
			player:hud_change(hud[key], "offset", {x = g.hints_x, y = g.hints_y + (i - 1) * g.line_h})
			player:hud_change(hud[key], "style", nhv.sidebars.text_style())
		end
	end
	-- the line saying what the keys and the mouse do (refresh_layer)
	hud.hint = add(player, {type = "text", offset = {x = 0, y = Y - SLOT / 2 - 26},
		number = SEARCH_DIM, text = "", z_index = 52})
	layer_sig = nil
	-- the cooldown bar: just above the hotbar while an action plays out
	-- (until it's gone you can't act again); see update_cooldown
	hud.cooldown = add(player, {type = "image", offset = {x = 0, y = Y - SLOT / 2 - 10},
		scale = {x = 0, y = 4}, text = "[fill:1x1:#FFFFFF", z_index = 52})
	cooldown_w = nil
end

-- ---------------------------------------------------------------- layers
-- Holding Shift the action slots show your quick items, holding Ctrl your
-- quick spells (quick.lua): the picture, and what it does or the spell's
-- name; the line over the hotbar says what the keys and the mouse do with
-- that held
local HINTS = {
	actions = "Shift: quick items    Ctrl: quick spells    Shift+LMB: fire",
	items = "Shift+1-5: quick items    Shift+LMB: fire    Shift+RMB (hold): yourself",
	spells = "Ctrl+1-5: cast where you aim    Ctrl+RMB (hold): magic",
}

local function layer_slots(which)
	local out = {}
	local most = math.max(4, math.floor(SLOT / 8.5))
	for n = 1, 5 do
		if which == "items" then
			local o, s = nhv.quick.find(n)
			out[n] = {icon = o and nhv_tiles.texture(o.tile) or "blank.png",
				label = s and s.action:sub(1, most) or ""}
		elseif which == "spells" then
			-- ("@" before it: cast at yourself - NetHack's you)
			local sp, _, self = nhv.quick.spell(n)
			out[n] = {icon = sp and nhv_tiles.texture(sp.tile) or "blank.png",
				label = sp and ((self and sp.directional and "@" or "") .. sp.name):sub(1, most) or ""}
		else
			local a = hotbar.ACTIONS[n]
			out[n] = {icon = "blank.png", label = a and a[1] or ""}
		end
	end
	return out
end

function hotbar.refresh_layer(player, force)
	if not hud.label3 then
		return
	end
	local slots = layer_slots(layer)
	local parts = {layer}
	for n, s in ipairs(slots) do
		parts[#parts + 1] = n .. s.icon .. "|" .. s.label
	end
	local sig = table.concat(parts, ";")
	if sig == layer_sig and not force then
		return
	end
	layer_sig = sig
	-- (a picture: it in the slot's top, its words under it)
	local pictured = layer ~= "actions"
	for n, s in ipairs(slots) do
		local k = n + 2
		player:hud_change(hud["icon" .. k], "text", s.icon)
		player:hud_change(hud["icon" .. k], "offset", {x = slot_x(k), y = pictured and Y - SLOT * 0.1 or Y - 4})
		player:hud_change(hud["icon" .. k], "scale", pictured and {x = 1.8 * SLOT / 64, y = 1.8 * SLOT / 64}
			or {x = 2.5 * SLOT / 64, y = 2.5 * SLOT / 64})
		player:hud_change(hud["label" .. k], "text", s.label)
		player:hud_change(hud["label" .. k], "offset", {x = slot_x(k), y = pictured and Y + SLOT * 0.33 or Y + 2})
	end
	if hud.hint then
		player:hud_change(hud.hint, "text", HINTS[layer])
	end
end

-- (Shift or Ctrl held, or let go: the slots change)
local layer_t = 0
core.register_globalstep(function(dtime)
	layer_t = layer_t + dtime
	if layer_t < 0.05 then
		return
	end
	layer_t = 0
	local player = nhv.player.get()
	if not (player and hud.label3) then
		return
	end
	local ctl = player:get_player_control()
	local want = ctl.sneak and "items" or (ctl.nhv_ctrl and "spells") or "actions"
	if want ~= layer then
		layer = want
		hotbar.refresh_layer(player, true)
	elseif layer_sig == nil then
		hotbar.refresh_layer(player, true)
	end
end)

-- the hint lights up for a moment when X is pressed
function hotbar.flash_search()
	local player = nhv.player.get()
	if player and hud.search then
		player:hud_change(hud.search, "number", HINT_LIT)
		core.after(0.2, function()
			if player:is_player() and hud.search then
				player:hud_change(hud.search, "number", idle())
			end
		end)
	end
end

-- "P  Pay Shop": shown while you're in a shop; grey, pulsing yellow while
-- you owe it something (picked up something for sale, used something up)
-- (in the side bars it's always there, darker out of a shop)
local pay = {owes = false}

local function set_pay_color(player, c)
	if hint_shown.pay_color ~= c then
		hint_shown.pay_color = c
		player:hud_change(hud.pay, "number", c)
	end
end

local function update_pay(player, hero)
	if not hud.pay then
		return
	end
	local shown = hero and U.has(hero.flags, U.HERO.INSHOP) or false
	pay.owes = shown and U.has(hero.flags, U.HERO.OWES)
	local text = (shown or (nhv.sidebars and nhv.sidebars.on())) and "P  Pay Shop" or ""
	if text ~= hint_shown.pay_text then
		hint_shown.pay_text = text
		player:hud_change(hud.pay, "text", text)
	end
	if not pay.owes then
		set_pay_color(player, shown and idle() or nhv.hud.KEY_OFF)
	end
end

-- (a channel of a colour: c is 0xAARRGGBB, shift 24 / 16 / 8 / 0)
local function channel(c, shift)
	return math.floor(c / 2 ^ shift) % 256
end

-- grey -> yellow -> grey, about once a second (in steps, so it isn't sent
-- to the screen every frame)
local function pulse_color(t)
	local k = math.floor((0.5 - 0.5 * math.cos(t * 2 * math.pi)) * 8 + 0.5) / 8
	local c = 0
	for _, shift in ipairs({24, 16, 8, 0}) do
		local a, b = channel(idle(), shift), channel(0xFFFFD040, shift)
		c = c + math.floor(a + (b - a) * k + 0.5) * 2 ^ shift
	end
	return c
end

-- "G  Enhance Skills": left of the hotbar while NetHack would let you
-- advance a skill; pulsing (in the side bars always there, darker while
-- there's none)
local enhance = {shown = false}

local function update_enhance(player, hero)
	if not hud.enhance then
		return
	end
	local shown = hero and U.has(hero.flags, U.HERO.ENHANCE) or false
	enhance.shown = shown
	local text = (shown or (nhv.sidebars and nhv.sidebars.on())) and "G  Enhance Skills" or ""
	if text ~= hint_shown.enhance_text then
		hint_shown.enhance_text = text
		player:hud_change(hud.enhance, "text", text)
	end
	if not shown and hint_shown.enhance_color ~= nhv.hud.KEY_OFF then
		hint_shown.enhance_color = nhv.hud.KEY_OFF
		player:hud_change(hud.enhance, "number", nhv.hud.KEY_OFF)
	end
end

-- the cooldown bar shrinks as the action plays out
local function update_cooldown(player)
	if not hud.cooldown then
		return
	end
	local w = math.floor(SLOT * 2.5 * nhv.clock.cooldown() / 2 + 0.5) * 2 -- (even: stays centred)
	if w ~= cooldown_w then
		cooldown_w = w
		player:hud_change(hud.cooldown, "scale", {x = w, y = 4})
	end
end

core.register_globalstep(function()
	local player = nhv.player.get()
	if player then
		update_cooldown(player)
	end
end)

local pulse_t = 0
core.register_globalstep(function(dtime)
	local owes = pay.owes and hud.pay
	local can = enhance.shown and hud.enhance
	if not (owes or can) then
		return
	end
	pulse_t = pulse_t + dtime
	local player = nhv.player.get()
	if not player then
		return
	end
	local c = pulse_color(pulse_t)
	if owes then
		set_pay_color(player, c)
	end
	if can and hint_shown.enhance_color ~= c then
		hint_shown.enhance_color = c
		player:hud_change(hud.enhance, "number", c)
	end
end)

local function refresh(player, inv)
	if not hud.bg1 then
		return
	end
	local wep, alt = weapons(inv)
	local h = nh.snap and nh.snap.hero
	local two = h and U.has(h.flags, U.HERO.TWOWEAP) and alt
	for k, o in ipairs({wep or false, alt or false}) do
		player:hud_change(hud["icon" .. k], "text", o and nhv_tiles.texture(o.tile) or "blank.png")
		-- the weapons in your hands are framed green (both, dual wielding)
		player:hud_change(hud["bg" .. k], "text", frame(o and (k == 1 or two) and "#30C040" or "#50505A", wep_size))
	end
	-- your hand shows the wielded weapon
	local pinv = player:get_inventory()
	pinv:set_size("main", 1)
	pinv:set_size("craft", 0)
	local st = ItemStack("")
	-- (bare-handed in gloves: fists of the gloves' colour)
	local glove
	for _, o in ipairs(inv or {}) do
		if has_mask(o, 0x10) then -- (W_ARMG: gloves worn)
			glove = nhv_tiles.glove_color(o.tile)
		end
	end
	if not wep and glove then
		st = ItemStack("nhv:fist")
		st:get_meta():set_string("wield_image", nhv_tiles.fist(false, glove))
	end
	if wep then
		st = ItemStack(nhv_tiles.item(wep.tile))
		local meta = st:get_meta()
		meta:set_string("description", wep.invlet .. " - " .. wep.name)
		meta:set_string("nhv_invlet", wep.invlet)
		-- (ASCII mode: its character in your hand - ascii.lua)
		if nhv_tiles.ascii then
			meta:set_string("wield_image", nhv_tiles.texture(wep.tile))
		end
	end
	pinv:set_list("main", {st})
	-- dual wielding, your left hand holds the secondary weapon; a Monk
	-- fighting bare-handed has a fist in each (drawn by the VoxHack
	-- build of Luanti from this list; empty: no left hand)
	local left = ItemStack("")
	if two then
		left = ItemStack(nhv_tiles.item(alt.tile))
		-- (mirrored: the left hand's picture, not the right's)
		left:get_meta():set_string("wield_image", nhv_tiles.texture(alt.tile) .. "^[transformFX")
	elseif h and U.has(h.flags, U.HERO.TWOFISTS) then
		left = ItemStack("nhv:fist")
		left:get_meta():set_string("wield_image", nhv_tiles.fist(true, glove))
	end
	pinv:set_size("nhv_offhand", 1)
	pinv:set_list("nhv_offhand", {left})
end

-- redraw at a new size (Graphics > Text size)
function hotbar.rebuild(player)
	if not hud.bg1 then
		return -- (not built yet: it will be at the new size)
	end
	for k, id in pairs(hud) do
		player:hud_remove(id)
		hud[k] = nil
	end
	build(player)
	if nh.snap then
		refresh(player, nh.snap.inventory)
	end
	nhv.showroom.hide_new(player)
	pay.shown, pay.color = false, nil
	update_pay(player, nh.snap and nh.snap.hero)
	enhance.shown, enhance.color = false, nil
	update_enhance(player, nh.snap and nh.snap.hero)
end

core.register_on_joinplayer(function(player)
	player:hud_set_hotbar_itemcount(1)
	-- no built-in hotbar or chat text; number keys and the chat prompt are ours
	player:hud_set_flags({hotbar = false, chat = false, nhv_action_keys = true,
		nhv_chat_events = true})
	core.after(0, function()
		if player:is_player() then
			build(player)
			if nh.snap then
				refresh(player, nh.snap.inventory)
			end
			nhv.showroom.hide_new(player) -- (not a frame of it over the title)
		end
	end)
	-- (the window's size is only known a little after joining: fit to it then)
	core.after(1.5, function()
		if player:is_player() then
			hotbar.rebuild(player)
		end
	end)
end)

nh.on_snapshot(function(snap)
	local player = nhv.player.get()
	if snap and player then
		refresh(player, snap.inventory)
		update_pay(player, snap.hero)
		update_enhance(player, snap.hero)
		hotbar.refresh_layer(player) -- (what's in the quick slots)
	end
end)

-- ---------------------------------------------------------------- looking
-- The middle mouse button looks at what's under the crosshair (NetHack's
-- farlook, ;): the monster, object or feature it's on, or the block's square
-- (a wall, the floor, a trap...). Up to LOOK_RANGE squares away. What was
-- looked at flashes: a green box around it that fades.
local LOOK_RANGE = 25
local PING_S = 0.5

local function ping_textures(a)
	local tex = "[fill:16x16:#40FF60^[opacity:" .. a
	return {tex, tex, tex, tex, tex, tex}
end

core.register_entity("nhv:ping", {
	initial_properties = {
		visual = "cube", physical = false, pointable = false, static_save = false,
		collisionbox = {0, 0, 0, 0, 0, 0}, use_texture_alpha = true, glow = 14,
		shaded = false, backface_culling = false, textures = ping_textures(120),
	},
	on_step = function(self, dtime)
		self.age = (self.age or 0) + dtime
		if self.age >= PING_S then
			self.object:remove()
			return
		end
		-- fades in steps (each change is sent to the screen)
		local a = math.floor((1 - self.age / PING_S) * 6 + 0.5) * 20
		if a ~= self.alpha then
			self.alpha = a
			self.object:set_properties({textures = ping_textures(a)})
		end
	end,
})

local function ping(center, size)
	local obj = core.add_entity(center, "nhv:ping")
	if obj then
		obj:set_properties({visual_size = size, textures = ping_textures(120)})
		obj:get_luaentity().alpha = 120
	end
end

-- the square under the crosshair, and the box to flash around what's there
local function look_target(player)
	local pos = player:get_pos()
	local eye = vector.new(pos.x, pos.y + (player:get_properties().eye_height or 1.625), pos.z)
	local dir = player:get_look_dir()
	local ray = core.raycast(eye, vector.add(eye, vector.multiply(dir, LOOK_RANGE * U.TILE)), true, false)
	for pointed in ray do
		if pointed.type == "object" then
			local ent = pointed.ref:get_luaentity()
			local p = pointed.ref:get_pos()
			if ent and p and ent.name:sub(1, 4) == "nhv:" and ent.name ~= "nhv:ping" then
				local b = pointed.ref:get_properties().selectionbox or {-0.5, -0.5, -0.5, 0.5, 0.5, 0.5}
				local tx, ty = U.pos_to_tile(p)
				return tx, ty,
					vector.offset(p, (b[1] + b[4]) / 2, (b[2] + b[5]) / 2, (b[3] + b[6]) / 2),
					vector.new((b[4] - b[1]) * 1.1, (b[5] - b[2]) * 1.1, (b[6] - b[3]) * 1.1)
			end
		elseif pointed.type == "node" then
			-- (just inside the block that was hit, not on its face)
			local inside = vector.add(pointed.intersection_point, vector.multiply(dir, 0.05))
			local tx, ty = U.pos_to_tile(inside)
			return tx, ty, vector.round(inside), vector.new(1.04, 1.04, 1.04)
		end
	end
	return nil
end

function hotbar.look(player)
	local tx, ty, center, size = look_target(player)
	if not tx or not U.in_map(tx, ty) then
		return
	end
	ping(center, size)
	local h = nhv.player.hero
	if h and tx == h.x and ty == h.y then
		-- your own square: what's here (objects, a trap, the floor...), not
		-- you yourself (NetHack's :, which takes no time either)
		nh.act(":", {kind = "look"})
		return
	end
	nh.act({{key = "#"}, {text = ("nhvlook %d %d"):format(tx, ty)}}, {kind = "look"})
end

-- ---------------------------------------------------------------- action keys
local function flash_slot(k)
	local player = nhv.player.get()
	if player and hud["bg" .. k] then
		player:hud_change(hud["bg" .. k], "text", frame("#E0A020"))
		core.after(0.15, function()
			if player:is_player() then
				player:hud_change(hud["bg" .. k], "text", frame("#50505A"))
			end
		end)
	end
end

core.register_chatcommand("nhvkey", {
	description = "(VoxHack) action key",
	func = function(pname, param)
		if param == "retro" then
			-- (F7: retro mode on or off, as Options > Graphics does it -
			-- the HUD laid out again for the screen it's on now)
			local player = core.get_player_by_name(pname)
			if player and nhv.graphics then
				nhv.graphics.set_retro(player, not core.settings:get_bool("nhv_retro", false))
			end
			return true
		end
		if param == "sprites" then
			-- (F8: sprites flat or extruded, as Options > Graphics does it)
			if nhv.graphics then
				nhv.graphics.set_flat(not core.settings:get_bool("nhv_flat_sprites", false))
			end
			return true
		end
		if nhv.cutscene and nhv.cutscene.active then
			return true -- (a cutscene: keys do nothing, and aren't kept)
		end
		local notches = param:match("^wheel (%-?%d+)$")
		if notches then
			-- (the big map, when it's open and wider than the screen; else the
			-- side bars' inventory)
			if not nhv.hud.scroll_map(tonumber(notches)) and nhv.sidebars then
				nhv.sidebars.scroll_inventory(tonumber(notches))
			end
			return true
		end
		-- Shift + 1-5: a quick item; Ctrl + 1-5: a quick spell (quick.lua)
		local mod, qn = param:match("^([sc])(%d)$")
		if mod then
			local player = core.get_player_by_name(pname)
			qn = tonumber(qn)
			if player and qn >= 1 and qn <= nhv.quick.SLOTS then
				flash_slot(qn + 2)
				if mod == "s" then
					nhv.quick.use(player, qn)
				else
					nhv.quick.cast(player, qn)
				end
			end
			return true
		end
		if param == "look" then
			local player = core.get_player_by_name(pname)
			if player and not nhv.ui.open and nh.ready() then
				hotbar.look(player)
			end
			return true
		end
		if param == "wiki" then
			-- (F2: the NetHackWiki viewer, on what you look at; F2 again
			-- closes it - the engine does that while it's open)
			local player = core.get_player_by_name(pname)
			if player and not nhv.ui.open then
				nhv.wiki.toggle(player)
			end
			return true
		end
		if param == "ascii" then
			-- (F4: ASCII mode on or off - ascii.lua)
			if nh.snap then
				nhv.ascii.toggle()
			end
			return true
		end
		if param == "commands" then
			-- (F3: the command finder; F3 again closes it - the engine
			-- does that while it's open)
			local player = core.get_player_by_name(pname)
			if player and not nhv.ui.open then
				nhv.commands.toggle(player)
			end
			return true
		end
		if param == "invoke" then
			-- (Q: your form's special ability (#monster) when it has one -
			-- breathing, spitting, hiding...; otherwise #invoke the wielded
			-- item - an artifact's power, a crystal ball - when it has one.
			-- "Q  <what it does>" shows on the left then. A direction it
			-- asks for is where you look.)
			if nhv.ui.open or not nh.ready() or nhv.clock.busy() then
				return true
			end
			local ability = nhv.actions.monster_ability()
			local o = nhv.actions.invokable()
			if ability then
				nhv.actions.run({label = ability, keys = {{key = "#"}, {text = "monster"}}},
					{kind = "hotkey"})
			elseif o then
				nhv.actions.run({label = "Invoke", keys = {{key = "#"}, {text = "invoke"}, {key = o.invlet}}},
					{kind = "hotkey"})
			end
			return true
		end
		if param == "enhance" then
			-- (NetHack's #enhance: the skills you could advance are
			-- selectable in its list; takes no time)
			if not nhv.ui.open and nh.ready() and not nhv.clock.busy() then
				nhv.actions.run({label = "Enhance", free = true, keys = {{key = "#"}, {text = "enhance"}}},
					{kind = "info"})
			end
			return true
		end
		if param == "search" and nh.repeating then
			nh.answer_key(27) -- (searching for a number of turns: X stops it)
			return true
		elseif param == "search" then
			nhv.clock.search_held = true -- (searches on until let go)
		elseif param == "searchup" then
			nhv.clock.search_held = false
			return true
		elseif param == "searchcount" then
			hotbar.ask_search_count(core.get_player_by_name(pname))
			return true
		end
		local n = tonumber(param)
		local a = n and hotbar.ACTIONS[n] or (param == "search" and hotbar.SEARCH)
			or (param == "pay" and hotbar.PAY) or (param == "pickup" and hotbar.PICKUP)
		-- (a held key repeats: each press waits until the last action has
		-- played out, so it repeats at action speed instead of piling up;
		-- picking up just after a step waits for it instead - actions.run)
		if not a or nhv.ui.open or not nh.ready()
				or (nhv.clock.busy() and a ~= hotbar.PICKUP) then
			return true
		end
		local hero = nh.snap and nh.snap.hero
		if a.shop and not (hero and U.has(hero.flags, U.HERO.INSHOP)) then
			return true -- (no shopkeeper to pay)
		end
		if n then
			flash_slot(n + 2)
		elseif a == hotbar.SEARCH then
			hotbar.flash_search()
		end
		local keys = {}
		for c in a[2]:gmatch(".") do
			keys[#keys + 1] = {key = c}
		end
		local player = core.get_player_by_name(pname)
		if a.aim == "kick" and player then
			keys = nhv.actions.kick_keys(player)
		end
		nhv.actions.run({label = a[1], keys = keys}, {kind = "hotkey"})
		return true
	end,
})

-- ---------------------------------------------------------------- searching
-- Search held: another search as soon as the last has played out (time
-- runs fast meanwhile; clock.lua)
core.register_globalstep(function()
	if not nhv.clock.search_held then
		return
	end
	-- (a question or menu came up: searching stops - letting go of the key
	-- while it's up wouldn't be noticed)
	if nhv.ui.open or nhv.ui.menu_open or nhv.ui.chat_open then
		nhv.clock.search_held = false
		return
	end
	if not nh.ready() or nhv.clock.busy() then
		return
	end
	hotbar.flash_search()
	nhv.actions.run({label = hotbar.SEARCH[1], keys = {{key = "s"}}}, {kind = "search"})
end)

-- Ctrl+X: search for a number of turns (NetHack's count, "20s"); it
-- plays out turn by turn, fast forward, seen from behind you (as when
-- helpless), and stops early whenever NetHack would stop it, or on X
local COUNT_FORM = "nhv:searchcount"
hotbar.search_count = 20
function hotbar.ask_search_count(player)
	if not player or nhv.ui.open or not nh.ready() then
		return
	end
	core.show_formspec(player:get_player_name(), COUNT_FORM, nhv.theme.head(8, 3.6)
		.. "label[0.5,0.7;Search for how many turns?]"
		.. ("field[0.5,1.3;3,0.8;count;;%d]field_close_on_enter[count;false]"):format(hotbar.search_count)
		.. "button[3.8,1.3;3.7,0.8;go;Search]"
		.. "button[3.8,2.4;3.7,0.8;cancel;Cancel]")
end

core.register_on_player_receive_fields(function(player, formname, fields)
	if formname ~= COUNT_FORM then
		return false
	end
	if fields.go or fields.key_enter_field == "count" then
		local n = math.floor(tonumber(fields.count or "") or 0)
		core.close_formspec(player:get_player_name(), COUNT_FORM)
		if n >= 1 and nh.ready() and not nhv.clock.busy() then
			n = math.min(n, 999)
			hotbar.search_count = n
			hotbar.flash_search()
			nhv.clock.act(tostring(n) .. "s", {kind = "search_count"})
		end
	elseif fields.cancel then
		core.close_formspec(player:get_player_name(), COUNT_FORM)
	end
	return true
end)

-- ---------------------------------------------------------------- command line
nhv.ui.chat_open = false
core.register_chatcommand("nhvchat", {
	description = "(VoxHack) chat prompt opened/closed",
	func = function(_, param)
		nhv.ui.chat_open = param == "open"
		return true
	end,
})

-- any menu on screen (the inventory, a NetHack question, a container...):
-- the game pauses (the VoxHack build of Luanti reports these)
nhv.ui.menu_open = false
core.register_chatcommand("nhvmenu", {
	description = "(VoxHack) a menu opened/closed",
	func = function(pname, param)
		nhv.ui.menu_open = param == "open"
		if param == "open" and nhv.cutscene and nhv.cutscene.active and not nhv.cutscene.menus_ok then
			core.close_formspec(pname, "") -- (no inventory during a cutscene; the
			-- ascension's questions once it lets them: cutscene.lua)
		end
		return true
	end,
})

-- "pray" / "#pray" -> extended command; anything else -> keys ("^D" = Ctrl+D)
local function command_keys(text)
	text = text:gsub("^%s+", ""):gsub("%s+$", "")
	if text == "" then
		return nil
	end
	local ext = text:match("^#(.+)$") or (text:match("^%l[%l_]+$") and #text >= 3 and text)
	if ext then
		return {{key = "#"}, {text = ext}}
	end
	local keys = {}
	local i = 1
	while i <= #text do
		local c = text:sub(i, i)
		if c == "^" and i < #text then
			local nxt = text:sub(i + 1, i + 1):upper()
			keys[#keys + 1] = {key = string.char(nxt:byte() - 64)}
			i = i + 2
		else
			keys[#keys + 1] = {key = c}
			i = i + 1
		end
	end
	return keys
end

core.register_on_chat_message(function(_, message)
	if message:sub(1, 1) == "/" then
		return false -- chat commands (/nhvkey, ...) run as usual
	end
	nhv.ui.chat_open = false
	local keys = command_keys(message)
	if keys then
		if nh.ready() then
			nhv.hud.message("> " .. message)
			nhv.clock.act(keys, {kind = "command"})
		else
			nhv.hud.message("(busy - try again in a moment)")
		end
	end
	return true -- never shown as chat
end)

return hotbar
