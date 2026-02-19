#!/bin/bash
# Build only packages whose PKGBUILD version doesn't match the built package in x86_64/
# or that have no built package yet. Uses repo directory name for build.sh (e.g. build.sh walker).
set -e

REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$REPO_ROOT"

X86_64="$REPO_ROOT/x86_64"
SRC="$REPO_ROOT/src"

# Optional: skip chroot (same as build.sh --debug)
USE_CHROOT=1
while [[ "${1:-}" == --debug ]]; do
  USE_CHROOT=0
  shift
done

# Build map: pkgname -> "pkgver-pkgrel" from existing .pkg.tar.zst in x86_64
declare -A DB_VERSION
if [[ -d "$X86_64" ]]; then
  for f in "$X86_64"/*.pkg.tar.zst; do
    [[ -e "$f" ]] || continue
    # pacman -Qp prints "pkgname pkgver-pkgrel"
    line=$(pacman -Qp "$f" 2>/dev/null) || continue
    read -r pkgname pkgverrel _ <<< "$line"
    DB_VERSION["$pkgname"]="$pkgverrel"
  done
fi

# Collect directory names (build targets) that need a build
TO_BUILD=()

for dir in "$SRC"/*/; do
  [[ -d "$dir" ]] || continue
  [[ -f "${dir}PKGBUILD" ]] || continue
  name=$(basename "$dir")

  # Get pkgname, pkgver, pkgrel from PKGBUILD (source in subshell so we get resolved $_pkgname etc.)
  vars=$(cd "$dir" && source PKGBUILD 2>/dev/null && echo "${pkgname} ${pkgver} ${pkgrel}")
  read -r pkgname pkgver pkgrel <<< "$vars"
  if [[ -z "$pkgname" || -z "$pkgver" ]]; then
    echo "Warning: could not parse PKGBUILD in $name, skipping"
    continue
  fi
  pkgrel=${pkgrel:-1}
  want_version="${pkgver}-${pkgrel}"
  have_version="${DB_VERSION[$pkgname]:-}"

  if [[ "$have_version" != "$want_version" ]]; then
    if [[ -z "$have_version" ]]; then
      echo "Need build: $name (no package in x86_64)"
    else
      echo "Need build: $name (PKGBUILD ${want_version} != x86_64 ${have_version})"
    fi
    TO_BUILD+=("$name")
  fi
done

if [[ ${#TO_BUILD[@]} -eq 0 ]]; then
  echo "All packages match x86_64. Nothing to build."
  exit 0
fi

echo ""
echo "Building ${#TO_BUILD[@]} package(s): ${TO_BUILD[*]}"
BUILD_OPTS=()
[[ "$USE_CHROOT" -eq 0 ]] && BUILD_OPTS=(--debug)
for name in "${TO_BUILD[@]}"; do
  echo "--- $name ---"
  "$REPO_ROOT/build.sh" "${BUILD_OPTS[@]}" "$name"
done
echo "Done."
