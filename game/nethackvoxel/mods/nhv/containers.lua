-- Containers (chests, boxes, bags): opened into a panel with two lists,
-- your inventory and the container's contents. Drag items between them
-- (or shift-click to send one straight across).
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
local COLS, ROWS = 8, 6 -- slots shown per list (the lists scroll if longer)
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

-- ---------------------------------------------------------------- lists
local inv = core.create_detached_inventory("nhv_container", {
	allow_move = function(_, from_list, _, to_list, _, count)
		if from_list == to_list or not containers.cid then
			return 0 -- only between the two lists
		end
		return count
	end,
	allow_put = function() return 0 end,
	allow_take = function() return 0 end,
	on_move = function(detinv, from_list, _, to_list, to_index, count)
		-- the moved stack is already in its new slot; read which object it was
		local st = detinv:get_stack(to_list, to_index)
		local oid = tonumber(st:get_meta():get_string("nhv_oid")) or 0
		local quan = tonumber(st:get_meta():get_string("nhv_quan")) or count
		local n = count >= quan and 0 or count
		if from_list == "player" then
			command(("nhvcontin %d %d %d"):format(containers.cid, oid, n))
		else
			command(("nhvcontout %d %d %d"):format(containers.cid, oid, n))
		end
	end,
})

local function stack_for(o)
	local st = ItemStack(nhv_tiles.item(o.tile))
	st:set_count(math.max(1, math.min(o.quan, 65535)))
	local meta = st:get_meta()
	meta:set_string("description", o.name)
	meta:set_string("nhv_oid", tostring(o.id))
	meta:set_string("nhv_quan", tostring(o.quan))
	return st
end

local function fill(list, objs)
	local size = math.max(COLS * ROWS, (math.ceil((#objs + 1) / COLS)) * COLS)
	inv:set_size(list, size)
	local stacks = {}
	for i, o in ipairs(objs) do
		stacks[i] = stack_for(o)
	end
	inv:set_list(list, stacks)
end

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

local function formspec(cont, contents, mine)
	local lw = COLS * 1.25 - 0.25 -- width of a list
	local w = lw * 2 + 2.2
	local h = ROWS * 1.25 + 2.6
	local function heading(x, title, sub)
		return ("label[%f,0.55;%s]label[%f,0.95;%s]"):format(x, core.colorize("#FFD080", E(title)),
			x, core.colorize("#A0A0A0", E(sub)))
	end
	local rx = 0.6 + lw + 1.0
	return table.concat({
		("formspec_version[6]size[%f,%f]"):format(w, h),
		"bgcolor[#000000B0;true]style_type[button;bgcolor=#303040]",
		("background9[0,0;%f,%f;[fill:8x8:#16161cF0;true;2]"):format(w, h),
		"listcolors[#00000060;#5a5a7080;#141418;#30304a;#FFFFFF]",
		heading(0.6, "Your inventory", ("%d items, weight %d"):format(#mine, total_weight(mine))),
		heading(rx, cont and short(cont) or "Container",
			#contents == 0 and "empty" or ("%d items, weight %d"):format(#contents, total_weight(contents))),
		("box[0.45,1.25;%f,%f;#ffffff10]"):format(lw + 0.3, ROWS * 1.25 + 0.05),
		("box[%f,1.25;%f,%f;#ffd08018]"):format(rx - 0.15, lw + 0.3, ROWS * 1.25 + 0.05),
		("list[detached:nhv_container;player;0.6,1.4;%d,%d;]"):format(COLS, ROWS),
		("list[detached:nhv_container;cont;%f,1.4;%d,%d;]"):format(rx, COLS, ROWS),
		"listring[detached:nhv_container;player]listring[detached:nhv_container;cont]",
		("label[%f,%f;%s]"):format(0.6 + lw + 0.2, 1.4 + ROWS * 0.62, core.colorize("#808080", "<->")),
		("label[0.6,%f;%s]"):format(h - 0.75, core.colorize("#A0A0A0",
			E("Drag items between the lists (shift-click moves one across). Hover an item for its name."))),
		("button_exit[%f,%f;2.4,0.75;close;Close]"):format(w - 3.0, h - 1.05),
	})
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
	fill("player", mine)
	fill("cont", contents)
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
