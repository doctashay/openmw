#!/bin/sh
SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
APP_BUNDLE="$SCRIPT_DIR/OpenMW.app"

if [ -f "$SCRIPT_DIR/openmw_folder_wizard.py" ]; then
    PYTHON_SCRIPT="$SCRIPT_DIR/openmw_folder_wizard.py"
elif [ -f "$APP_BUNDLE/Contents/Resources/openmw_folder_wizard.py" ]; then
    PYTHON_SCRIPT="$APP_BUNDLE/Contents/Resources/openmw_folder_wizard.py"
else
    PYTHON_SCRIPT="$SCRIPT_DIR/../../scripts/openmw_folder_wizard.py"
fi

if [ -f "$SCRIPT_DIR/First Time Setup.applescript" ]; then
    APPLESCRIPT="$SCRIPT_DIR/First Time Setup.applescript"
elif [ -f "$APP_BUNDLE/Contents/Resources/First Time Setup.applescript" ]; then
    APPLESCRIPT="$APP_BUNDLE/Contents/Resources/First Time Setup.applescript"
else
    APPLESCRIPT="$SCRIPT_DIR/../../files/mac/First Time Setup.applescript"
fi

if [ -d "$APP_BUNDLE" ]; then
    osascript "$APPLESCRIPT" "$PYTHON_SCRIPT" "$APP_BUNDLE" "$@"
else
    osascript "$APPLESCRIPT" "$PYTHON_SCRIPT" "$@"
fi
STATUS=$?

echo
echo "Press Return to close."
read dummy
exit "$STATUS"
