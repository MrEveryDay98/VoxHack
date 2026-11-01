-- Quick slots: Shift + 1-5 uses the item put in that slot, doing what was
-- picked for it (quaff, read, zap, throw, put on...); Ctrl + 1-5 casts one
-- of your spells - the first five you know, in NetHack's order - at what
-- you aim at (one that needs no aim is just cast). While Shift or Ctrl is
-- held the hotbar shows them (hotbar.lua).
--
-- An item's slot is set from its menu ("Quick slot": ui.lua), kept with
-- the game (mod storage, by the hero's name), and goes on to another of
-- the same kind (the same picture) when the one you had is used up.

local nh = nhv.nh
local E = core.formspec_escape

local quick = {}
nhv.quick = quick

quick.SLOTS = 5
local store = core.get_mod_storage()

local function key()
	local h = nh.snap and nh.snap.hero
	return "quick_items:" .. (h and h.name or "")
end

-- the item slots: n -> {tile=, invlet=, name=, action=}
function quick.items()
	local raw = store:get_string(key())
	return raw ~= "" and core.deserialize(raw) or {}
end

local function save(t)
	store:set_string(key(), core.serialize(t))
end

-- (an item's name without how many: "potions of healing", for messages)
local function base_name(name)
	return (name or ""):gsub("^%d+ ", ""):gsub("^an? ", "")
end

function quick.set_item(n, o, action)
	local t = quick.items()
	t[n] = {tile = o.tile, invlet = o.invlet, name = base_name(o.name), action = action}
	save(t)
end

function quick.clear(n)
	local t = quick.items()
	t[n] = nil
	save(t)
end

-- the item slot n holds now (and the slot): the same letter and picture,
-- else another of the same picture
function quick.find(n)
	local s = quick.items()[n]
	if not s then
		return nil, nil
	end
	local inv = (nh.snap and nh.snap.inventory) or {}
	for _, o in ipairs(inv) do
		if o.invlet == s.invlet and o.tile == s.tile then
			return o, s
		end
	end
	for _, o in ipairs(inv) do
		if o.tile == s.tile then
			return o, s
		end
	end
	return nil, s
end

-- Shift + n
function quick.use(player, n)
	if nhv.ui.open or not nh.ready() or nhv.clock.busy() then
		return
	end
	local o, s = quick.find(n)
	if not o then
		nhv.hud.message(s and ("You have no %s left."):format(s.name)
			or ("Nothing in Shift+%d. (An item's menu: Quick slot.)"):format(n))
		return
	end
	local acts = nhv.actions.item_actions(o)
	local a = acts[1]
	for _, it in ipairs(acts) do
		if it.label == s.action then
			a = it
			break
		end
	end
	if a then
		nhv.actions.do_item_action(player, o, a)
	end
end

-- the spells, in NetHack's order: {name=, tile=, directional=}
function quick.spells()
	return core.nh_get_spells and core.nh_get_spells() or {}
end

-- Ctrl + n: the nth spell, at what you aim at
function quick.cast(player, n)
	if nhv.ui.open or not nh.ready() or nhv.clock.busy() then
		return
	end
	local sp = quick.spells()[n]
	if not sp then
		nhv.hud.message(("You know no spell for Ctrl+%d."):format(n))
		return
	end
	-- (its letter in NetHack's spell menu: a, b, c... in this order)
	nhv.spells.cast_at_aim(player, string.char(96 + n), sp.name, sp.directional)
end

-- ---------------------------------------------------------------- choosing
-- An item's menu, "Quick slot": which of the five, and what it does
local chosen = nil -- {o=, acts=}

function quick.show_chooser(player, o)
	local acts = {}
	for _, a in ipairs(nhv.actions.item_actions(o)) do
		if not a.func then -- (NetHack's commands only: not the wiki...)
			acts[#acts + 1] = a
		end
	end
	if #acts == 0 then
		return
	end
	chosen = {o = o, acts = acts}
	local labels = {}
	for k, a in ipairs(acts) do
		labels[k] = E(a.label)
	end
	local slots = quick.items()
	local fs = {nhv.ui.head(9, 4.9 + quick.SLOTS * 0.85),
		("item_image[0.4,0.3;1,1;%s]"):format(nhv_tiles.item(o.tile)),
		("label[1.6,0.8;%s]"):format(E(o.invlet .. " - " .. o.name)),
		"label[0.5,1.8;What it does:]",
		("dropdown[3,1.45;5.5,0.75;action;%s;1;true]"):format(table.concat(labels, ",")),
		"label[0.5,2.7;Put it in (Shift + the key):]"}
	for n = 1, quick.SLOTS do
		local s = slots[n]
		local now = s and (s.action .. " " .. s.name) or "(empty)"
		fs[#fs + 1] = ("button[0.5,%f;8,0.75;slot_%d;%s]"):format(3.0 + (n - 1) * 0.85, n,
			E(("Shift+%d   %s"):format(n, now)))
	end
	fs[#fs + 1] = ("button[0.5,%f;8,0.75;clear;Take it out of its slot]"):format(3.2 + quick.SLOTS * 0.85)
	core.show_formspec(player:get_player_name(), "nhv:quick", table.concat(fs))
end

core.register_on_player_receive_fields(function(player, formname, fields)
	if formname ~= "nhv:quick" then
		return
	end
	local c = chosen
	if not c then
		return true
	end
	local k = tonumber(fields.action) or 1
	local a = c.acts[k] or c.acts[1]
	for n = 1, quick.SLOTS do
		if fields["slot_" .. n] then
			quick.set_item(n, c.o, a.label)
			core.close_formspec(player:get_player_name(), "nhv:quick")
			nhv.hud.message(("Shift+%d: %s %s."):format(n, a.label, base_name(c.o.name)))
			chosen = nil
			if nhv.hotbar.refresh_layer then
				nhv.hotbar.refresh_layer(player)
			end
			return true
		end
	end
	if fields.clear then
		local slots = quick.items()
		for n = 1, quick.SLOTS do
			local s = slots[n]
			if s and s.tile == c.o.tile then
				quick.clear(n)
			end
		end
		core.close_formspec(player:get_player_name(), "nhv:quick")
		chosen = nil
		if nhv.hotbar.refresh_layer then
			nhv.hotbar.refresh_layer(player)
		end
	end
	return true
end)

return quick
