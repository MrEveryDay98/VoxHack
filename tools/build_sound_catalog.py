"""Build the catalog of sound hooks (every event a sound can be attached to)
for the sound editor and the game.

Groups:
  nethack   NetHack's own sound effects (Soundeffect(se_*) in its code)
  events    hooks added to NetHack's code by NetHack Voxel (NHV_HOOK)
  traps     one per trap type (when the hero sets it off)
  game      hooks raised by the 3D game itself (footsteps, missiles, ...)
  music     music for places and moments

usage: python build_sound_catalog.py <nethack root> <out hooks.json>
"""
import json
import os
import re
import sys

GAME_HOOKS = [
    ("footstep", "The hero takes a step (every ~1.5 blocks walked)"),
    ("hero_swing", "The hero swings at a monster"),
    ("hero_swing_miss_air", "The hero swings at nothing"),
    ("hero_hurt", "The hero loses hit points"),
    ("hero_heal", "The hero regains a good chunk of hit points"),
    ("hp_low", "Hit points drop below a third"),
    ("death", "The hero dies"),
    ("missile_launch", "A monster throws or shoots something"),
    ("missile_dodged", "A missile that reached you misses (\"Dodged!\")"),
    ("missile_hit", "A missile hits you"),
    ("missile_land", "A missile comes down on the floor or a wall"),
    ("boulder_push", "The hero pushes a boulder"),
    ("ray_fire", "A wand, spell or breath ray is fired"),
    ("ray_bounce", "A ray bounces off a wall"),
    ("ray_hit", "A ray hits a body"),
    ("container_open", "A chest, box or bag is opened"),
    ("container_move", "An item goes into or out of a container"),
    ("container_close", "The container panel is closed"),
    ("block_destroyed", "A door is broken, or rock or wall dug out"),
    ("climb_out", "The hero climbs out of a pit"),
    ("level_enter_down", "Arriving on a deeper level"),
    ("level_enter_up", "Arriving on a shallower level"),
    ("hunger_hungry", "The hero becomes Hungry"),
    ("hunger_weak", "The hero becomes Weak"),
    ("hunger_fainting", "The hero is Fainting"),
    ("gold_gain", "The hero's gold goes up"),
    ("gold_loss", "The hero's gold goes down"),
    ("item_pickup", "Something is added to the inventory"),
    ("item_drop", "Something leaves the inventory"),
    ("blind_start", "The hero is blinded"),
    ("blind_end", "The hero can see again"),
    ("hallucination_start", "The hero starts hallucinating"),
    ("hallucination_end", "The hero stops hallucinating"),
    ("speed_fast", "The hero becomes fast"),
    ("levitation_start", "The hero starts levitating"),
    ("levitation_end", "The hero stops levitating"),
    ("wheel_open", "The action wheel opens"),
    ("wheel_select", "An action is picked on the wheel"),
    ("dialog_open", "A question or menu appears"),
]

MUSIC = [
    ("music_title", "Character selection"),
    ("music_dungeon", "The Dungeons of Doom"),
    ("music_mines", "The Gnomish Mines"),
    ("music_minetown", "Minetown"),
    ("music_sokoban", "Sokoban"),
    ("music_shop", "Inside a shop"),
    ("music_temple", "Inside a temple"),
    ("music_oracle", "The Oracle's level"),
    ("music_bigroom", "The Big Room"),
    ("music_quest", "The Quest"),
    ("music_ludios", "Fort Ludios"),
    ("music_gehennom", "Gehennom"),
    ("music_vlad", "Vlad's Tower"),
    ("music_endgame", "The Elemental Planes"),
    ("music_astral", "The Astral Plane"),
    ("music_death", "After dying"),
    ("music_victory", "After ascending"),
]

DESCRIBE_EVENTS = {
    "hero_hits": "The hero hits a monster", "hero_misses": "The hero misses a monster",
    "monster_killed": "The hero kills a monster", "monster_hits_you": "A monster hits the hero",
    "monster_misses_you": "A monster misses the hero", "eat_done": "The hero finishes eating",
    "vomit": "The hero vomits", "shop_enter": "Entering a shop", "shop_buy": "Paying for something",
    "item_stolen": "A monster steals from the hero", "teleport": "The hero teleports",
    "fall_into_water": "The hero falls into water", "secret_found": "A secret door or passage is found",
    "dig": "Digging (every turn of it)", "dig_hole": "Digging through to a hole",
    "level_up": "The hero gains an experience level", "skill_up": "The hero advances a skill",
    "skill_ready": "A skill can be advanced", "pray": "The hero prays",
    "prayer_answered": "A god answers favourably", "spell_cast": "The hero casts a spell",
    "study_book": "The hero starts studying a spellbook", "fall_asleep": "The hero falls asleep",
    "sit": "The hero sits down", "door_close": "A door closes", "door_resists": "A door resists",
    "door_locked": "A door is found locked", "skill_ready ": "", "eat_dog_food": "Eating dog food",
    "eat_rotten": "Eating something rotten", "fountain_refresh": "A refreshing drink from a fountain",
    "door_opens": "The hero opens a door", "kick_door_whamm": "Kicking a door that holds (WHAMM!)",
    "lid_slams_open_falls_shut": "Kicking a box: the lid slams open, then shut",
    "whip_snap": "Cracking a bullwhip (Snap!)", "dig_too_hard": "Something is too hard to dig",
    "item_glows": "An item glows (blessed, enchanted...)", "item_glows_black": "An item glows black (cursed)",
    "punished": "Punished: a ball and chain", "magic_energy": "Shimmering light / magical energy restores you",
    "god_gift": "A god's gift appears at your feet", "water_gushes": "Water gushes from a fountain",
    "tin_opened": "The hero opens a tin", "lot_of_noise": "The hero makes a lot of noise",
    "delphi_welcome": "Welcomed to Delphi by the Oracle", "blinded_by_flash": "Blinded by a flash",
    "mimic_revealed": "Bumping into a mimic", "read_scroll": "The hero reads a scroll",
    "read_spellbook": "The hero reads a spellbook", "quaff_potion": "The hero drinks a potion",
    "ambient_bubbling": "A fountain on the level: bubbling water", "ambient_coins": "A fountain: water falling on coins",
    "ambient_naiad": "A fountain: the splashing of a naiad", "ambient_soda": "A fountain (hallucinating): a soda fountain",
    "ambient_sink_drip": "A sink on the level: a slow drip", "ambient_sink_gurgle": "A sink: a gurgling noise",
    "ambient_sink_dishes": "A sink (hallucinating): dishes being washed",
}


def main():
    root, out = sys.argv[1:3]
    hooks = []
    seffects = open(os.path.join(root, "include", "seffects.h"), encoding="latin-1").read()
    for name in re.findall(r'seffect\(([a-z_0-9]+)\)', seffects):
        if name == "basename":
            continue
        hooks.append({"id": name, "group": "nethack", "desc": name.replace("_", " ")})
    found = set()
    for fname in sorted(os.listdir(os.path.join(root, "src"))):
        if fname.endswith(".c"):
            src = open(os.path.join(root, "src", fname), encoding="latin-1").read()
            # NHV_HOOK("name"), NHV_HOOK(cond ? "a" : "b") and lists of hook
            # names chosen in code (static const char *const ..._hook[] = {...})
            names = []
            for call in re.findall(r'NHV_HOOK\(([^;]*?)\)\s*[;,]', src):
                names += re.findall(r'"([a-z_0-9]+)"', call)
            for body in re.findall(r'_hook\[\d*\]\s*=\s*\{([^}]*)\}', src):
                names += re.findall(r'"([a-z_0-9]+)"', body)
            for hid in names:
                if hid not in found:
                    found.add(hid)
                    hooks.append({"id": hid, "group": "events",
                                  "desc": DESCRIBE_EVENTS.get(hid, hid.replace("_", " ")),
                                  "source": fname})
    defsym = open(os.path.join(root, "include", "defsym.h"), encoding="latin-1").read()
    for m in re.finditer(r"PCHAR2?\(\s*\d+,\s*'\^',\s*S_\w+,\s*\"([^\"]+)\"", defsym):
        hid = "trap_" + m.group(1).replace(" ", "_").replace("-", "_")
        hooks.append({"id": hid, "group": "traps", "desc": m.group(1)})
    m = re.search(r"PCHAR2?\(\s*\d+,\s*'\"',\s*S_web,\s*\"([^\"]+)\"", defsym)
    if m:
        hooks.append({"id": "trap_web", "group": "traps", "desc": "web"})
    for hid, desc in GAME_HOOKS:
        hooks.append({"id": hid, "group": "game", "desc": desc})
    for hid, desc in MUSIC:
        hooks.append({"id": hid, "group": "music", "desc": desc})
    json.dump({"hooks": hooks}, open(out, "w", encoding="utf-8"), indent=1)
    counts = {}
    for h in hooks:
        counts[h["group"]] = counts.get(h["group"], 0) + 1
    print("%d hooks:" % len(hooks), ", ".join("%s %d" % kv for kv in counts.items()))


if __name__ == "__main__":
    main()
