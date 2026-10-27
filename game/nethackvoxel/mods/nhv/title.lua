-- Title screen: shown when the game opens (and after a game ends), before
-- NetHack starts. Continue a saved character, make a new one, open the
-- options, or quit. The logo and background are textures in nhv_tiles
-- (nhv_title_logo.png, nhv_title_bg.png; placeholders for now, made by
-- tools/make_title_placeholders.py).

local nh = nhv.nh
local theme = nhv.theme
local E = core.formspec_escape

local title = {}
nhv.title = title
-- this copy's version: its release tag (bump it for each release - the
-- update check compares it with GitHub's releases, update.lua)
title.TAG = "v0.10.1"
title.VERSION = "VoxHack " .. title.TAG .. " alpha"

local FORM, NEW, CONFIRM = "nhv:title", "nhv:newchar", "nhv:replace"

local function save_dir()
	return core.get_worldpath() .. DIR_DELIM .. "nethack" .. DIR_DELIM
end

-- a world with nhv_debug plays in wizard mode, where NetHack insists on
-- the name "wizard"
local function debug_world()
	local f = io.open(core.get_worldpath() .. DIR_DELIM .. "nhv_debug", "r")
	if f then
		f:close()
		return true
	end
	return false
end

-- is there a saved game (or one in progress) for this name?
local function has_save(name)
	for _, f in ipairs({name .. ".NetHack-saved-game", name .. ".0"}) do
		local h = io.open(save_dir() .. f, "rb")
		if h then
			h:close()
			return true
		end
	end
	return false
end

-- the character Continue would load: the last one played, or any save
function title.saved_character(player)
	local last = core.settings:get("nhv_last_character")
	if debug_world() then
		return has_save("wizard") and "wizard" or nil
	end
	for _, n in ipairs({last or "", player:get_player_name()}) do
		if n ~= "" and has_save(n) then
			return n
		end
	end
	for _, f in ipairs(core.get_dir_list(save_dir(), false) or {}) do
		local n = f:match("^(.+)%.NetHack%-saved%-game$")
		if n then
			return n
		end
	end
	return nil
end

local function delete_save(name)
	for _, f in ipairs(core.get_dir_list(save_dir(), false) or {}) do
		if f == name .. ".NetHack-saved-game" or f:match("^" .. name:gsub("%p", "%%%0") .. "%.%d+$") then
			os.remove(save_dir() .. f)
		end
	end
end

local function start(player, name)
	core.settings:set("nhv_last_character", name)
	core.settings:write()
	-- (whichever screen it was started from: the title, the new character
	-- form or the replace question; only one with the right name closes)
	core.close_formspec(player:get_player_name(), "")
	title.open = false
	nhv.guide.first_run() -- (the guide, the very first time)
	nhv.new_game(player, name)
end

-- Quit in the pause menu (the VoxHack build of Luanti sends
-- "/nhvtitle"): save the game and go back to the title screen
core.register_chatcommand("nhvtitle", {
	description = "(VoxHack) save and go back to the title screen",
	func = function(pname)
		local player = core.get_player_by_name(pname)
		if not player then
			return true
		end
		if nhv.ui.open then
			core.close_formspec(pname, "")
			nhv.ui.open = nil
		end
		nhv.ui.to_title = true
		if not nhv.nh.save_game() then
			-- (no game running: just the title)
			nhv.ui.to_title = false
			title.show(player)
		end
		return true
	end,
})

-- ---------------------------------------------------------------- screens
local function screen(w, h)
	-- (full screen: the background covers the waiting world)
	return ("formspec_version[6]size[%s,%s]no_prepend[]"):format(w, h)
		.. "bgcolor[#000000FF;both;#000000FF]"
		.. "background[0,0;" .. w .. "," .. h .. ";nhv_title_bg.png;true]"
		.. theme.styles():gsub("bgcolor%[[^%]]*%]", ""):gsub("background9%[[^%]]*%]", "")
end

function title.formspec(player)
	local saved = title.saved_character(player)
	local fs = {screen(16, 10),
		"image[3,0.6;10,2.5;nhv_title_logo.png]"}
	-- (five buttons fit above the update notice)
	local y = 3.8
	local function button(name, label)
		fs[#fs + 1] = ("button[5.5,%s;5,0.9;%s;%s]"):format(y, name, E(label))
		y = y + 1.0
	end
	if saved then
		button("continue", "Continue (" .. saved .. ")")
	end
	button("new", "New game")
	button("options", "Options")
	button("achievements", "Achievements")
	button("quitgame", "Quit")
	fs[#fs + 1] = "label[0.4,9.6;" .. theme.dim(E(title.VERSION .. " - based on NetHack 3.7")) .. "]"
	-- a newer release out (update.lua): say so, with a link to get it
	local upd = nhv.update and nhv.update.available
	if upd then
		fs[#fs + 1] = ("hypertext[0.4,8.75;15.2,0.75;update;%s]"):format(E(
			("<global valign=middle color=#FFD25A><tag name=action color=#78C8FF hovercolor=#FFFFFF>"
			.. "A new version is available: <b>%s</b>   "
			.. "<action name=get url=%s>Download it from GitHub</action>"):format(upd.tag, upd.url)))
	end
	return table.concat(fs)
end

function title.show(player)
	title.open = true
	if nhv.update then
		nhv.update.check() -- (once a session)
	end
	nhv.player.freeze(true)
	core.show_formspec(player:get_player_name(), FORM, title.formspec(player))
end

-- character creation: what's chosen is stored as the NetHack options
-- (the pause menu > NetHack Options shows the same)
local CREATE = {"role", "race", "gender", "align", "pettype"}

-- NetHack's allowed combinations (role.c): each role's races, genders and
-- alignments; each race's alignments. A choice is offered only if it fits
-- the ones above it (the role; for alignment, the race too). "Ask" and
-- "Random" always are: NetHack then picks something that fits.
local function set(...)
	local t = {}
	for _, v in ipairs({...}) do
		t[v] = true
	end
	return t
end
local BOTH = set("male", "female")
local ROLES = {
	archeologist = {race = set("human", "dwarf", "gnome"), gender = BOTH, align = set("lawful", "neutral")},
	barbarian = {race = set("human", "orc"), gender = BOTH, align = set("neutral", "chaotic")},
	caveman = {race = set("human", "dwarf", "gnome"), gender = BOTH, align = set("lawful", "neutral")},
	healer = {race = set("human", "gnome"), gender = BOTH, align = set("neutral")},
	knight = {race = set("human"), gender = BOTH, align = set("lawful")},
	monk = {race = set("human"), gender = BOTH, align = set("lawful", "neutral", "chaotic")},
	priest = {race = set("human", "elf"), gender = BOTH, align = set("lawful", "neutral", "chaotic")},
	rogue = {race = set("human", "orc"), gender = BOTH, align = set("chaotic")},
	ranger = {race = set("human", "elf", "gnome", "orc"), gender = BOTH, align = set("neutral", "chaotic")},
	samurai = {race = set("human"), gender = BOTH, align = set("lawful")},
	tourist = {race = set("human"), gender = BOTH, align = set("neutral")},
	valkyrie = {race = set("human", "dwarf"), gender = set("female"), align = set("lawful", "neutral")},
	wizard = {race = set("human", "elf", "gnome", "orc"), gender = BOTH, align = set("neutral", "chaotic")},
}
-- roles that always start with the same pet (NetHack ignores the choice
-- of kitten or dog for them; no pet still works)
local ROLE_PET = {knight = "pony", samurai = "little dog", caveman = "little dog",
	ranger = "little dog", wizard = "kitten"}

local RACE_ALIGN = {
	human = set("lawful", "neutral", "chaotic"), elf = set("chaotic"), dwarf = set("lawful"),
	gnome = set("neutral"), orc = set("chaotic"),
}

-- may key k be v, given what's chosen above it?
local function allowed(k, v, get)
	if v == "" or v == "random" then
		return true
	end
	local role = ROLES[get("role")]
	if k == "race" or k == "gender" then
		return not role or role[k][v] == true
	elseif k == "align" then
		local race = RACE_ALIGN[get("race")]
		return (not role or role.align[v] == true) and (not race or race[v] == true)
	elseif k == "pettype" then
		return not ROLE_PET[get("role")] or v == "none"
	end
	return true
end

-- the choices still allowed for key k (in order)
local function allowed_choices(k, get)
	local out = {}
	for _, c in ipairs(nhv.nhopts.BY_KEY[k].choices) do
		if allowed(k, c[1], get) then
			out[#out + 1] = c
		end
	end
	return out
end

-- after the role or race changed: anything below that no longer fits
-- becomes Random
local function fix_choices(o)
	for _, k in ipairs({"race", "gender", "align"}) do
		if not allowed(k, o.get(k), o.get) then
			o.set(k, "random")
		end
	end
	if not allowed("pettype", o.get("pettype"), o.get) or o.get("pettype") == "horse" then
		o.set("pettype", "")
	end
end

local function newchar_formspec(player)
	local o = nhv.nhopts
	local name = o.get("name")
	if name == "" then
		name = player:get_player_name()
	end
	local fs = {screen(16, 10),
		"label[4,0.8;" .. theme.title("New character") .. "]"}
	local y = 1.4
	if debug_world() then
		fs[#fs + 1] = ("label[4,%s;%s]"):format(y + 0.4, E("Name: wizard (debug mode needs it)"))
	else
		fs[#fs + 1] = ("label[4,%s;Name]field[8,%s;4,0.8;name;;%s]field_close_on_enter[name;false]"):format(y + 0.4, y, E(name))
	end
	y = y + 1
	fix_choices(o)
	for _, k in ipairs(CREATE) do
		local opt = o.BY_KEY[k]
		local labels, sel = {}, 1
		for i, c in ipairs(allowed_choices(k, o.get)) do
			labels[i] = E(c[2])
			if k == "pettype" and c[1] == "" and ROLE_PET[o.get("role")] then
				labels[i] = E("Usual: " .. ROLE_PET[o.get("role")])
			end
			if c[1] == o.get(k) then
				sel = i
			end
		end
		fs[#fs + 1] = ("label[4,%s;%s]dropdown[8,%s;4,0.8;%s;%s;%d;true]"):format(
			y + 0.4, E(opt.label), y, k, table.concat(labels, ","), sel)
		y = y + 1
	end
	local pet = o.get("dogname")
	fs[#fs + 1] = ("label[4,%s;Pet's name]field[8,%s;4,0.8;petname;;%s]field_close_on_enter[petname;false]"):format(y + 0.4, y, E(pet))
	fs[#fs + 1] = ("tooltip[petname;%s]"):format(E("Blank: NetHack's usual name. Used whatever kind of pet you get."))
	y = y + 1.4
	fs[#fs + 1] = ("button[4,%s;3.8,0.9;begin;Start]button[8.2,%s;3.8,0.9;back;Back]"):format(y, y)
	return table.concat(fs)
end

local function confirm_formspec(name)
	return screen(16, 10)
		.. "label[3,4;" .. E(("There's a saved game for %s. Starting a new %s replaces it."):format(name, name)) .. "]"
		.. "button[3,5.2;4.8,0.9;replace;Replace it]button[8.2,5.2;4.8,0.9;back;Back]"
end

local pending -- name waiting for the replace confirmation

core.register_on_player_receive_fields(function(player, formname, fields)
	local pname = player:get_player_name()
	if formname == FORM then
		if fields.continue then
			start(player, title.saved_character(player))
		elseif fields.new then
			core.show_formspec(pname, NEW, newchar_formspec(player))
		elseif fields.options then
			title.from_title = true
			nhv.graphics.show(player)
		elseif fields.achievements then
			nhv.achievements.show(player)
		elseif fields.quitgame then
			core.disconnect_player(pname, "nhv:quit")
		elseif fields.quit then
			title.show(player) -- (Esc: the title stays)
		end
		return true
	elseif formname == NEW then
		local o = nhv.nhopts
		-- (each dropdown's number counts the choices it showed: the allowed
		-- ones, worked out top-down as they were shown)
		local before = {}
		for _, k in ipairs(CREATE) do
			before[k] = o.get(k)
		end
		local function shown(k)
			return before[k]
		end
		for _, k in ipairs(CREATE) do
			local c = allowed_choices(k, shown)[tonumber(fields[k] or "") or 0]
			if c then
				o.set(k, c[1])
			end
		end
		fix_choices(o)
		if fields.petname then
			local pet = o.clean_name(fields.petname)
			o.set("dogname", pet)
			o.set("catname", pet)
			o.set("horsename", pet)
		end
		local name = debug_world() and "wizard" or o.clean_name(fields.name or "")
		if name == "" then
			name = pname
		end
		if not debug_world() then
			o.set("name", name)
		end
		core.settings:write()
		if fields.begin then
			if has_save(name) then
				pending = name
				core.show_formspec(pname, CONFIRM, confirm_formspec(name))
			else
				start(player, name)
			end
		elseif fields.back or fields.quit then
			title.show(player)
		elseif o.get("role") ~= before.role or o.get("race") ~= before.race then
			-- (a new role or race: the choices below it change)
			core.show_formspec(pname, NEW, newchar_formspec(player))
		end
		return true
	elseif formname == CONFIRM then
		if fields.replace and pending then
			delete_save(pending)
			start(player, pending)
		else
			core.show_formspec(pname, NEW, newchar_formspec(player))
		end
		pending = nil
		return true
	end
	return false
end)

return title
