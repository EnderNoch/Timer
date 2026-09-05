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
| Szkło | kontrolki rysuje CSS; opcjonalne szkło na całe okno to `NSGlassEffectView` (macOS 26) z zapasowym `NSVisualEffectView` |
| Alarm w aplikacji | `NSSound` przez systemowe wyjście — głośnością zarządza mikser systemu |
| Pasek menu | `NSStatusItem` + `NSMenu`, odświeżane komunikatem ze strony |
| Budowanie | `zbuduj.sh` — `osacompile`, `PlistBuddy`, `codesign --sign -` (ad-hoc) |

Cały interfejs to około 730 linii HTML-a, aplikacja to około 650 linii
AppleScriptObjC. Zero bibliotek do pobrania — strona działa też sama z siebie,
otwarta w dowolnej przeglądarce.

## Szkło

Apple rozpisuje szkło jako **warstwę pływającą nad treścią** — paski narzędzi,
paski boczne, menu, przyciski — i wprost odradza robienie z niego tła na całe
okno. Domyślnie aplikacja trzyma się tej zasady: okno jest zwykłym oknem,
a szklane są same kontrolki strony.

Dwa pozostałe tryby robią jednak z całego okna taflę, bo dla timera parkowanego
na pulpicie to ma sens. Wtedy okno przestaje być kryjące, a `WKWebView` przestaje
malować własne tło (`drawsBackground` = fałsz) — inaczej zasłoniłby szkło płytą.

Pasek tytułu zostaje zwykłym paskiem tytułu. Wersja z `fullSizeContentView`,
gdzie szkło szło na wylot pod pasek, wyglądała lepiej i była nie do użycia:
strona wchodziła pod przyciski okna i przykrywała jedyne miejsce, za które
okno się łapie — `WKWebView` połyka ruchy myszy, więc okna nie dało się
przesunąć.

| Tryb | Co rysuje tło | Menu |
| --- | --- | --- |
| `system` | nic — zwykłe okno z paskiem tytułu, szkło tylko na kontrolkach | Tło okna → Jak w systemie |
| `liquid` (domyślny) | `NSGlassEffectView` — prawdziwe zaginanie światła z macOS 26 | Tło okna → Szkło na całe okno |
| `frost` | `NSVisualEffectView`, materiał `underWindowBackground` — matowe rozmycie | Tło okna → Szkło matowe na całe okno |

Wybór zapisuje się w `ustawienia.plist`. Aplikacja mówi o nim stronie przez
`window.__glass(1|0)`, a strona ustawia sobie `html[data-glass="1"]` i chowa
własne tło.

Same kontrolki są szklane po obu stronach — także w przeglądarce, gdzie tła
nie ma. Tafla to wypełnienie, `backdrop-filter`, refleks na górnej krawędzi,
cienki rant i miękki cień; kształt to kapsuła, jak w dzisiejszym macOS.
W przeglądarce rozmycie bierze poświatę malowaną przez `body::before` —
w oknie aplikacji tej poświaty nie ma, bo pod spodem jest już prawdziwe szkło
(CSS-owy `backdrop-filter` nie sięga do treści natywnej pod `WKWebView`).

## Jak strona rozmawia z aplikacją

Stan timera jedzie do aplikacji jednym ciągiem znaków z neutralnymi językowo
znacznikami. Wysyła go funkcja `chan()` w pliku HTML — **tylko wtedy, gdy ciąg
się zmieni** — przez `window.webkit.messageHandlers.timer`, czyli
`WKScriptMessageHandler` (`addScriptMessageHandler:name:`). Ten sam ciąg ląduje
w `document.title`, żeby było go widać w przeglądarce, ale nikt go stamtąd nie
czyta.

Nic tu nie odpytuje w kółko: WebKit sam woła aplikację, gdy stan się zmieni.
Przy nieruszonym timerze aplikacja nie wykonuje **ani jednej** instrukcji,
a przy odliczaniu najwyżej jedną wiadomość na sekundę — mimo że rysowanie
tarczy chodzi dziesięć razy na sekundę.

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
- szklane kontrolki, a tło okna w trzech stopniach (jak w systemie / Liquid Glass / matowe)

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

## Licencja

Wszelkie prawa zastrzeżone — patrz [LICENSE](LICENSE). To nie jest
oprogramowanie otwarte: kopiowanie, rozpowszechnianie i modyfikowanie kodu
wymaga pisemnej zgody autora.
