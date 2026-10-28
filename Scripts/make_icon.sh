#!/bin/sh
# Makes the app icon (Resources/AppIcon.icns) from the cube image: the blue cube on a
# black rounded square with a soft blue glow, like the widget's cards.
# Run it again after changing the cube image. Needs Python 3 with Pillow.
set -e
cd "$(dirname "$0")/.."

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

python3 - "$WORK/icon_1024.png" <<'PY'
import sys
from PIL import Image, ImageDraw, ImageFilter

S = 1024
# Apple's icon grid: a 824 px rounded square centered in the 1024 px canvas.
SQUARE, RADIUS = 824, 185
BORDER = (58, 58, 62, 255)     # thin dark gray outline, like the cards
GLOW = (110, 180, 245)         # the "bosse" blue
CUBE_WIDTH = 560               # width of the cube (solid part) in the icon

canvas = Image.new("RGBA", (S, S), (0, 0, 0, 0))
off = (S - SQUARE) // 2
box = (off, off, off + SQUARE, off + SQUARE)

# Soft shadow under the square.
shadow = Image.new("RGBA", (S, S), (0, 0, 0, 0))
ImageDraw.Draw(shadow).rounded_rectangle((box[0], box[1] + 12, box[2], box[3] + 12), RADIUS, fill=(0, 0, 0, 110))
canvas.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(18)))

# The black square with its outline.
square = Image.new("RGBA", (S, S), (0, 0, 0, 0))
ImageDraw.Draw(square).rounded_rectangle(box, RADIUS, fill=(0, 0, 0, 255), outline=BORDER, width=6)
canvas.alpha_composite(square)

# Soft blue glow behind the cube, kept inside the square.
glow = Image.new("RGBA", (S, S), (0, 0, 0, 0))
r = 300
ImageDraw.Draw(glow).ellipse((S/2 - r, S/2 - r, S/2 + r, S/2 + r), fill=GLOW + (95,))
glow = glow.filter(ImageFilter.GaussianBlur(90))
mask = Image.new("L", (S, S), 0)
ImageDraw.Draw(mask).rounded_rectangle(box, RADIUS, fill=255)
clipped = Image.new("RGBA", (S, S), (0, 0, 0, 0))
clipped.paste(glow, (0, 0), mask)
canvas.alpha_composite(clipped)

# The cube, centered on its solid part.
cube = Image.open("Assets/Travail/01_centre.png").convert("RGBA")
solid = cube.split()[-1].point(lambda v: 255 if v > 128 else 0).getbbox()
scale = CUBE_WIDTH / (solid[2] - solid[0])
cube = cube.resize((round(cube.width * scale), round(cube.height * scale)), Image.LANCZOS)
cx = (solid[0] + solid[2]) / 2 * scale
cy = (solid[1] + solid[3]) / 2 * scale
canvas.alpha_composite(cube, (round(S / 2 - cx), round(S / 2 - cy)))

canvas.save(sys.argv[1])
PY

# Every size macOS asks for, then one .icns file.
SET="$WORK/AppIcon.iconset"
mkdir "$SET"
for size in 16 32 128 256 512; do
    sips -z $size $size "$WORK/icon_1024.png" --out "$SET/icon_${size}x${size}.png" >/dev/null
    double=$((size * 2))
    sips -z $double $double "$WORK/icon_1024.png" --out "$SET/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$SET" -o Resources/AppIcon.icns
echo "✓ Resources/AppIcon.icns"
