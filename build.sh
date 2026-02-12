#!/bin/bash

REPO_ROOT="$(pwd)"
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
PKGDIR="src/$PKGNAME"

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

if [ $? -ne 0 ]; then
    echo "Build failed!"
    exit 1
fi

# Move all new .pkg.tar.* to parent x86_64/
find . -maxdepth 1 -name "$PKGNAME-*.pkg.tar.*" -exec mv {} ../../x86_64/ \;

echo "Moved packages to ../../x86_64/"
ls -la ../../x86_64/"$PKGNAME"-*.pkg.tar.*

echo "Build succeeded. Running clean..."
cd "$REPO_ROOT" || exit 1
./clean.sh

echo "Updating repo database..."
git lfs pull
repo-add x86_64/myrepo.db.tar.zst x86_64/*.pkg.tar.zst

echo "Syncing to pacman..."
./sync.sh