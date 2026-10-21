-- NetHack's commands (F3, "/nhvcommands"): every command a player can use,
-- in one scrollable page, with NetHack's own short descriptions and keys
-- (nhcommands.lua, made from NetHack's command table). Any of them can be
-- typed in the command line (T): #name, or its key. F3 again or Esc closes
-- it.

local commands = {}
nhv.commands = commands

local FORM = "nhv:commands"
local GOLD, KEY, DIM = "#FFD25A", "#FFD080", "#A3A3AD"
local NAME_W, KEY_W = 15, 7 -- (column widths, in characters)

commands.LIST = dofile(core.get_modpath("nhv") .. DIR_DELIM .. "nhcommands.lua")

local function esc(s)
	return (s:gsub("[\\<>]", "\\%0"))
end

function commands.formspec()
	local E = core.formspec_escape
	local lines = {("<global margin=12 color=#E8E6DF><tag name=k color=%s>"):format(KEY),
		("<style color=%s>Type any of these in the command line (T): #name, or its key. "
			.. "(M- keys are Alt + the key in NetHack; type #name for those.)</style>"):format(DIM),
		""}
	for _, c in ipairs(commands.LIST) do
		local name, key, what = "#" .. c[1], c[2], c[3]
		-- (the name and key in padded columns, NetHack's description after)
		lines[#lines + 1] = ("<mono><k>%s</k>%s%s%s</mono>%s"):format(esc(name),
			(" "):rep(math.max(1, NAME_W - #name)), esc(key), (" "):rep(math.max(1, KEY_W - #key)),
			esc(what:sub(1, 1):upper() .. what:sub(2)))
	end
	return nhv.theme.head(18, 12)
		.. ("label[0.5,0.6;%s]"):format(nhv.theme.title(E("NetHack's commands")))
		.. ("hypertext[0.3,1.1;17.4,9.9;commands;%s]"):format(E(table.concat(lines, "\n")))
		.. "button_exit[7.5,11.1;3,0.8;close;Close]"
end

function commands.show(player)
	commands.open = true
	nhv.player.freeze(true)
	core.show_formspec(player:get_player_name(), FORM, commands.formspec())
end

-- F3: open it (F3 again closes it: the engine does that while it's open)
function commands.toggle(player)
	-- (the F3 that just closed it reaches the game too: not again)
	if commands.closed_at and core.get_us_time() - commands.closed_at < 400000 then
		return
	end
	commands.show(player)
end

core.register_on_player_receive_fields(function(_, formname, fields)
	if formname ~= FORM then
		return false
	end
	if fields.quit or fields.close then
		commands.open = false
		commands.closed_at = core.get_us_time()
		if not (nhv.ui and nhv.ui.open) then
			nhv.player.freeze(false)
		end
	end
	return true
end)

core.register_chatcommand("nhvcommands", {
	description = "(VoxHack) NetHack's commands, explained (F3)",
	func = function(pname)
		local player = core.get_player_by_name(pname)
		if player then
			commands.show(player)
		end
		return true
	end,
})

return commands
