-- Prosty timer - aplikacja macOS wokol pliku "prosty timer.html".
-- Zrodlo aplikacji z /Applications/Prosty Timer.app (Skrypty/main.scpt).
-- Buduje sie skryptem ./zbuduj.sh

use framework "Foundation"
use framework "AppKit"
use framework "WebKit"
use scripting additions

property win : missing value
property webV : missing value
property statusItem : missing value
property barIcon : missing value
property lastTitle : ""
property restored : false
property alarmSound : missing value
property testPlaying : false
property lastToken : ""
property soundPaths : {}
-- tlo okna: "system" zwykle okno (szklo tylko na kontrolkach strony),
-- "liquid" NSGlassEffectView na cale okno, "frost" NSVisualEffectView
property glassMode : "liquid"
property glassItems : {}
-- granice okna (patrz buildWindow). Musza stac nad kazdym handlerem, ktory
-- ich uzywa - AppleScript czyta nazwy po kolei i wlasciwosc zadeklarowana
-- nizej bralby za niezdefiniowana zmienna lokalna.
property minW : 420
property minH : 750
property maxW : 560
property maxH : 1100

-- sciezki i ustawienia
property supportDir : ""
property soundStore : ""
property prefStore : ""
property htmlPath : ""
property htmlDir : ""

on run
	set my supportDir to ((current application's NSHomeDirectory()) as text) & "/Library/Application Support/ProstyTimer"
	set my soundStore to supportDir & "/dzwieki.json"
	set my prefStore to supportDir & "/ustawienia.plist"
	my ensureDir(supportDir)
	my loadPrefs()
	
	if my useHTML(my findHTML()) is false then
		if my askForHTML() is false then
			display alert "Nie znalazłem pliku strony" message "Aplikacja potrzebuje pliku „prosty timer.html”. Wskaż go przy następnym uruchomieniu." as critical
			current application's NSApp's terminate:me
			return
		end if
	end if
	
	my buildWindow()
	my watchColors()
	my buildStatusItem()
	my buildMenu()
end run

-- ---------- strona ----------

on findHTML()
	set fm to current application's NSFileManager's defaultManager()
	set home to (current application's NSHomeDirectory()) as text
	set bundlePath to (current application's NSBundle's mainBundle()'s bundlePath()) as text
	set nextTo to ((current application's NSString's stringWithString:bundlePath)'s stringByDeletingLastPathComponent()) as text
	set resDir to (current application's NSBundle's mainBundle()'s resourcePath()) as text
	
	set cands to {}
	if htmlPath is not "" then set end of cands to htmlPath
	set end of cands to home & "/OtherProjects/prosty-timer/prosty timer.html"
	set end of cands to home & "/Documents/prosty timer.html"
	set end of cands to nextTo & "/prosty timer.html"
	set end of cands to resDir & "/prosty timer.html"
	
	repeat with c in cands
		set c to c as text
		if (fm's fileExistsAtPath:c) as boolean then return c
	end repeat
	return ""
end findHTML

on useHTML(p)
	if p is "" then return false
	set my htmlPath to p
	set my htmlDir to ((current application's NSString's stringWithString:p)'s stringByDeletingLastPathComponent()) as text
	my savePrefs()
	return true
end useHTML

on askForHTML()
	try
		set f to choose file with prompt "Wskaż plik „prosty timer.html”"
	on error number -128
		return false
	end try
	return my useHTML(POSIX path of (f as alias))
end askForHTML

on buildWindow()
	set theURL to current application's NSURL's fileURLWithPath:htmlPath
	set theDir to current application's NSURL's fileURLWithPath:htmlDir
	
	set frameRect to current application's NSMakeRect(0, 0, 460, 820)
	
	-- 1 pasek tytulu + 2 zamykanie + 4 minimalizacja + 8 zmiana rozmiaru
	set styleMask to 15
	
	set win to current application's NSWindow's alloc()'s ¬
		initWithContentRect:frameRect styleMask:styleMask backing:2 defer:false
	
	win's setTitle:"Prosty timer"
	-- Jeden, pionowy uklad strony i granice jak w Ustawieniach systemowych:
	-- okno nie rozciaga sie na caly ekran. 750 px to najmniejsza tarcza
	-- (200 px) z kontrolkami pod nia plus pasek tytulu; przy 560 x 1100
	-- tarcza dochodzi do ~520 px, a sekcje maja rozsadna szerokosc.
	win's setMinSize:(current application's NSMakeSize(minW, minH))
	win's setMaxSize:(current application's NSMakeSize(maxW, maxH))
	-- bez pelnego ekranu (NSWindowCollectionBehaviorFullScreenNone = 512);
	-- zielony przycisk tylko powieksza okno do maksimum
	win's setCollectionBehavior:512
	win's setFrameAutosaveName:"ProstyTimerOkno"
	-- zapamietana ramka mogla powstac przy starych granicach (np. 1100 px
	-- szerokosci w ukladzie poziomym)
	set r to my rectSize(win's frame())
	set dobry to my fitSize(item 1 of r, item 2 of r)
	if dobry is not r then
		set f to win's frame()
		try
			set ox to item 1 of item 1 of f
			set oy to item 2 of item 1 of f
		on error
			set ox to x of origin of f
			set oy to y of origin of f
		end try
		-- gorna krawedz zostaje na miejscu
		win's setFrame:(current application's NSMakeRect(ox, oy - ((item 2 of dobry) - (item 2 of r)), item 1 of dobry, item 2 of dobry)) display:false
	end if
	win's setReleasedWhenClosed:false
	win's |center|()
	
	set cfg to current application's WKWebViewConfiguration's alloc()'s init()
	-- trwaly magazyn danych: bez tego localStorage znika po zamknieciu
	cfg's setWebsiteDataStore:(current application's WKWebsiteDataStore's defaultDataStore())
	-- most JS -> aplikacja. Strona sama zglasza zmiane stanu, wiec nic tu
	-- nie chodzi w kolko: przy nieruszonym timerze aplikacja nie robi nic.
	cfg's userContentController()'s addScriptMessageHandler:me |name|:"timer"
	set webV to current application's WKWebView's alloc()'s ¬
		initWithFrame:frameRect configuration:cfg
	
	-- wlasny identyfikator, po ktorym strona pozna, ze dziala w aplikacji
	webV's setCustomUserAgent:"ProstyTimerApp"
	
	webV's setAutoresizingMask:18
	webV's loadFileURL:theURL allowingReadAccessToURL:theDir
	
	-- tlo okna (szklo albo zwykle) i wpiecie w nie strony
	my applyGlass()
	
	win's makeKeyAndOrderFront:me
	current application's NSApp's activateIgnoringOtherApps:true
end buildWindow

on reloadPage:sender
	set p to my findHTML()
	if p is "" then return
	my useHTML(p)
	set my restored to false
	webV's loadFileURL:(current application's NSURL's fileURLWithPath:htmlPath) ¬
		allowingReadAccessToURL:(current application's NSURL's fileURLWithPath:htmlDir)
end reloadPage:

-- ---------- tlo okna: Liquid Glass ----------

-- Domyslnie ("system") okno jest zwyklym oknem, a szklo siedzi tylko na
-- kontrolkach strony - tak Apple to rozpisuje: szklo to warstwa plywajaca
-- nad trescia, nie tlo na cale okno.
-- "liquid" i "frost" robia z calego okna tafle: pierwsze przez
-- NSGlassEffectView (macOS 26), drugie przez starsze NSVisualEffectView.
on applyGlass()
	if win is missing value or webV is missing value then return
	
	set szklo to (glassMode is not "system")
	set clearC to current application's NSColor's clearColor()
	set solidC to current application's NSColor's windowBackgroundColor()
	
	-- Szklo idzie na cale okno, takze pod pasek tytulu (fullSizeContentView),
	-- a strona siedzi PONIZEJ paska. W macOS 27 pasek nad niekryjacym oknem
	-- nie maluje wlasnego tla, wiec nazwa i przyciski okna wisialy na golym
	-- pulpicie; pusty toolbar nie pomogl, bo tafle dostaja dopiero jego
	-- elementy. Pierwsza proba z fullSizeContentView polegla na tym, ze
	-- strona wchodzila pod pasek - WKWebView polyka mysz i okna nie dalo sie
	-- zlapac. Tu strona konczy sie pod paskiem, a pas nad nia to sama tafla,
	-- ktora pozwala przesuwac okno (mouseDownCanMoveWindow).
	set ramka to win's frame()
	if szklo then
		win's setStyleMask:(15 + 32768)
		win's setTitlebarAppearsTransparent:true
		win's setOpaque:false
		win's setBackgroundColor:clearC
	else
		win's setStyleMask:15
		win's setTitlebarAppearsTransparent:false
		win's setOpaque:true
		win's setBackgroundColor:solidC
	end if
	win's setFrame:ramka display:true
	
	-- WKWebView domyslnie maluje wlasne, kryjace tlo; bez tego szkla nie widac
	try
		webV's setValue:(current application's NSNumber's numberWithBool:(not szklo)) forKey:"drawsBackground"
	end try
	try
		if szklo then
			webV's setUnderPageBackgroundColor:clearC
		else
			webV's setUnderPageBackgroundColor:solidC
		end if
	end try
	
	try
		webV's removeFromSuperview()
	end try
	
	set bg to my makeBackdrop()
	if bg is missing value then
		win's setContentView:webV
	else
		win's setContentView:bg
		-- Strona nie moze byc bezposrednio tresca szkla, bo szklo rozciaga ja
		-- na cala swoja powierzchnie, razem z pasem pod paskiem tytulu.
		-- Stad pusta oprawka na cale szklo, a strona w niej tylko w obszarze
		-- tresci okna (contentLayoutRect, czyli bez paska).
		-- Oprawka od razu na wymiar szkla. Z init() startowala 0x0 i szklo
		-- rozciagalo ja dopiero przy ukladaniu - czyli PO wpieciu strony, ktora
		-- (maska 18) rosla razem z nia o caly rozmiar okna: strona 2x wieksza
		-- niz okno, tresc wyjechana w prawy dolny rog.
		set oprawka to current application's NSView's alloc()'s initWithFrame:(bg's |bounds|())
		oprawka's setAutoresizingMask:18
		-- NSGlassEffectView reczy tylko za contentView: reszta podwidokow
		-- moze wyladowac nad szklem albo pod nim. NSVisualEffectView
		-- takiego wejscia nie ma, tam oprawka idzie zwyklym podwidokiem.
		if (bg's respondsToSelector:"setContentView:") as boolean then
			bg's setContentView:oprawka
		else
			bg's addSubview:oprawka
		end if
		oprawka's addSubview:webV
		-- Ramka strony liczona z oprawki: cala szerokosc, wysokosc bez paska.
		-- contentLayoutRect odpada - zanim okno stanie na ekranie, podaje
		-- nieaktualne y (np. -637) i strona ladowala pod oknem.
		set wh to my rectSize(oprawka's |bounds|())
		set pasek to (item 2 of my rectSize(current application's NSWindow's ¬
			frameRectForContentRect:(current application's NSMakeRect(0, 0, 100, 100)) styleMask:15)) - 100
		webV's setFrame:(current application's NSMakeRect(0, 0, item 1 of wh, (item 2 of wh) - pasek))
	end if
	-- 18 = rozciaganie w szerz i wzwyz; marginesy stale, wiec pas nad
	-- strona trzyma wysokosc paska przy kazdej zmianie rozmiaru
	webV's setAutoresizingMask:18
	
	my tellGlass()
end applyGlass

-- {szerokosc, wysokosc} z NSRect - AppleScriptObjC oddaje go raz lista
-- {{x, y}, {w, h}}, raz rekordem {origin:..., size:...}
-- rozmiar przyciety do granic okna
on fitSize(w, h)
	if w < minW then set w to minW
	if w > maxW then set w to maxW
	if h < minH then set h to minH
	if h > maxH then set h to maxH
	return {w, h}
end fitSize

on rectSize(r)
	try
		return {(item 1 of item 2 of r) as real, (item 2 of item 2 of r) as real}
	on error
		return {(width of |size| of r) as real, (height of |size| of r) as real}
	end try
end rectSize

on makeBackdrop()
	if glassMode is "system" then return missing value
	
	if glassMode is "liquid" then
		set cls to current application's NSClassFromString("NSGlassEffectView")
		if cls is not missing value then
			set v to cls's alloc()'s init()
			-- 0 = NSGlassEffectViewStyle.regular (czytelne tlo pod trescia)
			try
				v's setStyle:0
			end try
			-- rogi obcina samo okno, szklo ma isc na wylot
			try
				v's setCornerRadius:0
			end try
			return v
		end if
	end if
	
	set cls to current application's NSClassFromString("NSVisualEffectView")
	if cls is missing value then return missing value
	set v to cls's alloc()'s init()
	-- 21 = NSVisualEffectMaterialUnderWindowBackground, 0 = rozmycie tego,
	-- co za oknem, 1 = zawsze aktywne (takze gdy okno nie jest na wierzchu)
	v's setMaterial:21
	v's setBlendingMode:0
	v's setState:1
	return v
end makeBackdrop

-- strona musi wiedziec, czy ma byc przezroczysta i jak mocno zabarwione
-- jest szklo w systemie
on tellGlass()
	if webV is missing value then return
	set v to "0"
	if glassMode is not "system" then set v to "1"
	set t to my glassTint()
	try
		webV's evaluateJavaScript:("window.__glass&&window.__glass(" & v & "," & t & ")") ¬
			completionHandler:(missing value)
	end try
end tellGlass

-- Suwak "Liquid Glass" z Ustawien -> Wyglad (macOS 27). Zapisuje sie jako
-- liczba zmiennoprzecinkowa 0-1 pod NSGlassTintAmount w ustawieniach
-- globalnych; 0 to szklo przejrzyste, 1 zabarwione. Oddajemy calkowite
-- promile od zera do stu, bo AppleScript zamienia ulamek na tekst wedlug
-- jezyka systemu i przy polskim wyszedlby przecinek, ktorego JavaScript
-- nie przyjmie.
on glassTint()
	try
		set d to current application's NSUserDefaults's standardUserDefaults()
		set t to (d's doubleForKey:"NSGlassTintAmount") as real
	on error
		return 0
	end try
	if t < 0 then set t to 0
	if t > 1 then set t to 1
	-- "round" w kontekscie ASOC trafia do mostka ObjC jako selektor, nie do
	-- AppleScriptu; dzielenie calkowite nie potrzebuje zadnych dodatkow
	return ((t * 100) + 0.5) div 1
end glassTint

-- Systemu nie odpytujemy: wartosc odswiezamy, gdy uzytkownik wraca do okna
-- po zmianie w Ustawieniach.
on applicationDidBecomeActive:aNotification
	my tellGlass()
	my tellAccent()
end applicationDidBecomeActive:

-- ---------- kolor akcentu i ikony z systemu ----------

-- Kolor z Ustawien -> Wyglad -> Kolor. Strona liczy z niego odcienie
-- motywu. "Wielokolorowy" (brak AppleAccentColor) zostawia fiolet strony.
-- Liczby ida jako calkowite 0-255 - ulamek AppleScript zamienilby na tekst
-- z przecinkiem wedlug jezyka systemu.
on tellAccent()
	if webV is missing value then return
	set js to "window.__accent&&window.__accent(null)"
	try
		set k to current application's NSUserDefaults's standardUserDefaults()'s objectForKey:"AppleAccentColor"
		if k is not missing value then
			set c to (current application's NSColor's controlAccentColor())'s colorUsingColorSpace:(current application's NSColorSpace's sRGBColorSpace())
			set r to ((c's redComponent()) * 255 + 0.5) div 1
			set g to ((c's greenComponent()) * 255 + 0.5) div 1
			set b to ((c's blueComponent()) * 255 + 0.5) div 1
			set js to "window.__accent&&window.__accent(" & r & "," & g & "," & b & ")"
		end if
	end try
	try
		webV's evaluateJavaScript:js completionHandler:(missing value)
	end try
end tellAccent

-- Zmiana koloru w Ustawieniach dochodzi od razu, a nie dopiero po powrocie
-- do okna: AppKit wysyla NSSystemColorsDidChangeNotification, a system
-- rozglasza AppleColorPreferencesChangedNotification.
on systemColorsChanged:aNotification
	my tellAccent()
end systemColorsChanged:

on watchColors()
	current application's NSNotificationCenter's defaultCenter()'s addObserver:me ¬
		selector:"systemColorsChanged:" |name|:"NSSystemColorsDidChangeNotification" object:(missing value)
	current application's NSDistributedNotificationCenter's defaultCenter()'s addObserver:me ¬
		selector:"systemColorsChanged:" |name|:"AppleColorPreferencesChangedNotification" object:(missing value)
end watchColors

-- Ikony strony to SF Symbols. Strona nie ma do nich dostepu, wiec rysuje je
-- aplikacja: symbol -> PNG -> base64. Strona uzywa ich jako maski, wiec
-- kolor bierze z CSS. Rysowane raz, potem z pamieci.
property symJS : ""
on tellSymbols()
	if webV is missing value then return
	if symJS is "" then
		set parts to {}
		repeat with n in {"play.fill", "stop.fill", "square.and.arrow.up", "arrow.counterclockwise", "music.note", "globe", "circle.lefthalf.filled", "textformat", "xmark", "chevron.up", "chevron.down", "speaker.slash.fill", "speaker.wave.2.fill", "plus"}
			try
				set img to (current application's NSImage's imageWithSystemSymbolName:(n as text) accessibilityDescription:(missing value))
				if img is not missing value then
					-- 32 pt, waga regular (0), skala srednia (2); na stronie ~16 px,
					-- wiec jest zapas na ekran Retina
					set cfg to (current application's NSImageSymbolConfiguration's configurationWithPointSize:32 weight:0 |scale|:2)
					set img to (img's imageWithSymbolConfiguration:cfg)
					set rep to (current application's NSBitmapImageRep's imageRepWithData:(img's TIFFRepresentation()))
					set png to (rep's representationUsingType:4 |properties|:(current application's NSDictionary's dictionary()))
					set b64 to (png's base64EncodedStringWithOptions:0) as text
					set end of parts to quote & (n as text) & quote & ":" & quote & "data:image/png;base64," & b64 & quote
				end if
			end try
		end repeat
		set oldTID to AppleScript's text item delimiters
		set AppleScript's text item delimiters to ","
		set my symJS to "window.__symbols&&window.__symbols({" & (parts as text) & "})"
		set AppleScript's text item delimiters to oldTID
	end if
	try
		webV's evaluateJavaScript:symJS completionHandler:(missing value)
	end try
end tellSymbols

on setGlass:sender
	try
		set m to (sender's representedObject()) as text
	on error
		return
	end try
	if m is glassMode then return
	set my glassMode to m
	my savePrefs()
	my applyGlass()
	my syncGlassMenu()
end setGlass:

on syncGlassMenu()
	repeat with gi in glassItems
		set mi to contents of gi
		if ((mi's representedObject()) as text) is glassMode then
			mi's setState:1
		else
			mi's setState:0
		end if
	end repeat
end syncGlassMenu

-- ---------- pasek menu ----------

on buildStatusItem()
	set bar to current application's NSStatusBar's systemStatusBar()
	-- -1 to NSVariableStatusItemLength
	set statusItem to bar's statusItemWithLength:-1
	
	set btn to statusItem's button()
	set img to current application's NSImage's ¬
		imageWithSystemSymbolName:"timer" accessibilityDescription:"Prosty timer"
	if img is not missing value then
		img's setTemplate:true
		set barIcon to img
		btn's setImage:img
	end if
	
	btn's setTarget:me
	btn's setAction:"toggleWindow:"
	btn's sendActionOn:2
end buildStatusItem

-- ---------- most ze strony ----------

-- Strona wola tu sama, gdy zmieni sie stan (window.webkit.messageHandlers).
on userContentController:ucc didReceiveScriptMessage:msg
	try
		set t to (msg's |body|()) as text
	on error
		return
	end try
	my handleState(t)
end userContentController:didReceiveScriptMessage:

-- Stan strony w jednym ciagu znakow. Znaczniki sa jezykowo neutralne:
-- |L czasy w spoczynku, |P pauza, |O po czasie, |M wyciszone, |S numer dzwieku.
on handleState(t)
	-- strona wystartowala od nowa (takze po przeladowaniu przez sam WebKit):
	-- stan trzeba jej podac jeszcze raz
	if t is "__READY__" then
		set my restored to false
		return
	end if
	
	-- pierwszy komunikat ze znacznikiem "|L" znaczy, ze skrypt strony ruszyl
	-- i window.__loadAlarms juz istnieje
	if restored is false and t contains "|L" then
		set my restored to true
		my tellAccent()
		my tellSymbols()
		my restoreSounds()
		my tellGlass()
	end if
	
	-- przycisk dzwiekow w oknie prosi o wybor plikow
	if t is "__PICK__" then
		webV's evaluateJavaScript:"window.__pickDone&&window.__pickDone()" completionHandler:(missing value)
		my pickSounds:me
		return
	end if
	
	-- strona wrocila do dzwieku domyslnego
	if t is "__RESET__" then
		set my soundPaths to {}
		my deleteStore()
		return
	end if
	
	if t starts with "__PLAY__" then
		if t is not lastToken then
			set my lastToken to t
			my stopAlarm()
			set my testPlaying to true
			my playSound(t, false)
		end if
		return
	end if
	if t is "__STOP__" then
		set my testPlaying to false
		my stopAlarm()
		return
	end if
	
	set my lastTitle to t
	
	if t contains "|O" and t does not contain "|M" then
		set my testPlaying to false
		my startAlarm(t)
	else if testPlaying is false then
		my stopAlarm()
	end if
	
	set btn to statusItem's button()
	
	-- spoczynek: "Prosty timer |L300,600" - sama ikona
	if t contains "|L" then
		btn's setAttributedTitle:(current application's NSAttributedString's alloc()'s initWithString:"")
		if barIcon is not missing value then btn's setImage:barIcon
		statusItem's setLength:-1
		return
	end if
	
	-- z tytulu bierzemy sam czas, reszta to znaczniki stanu
	set AppleScript's text item delimiters to " "
	set t to first text item of t
	set AppleScript's text item delimiters to ""
	
	-- odliczanie: sam czas, bez ikony (ikona dokladala odstep)
	btn's setImage:(missing value)
	if (count of t) > 6 then
		statusItem's setLength:58
	else
		statusItem's setLength:44
	end if
	
	-- font jak systemowy zegar: te same cyfry, ta sama linia bazowa
	set fSize to current application's NSFont's systemFontSize()
	set fnt to current application's NSFont's ¬
		monospacedDigitSystemFontOfSize:fSize weight:0
	set para to current application's NSMutableParagraphStyle's alloc()'s init()
	para's setAlignment:1
	
	set attrs to current application's NSDictionary's dictionaryWithObjects:{fnt, para, -1.0} ¬
		forKeys:{current application's NSFontAttributeName, ¬
		current application's NSParagraphStyleAttributeName, ¬
		current application's NSBaselineOffsetAttributeName}
	
	set aStr to current application's NSAttributedString's alloc()'s ¬
		initWithString:t attributes:attrs
	btn's setAttributedTitle:aStr
end handleState

on buildMenu()
	set mainMenu to current application's NSMenu's alloc()'s init()
	
	set appItem to current application's NSMenuItem's alloc()'s init()
	mainMenu's addItem:appItem
	set appMenu to current application's NSMenu's alloc()'s init()
	appItem's setSubmenu:appMenu
	
	-- Cmd+W zamyka okno (aplikacja zostaje na pasku menu)
	set closeItem to current application's NSMenuItem's alloc()'s ¬
		initWithTitle:"Zamknij okno" action:"performClose:" keyEquivalent:"w"
	appMenu's addItem:closeItem
	
	-- Cmd+O wybiera pliki dzwiekowe alarmu
	set openItem to current application's NSMenuItem's alloc()'s ¬
		initWithTitle:"Wybierz dźwięki alarmu" action:"pickSounds:" keyEquivalent:"o"
	openItem's setTarget:me
	appMenu's addItem:openItem
	
	-- Cmd+R wczytuje plik strony jeszcze raz (po edycji HTML)
	set reloadItem to current application's NSMenuItem's alloc()'s ¬
		initWithTitle:"Przeładuj stronę" action:"reloadPage:" keyEquivalent:"r"
	reloadItem's setTarget:me
	appMenu's addItem:reloadItem
	
	-- tlo okna: szklo systemu albo zwykle
	appMenu's addItem:(current application's NSMenuItem's separatorItem())
	set bgItem to current application's NSMenuItem's alloc()'s ¬
		initWithTitle:"Tło okna" action:(missing value) keyEquivalent:""
	set bgMenu to current application's NSMenu's alloc()'s init()
	set lista to {}
	repeat with pair in {{"Jak w systemie", "system"}, {"Szkło na całe okno (Liquid Glass)", "liquid"}, {"Szkło matowe na całe okno", "frost"}}
		set p to contents of pair
		set mi to current application's NSMenuItem's alloc()'s ¬
			initWithTitle:(item 1 of p) action:"setGlass:" keyEquivalent:""
		mi's setTarget:me
		mi's setRepresentedObject:(item 2 of p)
		bgMenu's addItem:mi
		set end of lista to mi
	end repeat
	set my glassItems to lista
	bgItem's setSubmenu:bgMenu
	appMenu's addItem:bgItem
	my syncGlassMenu()
	
	appMenu's addItem:(current application's NSMenuItem's separatorItem())
	
	-- Cmd+Q konczy aplikacje
	set quitItem to current application's NSMenuItem's alloc()'s ¬
		initWithTitle:"Zakończ" action:"terminate:" keyEquivalent:"q"
	appMenu's addItem:quitItem
	
	current application's NSApp's setMainMenu:mainMenu
end buildMenu

-- ---------- dzwiek ----------

on makeSound(pth)
	set u to current application's NSURL's fileURLWithPath:pth
	set s to current application's NSSound's alloc()'s initWithContentsOfURL:u byReference:false
	if s is missing value then return missing value
	return s
end makeSound

-- klikniecie ikony w Docku ma przywracac okno
on applicationShouldHandleReopen:sender hasVisibleWindows:flag
	my showWindow()
	return true
end applicationShouldHandleReopen:hasVisibleWindows:

on startAlarm(t)
	my playSound(t, true)
end startAlarm

on playSound(t, looping)
	if alarmSound is not missing value then return
	
	set idx to -1
	try
		set AppleScript's text item delimiters to "|S"
		set tail to last text item of t
		set AppleScript's text item delimiters to ""
		set idx to my leadingInt(tail)
	end try
	
	set pth to ""
	try
		if idx > -1 and (count of soundPaths) > idx then
			set pth to item (idx + 1) of soundPaths
		else if (count of soundPaths) > 0 then
			set pth to item 1 of soundPaths
		end if
	end try
	
	set fm to current application's NSFileManager's defaultManager()
	if pth is "" then set pth to "/System/Library/Sounds/Submarine.aiff"
	if not ((fm's fileExistsAtPath:pth) as boolean) then set pth to "/System/Library/Sounds/Submarine.aiff"
	
	set snd to my makeSound(pth)
	-- format, ktorego NSSound nie otworzy (np. flac), nie moze uciszyc alarmu
	if snd is missing value then set snd to my makeSound("/System/Library/Sounds/Submarine.aiff")
	if snd is missing value then return
	
	snd's setLoops:looping
	snd's setVolume:1.0
	snd's play()
	set my alarmSound to snd
end playSound

on stopAlarm()
	if alarmSound is missing value then return
	try
		alarmSound's |stop|()
	end try
	set my alarmSound to missing value
end stopAlarm

-- ---------- lista dzwiekow ----------

on pickSounds:sender
	try
		set theFiles to choose file with prompt ¬
			"Wybierz pliki dźwiękowe alarmu" of type {"mp3", "wav", "aiff", "aif", "m4a", "aac", "public.audio"} ¬
			with multiple selections allowed
	on error number -128
		return
	end try
	
	set arr to current application's NSMutableArray's array()
	repeat with f in theFiles
		set pth to POSIX path of (f as alias)
		set d to current application's NSMutableDictionary's dictionary()
		d's setObject:(my lastPathPart(pth)) forKey:"name"
		d's setObject:pth forKey:"path"
		arr's addObject:d
	end repeat
	
	-- kolejnosc ustala aplikacja, strona jej nie zmienia: numer |S w tytule
	-- musi wskazywac ten sam plik po obu stronach
	set sd to current application's NSSortDescriptor's ¬
		sortDescriptorWithKey:"name" ascending:true selector:"localizedStandardCompare:"
	set sorted to arr's sortedArrayUsingDescriptors:{sd}
	
	my applyList(sorted, false)
	win's makeKeyAndOrderFront:me
	current application's NSApp's activateIgnoringOtherApps:true
end pickSounds:

on applyList(arr, restoring)
	set paths to {}
	repeat with i from 0 to ((arr's |count|() as integer) - 1)
		set d to (arr's objectAtIndex:i)
		set p to (d's objectForKey:"path")
		if p is not missing value then set end of paths to (p as text)
	end repeat
	set my soundPaths to paths
	
	set jsonText to my jsonFrom(arr)
	if jsonText is "" then return
	if restoring is false then my writeStore(jsonText)
	if webV is missing value then return
	if restoring then
		webV's evaluateJavaScript:("window.__loadAlarms&&window.__loadAlarms(" & jsonText & ",true)") completionHandler:(missing value)
	else
		webV's evaluateJavaScript:("window.__loadAlarms&&window.__loadAlarms(" & jsonText & ")") completionHandler:(missing value)
	end if
end applyList

on jsonFrom(arr)
	try
		set jd to current application's NSJSONSerialization's ¬
			dataWithJSONObject:arr options:0 |error|:(missing value)
		if jd is missing value then return ""
		return (current application's NSString's alloc()'s initWithData:jd encoding:4) as text
	on error
		return ""
	end try
end jsonFrom

on writeStore(jsonText)
	try
		my ensureDir(supportDir)
		set nsStr to current application's NSString's stringWithString:jsonText
		-- 4 to NSUTF8StringEncoding
		nsStr's writeToFile:soundStore atomically:true encoding:4 |error|:(missing value)
	end try
end writeStore

on deleteStore()
	try
		current application's NSFileManager's defaultManager()'s ¬
			removeItemAtPath:soundStore |error|:(missing value)
	end try
end deleteStore

on restoreSounds()
	try
		set fm to current application's NSFileManager's defaultManager()
		if not ((fm's fileExistsAtPath:soundStore) as boolean) then return
		set jd to current application's NSData's dataWithContentsOfFile:soundStore
		if jd is missing value then return
		set raw to current application's NSJSONSerialization's ¬
			JSONObjectWithData:jd options:0 |error|:(missing value)
		if raw is missing value then return
		
		set arr to current application's NSMutableArray's array()
		set hadData to false
		repeat with i from 0 to ((raw's |count|() as integer) - 1)
			set src to (raw's objectAtIndex:i)
			set p to (src's objectForKey:"path")
			if p is not missing value then
				if (src's objectForKey:"data") is not missing value then set hadData to true
				set n to (src's objectForKey:"name")
				if n is missing value then set n to (my lastPathPart(p as text))
				set d to current application's NSMutableDictionary's dictionary()
				d's setObject:n forKey:"name"
				d's setObject:p forKey:"path"
				arr's addObject:d
			end if
		end repeat
		if (arr's |count|() as integer) is 0 then return
		
		my applyList(arr, true)
		-- stary zapis trzymal base64 kazdego pliku (dziesiatki MB) - przepisz go chudo
		if hadData then my writeStore(my jsonFrom(arr))
	end try
end restoreSounds

-- ---------- ustawienia ----------

on ensureDir(pth)
	try
		current application's NSFileManager's defaultManager()'s ¬
			createDirectoryAtPath:pth withIntermediateDirectories:true ¬
				attributes:(missing value) |error|:(missing value)
	end try
end ensureDir

on loadPrefs()
	try
		set d to current application's NSDictionary's dictionaryWithContentsOfFile:prefStore
		if d is missing value then return
		set v to (d's objectForKey:"htmlPath")
		if v is not missing value then set my htmlPath to (v as text)
		set g to (d's objectForKey:"glassMode")
		if g is not missing value then set my glassMode to (g as text)
	end try
end loadPrefs

on savePrefs()
	try
		my ensureDir(supportDir)
		set d to current application's NSMutableDictionary's dictionary()
		d's setObject:htmlPath forKey:"htmlPath"
		d's setObject:glassMode forKey:"glassMode"
		d's writeToFile:prefStore atomically:true
	end try
end savePrefs

-- ---------- menu na pasku ----------

on toggleWindow:sender
	set m to current application's NSMenu's alloc()'s init()
	
	if lastTitle is "" or lastTitle contains "|L" then
		set secs to my presetList(lastTitle)
		if (count of secs) > 0 then
			-- pierwsza pozycja to czas ustawiony w oknie
			set cur to item 1 of secs
			if cur > 0 then
				set mi to current application's NSMenuItem's alloc()'s ¬
					initWithTitle:("Start " & my niceTime(cur) & "  (z okna)") action:"cmdPreset:" keyEquivalent:""
				mi's setTarget:me
				mi's setRepresentedObject:cur
				m's addItem:mi
			end if
			
			if (count of secs) > 1 then
				m's addItem:(current application's NSMenuItem's separatorItem())
				set hdr to current application's NSMenuItem's alloc()'s ¬
					initWithTitle:"Zapisane" action:(missing value) keyEquivalent:""
				hdr's setEnabled:false
				m's addItem:hdr
				repeat with i from 2 to (count of secs)
					set sc to item i of secs
					set mi to (current application's NSMenuItem's alloc()'s ¬
						initWithTitle:("   " & my niceTime(sc)) action:"cmdPreset:" keyEquivalent:"")
					(mi's setTarget:me)
					(mi's setRepresentedObject:sc)
					(m's addItem:mi)
				end repeat
			end if
			m's addItem:(current application's NSMenuItem's separatorItem())
		end if
		if win's isVisible() as boolean then
			my addItem(m, "Ukryj okno", "hideWindow:")
		else
			my addItem(m, "Pokaż okno", "showWindowAction:")
		end if
		m's addItem:(current application's NSMenuItem's separatorItem())
		my addItem(m, "Zakończ", "terminate:")
		statusItem's setMenu:m
		statusItem's button()'s performClick:me
		statusItem's setMenu:(missing value)
		return
	end if
	
	if win's isVisible() as boolean then
		my addItem(m, "Ukryj okno", "hideWindow:")
	else
		my addItem(m, "Pokaż okno", "showWindowAction:")
	end if
	m's addItem:(current application's NSMenuItem's separatorItem())
	
	if lastTitle contains "|O" then
		my addItem(m, "Wycisz dźwięk", "cmdMute:")
		my addItem(m, "Zatrzymaj", "cmdMain:")
	else if lastTitle contains "|P" then
		my addItem(m, "Wznów", "cmdMain:")
	else
		my addItem(m, "Pauza", "cmdMain:")
	end if
	my addItem(m, "Wyzeruj", "cmdReset:")
	
	m's addItem:(current application's NSMenuItem's separatorItem())
	my addItem(m, "Zakończ", "terminate:")
	
	statusItem's setMenu:m
	statusItem's button()'s performClick:me
	statusItem's setMenu:(missing value)
end toggleWindow:

on presetList(t)
	if t does not contain "|L" then return {}
	set AppleScript's text item delimiters to "|L"
	set tail to last text item of t
	set AppleScript's text item delimiters to ","
	set parts to text items of tail
	set AppleScript's text item delimiters to ""
	set out to {}
	repeat with p in parts
		try
			set end of out to (p as integer)
		end try
	end repeat
	return out
end presetList

on niceTime(sc)
	set h to sc div 3600
	set m to (sc mod 3600) div 60
	set s2 to sc mod 60
	set mm to (m as text)
	if h > 0 and m < 10 then set mm to "0" & mm
	set ss to (s2 as text)
	if s2 < 10 then set ss to "0" & ss
	if h > 0 then return (h as text) & ":" & mm & ":" & ss
	return mm & ":" & ss
end niceTime

on cmdPreset:sender
	set sc to (sender's representedObject()) as integer
	webV's evaluateJavaScript:("window.__cmd(" & sc & ")") completionHandler:(missing value)
	my showWindow()
end cmdPreset:

on addItem(theMenu, theTitle, theAction)
	set mi to current application's NSMenuItem's alloc()'s ¬
		initWithTitle:theTitle action:theAction keyEquivalent:""
	if theAction is not "terminate:" then mi's setTarget:me
	theMenu's addItem:mi
end addItem

on showWindow()
	win's makeKeyAndOrderFront:me
	current application's NSApp's activateIgnoringOtherApps:true
end showWindow

on showWindowAction:sender
	my showWindow()
end showWindowAction:

on hideWindow:sender
	win's orderOut:me
end hideWindow:

on cmdMain:sender
	webV's evaluateJavaScript:"window.__cmd('main')" completionHandler:(missing value)
end cmdMain:

on cmdReset:sender
	webV's evaluateJavaScript:"window.__cmd('reset')" completionHandler:(missing value)
end cmdReset:

on cmdMute:sender
	webV's evaluateJavaScript:"window.__cmd('mute')" completionHandler:(missing value)
end cmdMute:

-- ---------- drobiazgi ----------

on lastPathPart(pth)
	set AppleScript's text item delimiters to "/"
	set nm to last text item of pth
	set AppleScript's text item delimiters to ""
	return nm
end lastPathPart

on leadingInt(s)
	set out to ""
	repeat with c in characters of s
		set c to c as text
		if c is in "0123456789" then
			set out to out & c
		else
			exit repeat
		end if
	end repeat
	if out is "" then return -1
	return out as integer
end leadingInt

-- zamkniecie okna NIE konczy aplikacji: ikona zostaje na pasku menu
on applicationShouldTerminateAfterLastWindowClosed:sender
	return false
end applicationShouldTerminateAfterLastWindowClosed:
