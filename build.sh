#!/bin/bash
# Buduje "Timer.app" ze zrodel w Sources/, sklada Timer.zip do pobrania
# i instaluje w /Applications.
# W Finderze, Docku i menu aplikacja nazywa sie jak timer w Zegarze macOS,
# w jezyku systemu: "Minutnik", "Timer", "Minuteur"...
set -euo pipefail
cd "$(dirname "$0")"

NAME="Timer"
ID="atyp.makers.timer.app"
APP="/Applications/$NAME.app"
TMP="$(mktemp -d)"
NEW="$TMP/$NAME.app"
trap 'rm -rf "$TMP"' EXIT

echo "› kompiluje"
mkdir -p "$NEW/Contents/MacOS" "$NEW/Contents/Resources"
swiftc -O -swift-version 5 -default-isolation MainActor \
	-target arm64-apple-macos26.0 \
	Sources/*.swift -o "$NEW/Contents/MacOS/$NAME"

# Ikona jak systemowe w macOS 26/27: warstwy z Icon Composera (Timer.icon), ktore
# system sam pokrywa szklem i przestawia na style z Ustawien -> Wyglad (ciemny,
# przejrzysty, matowy). actool z Xcode sklada z nich Assets.car oraz zapasowy
# Timer.icns dla starszych miejsc.
# actool pamieta wyrenderowana ikone po sciezce pliku i przy tej samej sciezce nie widzi
# zmian w warstwach - dlatego kompiluje kopie z jednorazowego katalogu.
echo "› ikona"
cp -R "$NAME.icon" "$TMP/$NAME.icon"
xcrun actool "$TMP/$NAME.icon" --compile "$NEW/Contents/Resources" \
	--platform macosx --minimum-deployment-target 26.0 --app-icon "$NAME" \
	--output-partial-info-plist "$TMP/ikona.plist" >/dev/null

# Nazwa bazowa "Timer" musi zgadzac sie z nazwa pakietu na dysku (Timer.app) -
# inaczej Finder uznaje, ze pakiet zostal przemianowany recznie, i pokazuje sama
# nazwe pliku zamiast tlumaczenia. Tak samo lezy Zegar: Clock.app, widoczny
# jako "Zegar".
echo "› Info.plist"
cat > "$NEW/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleName</key><string>$NAME</string>
	<key>CFBundleDisplayName</key><string>$NAME</string>
	<key>LSHasLocalizedDisplayName</key><true/>
	<key>CFBundleDevelopmentRegion</key><string>en</string>
	<key>CFBundleExecutable</key><string>$NAME</string>
	<key>CFBundleIconFile</key><string>$NAME</string>
	<key>CFBundleIconName</key><string>$NAME</string>
	<key>CFBundleIdentifier</key><string>$ID</string>
	<key>CFBundlePackageType</key><string>APPL</string>
	<key>CFBundleShortVersionString</key><string>2.0</string>
	<key>CFBundleVersion</key><string>2</string>
	<key>LSMinimumSystemVersion</key><string>26.0</string>
	<key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
	<key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

# Tlumaczenia nazwy bierzemy od Apple: slowo "Timer" (klucz TIMER) z Zegara,
# w kazdym jezyku, w jakim jest macOS - bez wlasnych tlumaczen.
echo "› nazwa w jezyku systemu"
CLOCK=/System/Applications/Clock.app/Contents/Resources/Localizable.loctable
if [ -f "$CLOCK" ]; then
	for L in ar ca cs da de el en en_AU en_CA en_GB en_PH es es_419 es_US fi fr fr_CA \
	         he hi hr hu id it ja ko ms nl no pl pt_BR pt_PT ro ru sk sl sv th tr uk vi \
	         zh_CN zh_HK zh_TW; do
		T="$(plutil -extract "$L.TIMER" raw -o - "$CLOCK" 2>/dev/null)" || continue
		mkdir -p "$NEW/Contents/Resources/$L.lproj"
		printf '"CFBundleName" = "%s";\n"CFBundleDisplayName" = "%s";\n' "$T" "$T" \
			> "$NEW/Contents/Resources/$L.lproj/InfoPlist.strings"
	done
	echo "  $(ls -d "$NEW"/Contents/Resources/*.lproj | wc -l | tr -d ' ') jezykow, po polsku: $(plutil -extract pl.TIMER raw -o - "$CLOCK")"
else
	echo "  brak Zegara macOS - zostaje sama nazwa \"$NAME\""
fi

echo "› podpisuje ad-hoc"
codesign --force --sign - "$NEW"

# paczka do pobrania: rozpakowac i przeciagnac Timer.app do Aplikacji
echo "› Timer.zip"
rm -f "$NAME.zip"
ditto -c -k --keepParent "$NEW" "$NAME.zip"

if pgrep -f "$APP/Contents/MacOS/$NAME" >/dev/null; then
	echo "› zamykam dzialajaca aplikacje"
	osascript -e "tell application id \"$ID\" to quit" 2>/dev/null || true
	sleep 1
fi

echo "› instaluje w /Applications"
rm -rf "$APP"
ditto "$NEW" "$APP"
# odswiez pamiec podreczna ikon i nazw, inaczej Finder pokazuje stare
touch "$APP"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$APP" || true
echo "› gotowe: $APP"
