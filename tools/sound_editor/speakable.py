"""Turn dialogue lines into text a text-to-speech voice can read.

NetHack fills placeholders in when a line is shown: %n is the quest
nemesis, %o the quest artifact, %p the player's name, and printf-style
codes like %s or %d are names and numbers. A recording can't change with
them, so:

  * placeholders that are fixed for a role's quest (leader, nemesis,
    guardian, artifact, home, the quest's lawful god...) are filled in
    from NetHack's own tables, exactly as the game would;
  * placeholders that change from game to game (your name, rank, gender,
    god, alignment) get a generic stand-in and are listed in "varies", so
    the editor can point them out;
  * printf-style codes are dropped.

speakable(entry) -> (text, varies, tokens)
  tokens: each placeholder in the line, with what it means and what it
  becomes here (for the editor's legend and tooltips)
"""
import os
import re

HERE = os.path.dirname(os.path.abspath(__file__))
NETHACK = os.path.normpath(os.path.join(HERE, "..", "..", "external", "nethack"))

# stand-ins for things that differ between games
GENERIC = {
    "p": "adventurer", "s": "friend", "S": "child", "G": "god",
    "d": "your god", "a": "", "A": "", "x": "see",
}
VARIES = {
    "p": "player name", "c": "role name (female form)", "r": "rank",
    "R": "rank", "s": "brother/sister", "S": "son/daughter",
    "G": "god/goddess", "a": "alignment", "A": "alignment", "d": "deity",
}

_roles = None


def _read(rel):
    with open(os.path.join(NETHACK, rel), encoding="latin-1") as f:
        return re.sub(r"/\*.*?\*/", "", f.read(), flags=re.S)  # drop comments


def _strings(s):
    return re.findall(r'"((?:[^"\\]|\\.)*)"', s)


def _load():
    """Per-role quest values, keyed by the quest file code ("Arc", ...)."""
    global _roles
    if _roles is not None:
        return _roles
    _roles = {}
    try:
        mons = {}
        for chunk in _read("include/monsters.h").split("MON(NAM")[1:]:
            names = _strings(chunk.split(")", 1)[0])
            if not names:
                continue
            name = names[-1] if chunk.startswith("S(") else names[0]
            # the entry's last argument is its PM_ suffix
            end = re.findall(r",\s*(\w+)\)\s*,?\s*(?:\n|$)", chunk)
            if not end:
                continue
            gender = "f" if "M2_FEMALE" in chunk else "m" if "M2_MALE" in chunk else "n"
            mons["PM_" + end[-1]] = {"name": name, "pname": "M2_PNAME" in chunk, "gender": gender}
        arts = {}
        for chunk in _read("include/artilist.h").split('\n    A("')[1:]:
            end = re.search(r"\d+L,\s*\w+,\s*(\w+)\)", chunk)  # cost, colour, id
            if end:
                arts["ART_" + end.group(1)] = chunk.split('"', 1)[0]
        src = _read("src/role.c")
        body = src[src.index("const struct Role roles"):]
        body = body[:body.index("\n};")]
        for chunk in re.split(r"\n    \{ (?=\{ )", body)[1:]:
            strs = _strings(chunk)
            # name.m, name.f(or 0), 9 ranks (m, f/0), 3 gods, filecode, home, intermediate
            names = re.findall(r'\{\s*"([^"]+)",\s*(?:"([^"]+)"|0)\s*\}', chunk)
            role_m, role_f = names[0]
            ranks = [n[0] for n in names[1:10]]
            rest = chunk[chunk.index("} },") + 4:]
            # 3 gods (0 for priests: they serve their alignment's god),
            # file code, home base, intermediate target
            toks = [a if a else None for a, _ in
                    re.findall(r'"((?:[^"\\]|\\.)*)"|\b(0)\b', rest.split("PM_")[0])]
            gods = [g or "" for g in toks[0:3]]
            code, home, inter = toks[3:6]
            pms = re.findall(r"\b(PM_\w+|NON_PM)\b", rest)
            # role PM, female PM, leader, guardian, nemesis, enemy1, enemy2
            leader, guard, nemesis = pms[2], pms[3], pms[4]
            art = re.search(r"\b(ART_\w+)\b", rest).group(1)
            _roles[code] = {
                "role": role_m, "role_f": role_f or "", "rank": ranks[(14 + 2) // 4],
                "gods": [g for g in gods], "home": home, "intermed": inter,
                "leader": mons.get(leader), "guardian": mons.get(guard),
                "nemesis": mons.get(nemesis), "artifact": arts.get(art, "the artifact"),
            }
    except (OSError, ValueError, IndexError, AttributeError):
        pass
    return _roles


def _the(name):
    if name.lower().startswith("the "):
        return "the " + name[4:]
    return "the " + name


def _mon(m):
    if not m:
        return ""
    return m["name"] if m["pname"] else "the " + m["name"]


def _an(s):
    if s.lower().startswith("the ") or not s:
        return s
    return ("an " if s[:1].lower() in "aeiou" else "a ") + s


def _plural(s):
    if s.endswith(("s", "x", "ch", "sh")):
        return s + "es"
    if s.endswith("y") and s[-2:-1] not in "aeiou":
        return s[:-1] + "ies"
    return s + "s"


PRONOUNS = {"m": ("he", "him", "his"), "f": ("she", "her", "her"), "n": ("it", "it", "its")}

# ---------------------------------------------------------------- legend
# quest text codes (NetHack's questpgr.c)
QUEST_CODES = {
    "p": "your character's name",
    "c": "your role, e.g. Valkyrie (Priestess, Cavewoman when female)",
    "r": "your current rank title",
    "R": "the rank title needed to start the quest (level 14)",
    "s": "brother or sister (your gender)",
    "S": "son or daughter (your gender)",
    "l": "the quest leader",
    "n": "the quest nemesis",
    "g": "the leader's guards",
    "o": "the quest artifact",
    "O": "the quest artifact, short name (without \"of ...\")",
    "i": "where the nemesis waits (the quest's goal level)",
    "H": "the quest home base",
    "d": "your god",
    "D": "your role's lawful god",
    "G": "god or goddess (whichever your god is)",
    "a": "your starting alignment (lawful, neutral, chaotic)",
    "A": "your current alignment",
    "C": "the word \"chaotic\"",
    "N": "the word \"neutral\"",
    "L": "the word \"lawful\"",
    "x": "\"see\" (\"sense\" while blind)",
    "Z": "the main dungeon's name (The Dungeons of Doom)",
}
# a letter right after the code changes it
QUEST_MODS = {
    "A": "with \"A\"/\"An\" in front",
    "a": "with \"a\"/\"an\" in front",
    "C": "capitalised",
    "P": "plural, capitalised",
    "p": "plural",
    "S": "possessive ('s), capitalised",
    "s": "possessive ('s)",
    "t": "without a leading \"the\"",
    "h": "as he/she/it", "H": "as He/She/It",
    "i": "as him/her/it", "I": "as Him/Her/It",
    "j": "as his/her/its", "J": "as His/Her/Its",
}
PRONOUN_CODES = "dlno"  # h/H/i/I/j/J only work after these
# stand-ins in the common quest text (shared by every role)
COMMON_GENERIC = {
    "l": "your leader", "n": "your nemesis", "g": "guard", "o": "the artifact",
    "O": "the artifact", "i": "the nemesis's lair", "H": "your home", "D": "god",
    "c": "adventurer", "r": "adventurer", "R": "adventurer",
}
# printf-style codes in ordinary game messages
PRINTF_CODES = {
    "s": "words the game fills in: a name, an item, a monster...",
    "d": "a number", "i": "a number", "u": "a number", "ld": "a number", "lu": "a number",
    "c": "a single letter or symbol",
    "f": "a number with decimals", "g": "a number with decimals",
    "x": "a number (hexadecimal)", "X": "a number (hexadecimal)",
}


def legend():
    """Everything the editor's placeholder legend shows."""
    return {"quest": QUEST_CODES, "quest_mods": QUEST_MODS, "pronoun_codes": PRONOUN_CODES,
            "printf": PRINTF_CODES, "quest_varies": "".join(VARIES),
            "marks": [[label, meaning] for _, label, meaning, _ in MARKS] + [list(n) for n in OTHER_NOTES]}


def _quest(text, role):
    """Fill quest placeholders as NetHack would. role is None for the common
    quest text (shared by all roles): role-specific parts are left out."""
    varies = []
    tokens = []
    god_gender = "n"

    def arg(c):
        if role is None:
            # common quest text: the same for every role, so generic words
            if c in COMMON_GENERIC:
                varies.append("role-specific names")
                return COMMON_GENERIC[c]
        if c in VARIES and not (c == "c" and role and not role.get("role_f")):
            varies.append(VARIES[c])
        if c == "p":
            return GENERIC["p"]
        if c == "c":
            return role["role"]
        if c in "rR":
            return role["rank"]
        if c == "l":
            return _mon(role["leader"])
        if c == "n":
            return _mon(role["nemesis"])
        if c == "g":
            return (role["guardian"] or {}).get("name", "")
        if c in "oO":
            s = _the(role["artifact"])
            return s.split(" of ")[0] if c == "O" else s
        if c == "i":
            return role["intermed"]
        if c == "H":
            return role["home"]
        if c == "D":
            if not role["gods"][0]:
                varies.append("deity")
                return "the lawful god"
            return role["gods"][0].lstrip("_")
        if c in "CNL":
            return {"C": "chaotic", "N": "neutral", "L": "lawful"}[c]
        if c == "Z":
            return "The Dungeons of Doom"
        return GENERIC.get(c, "")

    out = []
    i = 0
    while i < len(text):
        ch = text[i]
        if ch != "%" or i + 1 >= len(text):
            out.append(ch)
            i += 1
            continue
        start = i
        c = text[i + 1]
        i += 2
        if c == "%":
            out.append("%")
            continue
        n_varies = len(varies)
        s = arg(c)
        mod = text[i] if i < len(text) else ""
        used = ""
        if mod and mod in "Aa":
            s = _an(s)
            s = s[:1].upper() + s[1:] if mod == "A" else s
            used = mod
        elif mod == "C":
            s = s[:1].upper() + s[1:]
            used = mod
        elif mod and mod in "hHiIjJ" and c in PRONOUN_CODES:
            if role is None:
                s = ""
            else:
                who = {"l": role["leader"], "n": role["nemesis"]}.get(c)
                gender = (who or {}).get("gender", "n") if c in "ln" else god_gender
                if c == "o":
                    gender = "n"
                s = PRONOUNS[gender]["hij".index(mod.lower())]
                s = s[:1].upper() + s[1:] if mod.isupper() else s
            used = mod
        elif mod and mod in "Pp":
            s = _plural(s) if s else s
            s = s[:1].upper() + s[1:] if mod == "P" else s
            used = mod
        elif mod and mod in "Ss":
            s = s + ("'" if s.endswith("s") else "'s") if s else s
            s = s[:1].upper() + s[1:] if mod == "S" else s
            used = mod
        elif mod == "t":
            s = s[4:] if s.lower().startswith("the ") else s
            used = mod
        i += len(used)
        meaning = QUEST_CODES.get(c, "unknown code (left empty)")
        if used:
            meaning += ", " + QUEST_MODS[used]
        tokens.append({"text": text[start:i], "meaning": meaning, "value": s,
                       "varies": len(varies) > n_varies})
        out.append(s)
    return "".join(out), varies, tokens


PRINTF = re.compile(r"%[-+ #0-9.*]*(l|ll|h)?([sdciuxXfgeEp])")


def tidy(text):
    text = text.replace("\n\n", " ").replace("\n", " ").replace(" ", "\n\n")
    text = re.sub(r"[ \t]+", " ", text)
    text = re.sub(r" +([,.;:!?])", r"\1", text)
    text = re.sub(r"[,;:]+([.!?])", r"\1", text)      # "the amulet,!" -> "the amulet!"
    text = re.sub(r'(^|\n)\s*[,.;:!?]+\s*', r"\1", text)  # punctuation left at a start
    return text.strip()


def has_words(text):
    """False when nothing speakable is left (e.g. a line that was only placeholders)."""
    return bool(re.search(r"[^\W\d_]", text))


# ---------------------------------------------------------------- other markings
# Things in the text that aren't placeholders but need explaining, as
# (pattern, label, meaning, spoken replacement or None to keep as is).
MARKS = [
    (re.compile(r"^\[cookie\] "), "[cookie]",
     "at the start of a rumor: it only comes out of fortune cookies. NetHack removes the tag, "
     "so it's never shown or spoken.", ""),
    (re.compile(r"(?m)^#.*(?:\n|$)"), "# note",
     "a line starting with # in a book passage is the file's source note (edition, page...). "
     "NetHack never shows it; it's left out of the spoken text.", ""),
    (re.compile(r"\[\.\.\.[^\]]*\]"), "[...]",
     "words cut from the quoted book passage. Shown as is; spoken as a pause.", "…"),
    (re.compile(r"\[[^\]\n]+, by [^\]\n]+\]"), "[Book, by Author]",
     "the book a passage is quoted from, shown under it in play. Left out of the spoken text "
     "(add it to the Spoken text if you want it read).", ""),
    (re.compile(r"`([^`'\n]*)'"), "`word'",
     "old typewriter-style quotation marks: the same as 'word'. Spoken normally.", r"'\1'"),
    (re.compile(r"AM\$"), "AM$",
     "Ankh-Morpork dollars (Discworld money).", None),
]
OTHER_NOTES = [
    ("ALL CAPITALS", "in the \"Death Quotes\" book passages, Death is talking (in Terry Pratchett's books "
     "Death speaks in capitals). The spoken text is written in normal case so the voice doesn't "
     "shout or spell it out; give these lines a deep, calm voice."),
    ("% alone", "a % that isn't followed by a code letter (10%, %&#@#&) is just a percent sign or a "
     "censored swear word, not a placeholder."),
    ("^? and ^.", "engravings of odd keyboard symbols (an old programmers' joke); there's nothing to say."),
    ("Line breaks", "shown as written. The spoken text joins the lines; a blank line becomes a paragraph pause."),
    ("TEST:{ ... }", "developer and settings messages (also 'msg_window' ...) only appear when testing or when "
     "an option is set wrong. They don't need voicing."),
]


def _marks(text):
    """Markings found in text: tokens for the editor, and the speakable text."""
    tokens = []
    for pat, label, meaning, _ in MARKS:
        for m in pat.finditer(text):
            tokens.append({"pos": m.start(), "text": m.group(0).rstrip("\n"), "value": "",
                           "meaning": meaning, "varies": False, "mark": label})
    spoken = text
    for pat, _, _, repl in MARKS:
        if repl is not None:
            spoken = pat.sub(repl, spoken)
    return tokens, spoken


def _caps_to_sentence(text):
    """DEATH'S LINES IN CAPITALS -> Death's lines in normal case."""
    def para(p):
        letters = [c for c in p if c.isalpha()]
        if len(letters) < 8 or any(c.islower() for c in letters):
            return p
        p = p.lower()
        p = re.sub(r"(^|[.!?]\s+|\n\s*)([a-z])", lambda m: m.group(1) + m.group(2).upper(), p)
        return re.sub(r"\bi\b", "I", p)
    return "\n\n".join(para(p) for p in text.split("\n\n"))


def speakable(entry):
    """Default text to send to the voice generator for a dialogue entry,
    what changes from game to game, and each placeholder or marking explained."""
    text = entry.get("text", "")
    varies, tokens = [], []
    q = entry.get("quest")
    mark_tokens, text = _marks(text)
    if q and "%" in text:
        role = _load().get(q.get("section"))
        text, varies, tokens = _quest(text, role)
    elif "%" in text and entry.get("category") not in ("written", "oracle"):
        # (book passages, rumors, epitaphs and the Oracle are shown word for word)
        for m in PRINTF.finditer(text):
            conv = (m.group(1) or "") + m.group(2)
            tokens.append({"text": m.group(0), "value": "",
                           "meaning": PRINTF_CODES.get(conv, PRINTF_CODES.get(m.group(2), "something the game fills in")),
                           "varies": True})
        if tokens:
            varies.append("names or numbers")
        text = PRINTF.sub("", text).replace("%%", "%")
    # placeholders were found in the marked-up text: place them in the original
    original = entry.get("text", "")
    pos = 0
    for t in tokens:
        at = original.find(t["text"], pos)
        t["pos"] = at if at >= 0 else pos
        pos = t["pos"] + len(t["text"])
    tokens = sorted(tokens + mark_tokens, key=lambda t: t["pos"])
    for t in tokens:
        del t["pos"]
    return tidy(_caps_to_sentence(text)), sorted(set(varies)), tokens


if __name__ == "__main__":
    import json
    import sys
    cat = json.load(open(sys.argv[1], encoding="utf-8"))
    for e in cat["entries"]:
        if e.get("quest") and e["id"].startswith(sys.argv[2] if len(sys.argv) > 2 else "quest.Arc.assign"):
            print(e["id"], speakable(e))
