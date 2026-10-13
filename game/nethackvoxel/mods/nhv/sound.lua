-- Sound: plays what the sound configuration (made in the sound editor)
-- attaches to each hook.
--
-- Hooks come from code, never from reading messages:
--   * NetHack's own sound effects and the hooks NetHack Voxel added to its
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
local known = {}   -- sound names the client has
for _, f in ipairs(core.get_dir_list(SOUND_DIR, false) or {}) do
	local n = f:match("^(.+)%.ogg$")
	if n then
		known[n] = true
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
	for _, f in ipairs(core.get_dir_list(SOUND_DIR, false) or {}) do
		local n = f:match("^(.+)%.ogg$")
		if n and not known[n] then
			known[n] = true
			core.dynamic_add_media({filepath = SOUND_DIR .. DIR_DELIM .. f}, function() end)
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

-- Play whatever is attached to a hook. opts: volume (0-100), pos.
function sound.hook(id, opts)
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
	if opts.pos then
		params.pos = opts.pos
		params.max_hear_distance = 48
	else
		params.to_player = p:get_player_name()
	end
	core.sound_play(name, params, true)
end

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
				sound.hook(parts[2], {volume = tonumber(parts[3]) or 100})
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
		sound.set_music("music_death")
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
