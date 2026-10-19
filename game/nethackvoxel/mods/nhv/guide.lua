-- The guide: what NetHack is, and the controls.
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
	{"NetHack", [[
NetHack is a single-player dungeon exploration game.

You play an adventurer of a role, race and alignment of your choosing, sent by your god to recover the fabled Amulet of Yendor from deep within the dungeon, and to offer it to your god on the Astral Plane.

On the way down you will meet monsters, find weapons, armour, magic and gold, visit shops, temples and other special places, and learn what the many unidentified items do by trying them.

Every game is different: the dungeon, its monsters and its treasures are made anew each time. Death is permanent: when your character dies, the game is over.]]},
	{"Moving", [[
W A S D: walk
Mouse: look around
Space: wait a turn; in a pit, climb out (facing its edge)
Z: the big map (Z again to close it)
Right click a door: open or close it
Walk into stairs or a ladder (or right click it): take it
Walk straight into a boulder: push it]]},
	{"Fighting", [[
Left click: attack the monster nearest your crosshair, if it's in reach
Shift + left click: fire your quivered ammo where the crosshair points
1: Fire
2: Kick

Throwing, firing, zapping and casting go where the crosshair points.
The white bar above the hotbar shows your last action playing out; you can act again when it's gone.]]},
	{"Right click and the wheel", [[
Right click (tap): the obvious action for what you point at (open a door, take the stairs, talk...)
Right click (hold): a wheel of actions for it; move the mouse toward one and let go, or let go in the middle to cancel

Shift + right click: actions on yourself (pray, rest, engrave...)
R: pick up what is here
F2: NetHackWiki in the game - the page for what you're pointing at (shown under the crosshair as "F2  Look up: ..."); F2 again closes it
Alt + right click: use an item (quaff, read, apply, wear, drop...)
Ctrl + right click: magic and abilities
E: actions with your wielded weapon]]},
	{"Keys", [[
1 to 5: the hotbar (Fire, Kick, Zap, Spell, Eat)
X: search
P: pay, in a shop
I: inventory and equipment (click an item for what you can do with it)
Middle click: look at what's under the crosshair
T: the command line, for any NetHack command (#pray, #loot, #offer, s...); it also lists every message so far (Page Up scrolls back)
Esc: the game menu]]},
	{"Spells", [[
4 opens your spells. Each has buttons:

Cast: a spell without a direction
Self: cast it on yourself
Target: ready it in your hand, then left click to cast it where the crosshair points (it fades after a few seconds)]]},
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
