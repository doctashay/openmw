#!/bin/bash
# One script: patch OpenMW so Mesa/libgallium and ImageIO work, then run it.
# Do not set DYLD_LIBRARY_PATH (breaks ImageIO / __cg_DGifCloseFile). Uses rpath instead.
#
# Usage: ./run_openmw.sh <path/to/OpenMW.app or openmw> [openmw args...]
# Example: ./run_openmw.sh ./build_test/OpenMW.app --data "/Volumes/media/Data Files" --content Morrowind.esm --no-sound

set -e

MESA_LIB="/opt/local/lib"
MESA_GL="/opt/local/lib/libGL.1.dylib"
SYSTEM_GL="/System/Library/Frameworks/OpenGL.framework/Versions/A/Libraries/libGL.dylib"

APP_OR_BIN="${1:-}"
if [ -z "$APP_OR_BIN" ]; then
    echo "Usage: $0 <OpenMW.app | path/to/openmw> [openmw args...]" 1>&2
    exit 1
fi
shift || true

# Resolve executable
if [ -d "$APP_OR_BIN" ]; then
    EXE="$APP_OR_BIN/Contents/MacOS/openmw"
    [ ! -f "$EXE" ] && echo "Error: $EXE not found" 1>&2 && exit 1
elif [ -f "$APP_OR_BIN" ] && [ -x "$APP_OR_BIN" ]; then
    EXE="$APP_OR_BIN"
else
    echo "Error: Not an app bundle or executable: $APP_OR_BIN" 1>&2
    exit 1
fi

# Patch only the main executable (idempotent)
if [ ! -f "$MESA_GL" ]; then
    echo "Warning: $MESA_GL not found; skipping Mesa/rpath fix." 1>&2
else
    # 1) Revert system libGL -> Mesa if a previous patch pointed at system libGL
    for ref in $(otool -L "$EXE" 2>/dev/null | sed 's/^[[:space:]]*//;s/[[:space:]].*//;s/\r$//'); do
        case "$ref" in
            "$SYSTEM_GL")
                install_name_tool -change "$ref" "$MESA_GL" "$EXE"
                echo "Patched: reverted to Mesa libGL"
                break
                ;;
        esac
    done

    # 2) Add rpath so libGL.1.dylib can find libgallium (no DYLD_LIBRARY_PATH = no ImageIO break)
    if ! otool -l "$EXE" 2>/dev/null | grep -q "path $MESA_LIB"; then
        if install_name_tool -add_rpath "$MESA_LIB" "$EXE" 2>/dev/null; then
            echo "Patched: added rpath $MESA_LIB"
        fi
    fi
fi

exec "$EXE" "$@"
