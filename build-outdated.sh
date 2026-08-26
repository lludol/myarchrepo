#!/bin/bash
# Build only packages whose PKGBUILD version doesn't match the published repository database.
# Uses repo directory name for build.sh (e.g. build.sh cursor-bin).
set -e

REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$REPO_ROOT"

X86_64="$REPO_ROOT/x86_64"
SRC="$REPO_ROOT/src"
R2_PUBLIC_URL="https://repo.ll03.me/x86_64"

# Optional: skip chroot (same as build.sh --debug) or skip R2 publishing.
USE_CHROOT=1
UPLOAD_R2=1
while [[ $# -gt 0 ]]; do
  case "$1" in
    --debug)
      USE_CHROOT=0
      ;;
    --no-upload)
      UPLOAD_R2=0
      ;;
    -h|--help)
      echo "Usage: $0 [--debug] [--no-upload]"
      echo "  --debug      Build with makepkg instead of a clean chroot"
      echo "  --no-upload  Do not publish the finished repository to R2"
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      exit 1
      ;;
  esac
  shift
done

publish_r2() {
  if [[ "$UPLOAD_R2" -eq 1 ]]; then
    echo ""
    echo "Publishing repository to Cloudflare R2..."
    "$REPO_ROOT/upload-r2.sh" --prune
  fi
}

mkdir -p "$X86_64"

download_database() {
  local filename=$1
  local destination="$X86_64/$filename"

  if [[ ! -f "$destination" ]]; then
    echo "Downloading $filename from R2..."
    curl --fail --location --output "$destination.tmp" "$R2_PUBLIC_URL/${filename%.tar.zst}"
    mv -- "$destination.tmp" "$destination"
  fi
}

download_database myrepo.db.tar.zst
download_database myrepo.files.tar.zst

# Build map: pkgname -> "pkgver-pkgrel" from the current repository database.
declare -A DB_VERSION
while IFS=$'\t' read -r pkgname pkgverrel; do
  [[ -n "$pkgname" && -n "$pkgverrel" ]] || continue
  DB_VERSION["$pkgname"]="$pkgverrel"
done < <(
  bsdtar -xOf "$X86_64/myrepo.db.tar.zst" '*/desc' |
    awk '/^%NAME%$/ { getline; name=$0 } /^%VERSION%$/ { getline; print name "\t" $0 }'
)

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
      echo "Need build: $name (not in published repository)"
    else
      echo "Need build: $name (PKGBUILD ${want_version} != repository ${have_version})"
    fi
    TO_BUILD+=("$name")
  fi
done

if [[ ${#TO_BUILD[@]} -eq 0 ]]; then
  echo "All packages match x86_64. Nothing to build."
  publish_r2
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
publish_r2
echo "Done."
