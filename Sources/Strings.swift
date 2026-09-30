import Foundation

/// UI text in 43 languages, one row per language in the order of the properties below.
/// Wherever macOS has its own wording, the row carries it, taken from the system's
/// localization tables: Start, Pause, Resume, Cancel and Sound from the Clock app,
/// Delete and Save from AppKit, Quit and "Open …" as in Screen Light. Languages macOS
/// doesn't ship keep our own words, or English where we had none.
struct Strings {
    private let v: [String]

    var ready: String { v[0] }
    var running: String { v[1] }
    var paused: String { v[2] }
    var overtime: String { v[3] }
    var start: String { v[4] }
    var pause: String { v[5] }
    var resume: String { v[6] }
    var stop: String { v[7] }
    var cancel: String { v[8] }
    var mute: String { v[9] }
    var unmute: String { v[10] }
    var quit: String { v[11] }
    var sound: String { v[12] }
    var save: String { v[13] }
    var delete: String { v[14] }
    /// "Open …" with the app's name in it.
    var open: String { String(format: v[15], Model.appName) }

    private static let count = 16

    static func `for`(_ code: String) -> Strings {
        let row = table[code] ?? []
        return Strings(v: row.count == count ? row : table["en"]!)
    }

    static let rtl: Set = ["ar", "he", "fa"]

    /// First of the system's preferred languages that we have; a per-app language from
    /// System Settings → General → Language & Region counts too.
    static var detected: String {
        for id in Locale.preferredLanguages {
            if table[id] != nil { return id }
            let lang = Locale.Language(identifier: id)
            guard let code = lang.languageCode?.identifier else { continue }
            if code == "zh" {
                let hant = lang.script?.identifier == "Hant" || ["TW", "HK", "MO"].contains(lang.region?.identifier ?? "")
                return hant ? "zh-Hant" : "zh-Hans"
            }
            if code == "no" || code == "nn" { return "nb" }
            if table[code] != nil { return code }
        }
        return "en"
    }

    static let table: [String: [String]] = [
        "pl": ["gotowy", "odliczanie", "pauza", "po czasie", "Start", "Pauza", "Wznów", "Zatrzymaj", "Anuluj", "wycisz dźwięk", "włącz dźwięk", "Zakończ", "Dźwięk", "Zachowaj", "Usuń", "Otwórz %@"],
        "en": ["ready", "counting down", "paused", "overtime", "Start", "Pause", "Resume", "Stop", "Cancel", "mute sound", "unmute sound", "Quit", "Sound", "Save", "Delete", "Open %@"],
        "de": ["bereit", "läuft", "pausiert", "überzogen", "Start", "Pause", "Weiter", "Stopp", "Abbrechen", "Ton stummschalten", "Ton einschalten", "Beenden", "Ton", "Sichern", "Löschen", "%@ öffnen"],
        "fr": ["prêt", "décompte", "pause", "dépassement", "Démarrer", "Pause", "Reprendre", "Arrêter", "Annuler", "couper le son", "rétablir le son", "Quitter", "Sonnerie", "Enregistrer", "Supprimer", "Ouvrir %@"],
        "es": ["listo", "contando", "pausa", "tiempo extra", "Iniciar", "Pausar", "Reanudar", "Detener", "Cancelar", "silenciar sonido", "activar sonido", "Salir", "Sonido", "Guardar", "Eliminar", "Abrir %@"],
        "pt": ["pronto", "contando", "pausa", "tempo extra", "Iniciar", "Pausar", "Retomar", "Parar", "Cancelar", "silenciar som", "ativar som", "Sair", "Som", "Guardar", "Apagar", "Abrir %@"],
        "it": ["pronto", "conteggio", "pausa", "oltre il tempo", "Avvia", "Pausa", "Riprendi", "Ferma", "Interrompi", "disattiva audio", "attiva audio", "Esci", "Suono", "Salva", "Elimina", "Apri %@"],
        "nl": ["gereed", "aftellen", "pauze", "over tijd", "Start", "Pauze", "Hervat", "Stop", "Annuleer", "geluid dempen", "geluid aan", "Stop", "Geluid", "Bewaar", "Verwijder", "Open %@"],
        "sv": ["redo", "räknar ner", "pausad", "övertid", "Starta", "Pausa", "Återuppta", "Stoppa", "Avbryt", "ljud av", "ljud på", "Avsluta", "Ljud", "Spara", "Radera", "Öppna %@"],
        "da": ["klar", "tæller ned", "pause", "overtid", "Start", "Pause", "Genoptag", "Stop", "Annuller", "lyd fra", "lyd til", "Slut", "Lyd", "Gem", "Slet", "Åbn %@"],
        "nb": ["klar", "teller ned", "pause", "overtid", "Start", "Pause", "Fortsett", "Stopp", "Avbryt", "lyd av", "lyd på", "Avslutt", "Lyd", "Lagre", "Slett", "Åpne %@"],
        "fi": ["valmis", "laskee", "tauko", "yliaika", "Aloita", "Tauko", "Jatka", "Pysäytä", "Kumoa", "mykistä ääni", "palauta ääni", "Lopeta", "Merkkiääni", "Tallenna", "Poista", "Avaa %@"],
        "is": ["tilbúinn", "telur niður", "í bið", "yfir tíma", "Byrja", "Bið", "Halda áfram", "Stöðva", "Núllstilla", "slökkva á hljóði", "kveikja á hljóði", "Hætta", "Sound", "Save", "Delete", "Opna %@"],
        "cs": ["připraven", "odpočet", "pauza", "po čase", "Spustit", "Pauza", "Pokračovat", "Zastavit", "Zrušit", "ztlumit zvuk", "zapnout zvuk", "Ukončit", "Zvuk", "Uložit", "Smazat", "Otevřít %@"],
        "sk": ["pripravený", "odpočet", "pauza", "po čase", "Štart", "Pozastaviť", "Pokračovať", "Zastaviť", "Zrušiť", "stlmiť zvuk", "zapnúť zvuk", "Ukončiť", "Zvuk", "Uložiť", "Vymazať", "Otvoriť %@"],
        "sl": ["pripravljen", "odštevanje", "premor", "po času", "Začni", "Začasno ustavi", "Nadaljuj", "Ustavi", "Prekliči", "utišaj zvok", "vklopi zvok", "Izhod", "Zvok", "Shrani", "Izbriši", "Odpri %@"],
        "hr": ["spreman", "odbrojavanje", "pauza", "nakon vremena", "Pokreni", "Pauziraj", "Nastavi", "Zaustavi", "Odustani", "utišaj zvuk", "uključi zvuk", "Zatvori", "Zvuk", "Spremi", "Obriši", "Otvori %@"],
        "sr": ["спреман", "одбројавање", "пауза", "после времена", "Покрени", "Пауза", "Настави", "Заустави", "Поништи", "утишај звук", "укључи звук", "Изађи", "Sound", "Save", "Delete", "Отвори %@"],
        "bg": ["готов", "отброяване", "пауза", "след времето", "Старт", "Пауза", "Продължи", "Спри", "Нулирай", "заглуши звука", "включи звука", "Изход", "Sound", "Save", "Delete", "Отвори %@"],
        "ro": ["pregătit", "numără", "pauză", "peste timp", "Start", "Suspendați", "Continuați", "Oprește", "Anulați", "oprește sunetul", "pornește sunetul", "Închideți aplicația", "Sunet", "Salvați", "Ștergeți", "Deschide %@"],
        "hu": ["kész", "visszaszámlálás", "szünet", "túlfutás", "Indítás", "Szünet", "Folytatás", "Leállítás", "Mégsem", "hang némítása", "hang bekapcsolása", "Kilépés", "Hang", "Mentés", "Törlés", "%@ megnyitása"],
        "el": ["έτοιμο", "αντίστροφη μέτρηση", "παύση", "υπέρβαση", "Έναρξη", "Παύση", "Συνέχιση", "Διακοπή", "Ακύρωση", "σίγαση ήχου", "ενεργοποίηση ήχου", "Τερματισμός", "Ήχος", "Αποθήκευση", "Διαγραφή", "Άνοιγμα %@"],
        "tr": ["hazır", "geri sayım", "duraklatıldı", "süre aşımı", "Başlat", "Duraklat", "Sürdür", "Durdur", "Vazgeç", "sesi kapat", "sesi aç", "Çık", "Ses", "Kaydet", "Sil", "%@ uygulamasını aç"],
        "uk": ["готово", "відлік", "пауза", "після часу", "Старт", "Пауза", "Далі", "Зупинити", "Скинути", "вимкнути звук", "увімкнути звук", "Завершити", "Звук", "Зберегти", "Видалити", "Відкрити %@"],
        "ru": ["готов", "отсчёт", "пауза", "после времени", "Старт", "Пауза", "Возобновить", "Остановить", "Отмена", "выключить звук", "включить звук", "Завершить", "Звук", "Сохранить", "Удалить", "Открыть %@"],
        "be": ["гатова", "адлік", "паўза", "пасля часу", "Старт", "Паўза", "Працягнуць", "Спыніць", "Скінуць", "выключыць гук", "уключыць гук", "Выйсці", "Sound", "Save", "Delete", "Адкрыць %@"],
        "lt": ["paruošta", "skaičiuoja", "pauzė", "viršyta", "Pradėti", "Pauzė", "Tęsti", "Stabdyti", "Iš naujo", "išjungti garsą", "įjungti garsą", "Baigti", "Sound", "Save", "Delete", "Atidaryti %@"],
        "lv": ["gatavs", "atskaite", "pauze", "pēc laika", "Sākt", "Pauze", "Turpināt", "Apturēt", "Atiestatīt", "izslēgt skaņu", "ieslēgt skaņu", "Iziet", "Sound", "Save", "Delete", "Atvērt %@"],
        "et": ["valmis", "loendab", "paus", "üleaeg", "Alusta", "Paus", "Jätka", "Peata", "Lähtesta", "vaigista heli", "lülita heli sisse", "Lõpeta", "Sound", "Save", "Delete", "Ava %@"],
        "ca": ["a punt", "compte enrere", "pausa", "temps extra", "Inicia", "Posa en pausa", "Reprèn", "Atura", "Cancel·la", "silencia el so", "activa el so", "Surt", "So", "Desa", "Elimina", "Obrir %@"],
        "ar": ["جاهز", "العد التنازلي", "متوقف مؤقتاً", "بعد الوقت", "بدء", "إيقاف مؤقت", "استئناف", "إيقاف", "إلغاء", "كتم الصوت", "تشغيل الصوت", "إنهاء", "الصوت", "حفظ", "حذف", "فتح %@"],
        "he": ["מוכן", "סופר", "מושהה", "אחרי הזמן", "התחלה", "השהיה", "המשך", "עצור", "ביטול", "השתק צליל", "הפעל צליל", "סיום", "צליל", "שמירה", "מחיקה", "פתח את %@"],
        "fa": ["آماده", "شمارش معکوس", "مکث", "پس از زمان", "شروع", "مکث", "ادامه", "توقف", "بازنشانی", "بی‌صدا کردن", "پخش صدا", "خروج", "Sound", "Save", "Delete", "باز کردن %@"],
        "hi": ["तैयार", "गिनती", "रुका", "समय के बाद", "शुरू करें", "पॉज़ करें", "जारी रखें", "बंद करें", "रद्द करें", "ध्वनि बंद करें", "ध्वनि चालू करें", "बंद करें", "ध्वनि", "सहेजें", "डिलीट करें", "%@ खोलें"],
        "bn": ["প্রস্তুত", "গণনা চলছে", "বিরতি", "সময়ের পরে", "শুরু", "বিরতি", "চালিয়ে যান", "থামান", "রিসেট", "শব্দ বন্ধ করুন", "শব্দ চালু করুন", "বন্ধ করুন", "Sound", "Save", "Delete", "%@ খুলুন"],
        "th": ["พร้อม", "กำลังนับ", "หยุดชั่วคราว", "เลยเวลา", "เริ่ม", "หยุดพัก", "นับต่อ", "หยุด", "ยกเลิก", "ปิดเสียง", "เปิดเสียง", "ออก", "เสียง", "บันทึก", "ลบ", "เปิด %@"],
        "vi": ["sẵn sàng", "đang đếm", "tạm dừng", "quá giờ", "Bắt đầu", "Tạm dừng", "Tiếp tục", "Dừng", "Hủy", "tắt tiếng", "bật tiếng", "Thoát", "Âm thanh", "Lưu", "Xóa", "Mở %@"],
        "id": ["siap", "menghitung", "jeda", "lewat waktu", "Mulai", "Jeda", "Lanjutkan", "Berhenti", "Batalkan", "bisukan suara", "nyalakan suara", "Tutup", "Bunyi", "Simpan", "Hapus", "Buka %@"],
        "ms": ["sedia", "mengira", "jeda", "lebih masa", "Mula", "Jeda", "Teruskan", "Henti", "Batal", "senyapkan bunyi", "hidupkan bunyi", "Keluar", "Bunyi", "Simpan", "Padam", "Buka %@"],
        "zh-Hans": ["就绪", "倒计时", "暂停", "超时", "开始计时", "暂停", "继续", "停止", "取消", "静音", "打开声音", "退出", "铃声", "保存", "删除", "打开 %@"],
        "zh-Hant": ["就緒", "倒數", "暫停", "超時", "開始", "暫停", "繼續", "停止", "取消", "靜音", "開啟聲音", "結束", "提示聲", "儲存", "刪除", "打開 %@"],
        "ja": ["準備完了", "カウント中", "一時停止", "超過", "開始", "一時停止", "再開", "停止", "キャンセル", "音を消す", "音を出す", "終了", "サウンド", "保存", "削除", "%@ を開く"],
        "ko": ["준비됨", "카운트다운", "일시정지", "초과", "시작", "일시 정지", "재개", "정지", "취소", "소리 끄기", "소리 켜기", "종료", "사운드", "저장", "삭제", "%@ 열기"],
    ]
}
