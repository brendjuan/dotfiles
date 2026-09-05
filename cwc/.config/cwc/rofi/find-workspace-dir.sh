#!/usr/bin/env bash
for name in Workspace Workspaces workspace workspaces; do
    [[ -d "$HOME/$name" ]] && echo "$HOME/$name" && exit 0
done
exit 1
