#!/usr/bin/env python3
"""Desktop wallpaper generator - TOP SECRET FISH INTELLIGENCE EDITION

Generates a desktop wallpaper matching the swaylock/waybar cyberspace theme.
Requires: pip install Pillow
Usage: python3 scripts/gen_wallpaper.py [output_path]
"""

from PIL import Image, ImageDraw, ImageFont
import os
import random
import math
import sys

W, H = 1920, 1200
random.seed(77)  # reproducible chaos, different seed than lockscreen

REPO_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DEFAULT_OUTPUT = os.path.join(REPO_DIR, "cwc/.config/cwc/wallpaper.png")

# Load fonts
FONT_BOLD = os.path.expanduser("~/.local/share/fonts/NerdFonts/JetBrainsMonoNLNerdFont-Bold.ttf")
FONT_REG = os.path.expanduser("~/.local/share/fonts/NerdFonts/JetBrainsMonoNLNerdFont-Regular.ttf")

def font(size, bold=False):
    try:
        return ImageFont.truetype(FONT_BOLD if bold else FONT_REG, size)
    except:
        return ImageFont.load_default()

# === BASE IMAGE ===
img = Image.new("RGBA", (W, H), (2, 0, 8, 255))
draw = ImageDraw.Draw(img)

# === GRADIENT (dark blue-purple, slightly lighter center) ===
cx, cy = W // 2, H // 2
max_dist = math.sqrt(cx**2 + cy**2)
for y in range(H):
    base_r = int(4 + 12 * (1 - y/H))
    base_g = int(2 + 6 * (1 - y/H))
    base_b = int(14 + 30 * (1 - y/H))
    draw.line([(0, y), (W, y)], fill=(base_r, base_g, base_b, 255))

# === SUBTLE GRID (very faint, whole screen) ===
grid_layer = Image.new("RGBA", (W, H), (0, 0, 0, 0))
gd = ImageDraw.Draw(grid_layer)
# Vertical lines
for x in range(0, W, 120):
    alpha = 18 + random.randint(0, 8)
    gd.line([(x, 0), (x, H)], fill=(0, 255, 180, alpha), width=1)
# Horizontal lines
for y in range(0, H, 80):
    alpha = 14 + random.randint(0, 6)
    gd.line([(0, y), (W, y)], fill=(0, 255, 180, alpha), width=1)
img = Image.alpha_composite(img, grid_layer)

# === MATRIX RAIN (very subtle, background texture) ===
matrix_layer = Image.new("RGBA", (W, H), (0, 0, 0, 0))
md = ImageDraw.Draw(matrix_layer)
matrix_chars = "01アイウエオカキクケコ><))°彡"
tiny_font = font(9)
for _ in range(250):
    x = random.randint(0, W)
    y_start = random.randint(0, H)
    length = random.randint(2, 10)
    for j in range(length):
        char = random.choice(matrix_chars)
        alpha = random.randint(14, 38)
        y = y_start + j * 11
        if y < H:
            md.text((x, y), char, fill=(0, 255, 70, alpha), font=tiny_font)
img = Image.alpha_composite(img, matrix_layer)

# === GLITCH BARS (horizontal displacement artifacts) ===
glitch_layer = Image.new("RGBA", (W, H), (0, 0, 0, 0))
gld = ImageDraw.Draw(glitch_layer)
for _ in range(50):
    y = random.randint(0, H)
    h = random.randint(1, 3)
    x = random.randint(0, W - 100)
    w = random.randint(30, 600)
    color_choice = random.choice([
        (255, 0, 80, random.randint(15, 40)),
        (0, 255, 180, random.randint(10, 30)),
        (255, 0, 255, random.randint(8, 22)),
        (0, 255, 70, random.randint(8, 20)),
    ])
    gld.rectangle([(x, y), (x + w, y + h)], fill=color_choice)
img = Image.alpha_composite(img, glitch_layer)

# === SCANLINES ===
scan_layer = Image.new("RGBA", (W, H), (0, 0, 0, 0))
sd = ImageDraw.Draw(scan_layer)
for y in range(0, H, 3):
    sd.line([(0, y), (W, y)], fill=(0, 0, 0, 14))
img = Image.alpha_composite(img, scan_layer)

# === SUBTLE DATA BLOCKS (rectangular noise patches) ===
block_layer = Image.new("RGBA", (W, H), (0, 0, 0, 0))
bld = ImageDraw.Draw(block_layer)
for _ in range(20):
    x = random.randint(100, W - 200)
    y = random.randint(100, H - 200)
    w = random.randint(40, 180)
    h = random.randint(20, 80)
    color = random.choice([
        (0, 255, 180, random.randint(8, 20)),
        (0, 80, 60, random.randint(12, 28)),
        (255, 0, 80, random.randint(6, 16)),
    ])
    bld.rectangle([(x, y), (x + w, y + h)], fill=color)
img = Image.alpha_composite(img, block_layer)

# === GHOST TEXT (barely visible data streams scattered around) ===
text_layer = Image.new("RGBA", (W, H), (0, 0, 0, 0))
td = ImageDraw.Draw(text_layer)
ghost_font = font(10)
ghost_texts = [
    "FISH PROTOCOL ACTIVE", "SONAR PING", "DEPTH: 20000",
    "AES-FISH-256", "CLEARANCE: KRAKEN", "ENCRYPTED",
    "SECTOR DEEP-7", "><(((º>", ">°))))彡", "CLASSIFIED",
    "FIREWALL: CORAL REEF", "FISHNET v3.7", "SUBMERGED",
    "0xDEAD BEEF CAFE F15H", "SIGNAL LOST", "CODENAME BARRACUDA",
]
for _ in range(35):
    text = random.choice(ghost_texts)
    x = random.randint(50, W - 300)
    y = random.randint(50, H - 50)
    alpha = random.randint(18, 45)
    color = random.choice([
        (0, 255, 180, alpha),
        (0, 255, 100, alpha),
        (255, 0, 80, max(10, alpha - 8)),
    ])
    td.text((x, y), text, fill=color, font=ghost_font)
img = Image.alpha_composite(img, text_layer)

# === VIGNETTE ===
vignette = Image.new("RGBA", (W, H), (0, 0, 0, 0))
vd = ImageDraw.Draw(vignette)
for y in range(0, H, 2):
    for x in range(0, W, 4):
        dist = math.sqrt((x - cx)**2 + (y - cy)**2)
        alpha = int(min(80, max(0, (dist / max_dist) ** 2.2 * 120)))
        if alpha > 3:
            for dx in range(4):
                for dy in range(2):
                    vd.point((x + dx, y + dy), fill=(0, 0, 0, alpha))
img = Image.alpha_composite(img, vignette)

# === FINAL: flatten and save ===
final = Image.new("RGB", (W, H), (0, 0, 0))
final.paste(img, mask=img.split()[3])

output_path = sys.argv[1] if len(sys.argv) > 1 else DEFAULT_OUTPUT
final.save(output_path, "PNG")
print(f"Saved to {output_path}")
print(f"Size: {final.size}")
