#!/bin/bash
# Buduje "Prosty Timer.app" ze zrodel w tym katalogu i instaluje w /Applications.
# Pakiet powstaje na bazie juz zainstalowanego (zachowuje Info.plist i ikone).
# Stara wersja ladu je w ~/Library/Application Support/ProstyTimer/kopie.
set -euo pipefail

SRC="$(cd "$(dirname "$0")" && pwd)"
APP="/Applications/Prosty Timer.app"
BACKUPS="$HOME/Library/Application Support/ProstyTimer/kopie"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "› kompiluje skrypt"
osacompile -o "$TMP/swiezy.app" "$SRC/Prosty Timer.applescript"

if [ -d "$APP" ]; then
  echo "› biore Info.plist i ikone z zainstalowanej wersji"
  cp -R "$APP" "$TMP/Prosty Timer.app"
  rm -rf "$TMP/Prosty Timer.app/Contents/_CodeSignature"
  cp "$TMP/swiezy.app/Contents/Resources/Scripts/main.scpt" \
     "$TMP/Prosty Timer.app/Contents/Resources/Scripts/main.scpt"
else
  echo "› brak zainstalowanej wersji, skladam pakiet od zera"
  mv "$TMP/swiezy.app" "$TMP/Prosty Timer.app"
  PL="$TMP/Prosty Timer.app/Contents/Info.plist"
  /usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier atyp.makers.timer.app" "$PL"
  /usr/libexec/PlistBuddy -c "Set :CFBundleName Prosty Timer" "$PL"
  [ -f "$SRC/Prosty timer.icns" ] && cp "$SRC/Prosty timer.icns" \
     "$TMP/Prosty Timer.app/Contents/Resources/applet.icns"
fi

# LSUIElement = agent w tle. Zwykla aplikacja nie ma tego klucza - inaczej nie
# widza jej narzedzia, ktore listuja aplikacje (np. mikser glosnosci Vorssaint).
echo "› kasuje LSUIElement (ma byc zwykla aplikacja)"
/usr/libexec/PlistBuddy -c "Delete :LSUIElement" \
  "$TMP/Prosty Timer.app/Contents/Info.plist" 2>/dev/null || true

# Ikona: szablon apletu niesie Assets.car z generyczna ikona zwoju o nazwie
# "applet", a CFBundleIconName wskazuje wlasnie na nia i wygrywa z applet.icns.
# Kasujemy klucz i katalog, zostaje CFBundleIconFile -> applet.icns.
echo "› ustawiam ikone"
cp "$SRC/Prosty timer.icns" "$TMP/Prosty Timer.app/Contents/Resources/applet.icns"
rm -f "$TMP/Prosty Timer.app/Contents/Resources/Assets.car"
/usr/libexec/PlistBuddy -c "Delete :CFBundleIconName" \
  "$TMP/Prosty Timer.app/Contents/Info.plist" 2>/dev/null || true

# ikona pakietu siedzi w applet.icns; plik Icon\r (widelec zasobow, 16 MB)
# jest zbedny, a codesign go nie przepuszcza
find "$TMP/Prosty Timer.app" -name "Icon"$'\r' -delete 2>/dev/null || true
xattr -cr "$TMP/Prosty Timer.app"

echo "› podpisuje ad-hoc"
codesign --force --sign - "$TMP/Prosty Timer.app"

if pgrep -f "Prosty Timer.app/Contents/MacOS/applet" >/dev/null; then
  echo "› zamykam dzialajaca aplikacje"
  osascript -e 'tell application id "atyp.makers.timer.app" to quit' 2>/dev/null || true
  sleep 1
  pkill -f "Prosty Timer.app/Contents/MacOS/applet" 2>/dev/null || true
fi

if [ -d "$APP" ]; then
  mkdir -p "$BACKUPS"
  STAMP="$(date +%Y-%m-%d-%H%M%S)"
  echo "› kopia zapasowa: $BACKUPS/Prosty Timer $STAMP.app"
  rm -rf "$BACKUPS/Prosty Timer $STAMP.app"
  ditto "$APP" "$BACKUPS/Prosty Timer $STAMP.app"
  rm -rf "$APP"
fi

ditto "$TMP/Prosty Timer.app" "$APP"

# odswiez pamiec podreczna ikon, inaczej Finder pokazuje stara
touch "$APP"
LSREG=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
[ -x "$LSREG" ] && "$LSREG" -f "$APP" || true

echo "› gotowe: $APP"
