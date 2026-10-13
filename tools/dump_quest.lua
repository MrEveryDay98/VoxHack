-- Dump NetHack's dat/quest.lua (the questtext table) as JSON on stdout.
-- usage: luajit dump_quest.lua <path to quest.lua>
local path = arg[1]
dofile(path)

local function esc(s)
	return '"' .. s:gsub('[%c"\\]', function(c)
		if c == "\n" then return "\\n" end
		if c == "\t" then return "\\t" end
		if c == '"' then return '\\"' end
		if c == "\\" then return "\\\\" end
		return string.format("\\u%04x", c:byte())
	end) .. '"'
end

local function encode(v)
	local t = type(v)
	if t == "string" then
		return esc(v)
	elseif t == "number" or t == "boolean" then
		return tostring(v)
	elseif t == "table" then
		if #v > 0 then
			local out = {}
			for _, x in ipairs(v) do
				out[#out + 1] = encode(x)
			end
			return "[" .. table.concat(out, ",") .. "]"
		end
		local keys = {}
		for k in pairs(v) do
			keys[#keys + 1] = tostring(k)
		end
		table.sort(keys)
		local out = {}
		for _, k in ipairs(keys) do
			out[#out + 1] = esc(k) .. ":" .. encode(v[k])
		end
		return "{" .. table.concat(out, ",") .. "}"
	end
	return "null"
end

io.write(encode(questtext))
