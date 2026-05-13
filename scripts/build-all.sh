#!/bin/bash
# build-all.sh – iterate scripts/packages.list and build each COSMIC package
# in order, feeding produced .deb files back as build-deps via a local apt repo.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PACKAGES_LIST="${PACKAGES_LIST:-$SCRIPT_DIR/packages.list}"
OUTPUT_DIR="${OUTPUT_DIR:-/out}"
BUILD_CACHE_DIR="${BUILD_CACHE_DIR:-/cache}"
HOST_UID="${HOST_UID:-1000}"
HOST_GID="${HOST_GID:-1000}"
ONLY="${ONLY:-}"

# ── Setup ──────────────────────────────────────────────────────────────────────
mkdir -p "$OUTPUT_DIR" "$BUILD_CACHE_DIR"

# Initialise a (possibly empty) local apt repository inside $OUTPUT_DIR so that
# packages built earlier in the run are available as build-deps for later ones.
(cd "$OUTPUT_DIR" && dpkg-scanpackages . 2>/dev/null > Packages && gzip -c Packages > Packages.gz)

if [ ! -f /etc/apt/sources.list.d/local-cosmic.list ]; then
    printf 'deb [trusted=yes] file://%s ./\n' "$OUTPUT_DIR" \
        > /etc/apt/sources.list.d/local-cosmic.list
fi
apt-get update -qq

# ── Main loop ─────────────────────────────────────────────────────────────────
failed=()
succeeded=()

while read -r name url ref _rest; do
    # Skip blank lines and comment lines.
    case "$name" in
        ''|\#*) continue ;;
    esac

    # Apply ONLY filter when set.
    if [ -n "$ONLY" ] && [ "$name" != "$ONLY" ]; then
        continue
    fi

    # Substitute defaults.
    if [ "$url" = "_" ] || [ -z "$url" ]; then url="https://github.com/pop-os/${name}.git"; fi
    if [ "$ref" = "_" ] || [ -z "$ref" ]; then ref="master"; fi

    echo ""
    echo "================================================================"
    echo ">>> Building: $name  ($url @ $ref)"
    echo "================================================================"

    if (
        export OUTPUT_DIR BUILD_CACHE_DIR HOST_UID HOST_GID
        export COSMIC_REPOSITORY="$url"
        export COSMIC_REF="$ref"
        export SOURCE_DIR="/workspace/$name"
        bash "$SCRIPT_DIR/build-cosmic-deb.sh"
    ); then
        echo ">>> SUCCESS: $name"
        succeeded+=("$name")
        # Refresh the local apt repo so the next package can see these .debs.
        (cd "$OUTPUT_DIR" && dpkg-scanpackages . 2>/dev/null > Packages && gzip -c Packages > Packages.gz)
        apt-get update -qq
    else
        echo ">>> FAILED: $name"
        failed+=("$name")
    fi
done < "$PACKAGES_LIST"

# ── Final chown ────────────────────────────────────────────────────────────────
chown -R "${HOST_UID}:${HOST_GID}" "$OUTPUT_DIR" "$BUILD_CACHE_DIR"

# ── Summary ────────────────────────────────────────────────────────────────────
echo ""
echo "================================================================"
echo "BUILD SUMMARY"
echo "================================================================"
printf "Succeeded (%d): %s\n" "${#succeeded[@]}" "${succeeded[*]:-none}"
printf "Failed    (%d): %s\n" "${#failed[@]}"   "${failed[*]:-none}"
echo "================================================================"

[ "${#failed[@]}" -eq 0 ]
