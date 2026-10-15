-- HUD: status line, message log and the overhead pixel map.

local U = nhv.util
local nh = nhv.nh
local hud = {
	ids = {},
	messages = {},   -- {text=, t=}
	big_map = false,
	last_map_png = nil,
}
nhv.hud = hud

local MSG_LINES = 6
local MSG_TTL = 12 -- seconds a message stays visible

-- pixel map colours (RGBA bytes)
local COL = {
	unknown = {0, 0, 0, 150},
	floor = {70, 70, 80, 255},
	corridor = {55, 55, 60, 255},
	wall = {150, 150, 160, 255},
	door = {150, 100, 40, 255},
	water = {40, 80, 220, 255},
	lava = {230, 70, 20, 255},
	stairs = {255, 255, 0, 255},
	feature = {0, 200, 200, 255},
	trap = {255, 0, 255, 255},
	object = {60, 200, 60, 255},
	boulder = {200, 200, 200, 255},
	hole = {120, 0, 120, 255},
	monster = {255, 40, 40, 255},
	pet = {255, 150, 150, 255},
	peaceful = {255, 150, 0, 255},
	hero = {255, 255, 255, 255},
}

local function color_for(map, i)
	local gi = nhv.glyph_info(map.glyph[i])
	local k = gi.kind
	if k == "mon" or k == "detected" or k == "ridden" or k == "invis" or k == "warning" then
		return COL.monster
	elseif k == "pet" then
		return COL.pet
	elseif k == "obj" or k == "body" or k == "statue" then
		if core.nh_obj_name(gi.index) == "boulder" then
			return COL.boulder
		end
		return COL.object
	elseif k == "cmap" then
		local n = nhv.cmap_name(gi.index)
		if n == "S_stone" or n == "S_unexplored" then
			return COL.unknown
		elseif n:match("wall") or n:match("corn") or n == "S_tree" or n == "S_bars" then
			return COL.wall
		elseif n:match("door") or n:match("dbridge") then
			return COL.door
		elseif n:match("stair") or n:match("ladder") then
			return COL.stairs
		elseif n == "S_pool" or n == "S_water" then
			return COL.water
		elseif n == "S_lava" or n == "S_lavawall" then
			return COL.lava
		elseif n == "S_hole" or n == "S_trap_door" or n == "S_pit" or n == "S_spiked_pit" then
			return COL.hole
		elseif gi.sym == 94 then
			return COL.trap
		elseif n == "S_corr" or n == "S_litcorr" or n == "S_engrcorr" then
			return COL.corridor
		elseif n == "S_altar" or n == "S_fountain" or n == "S_throne" or n == "S_sink"
				or n == "S_grave" then
			return COL.feature
		elseif n == "S_room" or n == "S_darkroom" or n == "S_engroom" or n == "S_ndoor"
				or n == "S_ice" then
			return COL.floor
		end
		return COL.floor
	end
	return COL.unknown
end

local function map_png(snap)
	local map, h = snap.map, snap.hero
	local data = {}
	for y = 0, U.ROWNO - 1 do
		for x = 0, U.COLNO - 1 do
			local c
			if x == h.x and y == h.y then
				c = COL.hero
			elseif x == 0 then
				c = COL.unknown
			else
				c = color_for(map, U.idx(x, y))
			end
			data[#data + 1] = string.char(c[1], c[2], c[3], c[4])
		end
	end
	local png = core.encode_png(U.COLNO, U.ROWNO, table.concat(data))
	return "[png:" .. core.encode_base64(png)
end

local HUNGER = {[0] = "", "", "Hungry", "Weak", "Fainting", "Fainted", "Starved"}
local ENCUMBRANCE = {[0] = "", "Burdened", "Stressed", "Strained", "Overtaxed", "Overloaded"}

local function status_text(h)
	local conds = {}
	local function add(flag, txt)
		if U.has(h.flags, flag) then
			conds[#conds + 1] = txt
		end
	end
	add(U.HERO.BLIND, "Blind")
	add(U.HERO.HALLU, "Hallu")
	add(U.HERO.CONF, "Conf")
	add(U.HERO.STUN, "Stun")
	add(U.HERO.LEVITATE, "Lev")
	add(U.HERO.FLYING, "Fly")
	add(U.HERO.RIDING, "Ride")
	if HUNGER[h.hunger] and HUNGER[h.hunger] ~= "" then
		conds[#conds + 1] = HUNGER[h.hunger]
	end
	if ENCUMBRANCE[h.encumbrance] and ENCUMBRANCE[h.encumbrance] ~= "" then
		conds[#conds + 1] = ENCUMBRANCE[h.encumbrance]
	end
	local line1 = string.format("%s the %s   St:%s Dx:%d Co:%d In:%d Wi:%d Ch:%d   %s",
		h.name, h.rank, h.str > 18 and (h.str <= 118 and ("18/" .. (h.str - 18)) or tostring(h.str - 100)) or tostring(h.str),
		h.dex, h.con, h.int, h.wis, h.cha, h.align)
	-- (HP and Pw are on the meters, top left)
	local line2 = string.format("%s  $:%d  AC:%d  XL:%d/%d  T:%d  %s",
		h.level_desc, h.gold, h.ac, h.xlvl, h.xp, h.moves,
		table.concat(conds, " "))
	return line1 .. "\n" .. line2
end

local msg_shown
local function update_messages(player)
	local now = core.get_us_time() / 1e6
	-- (while a prompt is up the messages stay: they're often what it's
	-- about, e.g. the hint of what a scroll did when you're asked to name it)
	if nhv.ui.open or nhv.ui.menu_open then
		for _, m in ipairs(hud.messages) do
			m.t = math.max(m.t, now - MSG_TTL + 2)
		end
	end
	while #hud.messages > 0 and now - hud.messages[1].t > MSG_TTL do
		table.remove(hud.messages, 1)
	end
	local lines = {}
	-- (the chat console shows the whole log meanwhile)
	if not nhv.ui.chat_open then
		for _, m in ipairs(hud.messages) do
			lines[#lines + 1] = m.text
		end
	end
	local text = table.concat(lines, "\n")
	if text ~= msg_shown then
		msg_shown = text
		player:hud_change(hud.ids.msg, "text", text)
	end
end

function hud.message(text)
	if not text or text == "" then
		return
	end
	table.insert(hud.messages, {text = text, t = core.get_us_time() / 1e6})
	while #hud.messages > MSG_LINES do
		table.remove(hud.messages, 1)
	end
	local player = nhv.player.get()
	if player and hud.ids.msg then
		update_messages(player)
	end
	-- every message also goes to the chat log: the chat console (T) shows
	-- them all (the chat itself isn't drawn on screen)
	if player then
		core.chat_send_player(player:get_player_name(), text)
	end
end

-- the big map fills most of the window's width (in whole pixels per square)
local function big_map_scale(player)
	local info = core.get_player_window_information(player:get_player_name())
	if not info or not info.size or not info.real_hud_scaling then
		return 10
	end
	local fit = math.min(0.92 * info.size.x / U.COLNO, 0.8 * info.size.y / U.ROWNO)
	return math.max(2, math.floor(fit / info.real_hud_scaling))
end

-- the corner map's pixels per square (Graphics > Map size; 0 hides it)
local function corner_scale()
	return tonumber(core.settings:get("nhv_map_scale")) or 3
end

local function place_map(player)
	if not hud.ids.map then
		return
	end
	if hud.big_map then
		local s = big_map_scale(player)
		player:hud_change(hud.ids.map, "position", {x = 0.5, y = 0.45})
		player:hud_change(hud.ids.map, "alignment", {x = 0, y = 0})
		player:hud_change(hud.ids.map, "scale", {x = s, y = s})
		player:hud_change(hud.ids.map, "offset", {x = 0, y = 0})
	else
		local s = corner_scale()
		player:hud_change(hud.ids.map, "position", {x = 1, y = 0})
		player:hud_change(hud.ids.map, "alignment", {x = -1, y = 1})
		-- (a hidden map is scaled to nothing)
		player:hud_change(hud.ids.map, "scale", {x = s, y = s})
		player:hud_change(hud.ids.map, "offset", {x = -10, y = 10})
	end
end
hud.place_map = place_map

-- the status line's distance from the bottom of the screen (above the hotbar)
function hud.place_status(player, above)
	if hud.ids.status then
		player:hud_change(hud.ids.status, "offset", {x = 0, y = -above})
	end
end

function hud.toggle_map()
	hud.big_map = not hud.big_map
	local player = nhv.player.get()
	if player then
		place_map(player)
	end
end

core.register_on_joinplayer(function(player)
	-- right-click doesn't swing the arm by itself (actions.run swings it)
	-- (clicking doesn't swing the arm by itself: actions.swing does, when an
	-- attack really happens)
	player:hud_set_flags({nhv_no_place_swing = true, nhv_no_dig_swing = true})
	player:hud_set_flags({minimap = false, minimap_radar = false, healthbar = false,
		breathbar = false, basic_debug = false})
	hud.ids.status = player:hud_add({
		type = "text", position = {x = 0.5, y = 1}, alignment = {x = 0, y = -1},
		offset = {x = 0, y = -90}, number = 0xFFFFFF, text = "",
		style = 4, -- monospace
	})
	-- (z_index 1000 and up: the NetHack Voxel build of Luanti draws it
	-- above menus and prompts, so it can be read while answering them)
	hud.ids.msg = player:hud_add({
		type = "text", position = {x = 0.5, y = 0}, alignment = {x = 0, y = 1},
		offset = {x = 0, y = 60}, number = 0xFFFFE0, text = "", z_index = 1000,
	})
	msg_shown = nil
	hud.ids.map = player:hud_add({
		type = "image", position = {x = 1, y = 0}, alignment = {x = -1, y = 1},
		offset = {x = -10, y = 10}, scale = {x = 3, y = 3}, text = "blank.png",
	})
	hud.ids.flash = player:hud_add({
		type = "image", position = {x = 0.5, y = 0.5}, alignment = {x = 0, y = 0},
		scale = {x = -100, y = -100}, text = "blank.png",
	})
	place_map(player)
	hud.build_meters(player)
end)

-- ---------------------------------------------------------------- meters
-- HP and Pw bars in the top-left corner, sized for Graphics > Text size
local METERS = {
	{key = "hp", label = "HP", cur = "hp", max = "hpmax", color = "#C02020", low = "#FF5555"},
	{key = "pw", label = "Pw", cur = "pw", max = "pwmax", color = "#2040C0", low = "#5555FF"},
}
local meter_ids = {}
local meter_last = {} -- key -> "cur/max" shown

local function meter_size()
	local k = nhv.theme and nhv.theme.box_scale() or 1
	return math.floor(200 * k), 14 * k + 6 -- width, height (HUD pixels)
end

local function meter_y(row)
	local _, h = meter_size()
	return 12 + (row - 1) * (h + 6)
end

function hud.build_meters(player)
	for _, id in pairs(meter_ids) do
		player:hud_remove(id)
	end
	meter_ids, meter_last = {}, {}
	local w, h = meter_size()
	local frame = nhv.theme and nhv.theme.retro() and "#AAAAAA" or "#000000"
	for row, m in ipairs(METERS) do
		local y = meter_y(row)
		local base = {position = {x = 0, y = 0}, alignment = {x = 1, y = 1}}
		meter_ids[m.key .. "_bg"] = player:hud_add({
			type = "image", position = base.position, alignment = base.alignment,
			offset = {x = 12, y = y}, scale = {x = 1, y = 1}, z_index = 40,
			text = ("[fill:%dx%d:%s^[fill:%dx%d:2,2:#141418"):format(w, h, frame, w - 4, h - 4),
		})
		meter_ids[m.key .. "_fill"] = player:hud_add({
			type = "image", position = base.position, alignment = base.alignment,
			offset = {x = 14, y = y + 2}, scale = {x = 0, y = 0}, z_index = 41,
			text = "[fill:1x1:" .. m.color,
		})
		meter_ids[m.key .. "_text"] = player:hud_add({
			type = "text", position = base.position, alignment = {x = 0, y = 0},
			offset = {x = 12 + w / 2, y = y + h / 2}, number = 0xFFFFFF, z_index = 42, text = "",
		})
	end
end

local function update_meters(player, h)
	if not next(meter_ids) then
		return
	end
	local w, ht = meter_size()
	for _, m in ipairs(METERS) do
		local cur, max = h[m.cur] or 0, h[m.max] or 0
		local shown = cur .. "/" .. max
		if meter_last[m.key] ~= shown then
			meter_last[m.key] = shown
			local frac = max > 0 and math.max(0, math.min(1, cur / max)) or 0
			-- (a 1-pixel texture stretched to the filled part; low = brighter)
			player:hud_change(meter_ids[m.key .. "_fill"], "scale",
				{x = (w - 4) * frac, y = frac > 0 and (ht - 4) or 0})
			player:hud_change(meter_ids[m.key .. "_fill"], "text",
				"[fill:1x1:" .. (frac <= 1 / 3 and m.low or m.color))
			player:hud_change(meter_ids[m.key .. "_text"], "text",
				("%s %d/%d"):format(m.label, cur, max))
		end
	end
end

-- redraw at a new size (Graphics > Text size / Interface)
function hud.rebuild_meters(player)
	if next(meter_ids) then
		hud.build_meters(player)
		if nh.snap then
			update_meters(player, nh.snap.hero)
		end
	end
end

-- A coloured vignette (the screen's edges) that flashes and fades: red
-- when hurt (stronger for bigger hits), green when healed a good amount.
local FLASH_S = 0.6
local flash = nil -- {color=, t0=, strength=}
local flash_shown = nil
function hud.flash(color, strength)
	flash = {color = color or "#FF2020", t0 = core.get_us_time(),
		strength = math.max(0.3, math.min(1, strength or 1))}
end

local tick = 0
core.register_globalstep(function(dtime)
	tick = tick + dtime
	local player = nhv.player.get()
	if not player or not hud.ids.msg then
		return
	end
	if flash then
		local t = (core.get_us_time() - flash.t0) / 1e6 / FLASH_S
		local tex = "blank.png"
		if t < 1 then
			-- (steps of 16 keep the number of different textures small)
			local a = math.floor((1 - t) * 230 * flash.strength / 16) * 16
			tex = ("nhv_vignette.png^[multiply:%s^[opacity:%d"):format(flash.color, a)
		else
			flash = nil
		end
		if tex ~= flash_shown then
			flash_shown = tex
			player:hud_change(hud.ids.flash, "text", tex)
		end
	end
	if tick > 0.2 then
		tick = 0
		update_messages(player)
	end
end)

-- Messages about bumping into things make no sense with free movement:
-- your body just collides. Lua patterns, matched against the message.
local SILENCED = {
	"^You stop%.", "in your way", "^You move right into", "^Pardon me",
	"^You try to move the boulder", "^Perhaps that's why you cannot move",
	"^There is a boulder in your way", "^You cannot pass", "^You are carrying too much to get through",
	"^You don't have enough room to maneuver", "^You can't move diagonally",
	"^Your body is too large to fit", "^You try to squeeze",
	"^There is an obstacle there", "^You harmlessly attack thin air",
	"^You already found a monster", "^There's a .* in the way",
	"^You hear a monster behind the boulder", "blocks your way", "blocks your path",
	"^You can.t move past", "in the way%.$", "^You swap places with",
	-- (the game's NetHack options are applied quietly at every start)
	"^Fruit is now ", "option toggled o[nf]f?%.$",
}

function hud.silenced(text)
	for _, pat in ipairs(SILENCED) do
		if text:find(pat) then
			return true
		end
	end
	return false
end

nh.on_event(function(evs)
	for _, ev in ipairs(evs) do
		if (ev.kind == "message" or ev.kind == "raw") and not hud.silenced(ev.text) then
			hud.message(ev.text)
		end
	end
end)

local last_hp
nh.on_snapshot(function(snap)
	local player = nhv.player.get()
	if not snap or not player or not hud.ids.status then
		return
	end
	local h = snap.hero
	player:hud_change(hud.ids.status, "text", status_text(h))
	update_meters(player, h)
	player:hud_change(hud.ids.map, "text", map_png(snap))
	if last_hp and h.hp < last_hp then
		hud.flash("#FF2020", 0.5 + (last_hp - h.hp) / math.max(1, h.hpmax) * 2.5)
	elseif last_hp and h.hp >= last_hp + math.max(3, h.hpmax / 5) then
		hud.flash("#30FF60", 0.7) -- (healed a good chunk; not each point regained)
	end
	last_hp = h.hp
	-- blindness: black fog that hides everything beyond arm's reach
	local blind = U.has(h.flags, U.HERO.BLIND)
	if blind ~= hud.blind then
		hud.blind = blind
		player:set_sky({type = "plain", base_color = "#000000", clouds = false,
			fog = blind and {fog_distance = 5, fog_start = 0.1}
				or {fog_distance = 90, fog_start = 0.3}})
	end
end)

return hud
