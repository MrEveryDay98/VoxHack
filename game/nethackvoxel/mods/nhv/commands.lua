-- The command finder (F3, "/nhvcommands"): every command a player can use
-- (cmdtable.lua's groups, then the rest of NetHack's), with NetHack's own
-- short descriptions. Type to narrow the list - by name, group or what it
-- does - and Enter does the first one (or the one picked in the list);
-- double-clicking one does it too. F3 again or Esc closes it.

local commands = {}
nhv.commands = commands

local FORM = "nhv:commands"
local GOLD, DIM, TEXT = "#FFD25A", "#A3A3AD", "#E8E6DF"

commands.LIST = dofile(core.get_modpath("nhv") .. DIR_DELIM .. "nhcommands.lua")

local query, shown, picked = "", {}, 1

-- (how well a command matches: its name first, then its group and what it
-- does; nil: not at all)
local function score(e, q)
	if q == "" then
		return 0
	end
	local label = e.a.label:lower()
	if label:sub(1, #q) == q then
		return 0
	elseif label:find(q, 1, true) then
		return 1
	elseif e.a.cmd and e.a.cmd:find(q, 1, true) then
		return 2
	elseif e.group:lower():sub(1, #q) == q then
		return 3
	elseif e.what:lower():find(q, 1, true) then
		return 4
	end
end

local function filter()
	local q = query:lower():gsub("^%s+", ""):gsub("%s+$", ""):gsub("^#", "")
	local hits = {}
	for i, e in ipairs(nhv.cmdtable.all()) do
		local s = score(e, q)
		if s then
			hits[#hits + 1] = {e = e, s = s, i = i}
		end
	end
	-- (the best matches first; otherwise in the table's order)
	table.sort(hits, function(a, b)
		if a.s ~= b.s then
			return a.s < b.s
		end
		return a.i < b.i
	end)
	shown = {}
	for _, h in ipairs(hits) do
		shown[#shown + 1] = h.e
	end
	picked = math.max(1, math.min(picked, #shown))
end

function commands.formspec()
	local E = core.formspec_escape
	local cells = {}
	for _, e in ipairs(shown) do
		cells[#cells + 1] = table.concat({GOLD, E(e.a.label), DIM, E(e.group), TEXT, E(e.what)}, ",")
	end
	return nhv.theme.head(18, 12)
		.. ("label[0.5,0.6;%s]"):format(nhv.theme.title(E("Commands")))
		.. ("label[6,0.6;%s]"):format(nhv.theme.dim(E("Type to find one.  Enter or double-click: do it.")))
		.. ("field[0.5,1.1;8,0.8;q;;%s]"):format(E(query))
		.. "field_enter_after_edit[q;true]field_close_on_enter[q;false]set_focus[q;true]"
		.. "tablecolumns[color;text,width=10;color;text,width=5;color;text]"
		.. ("table[0.5,2.1;17,8.8;list;%s;%d]"):format(table.concat(cells, ","), #shown > 0 and picked or 0)
		.. "button[0.5,11.1;4,0.8;run;Do it]"
		.. "button_exit[13.5,11.1;4,0.8;close;Close]"
end

function commands.show(player)
	commands.open = true
	nhv.player.freeze(true)
	filter()
	core.show_formspec(player:get_player_name(), FORM, commands.formspec())
end

-- F3: open it (F3 again closes it: the engine does that while it's open)
function commands.toggle(player)
	-- (the F3 that just closed it reaches the game too: not again)
	if commands.closed_at and core.get_us_time() - commands.closed_at < 400000 then
		return
	end
	query, picked = "", 1
	commands.show(player)
end

local function closed()
	commands.open = false
	commands.closed_at = core.get_us_time()
	if not (nhv.ui and nhv.ui.open) then
		nhv.player.freeze(false)
	end
end

-- do the picked one (once the finder has closed)
local function run(player)
	local e = shown[picked]
	core.close_formspec(player:get_player_name(), FORM)
	closed()
	if e and nhv.nh.ready() then
		core.after(0, function()
			nhv.actions.run(e.a, {kind = "wheel"})
		end)
	end
end

core.register_on_player_receive_fields(function(player, formname, fields)
	if formname ~= FORM then
		return false
	end
	if fields.quit or fields.close then
		closed()
		return true
	end
	local ev = fields.list and core.explode_table_event(fields.list)
	if ev and ev.row > 0 then
		picked = ev.row
		if ev.type == "DCL" then
			run(player)
		end
		return true
	end
	if fields.run then
		run(player)
		return true
	end
	if fields.q and fields.q ~= query then
		-- typing: the list narrows (the best match picked)
		query, picked = fields.q, 1
		filter()
		core.show_formspec(player:get_player_name(), FORM, commands.formspec())
	elseif fields.key_enter_field == "q" then
		run(player)
	end
	return true
end)

core.register_chatcommand("nhvcommands", {
	description = "(VoxHack) find and do any command (F3)",
	func = function(pname)
		local player = core.get_player_by_name(pname)
		if player then
			query, picked = "", 1
			commands.show(player)
		end
		return true
	end,
})

return commands
