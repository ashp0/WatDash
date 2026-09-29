#!/bin/bash
# Builds a Release WatDash, installs it into /Applications (or ~/Applications
# when /Applications isn't writable) and launches it.
#
# Widgets are registered from wherever the app lives, so build copies in
# DerivedData are unregistered first — otherwise the widget gallery shows
# each widget twice.
set -euo pipefail
cd "$(dirname "$0")/.."

# --no-launch: install without quitting a running copy or opening the new one.
LAUNCH=1
[ "${1:-}" = "--no-launch" ] && LAUNCH=0

python3 Tools/generate_project.py >/dev/null
xcodebuild -project WatDash.xcodeproj -scheme WatDash -configuration Release \
  -derivedDataPath build/DerivedData build | grep -E "error:|BUILD" || true

BUILT="build/DerivedData/Build/Products/Release/WatDash.app"
[ -d "$BUILT" ] || { echo "Build failed"; exit 1; }

DEST="/Applications"
[ -w "$DEST" ] || DEST="$HOME/Applications"
mkdir -p "$DEST"

if [ "$LAUNCH" = 1 ]; then
  osascript -e 'quit app "WatDash"' 2>/dev/null || true
  pkill -f "WatDash.app/Contents/MacOS/WatDash" 2>/dev/null || true
  sleep 1
fi

for copy in build/DerivedData/Build/Products/*/WatDash.app; do
  pluginkit -r "$copy/Contents/PlugIns/WatDashWidgets.appex" 2>/dev/null || true
done

rm -rf "$DEST/WatDash.app"
ditto "$BUILT" "$DEST/WatDash.app"
pluginkit -a "$DEST/WatDash.app/Contents/PlugIns/WatDashWidgets.appex" 2>/dev/null || true
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$DEST/WatDash.app"

[ "$LAUNCH" = 1 ] && open "$DEST/WatDash.app"
echo "Installed $DEST/WatDash.app"
