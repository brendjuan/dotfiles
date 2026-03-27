#!/usr/bin/env python3
"""SWAGLOCK 9000 v3.0 - TOP SECRET FISH INTELLIGENCE EDITION

Generates the swaylock lockscreen background image.
Requires: pip install Pillow
Usage: python3 scripts/gen_lockscreen.py [output_path]
"""

from PIL import Image, ImageDraw, ImageFont
import os
import random
import math
import sys

W, H = 1920, 1200
random.seed(42)  # reproducible chaos

REPO_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DEFAULT_OUTPUT = os.path.join(REPO_DIR, "swaylock/.config/swaylock/img/lockscreen.png")

# Load fonts - try NerdFont first, fall back to default
FONT_BOLD = os.path.expanduser("~/.local/share/fonts/NerdFonts/JetBrainsMonoNLNerdFont-Bold.ttf")
FONT_REG = os.path.expanduser("~/.local/share/fonts/NerdFonts/JetBrainsMonoNLNerdFont-Regular.ttf")

def font(size, bold=False):
    try:
        return ImageFont.truetype(FONT_BOLD if bold else FONT_REG, size)
    except:
        return ImageFont.load_default()

def rgba(r, g, b, a=255):
    return (r, g, b, a)

# === BASE IMAGE ===
img = Image.new("RGBA", (W, H), (2, 0, 8, 255))
draw = ImageDraw.Draw(img)

# === SUBTLE GRADIENT (dark blue-purple at top, darker at bottom) ===
for y in range(H):
    r = int(2 + 8 * (1 - y/H))
    g = int(0 + 3 * (1 - y/H))
    b = int(8 + 20 * (1 - y/H))
    draw.line([(0, y), (W, y)], fill=(r, g, b, 255))

# === CYBERSPACE GRID (bottom half, perspective) ===
grid_layer = Image.new("RGBA", (W, H), (0, 0, 0, 0))
gd = ImageDraw.Draw(grid_layer)

horizon_y = 580
# Vertical lines converging to center
for i in range(-30, 31):
    top_x = W // 2 + i * 3
    bot_x = W // 2 + i * 65
    alpha = max(8, 35 - abs(i))
    gd.line([(top_x, horizon_y), (bot_x, H)], fill=(0, 255, 180, alpha), width=1)

# Horizontal lines getting closer together near horizon
for i in range(20):
    t = i / 20.0
    y = int(horizon_y + (H - horizon_y) * (t ** 1.5))
    alpha = int(10 + 25 * t)
    gd.line([(0, y), (W, y)], fill=(0, 255, 180, alpha), width=1)

img = Image.alpha_composite(img, grid_layer)

# === MATRIX RAIN ===
matrix_layer = Image.new("RGBA", (W, H), (0, 0, 0, 0))
md = ImageDraw.Draw(matrix_layer)
matrix_chars = "01アイウエオカキクケコ><))°彡FISH"
tiny_font = font(10)
for _ in range(400):
    x = random.randint(0, W)
    y_start = random.randint(0, horizon_y - 50)
    length = random.randint(3, 15)
    for j in range(length):
        char = random.choice(matrix_chars)
        alpha = int(20 + 40 * (j / length))
        y = y_start + j * 12
        if y < horizon_y:
            md.text((x, y), char, fill=(0, 255, 70, alpha), font=tiny_font)

img = Image.alpha_composite(img, matrix_layer)

# === GLITCH BARS ===
glitch_layer = Image.new("RGBA", (W, H), (0, 0, 0, 0))
gld = ImageDraw.Draw(glitch_layer)
for _ in range(35):
    y = random.randint(0, H)
    h = random.randint(1, 5)
    x = random.randint(0, W - 100)
    w = random.randint(50, 500)
    color_choice = random.choice([
        (255, 0, 100, random.randint(15, 40)),
        (0, 255, 200, random.randint(10, 30)),
        (255, 0, 255, random.randint(10, 25)),
        (0, 255, 70, random.randint(8, 20)),
    ])
    gld.rectangle([(x, y), (x + w, y + h)], fill=color_choice)

img = Image.alpha_composite(img, glitch_layer)

# === SCANLINES ===
scan_layer = Image.new("RGBA", (W, H), (0, 0, 0, 0))
sd = ImageDraw.Draw(scan_layer)
for y in range(0, H, 3):
    sd.line([(0, y), (W, y)], fill=(0, 0, 0, 30))

img = Image.alpha_composite(img, scan_layer)

# === BORDER FRAMES ===
border_layer = Image.new("RGBA", (W, H), (0, 0, 0, 0))
bd = ImageDraw.Draw(border_layer)
bd.rectangle([(15, 15), (W-15, H-15)], outline=(255, 0, 80, 100), width=2)
bd.rectangle([(25, 25), (W-25, H-25)], outline=(255, 0, 80, 60), width=1)
bd.rectangle([(35, 35), (W-35, H-35)], outline=(0, 255, 150, 40), width=1)
# Corner brackets
for cx, cy, dx, dy in [(40, 40, 1, 1), (W-40, 40, -1, 1), (40, H-40, 1, -1), (W-40, H-40, -1, -1)]:
    bd.line([(cx, cy), (cx + 30*dx, cy)], fill=(0, 255, 200, 120), width=2)
    bd.line([(cx, cy), (cx, cy + 30*dy)], fill=(0, 255, 200, 120), width=2)

img = Image.alpha_composite(img, border_layer)

# === TEXT LAYERS ===
text_layer = Image.new("RGBA", (W, H), (0, 0, 0, 0))
td = ImageDraw.Draw(text_layer)

# TOP SECRET header with RGB split / glitch
ts_font = font(68, bold=True)
ts_text = "▓▓ T O P   S E C R E T ▓▓"
bbox = td.textbbox((0, 0), ts_text, font=ts_font)
tw = bbox[2] - bbox[0]
tx = (W - tw) // 2

# Red ghost (offset left-up)
td.text((tx - 4, 68), ts_text, fill=(255, 0, 60, 160), font=ts_font)
# Cyan ghost (offset right-down)
td.text((tx + 4, 72), ts_text, fill=(0, 255, 200, 140), font=ts_font)
# White main
td.text((tx, 70), ts_text, fill=(255, 255, 255, 230), font=ts_font)

# Classification banners
clf_font = font(22, bold=True)
td.text((50, 160), "█ CLASSIFICATION: ULTRA // COSMIC // FISH-EYES-ONLY █", fill=(255, 0, 80, 160), font=clf_font)
td.text((50, 192), "HANDLING: NOFORN / RESTRICTED / AQUATIC CLEARANCE LVL-7", fill=(255, 0, 80, 120), font=clf_font)

clf_font_sm = font(18)
td.text((W - 420, 160), "DOCUMENT ID: ████-██-████", fill=(255, 0, 80, 130), font=clf_font_sm)
td.text((W - 420, 184), "SERIAL: FI5H-0xDEAD-REEF", fill=(255, 0, 80, 100), font=clf_font_sm)

# Corner status box (top-left)
box_font = font(13)
# Render box lines individually so right ║ aligns perfectly
box_content = [
    "  CYBER FISHERIES INTELLIGENCE  ",
    "  COMMAND & CONTROL CENTER      ",
    "  SECTOR: DEEP-7 / ABYSSAL     ",
    "  CLEARANCE: KRAKEN             ",
    "  OPERATOR: REDACTED            ",
]
box_color = (255, 0, 255, 75)
bx, by = 50, 230
# Measure the width of the top border to set the box width
top_border = "╔══════════════════════════════════╗"
top_bbox = td.textbbox((bx, by), top_border, font=box_font)
box_right = top_bbox[2]
td.text((bx, by), top_border, fill=box_color, font=box_font)
# Measure ║ width
pipe_w = td.textbbox((0, 0), "║", font=box_font)[2]
for i, content in enumerate(box_content):
    row_y = by + (i + 1) * 16
    td.text((bx, row_y), "║", fill=box_color, font=box_font)
    td.text((bx + pipe_w, row_y), content, fill=box_color, font=box_font)
    td.text((box_right - pipe_w, row_y), "║", fill=box_color, font=box_font)
bot_border = "╚══════════════════════════════════╝"
td.text((bx, by + len(box_content) * 16 + 16), bot_border, fill=box_color, font=box_font)

# Top-right status indicators
status_font = font(14)
statuses = [
    ("[UPLINK: ACTIVE]", (0, 255, 200, 70)),
    ("[ENCRYPTION: AES-FISH-256]", (0, 255, 200, 60)),
    ("[SONAR: PINGING...]", (0, 255, 200, 55)),
    ("[DEPTH: 20,000 LEAGUES]", (0, 255, 200, 50)),
    ("[THREAT DETECTION: ONLINE]", (0, 255, 200, 45)),
    ("[ANTI-PHISHING: MAXIMUM]", (255, 200, 0, 50)),
]
for i, (text, color) in enumerate(statuses):
    bbox = td.textbbox((0, 0), text, font=status_font)
    tw = bbox[2] - bbox[0]
    td.text((W - tw - 50, 230 + i * 18), text, fill=color, font=status_font)

# === FISH ASCII ART (middle area) ===
fish_font = font(18)
fish_lines = [
    ("  ><(((º>  ><(((º>  ><(((º>  SECURE CHANNEL  ><(((º>  ><(((º>  ><(((º>", (0, 255, 200, 110)),
    ("       ><>   ><>   ><>  ENCRYPTED FISHNET PROTOCOL v3.7  ><>   ><>   ><>", (0, 255, 180, 80)),
    ("  >°))))彡  PHISHING PROTECTION: ACTIVE  >°))))彡    FIREWALL: CORAL REEF", (0, 255, 160, 65)),
]
for i, (text, color) in enumerate(fish_lines):
    td.text((60, 420 + i * 26), text, fill=color, font=fish_font)

# Right side operation info
op_font = font(16, bold=True)
ops = [
    ("▸ CODENAME: BARRACUDA", (0, 255, 200, 100)),
    ("▸ OPERATION: DEEP SWIM", (0, 255, 200, 85)),
    ("▸ STATUS: SUBMERGED", (0, 255, 200, 70)),
    ("▸ THREAT LEVEL: ANGLERFISH", (255, 80, 80, 90)),
    ("▸ SCHOOL SIZE: CLASSIFIED", (255, 0, 200, 70)),
]
for i, (text, color) in enumerate(ops):
    bbox = td.textbbox((0, 0), text, font=op_font)
    tw = bbox[2] - bbox[0]
    td.text((W - tw - 60, 420 + i * 22), text, fill=color, font=op_font)

# === BIG GHOST FISH (center, very subtle) ===
big_fish_font = font(14)
big_fish = [
    "                              ██                              ",
    "                            ██░░██                            ",
    "              ████████████████░░░░██                          ",
    "            ██░░░░░░░░░░░░░░██░░░░░░██                       ",
    "          ██░░░░░░░░░░░░░░░░░░██░░░░░░██                     ",
    "        ██░░░░░░░░░░░░░░██░░░░░░████████                     ",
    "      ██░░░░░░░░░░░░░░░░░░██░░░░░░██                         ",
    "    ██░░░░░░░░░░░░░░░░░░░░░░██████                           ",
    "      ██░░░░░░░░░░░░░░░░░░░░██                               ",
    "        ██░░░░░░░░░░░░░░░░██░░██                             ",
    "          ██░░░░░░░░░░░░██░░░░██                             ",
    "            ████████████████████                              ",
]
for i, line in enumerate(big_fish):
    bbox = td.textbbox((0, 0), line, font=big_fish_font)
    tw = bbox[2] - bbox[0]
    td.text(((W - tw) // 2, 500 + i * 16), line, fill=(0, 255, 180, 35), font=big_fish_font)

# === HEX DATA STREAMS ===
hex_font = font(11)
hex_lines = [
    ("0x4649 5348 2050 524F 544F 434F 4C20 494E 4954  // FISH PROTOCOL INIT", (0, 255, 100, 35)),
    ("0xDEAD BEEF CAFE F15H 0000 BADD C0DE 1337 FEED  // AQUATIC CIPHER KEY", (0, 255, 100, 28)),
    ("0xFF00 00FF 4242 C0D3 FACE B00C D15C F15H F15H  // ENCRYPTED STREAM", (0, 255, 100, 22)),
    ("0xBAAD F00D 0DAD DEAD C0D3 REEF DEEP BLUE AQUA  // SONAR SIGNATURE", (0, 255, 100, 18)),
]
for i, (text, color) in enumerate(hex_lines):
    td.text((50, 355 + i * 15), text, fill=color, font=hex_font)

# === ENTER CLEARANCE CODE (above center for password indicator) ===
prompt_font = font(38, bold=True)
prompt_text = "⟐ ENTER CLEARANCE CODE ⟐"
bbox = td.textbbox((0, 0), prompt_text, font=prompt_font)
tw = bbox[2] - bbox[0]
px = (W - tw) // 2
# RGB split on prompt too
td.text((px - 2, 718), prompt_text, fill=(255, 0, 100, 120), font=prompt_font)
td.text((px + 2, 722), prompt_text, fill=(0, 255, 200, 100), font=prompt_font)
td.text((px, 720), prompt_text, fill=(255, 255, 255, 200), font=prompt_font)

sub_font = font(15)
sub_text = "authentication required  ·  gill-print verified  ·  retinal scan pending"
bbox = td.textbbox((0, 0), sub_text, font=sub_font)
tw = bbox[2] - bbox[0]
td.text(((W - tw) // 2, 770), sub_text, fill=(0, 255, 180, 100), font=sub_font)

# === BOTTOM BANNERS ===
bot_font = font(16, bold=True)
td.text((50, H - 95), "UNAUTHORIZED ACCESS WILL BE REPORTED TO CYBER FISHERIES DIVISION", fill=(255, 0, 80, 90), font=bot_font)
td.text((50, H - 70), "▀▄▀▄▀▄ PROPERTY OF DEEPWATER INTELLIGENCE BUREAU ▀▄▀▄▀▄", fill=(255, 0, 80, 70), font=bot_font)

# Bottom-left syslog
log_font = font(11)
logs = [
    ("[SYSLOG] 2026-03-27T00:00:00Z FIREWALL: 9482 intrusion attempts blocked", (0, 255, 100, 32)),
    ("[SYSLOG] 2026-03-27T00:00:01Z FISHNET: all ports secured, sonar active", (0, 255, 100, 26)),
    ("[SYSLOG] 2026-03-27T00:00:02Z AUTH: biometric gill-scan required", (0, 255, 100, 22)),
    ("[SYSLOG] 2026-03-27T00:00:03Z SCHOOL: synchronized defense formation", (0, 255, 100, 18)),
]
for i, (text, color) in enumerate(logs):
    td.text((50, H - 160 + i * 15), text, fill=color, font=log_font)

# Bottom-right: small fish patrol
sm_font = font(12)
td.text((W - 500, H - 120), "><(((º>  ><(((º>  ><(((º>  ><(((º>", fill=(0, 255, 180, 40), font=sm_font)
td.text((W - 460, H - 105), ">°))))彡  >°))))彡  >°))))彡", fill=(0, 255, 160, 30), font=sm_font)
td.text((W - 380, H - 88), "~ ~ ~ PATROL ACTIVE ~ ~ ~", fill=(0, 255, 200, 35), font=sm_font)

img = Image.alpha_composite(img, text_layer)

# === VIGNETTE (darken edges) ===
vignette = Image.new("RGBA", (W, H), (0, 0, 0, 0))
vd = ImageDraw.Draw(vignette)
cx, cy = W // 2, H // 2
max_dist = math.sqrt(cx**2 + cy**2)
for y in range(0, H, 2):
    for x in range(0, W, 4):
        dist = math.sqrt((x - cx)**2 + (y - cy)**2)
        alpha = int(min(100, max(0, (dist / max_dist) ** 2 * 150)))
        if alpha > 5:
            vd.point((x, y), fill=(0, 0, 0, alpha))
            vd.point((x+1, y), fill=(0, 0, 0, alpha))
            vd.point((x+2, y), fill=(0, 0, 0, alpha))
            vd.point((x+3, y), fill=(0, 0, 0, alpha))
            vd.point((x, y+1), fill=(0, 0, 0, alpha))
            vd.point((x+1, y+1), fill=(0, 0, 0, alpha))
            vd.point((x+2, y+1), fill=(0, 0, 0, alpha))
            vd.point((x+3, y+1), fill=(0, 0, 0, alpha))

img = Image.alpha_composite(img, vignette)

# === FINAL: flatten and save ===
final = Image.new("RGB", (W, H), (0, 0, 0))
final.paste(img, mask=img.split()[3])

output_path = sys.argv[1] if len(sys.argv) > 1 else DEFAULT_OUTPUT
final.save(output_path, "PNG")
print(f"Saved to {output_path}")
print(f"Size: {final.size}")
