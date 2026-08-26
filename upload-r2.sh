#!/bin/bash

set -euo pipefail

export R2_ENDPOINT="https://5277160f58af6328e98e35970b05a309.r2.cloudflarestorage.com"
export R2_BUCKET="myarchrepo"
export R2_PUBLIC_URL="https://repo.ll03.me"
export AWS_PROFILE="${AWS_PROFILE:-r2}"

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$REPO_ROOT/x86_64"
REPO_NAME="myrepo"
REMOTE_PREFIX="x86_64"
PRUNE=0

usage() {
    cat <<'EOF'
Usage: ./upload-r2.sh [--prune]

Uploads the packages referenced by x86_64/myrepo.db.tar.zst to Cloudflare R2.

Options:
  --prune  Delete remote package archives that are not in the current database.
  -h       Show this help.

The AWS CLI must have an "r2" profile with write access to the myarchrepo bucket.
Set AWS_PROFILE to use a different profile.
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --prune)
            PRUNE=1
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "Unknown option: $1" >&2
            usage >&2
            exit 1
            ;;
    esac
    shift
done

for command in aws bsdtar sha256sum stat; do
    if ! command -v "$command" >/dev/null 2>&1; then
        echo "Error: required command not found: $command" >&2
        exit 1
    fi
done

DB_ARCHIVE="$REPO_DIR/$REPO_NAME.db.tar.zst"
FILES_ARCHIVE="$REPO_DIR/$REPO_NAME.files.tar.zst"

for archive in "$DB_ARCHIVE" "$FILES_ARCHIVE"; do
    if [[ ! -f "$archive" ]]; then
        echo "Error: required repository database not found: $archive" >&2
        exit 1
    fi
done

TMP_DIR="$(mktemp -d)"
trap 'rm -rf -- "$TMP_DIR"' EXIT

PACKAGE_MANIFEST="$TMP_DIR/packages"
REMOTE_KEEP_MANIFEST="$TMP_DIR/remote-keep"

bsdtar -xOf "$DB_ARCHIVE" '*/desc' |
    awk '
        /^%FILENAME%$/ { getline; filename=$0 }
        /^%CSIZE%$/ { getline; size=$0 }
        /^%SHA256SUM%$/ {
            getline
            if (filename != "" && size != "") {
                print filename "\t" size "\t" $0
            }
            filename=""
            size=""
        }
    ' |
    sort -u > "$PACKAGE_MANIFEST"

if [[ ! -s "$PACKAGE_MANIFEST" ]]; then
    echo "Error: no package filenames found in $DB_ARCHIVE" >&2
    exit 1
fi

AWS_GLOBAL_ARGS=(
    --profile "$AWS_PROFILE"
    --endpoint-url "$R2_ENDPOINT"
)
AWS_S3_ARGS=(
    "${AWS_GLOBAL_ARGS[@]}"
    --only-show-errors
)

uploaded_count=0
skipped_count=0
remote_only_count=0

read_remote_object() {
    local key=$1
    local remote_details

    REMOTE_SIZE=""
    REMOTE_CHECKSUM=""
    remote_details=$(aws s3api head-object \
        --bucket "$R2_BUCKET" \
        --key "$key" \
        --query '[ContentLength, Metadata.sha256]' \
        --output text \
        "${AWS_GLOBAL_ARGS[@]}" 2>/dev/null) || return 1
    read -r REMOTE_SIZE REMOTE_CHECKSUM <<< "$remote_details"
}

upload_object() {
    local source=$1
    local key=$2
    local content_type=$3
    local cache_control=$4
    local expected_size=${5:-}
    local expected_checksum=${6:-}
    local checksum local_size

    checksum=$(sha256sum "$source")
    checksum=${checksum%% *}
    local_size=$(stat -c %s "$source")

    if [[ -n "$expected_size" && -n "$expected_checksum" ]] && \
        [[ "$local_size" != "$expected_size" || "$checksum" != "$expected_checksum" ]]; then
        echo "Error: local object does not match repository database: ${source##*/}" >&2
        exit 1
    fi

    if read_remote_object "$key" && \
        [[ "$REMOTE_SIZE" == "$local_size" && "$REMOTE_CHECKSUM" == "$checksum" ]]; then
        skipped_count=$((skipped_count + 1))
        return
    fi

    aws s3 cp "$source" "s3://$R2_BUCKET/$key" \
        "${AWS_S3_ARGS[@]}" \
        --content-type "$content_type" \
        --cache-control "$cache_control" \
        --metadata "sha256=$checksum"
    uploaded_count=$((uploaded_count + 1))
}

echo "Uploading packages referenced by $REPO_NAME.db..."
package_count=0
while IFS=$'\t' read -r filename expected_size expected_checksum; do
    package_path="$REPO_DIR/$filename"
    package_key="$REMOTE_PREFIX/$filename"

    if [[ -f "$package_path" ]]; then
        upload_object \
            "$package_path" \
            "$package_key" \
            application/octet-stream \
            "public, max-age=31536000, immutable" \
            "$expected_size" \
            "$expected_checksum"
    elif read_remote_object "$package_key" && \
        [[ "$REMOTE_SIZE" == "$expected_size" && "$REMOTE_CHECKSUM" == "$expected_checksum" ]]; then
        remote_only_count=$((remote_only_count + 1))
    else
        echo "Error: package is missing locally and from R2: $filename" >&2
        exit 1
    fi

    printf '%s\n' "$package_key" >> "$REMOTE_KEEP_MANIFEST"
    package_count=$((package_count + 1))

    signature_path="$package_path.sig"
    signature_key="$package_key.sig"
    if [[ -f "$signature_path" ]]; then
        upload_object \
            "$signature_path" \
            "$signature_key" \
            application/pgp-signature \
            "public, max-age=31536000, immutable"
        printf '%s\n' "$signature_key" >> "$REMOTE_KEEP_MANIFEST"
    elif read_remote_object "$signature_key"; then
        printf '%s\n' "$signature_key" >> "$REMOTE_KEEP_MANIFEST"
    fi
done < "$PACKAGE_MANIFEST"

upload_repository_file() {
    local source=$1
    local destination=$2
    local content_type=${3:-application/octet-stream}

    upload_object \
        "$source" \
        "$REMOTE_PREFIX/$destination" \
        "$content_type" \
        "no-cache, max-age=0, must-revalidate"
}

echo "Uploading repository databases..."
upload_repository_file "$FILES_ARCHIVE" "$REPO_NAME.files.tar.zst"
upload_repository_file "$FILES_ARCHIVE" "$REPO_NAME.files"
upload_repository_file "$DB_ARCHIVE" "$REPO_NAME.db.tar.zst"
upload_repository_file "$DB_ARCHIVE" "$REPO_NAME.db"

for suffix in db files; do
    signature="$REPO_DIR/$REPO_NAME.$suffix.tar.zst.sig"
    if [[ -f "$signature" ]]; then
        upload_repository_file "$signature" "$REPO_NAME.$suffix.tar.zst.sig" application/pgp-signature
        upload_repository_file "$signature" "$REPO_NAME.$suffix.sig" application/pgp-signature
    fi
done

if [[ "$PRUNE" -eq 1 ]]; then
    echo "Removing remote package archives not referenced by $REPO_NAME.db..."
    remote_keys=$(aws s3api list-objects-v2 \
        --bucket "$R2_BUCKET" \
        --prefix "$REMOTE_PREFIX/" \
        --query 'Contents[].Key' \
        --output text \
        "${AWS_GLOBAL_ARGS[@]}")

    while IFS= read -r key; do
        [[ -n "$key" && "$key" != "None" ]] || continue
        case "$key" in
            "$REMOTE_PREFIX"/*.pkg.tar.zst|"$REMOTE_PREFIX"/*.pkg.tar.zst.sig|\
            "$REMOTE_PREFIX"/*.pkg.tar.xz|"$REMOTE_PREFIX"/*.pkg.tar.xz.sig)
                if ! grep -Fxq -- "$key" "$REMOTE_KEEP_MANIFEST"; then
                    echo "Deleting obsolete object: $key"
                    aws s3 rm "s3://$R2_BUCKET/$key" "${AWS_S3_ARGS[@]}"
                fi
                ;;
        esac
    done < <(printf '%s\n' "$remote_keys" | tr '\t' '\n')
fi

echo "Published $package_count packages to $R2_PUBLIC_URL/$REMOTE_PREFIX/"
echo "Uploaded $uploaded_count object(s); skipped $skipped_count unchanged object(s)."
echo "Verified $remote_only_count package object(s) that were available only in R2."
echo "Database: $R2_PUBLIC_URL/$REMOTE_PREFIX/$REPO_NAME.db"
