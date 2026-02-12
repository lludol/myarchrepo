#!/bin/bash
# Copy repo output to pacman sync dir. Run after build.sh on the build machine,
# or on other machines after pulling the repo (git pull + git lfs pull).
REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"
TARGET="/var/lib/pacman/sync/myarchrepo"

set -e
sudo mkdir -p "$TARGET"
sudo cp -f "$REPO_ROOT/x86_64"/* "$TARGET/"
echo "Synced x86_64/ to $TARGET/"
