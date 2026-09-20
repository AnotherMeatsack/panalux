#!/usr/bin/env bash
# Package an already built app and generate a signed Sparkle feed. Does not publish.
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="${1:?Usage: prepare_update.sh /path/to/PanaLux.app /path/to/output}"
OUT="${2:?Provide an empty output directory}"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$APP/Contents/Info.plist")"
TOOLS="$DIR/.build/artifacts/sparkle/Sparkle/bin"
mkdir -p "$OUT"
ARCHIVE="$OUT/PanaLux-${VERSION}.zip"
if [[ -e "$ARCHIVE" || -e "$OUT/appcast.xml" ]]; then
  echo 'Refusing to replace an existing archive or feed; use a new output directory.' >&2
  exit 1
fi
codesign --verify --deep --strict "$APP"
PUBLIC_KEY="$("$TOOLS/generate_keys" --account panalux -p)"
BUNDLED_KEY="$(/usr/libexec/PlistBuddy -c 'Print SUPublicEDKey' "$APP/Contents/Info.plist")"
[[ "$PUBLIC_KEY" == "$BUNDLED_KEY" ]] || { echo 'Signing key does not match app public key.' >&2; exit 1; }
# Use the notes from the exact staged app, not a potentially newer working tree.
NOTES="$APP/Contents/Resources/ReleaseNotes.md"
[[ -s "$NOTES" ]] || { echo 'Release notes are required for every update.' >&2; exit 1; }
python3 - "$NOTES" "$OUT/PanaLux-${VERSION}.html" "$VERSION" <<'PYNOTES'
import html, pathlib, re, sys
notes = pathlib.Path(sys.argv[1]).read_text()
assert notes.startswith("# PanaLux v" + sys.argv[3] + "\n"), "Release notes must start with the packaged version"
latest = notes.split("\n---\n", 1)[0]
def inline(text):
    return re.sub(r"\*\*(.+?)\*\*", r"<strong>\1</strong>", html.escape(text))
parts = []
for paragraph in latest.strip().split("\n\n"):
    if paragraph.startswith("# "):
        parts.append("<h2>" + html.escape(paragraph[2:]) + "</h2>")
    elif paragraph.startswith("- "):
        parts.append("<ul>" + "".join("<li><p>" + inline(line[2:]) + "</p></li>" for line in paragraph.splitlines()) + "</ul>")
    else:
        parts.append("<p>" + inline(paragraph).replace("\n", "<br>") + "</p>")
pathlib.Path(sys.argv[2]).write_text("\n".join(parts))
PYNOTES
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ARCHIVE"
"$TOOLS/generate_appcast" --account panalux --maximum-deltas 0 --embed-release-notes \
  --download-url-prefix "https://github.com/AnotherMeatsack/panalux/releases/download/v${VERSION}/" "$OUT"
echo "Prepared signed update: $ARCHIVE"
echo "Publish the archive and appcast.xml together on the new GitHub release."
