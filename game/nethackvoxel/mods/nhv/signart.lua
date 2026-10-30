-- A wooden sign's picture with words on it: nhv_tiles/textures/
-- nhv_wallWide_doorSign.png (one square wide, one block high) drawn 3x as
-- big, the words in white letters (and a dark shadow) in the game's pixel
-- font, centred: textures/nhv_sf_<char code>.png and nhv_sfs_<char
-- code>.png (8x12 each). The shop signs over shop doors (signs.lua), and
-- the signs put up in the opening's forest (intro_editor.lua).
--
--   signart.texture(words)   the picture ({"Asidonhopo's", "General Store"}:
--                            each starts a new line, long ones wrapped)

local signart = {}
nhv.signart = signart

local SCALE = 3
local W, H = 48 * SCALE, 16 * SCALE
local CW, CH = 8, 12 -- (a letter's cell)
local LINE_GAP = 2
local MARGIN = SCALE -- (keeps the letters off the frame)
local MAX_COLS = math.floor((W - 2 * MARGIN) / CW)
local MAX_LINES = 3
signart.W, signart.H = W, H

local function wrap(text, lines)
	local line = ""
	for word in text:gmatch("%S+") do
		if line ~= "" and #line + 1 + #word > MAX_COLS then
			lines[#lines + 1] = line
			line = word
		else
			line = line == "" and word or line .. " " .. word
		end
	end
	if line ~= "" then
		lines[#lines + 1] = line
	end
	return lines
end

-- the shopkeeper's name on a line of its own, then the kind of shop
local function sign_lines(words)
	local lines = {}
	for _, part in ipairs(words) do
		wrap(part, lines)
	end
	while #lines > MAX_LINES do
		table.remove(lines)
	end
	for i, l in ipairs(lines) do
		lines[i] = l:sub(1, MAX_COLS)
	end
	return lines
end

-- the sign's picture with these words on it ({"Asidonhopo's", "General
-- Store"}: each starts a new line)
function signart.texture(words)
	local lines = sign_lines(words)
	local parts = {}
	local total = #lines * CH + (#lines - 1) * LINE_GAP
	local y0 = math.floor((H - total) / 2)
	for li, line in ipairs(lines) do
		local x0 = math.floor((W - #line * CW) / 2)
		local y = y0 + (li - 1) * (CH + LINE_GAP)
		for i = 1, #line do
			local c = line:byte(i)
			if c > 32 and c < 127 then
				local x = x0 + (i - 1) * CW
				parts[#parts + 1] = ("%d,%d=nhv_sfs_%d.png"):format(x + 1, y + 1, c)
				parts[#parts + 1] = ("%d,%d=nhv_sf_%d.png"):format(x, y, c)
			end
		end
	end
	local base = ("nhv_wallWide_doorSign.png^[resize:%dx%d"):format(W, H)
	if #parts == 0 then
		return base
	end
	return base .. ("^([combine:%dx%d:"):format(W, H) .. table.concat(parts, ":") .. ")"
end

return signart
