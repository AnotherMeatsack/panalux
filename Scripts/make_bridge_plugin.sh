#!/usr/bin/env bash
# Builds Packaging/PanaLux Bridge.lrplugin from an official MIDI2LR plugin folder.
#
# PanaLux Bridge is MIDI2LR's Lightroom plugin (GPL-3.0) with four changes:
#   1. It does not launch the MIDI2LR desktop app (PanaLux takes that app's place).
#   2. The desktop app and its fonts are left out.
#   3. It has its own name and identifier so it can sit next to a regular MIDI2LR install.
#   4. PanaLuxRewind.lua is added and hooked into Client.lua: it reports which photo is on
#      screen and carries whole develop settings tables, which Rewind needs and MIDI2LR's
#      protocol does not have. The file is carried across a rebuild, not regenerated.
# The .lua files are the plugin's complete source. LICENSE.txt and NOTICE.txt ship with it.
#
# Usage: Scripts/make_bridge_plugin.sh /path/to/MIDI2LR.lrplugin
set -euo pipefail

SRC="${1:?path to MIDI2LR.lrplugin}"
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="${DIR}/Packaging/PanaLux Bridge.lrplugin"

# PanaLux's own addition lives in the built plugin; keep it across the rebuild.
KEEP="$(mktemp -d)"
trap 'rm -rf "$KEEP"' EXIT
if [ -f "$OUT/PanaLuxRewind.lua" ]; then
  cp "$OUT/PanaLuxRewind.lua" "$KEEP/"
else
  echo "error: $OUT/PanaLuxRewind.lua is missing; it is not generated, it is kept in git" >&2
  exit 1
fi

rm -rf "$OUT"
mkdir -p "$OUT"
rsync -a --exclude 'MIDI2LR.app' --exclude '*.ttf' --exclude '*.otf' --exclude 'OFL.txt' \
      --exclude 'MIDI2LR.exe' --exclude '.DS_Store' "$SRC/" "$OUT/"
cp "$KEEP/PanaLuxRewind.lua" "$OUT/"
chmod 644 "$OUT"/*

VERSION="$(sed -n 's/.*VERSION = { major=\([0-9]*\), minor=\([0-9]*\), revision=\([0-9]*\), build=\([0-9]*\)}.*/\1.\2.\3.\4/p' "$OUT/Info.lua")"

python3 - "$OUT" <<'PY'
import re, sys, pathlib
out = pathlib.Path(sys.argv[1])

client = out / "Client.lua"
s = client.read_text(encoding="utf-8")
launch = re.compile(
    r"\n(\s*)if WIN_ENV then\n\s*LrShell\.openFilesInApp\(\{LrPathUtils\.child\(_PLUGIN\.path, 'Info\.lua'\)\}, "
    r"LrPathUtils\.child\(_PLUGIN\.path, 'MIDI2LR\.exe'\)\)\n\s*else\n\s*LrShell\.openFilesInApp\(\{LrPathUtils\.child\(_PLUGIN\.path, 'Info\.lua'\)\}, "
    r"LrPathUtils\.child\(_PLUGIN\.path, 'MIDI2LR\.app'\)\)\n\s*end\n")
s, n = launch.subn(r"\n\1-- PanaLux Bridge: the PanaLux app connects on its own; don't launch the MIDI2LR app.\n", s)
assert n == 1, f"expected one app launch block in Client.lua, found {n}"

# Rewind needs the plugin to say which photo is on screen and to hand over whole develop
# settings tables. Both live in PanaLuxRewind.lua; these are the four lines that reach it.
s, n = re.subn(r"\n(\s*)local Presets( *)= require 'Presets'\n",
               r"\n\1local PanaLuxRewind   = require 'PanaLuxRewind' -- PanaLux Bridge: trail recording\n"
               r"\1local Presets\2= require 'Presets'\n", s)
assert n == 1, f"expected one Presets require in Client.lua, found {n}"

s, n = re.subn(r"\n(\s*)ProfileAmount( *)= CU\.ProfileAmount,\n",
               r"\n\1-- PanaLux Bridge: whole develop settings tables, for Rewind's keyframes.\n"
               r"\1PanaLuxSnapshot     = function(value) PanaLuxRewind.SendSnapshot(value) end,\n"
               r"\1PanaLuxRestoreBegin = function() PanaLuxRewind.RestoreBegin() end,\n"
               r"\1PanaLuxRestoreChunk = function(value) PanaLuxRewind.RestoreChunk(value) end,\n"
               r"\1PanaLuxRestoreEnd   = function() PanaLuxRewind.RestoreEnd() end,\n"
               r"\1PanaLuxProbe        = function() PanaLuxRewind.Probe() end,\n"
               r"\1ProfileAmount\2= CU.ProfileAmount,\n", s)
assert n == 1, f"expected one ProfileAmount setting in Client.lua, found {n}"

s, n = re.subn(r"\n(\s*)Profiles\.checkProfile\(\)\n",
               r"\n\1Profiles.checkProfile()\n"
               r"\1PanaLuxRewind.PushSelection() -- PanaLux Bridge: tell PanaLux which photo is on screen\n", s)
assert n == 2, f"expected two idle loops in Client.lua, found {n}"

client.write_text(s, encoding="utf-8")

info = out / "Info.lua"
s = info.read_text(encoding="utf-8")
s = s.replace("LrPluginName = 'MIDI2LR'", "LrPluginName = 'PanaLux Bridge (based on MIDI2LR)'")
s = s.replace("LrToolkitIdentifier = 'com.rsjaffe.midi2lr'", "LrToolkitIdentifier = 'app.panalux.bridge'")
for menu in ("LaunchServer.lua", "StopServer.lua"):
    s, n = re.subn(r"\n\s*\{\n[^{}]*file = \"%s\"\n\s*\},?" % re.escape(menu), "", s)
    assert n == 1, menu
s = s.replace("Info.lua\nMIDI2LR Plugin properties", "Info.lua\nMIDI2LR Plugin properties\n\nModified for PanaLux Bridge; see NOTICE.txt.")
assert "app.panalux.bridge" in s
info.write_text(s, encoding="utf-8")
PY

cat > "$OUT/NOTICE.txt" <<TXT
PanaLux Bridge

This Lightroom Classic plugin is a modified version of the MIDI2LR plugin
${VERSION}, copyright 2015 Rory Jaffe and contributors, distributed under the
GNU General Public License version 3 (see LICENSE.txt).

Changes made for PanaLux:
  - Client.lua no longer launches the MIDI2LR desktop application.
  - PanaLuxRewind.lua is added, and Client.lua calls it: it reports the selected photo and
    carries whole develop settings tables so PanaLux can record and replay an editing session.
  - Info.lua uses the name "PanaLux Bridge (based on MIDI2LR)" and the
    identifier app.panalux.bridge, and drops the Start/Close application menu items.
  - The MIDI2LR desktop application and its bundled fonts are not included.

The .lua files in this folder are the complete source of this plugin.
Upstream project and original source: https://github.com/rsjaffe/MIDI2LR

MIDI2LR is not affiliated with PanaLux. Please support the original project.
TXT

echo "Built ${OUT} from MIDI2LR ${VERSION}"
