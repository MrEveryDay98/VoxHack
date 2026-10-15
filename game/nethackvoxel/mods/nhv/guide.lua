-- The guide: how to play NetHack Voxel, a few short pages.
--
-- Shown once, the first time a game starts (setting nhv_guide_seen), and
-- any time from Options > Controls & guide. The game is paused while it's
-- open, as with any menu.

local guide = {pending = false, open = false}
nhv.guide = guide

local E = core.formspec_escape
local theme = nhv.theme
local FORM = "nhv:guide"

guide.PAGES = {
	{"Welcome", [[
NetHack Voxel is NetHack, seen from the inside.

Everything that happens is decided by NetHack itself: every monster, item, trap, roll of the dice and death. You move freely in the world, and NetHack keeps track of the square you're on.

Time moves when you move. Stand still and the world almost stops, so take your time to think. (Options > Time > Real time makes it always run.)

Menus and questions pause the game.

These pages are always under Options > Controls & guide.]]},
	{"Moving", [[
W A S D: walk
Mouse: look around
Space: wait a turn (or climb out of a pit, facing its edge)
Z: the big map (Z again to close it)

Doors: right click one to open or close it. Locked? Kick it (2) or unlock it.
Stairs and ladders: walk into them, or right click them.
Boulders: walk straight into one to push it. You can squeeze past one at a corner, unless you carry too much.
Monsters: you can walk past them, even in a narrow corridor.]]},
	{"Fighting", [[
Left click: attack the monster nearest your crosshair, if it's in reach.
Shift + left click: fire your quivered ammo (arrows, daggers...) at the crosshair.

The white bar above the hotbar is your last action playing out. When it's gone, you can act again.

Throwing, firing, zapping wands and casting spells all go where the crosshair points.

A monster flashes white when it attacks, and red when it's hurt.]]},
	{"Right click and the wheel", [[
Right click (tap): the obvious thing for what you point at: open a door, take the stairs, pick up, talk...
Right click (hold): a wheel of actions for it. Move the mouse toward one and let go (or let go in the middle to cancel). Time slows while it's open.

Shift + right click: things you do yourself (search, pray, rest...)
Alt + right click: use an item (eat, quaff, read, zap, wear...)
Ctrl + right click: magic and abilities
E: actions with your wielded weapon]]},
	{"Keys", [[
1 to 5: the hotbar (Fire, Kick, Zap, Spell, Eat)
X: search for hidden doors, passages and traps
P: pay, in a shop (it glows yellow while you owe something)
I: inventory and equipment (click an item for what you can do with it)
Middle click: look at what's under the crosshair
T: the command line, for any NetHack command (#pray, #loot, #offer, s...). It also lists every message so far: Page Up scrolls back.
Esc: the game menu]]},
	{"Spells and aiming", [[
4 opens your spells. Each spell has buttons:

Cast: for spells without a direction (light, detect monsters...)
Self: cast it on yourself (healing...)
Target: ready it in your hand. It glows for a few seconds while you aim; left click to cast it where you point.

Readying costs nothing; the spell is only cast when you click.

Healing goes to yourself unless you aim it at someone, like your pet.]]},
	{"Tips", [[
Messages appear at the top, and stay there while a question is up.

Options has the sizes of the HUD, menus, text and map, the interface style, and NetHack options (your name, your pet's name, autopickup...).

Shopkeepers stand in their door while you owe them. Pay with P.

Too much to carry? You'll walk slower, and can't squeeze past boulders.

Good luck, and mind the floating eyes.]]},
}

function guide.formspec(page)
	page = math.max(1, math.min(#guide.PAGES, page or 1))
	local p = guide.PAGES[page]
	local fs = {
		theme.head(14, 10.6),
		("label[0.5,0.6;%s]"):format(theme.title(E(p[1]))),
		("label[10.9,0.6;%s]"):format(theme.dim(("Page %d of %d"):format(page, #guide.PAGES))),
		("textarea[0.5,1.2;13,7.9;;;%s]"):format(E(p[2])),
	}
	if page > 1 then
		fs[#fs + 1] = ("button[0.5,9.4;3,0.8;g_prev_%d;< Back]"):format(page)
	end
	if page < #guide.PAGES then
		fs[#fs + 1] = ("button[10.5,9.4;3,0.8;g_next_%d;Next >]"):format(page)
		fs[#fs + 1] = "button_exit[5.5,9.4;3,0.8;g_close;Close]"
	else
		fs[#fs + 1] = "button_exit[10.5,9.4;3,0.8;g_close;Done]"
	end
	return table.concat(fs)
end

function guide.show(player, page)
	guide.open = true -- (the message lines make way meanwhile: hud.lua)
	core.show_formspec(player:get_player_name(), FORM, guide.formspec(page))
end

-- from the Options page: back to it when closed
guide.from_options = false

core.register_on_player_receive_fields(function(player, formname, fields)
	if formname ~= FORM then
		return false
	end
	for k in pairs(fields) do
		local dir, n = k:match("^g_(%a+)_(%d+)$")
		if dir then
			guide.show(player, tonumber(n) + (dir == "next" and 1 or -1))
			return true
		end
	end
	if fields.g_close or fields.quit then
		guide.open = false
		core.settings:set_bool("nhv_guide_seen", true)
		core.settings:write()
		if guide.from_options then
			guide.from_options = false
			nhv.graphics.show(player)
		end
	end
	return true
end)

-- the first time a game starts: once its first level is up
function guide.first_run()
	if not core.settings:get_bool("nhv_guide_seen", false) then
		guide.pending = true
	end
end

nhv.nh.on_snapshot(function(snap)
	if not (guide.pending and snap) then
		return
	end
	local player = nhv.player.get()
	if player and nhv.nh.ready() and not nhv.ui.open and not (nhv.title and nhv.title.open) then
		guide.pending = false
		guide.show(player, 1)
	end
end)

return guide
