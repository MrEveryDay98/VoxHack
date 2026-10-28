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

-- How bad each condition on the status line is: its colour, and how hard
-- it shakes (pixels, at box scale 1). 4: it kills you soon; 3: it's
-- dangerous; 2: it gets in your way; 1: a nuisance; 0: not a trouble at all
-- (levitating, flying, riding).
local SEVERITY = {
	[4] = {color = 0xFF3030, shake = 3},
	[3] = {color = 0xFF8C1A, shake = 2},
	[2] = {color = 0xFFD640, shake = 1},
	[1] = {color = 0xE8DDA8, shake = 0},
	[0] = {color = 0x90D0FF, shake = 0},
}
local HUNGER_SEVERITY = {[2] = 1, [3] = 3, [4] = 4, [5] = 4, [6] = 4}
local ENCUMBRANCE_SEVERITY = {1, 2, 3, 3, 3}

-- the status line: its numbers, and its conditions ({text=, severity=},
-- worst first)
local function status_text(h)
	local conds = {}
	local function add(on, txt, severity)
		if on then
			conds[#conds + 1] = {text = txt, severity = severity, n = #conds}
		end
	end
	local f, c = h.flags, h.conds or 0
	add(U.has(c, U.COND.STONE), "Stone", 4)
	add(U.has(c, U.COND.SLIME), "Slime", 4)
	add(U.has(c, U.COND.STRANGLED), "Strangled", 4)
	add(U.has(c, U.COND.FOODPOIS), "FoodPois", 4)
	add(U.has(c, U.COND.TERMILL), "TermIll", 4)
	add(U.has(c, U.COND.LAVA), "InLava", 4)
	add(HUNGER_SEVERITY[h.hunger] and HUNGER_SEVERITY[h.hunger] >= 4, HUNGER[h.hunger], 4)
	add(U.has(f, U.HERO.STUN), "Stun", 3)
	add(U.has(f, U.HERO.HELD), "Held", 3)
	add(h.hunger == 3, HUNGER[3], 3)
	add(U.has(f, U.HERO.BLIND), "Blind", 2)
	add(U.has(f, U.HERO.CONF), "Conf", 2)
	add(U.has(f, U.HERO.HALLU), "Hallu", 2)
	add(U.has(c, U.COND.LEGS), "Legs", 2)
	add(U.has(c, U.COND.GLIB), "Slippery", 2)
	add(U.has(f, U.HERO.TRAPPED) and not U.has(c, U.COND.LAVA), "Trapped", 2)
	add(h.hunger == 2, HUNGER[2], 1)
	add(U.has(c, U.COND.DEAF), "Deaf", 1)
	local enc = ENCUMBRANCE_SEVERITY[h.encumbrance]
	add(enc, ENCUMBRANCE[h.encumbrance], enc)
	table.sort(conds, function(a, b)
		return a.severity > b.severity or (a.severity == b.severity and a.n < b.n)
	end)
	add(U.has(f, U.HERO.LEVITATE), "Lev", 0)
	add(U.has(f, U.HERO.FLYING), "Fly", 0)
	add(U.has(f, U.HERO.RIDING), "Ride", 0)
	-- (name and title, HP and Pw, level, gold, AC and experience are top
	-- left, hud.info_text)
	return string.format("St:%s Dx:%d Co:%d In:%d Wi:%d Ch:%d   %s   T:%d",
		h.str > 18 and (h.str <= 118 and ("18/" .. (h.str - 18)) or tostring(h.str - 100)) or tostring(h.str),
		h.dex, h.con, h.int, h.wis, h.cha, h.align, h.moves), conds
end

-- The conditions are drawn each in its own colour, and shaking, as HUD
-- texts of their own over the status line: every one of them (and the
-- status line) is the whole line, the rest of it spaces, so in the
-- monospace font each word lands where it would in the one line.
local cond_ids = {}  -- HUD ids, made as they're needed
local cond_shown = {} -- {text=, severity=} drawn by each
local status_above = 90

local function show_status(player, h)
	local stats, conds = status_text(h)
	local words = {stats}
	for _, cd in ipairs(conds) do
		words[#words + 1] = cd.text
	end
	local line = table.concat(words, "   ", 1, math.min(2, #words))
		.. (#words > 2 and " " .. table.concat(words, " ", 3) or "")
	local function only(from, len)
		return (" "):rep(from - 1) .. line:sub(from, from + len - 1) .. (" "):rep(#line - from - len + 1)
	end
	player:hud_change(hud.ids.status, "text", only(1, #stats))
	local at = #stats + 4
	for i = 1, math.max(#conds, #cond_ids) do
		local cd = conds[i]
		if cd and not cond_ids[i] then
			cond_ids[i] = player:hud_add({
				type = "text", position = {x = 0.5, y = 1}, alignment = {x = 0, y = -1},
				offset = {x = 0, y = -status_above}, number = 0xFFFFFF, text = "",
				style = 4, -- monospace
			})
		end
		local text = cd and only(at, #cd.text) or ""
		if cond_ids[i] then
			local was = cond_shown[i]
			if not was or was.text ~= text or was.severity ~= (cd and cd.severity) then
				player:hud_change(cond_ids[i], "text", text)
				if cd then
					player:hud_change(cond_ids[i], "number", SEVERITY[cd.severity].color)
				end
				cond_shown[i] = {text = text, severity = cd and cd.severity}
			end
		end
		if cd then
			at = at + #cd.text + 1
		end
	end
end

-- each frame or so: the conditions shake, the worse the harder
local shake_t = 0
local function shake_conditions(player, dtime)
	shake_t = shake_t + dtime
	if shake_t < 1 / 30 then
		return
	end
	shake_t = 0
	local k = nhv.theme and nhv.theme.box_scale() or 1
	for i, id in ipairs(cond_ids) do
		local cd = cond_shown[i]
		local amp = cd and cd.severity and SEVERITY[cd.severity].shake or 0
		local x, y = 0, 0
		if amp > 0 then
			x = math.floor((math.random() * 2 - 1) * amp * k + 0.5)
			y = math.floor((math.random() * 2 - 1) * amp * k + 0.5)
		end
		if cd and (amp > 0 or cd.still ~= true) then
			cd.still = amp == 0
			player:hud_change(id, "offset", {x = x, y = y - status_above})
		end
	end
end

-- under the bars, top left: the numbers you check most (the level is under
-- the corner map: hud.level_text) (also: the text before the gold, and the
-- gold, for its flash)
function hud.info_text(h)
	local before = ""
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
local invoke_shown
local fade_shown = nil -- (the fade layer's texture now)
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
	-- (and what Q does under it: your form's special ability, or invoking
	-- what you wield, while there is one)
	local q = h and not covered and (nhv.actions.monster_ability()
		or (nhv.actions.invokable() and "Invoke"))
	local inv = q and "Q  " .. q or ""
	if inv ~= invoke_shown then
		invoke_shown = inv
		player:hud_change(hud.ids.invoke_key, "text", inv)
		player:hud_change(hud.ids.invoke_key_shadow, "text", inv)
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

-- a tile's picture on the map: in ASCII mode (ascii.lua) its character,
-- on black, the size of a tile's picture
local function map_texture(tile)
	if nhv.ascii and nhv.ascii.on then
		return ("[fill:%dx%d:#000000^(%s^[resize:%dx%d)"):format(TILE_PX, TILE_PX,
			nhv_tiles.texture(tile), TILE_PX, TILE_PX)
	end
	return nhv_tiles.texture(tile)
end

-- (bare: leave you and the monsters off it - the big map draws them where
-- they really are instead: Options > Map icons)
function hud.square_tex(map, h, x, y, bare)
	local i = U.idx(x, y)
	local top -- (you or a monster)
	if bare then -- luacheck: ignore 542
		-- (nothing on top)
	elseif x == h.x and y == h.y then
		top = h.tile
	else
		local c = color_for(map, i)
		if (c == COL.monster or c == COL.pet) and (map.tile[i] or -1) >= 0 then
			top = map.tile[i]
		end
	end
	-- ASCII mode: just the top character, as on NetHack's own screen
	if nhv.ascii and nhv.ascii.on then
		if top then
			return map_texture(top)
		end
		-- (an object remembered there: its character; else the ground's)
		local mt = map.mem_tile[i] or -1
		if mt >= 0 and nhv.glyph_info(map.mem[i]).kind ~= "cmap" then
			return map_texture(mt)
		end
		local code, color = nhv.ascii.square(map, i)
		if code == 32 then
			return nil
		end
		return ("[fill:%dx%d:#000000^(%s^[resize:%dx%d)"):format(TILE_PX, TILE_PX,
			nhv_tiles.ascii_texture(code, color), TILE_PX, TILE_PX)
	end
	local mem = map.mem_tile[i] or -1
	local mgi = nhv.glyph_info(map.mem[i])
	local mname = mgi.kind == "cmap" and nhv.cmap_name(mgi.index) or nil
	-- (the Plane of Air: NetHack shows every square you can't see as cloud -
	-- the map shows the clouds where they really are, as the world does)
	local rtyp = map.typ[i]
	if nhv.terrain.sky_floor == "air" and (mname == "S_cloud" or mname == "S_air")
			and (rtyp == U.TYP.CLOUD or rtyp == U.TYP.AIR) then
		mname = rtyp == U.TYP.CLOUD and "S_cloud" or "S_air"
		mem = cmap_tile(mname)
	elseif nhv.terrain.sky_floor == "water" and (mem < 0 or mgi.kind == "cmap")
			and (rtyp == U.TYP.WATER or rtyp == U.TYP.AIR) then
		-- (the Plane of Water likewise: its bubbles - air - where the 3D
		-- world has them, its spheres - what says you're in one - as
		-- NetHack's own tiles, in the water)
		local air = nhv.bubbles and nhv.bubbles.air_at(x, y)
		if air == nil then
			air = rtyp == U.TYP.AIR
		end
		mname = air and "S_air" or "S_water"
		mem = cmap_tile(mname)
	end
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
	-- (with the icons where they really are, the squares they're drawn
	-- for - yours, the monsters' you see - leave them off)
	local bare = {}
	if hud.exact_icons() then
		bare[U.idx(h.x, h.y)] = true
		for _, e in pairs(nhv.mobs.mons) do
			if e.x and e.tile then
				bare[U.idx(e.x, e.y)] = true
			end
		end
	end
	for y = 0, U.ROWNO - 1 do
		for x = 1, U.COLNO - 1 do
			local i = U.idx(x, y)
			local tex = hud.square_tex(map, h, x, y, bare[i])
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

-- Options > Map icons "Where they are": on the big map you and the monsters
-- you see are drawn where they really are (where the 3D view shows them),
-- not on their squares
function hud.exact_icons()
	return core.settings:get_bool("nhv_map_exact", false)
end

-- a world position on the map, in squares (x east, y south; a square's
-- middle is +0.5)
local function map_pos(p)
	return (p.x + 0.5) / U.TILE, (U.ROWNO - 1) - (p.z - (U.TILE - 0.5)) / U.TILE
end

local icons = {} -- key -> {id, tex, x, y, s}
local function clear_icons(player)
	for key, ic in pairs(icons) do
		player:hud_remove(ic.id)
		icons[key] = nil
	end
end

local function update_map_icons(player)
	local h = nh.snap and nh.snap.hero
	if not (hud.big_map and h and h.x and hud.exact_icons()) then
		if next(icons) then
			clear_icons(player)
		end
		return
	end
	local s = big_map_scale(player)
	local want = {}
	for key, e in pairs(nhv.mobs.mons) do
		local p = e.tile and e.obj and e.obj:get_pos()
		if p then
			want[key] = {tile = e.tile, p = p, z = 3}
		end
	end
	want.hero = {tile = h.tile, p = player:get_pos(), z = 4} -- (you on top)
	for key, w in pairs(want) do
		local fx, fy = map_pos(w.p)
		-- (the picture's own middle where they are, not its cell's: most
		-- stand at the bottom of theirs)
		local cx, cy = nhv_tiles.picture_center(w.tile)
		local x = (fx - U.COLNO / 2) * s - cx * s / TILE_PX
		local y = (fy - U.ROWNO / 2) * s - cy * s / TILE_PX
		local tex = map_texture(w.tile)
		local ic = icons[key]
		if not ic then
			icons[key] = {id = player:hud_add({
				type = "image", position = {x = 0.5, y = 0.45}, alignment = {x = 0, y = 0},
				offset = {x = x, y = y}, scale = {x = s / TILE_PX, y = s / TILE_PX},
				text = tex, z_index = w.z,
			}), tex = tex, x = x, y = y, s = s}
		else
			if tex ~= ic.tex then
				ic.tex = tex
				player:hud_change(ic.id, "text", tex)
			end
			if x ~= ic.x or y ~= ic.y then
				ic.x, ic.y = x, y
				player:hud_change(ic.id, "offset", {x = x, y = y})
			end
			if s ~= ic.s then
				ic.s = s
				player:hud_change(ic.id, "scale", {x = s / TILE_PX, y = s / TILE_PX})
			end
		end
	end
	for key, ic in pairs(icons) do
		if not want[key] then
			player:hud_remove(ic.id)
			icons[key] = nil
		end
	end
end

-- On the big map, an arrow beside you points the way you look, going round
-- you as you turn: one of ARROW_STEPS pictures (tools/make_map_arrow.py),
-- the one nearest your heading, ARROW_OUT squares out from where you
-- stand (where in your square, too: it moves as you walk).
local ARROW_STEPS, ARROW_OUT, ARROW_SIZE = 32, 1.05, 1.2 -- (squares)
local arrow_shown = {}
local function update_map_arrow(player)
	if not hud.ids.map_arrow then
		return
	end
	local h = nh.snap and nh.snap.hero
	local tex, offset, sc = "", nil, nil
	if hud.big_map and h and h.x then
		local s = big_map_scale(player)
		local fx, fy = map_pos(player:get_pos()) -- (where you are, in squares)
		-- (clockwise from north: looking along -sin(yaw), cos(yaw))
		local a = (-player:get_look_horizontal()) % (2 * math.pi)
		local k = math.floor(a / (2 * math.pi) * ARROW_STEPS + 0.5) % ARROW_STEPS
		tex = ("nhv_map_arrow_%02d.png"):format(k)
		offset = {x = (fx + math.sin(a) * ARROW_OUT - U.COLNO / 2) * s,
			y = (fy - math.cos(a) * ARROW_OUT - U.ROWNO / 2) * s}
		sc = {x = s * ARROW_SIZE / 24, y = s * ARROW_SIZE / 24}
	end
	if tex ~= arrow_shown.tex then
		arrow_shown.tex = tex
		player:hud_change(hud.ids.map_arrow, "text", tex)
	end
	if offset and (not arrow_shown.offset or offset.x ~= arrow_shown.offset.x
			or offset.y ~= arrow_shown.offset.y) then
		arrow_shown.offset = offset
		player:hud_change(hud.ids.map_arrow, "offset", offset)
	end
	if sc and (not arrow_shown.scale or sc.x ~= arrow_shown.scale.x) then
		arrow_shown.scale = sc
		player:hud_change(hud.ids.map_arrow, "scale", sc)
	end
end

-- the corner map's pixels per square (Graphics > Map size; 0 hides it)
local function corner_scale()
	return tonumber(core.settings:get("nhv_map_scale")) or 3
end

-- under the corner map: the dungeon level ("Dlvl:3"), and the branch when
-- it isn't the main dungeon
function hud.level_text(h)
	local t = h.level_desc or ""
	if h.dungeon_name and h.dungeon_name ~= "" and h.dungeon_name ~= "The Dungeons of Doom" then
		t = t .. "  (" .. h.dungeon_name .. ")"
	end
	return t
end
local level_shown = nil

-- the level's line under the corner map (not over the big map; at the top
-- when the corner map is hidden)
local function place_level(player)
	if not hud.ids.level then
		return
	end
	local text = (not hud.big_map and nh.snap and nh.snap.hero) and hud.level_text(nh.snap.hero) or ""
	if text ~= level_shown then
		level_shown = text
		player:hud_change(hud.ids.level, "text", text)
	end
	player:hud_change(hud.ids.level, "offset", {x = -10, y = 10 + U.ROWNO * corner_scale() + 6})
end

local function place_map(player)
	if not hud.ids.map then
		return
	end
	place_level(player)
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
	status_above = above
	for i, id in ipairs(cond_ids) do
		if cond_shown[i] then
			cond_shown[i].still = nil -- (shake_conditions moves it)
		end
		player:hud_change(id, "offset", {x = 0, y = -above})
	end
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
	icons = {}
	cond_ids, cond_shown = {}, {}
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
	hud.ids.invoke_key_shadow = player:hud_add({
		type = "text", position = {x = 0, y = HERE_Y}, alignment = {x = 1, y = -1},
		offset = {x = 22, y = 28}, number = 0x000000, text = "", z_index = 10,
	})
	hud.ids.invoke_key = player:hud_add({
		type = "text", position = {x = 0, y = HERE_Y}, alignment = {x = 1, y = -1},
		offset = {x = 20, y = 26}, number = 0xFFD040, text = "", z_index = 11,
	})
	here_shown, invoke_shown = nil, nil
	-- the big map's facing arrow (over its squares and icons; update_map_arrow)
	hud.ids.map_arrow = player:hud_add({
		type = "image", position = {x = 0.5, y = 0.45}, alignment = {x = 0, y = 0},
		offset = {x = 0, y = 0}, scale = {x = 1, y = 1}, text = "", z_index = 5,
	})
	arrow_shown = {}
	hud.ids.map = player:hud_add({
		type = "image", position = {x = 1, y = 0}, alignment = {x = -1, y = 1},
		offset = {x = -10, y = 10}, scale = {x = 3, y = 3}, text = "blank.png",
	})
	hud.ids.level = player:hud_add({
		type = "text", position = {x = 1, y = 0}, alignment = {x = -1, y = 1},
		offset = {x = -10, y = 10 + U.ROWNO * 3 + 6}, number = 0xFFFFFF, z_index = 42, text = "",
	})
	level_shown = nil
	hud.ids.flash = player:hud_add({
		type = "image", position = {x = 0.5, y = 0.5}, alignment = {x = 0, y = 0},
		scale = {x = -100, y = -100}, text = "blank.png",
	})
	-- the fade to black (level changes: hud.fade), over everything else
	hud.ids.fade = player:hud_add({
		type = "image", position = {x = 0.5, y = 0.5}, alignment = {x = 0, y = 0},
		scale = {x = -100, y = -100}, text = "blank.png", z_index = 1000,
	})
	fade_shown = nil
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
-- how far you see (nodes): the fog
function hud.fog_distance()
	return hud.blind and 5 or 90
end

function hud.apply_fog(player)
	local fog = {fog_distance = hud.fog_distance(), fog_start = hud.blind and 0.1 or 0.3}
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
-- Fading the whole screen to black and back (level changes, player.lua):
-- hud.fade(1, s) to black over s seconds, hud.fade(0, s) back.
local fade = {from = 0, to = 0, t0 = 0, dur = 0}
function hud.fade_level()
	local t = fade.dur > 0 and (core.get_us_time() - fade.t0) / 1e6 / fade.dur or 1
	t = math.max(0, math.min(1, t))
	return fade.from + (fade.to - fade.from) * t
end
function hud.fade(to, seconds)
	fade = {from = hud.fade_level(), to = to, t0 = core.get_us_time(), dur = seconds or 0}
end

-- a flash of colour over the screen (full: all of it, else at its edges);
-- seconds: a long one (an exploding light) starts fully opaque and fades
-- away slowly
function hud.flash(color, strength, full, seconds)
	flash = {color = color or "#FF2020", t0 = core.get_us_time(),
		strength = math.max(0.2, math.min(1, strength or 1)), full = full, seconds = seconds}
end

-- A white flash for lightning and a camera going off (not while you're
-- blind): their hooks (sound.hook), and a lightning ray fired (rays.lua)
local WHITE_FLASH = {
	lightning = {0.85, 0.45},
	camera = {0.7, 0.3},
}
local FLASH_HOOKS = {
	artifact_lightning = "lightning", -- (Mjollnir)
	bolt_of_lightning = "lightning",  -- (a monster's spell)
	lightning_flash = "lightning",    -- (a wand of lightning: at yourself, up or
	                                  -- down, engraving, broken)
	camera_flash = "camera",
}
function hud.white_flash(kind)
	local h = nh.snap and nh.snap.hero
	local f = WHITE_FLASH[kind]
	if f and not (h and U.has(h.flags, U.HERO.BLIND)) then
		hud.flash("#FFFFFF", f[1], true, f[2])
	end
end

function hud.hook_flash(id)
	if FLASH_HOOKS[id] then
		hud.white_flash(FLASH_HOOKS[id])
	end
end

local tick = 0
core.register_globalstep(function(dtime)
	tick = tick + dtime
	local player = nhv.player.get()
	if not player or not hud.ids.msg then
		return
	end
	shake_conditions(player, dtime)
	update_map_arrow(player)
	update_map_icons(player)
	if hud.ids.fade then
		-- (steps of 8 keep the number of different textures small)
		local a = math.floor(hud.fade_level() * 255 / 8 + 0.5) * 8
		local tex = a <= 0 and "blank.png" or ("[fill:16x16:#000000^[opacity:%d"):format(math.min(255, a))
		if tex ~= fade_shown then
			fade_shown = tex
			player:hud_change(hud.ids.fade, "text", tex)
		end
	end
	if flash then
		local t = (core.get_us_time() - flash.t0) / 1e6 / (flash.seconds or FLASH_S)
		local tex = "blank.png"
		if t < 1 then
			-- (steps of 16 keep the number of different textures small)
			local k = flash.seconds and (1 - t) ^ 1.5 * 255 or (1 - t) * 230
			local a = math.min(255, math.floor(k * flash.strength / 16 + (flash.seconds and 0.999 or 0)) * 16)
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

-- ---------------------------------------------------------------- the Amulet
-- Wearing or wielding the Amulet of Yendor, now and then it feels warm,
-- very warm or hot: how near the magic portal is (wizard.c's amulet). That
-- has a line of its own, at the bottom in the middle, coloured by how near
-- - warm yellow, very warm orange, hot red - fading slowly away a second
-- after it shows; it's in the log too, not with the other messages.
local AMULET = {
	{pat = "feels? hot!$", color = 0xFF3A28},
	{pat = "feels? very warm%.$", color = 0xFF9A30},
	{pat = "feels? warm%.$", color = 0xFFE070},
}
local AMULET_HOLD, AMULET_FADE = 3.0, 4.0 -- (seconds)
local amulet_line = nil -- {id=, color=, t=} while shown

function hud.amulet_feel(text)
	if not text:find("Amulet of Yendor") then
		return false
	end
	local color
	for _, a in ipairs(AMULET) do
		if text:find(a.pat) then
			color = a.color
			break
		end
	end
	if not color then
		return false
	end
	local player = nhv.player.get()
	if not player then
		return true
	end
	core.chat_send_player(player:get_player_name(), text) -- (the log)
	-- (a line over the status line, wherever the HUD's layout has put it)
	local st = hud.ids.status and player:hud_get(hud.ids.status)
	local y = (st and st.offset and st.offset.y or -90) - 48
	if not amulet_line then
		amulet_line = {id = player:hud_add({
			type = "text", position = {x = 0.5, y = 1}, alignment = {x = 0, y = -1},
			offset = {x = 0, y = y}, size = {x = 1.5, y = 0}, number = color, text = text,
			z_index = 30,
		})}
	else
		player:hud_change(amulet_line.id, "text", text)
		player:hud_change(amulet_line.id, "offset", {x = 0, y = y})
	end
	amulet_line.color, amulet_line.t = color, core.get_us_time() / 1e6
	player:hud_change(amulet_line.id, "number", color)
	return true
end

core.register_globalstep(function()
	local line = amulet_line
	if not line then
		return
	end
	local player = nhv.player.get()
	local age = core.get_us_time() / 1e6 - line.t
	if not player or age > AMULET_HOLD + AMULET_FADE then
		if player then
			player:hud_remove(line.id)
		end
		amulet_line = nil
		return
	end
	if age > AMULET_HOLD then
		-- (fading: the colour's alpha, from solid down to nearly clear - 0
		-- would be solid again)
		local a = math.max(1, math.floor(255 * (1 - (age - AMULET_HOLD) / AMULET_FADE)))
		player:hud_change(line.id, "number", a * 0x1000000 + line.color)
	end
end)

core.register_on_leaveplayer(function()
	amulet_line = nil
end)

nh.on_event(function(evs)
	-- (offering the Amulet on your own high altar: the ascension's scene,
	-- its lines said there: cutscene.lua)
	nhv.cutscene.ascension_check(evs)
	for _, ev in ipairs(evs) do
		if (ev.kind == "message" or ev.kind == "raw") and not hud.silenced(ev.text) then
			if hud.amulet_feel(ev.text) then -- luacheck: ignore 542
				-- (its own line: above)
			elseif nhv.cutscene.ascension_line(ev.text) then
				local player = nhv.player.get()
				if player then
					core.chat_send_player(player:get_player_name(), ev.text)
				end
			elseif hud.inscription(ev.text) then
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
	show_status(player, h)
	update_meters(player, h)
	update_here(player, snap)
	if hud.big_map then
		update_tiles(player, snap)
	else
		player:hud_change(hud.ids.map, "text", map_png(snap))
	end
	place_level(player)
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
