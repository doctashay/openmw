#!/bin/bash
# Prepare a release-style OpenMW.app by copying it to a staging directory,
# copying the sibling First Time Setup.command, and vendoring MacPorts
# dynamic libraries referenced from /opt/local.
#
# Usage:
#   ./prepare_app.sh [path/to/OpenMW.app] [output-dir]
#
# Defaults:
#   app:    ./build_test/OpenMW.app
#   output: ./prepared_app

set -euo pipefail

APP_SOURCE="${1:-$(pwd)/build_test/OpenMW.app}"
OUTPUT_ROOT="${2:-$(pwd)/prepared_app}"

if [ ! -d "$APP_SOURCE" ]; then
    echo "Error: app bundle not found: $APP_SOURCE" 1>&2
    exit 1
fi

APP_SOURCE="$(cd "$(dirname "$APP_SOURCE")" && pwd)/$(basename "$APP_SOURCE")"
OUTPUT_ROOT="$(mkdir -p "$OUTPUT_ROOT" && cd "$OUTPUT_ROOT" && pwd)"

APP_NAME="$(basename "$APP_SOURCE")"
STAGED_APP="$OUTPUT_ROOT/$APP_NAME"
FRAMEWORKS_DIR="$STAGED_APP/Contents/Frameworks"
MACOS_DIR="$STAGED_APP/Contents/MacOS"
SETUP_SOURCE="$(dirname "$APP_SOURCE")/First Time Setup.command"
SETUP_DEST="$OUTPUT_ROOT/First Time Setup.command"

echo "Staging app bundle:"
echo "  source: $APP_SOURCE"
echo "  output: $STAGED_APP"

rm -rf "$STAGED_APP"
mkdir -p "$FRAMEWORKS_DIR"
ditto "$APP_SOURCE" "$STAGED_APP"

if [ -f "$SETUP_SOURCE" ]; then
    cp -p "$SETUP_SOURCE" "$SETUP_DEST"
    chmod +x "$SETUP_DEST"
    echo "Copied setup command: $SETUP_DEST"
else
    echo "Warning: sibling First Time Setup.command not found at $SETUP_SOURCE"
fi

list_deps() {
    local target="$1"
    otool -L "$target" 2>/dev/null | tail -n +2 | awk '{print $1}'
}

copy_dependency() {
    local dep="$1"
    local base dest

    base="$(basename "$dep")"
    dest="$FRAMEWORKS_DIR/$base"

    if [ ! -e "$dest" ]; then
        cp -p "$dep" "$dest"
        chmod u+w "$dest"
        install_name_tool -id "@executable_path/../Frameworks/$base" "$dest"
        echo "Bundled dependency: $base"
    fi

    printf '%s\n' "$dest"
}

patch_binary() {
    local target="$1"
    local dep copied base new_ref

    chmod u+w "$target" 2>/dev/null || true
    while IFS= read -r dep; do
        case "$dep" in
            /opt/local/*)
                copied="$(copy_dependency "$dep")"
                base="$(basename "$copied")"
                new_ref="@executable_path/../Frameworks/$base"
                install_name_tool -change "$dep" "$new_ref" "$target"
                ;;
        esac
    done < <(list_deps "$target")
}

collect_binaries() {
    find "$MACOS_DIR" "$FRAMEWORKS_DIR" -type f | while IFS= read -r candidate; do
        if otool -L "$candidate" >/dev/null 2>&1; then
            printf '%s\n' "$candidate"
        fi
    done
}

previous_count=-1
while true; do
    current_count="$(find "$FRAMEWORKS_DIR" -type f | wc -l | tr -d ' ')"
    if [ "$current_count" = "$previous_count" ]; then
        break
    fi
    previous_count="$current_count"
    while IFS= read -r binary; do
        patch_binary "$binary"
    done < <(collect_binaries)
done

echo ""
echo "Final bundled /opt/local references:"
found_nonbundled=0
while IFS= read -r binary; do
    while IFS= read -r dep; do
        case "$dep" in
            /opt/local/*)
                echo "  $binary -> $dep"
                found_nonbundled=1
                ;;
        esac
    done < <(list_deps "$binary")
done < <(collect_binaries)

if [ "$found_nonbundled" -eq 0 ]; then
    echo "  none"
fi

echo ""
echo "Prepared app bundle:"
echo "  $STAGED_APP"
