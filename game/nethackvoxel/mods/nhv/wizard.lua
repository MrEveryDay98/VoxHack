-- Wizard mode (a world with a file named "nhv_debug" in it: NetHack's debug
-- mode) gets VoxHack's own debugging tools too:
--   K / H          fly and noclip (the fly, fast and noclip privileges).
--                  Flying, the body is a free camera: the hero stays where
--                  it stands (nothing you pass moves it, and it never pulls
--                  you back); stop flying to go back to the hero. Noclipping,
--                  the hero is invulnerable.
--   /god           infinite health on or off: invulnerable (no damage, no
--                  death) whether noclipping or not; kept for the world.
--   /brightness N  the level's brightness, 0 (as lit) .. 100 (everything at
--                  full brightness); kept for the world.
-- Outside wizard mode none of this is there.

local wizard = {}
nhv.wizard = wizard

local function debug_world()
	local f = io.open(core.get_worldpath() .. DIR_DELIM .. "nhv_debug", "r")
	if f then
		f:close()
		return true
	end
	return false
end
wizard.on = debug_world()

local storage = core.get_mod_storage()

local function set_brightness(pct)
	-- (the engine reads the setting: nhvFullbright in its shaders)
	core.settings:set("nhv_brightness", ("%.2f"):format(pct / 100))
end

core.register_on_joinplayer(function(player)
	if not wizard.on then
		set_brightness(0) -- (never carried over from a wizard-mode world)
		return
	end
	local name = player:get_player_name()
	local privs = core.get_player_privs(name)
	privs.fly, privs.fast, privs.noclip = true, true, true
	core.set_player_privs(name, privs)
	set_brightness(storage:get_int("brightness"))
	core.after(3, function()
		if nhv.hud then
			nhv.hud.message("Wizard mode: K flies, H noclips (flying, the hero stays put; land to go back). "
				.. "/brightness 0-100 lights the level. /god: infinite health.")
		end
	end)
end)

core.register_on_shutdown(function()
	set_brightness(0)
end)

core.register_chatcommand("brightness", {
	params = "[0-100]",
	description = "Wizard mode: the level's brightness (0: as lit, 100: everything fully lit)",
	func = function(_, param)
		if not wizard.on then
			return false, "Only in wizard mode."
		end
		local n = tonumber(param)
		if not n then
			return true, ("Brightness: %d (/brightness 0-100)"):format(storage:get_int("brightness"))
		end
		n = math.max(0, math.min(100, math.floor(n + 0.5)))
		storage:set_int("brightness", n)
		set_brightness(n)
		return true, ("Brightness: %d"):format(n)
	end,
})

-- K and H are the client's own toggles, the settings free_move and noclip;
-- the game and its window are one process, so they can be read here.
-- (Luanti's noclip only works while flying.)
local function flying()
	return core.settings:get_bool("free_move", false)
end
local function noclipping()
	return flying() and core.settings:get_bool("noclip", false)
end

-- Noclipping in wizard mode (H): every monster you could see from where
-- you are is shown, wherever the hero is (mobs.lua)
function wizard.noclipping()
	return wizard.on and noclipping()
end

-- Is the body flying free of the hero (wizard mode, K)? Then nothing it
-- does moves the hero, and the hero's position never pulls it back.
function wizard.detached()
	return wizard.on and flying()
end

-- Noclipping (wizard mode, H), the hero is invulnerable: NetHack's
-- #nhvgod (no attacks, no damage, death turned away). Told again whenever
-- it changes, and after a game starts or loads.
local god_told = nil
local nh = nhv.nh
-- /god: infinite health, on its own (kept for the world)
local function god_on()
	return storage:get_string("god") == "1"
end
core.register_globalstep(function()
	if not wizard.on then
		return
	end
	local want = noclipping() or god_on()
	if want ~= god_told and nh.ready() then
		local was = god_told
		god_told = want
		nh.act({{key = "#"}, {text = "nhvgod " .. (want and 1 or 0)}}, {kind = "info"})
		-- (said only when it changes: not "vulnerable" on every game start)
		if nhv.hud and (want or was) then
			local why = god_on() and "Infinite health" or "Noclip"
			nhv.hud.message(want and (why .. ": invulnerable.") or "Vulnerable again.")
		end
	end
end)

core.register_chatcommand("god", {
	description = "Wizard mode: infinite health on or off (no damage, no death)",
	func = function()
		if not wizard.on then
			return false, "Only in wizard mode."
		end
		local on = not god_on()
		storage:set_string("god", on and "1" or "")
		return true, on and "Infinite health on." or "Infinite health off."
	end,
})
nh.on_snapshot(function(snap)
	if not snap then
		god_told = nil -- (a new game: tell it again)
	end
end)

return wizard
