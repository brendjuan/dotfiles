#!/usr/bin/env bash
# for every repo under ~/Workspace(s)/*: fetch, then — ONLY when it's safe —
# switch the repo back to its default branch (main/master) and fast-forward it.
#
# "safe" means the current branch is fully synced to origin and the tree is
# clean, so nothing local gets orphaned or clobbered:
#   - working tree clean (no uncommitted OR untracked changes)
#   - current branch has an upstream and is NOT ahead of it (no unpushed
#     commits) — OR its upstream is GONE (remote branch deleted, e.g. a merged
#     PR), which we treat as a dead branch that's safe to leave behind. the
#     local branch ref survives the switch, so nothing is actually lost.
# repos that fail these gates are left exactly where they are. loud, glitchcore.
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

printf '%s%s── RETURN TO MAIN in %s ──%s\n\n' "$BOLD" "$RED" "$WS_DIR" "$RST"

total=0 switched=0 pulled=0 skipped=0 failed=0
start=$SECONDS

# resolve a repo's default branch: prefer origin/HEAD, else fall back to
# whichever of main/master exists on the remote.
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

    # fetch first so upstream/main refs are current.
    if ! git -C "$repo" fetch --all --prune --verbose 2>&1 | sed 's/^/    /'; then
        printf '%s    ✖ fetch failed for %s%s\n' "$RED" "$name" "$RST"
        ((failed++)); echo; continue
    fi

    main=$(default_branch "$repo")
    if [[ -z "$main" ]]; then
        printf '%s    ⊘ no main/master on origin, skipping%s\n' "$DIM" "$RST"
        ((skipped++)); echo; continue
    fi

    # safety gate 1: clean working tree (covers untracked + uncommitted).
    if [[ -n "$(git -C "$repo" status --porcelain 2>/dev/null)" ]]; then
        printf '%s    ⊘ local changes present, staying put%s\n' "$AMBER" "$RST"
        ((skipped++)); echo; continue
    fi

    # safety gate 2: current branch is synced to origin (not ahead / no
    # unpushed commits). detached HEAD or a branch with no upstream can't be
    # proven synced, so we refuse to move it. skip the gate if we're already
    # sitting on the default branch (nothing to abandon).
    if [[ "$branch" != "$main" ]]; then
        if [[ -z "$branch" ]]; then
            printf '%s    ⊘ detached HEAD, staying put%s\n' "$DIM" "$RST"
            ((skipped++)); echo; continue
        fi
        # is there a LIVE upstream we can compare against?
        if git -C "$repo" rev-parse --abbrev-ref --symbolic-full-name '@{u}' >/dev/null 2>&1; then
            # upstream exists → only move if we're not ahead (no unpushed commits).
            ahead=$(git -C "$repo" rev-list --count '@{u}..HEAD' 2>/dev/null)
            if [[ "${ahead:-0}" -ne 0 ]]; then
                printf '%s    ⊘ %s is %s commit(s) ahead of origin, staying put%s\n' "$AMBER" "$branch" "$ahead" "$RST"
                ((skipped++)); echo; continue
            fi
        elif [[ -n "$(git -C "$repo" config --get "branch.$branch.merge" 2>/dev/null)" ]]; then
            # @{u} unresolvable BUT a tracking ref was configured → the remote
            # branch is GONE (deleted on origin, typically a merged PR). the
            # branch is dead; return it to main. its local ref still points at
            # these commits, so check it back out if you ever need it.
            printf '%s    ⌁ %s upstream gone (merged?), returning to main%s\n' "$DIM" "$branch" "$RST"
        else
            # never had an upstream → can't prove it's synced, stay put.
            printf '%s    ⊘ %s has no upstream, staying put%s\n' "$AMBER" "$branch" "$RST"
            ((skipped++)); echo; continue
        fi

        # safe to switch.
        if git -C "$repo" checkout "$main" 2>&1 | sed 's/^/    /'; then
            printf '%s    ⇄ switched %s → %s%s\n' "$TEAL" "$branch" "$main" "$RST"
            ((switched++))
        else
            printf '%s    ✖ checkout %s failed for %s%s\n' "$RED" "$main" "$name" "$RST"
            ((failed++)); echo; continue
        fi
    fi

    # on main now — fast-forward it. --ff-only never merges or clobbers.
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
