#!/bin/bash

set -e

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
cd "$REPO_ROOT"
USE_CHROOT=1

while [[ $# -gt 0 ]]; do
    case "$1" in
        --debug)
            USE_CHROOT=0
            shift
            ;;
        -*)
            echo "Unknown option: $1"
            echo "Usage: $0 [--debug] <pkgname>"
            echo "  --debug  build with makepkg only (no chroot)"
            exit 1
            ;;
        *)
            break
            ;;
    esac
done

if [ $# -ne 1 ]; then
    echo "Usage: $0 [--debug] <pkgname>"
    echo "Example: $0 fastmail"
    echo "         $0 --debug fastmail"
    exit 1
fi

PKGNAME="$1"
PKGDIR="$REPO_ROOT/src/$PKGNAME"

if [ ! -d "$PKGDIR" ]; then
    echo "Error: $PKGDIR not found!"
    exit 1
fi

cd "$PKGDIR" || exit 1

if [ "$USE_CHROOT" -eq 1 ]; then
    echo "Building $PKGNAME in clean chroot..."
    extra-x86_64-build
else
    echo "Building $PKGNAME with makepkg (no chroot, --debug)..."
    makepkg -sCf
fi

# Capture only archives produced by this build. Split debug packages also
# start with the build target name and are included here.
mapfile -d '' BUILT_PACKAGES < <(
    find . -maxdepth 1 -type f \
        \( -name "$PKGNAME-*.pkg.tar.zst" -o -name "$PKGNAME-*.pkg.tar.xz" \) \
        -print0
)

if [[ ${#BUILT_PACKAGES[@]} -eq 0 ]]; then
    echo "Error: build succeeded but produced no package archives" >&2
    exit 1
fi

mkdir -p "$REPO_ROOT/x86_64"

# A fresh clone has no generated repository artifacts. Start from the current
# R2 databases so a standalone package build updates the complete repository.
for database in myrepo.db.tar.zst myrepo.files.tar.zst; do
    destination="$REPO_ROOT/x86_64/$database"
    if [[ ! -f "$destination" ]]; then
        public_name=${database%.tar.zst}
        echo "Downloading $public_name from R2..."
        curl --fail --location \
            --output "$destination.tmp" \
            "https://repo.ll03.me/x86_64/$public_name"
        mv -- "$destination.tmp" "$destination"
    fi
done

MOVED_PACKAGES=()
for package in "${BUILT_PACKAGES[@]}"; do
    filename=$(basename -- "$package")
    destination="$REPO_ROOT/x86_64/$filename"
    mv -- "$package" "$destination"
    MOVED_PACKAGES+=("$destination")

    if [[ -f "$package.sig" ]]; then
        mv -- "$package.sig" "$destination.sig"
    fi
done

echo "Moved packages to $REPO_ROOT/x86_64/"
printf '  %s\n' "${MOVED_PACKAGES[@]}"

echo "Build succeeded. Running clean..."
cd "$REPO_ROOT" || exit 1
./clean.sh

echo "Updating repo database..."
repo-add --prevent-downgrade x86_64/myrepo.db.tar.zst "${MOVED_PACKAGES[@]}"
