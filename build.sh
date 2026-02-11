#!/bin/bash

REPO_ROOT="$(pwd)"

if [ $# -ne 1 ]; then
    echo "Usage: $0 <pkgname>"
    echo "Example: $0 fastmail"
    exit 1
fi

PKGNAME="$1"
PKGDIR="src/$PKGNAME"

if [ ! -d "$PKGDIR" ]; then
    echo "Error: $PKGDIR not found!"
    exit 1
fi

cd "$PKGDIR" || exit 1

echo "Building $PKGNAME in clean chroot..."
extra-x86_64-build

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
repo-add x86_64/myrepo.db.tar.zst x86_64/*.pkg.tar.zst