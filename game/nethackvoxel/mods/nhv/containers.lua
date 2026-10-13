-- Containers (chests, boxes, bags): opened into a screen laid out like the
-- inventory, your items on the left and the container's on the right.
-- Click an item to move it across ("1" moves just one of a stack).
--
-- Opening goes through NetHack ("#nhvloot <id>": locks, chest traps,
-- cursed bags of holding... all still apply), and so does every move
-- ("#nhvcontin" / "#nhvcontout"); the lists are rebuilt from NetHack after
-- each one, so anything it refuses simply snaps back.
-- Time stands still while the panel is open, as in NetHack's own menus.

local nh = nhv.nh
local E = core.formspec_escape
local containers = {queue = {}}
nhv.containers = containers

local FORM = "nhv:container"
nhv.ui.persistent[FORM] = true
local CONTAINER_TYPES = {
	["large box"] = true, ["chest"] = true, ["ice box"] = true,
	["sack"] = true, ["oilskin sack"] = true, ["bag of holding"] = true,
}

function containers.is_container(o)
	return o and CONTAINER_TYPES[core.nh_obj_name(o.otyp) or ""] == true
end

-- "a large box" -> "large box" (for labels)
local function short(o)
	return (o.name:gsub("^an? ", ""):gsub("^the ", ""))
end

-- ---------------------------------------------------------------- open/close
local function player_name()
	local p = nhv.player.get()
	return p and p:get_player_name()
end

local function command(text)
	table.insert(containers.queue, {{key = "#"}, {text = text}})
end

function containers.open(id)
	command("nhvloot " .. id)
end

local function close_panel()
	if containers.cid and nhv.ui.open == FORM then
		nhv.ui.open = nil
		nhv.player.freeze(false)
	end
	containers.cid = nil
	local name = player_name()
	if name then
		core.close_formspec(name, FORM)
	end
end

-- ---------------------------------------------------------------- the screen
-- Laid out like the inventory screen: rows of items grouped by kind, yours
-- on the left and the container's on the right. Click an item to move it
-- across; "1" moves just one of a stack.
local function total_weight(objs)
	local w = 0
	for _, o in ipairs(objs) do
		w = w + (o.weight or 0)
	end
	return w
end

local function container_obj(id)
	for _, o in ipairs((nh.snap and nh.snap.inventory) or {}) do
		if o.id == id then
			return o
		end
	end
	local h = nh.snap and nh.snap.hero
	if h then
		for dx = -1, 1 do
			for dy = -1, 1 do
				for _, o in ipairs(core.nh_get_floor_objects(h.x + dx, h.y + dy) or {}) do
					if o.id == id then
						return o
					end
				end
			end
		end
	end
end

-- a scrolling column of item rows; dir = "in" (yours) or "out" (container's)
local function column(fs, objs, x, w, dir, empty_text)
	local ui = nhv.ui
	local view_h = 8.9
	fs[#fs + 1] = ("scroll_container[%f,1.55;%f,%f;scroll_%s;vertical;0.1]"):format(x, w + 0.2, view_h, dir)
	local y = 0.05
	local last_class
	for _, o in ipairs(objs) do
		if o.oclass ~= last_class then
			last_class = o.oclass
			fs[#fs + 1] = ("label[0.05,%f;%s]"):format(y + 0.25,
				core.colorize("#FFD080", ui.CLASS_NAMES[o.oclass] or "Other"))
			y = y + 0.55
		end
		local text = (dir == "in" and (o.invlet .. " - ") or "") .. o.name
		ui.item_row(fs, o, 0.05, y, dir .. "_" .. o.id, w - 1.85, text)
		if o.quan > 1 then
			fs[#fs + 1] = ("button[%f,%f;0.85,0.7;one%s_%d;1]"):format(w - 0.9, y, dir, o.id)
			fs[#fs + 1] = ("tooltip[one%s_%d;Move just one]"):format(dir, o.id)
		end
		y = y + 0.75
	end
	if #objs == 0 then
		fs[#fs + 1] = ("label[0.1,0.4;%s]"):format(core.colorize("#909090", empty_text))
	end
	fs[#fs + 1] = "scroll_container_end[]"
	fs[#fs + 1] = ("scrollbaroptions[max=%d;smallstep=7;largestep=40]"):format(
		math.max(0, math.ceil((y - view_h) * 10)))
	fs[#fs + 1] = ("scrollbar[%f,1.55;0.3,%f;vertical;scroll_%s;0]"):format(x + w + 0.25, view_h, dir)
end

local function formspec(cont, contents, mine)
	local E = core.formspec_escape
	local fs = {nhv.ui.head(19, 11.5)}
	local cname = cont and cont.name:gsub("^an? ", "") or "container"
	fs[#fs + 1] = ("label[0.4,0.5;%s]"):format(core.colorize("#FFFFFF", "Your inventory"))
	fs[#fs + 1] = ("label[0.4,0.95;%s]"):format(core.colorize("#A0A0A0",
		("%d items, weight %d   (click an item to put it in)"):format(#mine, total_weight(mine))))
	fs[#fs + 1] = ("label[9.9,0.5;%s]"):format(core.colorize("#FFD080", E(cname:sub(1, 1):upper() .. cname:sub(2))))
	fs[#fs + 1] = ("label[9.9,0.95;%s]"):format(core.colorize("#A0A0A0",
		("%d items, weight %d   (click an item to take it out)"):format(#contents, total_weight(contents))))
	fs[#fs + 1] = "box[0.3,1.45;8.95,9.1;#00000060]"
	fs[#fs + 1] = "box[9.75,1.45;8.95,9.1;#ffd0800f]"
	column(fs, mine, 0.4, 8.4, "in", "Not carrying anything.")
	column(fs, contents, 9.85, 8.4, "out", "Empty.")
	fs[#fs + 1] = "button_exit[16.2,10.75;2.5,0.6;close;Close]"
	return table.concat(fs)
end

-- rebuild both lists from NetHack and (re)show the panel
function containers.refresh()
	local id = containers.cid
	if not id then
		return
	end
	local contents = core.nh_get_container(id)
	if not contents then
		close_panel() -- out of reach, destroyed, ...
		return
	end
	local mine = {}
	for _, o in ipairs((nh.snap and nh.snap.inventory) or {}) do
		if o.id ~= id then -- the bag you're looking into stays out of its own list
			mine[#mine + 1] = o
		end
	end
	local name = player_name()
	if name then
		nhv.ui.open = FORM
		nhv.player.freeze(true)
		core.show_formspec(name, FORM, formspec(container_obj(id), contents, mine))
	end
end

-- ---------------------------------------------------------------- NetHack
nh.on_event(function(evs)
	for _, ev in ipairs(evs) do
		if ev.kind == "container" then
			local what, id = ev.text:match("^(%a+) (%d+)$")
			id = tonumber(id)
			if what == "open" then
				containers.cid = id
				containers.pending_refresh = true
				nhv.sound.hook("container_open")
			elseif what == "gone" then
				close_panel()
			elseif id == containers.cid then
				containers.pending_refresh = true -- changed, or refused: redraw
				if what == "changed" then
					nhv.sound.hook("container_move")
				end
			end
		end
	end
end)

-- lists follow the inventory once NetHack has the new state
nh.on_snapshot(function(snap)
	if not snap then
		close_panel()
		return
	end
	if containers.cid and containers.pending_refresh and nh.ready() then
		containers.pending_refresh = false
		containers.refresh()
	end
end)

core.register_globalstep(function()
	while #containers.queue > 0 and nh.ready() do
		nh.act(table.remove(containers.queue, 1), {kind = "container"})
	end
end)

core.register_on_player_receive_fields(function(_, formname, fields)
	if formname ~= FORM then
		return false
	end
	if containers.cid and nh.ready() then
		for k in pairs(fields) do
			local dir, id = k:match("^one(%a+)_(%d+)$")
			local one = dir ~= nil
			if not dir then
				dir, id = k:match("^(%a+)_(%d+)$")
			end
			if (dir == "in" or dir == "out") and id then
				command(("nhvcont%s %d %s %d"):format(dir, containers.cid, id, one and 1 or 0))
				return true
			end
		end
	end
	if fields.quit or fields.close then
		containers.cid = nil
		if nhv.ui.open == FORM then
			nhv.ui.open = nil
			nhv.player.freeze(false)
		end
		nhv.sound.hook("container_close")
	end
	return true
end)

function containers.clear()
	containers.queue = {}
	close_panel()
end

return containers
