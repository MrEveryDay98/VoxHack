-- NetHackWiki viewer (F2, or "Wiki" on an item; /wiki <page>).
--
-- Pages come live from nethackwiki.com (its MediaWiki API: the page as the
-- site shows it, in HTML) and are kept in the world's wiki_cache folder: a
-- page is fetched again after a week, and a cached page still shows when
-- the wiki can't be reached. The HTML is turned into the formspec
-- hypertext markup, keeping what it can of the page: headings, bold and
-- italics, colours (NetHack's coloured symbols too), lists, code, links,
-- images (fetched and sent to the client as media), infoboxes and tables
-- (aligned in a monospace grid). The wiki's text is CC BY-SA 3.0: the
-- viewer credits it on every page.
--
-- What you look up is only ever what you know: an unidentified potion is
-- "Potion", never the potion it really is (wiki.title_for_object).

local U = nhv.util
local wiki = {}
nhv.wiki = wiki

local SITE = "https://nethackwiki.com"
local API = SITE .. "/api.php"
local USER_AGENT = "VoxHack/0.1 (in-game NetHackWiki viewer; +https://github.com/MrEveryDay98/VoxHack)"
local FRESH_S = 7 * 24 * 3600 -- a cached page is fetched again after this
local IMG_WAIT_S = 2.5        -- a page waits this long for its images
local FORM = "nhv:wiki"
local HOME = "" -- (the start page: not a wiki page)

local http = nhv.http -- (requested in init.lua: it has to be)
if not http then
	core.log("warning", "[nhv] wiki: no internet access (add nhv to secure.http_mods)")
end
local CACHE = core.get_worldpath() .. DIR_DELIM .. "wiki_cache"
core.mkdir(CACHE)
core.mkdir(CACHE .. DIR_DELIM .. "img")

-- ---------------------------------------------------------------- text helpers
local function utf8_char(n)
	if n < 0x80 then
		return string.char(n)
	elseif n < 0x800 then
		return string.char(0xC0 + math.floor(n / 64), 0x80 + n % 64)
	elseif n < 0x10000 then
		return string.char(0xE0 + math.floor(n / 4096), 0x80 + math.floor(n / 64) % 64, 0x80 + n % 64)
	end
	return string.char(0xF0 + math.floor(n / 262144), 0x80 + math.floor(n / 4096) % 64,
		0x80 + math.floor(n / 64) % 64, 0x80 + n % 64)
end

local ENTITIES = {
	amp = "&", lt = "<", gt = ">", quot = "\"", apos = "'", nbsp = "\194\160",
	ndash = "\226\128\147", mdash = "\226\128\148", hellip = "\226\128\166",
	rarr = "\226\134\146", larr = "\226\134\144", times = "\195\151", minus = "\226\136\146",
	middot = "\194\183", deg = "\194\176", laquo = "\194\171", raquo = "\194\187",
	lsquo = "\226\128\152", rsquo = "\226\128\153", ldquo = "\226\128\156", rdquo = "\226\128\157",
	bull = "\226\128\162", copy = "\194\169", frac12 = "\194\189", frac14 = "\194\188",
}

local function decode(s)
	return (s:gsub("&(#?[xX]?)(%w+);", function(kind, v)
		if kind == "#" then
			return utf8_char(tonumber(v) or 63)
		elseif kind == "#x" or kind == "#X" then
			return utf8_char(tonumber(v, 16) or 63)
		end
		return ENTITIES[v] or ("&" .. v .. ";")
	end))
end

-- (text for the hypertext markup: its < > \ are escaped)
local function ht_escape(s)
	return (s:gsub("[\\<>]", "\\%0"))
end

-- the visible length of hypertext markup (tags out, escapes undone; UTF-8
-- characters count once)
local function plain_len(s)
	s = s:gsub("\\(.)", "%1x"):gsub("<[^<>]*>", ""):gsub("\\.", "x")
	local _, n = s:gsub("[^\128-\191]", "")
	return n
end

local function url_encode(s)
	return (s:gsub("[^%w%-_%.~]", function(c)
		return ("%%%02X"):format(c:byte())
	end))
end

local function url_decode(s)
	return (s:gsub("%%(%x%x)", function(h) return string.char(tonumber(h, 16)) end))
end

local function has_class(node, c)
	local cls = node.attrs and node.attrs.class
	return cls and (" " .. cls .. " "):find(" " .. c .. " ", 1, true) ~= nil
end

-- ---------------------------------------------------------------- HTML -> tree
local VOID = {img = true, br = true, hr = true, meta = true, link = true, input = true,
	source = true, wbr = true, col = true, area = true}

local function parse_attrs(s)
	local a = {}
	for k, v in s:gmatch('([%w%-:]+)%s*=%s*"(.-)"') do
		a[k:lower()] = decode(v)
	end
	for k, v in s:gmatch("([%w%-:]+)%s*=%s*'(.-)'") do
		a[k:lower()] = a[k:lower()] or decode(v)
	end
	return a
end

local function parse(html)
	html = html:gsub("<!%-%-.-%-%->", ""):gsub("<script.-</script>", ""):gsub("<style.-</style>", "")
	local root = {tag = "root", attrs = {}, kids = {}}
	local stack = {root}
	local pos = 1
	while true do
		local s, e, close, name, attrs = html:find("<(/?)([%w]+)(.-)>", pos)
		local top = stack[#stack]
		local text = html:sub(pos, (s or #html + 1) - 1)
		if text ~= "" then
			top.kids[#top.kids + 1] = {text = text}
		end
		if not s then
			break
		end
		name = name:lower()
		if close == "/" then
			for k = #stack, 2, -1 do
				if stack[k].tag == name then
					for _ = #stack, k, -1 do
						stack[#stack] = nil
					end
					break
				end
			end
		else
			local node = {tag = name, attrs = parse_attrs(attrs), kids = {}}
			top.kids[#top.kids + 1] = node
			if not VOID[name] and not attrs:find("/%s*$") then
				stack[#stack + 1] = node
			end
		end
		pos = e + 1
	end
	return root
end

-- ---------------------------------------------------------------- tree -> hypertext
local GOLD, GOLD2, LINK, DIM, CODE = "#FFD25A", "#F0C060", "#78C8FF", "#A3A3AD", "#E8D8B0"
-- NetHack's colours, as the wiki marks its symbols (class clr-<name>)
local CLR = {
	black = "#606060", red = "#E03030", green = "#30B030", brown = "#B07020", blue = "#4060FF",
	magenta = "#C040C0", cyan = "#30B0B0", gray = "#B0B0B0", grey = "#B0B0B0", orange = "#FF9020",
	["bright-green"] = "#60FF60", brightgreen = "#60FF60", yellow = "#FFFF40",
	["bright-blue"] = "#80A0FF", brightblue = "#80A0FF", ["bright-magenta"] = "#FF70FF",
	brightmagenta = "#FF70FF", ["bright-cyan"] = "#70FFFF", brightcyan = "#70FFFF", white = "#FFFFFF",
}
local SKIP_CLASS = {"mw-editsection", "toc", "navbox", "noprint", "reference", "references",
	"mw-references-wrap", "printfooter", "catlinks", "mw-empty-elt", "mw-cite-backlink",
	"navigation-not-searchable", "mw-jump-link", "languages"}
local NBSP = "\194\160"

local function hidden(node)
	local style = node.attrs and node.attrs.style
	if style and style:lower():find("display%s*:%s*none") then
		return true
	end
	for _, c in ipairs(SKIP_CLASS) do
		if has_class(node, c) then
			return true
		end
	end
	return false
end

local function css_color(node)
	for c in (node.attrs.class or ""):gmatch("clr%-([%w%-]+)") do
		if CLR[c] then
			return CLR[c]
		end
	end
	local style = node.attrs.style
	local col = style and style:match("[^%-]color%s*:%s*([^;]+)") or (style and style:match("^color%s*:%s*([^;]+)"))
	if col then
		col = col:gsub("%s+$", "")
		if col:match("^#%x%x%x%x?%x?%x?$") or col:match("^%a+$") then
			return col
		end
	end
end

-- a buffer the renderer writes to; nl = newlines at its end (for blocks)
local function new_out()
	return {parts = {}, nl = 2}
end

local function emit(out, s)
	if s == "" then
		return
	end
	out.parts[#out.parts + 1] = s
	local trail = #(s:match("\n*$"))
	if trail == #s then
		out.nl = out.nl + trail
	else
		out.nl = trail
	end
end

local function tag(out, s) -- (markup: doesn't change the line)
	out.parts[#out.parts + 1] = s
end

local function block(out, n, ctx)
	if ctx.inline then
		if out.nl == 0 and #out.parts > 0 then
			emit(out, " ")
		end
		return
	end
	if out.nl < n then
		emit(out, ("\n"):rep(n - out.nl))
	end
end

local render

local function render_kids(node, out, ctx)
	for _, k in ipairs(node.kids) do
		render(k, out, ctx)
	end
end

local function text_of(node, out, ctx)
	local s = node.text
	if ctx.pre then
		emit(out, ht_escape(decode(s)))
		return
	end
	s = decode(s):gsub("[ \t\r\n]+", " ")
	if out.nl > 0 or (#out.parts == 0) then
		s = s:gsub("^ +", "")
	end
	if s ~= "" then
		emit(out, ht_escape(s))
	end
end

-- a link: wiki pages become actions (the viewer opens them)
local function link_target(href)
	if not href then
		return nil
	end
	local page = href:match("^/wiki/(.+)$") or href:match("^" .. SITE:gsub("%p", "%%%0") .. "/wiki/(.+)$")
	if not page then
		return nil
	end
	page = url_decode(page:gsub("#.*$", "")):gsub("_", " ")
	if page:match("^File:") or page:match("^Special:") or page:match("^Category:") then
		return nil
	end
	return page
end

local function render_img(node, out, ctx)
	local src = node.attrs.src or ""
	local w, h = tonumber(node.attrs.width), tonumber(node.attrs.height)
	if not src:match("^/images/") or not (src:lower():match("%.png$") or src:lower():match("%.jpe?g$")) then
		return
	end
	local name = "nhvwiki_" .. src:gsub("^/images/", ""):gsub("[^%w%.]", "_")
	ctx.imgs[#ctx.imgs + 1] = {name = name, url = SITE .. src}
	if not wiki.media[name] then
		return -- (not here yet: fetched with the page; shown next time)
	end
	-- (small pixel art doubled, big pictures kept within the page)
	if w and h then
		local k = (w <= 32 and h <= 32) and 2 or 1
		w, h = w * k, h * k
		if w > 500 then
			h, w = math.floor(h * 500 / w), 500
		end
		tag(out, ("<img name=%s width=%d height=%d>"):format(name, w, h))
	else
		tag(out, ("<img name=%s>"):format(name))
	end
end

-- Tables. An infobox (rows of a heading and a value, the monster and
-- object boxes) becomes "Heading: value" lines; any other table a grid of
-- cells padded to line up in the monospace font.
local function rows_of(tbl)
	local rows = {}
	local function walk(n)
		for _, k in ipairs(n.kids) do
			if k.tag == "tr" then
				if not hidden(k) then
					rows[#rows + 1] = k
				end
			elseif k.tag == "thead" or k.tag == "tbody" or k.tag == "tfoot" then
				walk(k)
			end
		end
	end
	walk(tbl)
	return rows
end

local function cells_of(tr)
	local cells = {}
	for _, k in ipairs(tr.kids) do
		if (k.tag == "td" or k.tag == "th") and not hidden(k) then
			cells[#cells + 1] = k
		end
	end
	return cells
end

local function inline(node, ctx)
	local o = new_out()
	o.nl = 0
	local saved = ctx.inline
	ctx.inline = true
	render_kids(node, o, ctx)
	ctx.inline = saved
	return (table.concat(o.parts):gsub("^%s+", ""):gsub("%s+$", ""))
end

local function has_table(node)
	for _, k in ipairs(node.kids or {}) do
		if k.tag == "table" or has_table(k) then
			return true
		end
	end
	return false
end

local function render_table(tbl, out, ctx)
	local rows = rows_of(tbl)
	if #rows == 0 then
		return
	end
	-- (a table used for layout - a table of tables, a box around one: its
	-- cells are just blocks)
	local nested = false
	for _, tr in ipairs(rows) do
		for _, c in ipairs(cells_of(tr)) do
			if has_table(c) then
				nested = true
			end
		end
	end
	if nested then
		for _, tr in ipairs(rows) do
			for _, c in ipairs(cells_of(tr)) do
				block(out, 1, ctx)
				render_kids(c, out, ctx)
			end
		end
		block(out, 1, ctx)
		return
	end
	-- an infobox: each row a heading and a value, or one cell across
	local infobox, two = true, 0
	for _, tr in ipairs(rows) do
		local cells = cells_of(tr)
		if #cells == 2 and cells[1].tag == "th" then
			two = two + 1
		elseif #cells > 2 then
			infobox = false
		end
	end
	block(out, 2, ctx)
	for _, cap in ipairs(tbl.kids) do
		if cap.tag == "caption" then
			emit(out, "<b>" .. inline(cap, ctx) .. "</b>")
			block(out, 1, ctx)
		end
	end
	if infobox and two > 0 then
		for _, tr in ipairs(rows) do
			local cells = cells_of(tr)
			if #cells == 2 then
				local k, v = inline(cells[1], ctx), inline(cells[2], ctx)
				emit(out, ("<style color=%s><b>%s</b></style>: %s"):format(GOLD2, k, v))
				block(out, 1, ctx)
			elseif #cells == 1 then
				local c = cells[1]
				if c.tag == "th" then
					emit(out, ("<big><b>%s</b></big>"):format(inline(c, ctx)))
					block(out, 1, ctx)
				else
					-- (a whole block in one cell: a list of facts...)
					local saved = out.nl
					render_kids(c, out, ctx)
					if out.nl == saved and #out.parts > 0 then
						block(out, 1, ctx)
					end
					block(out, 1, ctx)
				end
			end
		end
		block(out, 2, ctx)
		return
	end
	-- a grid
	local grid, widths = {}, {}
	for r, tr in ipairs(rows) do
		grid[r] = {}
		for c, cell in ipairs(cells_of(tr)) do
			local s = inline(cell, ctx)
			if cell.tag == "th" then
				s = "<b>" .. s .. "</b>"
			end
			grid[r][c] = s
			widths[c] = math.max(widths[c] or 0, math.min(40, plain_len(s)))
		end
	end
	local total = 0
	for _, w in ipairs(widths) do
		total = total + w + 3
	end
	if total > 110 then
		-- (too wide to line up: a row per line, its cells separated)
		for _, row in ipairs(grid) do
			emit(out, table.concat(row, ("  <style color=%s>|</style>  "):format(DIM)))
			block(out, 1, ctx)
		end
	else
		for _, row in ipairs(grid) do
			local line = {}
			for c, s in ipairs(row) do
				local pad = math.max(0, (widths[c] or 0) - plain_len(s))
				line[#line + 1] = s .. (c < #row and (" "):rep(pad) or "")
			end
			emit(out, "<mono>" .. table.concat(line, ("  <style color=%s>|</style> "):format(DIM)) .. "</mono>")
			block(out, 1, ctx)
		end
	end
	block(out, 2, ctx)
end

local HEADINGS = {
	h1 = {"<bigger><b><style color=" .. GOLD .. ">", "</style></b></bigger>"},
	h2 = {"<bigger><b><style color=" .. GOLD .. ">", "</style></b></bigger>"},
	h3 = {"<big><b><style color=" .. GOLD2 .. ">", "</style></b></big>"},
	h4 = {"<b><style color=" .. GOLD2 .. ">", "</style></b>"},
	h5 = {"<b>", "</b>"}, h6 = {"<b>", "</b>"},
}
local WRAP = {
	b = {"<b>", "</b>"}, strong = {"<b>", "</b>"}, i = {"<i>", "</i>"}, em = {"<i>", "</i>"},
	cite = {"<i>", "</i>"}, var = {"<i>", "</i>"}, dfn = {"<i>", "</i>"}, u = {"<u>", "</u>"},
	ins = {"<u>", "</u>"}, small = {"", ""}, big = {"<big>", "</big>"},
	code = {"<mono><style color=" .. CODE .. ">", "</style></mono>"},
	tt = {"<mono>", "</mono>"}, kbd = {"<mono><b>", "</b></mono>"}, samp = {"<mono>", "</mono>"},
	s = {"<style color=" .. DIM .. ">", "</style>"}, del = {"<style color=" .. DIM .. ">", "</style>"},
	strike = {"<style color=" .. DIM .. ">", "</style>"},
}

function render(node, out, ctx)
	if node.text then
		return text_of(node, out, ctx)
	end
	if hidden(node) then
		return
	end
	local t = node.tag
	if HEADINGS[t] then
		block(out, 2, ctx)
		tag(out, HEADINGS[t][1])
		emit(out, inline(node, ctx))
		tag(out, HEADINGS[t][2])
		block(out, 1, ctx)
	elseif t == "p" then
		block(out, 2, ctx)
		render_kids(node, out, ctx)
		block(out, 1, ctx)
	elseif t == "br" then
		if ctx.inline then
			emit(out, " ")
		else
			emit(out, "\n")
		end
	elseif t == "hr" then
		block(out, 1, ctx)
		emit(out, ("<style color=%s>%s</style>"):format(DIM, ("\226\148\128"):rep(40)))
		block(out, 1, ctx)
	elseif t == "ul" or t == "ol" then
		ctx.depth = ctx.depth + 1
		local n = 0
		for _, k in ipairs(node.kids) do
			if k.tag == "li" and not hidden(k) then
				n = n + 1
				block(out, 1, ctx)
				local mark = t == "ol" and (n .. ".") or "\226\128\162"
				emit(out, NBSP:rep(3 * ctx.depth) .. mark .. " ")
				render_kids(k, out, ctx)
			elseif not k.text then
				render(k, out, ctx)
			end
		end
		ctx.depth = ctx.depth - 1
		block(out, ctx.depth == 0 and 2 or 1, ctx)
	elseif t == "dl" then
		for _, k in ipairs(node.kids) do
			if k.tag == "dt" and not hidden(k) then
				block(out, 1, ctx)
				emit(out, "<b>" .. inline(k, ctx) .. "</b>")
			elseif k.tag == "dd" and not hidden(k) then
				block(out, 1, ctx)
				emit(out, NBSP:rep(3 * (ctx.depth + 1)))
				render_kids(k, out, ctx)
			elseif not k.text then
				render(k, out, ctx)
			end
		end
		block(out, 1, ctx)
	elseif t == "pre" then
		block(out, 1, ctx)
		tag(out, "<mono><style color=" .. CODE .. ">")
		local saved = ctx.pre
		ctx.pre = true
		render_kids(node, out, ctx)
		ctx.pre = saved
		tag(out, "</style></mono>")
		block(out, 2, ctx)
	elseif t == "blockquote" then
		block(out, 2, ctx)
		tag(out, "<i>")
		render_kids(node, out, ctx)
		tag(out, "</i>")
		block(out, 2, ctx)
	elseif t == "center" then
		block(out, 1, ctx)
		tag(out, "<center>")
		render_kids(node, out, ctx)
		tag(out, "</center>")
		block(out, 1, ctx)
	elseif t == "table" then
		render_table(node, out, ctx)
	elseif t == "img" then
		render_img(node, out, ctx)
	elseif t == "a" then
		local target = link_target(node.attrs.href)
		if target and not has_class(node, "new") then
			ctx.links[#ctx.links + 1] = target
			tag(out, ("<action name=w%d>"):format(#ctx.links))
			render_kids(node, out, ctx)
			tag(out, "</action>")
		else
			render_kids(node, out, ctx)
		end
	elseif WRAP[t] then
		tag(out, WRAP[t][1])
		render_kids(node, out, ctx)
		tag(out, WRAP[t][2])
	elseif t == "span" or t == "font" then
		local col = css_color(node)
		if col then
			tag(out, ("<style color=%s>"):format(col))
			render_kids(node, out, ctx)
			tag(out, "</style>")
		else
			render_kids(node, out, ctx)
		end
	elseif t == "div" then
		local thumbcap = has_class(node, "thumbcaption")
		block(out, 1, ctx)
		if thumbcap then
			tag(out, ("<i><style color=%s>"):format(DIM))
		end
		render_kids(node, out, ctx)
		if thumbcap then
			tag(out, "</style></i>")
		end
		block(out, 1, ctx)
	elseif t == "sup" or t == "sub" then
		render_kids(node, out, ctx)
	else
		render_kids(node, out, ctx)
	end
end

-- a page's HTML -> hypertext, its links (action w<n> -> page) and images
function wiki.convert(html)
	local ctx = {links = {}, imgs = {}, depth = 0}
	local out = new_out()
	render(parse(html), out, ctx)
	local text = table.concat(out.parts):gsub("\n\n\n+", "\n\n"):gsub("^%s+", "")
	return text, ctx.links, ctx.imgs
end

-- ---------------------------------------------------------------- fetching
wiki.media = {}  -- texture name -> true once on the client
local inflight = {} -- image name -> true while fetching

local function cache_file(title)
	return CACHE .. DIR_DELIM .. title:lower():gsub("[^%w]", "_"):sub(1, 100) .. ".json"
end

local function cache_read(title)
	local f = io.open(cache_file(title), "rb")
	if not f then
		return nil
	end
	local data = core.parse_json(f:read("*a"))
	f:close()
	return type(data) == "table" and data or nil
end

local function cache_write(title, data)
	local f = io.open(cache_file(title), "wb")
	if f then
		f:write(core.write_json(data))
		f:close()
	end
end

local function fetch(url, cb)
	if not http then
		cb(nil)
		return
	end
	http.fetch({url = url, timeout = 12, user_agent = USER_AGENT}, function(res)
		if not (res.succeeded and res.code == 200) then
			core.log("warning", ("[nhv] wiki: %s: %s (HTTP %s)"):format(url,
				res.timeout and "timed out" or (res.succeeded and "refused" or "failed"), tostring(res.code)))
		end
		cb(res.succeeded and res.code == 200 and res.data or nil)
	end)
end

-- an image onto the client: from the cache folder, else the wiki
local function want_image(img, done)
	if wiki.media[img.name] then
		return done()
	end
	local path = CACHE .. DIR_DELIM .. "img" .. DIR_DELIM .. img.name
	local function add(data)
		if not data or wiki.media[img.name] then
			return done()
		end
		local player = nhv.player.get()
		local ok = core.dynamic_add_media({filename = img.name, filedata = data,
			to_player = player and player:get_player_name(), ephemeral = true}, function()
			wiki.media[img.name] = true
			done()
		end)
		if not ok then
			done()
		end
	end
	local f = io.open(path, "rb")
	if f then
		local data = f:read("*a")
		f:close()
		return add(data)
	end
	if inflight[img.name] then
		return done()
	end
	inflight[img.name] = true
	fetch(img.url, function(data)
		inflight[img.name] = nil
		if data then
			local w = io.open(path, "wb")
			if w then
				w:write(data)
				w:close()
			end
		end
		add(data)
	end)
end

-- a page: {title, html, t}, from the cache if fresh, else the wiki (the
-- cached copy if the wiki can't be reached); nil + "missing"/"offline"
local function get_page(title, cb)
	local cached = cache_read(title)
	if cached and os.time() - (cached.t or 0) < FRESH_S then
		return cb(cached)
	end
	local url = API .. "?action=parse&format=json&formatversion=2&redirects=1"
		.. "&prop=text%7Cdisplaytitle&disableeditsection=1&disabletoc=1&page=" .. url_encode(title)
	fetch(url, function(data)
		local j = data and core.parse_json(data)
		if j and j.parse and j.parse.text then
			local page = {title = j.parse.title, html = j.parse.text, t = os.time()}
			cache_write(title, page)
			if page.title ~= title then
				cache_write(page.title, page)
			end
			cb(page)
		elseif j and j.error and j.error.code == "missingtitle" then
			cb(nil, "missing")
		elseif cached then
			cached.stale = true
			cb(cached)
		else
			cb(nil, "offline")
		end
	end)
end

local function search(q, cb)
	local url = API .. "?action=opensearch&format=json&limit=25&namespace=0&search=" .. url_encode(q)
	fetch(url, function(data)
		local j = data and core.parse_json(data)
		cb(type(j) == "table" and type(j[2]) == "table" and j[2] or nil)
	end)
end

-- ---------------------------------------------------------------- the viewer
local view = {history = {}, pos = 0, links = {}, query = "", open = false, recent = {}}

local QUICK = {"Monster", "Object", "Role", "Race", "Alignment", "Prayer", "Elbereth",
	"Price identification", "Mazes of Menace", "Gnomish Mines", "Sokoban", "Oracle",
	"Big Room", "Quest", "Gehennom", "Ascension", "Main Page"}

local function show(body, title, note)
	local player = nhv.player.get()
	if not player then
		return
	end
	local E = core.formspec_escape
	local w, h = 18, 12.2
	local ht = ("<global margin=12 color=#E8E6DF hovercolor=#FFFFFF>"
		.. "<tag name=action color=%s hovercolor=#FFFFFF>"):format(LINK)
	if title and title ~= "" then
		ht = ht .. ("<bigger><b><style color=%s>%s</style></b></bigger>\n"):format(GOLD, ht_escape(title))
	end
	if note then
		ht = ht .. ("<i><style color=%s>%s</style></i>\n"):format(DIM, ht_escape(note))
	end
	ht = ht .. "\n" .. body
	local credit = title and title ~= ""
		and ("From NetHackWiki (nethackwiki.com/wiki/%s), CC BY-SA 3.0"):format(title:gsub(" ", "_"))
		or "NetHackWiki: the NetHack wiki, nethackwiki.com (CC BY-SA 3.0)"
	local fs = nhv.theme.head(w, h)
		.. "button[0.3,0.3;1.0,0.8;back;<]button[1.4,0.3;1.0,0.8;fwd;>]"
		.. "button[2.5,0.3;1.6,0.8;home;Home]"
		.. ("field[4.3,0.3;9.4,0.8;q;;%s]field_close_on_enter[q;false]"):format(E(view.query or ""))
		.. "button[13.8,0.3;1.9,0.8;go;Search]button_exit[15.9,0.3;1.8,0.8;close;Close]"
		.. ("hypertext[0.3,1.3;17.4,10.1;page;%s]"):format(E(ht))
		.. ("label[0.4,11.8;%s]"):format(nhv.theme.dim(E(credit)))
	view.open = true
	core.show_formspec(player:get_player_name(), FORM, fs)
	nhv.player.freeze(true)
end

local function home_page()
	view.links = {}
	local lines = {"Look things up on NetHackWiki, the NetHack wiki. Search above, or press F2 while",
		"looking at a monster, an object or a feature to open its page.", "",
		("<b><style color=%s>Start with</style></b>"):format(GOLD2)}
	for k, t in ipairs(QUICK) do
		view.links[k] = t
		lines[#lines + 1] = ("\226\128\162 <action name=w%d>%s</action>"):format(k, ht_escape(t))
	end
	if #view.recent > 0 then
		lines[#lines + 1] = ""
		lines[#lines + 1] = ("<b><style color=%s>Recently viewed</style></b>"):format(GOLD2)
		for _, t in ipairs(view.recent) do
			view.links[#view.links + 1] = t
			lines[#lines + 1] = ("\226\128\162 <action name=w%d>%s</action>"):format(#view.links, ht_escape(t))
		end
	end
	if not http then
		lines[#lines + 1] = ""
		lines[#lines + 1] = "<i>(The game isn't allowed to reach the internet: add nhv to the setting secure.http_mods.)</i>"
	end
	show(table.concat(lines, "\n"), "NetHackWiki")
end

local function remember(title)
	for k = #view.recent, 1, -1 do
		if view.recent[k] == title then
			table.remove(view.recent, k)
		end
	end
	table.insert(view.recent, 1, title)
	view.recent[13] = nil
end

local function results_page(q, titles)
	view.links = {}
	local lines = {}
	if not titles then
		lines[1] = "Couldn't reach NetHackWiki. Check your internet connection and try again."
	elseif #titles == 0 then
		lines[1] = ("Nothing on NetHackWiki matches \"%s\"."):format(ht_escape(q))
	else
		for k, t in ipairs(titles) do
			view.links[k] = t
			lines[#lines + 1] = ("\226\128\162 <action name=w%d>%s</action>"):format(k, ht_escape(t))
		end
	end
	show(table.concat(lines, "\n"), "Search: " .. q)
end

local token = 0 -- (a newer request wins: an older answer arriving late is dropped)

-- show a page (by title); from history: don't add to it
local function load(title, from_history)
	token = token + 1
	local mine = token
	if title == HOME then
		home_page()
	else
		show(("<i>Loading %s...</i>"):format(ht_escape(title)), title)
	end
	if not from_history then
		for k = #view.history, view.pos + 1, -1 do
			view.history[k] = nil
		end
		view.history[#view.history + 1] = title
		view.pos = #view.history
	end
	if title == HOME then
		return
	end
	get_page(title, function(page, why)
		if mine ~= token or not view.open then
			return
		end
		if not page then
			if why == "missing" then
				-- no such page: what the wiki has by that name
				view.query = title
				search(title, function(titles)
					if mine == token and view.open then
						if titles and #titles == 1 then
							view.history[view.pos] = titles[1]
							load(titles[1], true)
						else
							results_page(title, titles)
						end
					end
				end)
			else
				show("Couldn't reach NetHackWiki, and this page hasn't been opened before. "
					.. "Check your internet connection and try again.", title)
			end
			return
		end
		local text, links, imgs = wiki.convert(page.html)
		remember(page.title)
		view.history[view.pos] = page.title
		local function present()
			if mine == token and view.open then
				view.links = links
				local body = text
				-- (images that arrived meanwhile: the page again, with them)
				if #imgs > 0 then
					body = (wiki.convert(page.html))
				end
				show(body, page.title, page.stale and "(saved copy: NetHackWiki couldn't be reached)" or nil)
			end
		end
		-- the page's images first (briefly; ones still on their way show
		-- next time it's opened)
		local left, shown = #imgs, false
		local function one_done()
			left = left - 1
			if left <= 0 and not shown then
				shown = true
				present()
			end
		end
		if left == 0 then
			shown = true
			present()
		else
			core.after(IMG_WAIT_S, function()
				if not shown then
					shown = true
					present()
				end
			end)
			for _, img in ipairs(imgs) do
				want_image(img, one_done)
			end
		end
	end)
end

function wiki.open(title)
	view.query = ""
	load(title or HOME)
end

function wiki.close()
	local player = nhv.player.get()
	if player and view.open then
		core.close_formspec(player:get_player_name(), FORM)
	end
	view.open = false
	if not (nhv.ui and nhv.ui.open) then
		nhv.player.freeze(false)
	end
end

core.register_on_player_receive_fields(function(player, formname, fields)
	if formname ~= FORM then
		return
	end
	if fields.quit then
		-- (Esc, Close, or F2 again)
		view.open = false
		view.closed_at = core.get_us_time()
		if not (nhv.ui and nhv.ui.open) then
			nhv.player.freeze(false)
		end
		return true
	end
	if fields.q then
		view.query = fields.q
	end
	if fields.page then
		local n = fields.page:match("^action:w(%d+)$")
		local target = n and view.links[tonumber(n)]
		if target then
			load(target)
		end
	elseif fields.back and view.pos > 1 then
		view.pos = view.pos - 1
		load(view.history[view.pos], true)
	elseif fields.fwd and view.pos < #view.history then
		view.pos = view.pos + 1
		load(view.history[view.pos], true)
	elseif fields.home then
		load(HOME)
	elseif (fields.go or fields.key_enter_field == "q") and (fields.q or "") ~= "" then
		local q = fields.q:gsub("^%s+", ""):gsub("%s+$", "")
		token = token + 1
		local mine = token
		show(("<i>Searching for %s...</i>"):format(ht_escape(q)), "Search: " .. q)
		search(q, function(titles)
			if mine ~= token or not view.open then
				return
			end
			-- (an exact title: straight to it)
			for _, t in ipairs(titles or {}) do
				if t:lower() == q:lower() then
					return load(t)
				end
			end
			results_page(q, titles)
		end)
	end
	return true
end)

-- ---------------------------------------------------------------- what to look up
-- Only what the hero knows: names as NetHack gives them (doname), with an
-- unidentified potion, scroll... going to its class's page.
local CLASS_PAGE = {}
do
	local OC = U.OCLASS
	CLASS_PAGE[OC.POTION] = {"potions? of (.+)", "Potion of %s", "Potion"}
	CLASS_PAGE[OC.SCROLL] = {"scrolls? of (.+)", "Scroll of %s", "Scroll"}
	CLASS_PAGE[OC.SPBOOK] = {"spellbooks? of (.+)", "Spellbook of %s", "Spellbook"}
	CLASS_PAGE[OC.RING] = {"rings? of (.+)", "Ring of %s", "Ring"}
	CLASS_PAGE[OC.WAND] = {"wands? of (.+)", "Wand of %s", "Wand"}
	CLASS_PAGE[OC.AMULET] = {"amulets? of (.+)", "Amulet of %s", "Amulet"}
end

local STRIP = {"uncursed", "blessed", "cursed", "unholy", "rusty", "very", "thoroughly",
	"burnt", "rotted", "corroded", "fireproof", "rustproof", "corrodeproof", "partly",
	"eaten", "greased", "diluted", "lit", "empty", "unlit", "unpaid"}

function wiki.title_for_object(o)
	local name = (o.name or ""):lower()
	name = name:gsub("%s*%b()", ""):gsub("%s*%b[]", "")
	name = name:gsub(" named .*$", "")
	local called = name:find(" called ") ~= nil
	name = name:gsub(" called .*$", "")
	name = name:gsub("^an? ", ""):gsub("^the ", ""):gsub("^%d+ ", "")
	local again = true
	while again do
		again = false
		for _, w in ipairs(STRIP) do
			local n2 = name:gsub("^" .. w .. " ", "")
			if n2 ~= name then
				name, again = n2, true
			end
		end
		local n3 = name:gsub("^[%+%-]%d+ ", "")
		if n3 ~= name then
			name, again = n3, true
		end
	end
	local cp = CLASS_PAGE[o.oclass]
	if cp then
		local what = not called and name:match("^" .. cp[1] .. "$")
		return what and cp[2]:format(what) or cp[3]
	end
	if o.oclass == U.OCLASS.GEM and (name:match(" gems?$") or name:match("^%a+ stones?$")) then
		return name:match("gray stone") and "Gray stone" or "Gem"
	end
	-- a corpse, an egg or a tin of something: the something
	local of = name:match("^(.+) corpses?$")
	if of then
		return of
	end
	if name:match("^statue of") then
		return "Statue"
	end
	if name:match(" eggs?$") then
		return "Egg"
	end
	if name:match("^tins? of") then
		return "Tin"
	end
	return name
end

local FEATURE_PAGE = {
	S_fountain = "Fountain", S_altar = "Altar", S_throne = "Throne", S_sink = "Sink",
	S_grave = "Grave", S_tree = "Tree", S_upstair = "Staircase", S_dnstair = "Staircase",
	S_upladder = "Ladder", S_dnladder = "Ladder", S_pool = "Water", S_water = "Water",
	S_lava = "Lava", S_ice = "Ice", S_bars = "Iron bars", S_web = "Web",
	S_vodoor = "Door", S_hodoor = "Door", S_vcdoor = "Door", S_hcdoor = "Door",
	S_ndoor = "Doorway", S_vodbridge = "Drawbridge", S_hodbridge = "Drawbridge",
	S_engroom = "Engraving", S_engrcorr = "Engraving",
}

-- what's under the crosshair, as a wiki title (nil: nothing to look up)
function wiki.title_for_pointed(player)
	local p = nhv.actions.pointed(player)
	if p.kind == "mon" and p.mon and p.mon.mon and p.mon.mon.mndx then
		local name = core.nh_mon_name(p.mon.mon.mndx)
		if name and name ~= "" then
			return name
		end
	end
	local snap = nhv.nh.snap
	if not (snap and p.tx and U.in_map(p.tx, p.ty)) then
		return nil
	end
	local i = U.idx(p.tx, p.ty)
	local h = snap.hero
	local visible = U.has(snap.map.flags[i], U.LOC_CANSEE) or (h and h.x == p.tx and h.y == p.ty)
	if visible and nhv.mobs.objs[i] then
		local items = nhv.mobs.floor_items(p.tx, p.ty)
		if items[1] then
			return wiki.title_for_object(items[1])
		end
	end
	local gi = nhv.glyph_info(snap.map.mem[i])
	local cmap = gi.kind == "cmap" and nhv.cmap_name(gi.index)
	if cmap then
		if FEATURE_PAGE[cmap] then
			return FEATURE_PAGE[cmap]
		end
		-- a trap: its name ("S_arrow_trap" -> "Arrow trap")
		if gi.sym == 94 then
			local t = cmap:gsub("^S_", ""):gsub("_", " ")
			return t:sub(1, 1):upper() .. t:sub(2)
		end
	end
	if p.kind == "door" then
		return "Door"
	end
	return nil
end

-- F2: the viewer, on what you're looking at, else where you left it
function wiki.toggle(player)
	if view.open then
		return wiki.close()
	end
	-- (the F2 that just closed it reaches the game too: not again)
	if view.closed_at and core.get_us_time() - view.closed_at < 400000 then
		return
	end
	local title = player and wiki.title_for_pointed(player)
	if title then
		view.query = ""
		load(title:sub(1, 1):upper() .. title:sub(2))
	elseif view.history[view.pos] then
		load(view.history[view.pos], true)
	else
		wiki.open()
	end
end

core.register_chatcommand("wiki", {
	params = "[page]",
	description = "(VoxHack) look something up on NetHackWiki",
	func = function(_, param)
		param = (param or ""):gsub("^%s+", ""):gsub("%s+$", "")
		wiki.open(param ~= "" and param or nil)
		return true
	end,
})

return wiki
