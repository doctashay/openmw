#!/bin/bash
# runme.sh — Launch OpenMW on PowerPC Mac
# Prompts for your Morrowind "Data Files" folder the first time, saves it for next runs.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/.runme_config"

# ── Find the OpenMW binary ──────────────────────────────────────────────────
find_openmw() {
    # Common build output locations relative to this script
    local candidates=(
        "$SCRIPT_DIR/build/OpenMW.app"
        "$SCRIPT_DIR/build/openmw"
        "$SCRIPT_DIR/build_ppc/OpenMW.app"
        "$SCRIPT_DIR/build_ppc/openmw"
        "$SCRIPT_DIR/OpenMW.app"
        "$PWD/build/OpenMW.app"
        "$PWD/build/openmw"
        "$PWD/build_ppc/OpenMW.app"
        "$PWD/build_ppc/openmw"
        "$PWD/OpenMW.app"
        "$PWD/openmw"
    )
    for c in "${candidates[@]}"; do
        if [ -d "$c" ] || [ -x "$c" ]; then
            echo "$c"
            return 0
        fi
    done
    return 1
}

OPENMW="$(find_openmw)" || {
    echo "Error: could not find OpenMW binary or app bundle." >&2
    echo "Expected one of: build/OpenMW.app, build/openmw, etc." >&2
    echo "You can pass the path as the first argument: $0 /path/to/openmw" >&2
    exit 1
}

# Allow overriding the binary via first argument
if [ $# -ge 1 ] && ( [ -d "$1" ] || [ -x "$1" ] ); then
    OPENMW="$1"
    shift
fi

# ── Load or prompt for Data Files path ─────────────────────────────────────
if [ -f "$CONFIG_FILE" ]; then
    # shellcheck source=/dev/null
    source "$CONFIG_FILE"
fi

if [ -z "$DATA_FILES" ] || [ ! -d "$DATA_FILES" ]; then
    echo ""
    echo "Where is your Morrowind 'Data Files' folder?"
    echo "(This is the folder containing Morrowind.esm, Morrowind.bsa, etc.)"
    echo ""
    read -r -p "Data Files path: " DATA_FILES

    # Strip surrounding quotes the user might have typed
    DATA_FILES="${DATA_FILES%\"}"
    DATA_FILES="${DATA_FILES#\"}"
    DATA_FILES="${DATA_FILES%\'}"
    DATA_FILES="${DATA_FILES#\'}"

    if [ ! -d "$DATA_FILES" ]; then
        echo "Error: '$DATA_FILES' is not a directory." >&2
        exit 1
    fi
    if [ ! -f "$DATA_FILES/Morrowind.esm" ] && [ ! -f "$DATA_FILES/morrowind.esm" ]; then
        echo "Warning: Morrowind.esm not found in '$DATA_FILES' — continuing anyway."
    fi

    # Save for next time
    printf 'DATA_FILES=%q\n' "$DATA_FILES" > "$CONFIG_FILE"
    echo "Saved. Edit $CONFIG_FILE to change it."
fi

echo ""
echo "OpenMW : $OPENMW"
echo "Data   : $DATA_FILES"
echo ""

exec "$SCRIPT_DIR/run_openmw.sh" "$OPENMW" \
    --data "$DATA_FILES" \
    --content Morrowind.esm \
    "$@"
