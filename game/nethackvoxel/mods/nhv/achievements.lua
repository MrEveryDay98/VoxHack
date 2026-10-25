-- Achievements: kept for the player, not the character or world - from game
-- to game and from one VoxHack version to the next, Steam style (in the
-- player's own files: achievements.json, core.nh_profile_*). NetHack tells
-- what happens (NHV_EV_ACHIEVE events, nhcore/nhv_achieve.c; nothing in
-- debug or explore mode) and each achievement says which events unlock it.
-- Unlocking one shows a note at the lower right (and plays the hook
-- "achievement_unlocked"); the Achievements screen (the title screen's
-- button, or the inventory's) lists them all.

local U = nhv.util
local nh = nhv.nh
local theme = nhv.theme
local E = core.formspec_escape

local ach = {}
nhv.achievements = ach

local FILE = "achievements.json"
local FORM = "nhv:achievements"

-- ---------------------------------------------------------------- the list
-- {id, name, description, icon (a sprite's name in nhv_tiles.png)}; a
-- string starts a new group
local LIST = {
	"The dungeon",
	{"mines", "Into the Mines", "Enter the Gnomish Mines", "gnome leader"},
	{"minetown", "Town and Country", "Reach Minetown", "watchman"},
	{"mines_prize", "Rock Bottom", "Find the luckstone at Mines' End", "gray / luckstone"},
	{"sokoban", "Heave Ho", "Enter Sokoban", "boulder"},
	{"soko_prize", "Puzzle Master", "Take Sokoban's prize", "bag / bag of holding"},
	{"oracle", "Words of Wisdom", "Consult the Oracle", "Oracle"},
	{"bigroom", "Room to Breathe", "Enter the Big Room", "lit corridor"},
	{"medusa", "Stone Cold", "Kill Medusa", "Medusa"},
	{"tune", "Passtune", "Learn the castle drawbridge's tune", "flute / wooden flute"},
	{"gehennom", "Abandon Hope", "Enter Gehennom", "molten lava"},
	{"bell", "For Whom It Tolls", "Get the Bell of Opening", "silver bell / Bell of Opening"},
	{"candelabrum", "Seven Candles", "Get the Candelabrum of Invocation", "candelabrum / Candelabrum of Invocation"},
	{"book", "Necronomicon", "Get the Book of the Dead", "papyrus / Book of the Dead"},
	{"invocation", "The Invocation", "Perform the Invocation", "vibrating square"},
	{"amulet", "The Amulet", "Get the Amulet of Yendor", "Amulet of Yendor / Amulet of Yendor"},
	{"endgame", "Beyond the Dungeon", "Enter the Elemental Planes", "air elemental"},
	{"astral", "Among the Stars", "Reach the Astral Plane", "Angel"},
	{"ascended", "Demigod", "Ascend", "lawful altar"},

	"Firsts",
	{"shop", "Window Shopping", "Enter a shop", "shopkeeper"},
	{"temple", "Sanctuary", "Enter a temple", "aligned cleric"},
	{"novel", "A Good Read", "Read a passage from a Discworld novel", "paperback / novel"},
	{"rank1", "Moving Up", "Reach your role's second title (experience level 3)", "THARR / gold detection"},
	{"rank2", "Seasoned", "Reach your role's third title (experience level 6)", "THARR / gold detection"},
	{"rank3", "Veteran", "Reach your role's fourth title (experience level 10)", "THARR / gold detection"},
	{"rank4", "Accomplished", "Reach your role's fifth title (experience level 14)", "THARR / gold detection"},
	{"rank5", "Renowned", "Reach your role's sixth title (experience level 18)", "THARR / gold detection"},
	{"rank6", "Famed", "Reach your role's seventh title (experience level 22)", "THARR / gold detection"},
	{"rank7", "Legendary", "Reach your role's eighth title (experience level 26)", "THARR / gold detection"},
	{"rank8", "Highest Title", "Reach your role's ninth title (experience level 30)", "THARR / gold detection"},

	"Milestones",
	{"quest_home", "The Call", "Reach your Quest's home", "magic portal"},
	{"quest_accepted", "Worthy", "Be given your Quest by its leader", "PRATYAVAYAH / remove curse"},
	{"quest_nemesis", "Nemesis", "Kill your Quest's nemesis", "Dark One"},
	{"quest_artifact", "Quest Complete", "Take your Quest's artifact", "glass orb / crystal ball"},
	{"ludios", "Fort Knox", "Reach Fort Ludios", "gold piece"},
	{"croesus", "Richest Man Alive", "Kill Croesus", "Croesus"},
	{"castle", "Storming the Castle", "Enter the Castle", "horizontal closed drawbridge"},
	{"castle_wand", "Your Wish Is...", "Take the Castle's wand of wishing", "pine / wishing"},
	{"valley", "The Valley of the Dead", "Enter the Valley of the Dead", "ghost"},
	{"wizard_tower", "The Tower", "Enter the Wizard's Tower", "Wizard of Yendor"},
	{"vlad", "Stake Through the Heart", "Kill Vlad the Impaler", "Vlad the Impaler"},
	{"wizard", "Rodney", "Kill the Wizard of Yendor", "Wizard of Yendor"},
	{"wizard5", "He Keeps Coming Back", "Kill the Wizard of Yendor five times in one game", "Wizard of Yendor"},
	{"juiblex", "Slime Lord", "Kill Juiblex", "Juiblex"},
	{"orcus", "Prince of the Undead", "Kill Orcus", "Orcus"},
	{"yeenoghu", "Gnoll Lord", "Kill Yeenoghu", "Yeenoghu"},
	{"demogorgon", "Prince of Demons", "Kill Demogorgon", "Demogorgon"},
	{"asmodeus", "Lord of the Ninth", "Kill Asmodeus", "Asmodeus"},
	{"baalzebub", "Lord of the Flies", "Kill Baalzebub", "Baalzebub"},
	{"dispater", "Iron City", "Kill Dispater", "Dispater"},
	{"death", "Death Dies", "Kill Death", "Death"},
	{"famine", "A Full Plate", "Kill Famine", "Famine"},
	{"pestilence", "Clean Bill of Health", "Kill Pestilence", "Pestilence"},
	{"depth20", "Deeper", "Reach dungeon level 20", "staircase down"},
	{"depth30", "Deeper Still", "Reach dungeon level 30", "staircase down"},
	{"depth40", "The Depths", "Reach dungeon level 40", "staircase down"},
	{"depth50", "Rock Bottom, Really", "Reach dungeon level 50", "staircase down"},

	"Power",
	{"wish", "Wishful Thinking", "Make a wish", "pine / wishing"},
	{"crowned", "Crowned", "Be crowned by your god", "crystal helmet / helm of brilliance"},
	{"excalibur", "The Lady of the Lake", "Get Excalibur from a fountain", "fountain"},
	{"named_artifact", "What's in a Name", "Make an artifact by naming it", "runed dagger / elven dagger"},
	{"god_gift", "A Gift from Above", "Be given an artifact for a sacrifice", "lawful altar"},
	{"altar_converted", "Conversion", "Convert an altar to your god", "chaotic altar"},
	{"stat_max", "Peak Condition", "Raise a characteristic to its maximum", "ruby / gain ability"},
	{"ac-10", "Untouchable", "Reach armor class -10", "plate mail"},
	{"ac-20", "Walking Fortress", "Reach armor class -20", "plate mail"},
	{"resist_all", "Proof Against All", "Resist fire, cold, shock, sleep, poison and disintegration at once", "gray dragon scale mail"},
	{"expert", "Mastery", "Reach Expert in a skill", "long sword"},
	{"poly_dragon", "Dragon Form", "Turn into a dragon", "red dragon"},
	{"poly_controlled", "Shapeshifter", "Change form, choosing what into", "emerald / polymorph control"},
	{"poly_undead", "Undeath", "Turn into an undead creature", "vampire leader"},
	{"dragon_pet", "Here Be Dragons", "Have a grown dragon as a pet", "silver dragon"},

	"Combat",
	{"kill100", "Hundred Down", "Kill 100 monsters (across all your games)", "jackal"},
	{"kill1000", "Thousand Down", "Kill 1,000 monsters (across all your games)", "soldier"},
	{"trice_melee", "Hands Off", "Kill a cockatrice or chickatrice in melee", "cockatrice"},
	{"wield_trice", "Rubber Chicken", "Wield a cockatrice corpse", "cockatrice"},
	{"far_kill", "Sharpshooter", "Kill with something thrown or fired from 8 or more squares away", "arrow"},
	{"polearm_kill", "Reach Out", "Kill with a polearm's hit from a distance", "angled poleaxe / halberd"},
	{"snickersnee", "Shkinng!", "Land Snickersnee's free hit", "samurai sword / katana"},
	{"shopkeeper", "Hostile Takeover", "Kill a shopkeeper", "shopkeeper"},
	{"blind_kill", "Blind Fury", "Kill a monster while blind", "blindfold"},
	{"boulder_kill", "Look Out Below", "Kill a monster with a boulder you dropped", "boulder"},
	{"priest_kill", "Heresy", "Kill a priest of your own god", "aligned cleric"},

	"Oddities",
	{"quick_death", "That Was Quick", "Die within 10 turns of starting", "grave"},
	{"genocided", "Self-Inflicted", "Genocide yourself", "ELBIB YLOH / genocide"},
	{"gourmet", "Gourmet", "Eat 20 different kinds of corpses (across all your games)", "corpse"},
	{"sink_ring", "Down the Drain", "Get a ring out of a sink", "sink"},
	{"creamed", "Pie in the Face", "Blind yourself with a cream pie", "cream pie"},
	{"shk_paid", "Restitution", "Pay a shopkeeper for damage you did", "gold piece"},

	"Conducts (on ascending)",
	{"atheist", "Atheist", "Ascend without praying, sacrificing or using a priest", "chaotic altar"},
	{"foodless", "Foodless", "Ascend without eating", "apple"},
	{"vegan", "Vegan", "Ascend eating no animal products", "apple"},
	{"vegetarian", "Vegetarian", "Ascend eating no meat", "carrot"},
	{"weaponless", "Weaponless", "Ascend without hitting with a wielded weapon", "old gloves / leather gloves"},
	{"pacifist", "Pacifist", "Ascend without killing a monster yourself", "white unicorn"},
	{"illiterate", "Illiterate", "Ascend without reading anything", "unlabeled / blank paper"},
	{"polypileless", "Polypileless", "Ascend without polymorphing an object", "silver / polymorph"},
	{"polyselfless", "Polyselfless", "Ascend without changing form", "polymorph trap"},
	{"wishless", "Wishless", "Ascend without wishing", "pine / wishing"},
	{"artiwishless", "Artiwishless", "Ascend without wishing for an artifact", "long sword"},
	{"genocideless", "Genocideless", "Ascend without genociding", "ELBIB YLOH / genocide"},
	{"blind_ascension", "Blind from Birth", "Ascend having been blind the whole game", "blindfold"},
	{"nudist", "Nudist", "Ascend without ever wearing armor", "leather armor"},
	{"sokoban_clean", "By the Rules", "Ascend having finished Sokoban without breaking its rules", "boulder"},

	"Ascensions",
	{"asc_archeologist", "Archeologist", "Ascend as an Archeologist", "archeologist"},
	{"asc_barbarian", "Barbarian", "Ascend as a Barbarian", "barbarian"},
	{"asc_caveman", "Caveman", "Ascend as a Caveman or Cavewoman", "cave dweller"},
	{"asc_healer", "Healer", "Ascend as a Healer", "healer"},
	{"asc_knight", "Knight", "Ascend as a Knight", "knight"},
	{"asc_monk", "Monk", "Ascend as a Monk", "monk"},
	{"asc_priest", "Priest", "Ascend as a Priest or Priestess", "cleric"},
	{"asc_rogue", "Rogue", "Ascend as a Rogue", "rogue"},
	{"asc_ranger", "Ranger", "Ascend as a Ranger", "ranger"},
	{"asc_samurai", "Samurai", "Ascend as a Samurai", "samurai"},
	{"asc_tourist", "Tourist", "Ascend as a Tourist", "tourist"},
	{"asc_valkyrie", "Valkyrie", "Ascend as a Valkyrie", "valkyrie"},
	{"asc_wizard", "Wizard", "Ascend as a Wizard", "wizard"},
	{"asc_human", "Human", "Ascend as a human", "human"},
	{"asc_elf", "Elf", "Ascend as an elf", "Woodland-elf"},
	{"asc_dwarf", "Dwarf", "Ascend as a dwarf", "dwarf"},
	{"asc_gnome", "Gnome", "Ascend as a gnome", "gnome"},
	{"asc_orc", "Orc", "Ascend as an orc", "hill orc"},
	{"asc_lawful", "Lawful", "Ascend lawful", "lawful altar"},
	{"asc_neutral", "Neutral", "Ascend neutral", "neutral altar"},
	{"asc_chaotic", "Chaotic", "Ascend chaotic", "chaotic altar"},
	{"asc_male", "Male", "Ascend as a man", "human (male)"},
	{"asc_female", "Female", "Ascend as a woman", "human (female)"},
}

ach.list, ach.by_id = {}, {}
do
	local group
	for _, d in ipairs(LIST) do
		if type(d) == "string" then
			group = d
		else
			local a = {id = d[1], name = d[2], desc = d[3], icon = d[4], group = group}
			ach.list[#ach.list + 1] = a
			ach.by_id[a.id] = a
		end
	end
end

-- NetHack's own achievements (ACH_*, you.h) -> ours. (13 blind and 14
-- nudist it records at every game's end: here they count only when you
-- ascend, with the other conducts.)
local NH = {
	[1] = "bell", [2] = "gehennom", [3] = "candelabrum", [4] = "book",
	[5] = "invocation", [6] = "amulet", [7] = "endgame", [8] = "astral",
	[9] = "ascended", [10] = "mines_prize", [11] = "soko_prize", [12] = "medusa",
	[15] = "mines", [16] = "minetown", [17] = "shop", [18] = "temple",
	[19] = "oracle", [20] = "novel", [21] = "sokoban", [22] = "bigroom",
	[23] = "rank1", [24] = "rank2", [25] = "rank3", [26] = "rank4",
	[27] = "rank5", [28] = "rank6", [29] = "rank7", [30] = "rank8",
	[31] = "tune",
}

-- killing these (by name)
local KILLS = {
	["Croesus"] = "croesus", ["Vlad the Impaler"] = "vlad",
	["Wizard of Yendor"] = "wizard", ["Juiblex"] = "juiblex", ["Orcus"] = "orcus",
	["Yeenoghu"] = "yeenoghu", ["Demogorgon"] = "demogorgon",
	["Asmodeus"] = "asmodeus", ["Baalzebub"] = "baalzebub",
	["Dispater"] = "dispater", ["Death"] = "death", ["Famine"] = "famine",
	["Pestilence"] = "pestilence",
}
local KILL = { -- nhv_achieve.c's NHV_KILL_*
	SHOPKEEPER = 0x1, OWN_PRIEST = 0x2, BLIND = 0x4, MELEE = 0x20,
	POLEARM = 0x40, FAR = 0x80, BOULDER = 0x100, NEMESIS = 0x200,
}
local KILL_FLAGS = {
	{KILL.SHOPKEEPER, "shopkeeper"}, {KILL.OWN_PRIEST, "priest_kill"},
	{KILL.BLIND, "blind_kill"}, {KILL.POLEARM, "polearm_kill"},
	{KILL.FAR, "far_kill"}, {KILL.BOULDER, "boulder_kill"},
	{KILL.NEMESIS, "quest_nemesis"},
}
local POLY = {{0x1, "poly_controlled"}, {0x2, "poly_dragon"}, {0x4, "poly_undead"}}
-- oname's flags (ONAME_*, hack.h)
local ARTIFACT = {{0x2, "named_artifact"}, {0x10, "excalibur"}, {0x8, "god_gift"}}
-- conducts kept (NHV_CONDUCT_*)
local CONDUCTS = {
	{0x1, "atheist"}, {0x2, "foodless"}, {0x4, "vegan"}, {0x8, "vegetarian"},
	{0x10, "weaponless"}, {0x20, "pacifist"}, {0x40, "illiterate"},
	{0x80, "polypileless"}, {0x100, "polyselfless"}, {0x200, "wishless"},
	{0x400, "artiwishless"}, {0x800, "genocideless"}, {0x1000, "blind_ascension"},
	{0x2000, "nudist"}, {0x4000, "sokoban_clean"},
}
-- how a game ended (hack.h)
local GENOCIDED, PANICKED, ASCENDED = 10, 11, 15
-- these just happen (the event is the achievement's id)
local PLAIN = {
	snickersnee = true, wield_trice = true, quest_accepted = true,
	quest_artifact = true, castle_wand = true, wish = true, crowned = true,
	altar_converted = true, expert = true, sink_ring = true, creamed = true,
	shk_paid = true, stat_max = true, resist_all = true, dragon_pet = true,
}

-- ---------------------------------------------------------------- the file
-- {unlocked = {id = when (os.time)}, kills = n, eaten = {monster = true}}
local data
local dirty = false

local function load()
	local text = core.nh_profile_read(FILE)
	data = text and core.parse_json(text) or nil
	if type(data) ~= "table" then
		data = {}
	end
	data.unlocked = type(data.unlocked) == "table" and data.unlocked or {}
	data.eaten = type(data.eaten) == "table" and data.eaten or {}
	data.kills = tonumber(data.kills) or 0
end
load()

local function save()
	dirty = false
	local out = {unlocked = data.unlocked, kills = data.kills, eaten = data.eaten}
	local json = core.write_json(out, true)
	if json then
		-- (an empty table comes out as null: an empty object)
		core.nh_profile_write(FILE, (json:gsub('" : null', '" : {}')))
	end
end

-- (counters are saved a few seconds after they change; unlocks at once)
local save_timer = 0
core.register_globalstep(function(dtime)
	if dirty then
		save_timer = save_timer + dtime
		if save_timer > 5 then
			save_timer = 0
			save()
		end
	end
end)
core.register_on_shutdown(function()
	if dirty then
		save()
	end
end)

function ach.unlocked(id)
	return data.unlocked[id]
end

function ach.count()
	local n = 0
	for _, a in ipairs(ach.list) do
		if data.unlocked[a.id] then
			n = n + 1
		end
	end
	return n, #ach.list
end

-- ---------------------------------------------------------------- the note
-- A note at the lower right, a few seconds each, one after another.
local NOTE_TIME = 5
local queue, note = {}, nil -- note: {ids=, left=}
local SHEET = nil -- sprite name -> its sheet position

local function icon(a, locked)
	if not SHEET then
		SHEET = {}
		for s, name in pairs(nhv_tiles.sheet_names or {}) do
			SHEET[name] = SHEET[name] or s
		end
	end
	-- (a creature's sprite may be its male one: "gnome (male)")
	local s = a.icon and (SHEET[a.icon] or SHEET[a.icon .. " (male)"])
	if not s then
		return "blank.png"
	end
	local tex = nhv_tiles.sheet_texture(s)
	if locked then
		tex = tex .. "^[hsl:0:-100:-40"
	end
	return tex
end

local function hide_note(player)
	if note then
		for _, id in ipairs(note.ids) do
			player:hud_remove(id)
		end
		note = nil
	end
end

-- (text cut into lines of at most n characters, at spaces)
local function wrap(text, n)
	local lines, line = {}, ""
	for word in text:gmatch("%S+") do
		if line ~= "" and #line + 1 + #word > n then
			lines[#lines + 1] = line
			line = word
		else
			line = line == "" and word or line .. " " .. word
		end
	end
	lines[#lines + 1] = line
	return lines
end

local function show_note(player, a)
	local P, A = {x = 1, y = 1}, {x = 1, y = 1}
	-- (sized to the text: HUD text is 14 pixels a line at Text size 1)
	local k = theme.box_scale()
	local LH = math.floor(14 * k + 6) -- a line's height
	local CW = 14 * k * 0.62 -- a character's width (about)
	local PAD = math.floor(4 + 4 * k)
	local lines = {{"Achievement unlocked", 0xFFD25A}, {a.name, 0xFFFFFF}}
	for _, l in ipairs(wrap(a.desc, 40)) do
		lines[#lines + 1] = {l, 0xB0B0B0}
	end
	local chars = 0
	for _, l in ipairs(lines) do
		chars = math.max(chars, #l[1])
	end
	local ICON = 3 * LH -- (the sprite: three lines high)
	local W = math.floor(ICON + 3 * PAD + chars * CW)
	local H = math.max(ICON, #lines * LH) + 2 * PAD
	local function add(def)
		def.position, def.alignment = P, A
		def.z_index = def.z_index or 901
		return player:hud_add(def)
	end
	local x0, y0 = -W - 20, -H - 150
	local ids = {
		add({type = "image", text = ("[fill:%dx%d:#000000C8"):format(W, H), scale = {x = 1, y = 1},
			offset = {x = x0, y = y0}, z_index = 900}),
		add({type = "image", text = ("[fill:%dx2:#FFD25A"):format(W), scale = {x = 1, y = 1},
			offset = {x = x0, y = y0}}),
		add({type = "image", text = icon(a), scale = {x = ICON / 16, y = ICON / 16},
			offset = {x = x0 + PAD, y = y0 + PAD}}),
	}
	for i, l in ipairs(lines) do
		ids[#ids + 1] = add({type = "text", text = l[1], number = l[2],
			offset = {x = x0 + ICON + 2 * PAD, y = y0 + PAD + (i - 1) * LH}})
	end
	note = {left = NOTE_TIME, ids = ids}
	if nhv.sound then
		nhv.sound.hook("achievement_unlocked")
	end
end

core.register_globalstep(function(dtime)
	local player = nhv.player and nhv.player.get()
	if not player then
		return
	end
	if note then
		note.left = note.left - dtime
		if note.left > 0 then
			return
		end
		hide_note(player)
	end
	local a = table.remove(queue, 1)
	if a then
		show_note(player, a)
	end
end)

-- ---------------------------------------------------------------- unlocking
function ach.unlock(id)
	local a = ach.by_id[id]
	if not a or data.unlocked[id] then
		return
	end
	data.unlocked[id] = os.time()
	save()
	queue[#queue + 1] = a
	core.log("action", "[nhv] achievement unlocked: " .. id)
end

local function flags_unlock(flags, list)
	for _, f in ipairs(list) do
		if U.has(flags, f[1]) then
			ach.unlock(f[2])
		end
	end
end

local function on_kill(flags, times, name)
	data.kills = data.kills + 1
	dirty = true
	if data.kills >= 100 then
		ach.unlock("kill100")
	end
	if data.kills >= 1000 then
		ach.unlock("kill1000")
	end
	if KILLS[name] then
		ach.unlock(KILLS[name])
	end
	if name == "Wizard of Yendor" and times >= 5 then
		ach.unlock("wizard5")
	end
	if (name == "cockatrice" or name == "chickatrice") and U.has(flags, KILL.MELEE) then
		ach.unlock("trice_melee")
	end
	flags_unlock(flags, KILL_FLAGS)
end

local function on_end(how, turns, conducts, role, race, align, gender)
	if how < PANICKED and turns <= 10 then
		ach.unlock("quick_death")
	end
	if how == GENOCIDED then
		ach.unlock("genocided")
	end
	if how ~= ASCENDED then
		return
	end
	flags_unlock(conducts, CONDUCTS)
	for _, v in ipairs({role, race, align, gender}) do
		ach.unlock("asc_" .. v:lower())
	end
end

-- one NHV_EV_ACHIEVE event's text
function ach.event(text)
	local kind, rest = text:match("^(%S+)%s*(.*)$")
	if not kind then
		return
	end
	local n = tonumber(rest:match("^(%-?%d+)"))
	if kind == "nh" then
		if NH[n] then
			ach.unlock(NH[n])
		end
	elseif kind == "kill" then
		local flags, times, name = rest:match("^(%d+) (%d+) (.+)$")
		if name then
			on_kill(tonumber(flags), tonumber(times), name)
		end
	elseif kind == "eat" then
		if not data.eaten[rest] then
			data.eaten[rest] = true
			dirty = true
			local k = 0
			for _ in pairs(data.eaten) do
				k = k + 1
			end
			if k >= 20 then
				ach.unlock("gourmet")
			end
		end
	elseif kind == "poly" then
		flags_unlock(n or 0, POLY)
	elseif kind == "artifact" then
		flags_unlock(n or 0, ARTIFACT)
	elseif kind == "place" then
		ach.unlock(rest)
	elseif kind == "depth" and n then
		for _, d in ipairs({20, 30, 40, 50}) do
			if n >= d then
				ach.unlock("depth" .. d)
			end
		end
	elseif kind == "ac" and n then
		for _, ac in ipairs({-10, -20}) do
			if n <= ac then
				ach.unlock("ac" .. ac)
			end
		end
	elseif kind == "end" then
		local how, turns, conducts, role, race, align, gender =
			rest:match("^(%d+) (%d+) (%d+) (%S+) (%S+) (%S+) (%S+)$")
		if how then
			on_end(tonumber(how), tonumber(turns), tonumber(conducts), role, race, align, gender)
		end
	elseif PLAIN[kind] then
		ach.unlock(kind)
	end
end

nh.on_event(function(evs)
	for _, ev in ipairs(evs) do
		if ev.kind == "achieve" then
			ach.event(ev.text)
		end
	end
end)

-- ---------------------------------------------------------------- the screen
local function formspec()
	local got, total = ach.count()
	local W, H = 16, 10.5
	local fs = {theme.head(W, H),
		"label[0.4,0.5;" .. theme.title("Achievements") .. "]",
		("label[%s,0.5;%s]"):format(W - 3.2, E(("%d of %d unlocked"):format(got, total))),
		("scroll_container[0.3,1;%s,%s;list;vertical;0.1]"):format(W - 0.9, H - 2.3)}
	local y, group = 0, nil
	for _, a in ipairs(ach.list) do
		if a.group ~= group then
			group = a.group
			y = y + (y > 0 and 0.3 or 0)
			fs[#fs + 1] = ("label[0.1,%s;%s]"):format(y + 0.3, theme.title(E(group)))
			y = y + 0.7
		end
		-- (one not unlocked yet is hidden: a dark square, "???")
		local when = data.unlocked[a.id]
		fs[#fs + 1] = ("image[0.1,%s;0.8,0.8;%s]"):format(y,
			when and E(icon(a)) or E("[fill:16x16:#1A1A22"))
		if when then
			fs[#fs + 1] = ("label[1.1,%s;%s]"):format(y + 0.2, E(a.name))
			fs[#fs + 1] = ("label[1.1,%s;%s]"):format(y + 0.6, theme.dim(E(a.desc)))
		else
			fs[#fs + 1] = ("label[1.1,%s;%s]"):format(y + 0.2, core.colorize("#808080", "???"))
			fs[#fs + 1] = ("label[1.1,%s;%s]"):format(y + 0.6, theme.dim("???"))
		end
		if when then
			fs[#fs + 1] = ("label[%s,%s;%s]"):format(W - 3.1, y + 0.2,
				core.colorize("#FFD25A", E(os.date("%Y-%m-%d", when))))
		end
		y = y + 1
	end
	fs[#fs + 1] = "scroll_container_end[]"
	fs[#fs + 1] = ("scrollbaroptions[max=%d;smallstep=10;largestep=60]"):format(
		math.max(0, math.ceil((y - (H - 2.3)) * 10)))
	fs[#fs + 1] = ("scrollbar[%s,1;0.3,%s;vertical;list;0]"):format(W - 0.55, H - 2.3)
	fs[#fs + 1] = ("button[%s,%s;3,0.8;back;Back]"):format(W / 2 - 1.5, H - 1.05)
	return table.concat(fs)
end

function ach.show(player)
	core.show_formspec(player:get_player_name(), FORM, formspec())
end

core.register_on_player_receive_fields(function(player, formname, fields)
	if formname == "" and fields.achievements then
		ach.show(player)
		return true
	end
	if formname ~= FORM then
		return false
	end
	if fields.back or fields.quit then
		if nhv.title and nhv.title.open then
			nhv.title.show(player) -- (opened from the title screen: back to it)
		elseif fields.back then
			core.close_formspec(player:get_player_name(), FORM)
		end
	end
	return true
end)

return ach
