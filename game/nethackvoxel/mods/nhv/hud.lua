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

local sleep_shown = nil -- (the helpless overlay shown: "asleep", "frozen")

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
	-- (name and title, HP and Pw, level, gold, AC and experience are top
	-- left, hud.info_text)
	return (string.format("St:%s Dx:%d Co:%d In:%d Wi:%d Ch:%d   %s   T:%d   %s",
		h.str > 18 and (h.str <= 118 and ("18/" .. (h.str - 18)) or tostring(h.str - 100)) or tostring(h.str),
		h.dex, h.con, h.int, h.wis, h.cha, h.align, h.moves,
		table.concat(conds, " ")):gsub("%s+$", ""))
end

-- under the bars, top left: where you are and the numbers you check most
-- (also: the text before the gold, and the gold, for its flash)
function hud.info_text(h)
	local before = (h.level_desc or "") .. "   "
	local gold = ("$:%d"):format(h.gold or 0)
	return before .. gold .. ("   AC:%d   XL:%d/%d"):format(h.ac or 0, h.xlvl or 0, h.xp or 0),
		before, gold
end

local msg_shown

-- The things on your square, listed down the left side while you stand
-- there (instead of NetHack's "Things that are here:" window, which ui.lua
-- leaves out). Hidden under the inventory and other menus.
local HERE_MAX = 12
local here_shown
local function update_here(player, snap)
	if not hud.ids.here then
		return
	end
	local h = snap and snap.hero
	local covered = nhv.ui.menu_open or nhv.ui.chat_open or (nhv.title and nhv.title.open)
		or hud.big_map
	local lines = {}
	if h and h.x and not covered and not U.has(h.flags, U.HERO.SWALLOWED) then
		local items = nhv.mobs.floor_items(h.x, h.y)
		if #items > 0 then
			lines[1] = U.has(h.flags, U.HERO.BLIND) and "Things that you feel here:"
				or "Things that are here:"
			for k, o in ipairs(items) do
				if k > HERE_MAX then
					lines[#lines + 1] = ("  ...and %d more"):format(#items - HERE_MAX)
					break
				end
				lines[#lines + 1] = "  " .. o.name
			end
		end
	end
	local text = table.concat(lines, "\n")
	if text ~= here_shown then
		here_shown = text
		player:hud_change(hud.ids.here, "text", text)
		player:hud_change(hud.ids.here_shadow, "text", text)
		-- (and the key to pick it up, under the list)
		local key = text ~= "" and "F  Pick up" or ""
		player:hud_change(hud.ids.here_key, "text", key)
		player:hud_change(hud.ids.here_key_shadow, "text", key)
	end
end

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
	-- (above NetHack's questions only: not over other menus - the pause
	-- menu, the inventory, Options -, the title screen or the guide; the
	-- chat console shows the whole log meanwhile)
	local covered = nhv.ui.chat_open or (nhv.guide and nhv.guide.open)
		or (nhv.title and nhv.title.open) or (nhv.ui.menu_open and not nhv.ui.open)
	if not covered then
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

-- Inscriptions on the floor (engravings, graffiti, headstones...) are shown
-- low in the middle of the screen in gold, not with the messages (NetHack's
-- "Something is written here in the dust." line before them still is).
-- They stay until you step off the square (or a while has passed), and
-- still go to the message log (T).
local INSCR_TTL = 15
local inscr = nil -- {square = "x,y", t = seconds} while one is shown

local function wrap(text, width)
	local lines, line = {}, ""
	for word in text:gmatch("%S+") do
		if line ~= "" and #line + 1 + #word > width then
			lines[#lines + 1] = line
			line = word
		else
			line = line == "" and word or line .. " " .. word
		end
	end
	if line ~= "" then
		lines[#lines + 1] = line
	end
	return table.concat(lines, "\n")
end

local function hero_square()
	local h = nh.snap and nh.snap.hero
	return h and h.x and (h.x .. "," .. h.y) or nil
end

local function show_inscription(player, text)
	if not hud.ids.inscr then
		return
	end
	local body = text and wrap(text, 44) or ""
	player:hud_change(hud.ids.inscr, "text", body)
	player:hud_change(hud.ids.inscr_shadow, "text", body)
end

local function clear_inscription(player)
	inscr = nil
	show_inscription(player, nil)
end

-- true if the message was an inscription's words (shown in the middle,
-- not with the messages)
function hud.inscription(text)
	local said = text:match('^You read: "(.*)"[.]?$')
		or text:match('^You feel the words: "(.*)"[.]?$')
	if not said then
		return false
	end
	local player = nhv.player.get()
	if player then
		show_inscription(player, said)
		inscr = {square = hero_square(), t = core.get_us_time() / 1e6}
	end
	return true
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

-- The big map is drawn with the NetHack tiles: one HUD picture per known
-- square, changed only when that square changes. (Not one generated
-- picture of the whole map: the engine keeps every generated texture for
-- good, and a new one on every step would pile up.) The pixel map's
-- element is its dark backdrop meanwhile.
local TILE_PX = 16
local BACKDROP = "[fill:16x16:#000000^[opacity:200"
local tiles = {ids = {}, shown = {}, scale = nil}

-- the picture for map square (x, y) as the big map shows it: what you
-- remember there (terrain, a trap, objects) with you or a monster (or pet,
-- or a remembered unseen one) you know is there on top; nil unknown.
-- Sprites with see-through backgrounds (objects, monsters, traps, stairs,
-- fountains, trees...) are drawn over the floor that's under them - the
-- room's (lit or dark) or the corridor's - and over the square's terrain
-- feature, not over black.
local FLOORS = {S_room = true, S_darkroom = true, S_corr = true, S_litcorr = true,
	S_engroom = true, S_engrcorr = true, S_pool = true, S_water = true, S_lava = true,
	S_lavawall = true, S_ice = true, S_air = true, S_cloud = true, S_ndoor = true}
local cmap_ids -- name -> index
local function cmap_tile(name)
	if not cmap_ids then
		cmap_ids = {}
		for k = 0, 255 do
			local n = nhv.cmap_name(k)
			if n ~= "" then
				cmap_ids[n] = k
			end
		end
	end
	local k = cmap_ids[name]
	local t = k and core.nh_cmap_tile and core.nh_cmap_tile(k)
	return t and t >= 0 and t or nil
end

local function floor_under(map, i)
	local typ = map.typ[i]
	local lit = U.has(map.flags[i] or 0, U.LOC_LIT)
	if typ == U.TYP.CORR then
		return cmap_tile(lit and "S_litcorr" or "S_corr")
	end
	return cmap_tile(lit and "S_room" or "S_darkroom")
end

function hud.square_tex(map, h, x, y)
	local i = U.idx(x, y)
	local top -- (you or a monster)
	if x == h.x and y == h.y then
		top = h.tile
	else
		local c = color_for(map, i)
		if (c == COL.monster or c == COL.pet) and (map.tile[i] or -1) >= 0 then
			top = map.tile[i]
		end
	end
	local mem = map.mem_tile[i] or -1
	local mgi = nhv.glyph_info(map.mem[i])
	local mname = mgi.kind == "cmap" and nhv.cmap_name(mgi.index) or nil
	local known = mem >= 0 and mname ~= "S_stone" and mname ~= "S_unexplored"
	if not known then
		return top and nhv_tiles.texture(top) or nil
	end
	local layers = {}
	local typ = map.typ[i] or 0
	local open = typ >= U.TYP.POOL or typ == U.TYP.TREE
	if open and not (mname and FLOORS[mname]) then
		-- (the ground, then the terrain feature that's really there)
		local back = map.back and map.back[i]
		local bname = back and back ~= 255 and nhv.cmap_name(back) or nil
		if bname and FLOORS[bname] then
			layers[#layers + 1] = bname == "S_room" and floor_under(map, i) or cmap_tile(bname)
		else
			layers[#layers + 1] = floor_under(map, i)
			if bname and bname ~= "S_stone" then
				layers[#layers + 1] = cmap_tile(bname)
			end
		end
	end
	if layers[#layers] ~= mem then
		layers[#layers + 1] = mem
	end
	if top then
		layers[#layers + 1] = top
	end
	local parts = {}
	for _, t in ipairs(layers) do
		parts[#parts + 1] = "(" .. nhv_tiles.texture(t) .. ")"
	end
	if #parts == 1 then
		return nhv_tiles.texture(layers[1])
	end
	return table.concat(parts, "^")
end

local function clear_tiles(player)
	for i, id in pairs(tiles.ids) do
		player:hud_remove(id)
		tiles.ids[i] = nil
	end
	tiles.shown, tiles.scale = {}, nil
end

local function update_tiles(player, snap)
	if not (hud.big_map and snap and snap.map) then
		clear_tiles(player)
		return
	end
	local s = big_map_scale(player)
	if s ~= tiles.scale then
		clear_tiles(player) -- (the window changed size: place them all again)
		tiles.scale = s
	end
	local map, h = snap.map, snap.hero
	for y = 0, U.ROWNO - 1 do
		for x = 1, U.COLNO - 1 do
			local i = U.idx(x, y)
			local tex = hud.square_tex(map, h, x, y)
			if tex ~= tiles.shown[i] then
				tiles.shown[i] = tex
				local id = tiles.ids[i]
				if not tex then
					player:hud_remove(id)
					tiles.ids[i] = nil
				elseif id then
					player:hud_change(id, "text", tex)
				else
					tiles.ids[i] = player:hud_add({
						type = "image", position = {x = 0.5, y = 0.45}, alignment = {x = 0, y = 0},
						offset = {x = (x + 0.5 - U.COLNO / 2) * s, y = (y + 0.5 - U.ROWNO / 2) * s},
						scale = {x = s / TILE_PX, y = s / TILE_PX}, text = tex, z_index = 1,
					})
				end
			end
		end
	end
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
		-- (the backdrop: a 16x16 fill the size of the map)
		player:hud_change(hud.ids.map, "scale", {x = s * U.COLNO / 16, y = s * U.ROWNO / 16})
		player:hud_change(hud.ids.map, "offset", {x = 0, y = 0})
		player:hud_change(hud.ids.map, "text", BACKDROP)
		update_tiles(player, nh.snap)
	else
		local s = corner_scale()
		player:hud_change(hud.ids.map, "position", {x = 1, y = 0})
		player:hud_change(hud.ids.map, "alignment", {x = -1, y = 1})
		-- (a hidden map is scaled to nothing)
		player:hud_change(hud.ids.map, "scale", {x = s, y = s})
		player:hud_change(hud.ids.map, "offset", {x = -10, y = 10})
		clear_tiles(player)
		if nh.snap and nh.snap.map then
			player:hud_change(hud.ids.map, "text", map_png(nh.snap))
		end
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

-- Picking a place on the map (ui.lua's place picker): the big map itself is
-- shown meanwhile (and put back as it was after), and this tells where its
-- squares are on the screen: square size and the map's top-left corner, in
-- pixels, and the window's size.
local picking_was = nil
function hud.picking(on)
	local player = nhv.player.get()
	if on and picking_was == nil then
		picking_was = hud.big_map or false
		hud.big_map = true
	elseif not on and picking_was ~= nil then
		hud.big_map = picking_was
		picking_was = nil
	else
		return
	end
	if player then
		place_map(player)
	end
end

function hud.big_map_geometry(player)
	local info = core.get_player_window_information(player:get_player_name())
	if not (info and info.size and info.real_hud_scaling and info.max_formspec_size) then
		return nil
	end
	local px = big_map_scale(player) * info.real_hud_scaling -- (a square)
	return {
		info = info, square = px,
		left = 0.5 * info.size.x - U.COLNO / 2 * px,
		top = 0.45 * info.size.y - U.ROWNO / 2 * px,
	}
end

core.register_on_joinplayer(function(player)
	tiles.ids, tiles.shown, tiles.scale = {}, {}, nil -- (a new player object: none drawn yet)
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
	-- (z_index 1000 and up: the VoxHack build of Luanti draws it
	-- above menus and prompts, so it can be read while answering them)
	hud.ids.msg = player:hud_add({
		type = "text", position = {x = 0.5, y = 0}, alignment = {x = 0, y = 1},
		offset = {x = 0, y = 60}, number = 0xFFFFE0, text = "", z_index = 1000,
	})
	msg_shown = nil
	-- an inscription you're standing on: centred, in the lower part of the
	-- screen (under the crosshair, clear of the status line and hotbar),
	-- gold with a black shadow
	local function centre(shadow)
		return player:hud_add({
			type = "text", position = {x = 0.5, y = 0.66}, alignment = {x = 0, y = 1},
			offset = {x = shadow and 2 or 0, y = shadow and 2 or 0},
			number = shadow and 0x000000 or 0xFFD25A, text = "",
			z_index = shadow and 20 or 21, size = {x = 2, y = 0},
		})
	end
	hud.ids.inscr_shadow = centre(true)
	hud.ids.inscr = centre(false)
	inscr = nil
	-- what lies on your square, down the left side: no box, a black shadow
	-- (the same text again, a little down and right, behind it). "F  Pick up"
	-- sits at a fixed place low on the left, the list above it, growing up
	-- (clear of the messages coming down from the top)
	local HERE_Y = 0.72
	hud.ids.here_shadow = player:hud_add({
		type = "text", position = {x = 0, y = HERE_Y}, alignment = {x = 1, y = -1},
		offset = {x = 22, y = -28}, number = 0x000000, text = "", z_index = 10,
	})
	hud.ids.here = player:hud_add({
		type = "text", position = {x = 0, y = HERE_Y}, alignment = {x = 1, y = -1},
		offset = {x = 20, y = -30}, number = 0xFFFFFF, text = "", z_index = 11,
	})
	hud.ids.here_key_shadow = player:hud_add({
		type = "text", position = {x = 0, y = HERE_Y}, alignment = {x = 1, y = -1},
		offset = {x = 22, y = 2}, number = 0x000000, text = "", z_index = 10,
	})
	hud.ids.here_key = player:hud_add({
		type = "text", position = {x = 0, y = HERE_Y}, alignment = {x = 1, y = -1},
		offset = {x = 20, y = 0}, number = 0xFFD040, text = "", z_index = 11,
	})
	here_shown = nil
	hud.ids.map = player:hud_add({
		type = "image", position = {x = 1, y = 0}, alignment = {x = -1, y = 1},
		offset = {x = -10, y = 10}, scale = {x = 3, y = 3}, text = "blank.png",
	})
	hud.ids.flash = player:hud_add({
		type = "image", position = {x = 0.5, y = 0.5}, alignment = {x = 0, y = 0},
		scale = {x = -100, y = -100}, text = "blank.png",
	})
	-- the compass at the top middle (Skyrim style): a strip of directions
	-- that slides as you turn - the engine moves it every frame, from the
	-- camera (textures from tools/make_compass.py; NetHack's north is +z)
	hud.ids.compass_frame = player:hud_add({
		type = "image", position = {x = 0.5, y = 0}, alignment = {x = 0, y = 1},
		offset = {x = 0, y = 8}, scale = {x = 1, y = 1}, text = "nhv_compass_frame.png",
	})
	hud.ids.compass = player:hud_add({
		type = "compass", position = {x = 0.5, y = 0}, alignment = {x = 0, y = 1},
		offset = {x = 0, y = 8}, size = {x = 480, y = 48}, scale = {x = 1, y = 1},
		text = "nhv_compass.png", dir = 2,
	})
	hud.ids.compass_mark = player:hud_add({
		type = "image", position = {x = 0.5, y = 0}, alignment = {x = 0, y = 1},
		offset = {x = 0, y = 2}, scale = {x = 1, y = 1}, text = "nhv_compass_mark.png",
	})
	-- helpless: asleep or fainted, your eyes are shut (nearly black);
	-- awake but frozen (a floating eye's gaze, paralysis), a cold grey-blue
	-- you can still see through. (The messages show over both.)
	hud.ids.sleep = player:hud_add({
		type = "image", position = {x = 0.5, y = 0.5}, alignment = {x = 0, y = 0},
		scale = {x = -100, y = -100}, text = "blank.png", z_index = 500,
	})
	sleep_shown = nil
	place_map(player)
	hud.build_meters(player)
	hud.apply_fog(player)
end)

-- ---------------------------------------------------------------- fog
-- black fog in the distance (blindness brings it right in)
function hud.apply_fog(player)
	local fog = hud.blind and {fog_distance = 5, fog_start = 0.1}
		or {fog_distance = 90, fog_start = 0.3}
	-- (the sky's: black, or a sky over the level - see sky.lua)
	if nhv.sky and nhv.sky.apply then
		nhv.sky.apply(player, fog)
		return
	end
	player:set_sky({type = "plain", base_color = "#000000", clouds = false, fog = fog})
end

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

-- (row 0 is your name and title; the bars are rows 1 and 2)
local info_shown -- (the level, gold, AC... line under the bars)
local gold_last  -- (the gold last shown: a change flashes it)
local GOLD_FLASH = 0xFFD040
local flash_seq = 0

-- on, off, on: the money in gold over the white (with the modern font,
-- whose letters aren't all one width, the whole line flashes)
local function flash_gold(player, before, gold)
	if not meter_ids.info_flash then
		return
	end
	flash_seq = flash_seq + 1
	local mine = flash_seq
	local text = nhv.theme.retro() and ((" "):rep(#before) .. gold) or info_shown
	local function set(on)
		if mine == flash_seq and meter_ids.info_flash and player:is_player() then
			player:hud_change(meter_ids.info_flash, "text", on and text or "")
		end
	end
	set(true)
	core.after(0.25, set, false)
	core.after(0.4, set, true)
	core.after(0.8, set, false)
end
local function meter_y(row)
	local _, h = meter_size()
	return 12 + row * (h + 6)
end

-- your portrait (your NetHack sprite) to the left of the name and bars
local TILE_PX = 16 -- (NetHack's tiles)
local function portrait_size()
	local _, h = meter_size()
	return 3 * h + 2 * 6
end
local function meters_x()
	return 12 + portrait_size() + 8
end
local portrait_shown, name_shown

function hud.build_meters(player)
	for _, id in pairs(meter_ids) do
		player:hud_remove(id)
	end
	meter_ids, meter_last = {}, {}
	portrait_shown, name_shown = nil, nil
	local w, h = meter_size()
	local frame = nhv.theme and nhv.theme.retro() and "#AAAAAA" or "#000000"
	local base = {position = {x = 0, y = 0}, alignment = {x = 1, y = 1}}
	local mx = meters_x()
	-- your portrait in a framed box, as tall as the name and both bars
	local ps = portrait_size()
	meter_ids.portrait_bg = player:hud_add({
		type = "image", position = base.position, alignment = base.alignment,
		offset = {x = 12, y = 12}, scale = {x = 1, y = 1}, z_index = 40,
		text = ("[fill:%dx%d:%s^[fill:%dx%d:2,2:#141418"):format(ps, ps, frame, ps - 4, ps - 4),
	})
	local inner = ps - 8
	meter_ids.portrait = player:hud_add({
		type = "image", position = base.position, alignment = base.alignment,
		offset = {x = 16, y = 16}, scale = {x = inner / TILE_PX, y = inner / TILE_PX}, z_index = 41,
		text = "blank.png",
	})
	-- your name and title
	meter_ids.name = player:hud_add({
		type = "text", position = base.position, alignment = {x = 1, y = 0},
		offset = {x = mx + 2, y = 12 + h / 2}, number = 0xFFFFFF, z_index = 42, text = "",
	})
	for row, m in ipairs(METERS) do
		local y = meter_y(row)
		meter_ids[m.key .. "_bg"] = player:hud_add({
			type = "image", position = base.position, alignment = base.alignment,
			offset = {x = mx, y = y}, scale = {x = 1, y = 1}, z_index = 40,
			text = ("[fill:%dx%d:%s^[fill:%dx%d:2,2:#141418"):format(w, h, frame, w - 4, h - 4),
		})
		meter_ids[m.key .. "_fill"] = player:hud_add({
			type = "image", position = base.position, alignment = base.alignment,
			offset = {x = mx + 2, y = y + 2}, scale = {x = 0, y = 0}, z_index = 41,
			text = "[fill:1x1:" .. m.color,
		})
		meter_ids[m.key .. "_text"] = player:hud_add({
			type = "text", position = base.position, alignment = {x = 0, y = 0},
			offset = {x = mx + w / 2, y = y + h / 2}, number = 0xFFFFFF, z_index = 42, text = "",
		})
	end
	-- the level, gold, AC and experience line under them (from the
	-- portrait's left edge)
	meter_ids.info = player:hud_add({
		type = "text", position = base.position, alignment = {x = 1, y = 0},
		offset = {x = 14, y = meter_y(#METERS) + h + 6 + h / 2}, number = 0xFFFFFF, z_index = 42, text = "",
	})
	-- the gold's flash: the same line over it, all but the gold blanked
	-- (the pixel font's letters are all one width, so it lines up)
	meter_ids.info_flash = player:hud_add({
		type = "text", position = base.position, alignment = {x = 1, y = 0},
		offset = {x = 14, y = meter_y(#METERS) + h + 6 + h / 2}, number = GOLD_FLASH, z_index = 43, text = "",
	})
	info_shown = nil
	-- (the message lines start below all that: long ones don't run over it)
	if hud.ids.msg then
		player:hud_change(hud.ids.msg, "offset", {x = 0, y = meter_y(#METERS) + 2 * h + 14})
	end
end

local function update_meters(player, h)
	if not next(meter_ids) then
		return
	end
	local info, before, gold = hud.info_text(h)
	if meter_ids.info and info ~= info_shown then
		info_shown = info
		player:hud_change(meter_ids.info, "text", info)
	end
	-- gold picked up or lost: the money flashes gold
	if gold_last and h.gold ~= gold_last then
		flash_gold(player, before, gold)
	end
	gold_last = h.gold
	-- your sprite (polymorphed: what you've become) and "name the title"
	local tex = h.tile and h.tile >= 0 and nhv_tiles.texture(h.tile) or "blank.png"
	if tex ~= portrait_shown then
		portrait_shown = tex
		player:hud_change(meter_ids.portrait, "text", tex)
	end
	local name = ((h.name or "") .. (h.rank and h.rank ~= "" and (" the " .. h.rank) or ""))
	if name ~= name_shown then
		name_shown = name
		player:hud_change(meter_ids.name, "text", name)
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
-- full = the whole screen (a flash of light), not just the edges.
local FLASH_S = 0.6
local flash = nil -- {color=, t0=, strength=, full=}
local flash_shown = nil
function hud.flash(color, strength, full)
	flash = {color = color or "#FF2020", t0 = core.get_us_time(),
		strength = math.max(0.2, math.min(1, strength or 1)), full = full}
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
			if flash.full then
				tex = ("[fill:16x16:%s^[opacity:%d"):format(flash.color, a)
			else
				tex = ("nhv_vignette.png^[multiply:%s^[opacity:%d"):format(flash.color, a)
			end
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
		-- (a menu opened or closed over it; the square's things changed)
		update_here(player, nh.snap)
		-- (the message can come before the hero's new square - after a
		-- level change, say -: the square it's on settles for a second)
		local age = inscr and core.get_us_time() / 1e6 - inscr.t
		if inscr and age < 1 then
			inscr.square = hero_square()
		elseif inscr and (hero_square() ~= inscr.square or age > INSCR_TTL
				or (nhv.title and nhv.title.open) or hud.big_map or nhv.ui.chat_open) then
			clear_inscription(player)
		end
	end
end)

-- Messages about bumping into things make no sense with free movement:
-- your body just collides. Lua patterns, matched against the message.
-- (pushing a boulder only happens when you walk into it on purpose, so why
-- it won't move - "in vain", a monster behind it - is always shown)
local SILENCED = {
	"^You stop%.", "in your way", "^You move right into", "^Pardon me",
	"^There is a boulder in your way", "^You cannot pass",
	"^You don't have enough room to maneuver", "^You can't move diagonally",
	"^Your body is too large to fit", "^You try to squeeze",
	"^There is an obstacle there", "^You harmlessly attack thin air",
	"^You already found a monster", "^There's a .* in the way",
	"blocks your way", "blocks your path",
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
			if hud.inscription(ev.text) then
				-- (not with the messages, but still in the log)
				local player = nhv.player.get()
				if player then
					core.chat_send_player(player:get_player_name(), ev.text)
				end
			else
				hud.message(ev.text)
			end
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
	update_here(player, snap)
	if hud.big_map then
		update_tiles(player, snap)
	else
		player:hud_change(hud.ids.map, "text", map_png(snap))
	end
	if last_hp and h.hp < last_hp then
		hud.flash("#FF2020", 0.5 + (last_hp - h.hp) / math.max(1, h.hpmax) * 2.5)
	elseif last_hp and h.hp >= last_hp + math.max(3, h.hpmax / 5) then
		hud.flash("#30FF60", 0.7) -- (healed a good chunk; not each point regained)
	end
	last_hp = h.hp
	local look = U.has(h.flags, U.HERO.ASLEEP) and "asleep"
		or U.has(h.flags, U.HERO.HELPLESS) and "frozen" or nil
	if look ~= sleep_shown and hud.ids.sleep then
		sleep_shown = look
		player:hud_change(hud.ids.sleep, "text", look == "asleep" and "[fill:16x16:#000010^[opacity:150"
			or look == "frozen" and "[fill:16x16:#5070A0^[opacity:90" or "blank.png")
	end
	-- blindness: black fog that hides everything beyond arm's reach
	local blind = U.has(h.flags, U.HERO.BLIND)
	if blind ~= hud.blind then
		hud.blind = blind
		hud.apply_fog(player)
	end
end)

return hud
