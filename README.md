# Prosty timer

Timer na macOS: duże koło odliczające, alarm z własnym dźwiękiem, presety czasów
i ikona w pasku menu. Jedno okno, bez ustawień, których nikt nie czyta.

## W czym to jest zrobione

| Warstwa | Technologia |
| --- | --- |
| Interfejs | jeden plik `prosty timer.html` — czysty HTML + CSS + JavaScript (bez frameworków, bez zależności, bez sieci) |
| Dźwięk w przeglądarce | Web Audio API (`AudioContext`, `decodeAudioData`) |
| Pamięć ustawień | `localStorage` (presety, język, motyw, font, wybrany dźwięk) |
| Aplikacja macOS | `Prosty Timer.applescript` — AppleScriptObjC (AppleScript wołający wprost Cocoa: AppKit, WebKit, Foundation), zbudowany jako **zwykła aplikacja** — bez `LSUIElement`, więc widzą ją narzędzia listujące aplikacje (np. mikser głośności) |
| Okno aplikacji | `WKWebView` — natywne okno, w środku ta sama strona |
| Alarm w aplikacji | `NSSound` przez systemowe wyjście — głośnością zarządza mikser systemu |
| Pasek menu | `NSStatusItem` + `NSMenu`, odświeżane `NSTimer`-em |
| Budowanie | `zbuduj.sh` — `osacompile`, `PlistBuddy`, `codesign --sign -` (ad-hoc) |

Cały interfejs to około 730 linii HTML-a, aplikacja to około 650 linii
AppleScriptObjC. Zero bibliotek do pobrania — strona działa też sama z siebie,
otwarta w dowolnej przeglądarce.

## Jak strona rozmawia z aplikacją

WKWebView nie ma tu żadnego mostka JS↔AppleScript. Zamiast tego kanałem
sterowania jest **tytuł strony**: JavaScript dopisuje do `document.title`
neutralne językowo znaczniki, a aplikacja odczytuje go 10 razy na sekundę.

```
Prosty timer |L300,600      spoczynek + zapisane presety
12:34 |P                    pauza
00:00 |O |S2                po czasie, graj dźwięk numer 2
__PICK__                    strona prosi o okno wyboru plików
__PLAY__ |T… |S1            posłuchaj dźwięku numer 1
__RESET__                   wróć do dźwięku domyślnego
```

W drugą stronę aplikacja woła `evaluateJavaScript:` — stąd funkcje
`window.__cmd`, `window.__loadAlarms`, `window.__pickDone` w pliku HTML.
Dzięki temu polecenia z paska menu (Pauza, Wycisz, Wyzeruj) i wybór plików
z Findera trafiają do tej samej, jedynej logiki timera w JavaScripcie.

## Co potrafi

- odliczanie z kołem postępu, pauza, zerowanie, liczenie po czasie („po czasie”)
- własne dźwięki alarmu — pojedynczy plik albo cały folder z listą wyboru
- presety czasów zapisywane jednym przyciskiem
- 43 języki interfejsu, motyw jasny/ciemny
- font OpenDyslexic, jeśli jest zainstalowany w systemie

## Pliki

```
prosty timer.html        cała aplikacja: interfejs, logika, tłumaczenia
Prosty Timer.applescript źródło aplikacji macOS (AppleScriptObjC)
Prosty timer.icns        ikona aplikacji
zbuduj.sh                budowanie i instalacja w /Applications
```

## Uruchomienie

Sama strona — otwórz `prosty timer.html` w przeglądarce.

Aplikacja macOS:

```sh
./zbuduj.sh
```

Skrypt kompiluje AppleScript, składa pakiet `.app`, podpisuje go ad-hoc
i instaluje w `/Applications`. Poprzednia wersja ląduje w
`~/Library/Application Support/ProstyTimer/kopie`.
