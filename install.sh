#!/bin/zsh
# Compila, cierra la app si está abierta, la instala en /Applications y la abre.
set -e
cd "$(dirname "$0")"
./build.sh
DEST=/Applications/SubtitleFind.app
pkill -x SubtitleFind 2>/dev/null && sleep 1 || true
rm -rf "$DEST"
ditto build/SubtitleFind.app "$DEST"
xattr -cr "$DEST"
codesign -v "$DEST"
echo "Instalada en $DEST"
open "$DEST"
