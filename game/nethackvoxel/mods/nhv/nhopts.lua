-- NetHack's own options (Options > NetHack options), the ones that still
-- matter here (no display, symbol or keyboard options).
--
-- "New characters" options (name, role..., pet and its name) are read by
-- NetHack when a game starts; a saved game keeps its own. "Any time"
-- options are also applied to the game in progress, with #nhvopt (the
-- same as NetHack's 'O' menu), at the start of every session and when
-- they're changed. Each is stored as the setting nhv_nh_<key>.
--
-- NetHack finds its save by the character's name: a game in progress
-- under the name you're playing keeps loading until it ends, and the
-- name set here is used from the next new character on.

local nh = nhv.nh
local theme = nhv.theme
local E = core.formspec_escape

local nhopts = {}
nhv.nhopts = nhopts

local function list(...)
	local out = {}
	for _, v in ipairs({...}) do
		out[#out + 1] = {v:lower(), v}
	end
	return out
end
local ASK_RANDOM = {{"", "Ask"}, {"random", "Random"}}
local function choices(extra)
	local out = {}
	for _, c in ipairs(ASK_RANDOM) do
		out[#out + 1] = c
	end
	for _, c in ipairs(extra) do
		out[#out + 1] = c
	end
	return out
end

-- kind: text / choice / bool. opt: NetHack option name. new: new characters only.
nhopts.OPTIONS = {
	{key = "name", kind = "text", label = "Character name", new = true, default = "",
		note = "blank: your Windows name"},
	{key = "role", kind = "choice", label = "Role", opt = "role", new = true, default = "",
		choices = choices(list("Archeologist", "Barbarian", "Caveman", "Healer", "Knight", "Monk",
			"Priest", "Ranger", "Rogue", "Samurai", "Tourist", "Valkyrie", "Wizard"))},
	{key = "race", kind = "choice", label = "Race", opt = "race", new = true, default = "",
		choices = choices(list("Human", "Elf", "Dwarf", "Gnome", "Orc"))},
	{key = "gender", kind = "choice", label = "Gender", opt = "gender", new = true, default = "",
		choices = choices(list("Male", "Female"))},
	{key = "align", kind = "choice", label = "Alignment", opt = "align", new = true, default = "",
		choices = choices(list("Lawful", "Neutral", "Chaotic"))},
	{key = "pettype", kind = "choice", label = "Pet", opt = "pettype", new = true, default = "",
		choices = {{"", "Usual for the role"}, {"cat", "Kitten"}, {"dog", "Little dog"},
			{"horse", "Pony"}, {"none", "No pet"}}},
	{key = "dogname", kind = "text", label = "Dog's name", opt = "dogname", new = true, default = ""},
	{key = "catname", kind = "text", label = "Cat's name", opt = "catname", new = true, default = ""},
	{key = "horsename", kind = "text", label = "Horse's name", opt = "horsename", new = true, default = ""},

	{key = "fruit", kind = "text", label = "Favourite fruit", opt = "fruit", default = "slime mold"},
	{key = "autopickup", kind = "bool", label = "Autopickup", opt = "autopickup", default = false},
	{key = "pickup_types", kind = "text", label = "Autopickup kinds", opt = "pickup_types",
		default = "$?!/=\"+", note = "item symbols ($ gold, ? scrolls...); blank: all"},
	{key = "pickup_burden", kind = "choice", label = "Ask before carrying", opt = "pickup_burden",
		default = "u", -- (NetHack goes by these letters: s = stressed, n = strained...)
		choices = {{"u", "Any load"}, {"b", "Burdened"}, {"s", "Stressed"},
			{"n", "Strained"}, {"t", "Overtaxed"}, {"l", "Overloaded"}}},
	{key = "autounlock", kind = "choice", label = "Locked doors / boxes", opt = "autounlock",
		default = "apply-key",
		choices = {{"apply-key", "Use a key if you have one"}, {"untrap+apply-key", "Check for traps, then key"},
			{"kick", "Kick"}, {"force", "Force with weapon"}, {"none", "Nothing"}}},
	{key = "confirm", kind = "bool", label = "Confirm attacking peacefuls", opt = "confirm", default = true},
	{key = "safe_pet", kind = "bool", label = "Don't attack your pet by accident", opt = "safe_pet", default = true},
	{key = "pray", kind = "bool", label = "Confirm before praying", default = true,
		on = "paranoid_confirmation:pray", off = "paranoid_confirmation:none"},
	{key = "autoquiver", kind = "bool", label = "Autoquiver", opt = "autoquiver", default = false},
	{key = "autodig", kind = "bool", label = "Dig by walking into rock (wielded pick)", opt = "autodig", default = false},
	{key = "verbose", kind = "bool", label = "Verbose messages", opt = "verbose", default = false},
}
local BY_KEY = {}
for _, o in ipairs(nhopts.OPTIONS) do
	BY_KEY[o.key] = o
end

function nhopts.get(key)
	local o = BY_KEY[key]
	local v = core.settings:get("nhv_nh_" .. key)
	if o.kind == "bool" then
		if v == nil then
			return o.default
		end
		return core.is_yes(v)
	end
	if v == nil then
		return o.default
	end
	return v
end

local function set(key, v)
	local o = BY_KEY[key]
	if o.kind == "bool" then
		core.settings:set_bool("nhv_nh_" .. key, v)
	else
		core.settings:set("nhv_nh_" .. key, v)
	end
end

-- the NetHack option line for one option (nil = leave NetHack's default)
local function option_text(o)
	local v = nhopts.get(o.key)
	if o.on then
		return v and o.on or o.off
	elseif o.kind == "bool" then
		return (v and "" or "!") .. o.opt
	elseif v == "" then
		return nil -- (NetHack's default; blank kinds = all)
	end
	-- (option values can't hold commas or newlines)
	return o.opt .. ":" .. tostring(v):gsub("[,\n\r]", " ")
end

-- the lines given to NetHack when it starts
function nhopts.start_options()
	local lines = {}
	for _, o in ipairs(nhopts.OPTIONS) do
		local t = o.opt or o.on
		if t then
			t = option_text(o)
			if t then
				lines[#lines + 1] = "OPTIONS=" .. t
			end
		end
	end
	return table.concat(lines, "\n")
end

-- ---------------------------------------------------------------- name
local function clean_name(s)
	return (tostring(s or ""):gsub("[^%w _%-]", ""):gsub("^%s+", ""):gsub("%s+$", ""):sub(1, 30))
end

local function has_game(name)
	local dir = core.get_worldpath() .. DIR_DELIM .. "nethack" .. DIR_DELIM
	for _, f in ipairs({name .. ".NetHack-saved-game", name .. ".0"}) do
		local h = io.open(dir .. f, "rb")
		if h then
			h:close()
			return true
		end
	end
	return false
end

-- the name NetHack plays under: a game in progress keeps its name
function nhopts.character_name(player_name)
	local want = clean_name(nhopts.get("name"))
	if want == "" or want == player_name then
		return player_name
	end
	if has_game(want) then
		return want
	end
	if has_game(player_name) then
		return player_name -- (finish that character first)
	end
	return want
end

-- ---------------------------------------------------------------- applying
local queue = {}

local function queue_runtime(only)
	for _, o in ipairs(nhopts.OPTIONS) do
		if not o.new and (not only or only[o.key]) then
			local t = option_text(o)
			if t then
				queue[#queue + 1] = t
			end
		end
	end
end

local applied_once = false
core.register_globalstep(function()
	if not nh.ready() then
		return
	end
	if not applied_once then
		applied_once = true
		queue_runtime() -- (the save keeps its own; these settings win)
	end
	while #queue > 0 and nh.ready() do
		nh.act({{key = "#"}, {text = "nhvopt " .. table.remove(queue, 1)}}, {kind = "info"})
	end
end)

-- ---------------------------------------------------------------- the page
local FORM = "nhv:nhoptions"

local function field_for(o, x, y)
	local name = "o_" .. o.key
	local v = nhopts.get(o.key)
	local fs = {}
	if o.kind == "bool" then
		fs[#fs + 1] = ("checkbox[%s,%s;%s;%s;%s]"):format(x, y + 0.35, name, E(o.label), tostring(v))
		return table.concat(fs)
	end
	fs[#fs + 1] = ("label[%s,%s;%s]"):format(x, y + 0.4, E(o.label))
	if o.kind == "text" then
		fs[#fs + 1] = ("field[%s,%s;4.6,0.8;%s;;%s]"):format(x + 4.3, y, name, E(v))
		fs[#fs + 1] = ("field_close_on_enter[%s;false]"):format(name)
	else
		local labels, sel = {}, 1
		for i, c in ipairs(o.choices) do
			labels[i] = E(c[2])
			if c[1] == v then
				sel = i
			end
		end
		fs[#fs + 1] = ("dropdown[%s,%s;4.6,0.8;%s;%s;%d;true]"):format(x + 4.3, y, name,
			table.concat(labels, ","), sel)
	end
	if o.note then
		fs[#fs + 1] = ("tooltip[%s;%s]"):format(name, E(o.note))
	end
	return table.concat(fs)
end

function nhopts.formspec()
	local fs = {theme.head(20, 11.6),
		"label[0.5,0.6;", theme.title("NetHack options"), "]",
		"label[0.5,1.3;", theme.dim("New characters"), "]",
		"label[10.5,1.3;", theme.dim("Any time (your current game too)"), "]"}
	local yl, yr = 1.7, 1.7
	for _, o in ipairs(nhopts.OPTIONS) do
		if o.new then
			fs[#fs + 1] = field_for(o, 0.5, yl)
			yl = yl + 0.9
		else
			fs[#fs + 1] = field_for(o, 10.5, yr)
			yr = yr + (o.kind == "bool" and 0.62 or 0.9)
		end
	end
	fs[#fs + 1] = "label[0.5,10.1;" .. theme.dim(E("A game in progress keeps its character; these apply to the next new one.")) .. "]"
	fs[#fs + 1] = "button[11.5,10.5;3.6,0.8;save;Save]button[15.4,10.5;3.6,0.8;back;Back]"
	return table.concat(fs)
end

function nhopts.show(player)
	core.show_formspec(player:get_player_name(), FORM, nhopts.formspec())
end

core.register_on_player_receive_fields(function(player, formname, fields)
	if formname ~= FORM then
		return false
	end
	if fields.save or fields.key_enter_field then
		local changed = {}
		for _, o in ipairs(nhopts.OPTIONS) do
			local v = fields["o_" .. o.key]
			if v ~= nil then
				if o.kind == "bool" then
					v = v == "true"
				elseif o.kind == "choice" then
					local c = o.choices[tonumber(v) or 0]
					v = c and c[1]
				elseif o.key == "name" then
					v = clean_name(v)
				end
				if v ~= nil and v ~= nhopts.get(o.key) then
					set(o.key, v)
					changed[o.key] = true
				end
			end
		end
		if next(changed) then
			core.settings:write()
			queue_runtime(changed)
		end
		nhv.hud.message("NetHack options saved.")
		nhv.graphics.show(player)
		return true
	end
	if fields.back then
		nhv.graphics.show(player)
	end
	return true
end)

return nhopts
