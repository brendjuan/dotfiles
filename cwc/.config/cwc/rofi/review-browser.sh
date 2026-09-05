#!/usr/bin/env bash

REVIEW_DIR="$HOME/claude-reviews"
[[ -d "$REVIEW_DIR" ]] || { notify-send "review-browser" "No $REVIEW_DIR directory"; exit 1; }

if [ -f "$HOME/.cache/high-contrast-mode" ]; then
    THEME="$HOME/.config/cwc/rofi/highcontrast.rasi"
else
    THEME="$HOME/.config/cwc/rofi/glitchcore.rasi"
fi
ROFI_OPTS=(-theme "$THEME" -normal-window -steal-focus -i -markup-rows)

TEAL="#00ffb4"
RED="#ff0050"
AMBER="#ff5500"
GHOST="#00ffb470"

mapfile -t files < <(find "$REVIEW_DIR" -mindepth 2 -maxdepth 2 -name '*.md' -printf '%T@\t%p\n' | sort -rn | cut -f2)
[[ ${#files[@]} -eq 0 ]] && notify-send "review-browser" "No reviews in $REVIEW_DIR" && exit 0

rows=""
for f in "${files[@]}"; do
    base=$(basename "$f" .md)
    date=$(basename "$(dirname "$f")")

    case "$base" in
        review-swarm-*)      kind="swarm"; name="${base#review-swarm-}" ;;
        convention-review-*) kind="conv";  name="${base#convention-review-}" ;;
        code-review-*)       kind="code";  name="${base#code-review-}" ;;
        nasa-*)              kind="nasa";  name="${base#nasa-}" ;;
        *)                   kind="misc";  name="$base" ;;
    esac
    name=$(sed -E 's/-20[0-9]{6}(-[0-9]{4})?$//; s/-[0-9]{4}$//' <<<"$name")

    tally_line=$(grep -m1 -i 'severity tally' "$f" 2>/dev/null)
    if [[ $tally_line =~ ([0-9]+)\ critical,\ ([0-9]+)\ high,\ ([0-9]+)\ medium,\ ([0-9]+)\ low ]]; then
        c=${BASH_REMATCH[1]} h=${BASH_REMATCH[2]} m=${BASH_REMATCH[3]} l=${BASH_REMATCH[4]}
        tally=""
        (( c > 0 )) && tally+="${c}C "
        (( h > 0 )) && tally+="${h}H "
        (( m > 0 )) && tally+="${m}M "
        (( l > 0 )) && tally+="${l}L "
        if (( c > 0 || h > 0 )); then col="$RED"
        elif (( m > 0 ));           then col="$AMBER"
        else                             col="$TEAL"
        fi
        [[ -z "$tally" ]] && tally="clean " && col="$GHOST"
    else
        tally="?? " col="$GHOST"
    fi

    rows+=$(printf '<b>%s</b>  <span size="small" foreground="%s">%s · %s</span>  <span foreground="%s"><b>%s</b></span>' \
        "$name" "$GHOST" "$kind" "$date" "$col" "${tally% }")$'\n'
done

idx=$(printf '%s' "$rows" | rofi -dmenu -p "reviews" -format i "${ROFI_OPTS[@]}")
[[ -z "$idx" ]] && exit 0
file="${files[$idx]}"

action=$(printf '%s\n' "󰈈 Read" "󰨞 Open in VSCode" "󰅍 Copy path" | \
    rofi -dmenu -p "$(basename "$file" .md)" "${ROFI_OPTS[@]}")
case "$action" in
    "󰈈 Read")
        exec kitty --class float-term -o remember_window_size=no \
            -o initial_window_width=112c -o initial_window_height=44c \
            -o background='#020008' -o foreground='#b8ffe6' \
            -o background_opacity=0.96 -o window_padding_width=14 \
            -e env GLAMOUR_STYLE="$HOME/.config/cwc/rofi/glitchcore.glamour.json" \
            glow -p -w 104 "$file" ;;
    "󰨞 Open in VSCode")
        exec code "$file" ;;
    "󰅍 Copy path")
        printf '%s' "$file" | copyq write text/plain - && copyq select 0 ;;
esac
