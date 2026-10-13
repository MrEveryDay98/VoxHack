"""Import a sound bank (folder of .wav/.ogg/.mp3 files) into the game.

Every file is converted to Ogg Vorbis (Luanti's sound format) with ffmpeg
and stored as mods/nhv_sounds/sounds/<prefix>_<name>.ogg. MIDI files can't
be played by the game and are skipped (listed at the end).

With --yhacsib, the bank is "You Hear A Clicking Sound - It Bites!" and its
message rules are translated into hook assignments in config.json (only
for hooks that have nothing assigned yet).

usage: python import_soundbank.py <bank dir> <nhv_sounds mod dir> <prefix> [--yhacsib]
"""
import json
import os
import re
import shutil
import subprocess
import sys

# YHACSIB file -> hooks it fits (from the bank's Config.txt message rules)
YHACSIB = {
    "air": ["hero_swing_miss_air"],
    "almost": ["missile_dodged"],
    "applause": ["applause"],
    "arrow": ["missile_hit", "trap_arrow_trap"],
    "beam": ["teleport", "trap_teleportation_trap"],
    "beartrap": ["trap_bear_trap"],
    "bison": ["monster_behind_boulder"],
    "blecch": ["eat_rotten"],
    "book": ["study_book"],
    "boulder": ["boulder_push"],
    "bubbs": ["bubble_rising"],
    "circus": ["skill_up", "skill_ready"],
    "coins": ["gold_gain"],
    "coinsfall": ["gold_loss"],
    "crack": ["door_crash_open", "kick_door_it_crashes_open", "kick_door_it_shatters", "crash_door"],
    "creak": ["door_open", "door_unlock_and_open"],
    "crumble": ["crumbling_sound", "stone_crumbling"],
    "dart": ["trap_dart_trap"],
    "dive": ["fall_into_water"],
    "door1": ["door_resists"],
    "door2": ["door_open"],
    "door3": ["door_close"],
    "draught": ["fountain_refresh"],
    "evil": ["death"],
    "explosion": ["explosion"],
    "faster": ["speed_fast"],
    "fills": ["kadoom_boulder_falls_in"],
    "firework": ["level_up"],
    "footsteps": ["guards_footsteps"],
    "growl": ["canine_growl"],
    "gurgling": ["gurgle"],
    "gush": ["gushing_sound"],
    "hallucinate": ["hallucination_start"],
    "helping": ["prayer_answered"],
    "hit1": ["hero_hits"],
    "hit2": ["monster_killed"],
    "howling": ["canine_howl"],
    "kaboom": ["kaboom", "kaablamm_of_mine", "trap_land_mine"],
    "lightning": ["bolt_of_lightning"],
    "lock": ["door_locked"],
    "magic1": ["spell_cast"],
    "metal": ["klunk"],
    "missile": ["missile_launch"],
    "moan": ["hunger_hungry", "hunger_weak"],
    "monkey": ["item_stolen"],
    "munch": ["eat_done"],
    "naiad": ["faint_splashing"],
    "ouch": ["hero_hurt"],
    "pulse": ["heart_beat", "hp_low"],
    "register": ["shop_buy"],
    "rockl": ["dig_hole"],
    "rocks": ["dig"],
    "scream1": ["monster_hits_you"],
    "secret1": ["secret_found"],
    "shatter": ["glass_shattering", "potion_crash_and_break"],
    "shopdoor": ["shop_enter"],
    "skrap": ["scratching"],
    "slams": ["lid_slams_open_falls_shut"],
    "slop": ["splash"],
    "stairs1": ["level_enter_down"],
    "stairs2": ["level_enter_up"],
    "swing": ["hero_misses", "monster_misses_you"],
    "thud": ["thud"],
    "vomit": ["vomit"],
    "wind": ["rushing_wind_noise"],
    "yak": ["eat_dog_food"],
    "yawn": ["fall_asleep", "trap_sleeping_gas_trap"],
    # music (only the .wav tracks can be played)
    "music_cantina": ["music_shop"],
    "music_dead": ["music_death"],
    "music_endgame": ["music_endgame"],
    "music_endingyiruma": ["music_victory"],
    "music_al": ["music_dungeon"],
    "music_df": ["music_gehennom"],
}

AUDIO = (".wav", ".ogg", ".mp3", ".flac")


def sound_name(prefix, fname):
    base = os.path.splitext(fname)[0].lower()
    base = re.sub(r"[^a-z0-9_]+", "_", base).strip("_")
    return "%s_%s" % (prefix, base), base


def main():
    bank, moddir, prefix = sys.argv[1:4]
    yhacsib = "--yhacsib" in sys.argv
    ffmpeg = shutil.which("ffmpeg")
    if not ffmpeg:
        sys.exit("ffmpeg not found on PATH")
    outdir = os.path.join(moddir, "sounds")
    os.makedirs(outdir, exist_ok=True)
    imported, skipped = {}, []
    for dirpath, _, files in os.walk(bank):
        for f in sorted(files):
            ext = os.path.splitext(f)[1].lower()
            if ext not in AUDIO:
                if ext in (".mid", ".midi"):
                    skipped.append(f)
                continue
            name, base = sound_name(prefix, f)
            dst = os.path.join(outdir, name + ".ogg")
            if not os.path.exists(dst):
                subprocess.run([ffmpeg, "-loglevel", "error", "-y", "-i",
                                os.path.join(dirpath, f), "-c:a", "libvorbis",
                                "-q:a", "5", dst], check=True)
            imported[base] = name

    cfg_path = os.path.join(moddir, "config.json")
    cfg = {"version": 1, "hooks": {}, "voices": {},
           "master": {"effects": 100, "music": 60, "voices": 100}}
    if os.path.exists(cfg_path):
        cfg = json.load(open(cfg_path, encoding="utf-8"))
    assigned = 0
    if yhacsib:
        for base, hooks in YHACSIB.items():
            if base not in imported:
                continue
            for hid in hooks:
                if hid not in cfg["hooks"]:
                    entry = {"sounds": [imported[base]], "volume": 100, "pitch_var": 0.05}
                    if hid.startswith("music_"):
                        entry = {"sounds": [imported[base]], "volume": 100, "loop": True}
                    cfg["hooks"][hid] = entry
                    assigned += 1
    json.dump(cfg, open(cfg_path, "w", encoding="utf-8"), indent=1)
    print("imported %d sounds, %d hook assignments" % (len(imported), assigned))
    if skipped:
        print("skipped (MIDI can't be played): " + ", ".join(skipped))


if __name__ == "__main__":
    main()
