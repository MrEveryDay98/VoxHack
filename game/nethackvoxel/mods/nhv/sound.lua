-- Sound: plays what the sound configuration (made in the VoxHack Editor)
-- attaches to each hook.
--
-- Hooks come from code, never from reading messages:
--   * NetHack's own sound effects and the hooks VoxHack added to its
--     code (sound events "effect|<hook>|<volume>"),
--   * spoken lines and quest messages (voice acting, matched to the
--     dialogue catalog),
--   * the game's own hooks (sound.hook("footstep") etc.) and changes in the
--     hero's state (hunger, gold, hit points...),
--   * music for the place the hero is in.
--
-- The configuration is mods/nhv_sounds/config.json; it is re-read when it
-- changes, so edits in the VoxHack Editor apply while playing.

local U = nhv.util
local nh = nhv.nh
local sound = {
	cfg = {hooks = {}, voices = {}, master = {effects = 100, music = 60, voices = 100}},
	music = nil,       -- {hook=, handle=}
	voice = nil,       -- handle of the line being spoken
}
nhv.sound = sound

local MODPATH = core.get_modpath("nhv_sounds")
local CFG_PATH = MODPATH .. DIR_DELIM .. "config.json"
local SOUND_DIR = MODPATH .. DIR_DELIM .. "sounds"

-- ---------------------------------------------------------------- config
-- every sound under sounds/, folders included: {name = path}. .ogg, and
-- .mid / .midi music, which the VoxHack build of Luanti renders with
-- the SoundFont in mods/nhv_sounds/soundfonts (see below).
-- (names are global in Luanti, so the editor keeps them unique)
local function scan(dir, out)
	out = out or {}
	for _, f in ipairs(core.get_dir_list(dir, false) or {}) do
		local n = f:match("^(.+)%.ogg$") or f:match("^(.+)%.mid$") or f:match("^(.+)%.midi$")
		if n then
			out[n] = dir .. DIR_DELIM .. f
		end
	end
	for _, d in ipairs(core.get_dir_list(dir, true) or {}) do
		scan(dir .. DIR_DELIM .. d, out)
	end
	return out
end

local known = scan(SOUND_DIR)   -- sound names the client has

-- MIDI music: the engine renders it with the first SoundFont (.sf2) in
-- mods/nhv_sounds/soundfonts (GeneralUser GS by S. Christian Collins)
do
	local dir = MODPATH .. DIR_DELIM .. "soundfonts"
	for _, f in ipairs(core.get_dir_list(dir, false) or {}) do
		if f:lower():match("%.sf2$") then
			core.settings:set("nhv_soundfont", dir .. DIR_DELIM .. f)
			break
		end
	end
end

local cfg_text = nil
local function load_config()
	local f = io.open(CFG_PATH, "rb")
	if not f then
		return
	end
	local text = f:read("*a")
	f:close()
	if text == cfg_text then
		return
	end
	cfg_text = text
	local cfg = core.parse_json(text)
	if type(cfg) ~= "table" then
		core.log("warning", "[nhv] sound config is not valid JSON")
		return
	end
	cfg.hooks = cfg.hooks or {}
	cfg.voices = cfg.voices or {}
	cfg.master = cfg.master or {}
	sound.cfg = cfg
	-- sounds added since the game started are sent to the client now
	for n, path in pairs(scan(SOUND_DIR)) do
		if not known[n] then
			known[n] = path
			core.dynamic_add_media({filepath = path}, function() end)
		end
	end
	if sound.music then
		-- re-pick music in case its assignment changed
		local hook = sound.music.hook
		sound.stop_music()
		sound.set_music(hook)
	end
end
load_config()

-- the voice casting (voice_cast.json, from the editor's Voice casting tab):
-- which speakers SAM voices live, and how
local CAST_PATH = MODPATH .. DIR_DELIM .. "voice_cast.json"
local cast_text = nil
sound.cast = {speakers = {}, lines = {}}
local function load_cast()
	local f = io.open(CAST_PATH, "rb")
	if not f then
		return
	end
	local text = f:read("*a")
	f:close()
	if text == cast_text then
		return
	end
	cast_text = text
	local cast = core.parse_json(text)
	if type(cast) == "table" then
		cast.speakers = type(cast.speakers) == "table" and cast.speakers or {}
		cast.lines = type(cast.lines) == "table" and cast.lines or {}
		sound.cast = cast
	end
end
load_cast()

local reload_t = 0
core.register_globalstep(function(dtime)
	reload_t = reload_t + dtime
	if reload_t > 2 then
		reload_t = 0
		load_config()
		load_cast()
	end
end)

-- ---------------------------------------------------------------- playing
local function player()
	return core.get_connected_players()[1]
end

local function pick(entry)
	local list = entry and entry.sounds
	if not list or #list == 0 then
		return nil
	end
	local name = list[math.random(#list)]
	return known[name] and name or nil
end

sound.FEMALE_PITCH = 1.35

-- ---------------------------------------------------------------- where
-- Sounds with a place come from it: NetHack tells where a sound happens
-- (a square, or a monster: "effect|<hook>|<volume>|<x>|<y>|<m_id>"), and
-- the engine pans it and lets it fade with distance. One behind a wall
-- is muffled: quieter, its highs filtered out (the engine's nhv_muffle).

-- a monster's model if it has one (it may be mid-step), else the square
function sound.where(x, y, m_id)
	local e = m_id and m_id > 0 and nhv.mobs and nhv.mobs.mons["id" .. m_id]
	local pos = e and e.obj and e.obj:get_pos()
	if pos then
		return pos
	end
	if x and y and x > 0 then
		return U.tile_center(x, y, nhv.terrain.stand_y(x, y) + 1.0)
	end
	return nil
end

-- Does this node stop sound? Walls, rock and closed doors do; the
-- invisible nodes that fill open space (room and hero lights, level
-- edges, tight gaps) don't. (core.line_of_sight counts anything but air
-- as a wall, so lit rooms would muffle everything.)
local blocks_sound = {}
local function stops_sound(name)
	local b = blocks_sound[name]
	if b == nil then
		local def = core.registered_nodes[name]
		b = def ~= nil and def.walkable == true
			and (def.drawtype ~= "airlike" or (def.groups and def.groups.nhv_door ~= nil)) or false
		blocks_sound[name] = b
	end
	return b
end

local function clear_path(from, to)
	local d = vector.subtract(to, from)
	local steps = math.max(1, math.ceil(vector.length(d) * 4)) -- (quarter-node steps)
	-- (the sound's own square never muffles it: a door being opened, still
	-- closed for a moment, or anything in a wall)
	local own_x, own_y = U.pos_to_tile(to)
	local last
	for i = 1, steps - 1 do
		local q = vector.round(vector.add(from, vector.multiply(d, i / steps)))
		if not (last and vector.equals(q, last)) then
			last = q
			local qx, qy = U.pos_to_tile(q)
			if not (qx == own_x and qy == own_y) and stops_sound(core.get_node(q).name) then
				return false
			end
		end
	end
	return true
end

-- 0 (in plain sight) .. 1 (walls in the way): three lines from the hero's
-- eyes to around the source, so a sound by a doorway is partly muffled
local AROUND = {vector.new(0, 0, 0), vector.new(0, 0.7, 0), vector.new(0.35, -0.4, 0.35)}
function sound.muffle(pos)
	local p = player()
	if not p or not pos then
		return 0
	end
	local eye = vector.offset(p:get_pos(), 0, p:get_properties().eye_height or 1.6, 0)
	local blocked = 0
	for _, off in ipairs(AROUND) do
		if not clear_path(eye, vector.add(pos, off)) then
			blocked = blocked + 1
		end
	end
	return blocked / #AROUND
end

-- A free action's sounds (Snickersnee's free hit, which takes no time):
-- a little slowed, ringing on in quick echoes, as if time held still
local FREE_PITCH = 0.82
local FREE_ECHOES = {{0.09, 0.45}, {0.19, 0.22}, {0.30, 0.1}} -- (seconds later, gain)

-- Play whatever is attached to a hook. opts: volume (0-100), pos, free
-- (a free action's: FREE_*).
function sound.hook(id, opts)
	-- (particle effects attach to the same hooks: effects.lua)
	if nhv.effects then
		nhv.effects.hook(id, opts)
	end
	-- (and lightning and a camera flash the screen: hud.lua)
	if nhv.hud then
		nhv.hud.hook_flash(id)
	end
	-- (a lightning artifact's bolt: lightning.lua)
	if nhv.lightning then
		nhv.lightning.hook(id, opts)
	end
	local entry = sound.cfg.hooks[id]
	local name = pick(entry)
	local p = player()
	if not name or not p then
		return
	end
	opts = opts or {}
	local gain = (entry.volume or 100) / 100 * ((opts.volume or 100) / 100)
		* ((sound.cfg.master.effects or 100) / 100)
	local pv = entry.pitch_var or 0
	local params = {gain = gain, pitch = 1 + (math.random() * 2 - 1) * pv}
	-- the hero's own voice (hooks ticked "Player voice" in the sound
	-- editor: hurt, yawning...) is higher for a female hero
	local hero = nh.snap and nh.snap.hero
	if entry.player_voice and hero and U.has(hero.flags, U.HERO.FEMALE) then
		params.pitch = params.pitch * sound.FEMALE_PITCH
	end
	if opts.pos then
		params.pos = opts.pos
		params.max_hear_distance = 48
		params.nhv_muffle = sound.muffle(opts.pos)
	else
		params.to_player = p:get_player_name()
	end
	if opts.free then
		params.pitch = params.pitch * FREE_PITCH
		for _, echo in ipairs(FREE_ECHOES) do
			local copy = table.copy(params)
			copy.gain = params.gain * echo[2]
			core.after(echo[1], core.sound_play, name, copy)
		end
	end
	-- not "ephemeral": those go out unreliably and get dropped when several
	-- play at once; every effect gets its own handle, so they all overlap
	core.sound_play(name, params)
end

-- ---------------------------------------------------------------- notes
-- Note-based sounds play real notes through the MIDI player and SoundFont
-- (sounds/notes/nhv_note_<program>_<semitone>.mid, tools/make_note_midis.py):
-- squeaky boards squeak their own note, and instruments play the tune you
-- play (or improvise) on their General MIDI instrument (NetHack's
-- instrument ids are GM program numbers).
local BOARD_PROGRAM = 80 -- (ocarina: see make_note_midis.py)
local SEMITONE = {C = 0, D = 2, E = 4, F = 5, G = 7, A = 9, B = 11}
local NOTE_GAP = 0.32 -- seconds between the notes of a tune

function sound.note(program, semi, gain, pos)
	local p = player()
	local name = ("nhv_note_%d_%d"):format(program, semi % 12)
	if not known[name] then
		name = ("nhv_note_74_%d"):format(semi % 12) -- (an instrument without notes: flute)
	end
	if not p or not known[name] then
		return
	end
	local params = {gain = gain * ((sound.cfg.master.effects or 100) / 100)}
	if pos then
		params.pos, params.max_hear_distance, params.nhv_muffle = pos, 48, sound.muffle(pos)
	else
		params.to_player = p:get_player_name()
	end
	core.sound_play(name, params)
end

-- "squeak_D_flat" -> 1, "squeak_F_sharp" -> 6, "squeak_C" -> 0
local function squeak_semitone(id)
	local letter, acc = id:match("^squeak_(%u)_?(%a*)$")
	local semi = letter and SEMITONE[letter]
	if not semi then
		return nil
	end
	return semi + (acc == "flat" and -1 or acc == "sharp" and 1 or 0)
end

-- a tune: "CDEFG" on instrument program, one note after another
function sound.tune(program, notes, volume)
	local gain = 0.35 + 0.65 * math.min(100, volume or 50) / 100
	local k = 0
	for c in (notes or ""):upper():gmatch("%u") do
		local semi = SEMITONE[c]
		if semi then
			core.after(k * NOTE_GAP, sound.note, program, semi, gain)
			k = k + 1
		end
	end
end

-- "/nhvplay <sound>" (e.g. in the command line): play any sound by name,
-- to try one out; "/nhvplay" alone stops the last one
local tried
core.register_chatcommand("nhvplay", {
	params = "[sound name]",
	description = "(VoxHack) play a sound or music track to try it",
	func = function(name, param)
		if tried then
			core.sound_stop(tried)
			tried = nil
		end
		if param == "" then
			return true, "Stopped."
		end
		if not known[param] then
			return false, "No sound called " .. param
		end
		tried = core.sound_play(param, {to_player = name, gain = 1})
		return true, "Playing " .. param
	end,
})

-- ---------------------------------------------------------------- music
function sound.stop_music()
	if sound.music and sound.music.handle then
		core.sound_fade(sound.music.handle, 0.5, 0)
	end
	sound.music = nil
end

function sound.set_music(hook)
	if sound.music and sound.music.hook == hook then
		return
	end
	sound.stop_music()
	local entry = sound.cfg.hooks[hook]
	local name = pick(entry)
	local p = player()
	sound.music = {hook = hook}
	if not name or not p then
		return
	end
	local gain = (entry.volume or 100) / 100 * ((sound.cfg.master.music or 60) / 100)
	sound.music.handle = core.sound_play(name, {to_player = p:get_player_name(),
		gain = gain, loop = entry.loop ~= false, fade = 0.5, nhv_reverb = 0})
end

local DUNGEON_MUSIC = {
	["The Dungeons of Doom"] = "music_dungeon", ["The Gnomish Mines"] = "music_mines",
	["Sokoban"] = "music_sokoban", ["The Quest"] = "music_quest",
	["Fort Ludios"] = "music_ludios", ["Gehennom"] = "music_gehennom",
	["Vlad's Tower"] = "music_vlad", ["The Elemental Planes"] = "music_endgame",
}

-- special levels (NetHack's names for them) with music of their own
local LEVEL_MUSIC = {
	minetn = "music_minetown", oracle = "music_oracle", bigrm = "music_bigroom",
	astral = "music_astral",
}

-- (levels whose music plays in their temples and shops too: the Astral
-- Plane's three high altars are its whole point)
local LEVEL_MUSIC_FIRST = {music_astral = true}

local function music_for(h)
	-- a special level with its own music (Minetown, the Oracle...), when it
	-- has some; else the dungeon branch's
	local level = LEVEL_MUSIC[h.dnum and core.nh_level_proto(h.dnum, h.dlevel) or ""]
	if level and not sound.cfg.hooks[level] then
		level = nil
	end
	if U.has(h.flags, U.HERO.DEAD) then
		-- (dying - NetHack's last questions: silence; music_death waits for
		-- your gravestone, ui.show_death)
		return nil
	elseif level and LEVEL_MUSIC_FIRST[level] then
		return level
	elseif U.has(h.flags, U.HERO.INSHOP) and sound.cfg.hooks.music_shop then
		return "music_shop"
	elseif U.has(h.flags, U.HERO.INTEMPLE) and sound.cfg.hooks.music_temple then
		return "music_temple"
	end
	if level then
		return level
	end
	return DUNGEON_MUSIC[h.dungeon_name] or "music_dungeon"
end

-- ---------------------------------------------------------------- voices
local dialogue = {}      -- id -> entry
local spoken_pats = {}   -- {pattern, id} for spoken/ambient/level lines
local quest_ids = {}     -- "section/msgid" -> list of ids

-- C/quest format strings to Lua patterns (placeholders match anything)
local function to_pattern(text)
	local p = text:gsub("[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%0")
	p = p:gsub("%%%%[%-0-9%.]*l?[sdcuix]", ".-")  -- C %s %d ...
	p = p:gsub("%%%%%a%a?", ".-")                -- quest %p %dC ...
	return "^" .. p .. "$"
end

do
	local f = io.open(MODPATH .. DIR_DELIM .. "catalog" .. DIR_DELIM .. "dialogue.json", "rb")
	if f then
		local cat = core.parse_json(f:read("*a")) or {}
		f:close()
		for _, e in ipairs(cat.entries or {}) do
			dialogue[e.id] = e
			if e.quest then
				local k = e.quest.section .. "/" .. e.quest.msgid
				quest_ids[k] = quest_ids[k] or {}
				table.insert(quest_ids[k], e.id)
			elseif e.category ~= "written" and #e.text < 300 then
				-- (lines that are nearly all placeholders, like "%s" or
				-- "%s!", would match anything: they're left out, and the
				-- most specific line wins, so "Who left that %s in here?"
				-- beats a catch-all)
				local literal = e.text:gsub("%%[%-0-9%.]*l?[sdcuix]", ""):gsub("%%%a%a?", "")
				local _, letters = literal:gsub("%a", "")
				if letters >= 3 then
					table.insert(spoken_pats, {to_pattern(e.text:gsub('^"', ""):gsub('"$', "")), e.id, #literal})
				end
			end
		end
		table.sort(spoken_pats, function(a, b)
			if a[3] ~= b[3] then
				return a[3] > b[3]
			end
			return a[2] < b[2]
		end)
	end
end

-- ---------------------------------------------------------------- SAM
-- Speakers cast to SAM in the editor ("Speak live with SAM") are voiced by
-- SAM, the 1982 speech synth built into the VoxHack engine: it reads the
-- line's real text as it happens (your name, your god...), nothing is
-- recorded. The engine speaks a sound named
-- "nhv_sam:<speed>,<pitch>,<throat>,<mouth>,<sing>,<phonetic>,<smooth>,<tone>,<effects>|<text>"
-- and reads its words through the pronunciation dictionary
-- (mods/nhv_sounds/sam_dictionary.txt, edited in the editor).
core.settings:set("nhv_sam_dict", MODPATH .. DIR_DELIM .. "sam_dictionary.txt")

-- (the classic voices from SAM's manual; the same list as the editor's)
local SAM_VOICES = {
	["SAM"] = {speed = 72, pitch = 64, throat = 128, mouth = 128},
	["Elf"] = {speed = 72, pitch = 64, throat = 110, mouth = 160},
	["Little Robot"] = {speed = 92, pitch = 60, throat = 190, mouth = 190},
	["Stuffy Guy"] = {speed = 82, pitch = 72, throat = 110, mouth = 105},
	["Little Old Lady"] = {speed = 82, pitch = 32, throat = 145, mouth = 145},
	["Extra-Terrestrial"] = {speed = 100, pitch = 64, throat = 150, mouth = 200},
}
-- playback pitch by NetHack size class (tiny .. gigantic): big ones deeper
local SIZE_PITCH = {[0] = 1.2, 1.1, 1.0, 0.93, 0.86, 0.8}

-- a speaker's effects as the engine's chain:
-- {{type="echo", delay=250}, ...} -> "echo:delay=250/..." (sam_speech.cpp;
-- what a parameter leaves out, the engine fills in)
local function effect_chain(list)
	local out = {}
	for _, fx in ipairs(type(list) == "table" and list or {}) do
		if type(fx) == "table" and not fx.off and type(fx.type) == "string" and fx.type:match("^%a+$") then
			-- (keys sorted, so a line's sound name, and the engine's cache, stay the same)
			local keys = {}
			for k, v in pairs(fx) do
				if type(k) == "string" and k:match("^%a+$") and type(v) == "number" then
					keys[#keys + 1] = k
				end
			end
			table.sort(keys)
			local parts = {fx.type}
			for _, k in ipairs(keys) do
				parts[#parts + 1] = ("%s=%g"):format(k, fx[k])
			end
			out[#out + 1] = table.concat(parts, ":")
		end
	end
	return table.concat(out, "/")
end

local function clamp255(v)
	return math.max(1, math.min(255, math.floor(v + 0.5)))
end

-- three steady numbers in [-1, 1] for a monster, so each sounds a little
-- different from its kind, but always the same itself
local function monster_dice(m_id)
	local h = (m_id * 2654435761) % 4294967296
	local function die()
		local d = h % 1000
		h = math.floor(h / 1000) + d * 7919
		return d / 999 * 2 - 1
	end
	return die(), die(), die(), die()
end

-- The SAM settings for a line, or nil if its speaker isn't voiced by SAM.
-- who (optional): {m_id=, female=} of the monster saying it
local sam_settings
local function sam_for(id, who)
	local e = dialogue[id]
	if not e then
		return nil
	end
	local ln = sound.cast.lines[id] or {}
	return sam_settings(ln.cast or e.speaker, who, ln)
end

-- the SAM settings for a speaker of the voice casting (ln: a line's own
-- settings, if any), or nil if it isn't voiced live by SAM
function sam_settings(speaker, who, ln)
	ln = ln or {}
	-- (NetHack options > Spoken lines off: SAM says nothing)
	if not nhv.nhopts.get("sam_voices") then
		return nil
	end
	local sc = sound.cast.speakers[speaker]
	local ss = type(sc) == "table" and sc.sam
	if type(ss) ~= "table" or not ss.live then
		return nil
	end
	local st = {sing = ss.sing and 1 or 0, volume = tonumber(ss.volume) or 100,
		smooth = ss.smooth and 1 or 0, tone = ss.tone == false and 0 or 1, pitch_mul = 1,
		effects = effect_chain(ss.effects),
		text = type(ln.sam_text) == "string" and ln.sam_text ~= "" and ln.sam_text or nil}
	-- a line can take another of SAM's named voices
	local named = SAM_VOICES[ln.sam_voice or ""]
	local base = named or SAM_VOICES[ss.voice or ""] or SAM_VOICES.SAM
	for _, k in ipairs({"speed", "pitch", "throat", "mouth"}) do
		st[k] = named and base[k] or tonumber(ss[k]) or base[k]
	end
	local mon = who and who.m_id and who.m_id > 0
		and nhv.mobs and nhv.mobs.mons["id" .. who.m_id]
	if who and who.m_id and who.m_id > 0 then
		-- every monster its own voice (Variation, 0-100)
		local var = (tonumber(ss.variation) or 25) / 100
		local d1, d2, d3, d4 = monster_dice(who.m_id)
		st.pitch = st.pitch + d1 * var * 14
		st.speed = st.speed + d2 * var * 10
		st.throat = st.throat + d3 * var * 24
		st.mouth = st.mouth + d4 * var * 24
	end
	if who and who.female then
		-- females higher (SAM: a lower pitch number is a higher voice)
		st.pitch = st.pitch - (tonumber(ss.female) or 12)
	end
	if mon and mon.mon and ss.size ~= false then
		st.pitch_mul = SIZE_PITCH[mon.mon.size or 2] or 1
	end
	for _, k in ipairs({"speed", "pitch", "throat", "mouth"}) do
		st[k] = clamp255(st[k])
	end
	return st
end

-- Voices play over each other; a speaker's new line cuts off their last
-- (key: who's speaking - a monster, or a speaker of the catalog)
local voices = {} -- key -> sound handle
local function start_voice(key, name, params)
	key = key or "?"
	if voices[key] then
		core.sound_stop(voices[key])
	end
	voices[key] = core.sound_play(name, params)
end

local function speak_sam(st, text, pos, key)
	local p = player()
	if not p then
		return false
	end
	text = (st.text or text):gsub("%s+", " "):gsub('^%s*"', ""):gsub('"%s*$', "")
	if not text:find("%w") then
		return false
	end
	local name = ("nhv_sam:%d,%d,%d,%d,%d,0,%d,%d,%s|%s"):format(st.speed, st.pitch, st.throat, st.mouth,
		st.sing, st.smooth, st.tone, st.effects, text)
	local params = {gain = st.volume / 100 * ((sound.cfg.master.voices or 100) / 100), pitch = st.pitch_mul}
	if pos then
		params.pos, params.max_hear_distance, params.nhv_muffle = pos, 64, sound.muffle(pos)
	else
		params.to_player = p:get_player_name()
	end
	start_voice(key, name, params)
	return true
end

-- text: what the game actually said (SAM reads it; a recording ignores it)
local function play_voice(id, pos, text, who)
	local e = dialogue[id]
	local key = who and who.m_id and who.m_id > 0 and ("mon" .. who.m_id) or (e and e.speaker) or id
	local st = text and sam_for(id, who)
	if st then
		return speak_sam(st, text, pos, key)
	end
	local v = sound.cfg.voices[id]
	local name = v and v.sound
	local p = player()
	if not name or not known[name] or not p then
		return false
	end
	local gain = (v.volume or 100) / 100 * ((sound.cfg.master.voices or 100) / 100)
	local params = {gain = gain}
	if pos then
		params.pos, params.max_hear_distance, params.nhv_muffle = pos, 64, sound.muffle(pos)
	else
		params.to_player = p:get_player_name()
	end
	start_voice(key, name, params)
	return true
end

-- Lines that aren't in the dialogue catalog (put together as the game
-- goes - a priest's greeting, the Oracle's rumors...) are still read by
-- SAM, in the voice of whoever says them: the monster's name -> speaker
local SPEAKER_BY_MON = {
	Oracle = "The Oracle", priest = "Priest", priestess = "Priest",
	["high priest"] = "Priest", ["high priestess"] = "Priest",
	shopkeeper = "Shopkeeper", ["Wizard of Yendor"] = "Wizard of Yendor",
	["mail daemon"] = "Mail daemon", deity = "God",
	watchman = "Minetown watch", ["watch captain"] = "Minetown watch",
}

-- where the Oracle sits (her consultations are read from there)
local function oracle_pos()
	for _, e in pairs(nhv.mobs and nhv.mobs.mons or {}) do
		if e.mon and e.mon.mndx and core.nh_mon_name(e.mon.mndx) == "Oracle" and e.obj:get_pos() then
			return e.obj:get_pos(), e.id
		end
	end
end

-- Where a monster says something: its square now, as NetHack has it (its
-- body may still be on its way there - having just teleported next to you,
-- Rodney would be heard from where he was), else its body
local function speaker_pos(m_id)
	if not m_id or m_id <= 0 then
		return nil
	end
	for _, m in ipairs(core.nh_get_all_monsters and core.nh_get_all_monsters() or {}) do
		if m.id == m_id and m.x > 0 then
			return U.tile_center(m.x, m.y, nhv.terrain.stand_y(m.x, m.y) + 1.0)
		end
	end
	local e = nhv.mobs and nhv.mobs.mons["id" .. m_id]
	return e and e.obj and e.obj:get_pos()
end

local function voice_for_text(text)
	text = text:gsub('^"', ""):gsub('"$', "")
	for _, sp in ipairs(spoken_pats) do
		if text:find(sp[1]) then
			return sp[2]
		end
	end
end

local pending_quest = nil -- quest message whose text arrives next
-- a quest message SAM will read: its lines are collected as they arrive
-- (a text window, or messages in the same batch), then read as one
local sam_quest = nil -- {st=, lines={}, window=bool}

local function finish_sam_quest()
	if sam_quest and #sam_quest.lines > 0 then
		speak_sam(sam_quest.st, table.concat(sam_quest.lines, " "), sam_quest.pos, sam_quest.key)
	end
	sam_quest = nil
end

-- the Oracle's major consultation comes as a text window that opens with
-- one of these: she reads the rest
local ORACLE_INTRO = {
	["The Oracle meditates for a moment and then intones:"] = true,
	["The Oracle scornfully takes all your gold and says:"] = true,
}
local window_first = false -- (a text window just opened: its first line next)

nh.on_event(function(evs)
	local free_action = false
	for _, ev in ipairs(evs) do
		if ev.kind == "text_begin" then
			window_first = true
		elseif ev.kind == "text_line" and window_first then
			window_first = false
			if ORACLE_INTRO[ev.text] and not sam_quest then
				local pos, m_id = oracle_pos()
				local st = sam_settings("The Oracle", {m_id = m_id or 0})
				if st then
					-- (the intro line itself isn't hers to read: begun next)
					sam_quest = {st = st, lines = {}, window = true, pos = pos, skip = 1, key = "The Oracle"}
				end
			end
		end
		if sam_quest then
			if ev.kind == "text_begin" then
				sam_quest.window = true
			elseif ev.kind == "text_line" and sam_quest.window then
				if (sam_quest.skip or 0) > 0 then
					sam_quest.skip = sam_quest.skip - 1
				else
					table.insert(sam_quest.lines, ev.text)
				end
			elseif ev.kind == "text_end" and sam_quest.window then
				finish_sam_quest()
			elseif ev.kind == "message" and not sam_quest.window then
				table.insert(sam_quest.lines, ev.text)
			end
		end
		-- (Snickersnee's free hit: the sounds after it, of the same action,
		-- are a free action's - hitting, killing)
		if ev.kind == "combat" and ev.text:match("^upole 1 ") then
			free_action = true
		end
		if ev.kind == "sound" then
			local parts = {}
			for part in (ev.text .. "|"):gmatch("([^|]*)|") do
				parts[#parts + 1] = part
			end
			local kind = parts[1]
			if kind == "effect" then
				local id, vol = parts[2], tonumber(parts[3]) or 100
				-- where it happens, if NetHack knows (else centred on the hero)
				local pos = sound.where(tonumber(parts[4]), tonumber(parts[5]), tonumber(parts[6]))
				local semi = squeak_semitone(id or "")
				local entry = sound.cfg.hooks[id]
				if semi and not (entry and entry.sounds and #entry.sounds > 0) then
					-- a squeaky board's own note (unless the editor gives the
					-- hook a sound of its own)
					if nhv.effects then
						nhv.effects.hook(id, {volume = vol, pos = pos})
					end
					sound.note(BOARD_PROGRAM, semi, 0.35 + 0.65 * math.min(100, vol) / 100, pos)
				else
					sound.hook(id, {volume = vol, pos = pos, free = free_action})
				end
			elseif kind == "notes" then
				-- an instrument played: its notes (improvised or a tune)
				sound.tune(tonumber(parts[2]) or 74, parts[4] or "", tonumber(parts[3]) or 50)
			elseif kind == "verbal" then
				local text = table.concat(parts, "|", 7)
				local id = voice_for_text(text)
				local who = {m_id = tonumber(parts[2]) or 0, female = parts[4] == "1"}
				local body = speaker_pos(who.m_id)
				if id then
					play_voice(id, body, text, who)
				elseif SPEAKER_BY_MON[parts[3] or ""] then
					-- (not in the catalog: SAM reads it in its speaker's voice)
					local st = sam_settings(SPEAKER_BY_MON[parts[3]], who)
					if st then
						speak_sam(st, text, body, who.m_id > 0 and ("mon" .. who.m_id) or parts[3])
					end
				end
			elseif kind == "quest" then
				local ids = quest_ids[(parts[2] or "") .. "/" .. (parts[3] or "")]
				local st = ids and sam_for(ids[1])
				if st then
					finish_sam_quest()
					sam_quest = {st = st, lines = {}, window = false, key = "quest"}
				elseif ids and #ids == 1 then
					play_voice(ids[1])
				elseif ids then
					pending_quest = ids
				end
			end
		elseif (ev.kind == "message" or ev.kind == "text_line") and pending_quest then
			-- one of several lines of a quest message: find which
			for _, id in ipairs(pending_quest) do
				local e = dialogue[id]
				if e and ev.text:find(to_pattern(e.text:gsub('^"', ""):gsub('"$', ""))) then
					play_voice(id)
					pending_quest = nil
					break
				end
			end
		elseif ev.kind == "message" then
			-- arrival narration and ambient lines have no speaker hook (SAM
			-- doesn't read the ambient ones - "You hear faint splashing.":
			-- ordinary messages; a recording of one still plays)
			local id = voice_for_text(ev.text)
			local e = id and dialogue[id]
			if e and e.category ~= "spoken" and not sam_quest
					and not (e.category == "ambient" and sam_for(id)) then
				play_voice(id, nil, ev.text)
			end
		end
	end
	-- a quest message given as plain messages ends with its batch
	if sam_quest and not sam_quest.window then
		finish_sam_quest()
	end
end)

-- ---------------------------------------------------------------- acoustics
-- The reverb of the place the hero is in (the engine's nhv_acoustics:
-- every sound but music goes through it). The kind of place is the first
-- that applies in catalog/acoustics.json (engulfed, underwater, temple,
-- shop, the branch, then a corridor, open sky or a room, measured); with
-- "follow" the reverb rings longer the bigger the space measured around
-- the hero. The editor's Acoustics tab saves changes in config.json.
local ACOUSTICS = {kinds = {}}
do
	local f = io.open(MODPATH .. DIR_DELIM .. "catalog" .. DIR_DELIM .. "acoustics.json", "rb")
	if f then
		ACOUSTICS = core.parse_json(f:read("*a")) or ACOUSTICS
		f:close()
	end
end
local BRANCH_KIND = {
	["The Gnomish Mines"] = "mines", ["Sokoban"] = "sokoban", ["The Quest"] = "quest",
	["Fort Ludios"] = "ludios", ["Gehennom"] = "gehennom", ["Vlad's Tower"] = "vlad",
	["The Elemental Planes"] = "planes",
}

-- a kind's settings: the defaults, with the editor's changes over them
local function kind_settings(key)
	for _, k in ipairs(ACOUSTICS.kinds or {}) do
		if k.key == key then
			local own = (sound.cfg.acoustics or {})[key] or {}
			local function pick(field)
				if own[field] ~= nil then
					return own[field]
				end
				return k[field]
			end
			return {preset = pick("preset") or "", wet = tonumber(pick("wet")) or 0, follow = pick("follow")}
		end
	end
end

-- how far it is to a wall along a direction (nodes, up to max)
local function reach(from, dir, max)
	for d = 0.5, max, 0.5 do
		if stops_sound(core.get_node(vector.round(vector.add(from, vector.multiply(dir, d)))).name) then
			return d
		end
	end
	return max
end

local DIRS = {}
for i = 0, 7 do
	local a = i * math.pi / 4
	DIRS[#DIRS + 1] = vector.new(math.cos(a), 0, math.sin(a))
end
local UP = vector.new(0, 1, 0)

-- the space around the hero: average distance to the walls (in squares),
-- and whether there's a ceiling
local function measure(p)
	local eye = vector.offset(p:get_pos(), 0, p:get_properties().eye_height or 1.6, 0)
	local sum = 0
	for _, dir in ipairs(DIRS) do
		sum = sum + reach(eye, dir, 30)
	end
	return sum / #DIRS / U.TILE, reach(eye, UP, 18) < 18
end

local last_acoustics = nil
local acoustics_t = 0
local function update_acoustics(dtime)
	acoustics_t = acoustics_t + dtime
	if acoustics_t < 0.5 then
		return
	end
	acoustics_t = 0
	local p = player()
	local h = nh.snap and nh.snap.hero
	local setting = "preset=NONE"
	if p and h then
		local radius, roofed = measure(p)
		local chosen
		local function try(key, when)
			if chosen or not when then
				return
			end
			local k = kind_settings(key)
			if k and k.preset ~= "" then
				chosen = k
			end
		end
		try("swallowed", U.has(h.flags, U.HERO.SWALLOWED))
		try("underwater", U.has(h.flags, U.HERO.UNDERWATER))
		try("temple", U.has(h.flags, U.HERO.INTEMPLE))
		try("shop", U.has(h.flags, U.HERO.INSHOP))
		local branch = BRANCH_KIND[h.dungeon_name or ""]
		try(branch or "", branch ~= nil)
		-- (a hallway: NetHack's corridor squares - not the edge of a room,
		-- however close its walls)
		local typ = h.x and nh.snap.map.typ[U.idx(h.x, h.y)]
		try("corridor", typ == U.TYP.CORR or typ == U.TYP.SCORR)
		try("open", not roofed)
		try("room", true)
		if chosen then
			-- bigger spaces ring longer: about 4 squares across is the preset's own
			local decay = chosen.follow and math.max(0.5, math.min(2.2, radius / 4)) or 1
			setting = ("preset=%s;decay=%.2f;wet=%.2f"):format(chosen.preset, decay, chosen.wet)
		end
	end
	if setting ~= last_acoustics then
		last_acoustics = setting
		core.settings:set("nhv_acoustics", setting)
	end
end
core.register_globalstep(update_acoustics)
core.register_on_shutdown(function()
	core.settings:set("nhv_acoustics", "preset=NONE")
end)

-- ---------------------------------------------------------------- state hooks
local last = nil
nh.on_snapshot(function(snap)
	if not snap then
		-- the game ended: the music stops; if you died, music_death starts
		-- with your gravestone (ui.show_death) - not saving, quitting...
		sound.died = last and U.has(last.flags or 0, U.HERO.DEAD) or false
		sound.stop_music()
		last = nil
		return
	end
	local h = snap.hero
	local prev = last
	last = {hp = h.hp, hpmax = h.hpmax, gold = h.gold, hunger = h.hunger, flags = h.flags,
		depth = h.depth, ledger = h.ledger, ninv = #snap.inventory}
	sound.died = false
	local music = music_for(h)
	if music then
		sound.set_music(music)
	elseif sound.music then
		sound.stop_music()
	end
	if not prev then
		return
	end
	if h.ledger ~= prev.ledger then
		sound.hook(h.depth >= prev.depth and "level_enter_down" or "level_enter_up")
	end
	if h.hp < prev.hp then
		sound.hook("hero_hurt")
		if h.hp > 0 and h.hp < h.hpmax / 3 and prev.hp >= prev.hpmax / 3 then
			sound.hook("hp_low")
		end
	elseif h.hp >= prev.hp + math.max(3, h.hpmax / 5) then
		sound.hook("hero_heal")
	end
	if h.gold > prev.gold then
		sound.hook("gold_gain")
	elseif h.gold < prev.gold then
		sound.hook("gold_loss")
	end
	if h.hunger ~= prev.hunger then
		local H = {[2] = "hunger_hungry", [3] = "hunger_weak", [4] = "hunger_fainting"}
		if H[h.hunger] and h.hunger > prev.hunger then
			sound.hook(H[h.hunger])
		end
	end
	if #snap.inventory > prev.ninv then
		sound.hook("item_pickup")
	elseif #snap.inventory < prev.ninv then
		sound.hook("item_drop")
	end
	local function flag_changed(bit, on_hook, off_hook)
		local was, is = U.has(prev.flags, bit), U.has(h.flags, bit)
		if is and not was and on_hook then
			sound.hook(on_hook)
		elseif was and not is and off_hook then
			sound.hook(off_hook)
		end
	end
	flag_changed(U.HERO.BLIND, "blind_start", "blind_end")
	flag_changed(U.HERO.HALLU, "hallucination_start", "hallucination_end")
	flag_changed(U.HERO.FAST, "speed_fast", nil)
	flag_changed(U.HERO.LEVITATE, "levitation_start", "levitation_end")
	flag_changed(U.HERO.DIED, "death", nil) -- (dying: not quitting, winning...)
end)

-- before the dungeon exists (character selection)
core.register_on_joinplayer(function()
	core.after(1, function()
		if not nh.snap then
			sound.set_music("music_title")
		end
	end)
end)

return sound
