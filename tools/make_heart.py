"""The heart pets give off (mobs.lua's pet_hearts): nhv_heart.png, a 9x8
pixel heart - red, a dark red edge at its bottom, a light spot top left.

    py -3 tools/make_heart.py
"""
import os
from PIL import Image

OUT = os.path.join(os.path.dirname(__file__), '..', 'game', 'nethackvoxel', 'mods', 'nhv',
                   'textures', 'nhv_heart.png')
SHAPE = [
    '.RR...RR.',
    'RWRR.RRRR',
    'RRRRRRRRR',
    'RRRRRRRRR',
    'DRRRRRRRD',
    '.DRRRRRD.',
    '..DRRRD..',
    '...DDD...',
]
COLORS = {'R': (226, 32, 58, 255), 'D': (150, 16, 36, 255), 'W': (255, 190, 200, 255)}

img = Image.new('RGBA', (len(SHAPE[0]), len(SHAPE)), (0, 0, 0, 0))
for y, row in enumerate(SHAPE):
    for x, ch in enumerate(row):
        if ch in COLORS:
            img.putpixel((x, y), COLORS[ch])
img.save(OUT)
print(OUT)
