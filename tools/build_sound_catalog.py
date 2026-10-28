"""Build the catalog of sound hooks (every event a sound can be attached to)
for the VoxHack Editor and the game.

Groups:
  nethack   NetHack's own sound effects (Soundeffect(se_*) in its code)
  events    hooks added to NetHack's code by VoxHack (NHV_HOOK)
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
    ("achievement_unlocked", "An achievement is unlocked"),
    ("artifact_obtained", "An artifact is got for the first time this game (its cutscene starts)"),
    ("ascension_offered", "The Amulet is offered on your own god's high altar: the choir as the ascension cutscene starts"),
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
    "god_gift": "A god's gift appears at your feet",
    "sacrifice_accepted": "A sacrifice is accepted (consumed in a flash, smoke or flame)",
    "sacrifice_ignored": "A sacrifice is ignored: too old (\"Nothing happens\")",
    "altar_converted": "A cross-aligned altar is converted to your god",
    "god_angry": "Your god is angry with you (a bad sacrifice, prayer...)", "water_gushes": "Water gushes from a fountain",
    "tin_opened": "The hero opens a tin", "lot_of_noise": "The hero makes a lot of noise",
    "delphi_welcome": "Welcomed to Delphi by the Oracle", "blinded_by_flash": "Blinded by a flash",
    "mimic_revealed": "Bumping into a mimic", "read_scroll": "The hero reads a scroll",
    "read_spellbook": "The hero reads a spellbook", "quaff_potion": "The hero drinks a potion",
    "ambient_bubbling": "A fountain on the level: bubbling water", "ambient_coins": "A fountain: water falling on coins",
    "ambient_naiad": "A fountain: the splashing of a naiad", "ambient_soda": "A fountain (hallucinating): a soda fountain",
    "ambient_sink_drip": "A sink on the level: a slow drip", "ambient_sink_gurgle": "A sink: a gurgling noise",
    "ambient_sink_dishes": "A sink (hallucinating): dishes being washed",
    "artifact_fire": "A fire artifact burns someone (Fire Brand: \"The fiery blade burns...\")",
    "artifact_cold": "A cold artifact freezes someone (Frost Brand: \"The ice-cold blade freezes...\")",
    "artifact_lightning": "A lightning artifact strikes someone (Mjollnir: \"Lightning strikes...\")",
    "artifact_missiles": "A magic missile artifact strikes someone (\"A hail of magic missiles strikes...\")",
    "lightning_flash": "A wand of lightning flashes: zapped at yourself, up or down, engraved with or broken (zapped ahead, it's a ray: ray_fire)",
    "camera_flash": "An expensive camera's flash goes off",
}


# NetHack's own sound effects (include/seffects.h): where each is heard
DESCRIBE_NETHACK = {
    "air_crackles": "A monster's spell fizzles: the air crackles around it",
    "alarm": "An alarm sounds: robbing a shop (the Keystone Kops come) or entering a vault's security area",
    "angry_drone": "A beehive on the level: an angry drone (also a bee buzzing angrily)",
    "angry_snakes": "Iron bars dissolved by acid hiss like angry snakes",
    "angry_voice": "A shopkeeper shouts at you for damaging the shop (\"Out of my way, scum!\")",
    "applause": "Killing a peaceful while hallucinating: the studio audience applauds",
    "avian_screak": "A pet bird (parrot, raven...) screaks when you hurt or abuse it",
    "bang_weapon_side": "Digging with a blade that isn't for digging: \"Bang! You hit with the broad side\"",
    "bars_clink": "Gold, silver or coins hit iron bars: \"Clink\"",
    "bars_clonk": "A weapon or other object hits iron bars: \"Clonk\"",
    "bars_flapp": "Something flimsy (a scroll, cloth...) hits iron bars: \"Flapp\"",
    "bars_whang": "A boulder or heavy iron ball hits iron bars: \"Whang\"",
    "bars_whap": "A harmless missile (a cream pie, an egg...) hits iron bars: \"Whap\"",
    "bees": "A beehive on the level (hallucinating): bees in your bonnet",
    "blast": "An explosion out of sight: \"You hear a blast\"",
    "board_squeak": "A monster steps on a squeaky board (seen, or heard near or far); its note plays too",
    "board_squeaks_loudly": "You step on a squeaky board; its note plays too",
    "boing": "A monster's wand of striking hits you but your magic resistance stops it: \"Boing!\"",
    "bolt_of_lightning": "A monster's spell calls down a bolt of lightning on you",
    "bone_rattle": "A skeleton rattles noisily at you (you freeze for a moment)",
    "boomerang_klonk": "A thrown boomerang comes back and hits you: \"Klonk!\"",
    "boulder_drop": "A boulder falls into a pit or hole and fills it",
    "bovine_bellow": "A cow-like monster bellows (angry)",
    "bovine_moo": "A cow-like monster moos",
    "bubble_rising": "Quaffing from a fountain: a large bubble rises and a water nymph appears",
    "bugle_playing_reveille": "A soldier plays a bugle to wake the barracks (reveille)",
    "buzz": "An insect monster buzzes (chatting, or angry)",
    "canine_bark": "A peaceful dog barks (#chat)",
    "canine_growl": "A hostile dog growls (#chat), or a pet dog turns on you",
    "canine_howl": "A dog-like monster howls (also a werewolf howling at the moon)",
    "canine_whine": "A pet dog whines (hungry, or kept from what it wants)",
    "canine_yelp": "A pet dog yelps when you hurt or abuse it",
    "canine_yip": "A well-fed pet dog yips (#chat)",
    "canine_yowl": "A dingo yowls (#chat; dingos don't bark)",
    "chain_shatters": "An explosion shatters an iron chain",
    "chains_rattling_gears_turning": "A drawbridge is raised: chains rattle and gears turn",
    "chant": "Turning undead (you chant an arcane formula), or an invisible choir chants",
    "chirp": "A bird-like monster chirps",
    "clanging_sound": "A hard helmet saves a head: falling rocks, an iron ball, a thrown object",
    "clank": "A monster grows too big to hold its shield: it falls with a clank",
    "clanking_pipe": "Quaffing from a sink: clanking from the pipes",
    "clash": "Digging with a pick-axe into iron bars or something too hard: \"Clash!\"",
    "cockatrice_hiss": "A cockatrice hisses at someone (turning them to stone)",
    "cough": "A monster breathes in something nasty (a breath attack, a gas cloud) and coughs",
    "courtly_conversation": "A throne room on the level: courtly conversation",
    "cracking_sound": "A monster grows and bursts out of its armor",
    "crackling": "An electric attack: the air crackles with electricity",
    "crackling_of_hellfire": "Using a stethoscope in Gehennom: the crackling of hellfire",
    "crash": "Something glass shatters where you can see it (a mirror, a potion, a crystal ball...)",
    "crash_door": "Kicking a wall reveals a secret door or passage: \"Crash!\"",
    "crash_something_broke": "Something glass shatters out of sight: \"You hear something shatter!\"",
    "crash_throne_destroyed": "Kicking a throne to pieces: \"CRASH! You destroy it.\"",
    "crash_through_floor": "A monster out of sight digs a hole and falls through the floor",
    "crashed_ceiling": "A cave-in: \"Crash! The ceiling collapses around you!\"",
    "crashing_boulder": "A boulder falls into a pit or hole under you: a CRASH beneath you",
    "crashing_rock": "Rock crashes: a cave-in around you, or a monster digging through rock",
    "crashing_sound": "A door is forced open out of sight (force bolt, striking): a crashing sound",
    "croc_bellow": "A crocodile bellows",
    "crumbling_sound": "A boulder or statue is smashed apart (force bolt, striking)",
    "crunching_sound": "A rust monster or rock mole eats metal out of sight: crunching",
    "crushing_sound": "A drawbridge's portcullis falls and crushes someone",
    "deafening_roar_atmospheric": "A magic trap: a deafening roar (you may be deafened)",
    "destroy_web": "A dragged iron ball tears through a web",
    "distant_thunder": "Killing a peaceful: the rumble of distant thunder (your god is displeased)",
    "divine_music": "Praying successfully: divine music",
    "door_crash_open": "A monster smashes down a door",
    "door_open": "A monster opens a door",
    "door_unlock_and_open": "A monster unlocks and opens a door",
    "drain_noises": "Dropping a ring down a sink: loud noises from the drain",
    "dry_throat_rattle": "A monster tries to spit venom but has none left: a dry rattle",
    "egg_cracking": "Eggs break inside a kicked box or chest",
    "egg_splatting": "Eggs splat when a kicked box or chest lands",
    "elephant_trumpet": "An elephant-like monster (mastodon, mumak) trumpets",
    "equine_neigh": "A horse-like monster neighs",
    "equine_whicker": "A horse-like monster whickers",
    "equine_whinny": "A horse-like monster whinnies",
    "explosion": "An explosion out of sight (a booby-trapped door blowing up, near or far)",
    "faint_chime": "Reading the Book of the Dead without the Bell of Opening: a faint chime",
    "faint_sloshing": "Two puddings merge out of sight: faint sloshing",
    "faint_splashing": "Using a stethoscope on water: faint splashing",
    "feline_meow": "A cat-like monster meows",
    "feline_mew": "A kitten mews",
    "feline_purr": "A happy cat-like monster purrs",
    "feline_yelp": "A pet cat yowls when you hurt or abuse it",
    "feline_yip": "A distressed pet cat whimpers",
    "feline_yowl": "A cat-like monster yowls (angry or hungry)",
    "furious_bubbling": "Quaffing from a fountain: it bubbles furiously (snakes or a demon come out)",
    "gear_turn": "Playing the passtune at a drawbridge: gears turn",
    "gears_turning_chains_rattling": "A drawbridge is lowered: gears turn and chains rattle",
    "glass_crashing": "Glass breaks inside a kicked box (a muffled crash)",
    "glass_shattering": "Glass shatters inside a kicked box or chest",
    "groan": "A monster groans",
    "groans_and_moans": "Arriving in the Valley of the Dead: groans and moans everywhere",
    "growl": "A dog-like monster growls",
    "grunt": "A monster grunts",
    "guards_footsteps": "A vault on the level: the footsteps of a guard on patrol",
    "gurgle": "A water monster gurgles",
    "gushing_sound": "Kicking a fountain or sink: a gushing sound",
    "heart_beat": "Using a stethoscope on yourself: your heartbeat",
    "hiss": "A snake or reptile hisses",
    "hollow_sound": "Using a stethoscope on a wall with a secret door: a hollow sound",
    "horn_being_played": "A monster plays a fire or frost horn (near or far)",
    "iron_ball_dragging_you": "Punished, going downstairs: \"The iron ball drags you downstairs!\"",
    "iron_ball_hits_you": "Falling down stairs or a hole while punished: the iron ball smacks into you",
    "item_tumble_downwards": "Objects tumble down a hole or trap door",
    "jabberwock_burble": "A jabberwock burbles",
    "kaablamm_of_mine": "A land mine goes off: \"KAABLAMM!!!\"",
    "kaboom": "A booby-trapped box or chest explodes when opened: \"KABOOM!!\"",
    "kaboom_boom_boom": "A storm on the Plane of Air: \"Kaboom!!! Boom!! Boom!!\"",
    "kaboom_door_explodes": "A booby-trapped door explodes: \"KABOOM!! You see a door explode.\"",
    "kadoom_boulder_falls_in": "Digging a hole under a boulder: \"KADOOM! The boulder falls in!\"",
    "kerplunk_boulder_gone": "Pushing a boulder into water out of sight: \"Kerplunk!\"",
    "kick_door_it_crashes_open": "Kicking a door: it crashes open",
    "kick_door_it_shatters": "Kicking a door: it shatters to pieces",
    "klick": "Locking a box or chest: \"Klick!\"",
    "klunk": "Unlocking a box or chest: \"Klunk!\"",
    "klunk_pipe": "Kicking a sink: \"Klunk! The pipes vibrate noisily.\"",
    "laughter": "A monster laughs (giggles, chuckles; also a cursing attack)",
    "lid_slams_open_falls_shut": "Kicking a box or chest: the lid slams open, then falls shut",
    "loud_click": "Stepping on an arrow trap: a loud click",
    "loud_crash": "A drawbridge is destroyed, or a rolling boulder hits another: a loud crash",
    "loud_pop": "Quaffing from a fountain: a large bubble rises and pops",
    "loud_splash": "A drawbridge's portcullis falls into the moat",
    "low_buzzing": "A beehive on the level: a low buzzing",
    "low_hum": "A magic trap: a low hum",
    "maniacal_laughter": "Reading a scroll of scare monster while confused: maniacal laughter",
    "masticating_sound": "A monster eats a corpse out of sight: a masticating sound",
    "mon_chugging_potion": "A monster drinks a potion out of sight: a chugging sound",
    "monster_behind_boulder": "Pushing a boulder against a monster on the other side",
    "mutter_imprecations": "Entering a shop with a pick-axe: the shopkeeper mutters imprecations",
    "mutter_incantation": "A shopkeeper repairs shop damage, muttering an incantation",
    "orc_grunt": "An orc grunts",
    "paranoid_confirmation": "A paranoid confirmation prompt: answer \"yes\" to be sure",
    "potion_crash_and_break": "A thrown potion crashes and breaks: \"Crash!\"",
    "ring_in_drain": "Dropping a ring down a sink: it bounces down the drainpipe",
    "ripping_sound": "A monster grows and its cloak or shirt tears apart",
    "roar": "A big cat or bear roars (also a bear caught in a trap or web)",
    "rumbling": "A rolling boulder trap goes off: rumbling, near or far",
    "rumbling_of_earth": "An earthquake (drum of earthquake): the whole level shakes",
    "rushing_wind_noise": "An unseen monster swoops at you: a rushing noise",
    "rustling_paper": "Flipping through a spellbook: the pages rustle",
    "sad_wailing": "Reading a scroll of scare monster: sad wailing (also a monster wailing)",
    "sceptor_pounding": "A throne room on the level: a sceptre pounded in judgment",
    "scratching": "A corpse comes back to life inside a box: scratching noises",
    "scream": "Someone screams (falling into a chasm, or a monster's blood-curdling shriek)",
    "screech": "A pet bird turns on you: it screeches",
    "sewer_song": "Quaffing from a sink: snatches of song from the sewers",
    "sharp_crack": "Rubbing a gem on a touchstone: \"A sharp crack shatters\" it",
    "shriek": "A shrieker shrieks (it draws monsters to you)",
    "shrill_whistle": "Blowing a whistle (also the vault guards' whistles when they turn angry)",
    "sinister_laughter": "Eating something that puts you to sleep: sinister laughter",
    "sizzling": "A boulder drops into lava out of sight: sizzling",
    "slurping_sound": "A monster eats objects out of sight (a gelatinous cube...): slurping",
    "smashing_and_crushing": "A drawbridge closes on someone: smashing and crushing",
    "snake_rattle": "A pet snake turns on you: it rattles",
    "snakes_hissing": "Quaffing from a fountain: a stream of water moccasins pours out, hissing",
    "snarl": "A dog-like monster snarls",
    "soft_click": "Stepping on a dart trap: a soft click",
    "soft_crackling": "Cold freezes water or lava for a moment: a soft crackling",
    "someone_bowling": "A rolling boulder trap goes off out of sight: someone bowling",
    "someone_searching": "A vault on the level: someone counting money or searching",
    "someone_summoning": "A monster's spell summons insects",
    "someone_yells": "A monster out of sight yells something: \"You hear someone yell\"",
    "splash": "Something falls into water: \"Splash!\"",
    "splat_egg": "A thrown egg hits a monster: \"Splat!\"",
    "splat_from_engulf": "You get regurgitated, or expelled \"with a squelch\", from an engulfer",
    "squeak_C": "A squeaky board's note: C (a generated note plays unless you give it a sound)",
    "squeak_D_flat": "A squeaky board's note: D flat (a generated note plays unless you give it a sound)",
    "squeak_D": "A squeaky board's note: D (a generated note plays unless you give it a sound)",
    "squeak_E_flat": "A squeaky board's note: E flat (a generated note plays unless you give it a sound)",
    "squeak_E": "A squeaky board's note: E (a generated note plays unless you give it a sound)",
    "squeak_F": "A squeaky board's note: F (a generated note plays unless you give it a sound)",
    "squeak_F_sharp": "A squeaky board's note: F sharp (a generated note plays unless you give it a sound)",
    "squeak_G": "A squeaky board's note: G (a generated note plays unless you give it a sound)",
    "squeak_G_sharp": "A squeaky board's note: G sharp (a generated note plays unless you give it a sound)",
    "squeak_A": "A squeaky board's note: A (a generated note plays unless you give it a sound)",
    "squeak_B_flat": "A squeaky board's note: B flat (a generated note plays unless you give it a sound)",
    "squeak_B": "A squeaky board's note: B (a generated note plays unless you give it a sound)",
    "squawk": "A raven or parrot squawks (\"Nevermore!\")",
    "squeak": "A rodent squeaks",
    "squeal": "A pet rodent squeals when you hurt or abuse it (or whines)",
    "squelch": "Sitting on a cream pie: \"Squelch!\"",
    "stone_breaking": "An explosion breaks a boulder or statue apart",
    "stone_crumbling": "A boulder or statue crumbles out of sight",
    "swoosh": "A door springs up in an empty doorway (wizard lock): a swoosh",
    "sword_blade_rings": "Applying a polearm at something hard: \"Shkinng!\"",
    "thud": "A monster grows too big and its armor falls off: a thud",
    "thump": "An earthquake (drum of earthquake) shakes something loose from the ceiling",
    "thunderclap": "Offering a fake Amulet of Yendor at the end: a thunderclap",
    "tumbler_click": "Playing a tune at a drawbridge: tumblers click",
    "typing_noise": "Using a stethoscope off the edge of the map: a faint typing noise",
    "wail": "A wailing pet (a ghost-like one) wails when you hurt or abuse it",
    "wailing_of_the_banshee": "Your hit points get very low: the wailing of the Banshee",
    "wall_of_force": "Breaking a wand of striking or force bolt: a wall of force smashes down",
    "yelp": "A pet yelps when you hurt or abuse it",
    "zap": "A monster zaps a wand (near or far)",
    "zap_then_explosion": "A monster zaps a wand that blows up: a zap and an explosion",
}


def main():
    root, out = sys.argv[1:3]
    hooks = []
    seffects = open(os.path.join(root, "include", "seffects.h"), encoding="latin-1").read()
    srcs = [open(os.path.join(root, "src", f), encoding="latin-1").read()
            for f in sorted(os.listdir(os.path.join(root, "src"))) if f.endswith(".c")]
    names = [n for n in re.findall(r'seffect\(([A-Za-z_0-9]+)\)', seffects)
             if n != "basename"]
    for name in dict.fromkeys(names):
        desc = DESCRIBE_NETHACK.get(name, name.replace("_", " "))
        # (one NetHack never plays: no Soundeffect(se_<name>) nor
        # NHV_HOOK("<name>") anywhere - give it a place in NetHack's code)
        played = re.compile(r'\bse_%s\b|NHV_HOOK\([^;]*"%s"' % (name, name))
        if not any(played.search(src) for src in srcs):
            desc += " [never played by NetHack]"
        hooks.append({"id": name, "group": "nethack", "desc": desc})
    # (an NHV_HOOK named as one of NetHack's own sounds is that sound)
    found = set(names)
    for fname in sorted(os.listdir(os.path.join(root, "src"))):
        if fname.endswith(".c"):
            src = open(os.path.join(root, "src", fname), encoding="latin-1").read()
            # NHV_HOOK("name") (or _AT / _MON), NHV_HOOK(cond ? "a" : "b") and lists of hook
            # names chosen in code (static const char *const ..._hook[] = {...})
            names = []
            for call in re.findall(r'NHV_HOOK(?:_AT|_MON)?\(([^;]*?)\)\s*[;,]', src):
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
