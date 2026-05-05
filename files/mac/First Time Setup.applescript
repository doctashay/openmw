on open droppedItems
    runSetup(droppedItems, missing value)
end open

on run argv
    runSetup(argv, missing value)
end run

on runSetup(inputItems, overrideScript)
    set itemCount to count of inputItems
    set folderPath to missing value
    set appBundle to ""
    set pythonScript to ""

    if itemCount is 0 then
        set pythonScript to my resolvePythonScript(overrideScript, "")
        set appBundle to my resolveAppBundle("")
        set folderPath to my chooseFolderPath()
    else if itemCount is 1 then
        set firstItem to item 1 of inputItems
        if class of firstItem is alias then
            set folderPath to POSIX path of firstItem
        else
            set folderPath to firstItem
        end if
        set pythonScript to my resolvePythonScript(overrideScript, "")
    else
        set pythonScript to item 1 of inputItems
        set appBundle to my resolveAppBundle(item 2 of inputItems)
        if itemCount is 2 then
            set folderPath to my chooseFolderPath()
        else
            set folderPath to item 3 of inputItems
        end if
    end if

    if folderPath is missing value or folderPath is "" then
        return
    end if

    set promptText to "Enable Tribunal and Bloodmoon if they are present?"
    set choice to button returned of (display dialog promptText buttons {"No", "Yes"} default button "Yes")
    set noDLCFlag to ""
    if choice is "No" then
        set noDLCFlag to " --no-dlc"
    end if

    set iniPromptText to "Import settings from Morrowind.ini if one is found?"
    set iniChoice to button returned of (display dialog iniPromptText buttons {"No", "Yes"} default button "No")
    set iniImportFlag to " --skip-ini-import"
    if iniChoice is "Yes" then
        set iniImportFlag to ""
    end if

    if pythonScript is "" then
        display dialog "Could not locate openmw_folder_wizard.py." buttons {"OK"} default button "OK" with icon stop
        return
    end if

    set appFlag to ""
    if appBundle is not "" then
        set appFlag to " --app-dir " & quoted form of appBundle
    end if

    set shellCommand to "python_bin=$(command -v python || command -v python3); if [ -z \"$python_bin\" ]; then echo 'Python is required to run the OpenMW setup wizard.' >&2; exit 1; fi; \"$python_bin\" " & quoted form of pythonScript & appFlag & noDLCFlag & iniImportFlag & " " & quoted form of folderPath

    try
        set outputText to do shell script shellCommand
        if outputText is not "" then
            display dialog outputText buttons {"OK"} default button "OK"
        else
            display dialog "OpenMW has been configured." buttons {"OK"} default button "OK"
        end if
    on error errMsg number errNum
        display dialog errMsg buttons {"OK"} default button "OK" with icon stop
    end try
end runSetup

on chooseFolderPath()
    try
        return POSIX path of (choose folder with prompt "Select your Morrowind folder or Data Files folder")
    on error
        return missing value
    end try
end chooseFolderPath

on resolveAppBundle(rawPath)
    if rawPath is not "" then
        set candidate to rawPath
        if candidate ends with "/" then
            set candidate to text 1 thru -2 of candidate
        end if
        if candidate ends with ".app" then
            return candidate
        end if
    end if

    try
        set scriptPath to POSIX path of (path to me)
        if scriptPath ends with ".app/" then
            set candidate to text 1 thru -2 of scriptPath
            return candidate
        end if
        set scriptDir to do shell script "dirname " & quoted form of scriptPath
        set siblingApp to scriptDir & "/OpenMW.app"
        do shell script "test -d " & quoted form of siblingApp
        return siblingApp
    on error
        return ""
    end try
end resolveAppBundle

on resolvePythonScript(overrideScript, appBundle)
    if overrideScript is not missing value then
        return overrideScript
    end if

    try
        set resourcePath to POSIX path of (path to resource "openmw_folder_wizard.py")
        return resourcePath
    end try

    try
        if appBundle is not "" then
            return appBundle & "/Contents/Resources/openmw_folder_wizard.py"
        end if
    end try

    try
        set resolvedBundle to my resolveAppBundle("")
        if resolvedBundle is not "" then
            return resolvedBundle & "/Contents/Resources/openmw_folder_wizard.py"
        end if
    end try

    return ""
end resolvePythonScript
