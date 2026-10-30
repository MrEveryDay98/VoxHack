-- The opening: before the title, the camera flies through a forest along a
-- path built in the intro editor (intro_editor.lua), the Narrator (or
-- whoever's set) saying a line at each point, its words at the bottom of
-- the screen. Nothing else: no HUD, no control - Enter skips it.
--
-- The editor saves the forest (mod_data/nhv/intro/forest.mts) and its path
-- and signs (intro.json): the game puts the forest up out of the way
-- (ORIGIN: once, and again when it's saved anew) and plays it there.
--
-- Its time of day: as set in the editor (/intro_time) - the sky's sun,
-- moon and stars, and the light, as then. Its fog: its own, if it's set
-- one (/intro_fog: colour, how far you see, where it starts), or the game's.
--
-- Its music: the hook music_opening (the VoxHack Editor's Sound tab), or
-- the title's if that has none; the title goes on with its own after.
--
-- At each camera point: it fades in as the camera gets there (from black or
-- white, or not; as the last point faded out if it isn't said - the first:
-- from black), and its line starts; it waits (delay), then goes on to the
-- next point - gliding there (in the line's time, or so many seconds),
-- cutting to it after as long, or fading out to black or white for as long
-- and cutting to it. The VoxHack engine flies the camera
-- (core.nhv_camera_path: smooth, every frame); this times the rest.
--
--   intro_play.ready()                the game has an opening to play
--   intro_play.start_game(player, done)  put the forest up, play it, then done()
--   intro_play.preview(player, data, done)  the editor's: play this, where it is
--   intro_play.active                 true while it plays

local intro_play = {active = false}
nhv.intro_play = intro_play

local DATA_DIR = core.get_mod_data_path() .. DIR_DELIM .. "intro"
local SCHEMATIC = DATA_DIR .. DIR_DELIM .. "forest.mts"
local JSON = DATA_DIR .. DIR_DELIM .. "intro.json"
intro_play.DATA_DIR, intro_play.SCHEMATIC, intro_play.JSON = DATA_DIR, SCHEMATIC, JSON

-- where the game puts the forest: far from the levels and the title's spot
local ORIGIN = vector.new(-2048, 0, -2048)
local FADE_S = 0.8     -- a fade to black or white (and back)
local OPEN_S = 1.0     -- the first fade in
local CLOSE_S = 1.2    -- after the last line, then the fade out
local READ_S = 0.055   -- a character of a line, with the voices off
local MIN_LINE_S = 2.0
local WRAP = 60

local storage = core.get_mod_storage()

local function read_json()
	local f = io.open(JSON, "r")
	if not f then
		return nil
	end
	local data = core.parse_json(f:read("*a") or "")
	f:close()
	return type(data) == "table" and type(data.points) == "table" and #data.points > 0 and data or nil
end

function intro_play.ready()
	if not core.settings:get_bool("nhv_opening", true) or not core.nhv_camera_path then
		return false
	end
	local f = io.open(SCHEMATIC, "rb")
	if not f then
		return false
	end
	f:close()
	return read_json() ~= nil
end

local function wrap(text)
	local lines, line = {}, ""
	for word in text:gmatch("%S+") do
		if line ~= "" and #line + 1 + #word > WRAP then
			lines[#lines + 1] = line
			line = word
		else
			line = line == "" and word or (line .. " " .. word)
		end
	end
	if line ~= "" then
		lines[#lines + 1] = line
	end
	return table.concat(lines, "\n")
end

-- how long a point's line takes to say (or to read, with no voice)
local function line_seconds(p)
	if not p.line or p.line == "" then
		return 0
	end
	local s = nhv.sound and nhv.sound.say_seconds(p.voice or "Narrator", p.line, p.mood ~= "" and p.mood or nil) or 0
	if s > 0 then
		return s, true
	end
	return math.max(MIN_LINE_S, #p.line * READ_S), false
end

-- The timeline: the camera's points (for the engine) and what happens when
-- (lines, fades) - times in seconds from the start; at: added to every
-- point's place (where the forest is)
local COLOR = {black = "#000000", white = "#FFFFFF"}
local function timeline(points, at)
	local cam, events = {}, {}
	local function key(t, p, cut)
		cam[#cam + 1] = {t = t, pos = vector.add(at, p.pos), yaw = p.yaw or 0, pitch = p.pitch or 0, cut = cut}
	end
	local function event(e)
		e.n = #events -- (the order they're put in, for ones at the same time)
		events[#events + 1] = e
	end
	local t = 0
	key(0, points[1])
	local last_out = "black" -- (the screen's black as it starts)
	for i, p in ipairs(points) do
		-- (in: as set - or as the last point went out)
		local fade_in = p.fade_in
		if fade_in == nil then
			fade_in = last_out
		end
		if COLOR[fade_in] then
			-- (that colour now - at once if it isn't already - then from it)
			if fade_in ~= last_out then
				event({t = t, fade = COLOR[fade_in], out = true, dur = 0})
			end
			event({t = t, fade = COLOR[fade_in], out = false})
		elseif last_out then
			event({t = t, fade = COLOR[last_out], out = false, dur = 0})
		end
		if i == 1 and COLOR[fade_in] then
			t = t + OPEN_S
		end
		last_out = nil
		local secs, voiced = line_seconds(p)
		if secs > 0 then
			event({t = t, line = p, voiced = voiced})
			event({t = t + secs + 0.3, line = false, of = p})
		end
		local delay = tonumber(p.delay) or 0
		local move = p.sync ~= false and secs > 0 and secs or (tonumber(p.seconds) or 3)
		key(t, p)
		if delay > 0 then
			key(t + delay, p)
		end
		local nxt = points[i + 1]
		if not nxt then
			t = t + math.max(delay, secs) + CLOSE_S
			event({t = t, fade = "#000000", out = true})
			event({t = t + FADE_S + 0.2, done = true})
			break
		end
		if COLOR[p.transition] then
			-- (it waits, then fades out for the time set - its line's, or
			-- the seconds - and cuts there)
			local out_t = t + delay + math.max(move - FADE_S, 0)
			event({t = out_t, fade = COLOR[p.transition], out = true})
			t = out_t + FADE_S
			key(t, nxt, true)
			last_out = p.transition
		elseif p.transition == "cut" then
			t = t + delay + move
			key(t, nxt, true)
		else
			t = t + delay + move
		end
	end
	table.sort(events, function(a, b)
		if a.t ~= b.t then
			return a.t < b.t
		end
		return a.n < b.n
	end)
	return cam, events
end

local run = nil -- {player=, t0=, events=, next_ev=, ids={}, huds={}, signs={}, done=}

-- the fog as it is now (sky.fog's, or the game's): put on the player
function intro_play.apply_fog(player)
	if nhv.hud and nhv.hud.apply_fog then
		nhv.hud.apply_fog(player)
	elseif nhv.sky then
		nhv.sky.apply(player)
	end
end

-- the opening's music: its own, if it has some, else the title's
local function start_music()
	local sound = nhv.sound
	if not sound then
		return
	end
	local hooks = sound.cfg and sound.cfg.hooks or {}
	local own = hooks.music_opening
	sound.set_music(own and type(own.sounds) == "table" and #own.sounds > 0 and "music_opening" or "music_title")
end

-- the fade (the game's: hud.fade; the intro editor has its own, here)
local function fade(to, seconds, color)
	if nhv.hud and nhv.hud.fade then
		nhv.hud.fade(to, seconds, color)
		return
	end
	local f = run.fade
	local now = core.get_us_time()
	local level = f and (f.from + (f.to - f.from) * math.min(1, (now - f.t0) / math.max(1, f.dur))) or 0
	run.fade = {from = level, to = to, t0 = now, dur = (seconds or 0) * 1e6, color = color or "#000000"}
end
local function draw_fade()
	local f = run.fade
	if not f or not run.fade_id then
		return
	end
	local k = math.min(1, (core.get_us_time() - f.t0) / math.max(1, f.dur))
	local a = math.floor((f.from + (f.to - f.from) * k) * 255 + 0.5)
	local text = a > 0 and ("[fill:16x16:%s^[opacity:%d"):format(f.color, a) or ""
	if text ~= run.fade_text then
		run.fade_text = text
		run.player:hud_change(run.fade_id, "text", text)
	end
end

local FORM = "nhv:opening"

local function skip_formspec()
	return "formspec_version[6]size[5,1]position[1,1]anchor[1,1]padding[0.02,0.02]no_prepend[]"
		.. "bgcolor[#00000000;false]allow_close[false]"
		.. "label[0.4,0.5;" .. core.colorize("#AAAAAA", "Press Enter to skip") .. "]"
end

-- nothing of the HUD showing (but the fade, and the words): every element
-- moved off the screen, put back after (and any made meanwhile)
local function hide_huds(player)
	local keep = {}
	for _, id in ipairs(run.ids) do
		keep[id] = true
	end
	if run.fade_id then
		keep[run.fade_id] = true
	end
	for id, def in pairs(player:hud_get_all() or {}) do
		-- (not the hotbar: off by its flag, below - moved away it's drawn
		-- wrong)
		if def.position and def.position.x ~= 9 and not keep[id] and def.type ~= "hotbar"
				and not (nhv.hud and id == nhv.hud.ids.fade) then
			run.huds[id] = def.position
			player:hud_change(id, "position", {x = 9, y = 9})
		end
	end
end

local function set_words(text)
	for _, id in ipairs(run.ids) do
		run.player:hud_change(id, "text", text)
	end
end

local function finish()
	local player, done = run.player, run.done
	core.nhv_camera_path(nil)
	core.close_formspec(player:get_player_name(), FORM)
	if nhv.sound then
		nhv.sound.hush("opening")
	end
	for _, id in ipairs(run.ids) do
		player:hud_remove(id)
	end
	if run.fade_id then
		player:hud_remove(run.fade_id)
	end
	for id, pos in pairs(run.huds) do
		local def = player:hud_get(id)
		if def and def.position and def.position.x == 9 then
			player:hud_change(id, "position", pos)
		end
	end
	for _, obj in ipairs(run.signs) do
		if obj:get_pos() then
			obj:remove()
		end
	end
	nhv.intro_blocks.sprites({})
	-- (the editor's preview: quiet again; the game's title starts its own)
	if nhv.INTRO_EDITOR and nhv.sound then
		nhv.sound.stop_music()
	end
	player:hud_set_flags({wielditem = run.flags.wielditem, crosshair = run.flags.crosshair,
		hotbar = run.flags.hotbar, healthbar = run.flags.healthbar, breathbar = run.flags.breathbar,
		chat = run.flags.chat, nhv_no_selection = run.flags.nhv_no_selection,
		nhv_camera_lock = false})
	player:set_properties({is_visible = run.visible})
	player:override_day_night_ratio(run.ratio)
	if nhv.sky then
		nhv.sky.scene, nhv.sky.time, nhv.sky.fog = run.scene, run.sky_time, run.fog
		nhv.sky.update()
		intro_play.apply_fog(player)
	else
		player:set_sky(run.sky)
	end
	run = nil
	intro_play.active = false
	if done then
		done(player)
	end
end

-- play these points (and signs), at: where the forest is
local function play(player, data, at, done)
	intro_play.active = true
	run = {player = player, t0 = core.get_us_time(), ids = {}, huds = {}, signs = {}, done = done,
		ratio = player:get_day_night_ratio(), sky = player:get_sky(true),
		sky_time = nhv.sky and nhv.sky.time}
	local cam, events = timeline(data.points, at)
	run.events, run.next_ev = events, 1
	-- the words: white, with a shadow, low in the middle (a longer line goes
	-- further up)
	for _, l in ipairs({{0x000000, 2}, {0xFFFFFF, 0}}) do
		run.ids[#run.ids + 1] = player:hud_add({
			type = "text", position = {x = 0.5, y = 0.9}, alignment = {x = 0, y = -1},
			offset = {x = l[2], y = l[2]}, size = {x = 1, y = 0}, number = l[1], text = "",
			z_index = 60,
		})
	end
	hide_huds(player)
	run.flags = player:hud_get_flags()
	player:hud_set_flags({wielditem = false, crosshair = false, hotbar = false, healthbar = false,
		breathbar = false, chat = false, nhv_no_selection = true, nhv_camera_lock = true})
	run.visible = player:get_properties().is_visible
	player:set_properties({is_visible = false})
	-- (the light of its time of day - noon if it hasn't one; the game's sky -
	-- the "opening" one, the VoxHack Editor's Sky tab)
	player:override_day_night_ratio(nil)
	core.set_timeofday(tonumber(data.time) or 0.5)
	if nhv.sky then
		run.scene = nhv.sky.scene
		nhv.sky.scene = "opening"
		nhv.sky.time = tonumber(data.time) or 0.5
		run.fog = nhv.sky.fog
		nhv.sky.fog = type(data.fog) == "table" and data.fog or nil
		nhv.sky.update()
		intro_play.apply_fog(player)
	else
		player:set_sky({type = "regular", clouds = true})
	end
	if core.nhv_hero_light then
		core.nhv_hero_light(0)
	end
	-- the trees, the monsters and people
	local list = {}
	for _, t in ipairs(data.trees or {}) do
		list[#list + 1] = nhv.intro_blocks.tree(vector.add(at, t))
	end
	for _, f in ipairs(data.figures or {}) do
		list[#list + 1] = {pos = vector.add(at, f.pos), tile = f.tile, texture = f.texture, item = f.item, h = f.h}
	end
	nhv.intro_blocks.sprites(list)
	for _, s in ipairs(data.signs or {}) do
		local obj = nhv.intro_blocks.board(vector.add(at, s.pos), s.dir, s.text)
		if obj then
			run.signs[#run.signs + 1] = obj
		end
	end
	-- (you're out of sight in the middle of it, where all of it is sent to
	-- you - the camera's where the engine says)
	local mid = vector.add(at, vector.divide(vector.add(data.min, data.max), 2))
	player:set_pos(vector.new(mid.x, at.y + data.max.y + 2, mid.z))
	core.nhv_camera_path(cam)
	start_music()
	if not (nhv.hud and nhv.hud.fade) then
		-- (the editor's own fade: over the whole screen, black to start)
		run.fade_id = player:hud_add({
			type = "image", position = {x = 0.5, y = 0.5}, alignment = {x = 0, y = 0},
			scale = {x = -100, y = -100}, text = "", z_index = 50,
		})
		run.fade = {from = 1, to = 1, t0 = core.get_us_time(), dur = 1, color = "#000000"}
	end
	core.show_formspec(player:get_player_name(), FORM, skip_formspec())
end

core.register_on_player_receive_fields(function(player, formname, fields)
	if formname ~= FORM then
		return false
	end
	if run and fields.key_enter and not run.skipping then
		-- (to black, then on)
		run.skipping = true
		if nhv.sound then
			nhv.sound.hush("opening")
		end
		set_words("")
		fade(1, FADE_S)
		local now = (core.get_us_time() - run.t0) / 1e6
		run.events = {{t = now + FADE_S + 0.2, done = true}}
		run.next_ev = 1
	elseif run then
		core.show_formspec(player:get_player_name(), FORM, skip_formspec())
	end
	return true
end)

core.register_globalstep(function()
	if not run then
		return
	end
	if not run.player:is_player() then
		run = nil
		intro_play.active = false
		return
	end
	hide_huds(run.player)
	draw_fade()
	local now = (core.get_us_time() - run.t0) / 1e6
	while run and run.events[run.next_ev] and run.events[run.next_ev].t <= now do
		local ev = run.events[run.next_ev]
		run.next_ev = run.next_ev + 1
		if ev.done then
			finish()
		elseif ev.line ~= nil then
			if ev.line then
				run.saying = ev.line
				set_words(wrap(ev.line.line))
				if ev.voiced and nhv.sound then
					local p = ev.line
					nhv.sound.say(p.voice or "Narrator", p.line, "opening", p.mood ~= "" and p.mood or nil)
				end
			elseif ev.of == run.saying then
				-- (its own line's done - not the next one's, already up)
				run.saying = nil
				set_words("")
			end
		elseif ev.fade then
			fade(ev.out and 1 or 0, ev.dur or FADE_S, ev.fade)
		end
	end
end)

-- the game's: the forest put up where it goes (once - again when the
-- editor's saved it anew), loaded, then played; done(player) after
function intro_play.start_game(player, done)
	local data = read_json()
	if not data then
		done(player)
		return
	end
	local p1 = vector.add(ORIGIN, data.min)
	local p2 = vector.add(ORIGIN, data.max)
	local version = tostring(data.version or "")
	core.emerge_area(p1, p2, function(_, _, left)
		if left > 0 or not player:is_player() then
			return
		end
		if storage:get_string("opening_version") ~= version then
			core.place_schematic(p1, SCHEMATIC, "0", {["nhv:intro_cam"] = "air", ["nhv:intro_sign"] = "air"}, true)
			core.fix_light(p1, p2)
			storage:set_string("opening_version", version)
		end
		play(player, data, ORIGIN, done)
	end)
end

-- the editor's: play these, where they are
function intro_play.preview(player, data, done)
	play(player, data, vector.zero(), done)
end

return intro_play
