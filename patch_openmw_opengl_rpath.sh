#!/bin/bash
# Fix dyld "Library not loaded: @rpath/libgallium-*.dylib" when using MacPorts Mesa.
# - Ensures the openmw binary uses /opt/local/lib/libGL.1.dylib (Mesa), not system libGL.
# - Adds @rpath /opt/local/lib so libGL.1.dylib can find libgallium-*.dylib.
# Usage: ./patch_openmw_opengl_rpath.sh [path/to/OpenMW.app or path/to/openmw]

set -e

MESA_LIB="/opt/local/lib"
MESA_GL="/opt/local/lib/libGL.1.dylib"
SYSTEM_GL="/System/Library/Frameworks/OpenGL.framework/Versions/A/Libraries/libGL.dylib"

if [ ! -f "$MESA_GL" ]; then
    echo "Error: Mesa libGL not found at $MESA_GL. Install Mesa (e.g. sudo port install mesa)." 1>&2
    exit 1
fi

# Resolve app or executable path
APP_OR_BIN="${1:-}"
if [ -z "$APP_OR_BIN" ]; then
    echo "Usage: $0 <path/to/OpenMW.app | path/to/openmw>" 1>&2
    exit 1
fi

if [ -d "$APP_OR_BIN" ]; then
    BIN="$APP_OR_BIN/Contents/MacOS/openmw"
    if [ ! -f "$BIN" ]; then
        echo "Error: No openmw executable at $BIN" 1>&2
        exit 1
    fi
    BINS=("$BIN")
    if [ -d "$APP_OR_BIN/Contents/Frameworks" ]; then
        for f in "$APP_OR_BIN/Contents/Frameworks"/*.dylib; do
            [ -f "$f" ] && BINS+=("$f")
        done
    fi
    if [ -d "$APP_OR_BIN/Contents/MacOS" ]; then
        for f in "$APP_OR_BIN/Contents/MacOS"/*.dylib; do
            [ -f "$f" ] && BINS+=("$f")
        done
    fi
elif [ -f "$APP_OR_BIN" ]; then
    BINS=("$APP_OR_BIN")
else
    echo "Error: Not a file or directory: $APP_OR_BIN" 1>&2
    exit 1
fi

# 1) Revert system libGL back to Mesa (if a previous patch pointed to system libGL)
# 2) Add rpath so Mesa libGL can find libgallium via @rpath
patch_one() {
    local bin="$1"
    local changed=0
    for ref in $(otool -L "$bin" 2>/dev/null | sed 's/^[[:space:]]*//;s/[[:space:]].*//;s/\r$//'); do
        case "$ref" in
            "$SYSTEM_GL")
                echo "  Reverting to Mesa: $ref -> $MESA_GL"
                install_name_tool -change "$ref" "$MESA_GL" "$bin"
                changed=1
                ;;
        esac
    done
    # Add rpath so @rpath/libgallium-*.dylib resolves to /opt/local/lib (needs Xcode 9+ install_name_tool)
    if install_name_tool -add_rpath "$MESA_LIB" "$bin" 2>/dev/null; then
        echo "  Added rpath: $MESA_LIB"
        changed=1
    else
        echo "  Note: install_name_tool -add_rpath not available (e.g. Leopard). Use the launcher script." 1>&2
    fi
    return 0
}

echo "Patching OpenMW to use Mesa libGL and resolve libgallium @rpath:"
for b in "${BINS[@]}"; do
    echo "  $b"
done
echo ""

for bin in "${BINS[@]}"; do
    patch_one "$bin"
done

echo "Done. Run OpenMW again. If you still see libgallium not found, run with:"
echo "  DYLD_LIBRARY_PATH=/opt/local/lib $BINS \"\$@\""
echo "(or use the openmw launcher script in the app bundle if provided)."
