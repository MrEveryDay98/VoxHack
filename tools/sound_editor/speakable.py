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

speakable(entry) -> (text, varies)
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


def _quest(text, role):
    varies = []
    god_gender = "n"

    def arg(c):
        if c in VARIES and not (c == "c" and not role.get("role_f")):
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
        c = text[i + 1]
        i += 2
        if c == "%":
            out.append("%")
            continue
        s = arg(c)
        mod = text[i] if i < len(text) else ""
        if mod in "Aa" and mod:
            s = _an(s)
            s = s[:1].upper() + s[1:] if mod == "A" else s
            i += 1
        elif mod == "C":
            s = s[:1].upper() + s[1:]
            i += 1
        elif mod and mod in "hHiIjJ" and c in "dlno":
            who = {"l": role["leader"], "n": role["nemesis"]}.get(c)
            gender = (who or {}).get("gender", "n") if c in "ln" else god_gender
            if c == "o":
                gender = "n"
            s = PRONOUNS[gender]["hij".index(mod.lower())]
            s = s[:1].upper() + s[1:] if mod.isupper() else s
            i += 1
        elif mod in "Pp" and mod:
            s = _plural(s)
            s = s[:1].upper() + s[1:] if mod == "P" else s
            i += 1
        elif mod in "Ss" and mod:
            s = s + ("'" if s.endswith("s") else "'s")
            s = s[:1].upper() + s[1:] if mod == "S" else s
            i += 1
        elif mod == "t":
            s = s[4:] if s.lower().startswith("the ") else s
            i += 1
        out.append(s)
    return "".join(out), varies


PRINTF = re.compile(r"%[-+ #0-9.*]*(?:l|ll|h)?[sdciuxXfgeEp]")


def tidy(text):
    text = text.replace("\n\n", " ").replace("\n", " ").replace(" ", "\n\n")
    text = re.sub(r"[ \t]+", " ", text)
    text = re.sub(r" +([,.;:!?])", r"\1", text)
    return text.strip()


def speakable(entry):
    """Default text to send to the voice generator for a dialogue entry."""
    text = entry.get("text", "")
    varies = []
    q = entry.get("quest")
    if q and "%" in text:
        roles = _load()
        role = roles.get(q.get("section"))
        if role:
            text, varies = _quest(text, role)
        else:
            # common quest text: the role-specific parts differ per game
            if re.search(r"%[a-zA-Z]", text):
                varies.append("role-specific names")
            text = re.sub(r"%[a-zA-Z][AaCPpSsthHiIjJ]?", "", text)
    elif "%" in text:
        if PRINTF.search(text):
            varies.append("names or numbers")
        text = PRINTF.sub("", text).replace("%%", "%")
    return tidy(text), sorted(set(varies))


if __name__ == "__main__":
    import json
    import sys
    cat = json.load(open(sys.argv[1], encoding="utf-8"))
    for e in cat["entries"]:
        if e.get("quest") and e["id"].startswith(sys.argv[2] if len(sys.argv) > 2 else "quest.Arc.assign"):
            print(e["id"], speakable(e))
