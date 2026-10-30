-- NetHack's tiles as items. Entities that use visual = "wielditem" with
-- one of these items render it as an extruded voxel sprite, which is how
-- monsters and floor objects get their 3D look.
--
-- Sprites live in one sheet, textures/nhv_tiles.png (cols x rows sprites,
-- numbered left to right, top to bottom from 0). Edit it freely.
-- tilenames.lua maps NetHack's tile numbers onto sheet positions: a
-- monster's male and female tiles share a sprite unless they differ, and
-- statues reuse the monster's sprite with a stone colour filter.
local meta = dofile(core.get_modpath("nhv_tiles") .. "/tilenames.lua")

nhv_tiles = {
	count = meta.count,
	names = meta.names,
	sheet_names = meta.sheet_names, -- (what's at each sheet position)
	cols = meta.cols,
	rows = meta.rows,
}

-- the colour filter that turns a sprite into a statue
nhv_tiles.STONE = "^[hsl:0:-100:-10"

function nhv_tiles.item(tile)
	if not tile or tile < 0 or tile >= meta.count then
		tile = 0
	end
	return string.format("nhv_tiles:t%04d", tile)
end

-- NetHack's name for a tile ("main walls horizontal", "newt", ...)
function nhv_tiles.name(tile)
	return meta.names[tile]
end

-- sheet position of a NetHack tile
function nhv_tiles.sheet_index(tile)
	if not tile or tile < 0 or tile >= meta.count then
		tile = 0
	end
	return meta.sheet[tile] or 0
end

-- texture string for a sheet position (the block editor picks these)
function nhv_tiles.sheet_texture(s)
	return string.format("nhv_tiles.png^[sheet:%dx%d:%d,%d", meta.cols, meta.rows,
		s % meta.cols, math.floor(s / meta.cols))
end

-- The sprites' own sheet: nhv_tiles.png, or with the setting
-- nhv_sprite_shadows off (Options > Drawn shadows), nhv_tiles_noshadow.png -
-- the same without the shadows drawn on the monsters and objects
-- (tools/make_noshadow_tiles.py makes it; the game's shadows are real:
-- nhv/shadows.lua). Read when the game starts.
nhv_tiles.SPRITES = core.settings:get_bool("nhv_sprite_shadows", true) and "nhv_tiles.png"
	or "nhv_tiles_noshadow.png"

-- ASCII mode (nhv/ascii.lua): while it's on, this is a function giving a
-- tile's NetHack character and colour (code 0-255, NetHack colour 0-15),
-- and every sprite is that character, flat, in that colour
-- (textures/nhv_ascii.png: tools/make_ascii_font.py - the IBM EGA's 8x14
-- characters, in its colours)
nhv_tiles.ascii = nil
nhv_tiles.ASCII_COLORS = {
	[0] = "#555555", "#AA0000", "#00AA00", "#AA5500", "#0000AA", "#AA00AA", "#00AAAA", "#AAAAAA",
	"#AAAAAA", "#FF5555", "#55FF55", "#FFFF55", "#5555FF", "#FF55FF", "#55FFFF", "#FFFFFF",
}
nhv_tiles.ASCII_ASPECT = 8 / 14 -- (a character's width for its height)

-- a character (code 0-255) in a colour (0-15), on see-through
function nhv_tiles.ascii_texture(code, color)
	code = code % 256
	return ("nhv_ascii.png^[sheet:16x16:%d,%d^[multiply:%s"):format(code % 16, math.floor(code / 16),
		nhv_tiles.ASCII_COLORS[color or 7] or "#B0B0B0")
end

-- texture string for a NetHack tile
function nhv_tiles.texture(tile)
	if nhv_tiles.ascii then
		local code, color = nhv_tiles.ascii(tile)
		if code then
			return nhv_tiles.ascii_texture(code, color)
		end
	end
	local s = nhv_tiles.sheet_index(tile)
	local tex = string.format("%s^[sheet:%dx%d:%d,%d", nhv_tiles.SPRITES, meta.cols, meta.rows,
		s % meta.cols, math.floor(s / meta.cols))
	if meta.statue[tile] then
		tex = tex .. nhv_tiles.STONE
	end
	return tex
end

-- Where a sprite's picture really is in its cell: most monsters stand on
-- the bottom of theirs (tools/ground_monster_sprites.py), so a picture
-- put somewhere by its cell's middle sits too high. Read once from the
-- sheet's pixels (whatever it is now: edit it freely) the first time
-- it's asked for: the middle of the cell's visible (not see-through)
-- pixels, as the offset from the cell's middle in sheet pixels.
local TILE_PX = 16
local centers -- sheet position -> {dx, dy}; false: the sheet couldn't be read

-- the sheet's alpha values, row by row ({[y] = {[x] = alpha}}), or nil
-- (8-bit RGBA or RGB, not interlaced: what the sheet is saved as)
local function read_alpha(path)
	local f = io.open(path, "rb")
	if not f then
		return nil
	end
	local png = f:read("*a")
	f:close()
	if png:sub(1, 8) ~= "\137PNG\r\n\26\n" then
		return nil
	end
	local function u32(i)
		local a, b, c, d = png:byte(i, i + 3)
		return ((a * 256 + b) * 256 + c) * 256 + d
	end
	local w, h, depth, ctype, interlace
	local idat = {}
	local pos = 9
	while pos + 8 <= #png do
		local len, kind = u32(pos), png:sub(pos + 4, pos + 7)
		local body = pos + 8
		if kind == "IHDR" then
			w, h = u32(body), u32(body + 4)
			depth, ctype, interlace = png:byte(body + 8), png:byte(body + 9), png:byte(body + 12)
		elseif kind == "IDAT" then
			idat[#idat + 1] = png:sub(body, body + len - 1)
		elseif kind == "IEND" then
			break
		end
		pos = body + len + 4
	end
	if not w or depth ~= 8 or interlace ~= 0 or (ctype ~= 6 and ctype ~= 2) then
		return nil
	end
	local ok, data = pcall(core.decompress, table.concat(idat), "deflate")
	if not ok or not data then
		return nil
	end
	local bpp = ctype == 6 and 4 or 3
	local stride = w * bpp
	local alpha, prev = {}, {}
	for x = 1, stride do
		prev[x] = 0
	end
	for y = 0, h - 1 do
		local at = y * (stride + 1) + 1
		local filter = data:byte(at)
		local raw = {data:byte(at + 1, at + stride)}
		local cur = {}
		for x = 1, stride do
			local a = x > bpp and cur[x - bpp] or 0
			local b = prev[x]
			local v = raw[x] or 0
			if filter == 1 then
				v = v + a
			elseif filter == 2 then
				v = v + b
			elseif filter == 3 then
				v = v + math.floor((a + b) / 2)
			elseif filter == 4 then
				local c = x > bpp and prev[x - bpp] or 0
				local p = a + b - c
				local pa, pb, pc = math.abs(p - a), math.abs(p - b), math.abs(p - c)
				v = v + ((pa <= pb and pa <= pc) and a or (pb <= pc and b or c))
			end
			cur[x] = v % 256
		end
		local row = {}
		for x = 0, w - 1 do
			row[x] = bpp == 4 and cur[x * 4 + 4] or 255
		end
		alpha[y] = row
		prev = cur
	end
	return alpha
end

local function find_centers()
	local alpha = read_alpha(core.get_modpath("nhv_tiles") .. DIR_DELIM .. "textures"
		.. DIR_DELIM .. nhv_tiles.SPRITES)
	if not alpha then
		core.log("warning", "[nhv_tiles] couldn't read the sprite sheet's pixels")
		return false
	end
	local out = {}
	for s = 0, meta.cols * meta.rows - 1 do
		local x0, y0 = (s % meta.cols) * TILE_PX, math.floor(s / meta.cols) * TILE_PX
		local minx, miny, maxx, maxy
		for y = 0, TILE_PX - 1 do
			local row = alpha[y0 + y]
			for x = 0, TILE_PX - 1 do
				if row and (row[x0 + x] or 0) > 0 then
					minx, maxx = math.min(minx or x, x), math.max(maxx or x, x)
					miny, maxy = math.min(miny or y, y), math.max(maxy or y, y)
				end
			end
		end
		if minx then
			out[s] = {(minx + maxx + 1) / 2 - TILE_PX / 2, (miny + maxy + 1) / 2 - TILE_PX / 2}
		end
	end
	return out
end

-- the offset (sheet pixels, x right, y down) from a tile's cell middle to
-- the middle of its picture; 0, 0 for an empty cell
function nhv_tiles.picture_center(tile)
	if nhv_tiles.ascii then
		return 0, 0 -- (a character sits in the middle of its cell)
	end
	if centers == nil then
		centers = find_centers()
	end
	local c = centers and centers[nhv_tiles.sheet_index(tile)]
	if not c then
		return 0, 0
	end
	return c[1], c[2]
end

-- combat flashes for monster sprites: a faint white one when attacking,
-- red when hurt (entities swap to these items for a moment)
nhv_tiles.FLASH = {
	w = "^[colorize:#ffffff:70",
	r = "^[colorize:#ff2020:150",
}

-- Something invisible that you see anyway (See_invisible): Doom's
-- spectre fuzz - the monster faint and see-through, with fine specks of it
-- (darker, and in its own colours) crawling over it: FUZZ_FRAMES noise
-- masks (nhv_fuzz_<n>.png, FUZZ_RES square, finer than the sprite, which
-- is scaled up to match), swapped FUZZ_RATE times a second by whoever
-- draws it (mobs.lua, avatar.lua)
nhv_tiles.FUZZ_FRAMES = 8
nhv_tiles.FUZZ_RATE = 14
nhv_tiles.FUZZ_RES = 64
nhv_tiles.FUZZ_ALPHA = 120 -- (all of it see-through: 255 = only the gaps are)

function nhv_tiles.fuzz_textures(tile, frame)
	local n, r = nhv_tiles.FUZZ_FRAMES, nhv_tiles.FUZZ_RES
	local base = ("%s^[resize:%dx%d"):format(nhv_tiles.texture(tile), r, r)
	-- (faint, then darker specks, then specks in full colour)
	local tex = "((" .. base .. "^[opacity:70)"
		.. ("^(%s^[mask:nhv_fuzz_%d.png^[multiply:#505050^[opacity:200)"):format(base, frame % n)
		.. ("^(%s^[mask:nhv_fuzz_%d.png^[opacity:150)"):format(base, (frame + 3) % n)
		.. ")^[opacity:" .. nhv_tiles.FUZZ_ALPHA
	return {tex, tex .. "^[transformFX"}
end

-- the fuzz frame for now (everything fuzzy crawls in step)
function nhv_tiles.fuzz_frame()
	return math.floor(core.get_us_time() / 1e6 * nhv_tiles.FUZZ_RATE) % nhv_tiles.FUZZ_FRAMES
end

function nhv_tiles.fuzz_look(tile, height)
	return {
		visual = "upright_sprite", textures = nhv_tiles.fuzz_textures(tile, nhv_tiles.fuzz_frame()),
		visual_size = {x = height, y = height, z = height}, use_texture_alpha = true,
	}
end

-- Entity properties that draw a tile `height` nodes tall, either as an
-- extruded voxel model (default) or, with the setting nhv_flat_sprites,
-- as a flat sprite. kind: nil, or a FLASH key ("w"/"r") for a combat flash.
function nhv_tiles.flat()
	-- (ASCII mode: characters are flat)
	return nhv_tiles.ascii ~= nil or core.settings:get_bool("nhv_flat_sprites", false)
end

-- how far a sprite facing you is turned from having its front (+z) to you:
-- an extruded one has its back to you - its picture is the right way round
-- from there (wieldmesh's extrusion), the other way round from its front;
-- a flat one has its front to you (from behind, its picture is mirrored)
function nhv_tiles.facing_turn()
	return nhv_tiles.flat() and 0 or math.pi
end

function nhv_tiles.look(tile, height, kind)
	if nhv_tiles.flat() then
		local tex = nhv_tiles.texture(tile) .. (kind and nhv_tiles.FLASH[kind] or "")
		-- (a character is narrower than it's tall, as on a text screen)
		local w = nhv_tiles.ascii and height * nhv_tiles.ASCII_ASPECT or height
		return {
			visual = "upright_sprite",
			textures = {tex, tex .. "^[transformFX"},
			visual_size = {x = w, y = height, z = height},
		}
	end
	local s = height / 2
	return {
		visual = "wielditem",
		wield_item = kind and nhv_tiles.flash_item(tile, kind) or nhv_tiles.item(tile),
		visual_size = {x = s, y = s, z = s},
	}
end

-- visual_size for a tile `height` nodes tall, squashed/stretched by w
function nhv_tiles.size(height, w)
	local s = nhv_tiles.flat() and height or height / 2
	w = w or 1
	local aspect = nhv_tiles.ascii and nhv_tiles.ASCII_ASPECT or 1
	return {x = s * w * aspect, y = s / w, z = s}
end

function nhv_tiles.flash_item(tile, kind)
	if not tile or tile < 0 or tile >= meta.monsters or not nhv_tiles.FLASH[kind] then
		return nhv_tiles.item(tile)
	end
	return string.format("nhv_tiles:t%04d_%s", tile, kind)
end

-- a fist (a Monk's left hand fighting bare-handed; either hand in gloves;
-- the bare right hand is the hand item's picture, actions.lua). Its picture
-- is set per use (nhv_tiles.fist): mirrored for the left, the gloves' colour.
core.register_craftitem(":nhv:fist", {
	description = "Fist", inventory_image = "nhv_weapon_Fist.png",
	wield_image = "nhv_weapon_Fist.png", groups = {not_in_creative_inventory = 1},
})

-- the gloves' colours (tools/make_glove_colors.py): NetHack tile -> colour
local GLOVES = dofile(core.get_modpath("nhv_tiles") .. "/glove_colors.lua")
function nhv_tiles.glove_color(tile)
	return GLOVES[tile]
end

-- a fist's picture: the left hand's mirrored; in gloves, their colour over
-- the hand (where textures/nhv_glove_mask.png is white: to the wrist), the
-- fist's shading kept (grey, then tinted), the arm bare
function nhv_tiles.fist(left, color)
	local tex = "nhv_weapon_Fist.png"
	if color then
		tex = tex .. "^(nhv_weapon_Fist.png^[hsl:0:-100:15^[multiply:" .. color
			.. "^[mask:nhv_glove_mask.png)"
	end
	return left and (tex .. "^[transformFX") or tex
end

for i = 0, meta.count - 1 do
	local tex = nhv_tiles.texture(i)
	core.register_craftitem(nhv_tiles.item(i), {
		description = meta.names[i] or ("tile " .. i),
		inventory_image = tex,
		wield_image = tex,
		stack_max = 65535,
		groups = {not_in_creative_inventory = 1},
	})
	if i < meta.monsters then
		for kind, mod in pairs(nhv_tiles.FLASH) do
			core.register_craftitem(nhv_tiles.flash_item(i, kind), {
				description = meta.names[i] or ("tile " .. i),
				inventory_image = tex .. mod,
				groups = {not_in_creative_inventory = 1},
			})
		end
	end
end
