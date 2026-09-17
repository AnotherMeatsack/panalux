#!/usr/bin/env bash
# Builds Packaging/PanaLux Bridge.lrplugin from an official MIDI2LR plugin folder.
#
# PanaLux Bridge is MIDI2LR's Lightroom plugin (GPL-3.0) with three changes:
#   1. It does not launch the MIDI2LR desktop app (PanaLux takes that app's place).
#   2. The desktop app and its fonts are left out.
#   3. It has its own name and identifier so it can sit next to a regular MIDI2LR install.
# The .lua files are the plugin's complete source. LICENSE.txt and NOTICE.txt ship with it.
#
# Usage: Scripts/make_bridge_plugin.sh /path/to/MIDI2LR.lrplugin
set -euo pipefail

SRC="${1:?path to MIDI2LR.lrplugin}"
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="${DIR}/Packaging/PanaLux Bridge.lrplugin"

rm -rf "$OUT"
mkdir -p "$OUT"
rsync -a --exclude 'MIDI2LR.app' --exclude '*.ttf' --exclude '*.otf' --exclude 'OFL.txt' \
      --exclude 'MIDI2LR.exe' --exclude '.DS_Store' "$SRC/" "$OUT/"
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
  - Info.lua uses the name "PanaLux Bridge (based on MIDI2LR)" and the
    identifier app.panalux.bridge, and drops the Start/Close application menu items.
  - The MIDI2LR desktop application and its bundled fonts are not included.

The .lua files in this folder are the complete source of this plugin.
Upstream project and original source: https://github.com/rsjaffe/MIDI2LR

MIDI2LR is not affiliated with PanaLux. Please support the original project.
TXT

echo "Built ${OUT} from MIDI2LR ${VERSION}"
