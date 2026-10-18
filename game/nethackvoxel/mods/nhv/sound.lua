-- Sound: plays what the sound configuration (made in the sound editor)
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
-- changes, so edits in the sound editor apply while playing.

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

local reload_t = 0
core.register_globalstep(function(dtime)
	reload_t = reload_t + dtime
	if reload_t > 2 then
		reload_t = 0
		load_config()
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

-- Play whatever is attached to a hook. opts: volume (0-100), pos.
function sound.hook(id, opts)
	-- (particle effects attach to the same hooks: effects.lua)
	if nhv.effects then
		nhv.effects.hook(id, opts)
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
	else
		params.to_player = p:get_player_name()
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

function sound.note(program, semi, gain)
	local p = player()
	local name = ("nhv_note_%d_%d"):format(program, semi % 12)
	if not known[name] then
		name = ("nhv_note_74_%d"):format(semi % 12) -- (an instrument without notes: flute)
	end
	if not p or not known[name] then
		return
	end
	core.sound_play(name, {to_player = p:get_player_name(),
		gain = gain * ((sound.cfg.master.effects or 100) / 100)})
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
		gain = gain, loop = entry.loop ~= false, fade = 0.5})
end

local DUNGEON_MUSIC = {
	["The Dungeons of Doom"] = "music_dungeon", ["The Gnomish Mines"] = "music_mines",
	["Sokoban"] = "music_sokoban", ["The Quest"] = "music_quest",
	["Fort Ludios"] = "music_ludios", ["Gehennom"] = "music_gehennom",
	["Vlad's Tower"] = "music_vlad", ["The Elemental Planes"] = "music_endgame",
}

local function music_for(h)
	if U.has(h.flags, U.HERO.DEAD) then
		return "music_death"
	elseif U.has(h.flags, U.HERO.INSHOP) and sound.cfg.hooks.music_shop then
		return "music_shop"
	elseif U.has(h.flags, U.HERO.INTEMPLE) and sound.cfg.hooks.music_temple then
		return "music_temple"
	elseif (h.level_desc or ""):find("Astral") and sound.cfg.hooks.music_astral then
		return "music_astral"
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
				table.insert(spoken_pats, {to_pattern(e.text:gsub('^"', ""):gsub('"$', "")), e.id})
			end
		end
	end
end

local function play_voice(id, pos)
	local v = sound.cfg.voices[id]
	local name = v and v.sound
	local p = player()
	if not name or not known[name] or not p then
		return false
	end
	if sound.voice then
		core.sound_stop(sound.voice)
	end
	local gain = (v.volume or 100) / 100 * ((sound.cfg.master.voices or 100) / 100)
	local params = {gain = gain}
	if pos then
		params.pos, params.max_hear_distance = pos, 64
	else
		params.to_player = p:get_player_name()
	end
	sound.voice = core.sound_play(name, params)
	return true
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

nh.on_event(function(evs)
	for _, ev in ipairs(evs) do
		if ev.kind == "sound" then
			local parts = {}
			for part in (ev.text .. "|"):gmatch("([^|]*)|") do
				parts[#parts + 1] = part
			end
			local kind = parts[1]
			if kind == "effect" then
				local id, vol = parts[2], tonumber(parts[3]) or 100
				local semi = squeak_semitone(id or "")
				local entry = sound.cfg.hooks[id]
				if semi and not (entry and entry.sounds and #entry.sounds > 0) then
					-- a squeaky board's own note (unless the editor gives the
					-- hook a sound of its own)
					if nhv.effects then
						nhv.effects.hook(id, {volume = vol})
					end
					sound.note(BOARD_PROGRAM, semi, 0.35 + 0.65 * math.min(100, vol) / 100)
				else
					sound.hook(id, {volume = vol})
				end
			elseif kind == "notes" then
				-- an instrument played: its notes (improvised or a tune)
				sound.tune(tonumber(parts[2]) or 74, parts[4] or "", tonumber(parts[3]) or 50)
			elseif kind == "verbal" then
				local text = table.concat(parts, "|", 7)
				local id = voice_for_text(text)
				local body
				local mon = nhv.mobs and nhv.mobs.mons["id" .. (parts[2] or "")]
				if mon and mon.obj:get_pos() then
					body = mon.obj:get_pos()
				end
				if id then
					play_voice(id, body)
				end
			elseif kind == "quest" then
				local ids = quest_ids[(parts[2] or "") .. "/" .. (parts[3] or "")]
				if ids and #ids == 1 then
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
			-- arrival narration and ambient lines have no speaker hook
			local id = voice_for_text(ev.text)
			if id and dialogue[id] and dialogue[id].category ~= "spoken" then
				play_voice(id)
			end
		end
	end
end)

-- ---------------------------------------------------------------- state hooks
local last = nil
nh.on_snapshot(function(snap)
	if not snap then
		-- the game ended: death music only if you died (not saving, quitting
		-- to the title screen...); otherwise the music just stops
		if last and U.has(last.flags or 0, U.HERO.DEAD) then
			sound.set_music("music_death")
		else
			sound.stop_music()
		end
		last = nil
		return
	end
	local h = snap.hero
	local prev = last
	last = {hp = h.hp, hpmax = h.hpmax, gold = h.gold, hunger = h.hunger, flags = h.flags,
		depth = h.depth, ledger = h.ledger, ninv = #snap.inventory}
	sound.set_music(music_for(h))
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
	flag_changed(U.HERO.DEAD, "death", nil)
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
