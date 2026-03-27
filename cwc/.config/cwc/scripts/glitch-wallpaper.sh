#!/usr/bin/env bash
# glitch-wallpaper.sh — MAXIMUM CHAOS submarine defense glitchcore wallpaper
# theme: underwater classified ops + broken CRT + meme energy
# Dependencies: imagemagick (convert)

set -euo pipefail

OUT="${1:-$HOME/.config/cwc/wallpaper.png}"
W=1920
H=1200
FONT="Hack-Nerd-Font"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# --- base: deep ocean void gradient ---
convert -size "${W}x${H}" \
    "gradient:#05001a-#001a0f" \
    -sigmoidal-contrast 4x40% \
    "$tmp/canvas.png"

# --- underwater murk: layered blue-green fog patches ---
for _ in $(seq 1 8); do
    cx=$((RANDOM % W))
    cy=$((RANDOM % H))
    rx=$((150 + RANDOM % 400))
    ry=$((100 + RANDOM % 300))
    tint=$((RANDOM % 3))
    case $tint in
        0) color="rgba(0,40,30,0.15)" ;;
        1) color="rgba(0,20,50,0.12)" ;;
        2) color="rgba(10,0,30,0.10)" ;;
    esac
    convert "$tmp/canvas.png" \
        -fill "$color" -draw "ellipse $cx,$cy $rx,$ry 0,360" \
        "$tmp/canvas.png"
done

# ============================
# SONAR RINGS (defense HUD)
# ============================
# big sonar ping circles
for _ in $(seq 1 3); do
    cx=$((200 + RANDOM % (W - 400)))
    cy=$((200 + RANDOM % (H - 400)))
    for r in 60 120 180 240; do
        convert "$tmp/canvas.png" \
            -fill none -stroke "rgba(0,255,170,0.12)" -strokewidth 1 \
            -draw "circle $cx,$cy $((cx + r)),$cy" \
            "$tmp/canvas.png"
    done
    # sonar crosshair
    convert "$tmp/canvas.png" \
        -stroke "rgba(0,255,170,0.08)" -strokewidth 1 \
        -draw "line $((cx - 250)),$cy $((cx + 250)),$cy" \
        -draw "line $cx,$((cy - 250)) $cx,$((cy + 250))" \
        "$tmp/canvas.png"
done

# small sonar blips (contacts)
for _ in $(seq 1 12); do
    bx=$((RANDOM % W))
    by=$((RANDOM % H))
    convert "$tmp/canvas.png" \
        -fill "rgba(0,255,170,0.6)" -draw "circle $bx,$by $((bx + 2)),$by" \
        "$tmp/canvas.png"
done

# ============================
# HORIZONTAL GLITCH TEARS - CRANKED
# ============================
# magenta tears
for _ in $(seq 1 70); do
    y=$((RANDOM % H))
    thickness=$((1 + RANDOM % 3))
    x_start=$((RANDOM % (W / 3)))
    x_len=$((100 + RANDOM % (W - 200)))
    alpha=$((25 + RANDOM % 55))
    convert "$tmp/canvas.png" \
        -fill "rgba(255,0,238,0.${alpha})" \
        -draw "rectangle $x_start,$y $((x_start + x_len)),$((y + thickness))" \
        "$tmp/canvas.png"
done

# toxic green tears
for _ in $(seq 1 50); do
    y=$((RANDOM % H))
    thickness=$((1 + RANDOM % 3))
    x_start=$((RANDOM % (W / 3)))
    x_len=$((50 + RANDOM % (W / 2)))
    alpha=$((20 + RANDOM % 45))
    convert "$tmp/canvas.png" \
        -fill "rgba(0,255,170,0.${alpha})" \
        -draw "rectangle $x_start,$y $((x_start + x_len)),$((y + thickness))" \
        "$tmp/canvas.png"
done

# deep ocean blue tears
for _ in $(seq 1 30); do
    y=$((RANDOM % H))
    thickness=$((1 + RANDOM % 2))
    x_start=$((RANDOM % (W / 4)))
    x_len=$((80 + RANDOM % (W / 2)))
    alpha=$((15 + RANDOM % 35))
    convert "$tmp/canvas.png" \
        -fill "rgba(0,100,255,0.${alpha})" \
        -draw "rectangle $x_start,$y $((x_start + x_len)),$((y + thickness))" \
        "$tmp/canvas.png"
done

# FULL WIDTH glitch tears (the scuffed ones)
for _ in $(seq 1 10); do
    y=$((RANDOM % H))
    tint=$((RANDOM % 3))
    case $tint in
        0) color="rgba(255,0,238,0.85)" ;;
        1) color="rgba(0,255,170,0.75)" ;;
        2) color="rgba(0,100,255,0.65)" ;;
    esac
    convert "$tmp/canvas.png" \
        -fill "$color" \
        -draw "rectangle 0,$y ${W},$((y + 1))" \
        "$tmp/canvas.png"
done

# ============================
# VERTICAL DATA COLUMNS
# ============================
for _ in $(seq 1 25); do
    x=$((RANDOM % W))
    col_w=$((1 + RANDOM % 3))
    y_start=$((RANDOM % (H / 2)))
    y_len=$((80 + RANDOM % 500))
    alpha=$((12 + RANDOM % 35))
    tint=$((RANDOM % 2))
    if [ "$tint" -eq 0 ]; then
        color="rgba(0,255,170,0.${alpha})"
    else
        color="rgba(0,100,255,0.${alpha})"
    fi
    convert "$tmp/canvas.png" \
        -fill "$color" \
        -draw "rectangle $x,$y_start $((x + col_w)),$((y_start + y_len))" \
        "$tmp/canvas.png"
done

# ============================
# CORRUPTION BLOCKS
# ============================
for _ in $(seq 1 30); do
    bx=$((RANDOM % W))
    by=$((RANDOM % H))
    bw=$((15 + RANDOM % 150))
    bh=$((3 + RANDOM % 25))
    tint=$((RANDOM % 5))
    case $tint in
        0) color="rgba(255,0,238,0.12)" ;;
        1) color="rgba(0,255,170,0.10)" ;;
        2) color="rgba(255,0,60,0.11)" ;;
        3) color="rgba(50,255,10,0.08)" ;;
        4) color="rgba(0,80,255,0.09)" ;;
    esac
    convert "$tmp/canvas.png" \
        -fill "$color" \
        -draw "rectangle $bx,$by $((bx + bw)),$((by + bh))" \
        "$tmp/canvas.png"
done

# bright accent bars
for _ in $(seq 1 18); do
    y=$((RANDOM % H))
    x_start=$((RANDOM % (W / 2)))
    x_len=$((200 + RANDOM % 700))
    tint=$((RANDOM % 3))
    case $tint in
        0) color="rgba(255,0,238,0.75)" ;;
        1) color="rgba(0,255,170,0.65)" ;;
        2) color="rgba(0,100,255,0.55)" ;;
    esac
    convert "$tmp/canvas.png" \
        -fill "$color" \
        -draw "rectangle $x_start,$y $((x_start + x_len)),$((y + 1))" \
        "$tmp/canvas.png"
done

# red alert flickers
for _ in $(seq 1 10); do
    y=$((RANDOM % H))
    x_start=$((RANDOM % W))
    x_len=$((30 + RANDOM % 200))
    convert "$tmp/canvas.png" \
        -fill "rgba(255,0,60,0.6)" \
        -draw "rectangle $x_start,$y $((x_start + x_len)),$((y + 1))" \
        "$tmp/canvas.png"
done

# ============================
# DATA NOISE BLOCKS
# ============================
for _ in $(seq 1 18); do
    bx=$((50 + RANDOM % (W - 200)))
    by=$((50 + RANDOM % (H - 100)))
    bw=$((60 + RANDOM % 250))
    bh=$((20 + RANDOM % 80))
    convert "$tmp/canvas.png" \
        \( -size "${bw}x${bh}" xc:black \
           -attenuate 0.6 +noise Random \
           -channel G -evaluate multiply 0.5 \
           -channel RB -evaluate set 0 +channel \
           -blur 0x0.3 -alpha off \) \
        -geometry "+${bx}+${by}" -compose Screen -composite \
        "$tmp/canvas.png"
done

# ============================
# TEXT OVERLAYS — CLASSIFIED / DEFENSE / SUBMARINE / MEME
# ============================

# TOP SECRET stamps
declare -a stamps=(
    "TOP SECRET"
    "CLASSIFIED"
    "// EYES ONLY"
    "SCI // NOFORN"
    "[REDACTED]"
    "UMBRA"
    "CRYPTO"
)
for _ in $(seq 1 5); do
    tx=$((50 + RANDOM % (W - 400)))
    ty=$((50 + RANDOM % (H - 100)))
    idx=$((RANDOM % ${#stamps[@]}))
    sz=$((14 + RANDOM % 20))
    rot=$((RANDOM % 7 - 3))
    alpha=$((20 + RANDOM % 35))
    tint=$((RANDOM % 2))
    if [ "$tint" -eq 0 ]; then
        color="rgba(255,0,60,0.${alpha})"
    else
        color="rgba(255,0,238,0.${alpha})"
    fi
    convert "$tmp/canvas.png" \
        -font "$FONT" -pointsize "$sz" \
        -fill "$color" -stroke "rgba(255,0,60,0.10)" -strokewidth 1 \
        -gravity NorthWest -annotate "+${tx}+${ty}" "${stamps[$idx]}" \
        "$tmp/canvas.png" 2>/dev/null || true
done

# Defense HUD readouts
declare -a hud_lines=(
    "DEPTH: 847m  PRESSURE: 87.3 bar"
    "BEARING: 127.4°  SPEED: 12kts"
    "SONAR: ACTIVE  CONTACTS: 3"
    "HULL INTEGRITY: 94%  O2: 78%"
    "TORPEDO TUBES: 1-4 LOADED"
    "CONN: AHEAD FULL  DIVE DIVE DIVE"
    "WARNING: CAVITATION DETECTED"
    "PASSIVE SONAR: BIOLOGICAL 40dB"
    "THREAT LEVEL: ████████░░ 80%"
    "REACTOR: NOMINAL  SCRAM: READY"
    "// unauthorized access will be prosecuted"
    "lat: 36.0544°N  lon: -75.0616°W"
    "PERISCOPE DEPTH  SCOPE 2 UP"
    "MASTER 1: SIERRA-CLASS  BRG 045"
)
for _ in $(seq 1 10); do
    tx=$((30 + RANDOM % (W - 500)))
    ty=$((30 + RANDOM % (H - 60)))
    idx=$((RANDOM % ${#hud_lines[@]}))
    sz=$((10 + RANDOM % 8))
    alpha=$((18 + RANDOM % 30))
    tint=$((RANDOM % 3))
    case $tint in
        0) color="rgba(0,255,170,0.${alpha})" ;;
        1) color="rgba(0,180,255,0.${alpha})" ;;
        2) color="rgba(255,0,238,0.${alpha})" ;;
    esac
    convert "$tmp/canvas.png" \
        -font "$FONT" -pointsize "$sz" \
        -fill "$color" -stroke none \
        -gravity NorthWest -annotate "+${tx}+${ty}" "${hud_lines[$idx]}" \
        "$tmp/canvas.png" 2>/dev/null || true
done

# Shark warnings + meme text
declare -a meme_lines=(
    "🦈 SHARK DETECTED 🦈"
    "oh god oh fuck its a megalodon"
    "SHARK WEEK NEVER ENDS DOWN HERE"
    "they dont know im a submarine"
    "skill issue (the shark)"
    ">> JAWS.exe has stopped responding"
    "submarine goes brrrrrrr"
    "404: surface not found"
    "this is fine. (underwater edition)"
    "left shark best shark"
    "[shark approaching from port side]"
    "ALERT: unauthorized fish detected"
    "root@submarine:~# ping shark"
    "the ocean is just spicy water"
    "chmod 777 /dev/torpedo"
)
for _ in $(seq 1 8); do
    tx=$((40 + RANDOM % (W - 500)))
    ty=$((40 + RANDOM % (H - 60)))
    idx=$((RANDOM % ${#meme_lines[@]}))
    sz=$((9 + RANDOM % 10))
    alpha=$((15 + RANDOM % 30))
    tint=$((RANDOM % 3))
    case $tint in
        0) color="rgba(0,255,170,0.${alpha})" ;;
        1) color="rgba(255,0,238,0.${alpha})" ;;
        2) color="rgba(0,200,255,0.${alpha})" ;;
    esac
    convert "$tmp/canvas.png" \
        -font "$FONT" -pointsize "$sz" \
        -fill "$color" -stroke none \
        -gravity NorthWest -annotate "+${tx}+${ty}" "${meme_lines[$idx]}" \
        "$tmp/canvas.png" 2>/dev/null || true
done

# Corner HUD elements
convert "$tmp/canvas.png" \
    -font "$FONT" -pointsize 11 \
    -fill "rgba(0,255,170,0.35)" -stroke none \
    -gravity NorthWest -annotate "+20+15" "USS GLITCHCORE  CVN-404" \
    -gravity NorthEast -annotate "+20+15" "$(date +'%Y-%m-%d %H:%M:%S') UTC" \
    -gravity SouthWest -annotate "+20+15" "DEPTH: 847m // CLASSIFICATION: TS//SCI//GLITCHCORE" \
    -gravity SouthEast -annotate "+20+15" "REACTOR: ONLINE  SHARKS: YES" \
    "$tmp/canvas.png" 2>/dev/null || true

# Big watermark stamp diagonally
convert "$tmp/canvas.png" \
    -font "$FONT" -pointsize 90 \
    -fill "rgba(255,0,60,0.06)" -stroke "rgba(255,0,60,0.03)" -strokewidth 2 \
    -gravity Center -annotate "-25+0" "TOP SECRET" \
    "$tmp/canvas.png" 2>/dev/null || true

# ============================
# SHARK ASCII (subtle, ghostly)
# ============================
shark='    /\___/\\
   / o   o \\
  (    \"    )
   \\  ---  /
    \\_____/
  ~~~~~~~~~~~'

sx=$((100 + RANDOM % (W - 400)))
sy=$((100 + RANDOM % (H - 300)))
convert "$tmp/canvas.png" \
    -font "$FONT" -pointsize 14 \
    -fill "rgba(0,255,170,0.18)" -stroke none \
    -gravity NorthWest -annotate "+${sx}+${sy}" "$shark" \
    "$tmp/canvas.png" 2>/dev/null || true

# Second shark, different position
sx=$((RANDOM % (W - 300)))
sy=$((RANDOM % (H - 300)))
convert "$tmp/canvas.png" \
    -font "$FONT" -pointsize 10 \
    -fill "rgba(0,100,255,0.15)" -stroke none \
    -gravity NorthWest -annotate "+${sx}+${sy}" "$shark" \
    "$tmp/canvas.png" 2>/dev/null || true

# ============================
# SUBMARINE ASCII
# ============================
sub='         __|__
    ____/     \____
   /    |  O  |    \\
  | === |_____|=== |
   \___/  |||  \___/
         / | \\
        /  |  \\'

sx=$((200 + RANDOM % (W - 500)))
sy=$((200 + RANDOM % (H - 400)))
convert "$tmp/canvas.png" \
    -font "$FONT" -pointsize 12 \
    -fill "rgba(0,255,170,0.14)" -stroke none \
    -gravity NorthWest -annotate "+${sx}+${sy}" "$sub" \
    "$tmp/canvas.png" 2>/dev/null || true

# ============================
# POST-PROCESSING
# ============================

# CRT scanlines (opaque)
convert -size "${W}x2" xc:white \
    -fill "gray85" -draw "rectangle 0,1 ${W},1" \
    -alpha off \
    -write mpr:scanline +delete \
    -size "${W}x${H}" tile:mpr:scanline \
    "$tmp/scanlines.png"

convert "$tmp/canvas.png" "$tmp/scanlines.png" \
    -compose Multiply -composite \
    "$tmp/scanned.png"

# noise grain
convert -size "${W}x${H}" xc:gray50 \
    -attenuate 0.07 +noise Gaussian \
    -colorspace Gray -alpha off \
    "$tmp/noise.png"

convert "$tmp/scanned.png" "$tmp/noise.png" \
    -compose Overlay -composite \
    "$tmp/noisy.png"

# gentle vignette
convert -size "${W}x${H}" \
    radial-gradient:white-black \
    -level 25%,100% -alpha off \
    -brightness-contrast 15x0 \
    "$tmp/vignette.png"

convert "$tmp/noisy.png" "$tmp/vignette.png" \
    -compose Multiply -composite \
    "$OUT"

# pre-generate inverted version for high contrast toggle
INVERTED="${OUT%.png}-inverted.png"
convert "$OUT" -negate "$INVERTED"

echo "glitched wallpaper written to $OUT"
echo "inverted wallpaper written to $INVERTED"
