#!/bin/bash
# Do NOT set DYLD_LIBRARY_PATH=/opt/local/lib to fix libgallium. That makes the
# system load MacPorts libGIF.dylib, and ImageIO then fails (Symbol not found: __cg_DGifCloseFile).
#
# Use one of these instead:
#  1) Rebuild so the binary has rpath (OPENMW_MACOSX_10_5/PPC builds set BUILD_RPATH /opt/local/lib).
#  2) Run patch_openmw_opengl_rpath.sh to add rpath with install_name_tool -add_rpath (if your tool supports it).
#
# This script just runs OpenMW with your args (no env changes).
# Usage: ./run_openmw_mesa.sh [path/to/OpenMW.app or path/to/openmw] [openmw args...]

APP_OR_BIN="${1:-}"

if [ -z "$APP_OR_BIN" ]; then
    echo "Usage: $0 <OpenMW.app | openmw> [openmw args...]" 1>&2
    exit 1
fi

if [ -d "$APP_OR_BIN" ]; then
    EXE="$APP_OR_BIN/Contents/MacOS/openmw"
    [ ! -x "$EXE" ] && echo "Error: $EXE not found or not executable" 1>&2 && exit 1
    shift
    exec "$EXE" "$@"
elif [ -f "$APP_OR_BIN" ] && [ -x "$APP_OR_BIN" ]; then
    shift
    exec "$APP_OR_BIN" "$@"
else
    echo "Error: Not an app bundle or executable: $APP_OR_BIN" 1>&2
    exit 1
fi
