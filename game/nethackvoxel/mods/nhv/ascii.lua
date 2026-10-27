-- ASCII mode: the world drawn as NetHack's text screen.
--
-- Options > Graphics > ASCII mode, or F4 ("/nhvkey ascii"). Every square
-- is built of blocks showing its character in its colour, black where
-- nothing's known: walls and rock as columns of '|', '-' and ' ', floors
-- as a layer of '.', corridors '#', doors '+', fountains '{'... Monsters,
-- objects and you stand on them as flat characters (nhv_tiles.ascii), and
-- the big map shows the characters too, and everything is at full
-- brightness (no light or shadow: the engine's nhv_fullbright), as on a
-- screen. The characters and colours are
-- NetHack's own for each glyph (its symbol set), so the Rogue level - which
-- is always drawn this way, whatever the option says - comes out as Epyx's
-- Rogue had it: double-line walls, a smiley for you, its colours
-- (nh.lua's roguesymset).

local nh = nhv.nh
local U = nhv.util
local T = U.TYP

local ascii = {on = false}
nhv.ascii = ascii

-- The letter blocks: one per character a square can show, in each of
-- NetHack's 16 colours (the colour in the picture: full brightness draws a
-- block's picture as it is, without the colour a palette would give it).
-- A square's face shows one character over all its blocks (world-aligned,
-- TILE blocks to a character: textures/nhv_ascii.png, tools/make_ascii_font.py).
-- The characters: NetHack's map symbols (include/defsym.h), the Rogue
-- level's '%' stairs, '?' for anything else, and Epyx Rogue's (nhdata/symbols).
local CODES = {}
for _, c in ipairs({32, 33, 34, 35, 36, 37, 40, 41, 42, 43, 45, 46, 47, 48, 58, 60, 62, 63, 64,
		94, 95, 96, 123, 124, 125, 126,
		0x04, 0xB0, 0xB1, 0xB2, 0xDB, 0xB9, 0xBA, 0xBB, 0xBC, 0xC8, 0xC9, 0xCA, 0xCB, 0xCC, 0xCD, 0xCE,
		0xEE, 0xF0, 0xFA}) do
	CODES[c] = true
end

local function block_name(code, color)
	return ("nhv:ascii_%d_%d"):format(code, color)
end

for code in pairs(CODES) do
	for color = 0, 15 do
		local tex = ("[fill:8x14:#000000^(%s)"):format(nhv_tiles.ascii_texture(code, color))
		core.register_node(block_name(code, color), {
			description = ("Character %d"):format(code),
			tiles = {{name = tex, align_style = "world", scale = U.TILE}},
			drawtype = "normal", paramtype = "light",
			groups = {not_in_creative_inventory = 1}, is_ground_content = false, drop = "",
		})
	end
end

-- the block for a character in a colour (black: nothing there)
function ascii.block(code, color)
	if code == 32 then
		return block_name(32, 0)
	end
	return block_name(CODES[code] and code or 63, color or 7)
end

-- what blocks a square's whole height: rock, walls, trees, bars, a closed door
local SOLID = {[T.STONE] = true, [T.SCORR] = true, [T.SDOOR] = true, [T.TREE] = true,
	[T.IRONBARS] = true, [T.LAVAWALL] = true}
for typ = T.VWALL, T.DBWALL do
	SOLID[typ] = true
end

local function rogue()
	local h = nh.snap and nh.snap.hero
	return h and U.has(h.flags, U.HERO.ROGUELVL) or false
end

-- tile -> {code, colour}: from every glyph NetHack has, with the symbols and
-- colours it uses on this level
local by_tile = {}
local built_for -- (the Rogue level or not, when it was made)
local function build_table()
	by_tile = {}
	-- (the glyphs' symbols just changed with them: nhv.glyph_info's are old)
	nh.glyph_cache = {}
	for g = 0, (core.nh_max_glyph and core.nh_max_glyph() or 0) - 1 do
		local gi = core.nh_glyph_info(g)
		if gi and gi.tile and gi.tile >= 0 and not by_tile[gi.tile] then
			by_tile[gi.tile] = {gi.sym % 256, gi.color}
		end
	end
	built_for = rogue()
end

-- a tile's character and colour (nil: none known)
function ascii.char(tile)
	local c = tile and by_tile[tile]
	if c then
		return c[1], c[2]
	end
end

-- a map symbol's (S_room...) character and colour on this level
function ascii.cmap_char(k)
	return ascii.char(core.nh_cmap_tile(k))
end

-- Walls in the world are shade blocks in their colour, by how well you see
-- them: in view and lit, solid; in view in the dark, dense; remembered, a
-- lighter shade - lighter still where it's dark (the big map keeps
-- NetHack's own '|' and '-')
local WALL = {}
for typ = T.VWALL, T.DBWALL do
	WALL[typ] = true
end
WALL[T.SDOOR] = true
local function wall_shade(map, i)
	local f = map.flags[i]
	local lit = U.has(f, U.LOC_LIT)
	if U.has(f, U.LOC_CANSEE) then
		return lit and 0xDB or 0xB2
	end
	return lit and 0xB1 or 0xB0
end

-- What square i shows: its character, colour, and whether it fills its whole
-- height. What you remember there (the remembered top thing's ground, if
-- it's an object or monster - they stand on it as characters of their
-- own); nothing seen yet, blank (black). world: for the blocks (walls
-- shaded), not the big map.
function ascii.square(map, i, world)
	local typ = map.typ[i]
	local solid = SOLID[typ] or false
	if typ == T.DOOR then
		local d = map.door[i] or 0
		solid = d % 16 >= U.D_CLOSED -- (closed or locked)
	end
	if map.flags[i] % 2 ~= 1 then
		return 32, 0, solid
	end
	local gi = nhv.glyph_info(map.mem[i])
	local code, color
	if gi.kind == "cmap" then
		code, color = gi.sym % 256, gi.color
		if world and WALL[typ] and code ~= 32 then
			code = wall_shade(map, i)
		end
	else
		local back = map.back and map.back[i]
		if back and back ~= 255 then
			code, color = ascii.cmap_char(back)
		end
	end
	return code or 32, color or 0, solid
end

-- the option, or the Rogue level
function ascii.wanted()
	return not nhv.EDITOR and (core.settings:get_bool("nhv_ascii", false) or rogue())
end

-- Called as the terrain updates (terrain.lua): turns ASCII mode on or off
-- as wanted. True if it changed (everything is drawn again).
function ascii.update()
	local want = ascii.wanted()
	local changed = want ~= ascii.on
	if want and (changed or built_for ~= rogue()) then
		build_table()
		changed = true
	end
	ascii.on = want
	nhv_tiles.ascii = want and ascii.char or nil
	if changed then
		-- (full brightness with it, and the level's own light without it)
		local player = nhv.player.get()
		if player then
			player:hud_set_flags({nhv_fullbright = want})
		end
		-- (the monsters, objects and features in their new pictures; the
		-- terrain is redrawn by the caller)
		core.after(0, function()
			if nh.snap then
				nhv.mobs.refresh_sizes()
				-- (and you, your portrait, what's in your hands)
				nhv.avatar.refresh()
				local player = nhv.player.get()
				if player then
					nhv.hud.rebuild_meters(player)
					nhv.hotbar.rebuild(player)
				end
			end
		end)
	end
	return changed
end

-- F4: ASCII mode on or off (the Rogue level stays as it is)
function ascii.toggle()
	local on = not core.settings:get_bool("nhv_ascii", false)
	core.settings:set_bool("nhv_ascii", on)
	if rogue() then
		nhv.hud.message(on and "ASCII mode on." or "ASCII mode off (the Rogue level is always text).")
	else
		nhv.hud.message(on and "ASCII mode on." or "ASCII mode off.")
	end
	ascii.redraw()
end

-- draw everything again in the mode wanted now
function ascii.redraw()
	if nh.snap and nh.snap.map then
		nhv.terrain.update(nh.snap.map)
	end
end

return ascii
