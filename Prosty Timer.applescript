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
	
	set frameRect to current application's NSMakeRect(0, 0, 1100, 720)
	
	-- 1 pasek tytulu + 2 zamykanie + 4 minimalizacja + 8 zmiana rozmiaru
	set styleMask to 15
	
	set win to current application's NSWindow's alloc()'s ¬
		initWithContentRect:frameRect styleMask:styleMask backing:2 defer:false
	
	win's setTitle:"Prosty timer"
	win's setMinSize:(current application's NSMakeSize(420, 560))
	win's setFrameAutosaveName:"ProstyTimerOkno"
	win's setReleasedWhenClosed:false
	win's |center|()
	
	set cfg to current application's WKWebViewConfiguration's alloc()'s init()
	-- trwaly magazyn danych: bez tego localStorage znika po zamknieciu
	cfg's setWebsiteDataStore:(current application's WKWebsiteDataStore's defaultDataStore())
	set webV to current application's WKWebView's alloc()'s ¬
		initWithFrame:frameRect configuration:cfg
	
	-- wlasny identyfikator, po ktorym strona pozna, ze dziala w aplikacji
	webV's setCustomUserAgent:"ProstyTimerApp"
	
	webV's loadFileURL:theURL allowingReadAccessToURL:theDir
	win's setContentView:webV
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
	
	-- odpytywanie strony o czas
	current application's NSTimer's ¬
		scheduledTimerWithTimeInterval:0.2 target:me ¬
			selector:"tickStatus:" userInfo:(missing value) repeats:true
end buildStatusItem

-- Tytul strony to kanal sterowania. Znaczniki sa jezykowo neutralne:
-- |L czasy w spoczynku, |P pauza, |O po czasie, |M wyciszone, |S numer dzwieku.
on tickStatus:sender
	try
		set t to (webV's title) as text
	on error
		return
	end try
	
	-- "|L" pojawia sie dopiero, gdy skrypt strony ruszyl; sam tytul z <head>
	-- przychodzi wczesniej i wtedy window.__loadAlarms jeszcze nie istnieje
	if restored is false and t contains "|L" then
		set my restored to true
		my restoreSounds()
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
end tickStatus:

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
	end try
end loadPrefs

on savePrefs()
	try
		my ensureDir(supportDir)
		set d to current application's NSMutableDictionary's dictionary()
		d's setObject:htmlPath forKey:"htmlPath"
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
