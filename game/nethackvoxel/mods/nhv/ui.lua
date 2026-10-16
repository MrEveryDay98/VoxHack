-- Dialogs for NetHack's questions (y/n, menus, text input), text
-- windows, the inventory screen and item context menus.
--
-- While NetHack waits on a question the hero is frozen in place; time
-- can't pass anyway until it is answered.

local U = nhv.util
local nh = nhv.nh
local ui = {
	open = nil,        -- name of the request dialog on screen
	text_lines = nil,  -- collecting a text window
	pending_text = {}, -- text windows waiting to be shown
	ctx_obj = nil,     -- item whose context menu is open
}
nhv.ui = ui
ui.persistent = {} -- formspec names that stay open across commands

local E = core.formspec_escape
local function head(w, h)
	return nhv.theme.head(w, h)
end

local CHOICE_LABELS = {
	y = "Yes", n = "No", q = "Cancel", a = "All", ["#"] = "Count",
}

local function show(name, fs)
	local player = nhv.player.get()
	if player then
		if core.settings:get_bool("nhv_debug") then
			core.log("action", "[nhv] formspec " .. name .. ": " .. fs)
		end
		core.show_formspec(player:get_player_name(), name, fs)
	end
end

local function close(name)
	local player = nhv.player.get()
	if player then
		core.close_formspec(player:get_player_name(), name)
	end
end

local function wrap(text, width)
	local out, line = {}, ""
	for word in text:gmatch("%S+") do
		if #line + #word + 1 > width then
			out[#out + 1] = line
			line = word
		else
			line = (line == "") and word or (line .. " " .. word)
		end
	end
	if line ~= "" then
		out[#out + 1] = line
	end
	return table.concat(out, "\n")
end

local function inventory_by_letter()
	local inv = {}
	for _, o in ipairs((nh.snap and nh.snap.inventory) or {}) do
		inv[o.invlet] = o
	end
	return inv
end

-- ---------------------------------------------------------------- y/n
-- The question's buttons, in a row starting at (x, y).
local function yn_buttons(fs, req, x, y)
	for c in req.choices:gmatch(".") do
		if c ~= "\27" then
			local label = CHOICE_LABELS[c] or c
			if c == req.default then
				label = label .. " *"
			end
			fs[#fs + 1] = ("button[%f,%f;2,0.9;yn_%d;%s]"):format(x, y, c:byte(), E(label))
			x = x + 2.2
		end
	end
end

local function yn_dialog(req)
	local n = #req.choices
	local w = math.max(8, n * 2.2 + 1)
	local fs = {head(w, 4),
		("label[0.5,0.7;%s]"):format(E(wrap(req.prompt, math.floor(w * 5))))}
	yn_buttons(fs, req, 0.5, 2.6)
	return table.concat(fs)
end

-- A question that comes right after information windows (e.g. at the end
-- of the game: your attributes, then "Do you want to see your conduct?"):
-- one window, the information scrolling above and the question below.
local function yn_with_text(req, texts)
	local parts = {}
	for _, t in ipairs(texts) do
		if t.title and t.title ~= "" then
			parts[#parts + 1] = t.title
			parts[#parts + 1] = ""
		end
		for _, l in ipairs(t.lines) do
			parts[#parts + 1] = l
		end
		parts[#parts + 1] = ""
	end
	local fs = {head(18, 11.5),
		("textarea[0.5,0.5;17,8.2;;;%s]"):format(E(table.concat(parts, "\n"))),
		("label[0.5,9.2;%s]"):format(E(wrap(req.prompt, 85)))}
	yn_buttons(fs, req, 0.5, 10.1)
	return table.concat(fs)
end

-- ---------------------------------------------------------------- key prompt
-- "What do you want to eat? [fg or ?*]" -> list of letters
local function prompt_letters(prompt)
	local inside = prompt:match("%[([^%]]*)%]")
	if not inside then
		return {}
	end
	local spec = inside:match("^(.-) or ") or inside
	local letters = {}
	local i = 1
	while i <= #spec do
		local c = spec:sub(i, i)
		if spec:sub(i + 1, i + 1) == "-" and i + 2 <= #spec then
			local e = spec:sub(i + 2, i + 2)
			for b = c:byte(), e:byte() do
				letters[#letters + 1] = string.char(b)
			end
			i = i + 3
		else
			if c:match("[%a%$%-]") then
				letters[#letters + 1] = c
			end
			i = i + 1
		end
	end
	return letters
end

local function key_dialog(req)
	local letters = prompt_letters(req.prompt)
	local inv = inventory_by_letter()
	local rows = math.max(1, #letters)
	local h = 3.2 + math.min(rows, 10) * 0.9
	local fs = {head(10, h),
		("label[0.5,0.6;%s]"):format(E(wrap(req.prompt, 60)))}
	local y = 1.3
	fs[#fs + 1] = ("scroll_container[0.4,%f;9.2,%f;keyscroll;vertical]"):format(y, math.min(rows, 10) * 0.9)
	for k, c in ipairs(letters) do
		local o = inv[c]
		local yy = (k - 1) * 0.9
		if o then
			fs[#fs + 1] = ("item_image[0,%f;0.8,0.8;%s]"):format(yy, nhv_tiles.item(o.tile))
		end
		local label = o and (c .. " - " .. o.name) or c
		fs[#fs + 1] = ("button[1,%f;8,0.8;key_%d;%s]"):format(yy, c:byte(), E(label))
	end
	fs[#fs + 1] = "scroll_container_end[]"
	-- a scroll container needs its scrollbar to exist; park it off-screen
	-- when everything fits
	if rows > 10 then
		fs[#fs + 1] = ("scrollbaroptions[max=%d]"):format((rows - 10) * 9)
		fs[#fs + 1] = "scrollbar[9.6,1.3;0.3,9;vertical;keyscroll;0]"
	else
		fs[#fs + 1] = "scrollbar[-10,-10;0.1,0.1;vertical;keyscroll;0]"
	end
	fs[#fs + 1] = ("field[0.5,%f;3,0.8;keytext;Or type a key;]"):format(h - 1.4)
	fs[#fs + 1] = ("button[3.7,%f;2,0.8;keyok;OK]"):format(h - 1.4)
	fs[#fs + 1] = ("button[6,%f;3,0.8;key_42;Show all (*)]"):format(h - 1.4)
	fs[#fs + 1] = "field_close_on_enter[keytext;false]"
	return table.concat(fs)
end

-- ---------------------------------------------------------------- menus
local function menu_dialog(req)
	if nhv.spells and nhv.spells.is_menu(req) then
		return nhv.spells.dialog(req, head) -- (spells: Self / Target / Cast)
	end
	local items = req.items or {}
	local multi = req.menu_how == 2
	local rows = #items
	local view = math.min(rows, 12)
	local h = 2.8 + view * 0.8
	local fs = {head(13, h),
		("label[0.5,0.6;%s]"):format(E(req.prompt ~= "" and req.prompt or "Choose"))}
	fs[#fs + 1] = ("scroll_container[0.4,1.1;12.2,%f;menuscroll;vertical]"):format(view * 0.8)
	for k, it in ipairs(items) do
		local yy = (k - 1) * 0.8
		if it.tile and it.tile >= 0 then
			fs[#fs + 1] = ("item_image[0,%f;0.7,0.7;%s]"):format(yy, nhv_tiles.item(it.tile))
		end
		if it.selectable and it.sel ~= "" then
			if multi then
				fs[#fs + 1] = ("checkbox[0.9,%f;sel_%d;%s;%s]"):format(yy + 0.35, it.sel:byte(),
					E(it.sel .. " - " .. it.text), (ui.menu_sel[it.sel] and "true" or "false"))
			else
				fs[#fs + 1] = ("button[0.9,%f;11,0.7;sel_%d;%s]"):format(yy, it.sel:byte(),
					E(it.sel .. " - " .. it.text))
			end
		else
			fs[#fs + 1] = ("label[0.9,%f;%s]"):format(yy + 0.35,
				core.colorize("#FFD080", E(it.text)))
		end
	end
	fs[#fs + 1] = "scroll_container_end[]"
	if rows > 12 then
		fs[#fs + 1] = ("scrollbaroptions[max=%d]"):format((rows - 12) * 8)
		fs[#fs + 1] = ("scrollbar[12.6,1.1;0.3,%f;vertical;menuscroll;0]"):format(view * 0.8)
	else
		fs[#fs + 1] = "scrollbar[-10,-10;0.1,0.1;vertical;menuscroll;0]"
	end
	if multi then
		fs[#fs + 1] = ("button[0.5,%f;3,0.9;menu_ok;OK]"):format(h - 1.3)
		fs[#fs + 1] = ("button[3.8,%f;3,0.9;menu_all;Select all]"):format(h - 1.3)
	end
	fs[#fs + 1] = ("button[9.5,%f;3,0.9;menu_cancel;Cancel]"):format(h - 1.3)
	return table.concat(fs)
end

local function line_dialog(req)
	return head(10, 3.5)
		.. ("label[0.5,0.6;%s]"):format(E(wrap(req.prompt, 60)))
		.. "field[0.5,1.3;9,0.8;line;;]field_close_on_enter[line;false]"
		.. "button[0.5,2.4;3,0.8;line_ok;OK]button[6.5,2.4;3,0.8;line_cancel;Cancel]"
end

-- ---------------------------------------------------------------- requests
local function show_request(req)
	ui.req = req
	if req.kind == "yn" and req.choices == "" then
		-- some questions carry their choices in the text: "... [ynaq]"
		local inside = req.prompt:match("%[([%a%-%*%$#]+)%]")
		if inside then
			req.choices = inside
		end
	end
	if nhv.spells.is_zap(req) then
		ui.open = "nhv:req"
		show("nhv:req", nhv.spells.wand_dialog(req, head)) -- (wands: Self / Target)
	elseif req.kind == "yn" and req.choices ~= "" then
		ui.open = "nhv:req"
		if #ui.pending_text > 0 then
			-- (the information waiting to be read goes above the question)
			local texts = ui.pending_text
			ui.pending_text = {}
			show("nhv:req", yn_with_text(req, texts))
		else
			show("nhv:req", yn_dialog(req))
		end
	elseif req.kind == "menu" then
		ui.menu_sel = {}
		for _, it in ipairs(req.items or {}) do
			if it.preselected and it.sel ~= "" then
				ui.menu_sel[it.sel] = true
			end
		end
		ui.open = "nhv:req"
		show("nhv:req", menu_dialog(req))
	elseif req.kind == "line" then
		ui.open = "nhv:req"
		show("nhv:req", line_dialog(req))
	else
		ui.open = "nhv:req"
		show("nhv:req", key_dialog(req))
	end
	nhv.player.freeze(true)
	nhv.sound.hook("dialog_open")
end

nh.on_request(function(req)
	if req.kind == "key" and req.for_command then
		-- panels that stay open across commands (e.g. a container) keep you put
		if ui.open and ui.persistent[ui.open] then
			return true
		end
		if ui.open then
			close(ui.open)
			ui.open = nil
		end
		nhv.player.freeze(false)
		for k = #ui.auto_answers, 1, -1 do
			if ui.auto_answers[k].this_command then
				table.remove(ui.auto_answers, k)
			end
		end
		ui.show_pending_text()
		return true
	end
	if req.kind == "extcmd" then
		nh.answer_text("")
		return true
	end
	-- queued answers (e.g. which hand a ring goes on; a readied spell's
	-- menu choice and direction)
	-- (ones that timed out are dropped: e.g. the direction for a spell that
	-- failed before asking for one mustn't answer a later question)
	local now = core.get_us_time()
	for k = #ui.auto_answers, 1, -1 do
		local t = ui.auto_answers[k].t
		if t and now - t > 5e6 then
			table.remove(ui.auto_answers, k)
		end
	end
	for k, aa in ipairs(ui.auto_answers) do
		if req.prompt:find(aa.pattern) and (aa.menu ~= nil) == (req.kind == "menu") then
			table.remove(ui.auto_answers, k)
			if aa.menu then
				nh.answer_menu(aa.menu)
			else
				nh.answer_key(aa.key)
			end
			return true
		end
	end
	-- direction prompts are answered by where you are looking
	-- (they may come as a key or a y/n style question)
	if (req.kind == "key" or req.kind == "yn") and req.prompt:lower():find("direction") then
		local player = nhv.player.get()
		if player then
			nh.answer_key(nhv.actions.pointed_dir_key(player, req.prompt))
			return true
		end
	end
	-- --More---style "press a key" prompts from NetHack's own code
	if req.kind == "key" and req.prompt == "" then
		nh.answer_key(27)
		return true
	end
	show_request(req)
	return true
end)

-- show NetHack's current question again (the watchdog in loop.lua: the
-- game was waiting on one with nothing on screen)
function ui.reshow()
	if nh.state == "waiting" and nh.req and not nh.ready() then
		show_request(nh.req)
		return true
	end
	return false
end

local function answered()
	ui.open = nil
	ui.req = nil
end

core.register_on_player_receive_fields(function(player, formname, fields)
	if formname == "nhv:req" then
		local req = ui.req
		if not req or nh.state ~= "waiting" then
			return true
		end
		if nhv.spells.is_zap(req) and nhv.spells.wand_fields(fields, function(key)
			answered()
			close("nhv:req")
			nh.answer_key(key)
		end, function(pattern, key)
			-- (dropped at the next command: a wand that needs no direction
			-- never asks, and it mustn't answer a later question)
			table.insert(ui.auto_answers, {pattern = pattern, key = key,
				t = core.get_us_time(), this_command = true})
		end) then
			return true
		end
		if nhv.spells.is_menu(req) and nhv.spells.fields(fields, req, function(sels)
			answered()
			close("nhv:req")
			nh.answer_menu(sels)
		end, function(pattern, key)
			table.insert(ui.auto_answers, {pattern = pattern, key = key, t = core.get_us_time()})
		end) then
			return true
		end
		for k in pairs(fields) do
			local yn = k:match("^yn_(%d+)$") or k:match("^key_(%d+)$")
			if yn then
				answered()
				close("nhv:req")
				nh.answer_key(tonumber(yn))
				return true
			end
			local sel = k:match("^sel_(%d+)$")
			if sel then
				local c = string.char(tonumber(sel))
				if req.menu_how == 2 then
					ui.menu_sel[c] = fields[k] == "true"
				else
					answered()
					close("nhv:req")
					nh.answer_menu(c)
				end
				return true
			end
		end
		if fields.menu_ok or fields.menu_all then
			local s = ""
			if fields.menu_all then
				s = "\1"
			else
				for c, on in pairs(ui.menu_sel) do
					if on then
						s = s .. c
					end
				end
			end
			answered()
			close("nhv:req")
			nh.answer_menu(s)
			return true
		end
		if (fields.keyok or fields.key_enter_field == "keytext") and fields.keytext
				and fields.keytext ~= "" then
			answered()
			close("nhv:req")
			nh.answer_key(fields.keytext:sub(1, 1))
			return true
		end
		if fields.line_ok or fields.key_enter_field == "line" then
			answered()
			close("nhv:req")
			nh.answer_text(fields.line or "")
			return true
		end
		if fields.menu_cancel or fields.line_cancel or fields.quit then
			answered()
			-- (Esc already closed it; the Cancel button didn't)
			close("nhv:req")
			if req.kind == "menu" then
				nh.answer_menu("")
			elseif req.kind == "line" then
				nh.answer_text("\27")
			else
				nh.answer_key(27)
			end
			return true
		end
		return true
	elseif formname == "nhv:item" then
		ui.item_fields(player, fields)
		return true
	elseif formname == "nhv:text" then
		if fields.quit or fields.text_ok then
			ui.text_open = false
			ui.show_pending_text()
		end
		return true
	elseif formname == "" then
		-- inventory screen (keep where the list was scrolled to)
		local sc = fields.invscroll and tonumber(fields.invscroll:match("%d+"))
		if sc then
			ui.inv_scroll = sc
		end
		for k in pairs(fields) do
			local l = k:match("^inv_(%d+)$")
			if l then
				ui.show_item_menu(string.char(tonumber(l)))
				return true
			end
		end
	end
end)

-- ---------------------------------------------------------------- text windows
local function text_dialog(title, lines)
	local body = table.concat(lines, "\n")
	return head(14, 10)
		.. ("label[0.5,0.6;%s]"):format(E(title ~= "" and title or ""))
		.. ("textarea[0.5,1;13,7.8;;;%s]"):format(E(body))
		.. "button_exit[5.5,9;3,0.8;text_ok;OK]"
end

function ui.show_pending_text()
	if ui.text_open or ui.open or #ui.pending_text == 0 then
		return
	end
	local t = table.remove(ui.pending_text, 1)
	ui.text_open = true
	show("nhv:text", text_dialog(t.title, t.lines))
end

nh.on_event(function(evs)
	for _, ev in ipairs(evs) do
		if ev.kind == "message" and ev.text:find("^Saving") then
			ui.saving = true
		end
		if ev.kind == "text_begin" then
			ui.text_lines = {title = ev.text, lines = {}}
		elseif ev.kind == "text_line" and ui.text_lines then
			table.insert(ui.text_lines.lines, ev.text)
		elseif ev.kind == "text_end" and ui.text_lines then
			local t = ui.text_lines
			ui.text_lines = nil
			-- skip windows that are all blank
			local any = false
			for _, l in ipairs(t.lines) do
				if l:find("%S") then
					any = true
				end
			end
			if any then
				-- short single-line windows read better as messages
				if #t.lines <= 2 then
					for _, l in ipairs(t.lines) do
						nhv.hud.message(l)
					end
				else
					table.insert(ui.pending_text, t)
					if ui.dead then
						ui.show_death()
					end
				end
			end
		end
	end
end)

-- ---------------------------------------------------------------- inventory
local OC = U.OCLASS
local CLASS_NAMES = {
	[OC.WEAPON] = "Weapons", [OC.ARMOR] = "Armor", [OC.RING] = "Rings",
	[OC.AMULET] = "Amulets", [OC.TOOL] = "Tools", [OC.FOOD] = "Comestibles",
	[OC.POTION] = "Potions", [OC.SCROLL] = "Scrolls", [OC.SPBOOK] = "Spellbooks",
	[OC.WAND] = "Wands", [OC.COIN] = "Coins", [OC.GEM] = "Gems/Stones",
	[OC.ROCK] = "Boulders/Statues", [OC.BALL] = "Iron balls", [OC.CHAIN] = "Chains",
	[OC.VENOM] = "Venoms",
}

-- Equipment slots (like Minecraft's armor slots): one per place NetHack
-- lets you wear or wield something. mask = owornmask bit.
local W = {
	ARM = 0x1, ARMC = 0x2, ARMH = 0x4, ARMS = 0x8, ARMG = 0x10, ARMF = 0x20,
	ARMU = 0x40, WEP = 0x100, QUIVER = 0x200, SWAPWEP = 0x400, AMUL = 0x10000,
	RINGL = 0x20000, RINGR = 0x40000, TOOL = 0x80000,
}
-- armcat values: SUIT 0, SHIELD 1, HELM 2, GLOVES 3, BOOTS 4, CLOAK 5, SHIRT 6
local EQUIP = {
	{id = "amulet", label = "Amulet", mask = W.AMUL, col = 0, row = 0, oclass = OC.AMULET, put = "P"},
	{id = "helm", label = "Helmet", mask = W.ARMH, col = 1, row = 0, armcat = 2},
	{id = "eyes", label = "Eyewear", mask = W.TOOL, col = 2, row = 0, eyewear = true, put = "P"},
	{id = "cloak", label = "Cloak", mask = W.ARMC, col = 0, row = 1, armcat = 5},
	{id = "suit", label = "Body armor", mask = W.ARM, col = 1, row = 1, armcat = 0},
	{id = "shirt", label = "Shirt", mask = W.ARMU, col = 2, row = 1, armcat = 6},
	{id = "gloves", label = "Gloves", mask = W.ARMG, col = 0, row = 2, armcat = 3},
	{id = "shield", label = "Shield", mask = W.ARMS, col = 2, row = 2, armcat = 1},
	{id = "lring", label = "Left ring", mask = W.RINGL, col = 0, row = 3, oclass = OC.RING, put = "P", hand = "l"},
	{id = "boots", label = "Boots", mask = W.ARMF, col = 1, row = 3, armcat = 4},
	{id = "rring", label = "Right ring", mask = W.RINGR, col = 2, row = 3, oclass = OC.RING, put = "P", hand = "r"},
	{id = "wep", label = "Weapon", mask = W.WEP, col = 0, row = 4.3, weapon = true},
	{id = "alt", label = "Alternate", mask = W.SWAPWEP, col = 1, row = 4.3, weapon = true},
	{id = "quiver", label = "Quiver", mask = W.QUIVER, col = 2, row = 4.3, quiver = true},
}
local EQUIP_BY_ID = {}
for _, e in ipairs(EQUIP) do
	EQUIP_BY_ID[e.id] = e
end

local function has_mask(o, m)
	return (o.worn or 0) % (m * 2) >= m
end

local function fits(slot, o)
	if slot.armcat then
		return o.oclass == OC.ARMOR and o.armcat == slot.armcat
	elseif slot.oclass then
		return o.oclass == slot.oclass
	elseif slot.eyewear then
		local n = o.name:lower()
		return o.oclass == OC.TOOL and (n:find("blindfold") or n:find("towel") or n:find("lenses")) ~= nil
	elseif slot.weapon then
		return o.oclass == OC.WEAPON or o.oclass == OC.TOOL
	elseif slot.quiver then
		return o.oclass == OC.WEAPON or o.oclass == OC.GEM or o.oclass == OC.ROCK
	end
	return false
end

local function equipped(slot, inv)
	for _, o in ipairs(inv) do
		if has_mask(o, slot.mask) then
			return o
		end
	end
end

-- One clickable inventory row: the item's sprite and its name (also used by
-- the container screen). field = the button name, w = width of the name.
function ui.item_row(fs, o, x, y, field, w, text)
	local max = math.floor(w * 9)
	if #text > max then
		text = text:sub(1, max - 2) .. ".."
	end
	if nhv.theme.retro() then -- (plain text, lit up blue under the mouse)
		fs[#fs + 1] = ("style[%s;border=false;bgimg=blank.png;bgimg_hovered=[fill:8x8:#0000AA;"
			.. "bgimg_pressed=[fill:8x8:#000078]"):format(field)
	end
	fs[#fs + 1] = ("item_image_button[%f,%f;0.7,0.7;%s;%s;]"):format(x, y, nhv_tiles.item(o.tile), field)
	-- left-aligned text over an invisible button
	fs[#fs + 1] = ("image_button[%f,%f;%f,0.7;blank.png;%s;]"):format(x + 0.8, y, w, field)
	fs[#fs + 1] = ("label[%f,%f;%s]"):format(x + 0.9, y + 0.35, E(text))
	fs[#fs + 1] = ("tooltip[%s;%s]"):format(field, E(o.name))
end
ui.CLASS_NAMES = CLASS_NAMES
ui.head = head

-- NetHack's usual inventory order: $ " ) [ % ? + ! = / ( * ` 0 _
local INV_ORDER = {}
for i, c in ipairs({OC.COIN, OC.AMULET, OC.WEAPON, OC.ARMOR, OC.FOOD, OC.SCROLL, OC.SPBOOK,
		OC.POTION, OC.RING, OC.WAND, OC.TOOL, OC.GEM, OC.ROCK, OC.BALL, OC.CHAIN, OC.VENOM}) do
	INV_ORDER[c] = i
end

local function inventory_formspec(inv)
	local fs = {head(19, 11), "label[0.4,0.5;Equipment]",
		"label[5.6,0.5;Inventory  (click an item for actions)]",
		"button[16.6,0.15;2.1,0.7;graphics;Options]",
		"box[0.3,0.9;4.9,9.6;#00000060]"}
	-- equipment panel
	for _, slot in ipairs(EQUIP) do
		local x, y = 0.55 + slot.col * 1.55, 1.1 + slot.row * 1.75
		local o = equipped(slot, inv)
		if o then
			fs[#fs + 1] = ("item_image_button[%f,%f;1.3,1.3;%s;eq_%s;]"):format(x, y,
				nhv_tiles.item(o.tile), slot.id)
			fs[#fs + 1] = ("tooltip[eq_%s;%s]"):format(slot.id, E(slot.label .. ": " .. o.name))
		else
			fs[#fs + 1] = ("button[%f,%f;1.3,1.3;eq_%s;]"):format(x, y, slot.id)
			fs[#fs + 1] = ("tooltip[eq_%s;%s (empty)]"):format(slot.id, E(slot.label))
		end
		fs[#fs + 1] = ("label[%f,%f;%s]"):format(x, y + 1.45,
			core.colorize("#B0B0B0", E(slot.label)))
	end
	-- inventory list: one scrolling column, grouped by kind in NetHack's
	-- usual order, letters in order within each group
	local sorted = {}
	for i, o in ipairs(inv) do
		sorted[i] = o
	end
	table.sort(sorted, function(a, b)
		local ca, cb = INV_ORDER[a.oclass] or 99, INV_ORDER[b.oclass] or 99
		if ca ~= cb then
			return ca < cb
		end
		return a.invlet < b.invlet
	end)
	local VIEW_H = 9.8
	local rows, y = {}, 0.05
	local last_class
	for _, o in ipairs(sorted) do
		if o.oclass ~= last_class then
			last_class = o.oclass
			rows[#rows + 1] = ("label[0.1,%f;%s]"):format(y + 0.25,
				core.colorize("#FFD080", CLASS_NAMES[o.oclass] or "Other"))
			y = y + 0.55
		end
		ui.item_row(rows, o, 0.1, y, "inv_" .. o.invlet:byte(), 11.6, o.invlet .. " - " .. o.name)
		y = y + 0.75
	end
	fs[#fs + 1] = ("scroll_container[5.4,0.95;12.9,%s;invscroll;vertical;0.1]"):format(VIEW_H)
	fs[#fs + 1] = table.concat(rows)
	fs[#fs + 1] = "scroll_container_end[]"
	local over = y - VIEW_H
	if over > 0 then
		local max = math.ceil(over / 0.1)
		ui.inv_scroll = math.min(ui.inv_scroll or 0, max)
		fs[#fs + 1] = ("scrollbaroptions[max=%d;smallstep=5;largestep=40]"):format(max)
		fs[#fs + 1] = ("scrollbar[18.45,0.95;0.35,%s;vertical;invscroll;%d]"):format(VIEW_H, ui.inv_scroll)
	else
		ui.inv_scroll = 0
	end
	if #inv == 0 then
		fs[#fs + 1] = "label[5.6,1.5;Not carrying anything.]"
	end
	return table.concat(fs)
end

-- clicking an empty equipment slot: choose something that fits
local function show_equip_choices(slot)
	local inv = (nh.snap and nh.snap.inventory) or {}
	local items = {}
	for _, o in ipairs(inv) do
		if fits(slot, o) and (slot.weapon or slot.quiver or (o.worn or 0) == 0) then
			items[#items + 1] = o
		end
	end
	ui.equip_slot, ui.equip_items = slot, items
	local h = 2.2 + math.max(1, #items) * 0.85
	local fs = {head(10, h), ("label[0.5,0.6;%s]"):format(E(slot.label .. ": choose an item"))}
	for k, o in ipairs(items) do
		local yy = 1.1 + (k - 1) * 0.85
		fs[#fs + 1] = ("item_image[0.5,%f;0.75,0.75;%s]"):format(yy, nhv_tiles.item(o.tile))
		fs[#fs + 1] = ("button[1.4,%f;8,0.75;pick_%d;%s]"):format(yy, k, E(o.invlet .. " - " .. o.name))
	end
	if #items == 0 then
		fs[#fs + 1] = "label[0.5,1.4;You have nothing that goes here.]"
	end
	show("nhv:equip", table.concat(fs))
end

-- answers to follow-up questions, e.g. which hand for a ring
ui.auto_answers = {}

local function equip_item(slot, o)
	local cur
	for _, it in ipairs(nh.snap.inventory) do
		if has_mask(it, W.WEP) then
			cur = it
		end
	end
	local keys
	if slot.armcat then
		keys = "W" .. o.invlet
	elseif slot.put then
		keys = slot.put .. o.invlet
		if slot.hand then
			table.insert(ui.auto_answers, {pattern = "ring%-finger", key = slot.hand})
		end
	elseif slot.id == "wep" then
		keys = "w" .. o.invlet
	elseif slot.id == "alt" then
		-- NetHack only swaps: wield it, swap it to the off hand, re-wield
		keys = "w" .. o.invlet .. "x"
			.. ((cur and cur.invlet ~= o.invlet) and ("w" .. cur.invlet) or "")
	elseif slot.quiver then
		keys = "Q" .. o.invlet
	end
	if keys then
		nhv.clock.act(keys, {kind = "equip"})
	end
end

nh.on_snapshot(function(snap)
	local player = nhv.player.get()
	if not snap or not player then
		return
	end
	player:set_inventory_formspec(inventory_formspec(snap.inventory))
end)

core.register_on_player_receive_fields(function(player, formname, fields)
	if formname == "" then
		for k in pairs(fields) do
			local id = k:match("^eq_(%w+)$")
			if id and EQUIP_BY_ID[id] then
				local slot = EQUIP_BY_ID[id]
				local o = equipped(slot, (nh.snap and nh.snap.inventory) or {})
				if o then
					ui.show_item_menu(o.invlet)
				else
					show_equip_choices(slot)
				end
				return true
			end
		end
	elseif formname == "nhv:equip" then
		for k in pairs(fields) do
			local n = k:match("^pick_(%d+)$")
			if n and ui.equip_items and ui.equip_items[tonumber(n)] then
				close("nhv:equip")
				if nh.ready() then
					equip_item(ui.equip_slot, ui.equip_items[tonumber(n)])
				end
				return true
			end
		end
		return true
	end
end)

-- ---------------------------------------------------------------- item menu
function ui.show_item_menu(invlet)
	local o = inventory_by_letter()[invlet]
	if not o or not nh.ready() then
		return
	end
	ui.ctx_obj = o
	local acts = nhv.actions.item_actions(o)
	local h = 2.4 + #acts * 0.85
	local fs = {head(9, h),
		("item_image[0.4,0.3;1,1;%s]"):format(nhv_tiles.item(o.tile)),
		("label[1.6,0.8;%s]"):format(E(wrap(o.invlet .. " - " .. o.name, 40)))}
	for k, a in ipairs(acts) do
		fs[#fs + 1] = ("button[0.5,%f;8,0.75;act_%d;%s]"):format(1.6 + (k - 1) * 0.85, k, E(a.label))
	end
	ui.ctx_acts = acts
	show("nhv:item", table.concat(fs))
end

function ui.item_fields(player, fields)
	for k in pairs(fields) do
		local n = k:match("^act_(%d+)$")
		if n then
			local a = ui.ctx_acts and ui.ctx_acts[tonumber(n)]
			close("nhv:item")
			if a and ui.ctx_obj then
				nhv.actions.do_item_action(player, ui.ctx_obj, a)
			end
			return
		end
	end
end

-- ---------------------------------------------------------------- death
function ui.show_death()
	local lines = {}
	for _, t in ipairs(ui.pending_text) do
		for _, l in ipairs(t.lines) do
			lines[#lines + 1] = l
		end
		lines[#lines + 1] = ""
	end
	ui.pending_text = {}
	show("nhv:dead", head(14, 11)
		.. "label[0.5,0.6;" .. E(ui.end_title or "Your game is over.") .. "]"
		.. ("textarea[0.5,1;13,8.6;;;%s]"):format(E(table.concat(lines, "\n")))
		.. "button[4,9.9;6,0.9;totitle;Back to the title screen]")
end

core.register_on_player_receive_fields(function(player, formname, fields)
	if formname ~= "nhv:dead" then
		return
	end
	if fields.totitle then
		ui.dead = false
		close("nhv:dead")
		nhv.title.show(player)
	elseif fields.quit and ui.dead then
		ui.show_death()
	end
	return true
end)

nh.on_snapshot(function(snap, info)
	if snap or not info or not info.ended then
		return
	end
	if ui.open then
		close(ui.open)
		ui.open = nil
	end
	nhv.player.freeze(true)
	if ui.to_title then
		-- (saved from the pause menu: straight to the title screen)
		ui.to_title = false
		ui.saving = false
		nhv.hud.messages = {} -- (a fresh start on the title screen)
		local player = nhv.player.get()
		if player then
			core.after(0.2, nhv.title.show, player)
		end
		return
	end
	ui.dead = true
	ui.end_title = ui.saving and "Game saved. Continue it from the title screen."
		or "Your game is over."
	ui.saving = false
	core.after(0.2, ui.show_death)
end)

return ui
