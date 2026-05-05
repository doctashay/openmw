#!/usr/bin/env python
#
# Lightweight replacement for the Qt launcher wizard on older macOS/PPC setups.
# Accepts a Morrowind install root or Data Files folder, updates openmw.cfg,
# and imports Morrowind.ini through openmw-iniimporter when available.

from __future__ import print_function

import os
import shutil
import subprocess
import sys
import time

try:
    from optparse import OptionParser
except ImportError:
    OptionParser = None


MARKER_BEGIN = "# BEGIN OPENMW FOLDER WIZARD"
MARKER_END = "# END OPENMW FOLDER WIZARD"


def is_macos():
    return sys.platform == "darwin"


def quote_cfg_path(path):
    return '"' + path.replace('"', '\\"') + '"'


def default_config_dir():
    home = os.path.expanduser("~")
    if is_macos():
        return os.path.join(home, "Library", "Preferences", "openmw")
    return os.path.join(home, ".config", "openmw")


def default_user_data_dir():
    home = os.path.expanduser("~")
    if is_macos():
        return os.path.join(home, "Library", "Preferences", "openmw")
    return os.path.join(home, ".local", "share", "openmw")


def choose_folder_with_osascript():
    script = 'POSIX path of (choose folder with prompt "Select your Morrowind folder or Data Files folder")'
    try:
        proc = subprocess.Popen(
            ["osascript", "-e", script], stdout=subprocess.PIPE, stderr=subprocess.PIPE
        )
        out, _err = proc.communicate()
    except OSError:
        return None
    if proc.returncode != 0:
        return None
    if not isinstance(out, str):
        out = out.decode("utf-8", "replace")
    out = out.strip()
    return out or None


def normalize_path(path):
    return os.path.normpath(os.path.abspath(os.path.expanduser(path)))


def has_morrowind_core_files(path):
    names = set([name.lower() for name in os.listdir(path)])
    return "morrowind.esm" in names and "morrowind.bsa" in names


def resolve_data_files_dir(path):
    path = normalize_path(path)
    if not os.path.isdir(path):
        raise RuntimeError("Folder does not exist: %s" % path)

    if has_morrowind_core_files(path):
        return path

    candidate = os.path.join(path, "Data Files")
    if os.path.isdir(candidate) and has_morrowind_core_files(candidate):
        return normalize_path(candidate)

    raise RuntimeError("Could not find Morrowind.esm and Morrowind.bsa in %s" % path)


def detect_game_files(data_files_dir, include_dlc=True):
    names = set([name.lower() for name in os.listdir(data_files_dir)])
    content = ["Morrowind.esm"]
    if include_dlc:
        if "tribunal.esm" in names and "tribunal.bsa" in names:
            content.append("Tribunal.esm")
        if "bloodmoon.esm" in names and "bloodmoon.bsa" in names:
            content.append("Bloodmoon.esm")
    return content


def detect_ini_path(data_files_dir):
    candidates = [
        os.path.join(data_files_dir, "Morrowind.ini"),
        os.path.join(os.path.dirname(data_files_dir), "Morrowind.ini"),
    ]
    for candidate in candidates:
        if os.path.isfile(candidate):
            return candidate
    return None


def find_executable(name, extra_dirs):
    for directory in extra_dirs:
        if not directory:
            continue
        candidate = os.path.join(directory, name)
        if os.path.isfile(candidate) and os.access(candidate, os.X_OK):
            return candidate
    path_value = os.environ.get("PATH", "")
    for directory in path_value.split(os.pathsep):
        if not directory:
            continue
        candidate = os.path.join(directory, name)
        if os.path.isfile(candidate) and os.access(candidate, os.X_OK):
            return candidate
    return None


def strip_existing_wizard_block(lines):
    result = []
    inside = False
    for line in lines:
        stripped = line.rstrip("\r\n")
        if stripped == MARKER_BEGIN:
            inside = True
            continue
        if stripped == MARKER_END:
            inside = False
            continue
        if not inside:
            result.append(line)
    return result


def rewrite_openmw_cfg(cfg_path, data_files_dir, content_files, user_data_dir):
    existing = []
    if os.path.isfile(cfg_path):
        stream = open(cfg_path, "r")
        try:
            existing = stream.readlines()
        finally:
            stream.close()

    existing = strip_existing_wizard_block(existing)

    filtered = []
    content_lower = set([name.lower() for name in content_files])
    normalized_data_dir = normalize_path(data_files_dir)
    for line in existing:
        stripped = line.strip()
        lower = stripped.lower()
        if lower.startswith("content="):
            value = stripped.split("=", 1)[1].strip().strip('"')
            if value.lower() in content_lower:
                continue
        if lower.startswith("data="):
            value = stripped.split("=", 1)[1].strip().strip('"')
            if normalize_path(value) == normalized_data_dir:
                continue
        if lower.startswith("user-data="):
            continue
        filtered.append(line)

    while filtered and not filtered[-1].strip():
        filtered.pop()

    block = [MARKER_BEGIN + "\n"]
    block.append("user-data=%s\n" % quote_cfg_path(user_data_dir))
    block.append("data=%s\n" % quote_cfg_path(data_files_dir))
    for content in content_files:
        block.append("content=%s\n" % content)
    block.append(MARKER_END + "\n")

    out = open(cfg_path, "w")
    try:
        if filtered:
            out.writelines(filtered)
            out.write("\n")
        out.writelines(block)
    finally:
        out.close()


def ensure_settings_cfg(settings_path, encoding):
    existing = []
    if os.path.isfile(settings_path):
        stream = open(settings_path, "r")
        try:
            existing = stream.readlines()
        finally:
            stream.close()

    if encoding is None:
        return

    section = "[General]"
    key = "encoding"
    result = []
    in_general = False
    seen_general = False
    wrote_key = False

    for line in existing:
        stripped = line.strip()
        if stripped.startswith("[") and stripped.endswith("]"):
            if in_general and not wrote_key:
                result.append("%s = %s\n" % (key, encoding))
                wrote_key = True
            in_general = stripped.lower() == section.lower()
            if in_general:
                seen_general = True
            result.append(line)
            continue

        if in_general and stripped.lower().startswith(key + " ="):
            if not wrote_key:
                result.append("%s = %s\n" % (key, encoding))
                wrote_key = True
            continue

        result.append(line)

    if not seen_general:
        if result and result[-1].strip():
            result.append("\n")
        result.append(section + "\n")
        result.append("%s = %s\n" % (key, encoding))
    elif in_general and not wrote_key:
        result.append("%s = %s\n" % (key, encoding))

    out = open(settings_path, "w")
    try:
        out.writelines(result)
    finally:
        out.close()


def backup_file(path):
    if not os.path.isfile(path):
        return None
    stamp = time.strftime("%Y%m%d-%H%M%S")
    backup = path + ".bak." + stamp
    shutil.copy2(path, backup)
    return backup


def run_ini_importer(importer_path, ini_path, cfg_path, encoding):
    command = [importer_path, "--game-files", "--fonts", "--ini", ini_path, "--cfg", cfg_path]
    if encoding:
        command.extend(["--encoding", encoding])
    proc = subprocess.Popen(command)
    return proc.wait()


def parse_args(argv):
    if OptionParser is None:
        raise RuntimeError("optparse is unavailable")

    parser = OptionParser(
        usage="%prog [options] [Morrowind folder or Data Files folder]",
        description="Small script-based setup wizard for OpenMW on older macOS/PPC builds.",
    )
    parser.add_option("--config-dir", dest="config_dir", default=default_config_dir())
    parser.add_option("--user-data-dir", dest="user_data_dir", default=default_user_data_dir())
    parser.add_option("--encoding", dest="encoding", default="win1252")
    parser.add_option("--skip-ini-import", action="store_true", dest="skip_ini_import", default=False)
    parser.add_option("--no-dlc", action="store_true", dest="no_dlc", default=False)
    parser.add_option("--importer", dest="importer_path", default=None)
    parser.add_option("--app-dir", dest="app_dir", default=None)
    parser.add_option("--no-choose-folder", action="store_true", dest="no_choose_folder", default=False)
    options, args = parser.parse_args(argv)
    folder = args[0] if args else None
    return options, folder


def main(argv):
    options, folder = parse_args(argv)

    if folder is None and is_macos() and not options.no_choose_folder:
        folder = choose_folder_with_osascript()

    if folder is None:
        print("No folder provided.")
        return 1

    data_files_dir = resolve_data_files_dir(folder)
    content_files = detect_game_files(data_files_dir, include_dlc=not options.no_dlc)
    ini_path = detect_ini_path(data_files_dir)

    config_dir = normalize_path(options.config_dir)
    user_data_dir = normalize_path(options.user_data_dir)
    if not os.path.isdir(config_dir):
        os.makedirs(config_dir)
    if not os.path.isdir(user_data_dir):
        os.makedirs(user_data_dir)

    cfg_path = os.path.join(config_dir, "openmw.cfg")
    settings_path = os.path.join(config_dir, "settings.cfg")

    cfg_backup = backup_file(cfg_path)
    settings_backup = backup_file(settings_path)

    rewrite_openmw_cfg(cfg_path, data_files_dir, content_files, user_data_dir)
    ensure_settings_cfg(settings_path, options.encoding)

    script_dir = os.path.dirname(os.path.abspath(__file__))
    app_dir = normalize_path(options.app_dir) if options.app_dir else None
    app_parent_dir = os.path.dirname(app_dir) if app_dir else None
    app_resources_dir = None
    app_macos_dir = None
    if app_dir:
        app_resources_dir = os.path.join(app_dir, "Contents", "Resources")
        app_macos_dir = os.path.join(app_dir, "Contents", "MacOS")
    extra_dirs = [
        app_parent_dir,
        os.path.dirname(script_dir),
        script_dir,
        app_resources_dir,
        app_macos_dir,
        os.path.join(app_parent_dir, "build_test") if app_parent_dir else None,
        os.path.join(os.path.dirname(script_dir), "build_test"),
        os.path.join(os.path.dirname(script_dir), "build"),
        os.path.join(os.path.dirname(script_dir), "install"),
    ]

    importer_path = options.importer_path or find_executable("openmw-iniimporter", extra_dirs)
    imported_ini = False

    if ini_path and importer_path and not options.skip_ini_import:
        rc = run_ini_importer(importer_path, ini_path, cfg_path, options.encoding)
        if rc != 0:
            print("Warning: openmw-iniimporter exited with code %s" % rc)
        else:
            imported_ini = True

    print("Configured OpenMW for: %s" % data_files_dir)
    print("Content files: %s" % ", ".join(content_files))
    if options.no_dlc:
        print("DLC auto-detection disabled by user choice.")
    print("openmw.cfg: %s" % cfg_path)
    if cfg_backup:
        print("Backup: %s" % cfg_backup)
    if settings_backup:
        print("Settings backup: %s" % settings_backup)
    if ini_path:
        if imported_ini:
            print("Imported Morrowind.ini from: %s" % ini_path)
        elif options.skip_ini_import:
            print("Skipped Morrowind.ini import: %s" % ini_path)
        else:
            print("Morrowind.ini found but importer was not available: %s" % ini_path)
    else:
        print("No Morrowind.ini found next to the installation.")

    return 0


if __name__ == "__main__":
    try:
        sys.exit(main(sys.argv[1:]))
    except Exception as error:
        print("ERROR: %s" % error)
        sys.exit(1)
