-- A new character's beginning: NetHack's legacy, narrated.
--
-- Start on the new character screen: the game begins behind the scene
-- (showroom.lua) - your character on the pedestal, now in the middle at
-- the bottom of the screen - and once NetHack has made your character
-- (Random picked: your god and your title are known), the story of the
-- Amulet is told at the top of the screen, a paragraph at a time, read
-- by the Narrator (SAM: the voice casting), the title's music going on.
-- Then the screen goes white, then black, and you're on the first level
-- as it fades in. Enter skips it ("Press Enter to skip", bottom right).
--
--   intro.start(player)   begin (the game is started just after)
--   intro.active          true while it's on

local nh = nhv.nh

local intro = {active = false}
nhv.intro = intro

local SPEAKER = "Narrator"
local WRAP = 64            -- characters a line
local GAP_S = 0.7          -- after each paragraph
local READ_S = 0.055       -- a character, with the voices off (reading time)
local MIN_S = 2.5          -- a paragraph, at the least
local WAIT_MAX_S = 15      -- for NetHack to make the character
local WHITE_S, HOLD_S, BLACK_S = 1.6, 0.5, 1.4

-- NetHack's legacy (its "It is written in the Book of...")
local function story(god, rank)
	return {
		("It is written in the Book of %s:"):format(god),
		"After the creation, the cruel god Moloch rebelled against the authority of Marduk"
			.. " the Creator. Moloch stole from Marduk the most powerful of all the artifacts"
			.. " of the gods, the Amulet of Yendor, and he hid it in the dark cavities of"
			.. " Gehennom, the Under World, where he now lurks, and bides his time.",
		("Your god %s seeks to possess the Amulet, and with it to gain deserved ascendance"
			.. " over other gods."):format(god),
		("You, a newly trained %s, have been heralded from birth as the instrument of %s."
			.. " You are destined to recover the Amulet for your deity, or die in the attempt."
			.. " Your hour of destiny has come. For the sake of us all: Go bravely with %s!")
			:format(rank, god, god),
	}
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
	lines[#lines + 1] = line
	return table.concat(lines, "\n")
end

local run = nil -- {t0=, paras=, shown=, next_t=, phase=, ids={}}
local FORM = "nhv:intro"

-- "Press Enter to skip": a see-through screen over it all (it hears Enter)
local function skip_formspec()
	return "formspec_version[6]size[5,1]position[1,1]anchor[1,1]padding[0.02,0.02]no_prepend[]"
		.. "bgcolor[#00000000;false]allow_close[false]"
		.. "label[0.4,0.5;" .. core.colorize("#AAAAAA", "Press Enter to skip") .. "]"
end

local function set_text(player)
	local parts = {}
	for i = 1, run.shown do
		parts[i] = wrap(run.paras[i])
	end
	local text = table.concat(parts, "\n\n")
	for _, id in ipairs(run.ids) do
		player:hud_change(id, "text", text)
	end
end

function intro.start(player)
	intro.active = true
	run = {t0 = core.get_us_time(), shown = 0, phase = "wait", ids = {}}
	nhv.showroom.intro(player)
	-- the narration's text: white, with a shadow, at the top in the middle
	for _, l in ipairs({{0x000000, 2}, {0xFFFFFF, 0}}) do
		local id = player:hud_add({
			type = "text", position = {x = 0.5, y = 0.05}, alignment = {x = 0, y = 1},
			offset = {x = l[2], y = l[2]}, size = {x = 1, y = 0}, number = l[1], text = "",
			z_index = 60,
		})
		run.ids[#run.ids + 1] = id
		nhv.showroom.keep[id] = true
	end
	core.show_formspec(player:get_player_name(), FORM, skip_formspec())
end

-- to white (told, or skipped)
local function to_white(player)
	core.close_formspec(player:get_player_name(), FORM)
	nhv.hud.fade(1, WHITE_S, "#FFFFFF")
	run.phase, run.next_t = "white", core.get_us_time() + (WHITE_S + HOLD_S) * 1e6
end

core.register_on_player_receive_fields(function(player, formname, fields)
	if formname ~= FORM then
		return false
	end
	if run and fields.key_enter and (run.phase == "wait" or run.phase == "tell") then
		nhv.sound.hush("intro")
		for _, id in ipairs(run.ids) do
			player:hud_change(id, "text", "")
		end
		to_white(player)
	elseif run and (run.phase == "wait" or run.phase == "tell") then
		-- (Esc, a click: it stays)
		core.show_formspec(player:get_player_name(), FORM, skip_formspec())
	end
	return true
end)

local function finish(player)
	for _, id in ipairs(run.ids) do
		nhv.showroom.keep[id] = nil
		player:hud_remove(id)
	end
	run = nil
	intro.active = false
	-- (under the black: onto the level, where NetHack put you - a clear
	-- spot, the level built by now - with its music)
	local at = nhv.player.arrived_at
	nhv.showroom.hide(player)
	if at then
		player:set_pos(nhv.player.free_spot(at))
	end
	nhv.sound.level_music()
	-- (the level fades in: when it's all loaded if it's still loading -
	-- player.lua - or now)
	if not nhv.player.level_hold then
		nhv.hud.fade(0, 1.2)
	end
end

core.register_globalstep(function()
	if not run then
		return
	end
	local player = nhv.player.get()
	if not player then
		run, intro.active = nil, false
		return
	end
	local now = core.get_us_time()
	if run.phase == "wait" then
		-- (NetHack making the character: then the god and the title are known)
		local h = nh.snap and nh.snap.hero
		local ready = h and h.god and h.god ~= "" and h.rank and h.rank ~= ""
		if ready or now - run.t0 > WAIT_MAX_S * 1e6 then
			run.paras = story(ready and h.god or "your god", ready and h.rank or "hero")
			run.phase, run.next_t = "tell", now
		end
	elseif run.phase == "tell" and now >= run.next_t then
		if run.shown < #run.paras then
			run.shown = run.shown + 1
			set_text(player)
			local text = run.paras[run.shown]
			local secs = nhv.sound.say_seconds(SPEAKER, text)
			if secs > 0 then
				nhv.sound.say(SPEAKER, text, "intro")
			else
				secs = math.max(MIN_S, #text * READ_S)
			end
			run.next_t = now + (secs + GAP_S) * 1e6
		else
			to_white(player)
		end
	elseif run.phase == "white" and now >= run.next_t then
		nhv.hud.fade(1, BLACK_S, "#000000", "#FFFFFF")
		run.phase, run.next_t = "black", now + (BLACK_S + 0.2) * 1e6
	elseif run.phase == "black" and now >= run.next_t then
		finish(player)
	end
end)

return intro
