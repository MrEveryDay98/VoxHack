-- Help (the pause menu's Help button, "/nhvhelp"): every default key in one
-- scrollable page - moving, fighting, the right click and its wheels, the
-- other keys, and the function keys.

local help = {}
nhv.help = help

local FORM = "nhv:help"
local GOLD, KEY, DIM = "#FFD25A", "#FFD080", "#A3A3AD"
local KEY_W = 21 -- (the key column's width, in characters)

-- {section, {{keys, what}...}}
help.SECTIONS = {
	{"Look anything up: F2", {
		{"F2", "Open NetHackWiki, the NetHack wiki, right in the game, on the page for whatever you're pointing at: a monster, an item, a fountain, a trap... F2 again closes it. Every item's menu has a Wiki button too."},
	}},
	{"Moving and looking", {
		{"W A S D", "Walk"},
		{"Mouse", "Look around"},
		{"Space", "Wait a turn; hold to jump (Knights, jumping boots): the green squares are where you can land - look at one and let go; in a pit, climb out (face its edge)"},
		{"Z", "The big map (Z again closes it)"},
		{"Middle click", "Look at what's under the crosshair (what NetHack calls it)"},
	}},
	{"Fighting", {
		{"Left click", "Attack the monster nearest your crosshair, if it's in reach"},
		{"Shift + left click", "Fire your quivered ammo where the crosshair points"},
		{"1  Fire", "Fire your quivered ammo"},
		{"2  Kick", "Kick what's in front of you"},
		{"3  Zap", "Zap a wand (look steeply down or up to zap down or up)"},
		{"4  Spell", "Cast a spell (Cast, Self, or Target: then left click to cast it)"},
		{"5  Eat", "Eat something"},
	}},
	{"Right click and the action wheels", {
		{"Right click (tap)", "The obvious action for what you point at: open or close a door, take the stairs, talk, open a box..."},
		{"Right click (hold)", "A wheel of actions for what you point at: move the mouse toward one and let go (let go in the middle to cancel)"},
		{"Shift + right click", "Tap: nothing. Hold: actions on yourself (pray, rest, sit, engrave, loot, jump, look here...)"},
		{"Alt + right click", "Hold: use an item (quaff, read, apply, drop, throw, wear, take off, put on, wield, swap weapons, dual wield)"},
		{"Ctrl + right click", "Hold: magic and abilities (turn undead, monster abilities, invoke, skills, known spells, teleport)"},
		{"E (tap / hold)", "The same for your wielded weapon: its usual action, or a wheel of what you can do with it"},
	}},
	{"Items and other keys", {
		{"F", "Pick up what's under you (shown as \"F  Pick up\" when something is; a right click tap does it too, when nothing else is there)"},
		{"X", "Search (hold to keep searching; Ctrl + X: search for a number of turns)"},
		{"P", "Pay the shopkeeper, in a shop"},
		{"G", "Advance a skill (shown when you can)"},
		{"I", "Inventory and equipment: click an item for what you can do with it"},
		{"T", "NetHack's command line: any NetHack command (#pray, #loot, #offer, 20s...); it also lists every message so far (Page Up scrolls back)"},
		{"M", "Mute or unmute the sound"},
		{"Esc", "The game menu (and closes any window)"},
	}},
	{"Function keys", {
		{"F1", "Hide or show the HUD (for clean screenshots)"},
		{"F2", "NetHackWiki: the page for what you're pointing at, or the last page you read (F2 again closes it)"},
		{"F3", "NetHack's commands: every one, with what it does (F3 again closes it)"},
		{"F5", "Debug info: position, frame rate..."},
		{"F6", "The profiler (performance graphs)"},
		{"F10", "The console (the message log)"},
		{"F11", "Fullscreen on or off"},
		{"F12", "Take a screenshot (saved in the engine\\screenshots folder)"},
	}},
}

local function esc(s)
	return (s:gsub("[\\<>]", "\\%0"))
end

function help.formspec()
	local E = core.formspec_escape
	local lines = {("<global margin=12 color=#E8E6DF><tag name=k color=%s>"):format(KEY)}
	for _, sec in ipairs(help.SECTIONS) do
		lines[#lines + 1] = ("<big><b><style color=%s>%s</style></b></big>"):format(GOLD, esc(sec[1]))
		for _, row in ipairs(sec[2]) do
			-- (the keys in a padded column, the explanation after them)
			local keys = row[1]
			local pad = (" "):rep(math.max(1, KEY_W - #keys))
			lines[#lines + 1] = ("<mono><k>%s</k>%s</mono>%s"):format(esc(keys), pad, esc(row[2]))
		end
		lines[#lines + 1] = ""
	end
	lines[#lines + 1] = ("<i><style color=%s>These are the default keys.</style></i>")
		:format(DIM)
	return nhv.theme.head(18, 12)
		.. ("label[0.5,0.6;%s]"):format(nhv.theme.title(E("Help: the keys")))
		.. ("hypertext[0.3,1.1;17.4,9.9;help;%s]"):format(E(table.concat(lines, "\n")))
		.. "button_exit[7.5,11.1;3,0.8;close;Close]"
end

function help.show(player)
	help.open = true
	nhv.player.freeze(true)
	core.show_formspec(player:get_player_name(), FORM, help.formspec())
end

core.register_on_player_receive_fields(function(player, formname, fields)
	if formname ~= FORM then
		return false
	end
	if fields.quit or fields.close then
		help.open = false
		if not (nhv.ui and nhv.ui.open) then
			nhv.player.freeze(false)
		end
	end
	return true
end)

core.register_chatcommand("nhvhelp", {
	description = "(VoxHack) the keys, explained (the pause menu's Help)",
	func = function(pname)
		local player = core.get_player_by_name(pname)
		if player then
			help.show(player)
		end
		return true
	end,
})

return help
