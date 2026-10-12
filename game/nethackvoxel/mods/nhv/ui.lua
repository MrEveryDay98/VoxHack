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

local E = core.formspec_escape
local function head(w, h)
	return ("formspec_version[6]size[%s,%s]"):format(w, h)
		.. "bgcolor[#000000C0;true]style_type[button;bgcolor=#303040]"
		.. "style_type[label;textcolor=#E0E0E0]"
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
local function yn_dialog(req)
	local choices = req.choices
	local n = #choices
	local w = math.max(8, n * 2.2 + 1)
	local fs = {head(w, 4),
		("label[0.5,0.7;%s]"):format(E(wrap(req.prompt, math.floor(w * 5))))}
	local x = 0.5
	for c in choices:gmatch(".") do
		if c ~= "\27" then
			local label = CHOICE_LABELS[c] or c
			if c == req.default then
				label = label .. " *"
			end
			fs[#fs + 1] = ("button[%f,2.6;2,0.9;yn_%d;%s]"):format(x, c:byte(), E(label))
			x = x + 2.2
		end
	end
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
	if req.kind == "yn" and req.choices ~= "" then
		ui.open = "nhv:req"
		show("nhv:req", yn_dialog(req))
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
end

nh.on_request(function(req)
	if req.kind == "key" and req.for_command then
		if ui.open then
			close(ui.open)
			ui.open = nil
		end
		nhv.player.freeze(false)
		ui.show_pending_text()
		return true
	end
	if req.kind == "extcmd" then
		nh.answer_text("")
		return true
	end
	-- direction prompts are answered by where you are looking
	if req.kind == "key" and req.prompt:lower():find("direction") then
		local player = nhv.player.get()
		if player then
			nh.answer_key(nhv.player.look_dir_key(player))
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
		-- inventory screen
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

local function inventory_formspec(inv)
	local fs = {head(16, 11), "label[0.5,0.5;Inventory  (click an item for actions)]"}
	local x, y = 0.5, 1.0
	local col_w = 7.6
	local last_class
	for _, o in ipairs(inv) do
		if o.oclass ~= last_class then
			last_class = o.oclass
			if y > 9.8 then
				x, y = x + col_w, 1.0
			end
			fs[#fs + 1] = ("label[%f,%f;%s]"):format(x, y + 0.25,
				core.colorize("#FFD080", CLASS_NAMES[o.oclass] or "Other"))
			y = y + 0.55
		end
		if y > 10.2 then
			x, y = x + col_w, 1.0
		end
		fs[#fs + 1] = ("item_image_button[%f,%f;0.7,0.7;%s;inv_%d;]"):format(x, y,
			nhv_tiles.item(o.tile), o.invlet:byte())
		local name = o.invlet .. " - " .. o.name
		if #name > 52 then
			name = name:sub(1, 50) .. ".."
		end
		fs[#fs + 1] = ("button[%f,%f;6.7,0.7;inv_%d;%s]"):format(x + 0.8, y, o.invlet:byte(), E(name))
		fs[#fs + 1] = ("tooltip[inv_%d;%s]"):format(o.invlet:byte(), E(o.name))
		y = y + 0.75
	end
	if #inv == 0 then
		fs[#fs + 1] = "label[0.5,1.5;Not carrying anything.]"
	end
	return table.concat(fs)
end

-- Hotbar mirrors the inventory (first slots = first items).
local function sync_hotbar(player, inv)
	local pinv = player:get_inventory()
	pinv:set_size("main", 32)
	pinv:set_size("craft", 0)
	local list = {}
	for i, o in ipairs(inv) do
		if i > 32 then
			break
		end
		local st = ItemStack(nhv_tiles.item(o.tile))
		st:set_count(math.max(1, math.min(o.quan, 65535)))
		local meta = st:get_meta()
		meta:set_string("description", o.invlet .. " - " .. o.name)
		meta:set_string("nhv_invlet", o.invlet)
		meta:set_string("count_meta", o.quan > 1 and tostring(o.quan) or "")
		list[i] = st
	end
	for i = #list + 1, 32 do
		list[i] = ItemStack("")
	end
	pinv:set_list("main", list)
end

nh.on_snapshot(function(snap)
	local player = nhv.player.get()
	if not snap or not player then
		return
	end
	player:set_inventory_formspec(inventory_formspec(snap.inventory))
	sync_hotbar(player, snap.inventory)
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
		.. "button[0.5,9.9;6,0.9;newgame;" .. (ui.end_title:find("saved") and "Continue" or "Start a new game") .. "]"
		.. "button[7.5,9.9;6,0.9;quitgame;Quit to menu]")
end

core.register_on_player_receive_fields(function(player, formname, fields)
	if formname ~= "nhv:dead" then
		return
	end
	if fields.newgame then
		ui.dead = false
		close("nhv:dead")
		nhv.new_game(player)
	elseif fields.quitgame then
		core.disconnect_player(player:get_player_name(), "Farewell.")
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
	ui.dead = true
	ui.end_title = ui.saving and "Game saved. Rejoin this world to continue."
		or "Your game is over."
	ui.saving = false
	core.after(0.2, ui.show_death)
end)

return ui
