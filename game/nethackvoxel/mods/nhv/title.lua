-- Title screen: shown when the game opens (and after a game ends), before
-- NetHack starts. Continue a saved character, make a new one, open the
-- options, or quit. The logo is a texture in nhv_tiles (nhv_title_logo.png,
-- made by tools/make_title_placeholders.py); behind it all, the Astral
-- Plane's sky (showroom.lua).

local nh = nhv.nh
local theme = nhv.theme
local E = core.formspec_escape

local title = {}
nhv.title = title
-- this copy's version: its release tag (bump it for each release - the
-- update check compares it with GitHub's releases, update.lua)
title.TAG = "v0.12.0"
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

-- intro: a new character - the story told first (intro.lua)
local function start(player, name, intro)
	core.settings:set("nhv_last_character", name)
	core.settings:write()
	-- (whichever screen it was started from: the title, the new character
	-- form or the replace question; only one with the right name closes)
	core.close_formspec(player:get_player_name(), "")
	if intro then
		nhv.intro.start(player) -- (its own screen: "Press Enter to skip")
	else
		nhv.showroom.hide(player)
	end
	title.open, title.from_title = false, false
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
			title.show(player, true)
		end
		return true
	end,
})

-- ---------------------------------------------------------------- screens
-- see-through: a scene shows behind it (showroom.lua)
local function scene_screen(w, h)
	return ("formspec_version[6]size[%s,%s]no_prepend[]"):format(w, h)
		.. "bgcolor[#00000000;false]"
		.. theme.styles():gsub("bgcolor%[[^%]]*%]", ""):gsub("background9%[[^%]]*%]", "")
end

function title.formspec(player, black)
	local saved = title.saved_character(player)
	-- (see-through: the Astral sky behind it - showroom.lua; Esc doesn't
	-- close it - it would be gone a moment, the camera free)
	-- (fading in: the world under the HUD's fade, and the menu's own parts
	-- see-through - the logo, the buttons - no box over it all)
	local fading = black and black > 0
	local op = fading and math.floor((1 - black) * 255 + 0.5) or 255
	local hex = ("%02X"):format(op)
	local fs = {scene_screen(16, 10), "allow_close[false]",
		"image[3,0.6;10,2.5;nhv_title_logo.png" .. (fading and ("^[opacity:" .. op) or "") .. "]"}
	if fading then
		if theme.retro() then
			fs[#fs + 1] = ("style_type[button;border=false;bgimg=nhv_ui_button.png^[opacity:%d;"
				.. "bgimg_hovered=nhv_ui_button_hover.png^[opacity:%d;"
				.. "bgimg_pressed=nhv_ui_button_pressed.png^[opacity:%d;bgimg_middle=2;textcolor=#FFFFFF%s]")
				:format(op, op, op, hex)
		else
			fs[#fs + 1] = ("style_type[button;bgcolor=#303040%s;textcolor=#FFFFFF%s]"):format(hex, hex)
		end
	end
	-- (five buttons fit above the update notice; six closer together)
	local prologue = nhv.intro_play and nhv.intro_play.available()
	local six = saved and prologue
	local y, step, h = six and 3.4 or 3.8, six and 0.9 or 1.0, six and 0.8 or 0.9
	local function button(name, label)
		fs[#fs + 1] = ("button[5.5,%s;5,%s;%s;%s]"):format(y, h, name, E(label))
		y = y + step
	end
	if saved then
		button("continue", "Continue (" .. saved .. ")")
	end
	button("new", "New game")
	if prologue then
		button("prologue", "Prologue")
	end
	button("options", "Options")
	button("achievements", "Achievements")
	button("quitgame", "Quit")
	-- (the version and the update notice: once it's in)
	if fading then
		return table.concat(fs)
	end
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

-- the title screen coming in from black (the game starting, the opening
-- over)
function title.enter(player)
	-- (the title's backdrop: no hand, weapon or HUD showing before the
	-- title screen comes)
	nhv.showroom.title(player)
	core.after(0.5, function()
		if player:is_player() then
			title.show(player, true)
		end
	end)
end

-- the opening again (the Prologue button): out of the title's backdrop
-- (it holds you there - the opening takes you round its forest), the
-- screen and the music going, then back to the title
function title.prologue(player)
	title.open, title.fade_t0 = false, nil
	core.close_formspec(player:get_player_name(), FORM)
	nhv.showroom.hide(player)
	player:hud_set_flags({wielditem = false, crosshair = false, nhv_camera_lock = true})
	nhv.hud.fade(1, 0.6)
	if nhv.sound then
		nhv.sound.stop_music()
	end
	nhv.intro_play.start_game(player, title.enter)
end

-- Options or Achievements closed: back to the title screen if that's where
-- they were opened from (true), not if they were opened in the game
function title.back_from(player)
	if title.from_title then
		title.from_title = false
		title.show(player)
		return true
	end
	return false
end

-- (fade: coming in from black - the game opening, back from a game - the
-- world under it with the HUD's fade, the menu's own parts coming
-- through step by step)
local FADE_S, FADE_STEPS = 1.2, 12

function title.show(player, fade)
	title.open, title.from_title = true, false
	if fade then
		nhv.hud.fade(1, 0)
		nhv.hud.fade(0, FADE_S)
		title.fade_t0, title.fade_step = core.get_us_time(), nil
	end
	nhv.showroom.title(player) -- (the Astral sky behind it)
	if nhv.sound then
		nhv.sound.set_music("music_title") -- (back from a game too)
	end
	if nhv.update then
		nhv.update.check() -- (once a session)
	end
	nhv.player.freeze(true)
	core.show_formspec(player:get_player_name(), FORM, title.formspec(player, fade and 1 or nil))
end

-- the menu coming in from black, a step at a time (closed meanwhile - a
-- button pressed: done)
core.register_globalstep(function()
	if not title.fade_t0 then
		return
	end
	local player = nhv.player.get()
	if not (player and title.open) then
		title.fade_t0 = nil
		return
	end
	local k = (core.get_us_time() - title.fade_t0) / 1e6 / FADE_S
	local step = math.min(FADE_STEPS, math.floor(k * FADE_STEPS))
	if step ~= title.fade_step then
		title.fade_step = step
		core.show_formspec(player:get_player_name(), FORM,
			title.formspec(player, step < FADE_STEPS and 1 - step / FADE_STEPS or nil))
		if step >= FADE_STEPS then
			title.fade_t0 = nil
		end
	end
end)

-- character creation: what's chosen is stored as the NetHack options
-- (the pause menu > NetHack Options shows the same)
local CREATE = {"role", "race", "gender", "align", "pettype"}

-- NetHack's allowed combinations (role.c): each role's races, genders and
-- alignments; each race's alignments. A choice is offered only if it fits
-- the ones above it (the role; for alignment, the race too).
-- "Random" always is: NetHack then picks something that fits.
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
	-- (see-through: the scene shows behind it, the form on the right -
	-- showroom.lua)
	local fs = {scene_screen(16, 10),
		"label[8.4,0.8;" .. theme.title("New character") .. "]"}
	local y = 1.4
	if debug_world() then
		fs[#fs + 1] = ("label[8.4,%s;%s]"):format(y + 0.4, E("Name: wizard (debug mode needs it)"))
	else
		fs[#fs + 1] = ("label[8.4,%s;Name]field[11.6,%s;4,0.8;name;;%s]field_close_on_enter[name;false]"):format(y + 0.4, y, E(name))
	end
	y = y + 1
	fix_choices(o)
	-- each choice:  Role   < Knight >  (the arrows go round the allowed ones)
	for _, k in ipairs(CREATE) do
		local opt = o.BY_KEY[k]
		local shown = o.get(k)
		for _, c in ipairs(allowed_choices(k, o.get)) do
			if c[1] == o.get(k) then
				shown = c[2]
				if k == "pettype" and c[1] == "" and ROLE_PET[o.get("role")] then
					shown = "Usual: " .. ROLE_PET[o.get("role")]
				end
			end
		end
		fs[#fs + 1] = ("label[8.4,%s;%s]button[11.6,%s;0.8,0.8;%s_prev;<]"
			.. "hypertext[12.4,%s;2.4,0.8;%s_shown;%s]button[14.8,%s;0.8,0.8;%s_next;>]"):format(
			y + 0.4, E(opt.label), y, k,
			y, k, E("<global halign=center valign=middle color=#FFFFFF>" .. shown),
			y, k)
		y = y + 1
	end
	local pet = o.get("dogname")
	fs[#fs + 1] = ("label[8.4,%s;Pet's name]field[11.6,%s;4,0.8;petname;;%s]field_close_on_enter[petname;false]"):format(y + 0.4, y, E(pet))
	fs[#fs + 1] = ("tooltip[petname;%s]"):format(E("Blank: NetHack's usual name. Used whatever kind of pet you get."))
	y = y + 1.4
	fs[#fs + 1] = ("button[8.4,%s;3.5,0.9;begin;Start]button[12.1,%s;3.5,0.9;back;Back]"):format(y, y)
	return table.concat(fs)
end

-- the new character form, with its scene behind it
local function show_new(player)
	core.show_formspec(player:get_player_name(), NEW, newchar_formspec(player))
	nhv.showroom.show(player)
end

-- (where the new character form was: the scene still beside it)
local function confirm_formspec(name)
	return scene_screen(16, 10)
		.. "label[8.4,0.8;" .. theme.title("Replace your saved game?") .. "]"
		.. ("hypertext[8.4,1.6;7.2,2.4;msg;%s]"):format(E("<global color=#AAAAAA>"
			.. ("There's a saved game for <style color=#FFFFFF>%s</style>. Starting a new %s"
			.. " replaces it."):format(name, name)))
		.. "button[8.4,4.2;3.5,0.9;replace;Replace it]button[12.1,4.2;3.5,0.9;back;Back]"
end

local pending -- name waiting for the replace confirmation

core.register_on_player_receive_fields(function(player, formname, fields)
	local pname = player:get_player_name()
	if formname == FORM then
		-- (left before it had faded in: no more of it shown over what's next)
		if not fields.quit then
			title.fade_t0 = nil
		end
		if fields.continue then
			start(player, title.saved_character(player))
		elseif fields.new then
			show_new(player)
		elseif fields.prologue then
			title.prologue(player)
		elseif fields.options then
			title.from_title = true
			nhv.graphics.show(player)
		elseif fields.achievements then
			title.from_title = true
			nhv.achievements.show(player)
		elseif fields.quitgame then
			core.disconnect_player(pname, "nhv:quit")
		elseif fields.quit then
			title.show(player) -- (Esc: the title stays)
		end
		return true
	elseif formname == NEW then
		local o = nhv.nhopts
		-- (an arrow: the next or the one before among the allowed choices,
		-- round and round)
		local changed = false
		for _, k in ipairs(CREATE) do
			local step = fields[k .. "_next"] and 1 or fields[k .. "_prev"] and -1
			if step then
				local list = allowed_choices(k, o.get)
				local at = 1
				for i, c in ipairs(list) do
					if c[1] == o.get(k) then
						at = i
					end
				end
				if #list > 0 then
					o.set(k, list[(at - 1 + step) % #list + 1][1])
					changed = true
				end
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
				start(player, name, true)
			end
		elseif fields.back or fields.quit then
			title.show(player)
		elseif changed then
			show_new(player) -- (the form showing it, and the scene)
		end
		return true
	elseif formname == CONFIRM then
		if fields.replace and pending then
			delete_save(pending)
			start(player, pending, true)
		else
			show_new(player)
		end
		pending = nil
		return true
	end
	return false
end)

return title
