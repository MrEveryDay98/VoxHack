-- The hotbar and the command line.
--
-- Hotbar (drawn by the game; Luanti's own hotbar is hidden and nothing on
-- it can be selected):
--   [primary weapon] [alternate weapon]   [1] [2] [3] [4] [5]
-- The weapon you're wielding has a green frame. Keys 1-5 do the actions in
-- ACTIONS (the NetHack Voxel build of Luanti sends them as "/nhvkey <n>").
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
-- X and P (the NetHack Voxel build of Luanti sends "/nhvkey search" and
-- "/nhvkey pay"; paying only works in a shop)
hotbar.SEARCH = {"Search", "s"}
hotbar.PAY = {"Pay", "p", shop = true}

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
local function slot_x(k)
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

local function frame(color)
	return ("[fill:%dx%d:%s^[fill:%dx%d:3,3:#141418E0"):format(SLOT, SLOT, color, SLOT - 6, SLOT - 6)
end

local SEARCH_DIM = 0x90C8C8C8 -- (see-through grey: the alpha byte is first)
local HINT_LIT = 0xFFFFD080

local function build(player)
	measure(player)
	if nhv.hud.place_status then
		nhv.hud.place_status(player, SLOT + 28) -- (the status line sits just above)
	end
	for k = 1, 7 do
		hud["bg" .. k] = add(player, {type = "image", offset = {x = slot_x(k), y = Y},
			scale = {x = 1, y = 1}, text = frame("#50505A"), z_index = 50})
		hud["icon" .. k] = add(player, {type = "image", offset = {x = slot_x(k), y = Y - 4},
			scale = {x = 2.5 * SLOT / 64, y = 2.5 * SLOT / 64}, text = "blank.png", z_index = 51})
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
		alignment = {x = 1, y = 0}, number = SEARCH_DIM, text = "X  Search", z_index = 52})
	hud.pay = add(player, {type = "text", offset = {x = hx, y = Y + SLOT * 0.2},
		alignment = {x = 1, y = 0}, number = SEARCH_DIM, text = "", z_index = 52})
	-- on the other side, "G  Enhance Skills" while a skill can be advanced
	-- (see update_enhance)
	hud.enhance = add(player, {type = "text", offset = {x = slot_x(1) - SLOT / 2 - 14, y = Y},
		alignment = {x = -1, y = 0}, number = SEARCH_DIM, text = "", z_index = 52})
	-- the cooldown bar: just above the hotbar while an action plays out
	-- (until it's gone you can't act again); see update_cooldown
	hud.cooldown = add(player, {type = "image", offset = {x = 0, y = Y - SLOT / 2 - 10},
		scale = {x = 0, y = 4}, text = "[fill:1x1:#FFFFFF", z_index = 52})
	cooldown_w = nil
end

-- the hint lights up for a moment when X is pressed
function hotbar.flash_search()
	local player = nhv.player.get()
	if player and hud.search then
		player:hud_change(hud.search, "number", HINT_LIT)
		core.after(0.2, function()
			if player:is_player() and hud.search then
				player:hud_change(hud.search, "number", SEARCH_DIM)
			end
		end)
	end
end

-- "P  Pay Shop": shown while you're in a shop; grey, pulsing yellow while
-- you owe it something (picked up something for sale, used something up)
local pay = {shown = false, owes = false, color = nil}

local function set_pay_color(player, c)
	if pay.color ~= c then
		pay.color = c
		player:hud_change(hud.pay, "number", c)
	end
end

local function update_pay(player, hero)
	if not hud.pay then
		return
	end
	local shown = hero and U.has(hero.flags, U.HERO.INSHOP) or false
	pay.owes = shown and U.has(hero.flags, U.HERO.OWES)
	if shown ~= pay.shown then
		pay.shown = shown
		player:hud_change(hud.pay, "text", shown and "P  Pay Shop" or "")
	end
	if not pay.owes then
		set_pay_color(player, SEARCH_DIM)
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
		local a, b = channel(SEARCH_DIM, shift), channel(0xFFFFD040, shift)
		c = c + math.floor(a + (b - a) * k + 0.5) * 2 ^ shift
	end
	return c
end

-- "G  Enhance Skills": left of the hotbar while NetHack would let you
-- advance a skill; pulsing
local enhance = {shown = false, color = nil}

local function update_enhance(player, hero)
	if not hud.enhance then
		return
	end
	local shown = hero and U.has(hero.flags, U.HERO.ENHANCE) or false
	if shown ~= enhance.shown then
		enhance.shown = shown
		player:hud_change(hud.enhance, "text", shown and "G  Enhance Skills" or "")
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
	if can and enhance.color ~= c then
		enhance.color = c
		player:hud_change(hud.enhance, "number", c)
	end
end)

local function refresh(player, inv)
	if not hud.bg1 then
		return
	end
	local wep, alt = weapons(inv)
	for k, o in ipairs({wep or false, alt or false}) do
		player:hud_change(hud["icon" .. k], "text", o and nhv_tiles.texture(o.tile) or "blank.png")
		-- the weapon in your hands is framed green
		player:hud_change(hud["bg" .. k], "text", frame(o and k == 1 and "#30C040" or "#50505A"))
	end
	-- your hand shows the wielded weapon
	local pinv = player:get_inventory()
	pinv:set_size("main", 1)
	pinv:set_size("craft", 0)
	local st = ItemStack("")
	if wep then
		st = ItemStack(nhv_tiles.item(wep.tile))
		local meta = st:get_meta()
		meta:set_string("description", wep.invlet .. " - " .. wep.name)
		meta:set_string("nhv_invlet", wep.invlet)
	end
	pinv:set_list("main", {st})
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
	description = "(NetHack Voxel) action key",
	func = function(pname, param)
		if param == "look" then
			local player = core.get_player_by_name(pname)
			if player and not nhv.ui.open and nh.ready() then
				hotbar.look(player)
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
		if param == "search" then
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
			or (param == "pay" and hotbar.PAY)
		-- (a held key repeats: each press waits until the last action has
		-- played out, so it repeats at action speed instead of piling up)
		if not a or nhv.ui.open or not nh.ready() or nhv.clock.busy() then
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
-- plays out fast, and stops early if something turns up, as in NetHack
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
	description = "(NetHack Voxel) chat prompt opened/closed",
	func = function(_, param)
		nhv.ui.chat_open = param == "open"
		return true
	end,
})

-- any menu on screen (the inventory, a NetHack question, a container...):
-- the game pauses (the NetHack Voxel build of Luanti reports these)
nhv.ui.menu_open = false
core.register_chatcommand("nhvmenu", {
	description = "(NetHack Voxel) a menu opened/closed",
	func = function(_, param)
		nhv.ui.menu_open = param == "open"
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
