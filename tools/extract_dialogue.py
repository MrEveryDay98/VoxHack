"""Extract every line of dialogue, quest text and narration from NetHack
into a labelled catalog for voice acting.

Sources:
  quest      dat/quest.lua (dumped with tools/dump_quest.lua via luajit)
  spoken     verbalize(...) calls and quoted speech in src/*.c
  ambient    "You hear ..." lines in src/*.c
  level      des.message(...) in dat/*.lua (arrival narration)
  oracle     dat/oracles.txt
  written    rumors, epitaphs, engravings, tribute passages (text the hero
             reads; included so they can be voiced too)

Each entry gets a stable id (a hash of its category and text), so voice
recordings stay attached when the catalog is regenerated.
Placeholders like %s / %d (C) and %p / %d (quest) stand for names and
numbers filled in at runtime.

usage: python extract_dialogue.py <nethack root> <quest.json> <out.json>
"""
import hashlib
import json
import os
import re
import sys

SPEAKERS = {
    "shk.c": "Shopkeeper", "vault.c": "Vault guard", "priest.c": "Priest",
    "pray.c": "God", "wizard.c": "Wizard of Yendor", "minion.c": "Demon / angel",
    "mail.c": "Mail daemon", "quest.c": "Quest leader", "sounds.c": "Monster",
    "apply.c": "Shopkeeper", "dokick.c": "Shopkeeper", "mkobj.c": "Shopkeeper",
    "potion.c": "Djinni / ghost", "muse.c": "Monster", "mhitu.c": "Monster",
    "sit.c": "Throne voice", "nhlua.c": "Level", "monmove.c": "Monster",
    "fountain.c": "Water demon / nymph", "hack.c": "Shopkeeper",
    "uhitm.c": "Monster", "dig.c": "Shopkeeper", "do.c": "Voice",
    "read.c": "Voice", "artifact.c": "Talking artifact", "end.c": "Narrator",
}
# functions whose lines someone else says than their file's speaker
SPEAKER_BY_FUNCTION = {
    "watch_dig": "Minetown watch", "watchman_warn_fountain": "Minetown watch",
    "peacefuls_respond": "Minetown watch", "watch_on_duty": "Minetown watch",
}

C_STR = r'"(?:[^"\\\n]|\\.)*"'


def c_unescape(lits):
    out = []
    for lit in re.findall(C_STR, lits):
        s = lit[1:-1]
        s = (s.replace('\\"', '"').replace('\\n', '\n').replace('\\t', '\t')
             .replace("\\'", "'").replace('\\\\', '\\'))
        out.append(s)
    return "".join(out)


def make_id(prefix, text):
    return "%s.%s" % (prefix, hashlib.sha1(text.encode("utf-8")).hexdigest()[:10])


def function_at(src, pos):
    """name of the C function containing offset pos"""
    best = "?"
    for m in re.finditer(r'^([a-z_][a-z0-9_]*)\(', src[:pos], re.M):
        best = m.group(1)
    return best


def line_of(src, pos):
    return src.count("\n", 0, pos) + 1


def from_c(root, entries):
    srcdir = os.path.join(root, "src")
    for fname in sorted(os.listdir(srcdir)):
        if not fname.endswith(".c"):
            continue
        src = open(os.path.join(srcdir, fname), encoding="latin-1").read()
        speaker = SPEAKERS.get(fname, "Monster")
        seen = set()
        # verbalize("...") (and a monster's mon_yells(mon, "..."))
        for m in re.finditer(r'\b(?:verbalize\(|mon_yells\(\s*\w+\s*,)\s*((?:' + C_STR + r'\s*)+)', src):
            text = c_unescape(m.group(1))
            if not text.strip() or text in seen:
                continue
            seen.add(text)
            func = function_at(src, m.start())
            entries.append({
                "id": make_id("spoken", text), "category": "spoken",
                "speaker": SPEAKER_BY_FUNCTION.get(func, speaker), "context": func,
                "text": text, "source": "%s:%d" % (fname, line_of(src, m.start())),
            })
        # other quoted speech: pline("... says, \"...\"") and the like
        for m in re.finditer(r'\b(?:pline|pline_The|urgent_pline|pline_mon)\(\s*(?:mtmp,\s*)?((?:' + C_STR + r'\s*)+)', src):
            text = c_unescape(m.group(1))
            if '"' not in text or text in seen:
                continue
            seen.add(text)
            entries.append({
                "id": make_id("spoken", text), "category": "spoken",
                "speaker": speaker, "context": function_at(src, m.start()),
                "text": text, "source": "%s:%d" % (fname, line_of(src, m.start())),
            })
        # ambient narration: You_hear("...")
        for m in re.finditer(r'\bYou_hear\(\s*((?:' + C_STR + r'\s*)+)', src):
            text = "You hear " + c_unescape(m.group(1))
            if text in seen:
                continue
            seen.add(text)
            entries.append({
                "id": make_id("ambient", text), "category": "ambient",
                "speaker": "Narrator", "context": function_at(src, m.start()),
                "text": text, "source": "%s:%d" % (fname, line_of(src, m.start())),
            })


def from_quest(questjson, entries):
    q = json.load(open(questjson, encoding="utf-8"))
    for section in sorted(q):
        msgs = q[section]
        if not isinstance(msgs, dict) or section == "msg_fallbacks":
            continue
        for msgid in sorted(msgs):
            if section == "common" and msgid == "TEST_PATTERN":
                continue
            m = msgs[msgid]
            if isinstance(m, str):
                texts = [m]
            elif isinstance(m, list):
                texts = m
            else:
                texts = [m.get("text", "")]
            for n, text in enumerate(texts):
                if not text:
                    continue
                spoken = text.lstrip().startswith('"')
                key = "quest.%s.%s" % (section, msgid) + (".%d" % (n + 1) if len(texts) > 1 else "")
                entries.append({
                    "id": key, "category": "quest",
                    "speaker": ("Quest (%s)" % section) if spoken else "Narrator",
                    "context": "%s / %s" % (section, msgid),
                    "text": text, "source": "dat/quest.lua",
                    "quest": {"section": section, "msgid": msgid},
                })


def from_levels(root, entries):
    dat = os.path.join(root, "dat")
    for fname in sorted(os.listdir(dat)):
        if not fname.endswith(".lua") or fname == "quest.lua":
            continue
        src = open(os.path.join(dat, fname), encoding="latin-1").read()
        for m in re.finditer(r'des\.message\(\s*"((?:[^"\\]|\\.)*)"', src):
            text = m.group(1).replace('\\"', '"')
            entries.append({
                "id": make_id("level", fname + text), "category": "level",
                "speaker": "Narrator", "context": fname[:-4],
                "text": text, "source": "dat/%s" % fname,
            })


def split_file(path, sep="-----"):
    txt = open(path, encoding="latin-1").read()
    return [p.strip() for p in txt.split(sep) if p.strip()]


def from_text_files(root, entries):
    dat = os.path.join(root, "dat")
    for text in split_file(os.path.join(dat, "oracles.txt")):
        entries.append({"id": make_id("oracle", text), "category": "oracle",
                        "speaker": "The Oracle", "context": "major consultation",
                        "text": text, "source": "dat/oracles.txt"})
    for fname, ctx in (("rumors.tru", "true rumor"), ("rumors.fal", "false rumor"),
                       ("epitaph.txt", "epitaph"), ("engrave.txt", "engraving")):
        for line in open(os.path.join(dat, fname), encoding="latin-1"):
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            entries.append({"id": make_id("written", ctx + line), "category": "written",
                            "speaker": "Text", "context": ctx, "text": line,
                            "source": "dat/%s" % fname})
    # tribute: passages between %passage markers
    trib = open(os.path.join(dat, "tribute"), encoding="latin-1").read()
    book = ""
    for block in re.split(r'^%', trib, flags=re.M):
        head, _, body = block.partition("\n")
        if head.startswith("title"):
            book = head[len("title"):].strip()
        elif head.startswith("passage"):
            text = body.strip()
            if text:
                entries.append({"id": make_id("written", book + text), "category": "written",
                                "speaker": "Text", "context": "tribute: %s %s" % (book, head.strip()),
                                "text": text, "source": "dat/tribute"})


def main():
    root, questjson, out = sys.argv[1:4]
    entries = []
    from_quest(questjson, entries)
    from_c(root, entries)
    from_levels(root, entries)
    from_text_files(root, entries)
    # ids must be unique
    seen = {}
    for e in entries:
        if e["id"] in seen:
            seen[e["id"]] += 1
            e["id"] += "-%d" % seen[e["id"]]
        else:
            seen[e["id"]] = 1
    os.makedirs(os.path.dirname(out), exist_ok=True)
    json.dump({"entries": entries}, open(out, "w", encoding="utf-8"), indent=1, ensure_ascii=False)
    counts = {}
    for e in entries:
        counts[e["category"]] = counts.get(e["category"], 0) + 1
    print("%d lines:" % len(entries), ", ".join("%s %d" % kv for kv in sorted(counts.items())))


if __name__ == "__main__":
    main()
