#!/usr/bin/env bash
# git-fetch every repo under ~/Workspace(s)/* — loud, verbose, glitchcore.
# also fast-forwards each repo's default branch (main/master) to origin WITHOUT
# checking it out, so `main` stays current no matter which branch a workspace is
# parked on. the checkout / current branch / working tree is never touched.
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

total=0 fetched=0 skipped=0 failed=0 pulled=0 mained=0
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

    # keep the local default branch (main/master) current WITHOUT changing the
    # checkout. when main isn't the current branch we fast-forward its ref
    # straight from the already-fetched origin/<main> via `fetch .` (no network,
    # ff-only so a diverged local main is never clobbered; HEAD/index/worktree
    # are untouched). when main IS checked out, the pull above already did it.
    main=$(default_branch "$repo")
    if [[ -n "$main" && "$branch" != "$main" ]] \
        && git -C "$repo" show-ref --verify --quiet "refs/heads/$main" \
        && git -C "$repo" show-ref --verify --quiet "refs/remotes/origin/$main"; then
        cur=$(git -C "$repo" rev-parse "refs/heads/$main")
        tgt=$(git -C "$repo" rev-parse "refs/remotes/origin/$main")
        if [[ "$cur" == "$tgt" ]]; then
            : # main already current, nothing to do
        elif git -C "$repo" fetch --no-tags . "refs/remotes/origin/$main:refs/heads/$main" >/dev/null 2>&1; then
            printf '%s    ⇡ fast-forwarded %s → origin/%s (checkout untouched)%s\n' "$TEAL" "$main" "$main" "$RST"
            ((mained++))
        else
            printf '%s    ⊘ %s diverged from origin, left as-is%s\n' "$AMBER" "$main" "$RST"
        fi
    fi
    echo
done < <(find "$WS_DIR" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | sort)

elapsed=$((SECONDS - start))
printf '%s%s── done: %d fetched, %d pulled, %d main ff'"'"'d, %d failed, %d skipped — %ds ──%s\n' \
    "$BOLD" "$RED" "$fetched" "$pulled" "$mained" "$failed" "$skipped" "$elapsed" "$RST"

read -rsn1 -p $'\033[2mpress any key to close...\033[0m'
