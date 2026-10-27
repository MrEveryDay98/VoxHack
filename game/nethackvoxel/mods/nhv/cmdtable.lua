-- Every command a player uses, in groups: the wheel's "More..." rings
-- (wheel.lua) and the command finder (F3: commands.lua) both come from
-- this one table.
--
-- An entry is an action as actions.run takes it ({label, keys, free,
-- answers} or {label, func}) plus:
--   cmd   NetHack's name for it (its description in the finder comes from
--         NetHack's own command table, nhcommands.lua)
--   what  a description, for the ones that aren't NetHack commands
-- Directions a command asks for are where you look, and places on the map
-- are picked on the big map, as everywhere else (ui.lua).

local cmdtable = {}
nhv.cmdtable = cmdtable

local function ext(name, ...)
	local k = {{key = "#"}, {text = name}}
	for _, extra in ipairs({...}) do
		k[#k + 1] = extra
	end
	return k
end

local function c(label, keys, cmd)
	return {label = label, keys = keys, cmd = cmd}
end

-- (takes no game time: shows something)
local function info(label, keys, cmd)
	return {label = label, keys = keys, cmd = cmd, free = true}
end

-- (not a NetHack command: one of VoxHack's own screens)
local function fn(label, what, func)
	return {label = label, what = what, func = func}
end

cmdtable.GROUPS = {
	{name = "Items", list = {
		c("Eat", "e", "eat"), c("Quaff", "q", "quaff"), c("Read", "r", "read"),
		c("Apply", "a", "apply"), c("Zap", "z", "zap"), c("Throw", "t", "throw"),
		c("Fire", "f", "fire"), c("Quiver", "Q", "quiver"),
		-- (D's first question, which kinds, answered "All types")
		{label = "Drop", keys = "D", cmd = "droptype",
			answers = {{pattern = "^Drop what type of items", menu = "a"}}},
		c("Dip", ext("dip"), "dip"), c("Rub", ext("rub"), "rub"), c("Tip out", ext("tip"), "tip"),
	}},
	{name = "Gear", list = {
		c("Wield", "w", "wield"), c("Unwield", "w-"), c("Swap weapons", "x", "swap"),
		c("Dual wield", ext("twoweapon"), "twoweapon"),
		c("Wear", "W", "wear"), c("Take off", "T", "takeoff"), c("Take all off", "A", "takeoffall"),
		c("Put on", "P", "puton"), c("Remove", "R", "remove"), c("Wipe face", ext("wipe"), "wipe"),
		info("Name", ext("call"), "call"), info("Letters", ext("adjust"), "adjust"),
	}},
	{name = "Magic", list = {
		c("Cast", "Z", "cast"), info("Spells", "+", "showspells"), c("Pray", ext("pray"), "pray"),
		c("Offer", ext("offer"), "offer"), c("Turn undead", ext("turn"), "turn"),
		c("Ability", ext("monster"), "monster"), c("Invoke", ext("invoke"), "invoke"),
		c("Teleport", "\20", "teleport"), info("Skills", ext("enhance"), "enhance"),
	}},
	{name = "Move", list = {
		c("Travel", "_", "travel"), c("Travel again", "\31", "retravel"),
		c("Go up", "<", "up"), c("Go down", ">", "down"), c("Jump", ext("jump"), "jump"),
		c("Ride", ext("ride"), "ride"), c("Sit", ext("sit"), "sit"),
		{label = "Kick", cmd = "kick", func = function(player)
			nhv.actions.run({label = "Kick", keys = nhv.actions.kick_keys(player)}, {kind = "wheel"})
		end},
		c("Open", "o", "open"), c("Close", "c", "close"), c("Force lock", ext("force"), "force"),
		c("Untrap", ext("untrap"), "untrap"),
	}},
	{name = "Here", list = {
		c("Pick up", ",", "pickup"), info("Look here", ":", "look"), c("Loot", ext("loot"), "loot"),
		c("Search", "s", "search"), c("Wait", ".", "wait"), c("Rest 20", "20s"),
		c("Engrave", "E", "engrave"), c("Chat", ext("chat"), "chat"), c("Pay", "p", "pay"),
		-- (F takes its direction as a bare key, with no question: where you look)
		{label = "Fight", cmd = "fight", func = function(player)
			local dir = nhv.actions.pointed_dir_key(player, "In what direction?", true)
			nhv.actions.run({label = "Fight", keys = {{key = "F"}, {key = dir}}}, {kind = "wheel"})
		end},
		info("Trap?", "^", "showtrap"),
		info("Name level", ext("annotate"), "annotate"),
	}},
	{name = "Info", list = {
		info("Attributes", "\24", "attributes"), info("Dungeon", "\15", "overview"),
		info("Discoveries", "\\", "known"), info("Equipment", "*", "seeall"),
		info("Messages", "\16", "prevmsg"), info("Chronicle", "v", "chronicle"),
		info("Conduct", ext("conduct"), "conduct"), info("Vanquished", ext("vanquished"), "vanquished"),
		info("Genocided", ext("genocided"), "genocided"), info("What is", "/", "whatis"),
		info("Look around", ext("lookaround"), "lookaround"), info("Gold", "$", "showgold"),
	}},
	{name = "Game", list = {
		fn("Map", "show or hide the big map (Z)", function()
			nhv.hud.toggle_map()
		end),
		fn("Wiki", "NetHackWiki, on what you look at (F2)", function(player)
			nhv.wiki.toggle(player)
		end),
		fn("Help", "VoxHack's keys and how to play", function(player)
			nhv.help.show(player)
		end),
		fn("Achievements", "the achievements you've earned", function(player)
			nhv.achievements.show(player)
		end),
		fn("NH options", "NetHack's options", function(player)
			nhv.nhopts.show(player)
		end),
		info("Autopickup", "@", "autopickup"), info("Repeat", "\1", "repeat"),
		c("Save & quit", "S", "save"), c("Quit", ext("quit"), "quit"),
	}},
}

-- NetHack's commands that aren't in a group, or make no sense here (the
-- inventory and help are VoxHack's own; prefixes, the terminal's display)
local LEFT_OUT = {}
for _, n in ipairs({"?", "reqmenu", "run", "rush", "perminv", "redraw", "herecmdmenu",
		"therecmdmenu", "terrain", "glance", "help", "inventory", "inventtype", "options",
		"optionsfull", "saveoptions", "whatdoes", "drop", "kick"}) do
	LEFT_OUT[n] = true
end

-- description by NetHack command name
local DESC = {}
for _, row in ipairs(nhv.commands.LIST) do
	DESC[row[1]] = row[3]:sub(1, 1):upper() .. row[3]:sub(2)
end

-- every command, for the finder: {action, group name, description}; the
-- groups' first, then the rest of NetHack's (as #name)
function cmdtable.all()
	if cmdtable.ALL then
		return cmdtable.ALL
	end
	local all, seen = {}, {}
	for _, g in ipairs(cmdtable.GROUPS) do
		for _, a in ipairs(g.list) do
			all[#all + 1] = {a = a, group = g.name, what = a.what or (a.cmd and DESC[a.cmd]) or ""}
			if a.cmd then
				seen[a.cmd] = true
			end
		end
	end
	for _, row in ipairs(nhv.commands.LIST) do
		local name = row[1]
		if not seen[name] and not LEFT_OUT[name] then
			all[#all + 1] = {a = c("#" .. name, ext(name), name), group = "Other", what = DESC[name]}
		end
	end
	cmdtable.ALL = all
	return all
end

-- the wheel's rings: the groups, each opening its commands
function cmdtable.group_ring()
	local ring = {}
	for _, g in ipairs(cmdtable.GROUPS) do
		ring[#ring + 1] = {label = g.name .. " >", sub = g.list}
	end
	return ring
end

cmdtable.MORE = {label = "More...", sub = "groups"}

return cmdtable
