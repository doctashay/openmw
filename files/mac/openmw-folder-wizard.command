#!/bin/sh
SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"

if [ -f "$SCRIPT_DIR/openmw_folder_wizard.py" ]; then
    PYTHON_SCRIPT="$SCRIPT_DIR/openmw_folder_wizard.py"
else
    PYTHON_SCRIPT="$SCRIPT_DIR/../../scripts/openmw_folder_wizard.py"
fi

if command -v python >/dev/null 2>&1; then
    PYTHON=python
elif command -v python3 >/dev/null 2>&1; then
    PYTHON=python3
else
    echo "Python is required to run the OpenMW folder wizard."
    exit 1
fi

"$PYTHON" "$PYTHON_SCRIPT" "$@"
STATUS=$?

if [ -z "$1" ]; then
    echo
    echo "Drag a Morrowind folder or Data Files folder onto this script to use it directly."
fi

echo
echo "Press Return to close."
read dummy
exit "$STATUS"
