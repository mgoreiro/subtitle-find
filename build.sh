#!/bin/zsh
# Compila en release y empaqueta build/SubtitleFind.app (firma ad-hoc).
set -e
cd "$(dirname "$0")"
swift build -c release
APP=build/SubtitleFind.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/SubtitleFind "$APP/Contents/MacOS/"
cp Resources/Info.plist "$APP/Contents/"
cp Resources/AppIcon.icns "$APP/Contents/Resources/"
cp -R Resources/en.lproj Resources/es.lproj "$APP/Contents/Resources/"
codesign --force --sign - "$APP"
echo "OK -> $PWD/$APP"
