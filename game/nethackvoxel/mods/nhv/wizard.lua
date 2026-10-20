-- Wizard mode (a world with a file named "nhv_debug" in it: NetHack's debug
-- mode) gets VoxHack's own debugging tools too:
--   K / H          fly and noclip (the fly, fast and noclip privileges).
--                  Flying, the body is a free camera: off the ground or
--                  inside a wall, it leaves the hero where it stands (nothing
--                  you pass moves it); landing takes you back to the hero.
--   /brightness N  the level's brightness, 0 (as lit) .. 100 (everything at
--                  full brightness); kept for the world.
-- Outside wizard mode none of this is there.

local U = nhv.util
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
				.. "/brightness 0-100 lights the level.")
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

-- Is the body flying free of the hero (wizard mode): off the ground, or
-- inside something solid (noclip)? Then nothing it does moves the hero.
function wizard.detached(player)
	if not wizard.on then
		return false
	end
	local pos = player:get_pos()
	if pos.y > U.STAND_Y + 1.6 then
		return true
	end
	local def = core.registered_nodes[core.get_node(vector.offset(pos, 0, 0.5, 0)).name]
	return def ~= nil and def.walkable == true and def.drawtype ~= "airlike"
end

return wizard
