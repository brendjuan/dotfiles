#!/usr/bin/env bash
# git-fetch every repo under ~/Workspace(s)/* — loud, verbose, glitchcore.
# meant to run inside a float-term kitty so you can watch the carnage.

SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
WS_DIR=$("$SCRIPT_DIR/find-workspace-dir.sh") || {
    echo "no ~/Workspace(s) directory found" >&2
    read -rsn1 -p "press any key to close..."
    exit 1
}

# palette (matches glitchcore: teal primary, red urgent, amber warn)
TEAL=$'\033[38;2;0;255;180m'
RED=$'\033[38;2;255;0;80m'
AMBER=$'\033[38;2;255;85;0m'
DIM=$'\033[38;2;0;160;110m'
BOLD=$'\033[1m'
RST=$'\033[0m'

printf '%s%s── FETCHING ALL THE THINGS in %s ──%s\n\n' "$BOLD" "$RED" "$WS_DIR" "$RST"

total=0 fetched=0 skipped=0 failed=0 pulled=0
start=$SECONDS

while IFS= read -r name; do
    repo="$WS_DIR/$name"
    git -C "$repo" rev-parse --git-dir >/dev/null 2>&1 || {
        printf '%s  ◌ %-28s not a git repo, skipping%s\n' "$DIM" "$name" "$RST"
        ((skipped++)); continue
    }
    ((total++))
    branch=$(git -C "$repo" branch --show-current 2>/dev/null)
    printf '%s%s▶ %-28s%s %s(%s)%s\n' "$BOLD" "$TEAL" "$name" "$RST" "$DIM" "${branch:-detached}" "$RST"

    if git -C "$repo" fetch --all --prune --verbose 2>&1 | sed 's/^/    /'; then
        ((fetched++))
    else
        printf '%s    ✖ fetch failed for %s%s\n' "$RED" "$name" "$RST"
        ((failed++))
    fi

    # try a fast-forward pull, but only when it's safe to do so:
    #   - on an actual branch (not detached)
    #   - that branch tracks an upstream
    #   - the working tree is clean (no uncommitted local changes)
    # --ff-only guarantees we never merge or clobber diverged local commits.
    if [[ -z "$branch" ]]; then
        printf '%s    ⊘ detached HEAD, skipping pull%s\n' "$DIM" "$RST"
    elif ! git -C "$repo" rev-parse --abbrev-ref --symbolic-full-name '@{u}' >/dev/null 2>&1; then
        printf '%s    ⊘ no upstream, skipping pull%s\n' "$DIM" "$RST"
    elif [[ -n "$(git -C "$repo" status --porcelain 2>/dev/null)" ]]; then
        printf '%s    ⊘ local changes present, skipping pull%s\n' "$AMBER" "$RST"
    elif git -C "$repo" pull --ff-only --verbose 2>&1 | sed 's/^/    /'; then
        ((pulled++))
    else
        printf '%s    ✖ pull failed (diverged?) for %s%s\n' "$RED" "$name" "$RST"
    fi
    echo
done < <(find "$WS_DIR" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | sort)

elapsed=$((SECONDS - start))
printf '%s%s── done: %d fetched, %d pulled, %d failed, %d skipped — %ds ──%s\n' \
    "$BOLD" "$RED" "$fetched" "$pulled" "$failed" "$skipped" "$elapsed" "$RST"

read -rsn1 -p $'\033[2mpress any key to close...\033[0m'
