-- The changelog, from the title (the "Changelog" next to the version):
-- the game's CHANGELOG.md (a copy of the repository's, put in the game's
-- folder by tools/make_release.py and tools/deploy.sh - Luanti lets the
-- game read its own folder), its Markdown shown as Luanti's hypertext.

local theme = nhv.theme
local E = core.formspec_escape

local changelog = {}
nhv.changelog = changelog

local FORM = "nhv:changelog"
local FILE = core.get_modpath("nhv") .. DIR_DELIM .. ".." .. DIR_DELIM .. ".." .. DIR_DELIM .. "CHANGELOG.md"
local RELEASES = "https://github.com/MrEveryDay98/VoxHack/releases"

local function read()
	local ok, f = pcall(io.open, FILE, "rb")
	if not (ok and f) then
		return nil
	end
	local text = f:read("*a")
	f:close()
	return text
end

-- emphasis: bold and italic - in retro, white instead (the pixel font has
-- neither: hypertext would turn to another font for them)
local function strong(text)
	return theme.retro() and ("<style color=#FFFFFF>" .. text .. "</style>") or ("<b>" .. text .. "</b>")
end
local function em(text)
	return theme.retro() and ("<style color=#FFFFFF>" .. text .. "</style>") or ("<i>" .. text .. "</i>")
end

-- a line of Markdown as hypertext: **bold**, *italic*, `code`, [links](url)
local function inline(s)
	-- (hypertext's own: a backslash and < are written escaped)
	s = s:gsub("\\", "\\\\"):gsub("<", "\\<")
	s = s:gsub("%*%*(.-)%*%*", strong)
	s = s:gsub("%*(.-)%*", em)
	s = s:gsub("`(.-)`", "<mono>%1</mono>")
	s = s:gsub("%[(.-)%]%((.-)%)", function(text, url)
		return ("<action name=link url=%s>%s</action>"):format(url, text)
	end)
	return s
end

local function hypertext(md)
	local out = {"<global color=#C8C8C8><tag name=action color=#78C8FF hovercolor=#FFFFFF>"}
	local first = true
	for line in (md:gsub("\r", "") .. "\n"):gmatch("(.-)\n") do
		local h1 = line:match("^#%s+(.*)")
		local h2 = line:match("^##%s+(.*)")
		local item = line:match("^%s*[-*]%s+(.*)")
		if h1 then -- luacheck: ignore 542
			-- (the screen's own title says it)
		elseif h2 then
			-- "v0.13.0 (alpha) - 2026-10-30": the version big, its date dim
			local name, date = h2:match("^(.-)%s+%-%s+(%d%d%d%d%-%d%d%-%d%d)$")
			-- (in retro, the pixel font's own size: bigger, it'd turn to another font)
			local head = "<style color=#FFD25A>" .. inline(name or h2) .. "</style>"
			out[#out + 1] = (first and "" or "\n") .. (theme.retro() and head or ("<big><b>" .. head .. "</b></big>"))
				.. (date and ("  <style color=#909090>" .. date .. "</style>") or "") .. "\n"
			first = false
		elseif item then
			out[#out + 1] = "  •  " .. inline(item) .. "\n"
		elseif line:find("%S") then
			out[#out + 1] = inline(line) .. "\n"
		end
	end
	return table.concat(out)
end

local function formspec()
	local W, H = 16, 10.5
	local md = read()
	local body = md and hypertext(md)
		or ("<global color=#E0E0E0>This copy of VoxHack has no changelog with it. Every version's changes "
			.. "are on <tag name=action color=#78C8FF hovercolor=#FFFFFF>"
			.. "<action name=link url=%s>GitHub</action>."):format(RELEASES)
	return theme.head(W, H)
		.. "label[0.4,0.5;" .. theme.title("Changelog") .. "]"
		.. "label[0.4,1.05;" .. theme.dim(E(nhv.title.VERSION)) .. "]"
		.. ("hypertext[0.4,1.5;%s,%s;log;%s]"):format(W - 0.8, H - 2.8, E(body))
		.. ("button[%s,%s;3,0.8;back;Back]"):format(W / 2 - 1.5, H - 1.0)
end

function changelog.show(player)
	nhv.title.open = false
	core.show_formspec(player:get_player_name(), FORM, formspec())
end

core.register_on_player_receive_fields(function(player, formname, fields)
	if formname ~= FORM then
		return false
	end
	-- (a link: Luanti opens it; the screen stays)
	if fields.back or fields.quit then
		nhv.title.show(player)
	end
	return true
end)

return changelog
