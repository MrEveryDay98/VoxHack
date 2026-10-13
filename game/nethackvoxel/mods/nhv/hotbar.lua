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
-- game pauses while it's open.
--   #pray, #loot ...   extended commands (the # can be left out: "pray")
--   s, 20s, Ea ...     keys, as you'd type them in NetHack (^D = Ctrl+D)

local nh = nhv.nh
local hotbar = {}
nhv.hotbar = hotbar

-- the five action keys: label, NetHack keys (directions come from where
-- you look, like everywhere else)
hotbar.ACTIONS = {
	{"Fire", "f"},
	{"Kick", "\4"},
	{"Pick up", ","},
	{"Search", "s"},
	{"Eat", "e"},
}

local W = {WEP = 0x100, SWAPWEP = 0x400}
local SLOT = 64      -- slot size on screen (pixels)
local GAP = 6
local hud = {}       -- element ids

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
	def.alignment = {x = 0, y = 0}
	def.z_index = def.z_index or 50
	return player:hud_add(def)
end

local Y = -SLOT / 2 - 8

local function frame(color)
	return ("[fill:%dx%d:%s^[fill:%dx%d:3,3:#141418E0"):format(SLOT, SLOT, color, SLOT - 6, SLOT - 6)
end

local function build(player)
	for k = 1, 7 do
		hud["bg" .. k] = add(player, {type = "image", offset = {x = slot_x(k), y = Y},
			scale = {x = 1, y = 1}, text = frame("#50505A"), z_index = 50})
		hud["icon" .. k] = add(player, {type = "image", offset = {x = slot_x(k), y = Y - 4},
			scale = {x = 2.5, y = 2.5}, text = "blank.png", z_index = 51})
	end
	for k = 3, 7 do
		local a = hotbar.ACTIONS[k - 2]
		hud["key" .. k] = add(player, {type = "text", offset = {x = slot_x(k) - SLOT / 2 + 9, y = Y - SLOT / 2 + 10},
			number = 0xFFD080, text = tostring(k - 2), z_index = 52})
		hud["label" .. k] = add(player, {type = "text", offset = {x = slot_x(k), y = Y + 2},
			number = 0xFFFFFF, text = a and a[1] or "", z_index = 52})
	end
end

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
end)

nh.on_snapshot(function(snap)
	local player = nhv.player.get()
	if snap and player then
		refresh(player, snap.inventory)
	end
end)

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
	func = function(_, param)
		local n = tonumber(param)
		local a = n and hotbar.ACTIONS[n]
		if not a or nhv.ui.open or not nh.ready() then
			return true
		end
		flash_slot(n + 2)
		local keys = {}
		for c in a[2]:gmatch(".") do
			keys[#keys + 1] = {key = c}
		end
		nhv.actions.run({label = a[1], keys = keys}, {kind = "hotkey"})
		return true
	end,
})

-- ---------------------------------------------------------------- command line
nhv.ui.chat_open = false
core.register_chatcommand("nhvchat", {
	description = "(NetHack Voxel) chat prompt opened/closed",
	func = function(_, param)
		nhv.ui.chat_open = param == "open"
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
