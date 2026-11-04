-- Quick slots: Shift + 1-5 uses the item put in that slot, doing what was
-- picked for it (quaff, read, zap, throw, put on...); Ctrl + 1-5 casts the
-- spell put in that slot, at what you aim at or at yourself, as was picked
-- for it (one that needs no aim is just cast). Until a spell has been put
-- in any, Ctrl + n casts the spell NetHack lists n down. While Shift or
-- Ctrl is held the hotbar shows them (hotbar.lua).
--
-- An item's slot is set from its menu ("Quick slot": ui.lua), and goes on
-- to another of the same kind (the same picture) when the one you had is
-- used up; a spell's from the spell menu ("Quick": spells.lua), by its
-- name. Both are kept with the game (mod storage, by the hero's name and
-- the game's id - when it was started: a new hero of the same name starts
-- with none).

local nh = nhv.nh
local E = core.formspec_escape

local quick = {}
nhv.quick = quick

quick.SLOTS = 5
local store = core.get_mod_storage()

local function key(what)
	local h = nh.snap and nh.snap.hero
	local gid = core.nh_game_id and ("%d"):format(core.nh_game_id()) or ""
	return (what or "quick_items") .. ":" .. (h and h.name or "") .. ":" .. gid
end

-- (saving: the hero's slots from other games - same name, or kept by name
-- alone, from before - dropped, not piling up)
local function forget_others(k)
	local what_name = k:match("^(.*):[^:]*$")
	for _, other in ipairs(store:get_keys()) do
		if other ~= k and (other == what_name or other:sub(1, #what_name + 1) == what_name .. ":") then
			store:set_string(other, "")
		end
	end
end

-- the item slots: n -> {tile=, invlet=, name=, action=}
function quick.items()
	local raw = store:get_string(key())
	return raw ~= "" and core.deserialize(raw) or {}
end

local function save(t)
	local k = key()
	store:set_string(k, core.serialize(t))
	forget_others(k)
end

-- the spell slots: n -> {name=, self=} (self: cast at yourself)
function quick.spell_slots()
	local raw = store:get_string(key("quick_spells"))
	return raw ~= "" and core.deserialize(raw) or {}
end

local function save_spells(t)
	local k = key("quick_spells")
	store:set_string(k, core.serialize(t))
	forget_others(k)
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

-- the spell Ctrl + n casts now: the one put there - or, while none has
-- been put in any, NetHack's nth - (the spell, its letter in NetHack's
-- menu, at yourself?, the slot)
function quick.spell(n)
	local known = quick.spells()
	local slots = quick.spell_slots()
	local slot = slots[n]
	if next(slots) and not slot then
		return nil
	end
	if slot then
		for i, sp in ipairs(known) do
			if sp.name == slot.name then
				return sp, string.char(96 + i), slot.self, slot
			end
		end
		return nil, nil, nil, slot -- (put there, but forgotten)
	end
	local sp = known[n]
	return sp, sp and string.char(96 + n), false, nil
end

-- Ctrl + n
function quick.cast(player, n)
	if nhv.ui.open or not nh.ready() or nhv.clock.busy() then
		return
	end
	local sp, sel, self, slot = quick.spell(n)
	if not sp then
		nhv.hud.message(slot and ("You don't know %s any more."):format(slot.name)
			or ("You know no spell for Ctrl+%d."):format(n))
		return
	end
	nhv.spells.cast_at_aim(player, sel, sp.name, sp.directional, self and sp.directional and "." or nil)
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

-- A spell's "Quick" (the spell menu: spells.lua): which of the five, and
-- whether at what you aim at or at yourself
local chosen_spell = nil -- {name=, directional=}

function quick.show_spell_chooser(player, name)
	local sp
	for _, s in ipairs(quick.spells()) do
		if s.name == name then
			sp = s
		end
	end
	if not sp then
		return
	end
	chosen_spell = {name = sp.name, directional = sp.directional}
	local slots = quick.spell_slots()
	local fs = {nhv.ui.head(9, 4.9 + quick.SLOTS * 0.85)}
	if sp.tile and sp.tile >= 0 then
		fs[#fs + 1] = ("item_image[0.4,0.3;1,1;%s]"):format(nhv_tiles.item(sp.tile))
	end
	fs[#fs + 1] = ("label[1.6,0.8;%s]"):format(E(sp.name))
	if sp.directional then
		fs[#fs + 1] = "label[0.5,1.8;Cast it:]"
		fs[#fs + 1] = "dropdown[3,1.45;5.5,0.75;target;At what you aim at,At yourself;1;true]"
	else
		fs[#fs + 1] = ("label[0.5,1.8;%s]"):format(E("(It needs no aim: it's just cast.)"))
	end
	fs[#fs + 1] = "label[0.5,2.7;Put it in (Ctrl + the key):]"
	for n = 1, quick.SLOTS do
		local s = slots[n]
		local now = s and (s.name .. (s.self and " (at yourself)" or "")) or "(empty)"
		fs[#fs + 1] = ("button[0.5,%f;8,0.75;slot_%d;%s]"):format(3.0 + (n - 1) * 0.85, n,
			E(("Ctrl+%d   %s"):format(n, now)))
	end
	fs[#fs + 1] = ("button[0.5,%f;8,0.75;clear;Take it out of its slot]"):format(3.2 + quick.SLOTS * 0.85)
	core.show_formspec(player:get_player_name(), "nhv:quick_spell", table.concat(fs))
end

core.register_on_player_receive_fields(function(player, formname, fields)
	if formname ~= "nhv:quick_spell" then
		return
	end
	local c = chosen_spell
	if not c then
		return true
	end
	local self = c.directional and tonumber(fields.target) == 2 or false
	for n = 1, quick.SLOTS do
		if fields["slot_" .. n] then
			local t = quick.spell_slots()
			-- (a spell is in one slot at a time)
			for k = 1, quick.SLOTS do
				if t[k] and t[k].name == c.name then
					t[k] = nil
				end
			end
			t[n] = {name = c.name, self = self}
			save_spells(t)
			core.close_formspec(player:get_player_name(), "nhv:quick_spell")
			nhv.hud.message(("Ctrl+%d: %s%s."):format(n, c.name, self and ", at yourself" or ""))
			chosen_spell = nil
			if nhv.hotbar.refresh_layer then
				nhv.hotbar.refresh_layer(player)
			end
			return true
		end
	end
	if fields.clear then
		local t = quick.spell_slots()
		for n = 1, quick.SLOTS do
			if t[n] and t[n].name == c.name then
				t[n] = nil
			end
		end
		save_spells(t)
		core.close_formspec(player:get_player_name(), "nhv:quick_spell")
		chosen_spell = nil
		if nhv.hotbar.refresh_layer then
			nhv.hotbar.refresh_layer(player)
		end
	end
	return true
end)

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
