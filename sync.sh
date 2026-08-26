#!/bin/bash
# Copy locally available repo output to pacman's sync directory.
# The normal repository workflow serves packages from R2 instead.
REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"
TARGET="/var/lib/pacman/sync/myarchrepo"

set -e
sudo mkdir -p "$TARGET"
sudo cp -f "$REPO_ROOT/x86_64"/* "$TARGET/"
echo "Synced x86_64/ to $TARGET/"
