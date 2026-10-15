"""Write game/nethackvoxel/mods/nhv_sounds/sounds/notes/: one short MIDI
file per note (the 12 notes of an octave) for each instrument NetHack plays
notes on, played with the game's SoundFont:

  * squeaky boards (each squeaks its own note): BOARD_PROGRAM
  * instruments (flutes, horns, harps, drums, bugles...): NetHack's
    instrument ids are General MIDI program numbers

Files are named nhv_note_<program>_<semitone>.mid (semitone 0 = C).

Usage: python -I tools/make_note_midis.py
"""
import os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "game", "nethackvoxel", "mods", "nhv_sounds", "sounds", "notes")

BOARD_PROGRAM = 80  # ocarina: a bright, squeaky whistle
# General MIDI program (1-based) -> MIDI note of its C (where it sounds best)
PROGRAMS = {
    43: 48,   # cello
    47: 72,   # orchestral harp (wooden / magic harp)
    53: 60,   # choir aahs
    57: 72,   # trumpet (bugle)
    58: 60,   # trombone
    61: 60,   # french horn (tooled / frost / fire horn)
    68: 48,   # baritone sax
    70: 60,   # english horn
    73: 84,   # piccolo
    74: 72,   # flute (wooden / magic flute)
    76: 72,   # pan flute
    77: 72,   # blown bottle
    79: 84,   # whistle
    80: 84,   # ocarina (squeaky boards)
    113: 84,  # tinkle bell (bell)
    116: 72,  # woodblock
    117: 48,  # taiko drum (leather drum, drum of earthquake)
    118: 48,  # melodic tom
    123: 60,  # seashore
}

DIVISION = 480    # ticks per beat; the default tempo is 120 bpm: 0.5 s a beat
NOTE_TICKS = 384  # 0.4 s
TAIL_TICKS = 336  # (time for the note to ring out)


def vlq(n):
    out = [n & 0x7F]
    n >>= 7
    while n:
        out.insert(0, (n & 0x7F) | 0x80)
        n >>= 7
    return bytes(out)


def note_file(program, note):
    track = (vlq(0) + bytes([0xC0, program - 1])
             + vlq(0) + bytes([0x90, note, 100])
             + vlq(NOTE_TICKS) + bytes([0x80, note, 0])
             + vlq(TAIL_TICKS) + bytes([0xFF, 0x2F, 0x00]))
    return (b"MThd" + (6).to_bytes(4, "big") + (0).to_bytes(2, "big") + (1).to_bytes(2, "big")
            + DIVISION.to_bytes(2, "big")
            + b"MTrk" + len(track).to_bytes(4, "big") + track)


def main():
    os.makedirs(OUT, exist_ok=True)
    count = 0
    for program, c in PROGRAMS.items():
        for semi in range(12):
            with open(os.path.join(OUT, "nhv_note_%d_%d.mid" % (program, semi)), "wb") as f:
                f.write(note_file(program, c + semi))
            count += 1
    print("%d note files -> %s" % (count, OUT))


if __name__ == "__main__":
    main()
