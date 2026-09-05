#!/usr/bin/env bash

SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
WS_DIR=$("$SCRIPT_DIR/find-workspace-dir.sh") || {
    echo "no ~/Workspace(s) directory found" >&2
    read -rsn1 -p "press any key to close..."
    exit 1
}

TEAL=$'\033[38;2;0;255;180m'
RED=$'\033[38;2;255;0;80m'
AMBER=$'\033[38;2;255;85;0m'
DIM=$'\033[38;2;0;160;110m'
BOLD=$'\033[1m'
RST=$'\033[0m'

printf '%s%s── RETURN TO MAIN in %s ──%s\n\n' "$BOLD" "$RED" "$WS_DIR" "$RST"

total=0 switched=0 pulled=0 skipped=0 failed=0
start=$SECONDS

default_branch() {
    local repo=$1 b
    b=$(git -C "$repo" symbolic-ref --quiet refs/remotes/origin/HEAD 2>/dev/null \
        | sed 's@^refs/remotes/origin/@@')
    if [[ -z "$b" ]]; then
        for cand in main master; do
            if git -C "$repo" show-ref --verify --quiet "refs/remotes/origin/$cand"; then
                b=$cand; break
            fi
        done
    fi
    printf '%s' "$b"
}

while IFS= read -r name; do
    repo="$WS_DIR/$name"
    git -C "$repo" rev-parse --git-dir >/dev/null 2>&1 || {
        printf '%s  ◌ %-28s not a git repo, skipping%s\n' "$DIM" "$name" "$RST"
        ((skipped++)); continue
    }
    ((total++))
    branch=$(git -C "$repo" branch --show-current 2>/dev/null)
    printf '%s%s▶ %-28s%s %s(%s)%s\n' "$BOLD" "$TEAL" "$name" "$RST" "$DIM" "${branch:-detached}" "$RST"

    if ! git -C "$repo" fetch --all --prune --verbose 2>&1 | sed 's/^/    /'; then
        printf '%s    ✖ fetch failed for %s%s\n' "$RED" "$name" "$RST"
        ((failed++)); echo; continue
    fi

    main=$(default_branch "$repo")
    if [[ -z "$main" ]]; then
        printf '%s    ⊘ no main/master on origin, skipping%s\n' "$DIM" "$RST"
        ((skipped++)); echo; continue
    fi

    if [[ -n "$(git -C "$repo" status --porcelain 2>/dev/null)" ]]; then
        printf '%s    ⊘ local changes present, staying put%s\n' "$AMBER" "$RST"
        ((skipped++)); echo; continue
    fi

    if [[ "$branch" != "$main" ]]; then
        if [[ -z "$branch" ]]; then
            printf '%s    ⊘ detached HEAD, staying put%s\n' "$DIM" "$RST"
            ((skipped++)); echo; continue
        fi
        if git -C "$repo" rev-parse --abbrev-ref --symbolic-full-name '@{u}' >/dev/null 2>&1; then
            ahead=$(git -C "$repo" rev-list --count '@{u}..HEAD' 2>/dev/null)
            if [[ "${ahead:-0}" -ne 0 ]]; then
                printf '%s    ⊘ %s is %s commit(s) ahead of origin, staying put%s\n' "$AMBER" "$branch" "$ahead" "$RST"
                ((skipped++)); echo; continue
            fi
        elif [[ -n "$(git -C "$repo" config --get "branch.$branch.merge" 2>/dev/null)" ]]; then
            printf '%s    ⌁ %s upstream gone (merged?), returning to main%s\n' "$DIM" "$branch" "$RST"
        else
            printf '%s    ⊘ %s has no upstream, staying put%s\n' "$AMBER" "$branch" "$RST"
            ((skipped++)); echo; continue
        fi

        if git -C "$repo" checkout "$main" 2>&1 | sed 's/^/    /'; then
            printf '%s    ⇄ switched %s → %s%s\n' "$TEAL" "$branch" "$main" "$RST"
            ((switched++))
        else
            printf '%s    ✖ checkout %s failed for %s%s\n' "$RED" "$main" "$name" "$RST"
            ((failed++)); echo; continue
        fi
    fi

    if git -C "$repo" pull --ff-only --verbose 2>&1 | sed 's/^/    /'; then
        ((pulled++))
    else
        printf '%s    ✖ pull failed (diverged?) for %s%s\n' "$RED" "$name" "$RST"
        ((failed++))
    fi
    echo
done < <(find "$WS_DIR" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | sort)

elapsed=$((SECONDS - start))
printf '%s%s── done: %d switched, %d pulled, %d failed, %d skipped — %ds ──%s\n' \
    "$BOLD" "$RED" "$switched" "$pulled" "$failed" "$skipped" "$elapsed" "$RST"

read -rsn1 -p $'\033[2mpress any key to close...\033[0m'
