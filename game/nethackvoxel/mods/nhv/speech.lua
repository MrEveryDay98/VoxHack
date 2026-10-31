-- Spoken lines (NetHack's verbalize: a shopkeeper's greeting, the watch's
-- warnings, a priest, the Oracle, your god...) aren't put with the other
-- messages but where they're said:
--   above the speaker's head while you can see them (Options > Speech
--   above heads), else
--   in a box of their own on the right of the screen (Options > Spoken
--   lines), with who said it - once you've seen them (the name as NetHack
--   would put it: "Asidonhopo", "The watchman"); a voice you haven't seen
--   is just its words.
-- Both off, they're messages like any other. They're always in the message
-- log (T). Spoken in Animalese or Beeps and boops (Options > Voices), the
-- words come up a letter at a time as they're said (Options > Typing speed)
-- - the prologue's and the intro's too (speech.typer: intro_play.lua,
-- intro.lua).
--
-- NetHack puts a spoken line as a message (with its quotes), then the
-- sound event saying who said it (nhv_sound.c's "verbal|..."): hud.lua
-- asks speech.take whether a message is one.

local speech = {}
nhv.speech = speech

local theme = nhv.theme

local BOX_LINES = 3      -- spoken lines kept in the box
local BOX_WRAP = 36      -- characters a line in the box
local HEAD_WRAP = 28     -- characters a line over a head
local HEAD_SEEN = 24     -- nodes: farther, it's said into the box
local LETTER_S = 0.075   -- a letter of Animalese at its own pace (sam_voice.h)

-- Options (graphics.lua)
function speech.box_on()
	return core.settings:get_bool("nhv_speech_box", true)
end
function speech.heads_on()
	return core.settings:get_bool("nhv_speech_heads", true)
end
-- Typing speed: a letter's length, in percent (Animalese, beeps)
function speech.letter_pct()
	return tonumber(core.settings:get("nhv_speech_speed")) or 100
end
-- whether lines come up a letter at a time (the voices that say them so)
function speech.typed()
	local m = nhv.sound and nhv.sound.voice_mode()
	return m == "animalese" or m == "beeps"
end

speech.known = {} -- m_id -> name, once you've seen them speak
local lines = {}  -- {id, label, text, wrapped, t0, times, head, obj, ttl}

-- the text as said: spaces as one, no quotes (as sound.lua's voices have it)
function speech.clean(text)
	return (text:gsub("%s+", " "):gsub('^%s*"', ""):gsub('"%s*$', ""):gsub("^%s+", ""):gsub("%s+$", ""))
end

-- the same text with some spaces made line breaks (every character where
-- it was: what's been said so far is just its start)
local function wrap(text, width)
	local out, col, last_space = {}, 0, nil
	for i = 1, #text do
		local c = text:sub(i, i)
		out[i] = c
		col = col + 1
		if c == " " then
			last_space = i
		end
		if col > width and last_space then
			out[last_space] = "\n"
			col = i - last_space
			last_space = nil
		end
	end
	return table.concat(out)
end

-- When each character of a line is said, in seconds from its start, the
-- way the engine says it (sam_voice.cpp's script): a letter one letter's
-- time, a number its word's letters in Animalese (one beep a digit), a
-- full stop three, a comma two, a space one - the gaps never piling up.
local DIGIT_LEN = {[0] = 4, 3, 3, 5, 4, 4, 3, 5, 5, 4}
function speech.times(text, unit, spell_digits)
	local out, slots, trailing, in_word = {}, 0, 0, false
	local function gap(n)
		in_word = false
		if slots == 0 then
			return
		end
		if trailing < n then
			slots = slots + (n - trailing)
			trailing = n
		end
	end
	for i = 1, #text do
		local c = text:sub(i, i)
		out[i] = slots * unit
		if c:match("%a") then
			slots, trailing, in_word = slots + 1, 0, true
		elseif c:match("%d") then
			slots, trailing, in_word = slots + (spell_digits and DIGIT_LEN[tonumber(c)] or 1), 0, true
		elseif c == "'" and in_word then -- luacheck: ignore 542
			-- (one word: don't)
		elseif c:match("[%.!%?]") then
			gap(3)
		elseif c:match("[,;:%-]") then
			gap(2)
		else
			gap(1)
		end
	end
	return out, slots * unit
end

-- the speaker's body, if you can see it now - in plain view, near enough,
-- in front of you - else nil
local function seen_body(id)
	local e = id and id > 0 and nhv.mobs and nhv.mobs.mons["id" .. id]
	local player = nhv.player.get()
	if not (e and e.obj and player) or e.ghost or e.silhouette or e.occluded or (e.mon and e.mon.noclip_only) then
		return nil
	end
	local p = e.obj:get_pos()
	if not p then
		return nil
	end
	local eye = vector.add(player:get_pos(), vector.new(0, player:get_properties().eye_height or 1.6, 0))
	local head = vector.add(p, vector.new(0, (e.h or 1) / 2, 0))
	local to = vector.subtract(head, eye)
	local d = vector.length(to)
	if d > HEAD_SEEN or (d > 1.5 and vector.dot(vector.divide(to, d), player:get_look_dir()) < 0.55) then
		return nil
	end
	if nhv.mobs.wall_between and nhv.mobs.wall_between(eye, head) then
		return nil
	end
	return e.obj
end

local function set_head(obj, text)
	if obj and obj:get_pos() then
		obj:set_nametag_attributes({text = text, color = "#FFFFFF", bgcolor = text ~= "" and "#000000B0" or "#00000000"})
	end
end

local function drop(ln)
	if ln.obj then
		set_head(ln.obj, "")
		ln.obj = nil
	end
end

-- Is this message (evs[i]) a spoken line? If it is, and it's shown here,
-- true: hud.lua leaves it out of the messages (but not the log).
function speech.take(evs, i)
	if not (speech.box_on() or speech.heads_on()) then
		return false
	end
	local said = speech.clean(evs[i].text)
	for j = i + 1, math.min(#evs, i + 4) do
		local ev = evs[j]
		if ev.kind == "sound" and ev.text:find("^verbal|") then
			local parts = {}
			for part in (ev.text .. "|"):gmatch("([^|]*)|") do
				parts[#parts + 1] = part
			end
			local vt = speech.clean(table.concat(parts, "|", 9))
			-- (a long one is cut short in the event)
			if vt ~= "" and (vt == said or (#vt >= 120 and said:sub(1, #vt) == vt)) then
				return speech.add(tonumber(parts[2]) or 0, parts[3] or "", parts[7] == "1", parts[8] or "", said)
			end
		end
	end
	return false
end

function speech.add(id, who, seen, name, text)
	if seen and name ~= "" and id > 0 then
		speech.known[id] = name
	end
	local label = (who == "deity" and "A god") or (who == "artifact" and "An artifact") or speech.known[id]
	local obj = speech.heads_on() and seen_body(id)
	if not obj and not speech.box_on() then
		return false
	end
	-- (a speaker's new line over their head takes the place of their last)
	for k = #lines, 1, -1 do
		if obj and lines[k].obj == obj then
			drop(lines[k])
			table.remove(lines, k)
		end
	end
	lines[#lines + 1] = {id = id, label = label, text = text, tp = speech.typer(text),
		head = obj and true or false, obj = obj or nil}
	speech.refresh()
	return true
end

-- A line typed a letter at a time as it's said (Animalese, beeps; with
-- the other voices it's all there at once). display: as it's shown (line
-- breaks where it had spaces: the same characters); spoken: as its voice
-- was given it (sound.spoken's key), if not the same
function speech.typer(display, spoken)
	return {display = display, key = speech.clean(spoken or display), t0 = core.get_us_time() / 1e6}
end

local function letter_s()
	return LETTER_S * speech.letter_pct() / 100
end

-- when its letters come: known once its voice has started (sound.lua says
-- when, and at what pace - it may start a moment after the words are put
-- up: till then, nothing's shown), or it's plainly not going to
local function resolve(tp, now)
	if tp.times ~= nil then
		return true
	end
	if not speech.typed() then
		tp.times, tp.length = false, 0
		return true
	end
	local said = nhv.sound.spoken[tp.key]
	said = said and math.abs(said.t - tp.t0) < 1 and said
	if not said and now - tp.t0 < 0.2 then
		return false
	end
	local unit = letter_s()
	if said then
		unit, tp.t0 = said.unit, said.t
	end
	tp.times, tp.length = speech.times(tp.display, unit, nhv.sound.voice_mode() == "animalese")
	return true
end

-- what's been said of it by now, and whether that's all of it. Text
-- centred where it's shown keeps its place as it's said: the lines yet to
-- come there already, empty
function speech.typed_padded(tp, now)
	local text, done = speech.typed_text(tp, now)
	local _, more = tp.display:sub(#text + 1):gsub("\n", "")
	return text .. ("\n"):rep(more), done
end

function speech.typed_text(tp, now)
	now = now or core.get_us_time() / 1e6
	if not resolve(tp, now) then
		return "", false
	elseif not tp.times then
		return tp.display, true
	end
	local t, n = now - tp.t0, tp.n or 0
	while n < #tp.display and tp.times[n + 1] <= t do
		n = n + 1
	end
	tp.n = n
	return tp.display:sub(1, n), n == #tp.display
end

-- how long typing a line with no voice takes (0: not typed)
function speech.typing_seconds(text)
	if not speech.typed() then
		return 0
	end
	local _, length = speech.times(text, letter_s(), nhv.sound.voice_mode() == "animalese")
	return length
end

-- ---------------------------------------------------------------- the box
local ids = {}
local shown_sig

local function remove_box(player)
	for _, id in pairs(ids) do
		player:hud_remove(id)
	end
	ids = {}
end

local function draw_box(player, list)
	local sig = {}
	for _, it in ipairs(list) do
		sig[#sig + 1] = (it.label or "") .. "\1" .. it.shown
	end
	sig = table.concat(sig, "\2") .. (theme.retro() and "r" or "m") .. theme.box_scale()
	if sig == shown_sig then
		return
	end
	shown_sig = sig
	remove_box(player)
	if #list == 0 then
		return
	end
	local k = theme.box_scale()
	local line_h = math.ceil((theme.retro() and 15 or 18) * k)
	local char_w = (theme.retro() and 8 or 8.6) * k
	local pad = math.ceil(8 * k)
	local w = math.ceil(BOX_WRAP * char_w) + pad * 2
	local y = pad
	local texts = {}
	for n, it in ipairs(list) do
		if n > 1 then
			y = y + math.ceil(line_h * 0.6)
		end
		if it.label then
			texts[#texts + 1] = {y = y, text = it.label, color = 0xFFD040}
			y = y + line_h
		end
		local _, breaks = it.full:gsub("\n", "")
		texts[#texts + 1] = {y = y, text = it.shown, color = 0xFFFFFF}
		y = y + line_h * (breaks + 1)
	end
	local h = y + pad
	local POS, X = {x = 1, y = 0.36}, -16
	ids.bg = player:hud_add({
		type = "image", position = POS, alignment = {x = -1, y = 1}, offset = {x = X, y = 0},
		scale = {x = 1, y = 1}, z_index = 30,
		-- (the same as over a head: set_head)
		text = ("[fill:%dx%d:#000000B0"):format(w, h),
	})
	for n, t in ipairs(texts) do
		ids["t" .. n] = player:hud_add({
			type = "text", position = POS, alignment = {x = 1, y = 1},
			offset = {x = X - w + pad, y = t.y}, number = t.color, text = t.text, z_index = 31,
		})
	end
end

-- ---------------------------------------------------------------- each step
function speech.refresh()
	local player = nhv.player.get()
	if not player then
		return
	end
	local now = core.get_us_time() / 1e6
	local box = {}
	for k = #lines, 1, -1 do
		local ln = lines[k]
		-- (said, then a while to read it: longer for a long one)
		local ttl = resolve(ln.tp, now) and ln.tp.length + math.min(9, 3 + #ln.text * 0.05) or math.huge
		if now - ln.tp.t0 > ttl then
			drop(ln)
			table.remove(lines, k)
		elseif ln.head then
			-- (out of sight: on into the box - or stays up, unseen, if there's no box)
			local obj = seen_body(ln.id)
			if obj ~= ln.obj then
				drop(ln)
				if obj then
					ln.obj = obj
				elseif speech.box_on() then
					ln.head = false
				end
			end
		end
	end
	for _, ln in ipairs(lines) do
		ln.wrapped = ln.wrapped or {head = wrap(ln.text, HEAD_WRAP), box = wrap(ln.text, BOX_WRAP)}
		local n = #speech.typed_text(ln.tp, now)
		local _, more = ln.wrapped.head:sub(n + 1):gsub("\n", "")
		if ln.head then
			if ln.obj then
				-- (centred over the head: the lines to come there already)
				local text = ln.wrapped.head:sub(1, n) .. ("\n"):rep(more)
				if text ~= ln.on_head then
					ln.on_head = text
					set_head(ln.obj, text)
				end
			end
		else
			box[#box + 1] = {label = ln.label, shown = ln.wrapped.box:sub(1, n), full = ln.wrapped.box}
		end
	end
	while #box > BOX_LINES do
		table.remove(box, 1)
	end
	-- (not over the title, a menu or the console)
	local covered = (nhv.title and nhv.title.open) or (nhv.ui and (nhv.ui.chat_open or nhv.ui.menu_open))
		or (nhv.guide and nhv.guide.open)
	draw_box(player, covered and {} or box)
end

local step_t = 0
core.register_globalstep(function(dtime)
	step_t = step_t + dtime
	if step_t < 0.03 or (#lines == 0 and not shown_sig) then
		return
	end
	step_t = 0
	speech.refresh()
	if #lines == 0 then
		shown_sig = nil
	end
end)

-- (options changed, a new level, the game left: start clear)
function speech.clear()
	for _, ln in ipairs(lines) do
		drop(ln)
	end
	lines = {}
	local player = nhv.player.get()
	if player then
		remove_box(player)
	end
	shown_sig = nil
end

core.register_on_leaveplayer(function()
	lines, ids, shown_sig = {}, {}, nil
end)

return speech
