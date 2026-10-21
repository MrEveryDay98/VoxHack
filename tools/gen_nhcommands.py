"""Write game/nethackvoxel/mods/nhv/nhcommands.lua: NetHack's commands (the
F3 list) from its own command table (external/nethack/src/cmd.c,
extcmdlist), with NetHack's own short descriptions and keys.

Left out: wizard mode's, internal and movement commands, and VoxHack's own
(#nhv...). Run again after updating NetHack:

    python -I tools/gen_nhcommands.py
"""
import os
import re

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CMD_C = os.path.join(ROOT, "external", "nethack", "src", "cmd.c")
OUT = os.path.join(ROOT, "game", "nethackvoxel", "mods", "nhv", "nhcommands.lua")

SKIP_FLAGS = ("WIZMODECMD", "INTERNALCMD", "MOVEMENTCMD")
# (not in this build: no shell or suspend on Windows; no crash reports)
SKIP_NAMES = {"#", "bugreport", "shell", "suspend"}

ENTRY = re.compile(
	r"\{\s*(?P<key>'(?:\\[0-7]+|\\.|[^'])'|[MC]\('(?:\\.|[^'])'\)|\w+)\s*,\s*"
	r'"(?P<name>[^"]*)"\s*,\s*"(?P<desc>(?:[^"\\]|\\.)*)"\s*,'
	r"\s*(?:/\*.*?\*/\s*)*(?P<func>\w+)\s*,\s*(?P<flags>[^,]*),",
	re.S)


# (the item class symbols some commands use as their key)
SYMS = {"AMULET_SYM": '"', "ARMOR_SYM": "[", "RING_SYM": "=", "TOOL_SYM": "(",
	"WEAPON_SYM": ")", "GOLD_SYM": "$", "SPBOOK_SYM": "+"}


def key_text(k):
	if k in SYMS:
		return SYMS[k]
	m = re.match(r"([MC])\('(.+)'\)$", k)
	if m:
		c = m.group(2).replace("\\", "")
		return ("M-" if m.group(1) == "M" else "^") + (c.upper() if m.group(1) == "C" else c)
	if k in ("0", "'\\0'"):
		return ""
	c = k[1:-1]
	return {"\\177": "Delete", "\\033": "Esc", "\\n": "Enter", " ": "Space", "\\\\": "\\", "\\'": "'"}.get(c, c)


def main():
	src = open(CMD_C, encoding="latin-1").read()
	table = src[src.index("struct ext_func_tab extcmdlist[] = {"):]
	table = table[:table.index("\n};")]
	rows = []
	for m in ENTRY.finditer(table):
		name, flags = m.group("name"), m.group("flags")
		if name in SKIP_NAMES or name.startswith("nhv") or any(f in flags for f in SKIP_FLAGS):
			continue
		desc = m.group("desc").replace('\\"', '"')
		rows.append((name, key_text(m.group("key")), desc))
	lines = ["-- NetHack's commands, for the F3 list (commands.lua). Made by",
		"-- tools/gen_nhcommands.py from NetHack's own command table (src/cmd.c):",
		"-- don't edit; run it again instead.",
		"-- {extended command name, NetHack's key (\"\": none), what it does}",
		"return {"]
	for name, key, desc in rows:
		lines.append("\t{%s, %s, %s}," % tuple('"%s"' % s.replace("\\", "\\\\").replace('"', '\\"')
			for s in (name, key, desc)))
	lines.append("}")
	with open(OUT, "w", newline="\n") as f:
		f.write("\n".join(lines) + "\n")
	print("%d commands -> %s" % (len(rows), OUT))


if __name__ == "__main__":
	main()
