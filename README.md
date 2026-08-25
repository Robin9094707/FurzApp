# RJ Furz-App 2.0 💨

Eine native SwiftUI-/SwiftData-App für iOS 26, die das völlig unnötig professionelle Furz-Archiv mit Widgets, Karte, AlarmKit und einem optionalen privaten Furzfreunde-Backend kombiniert.

## Neu in 2.0

- **Notfall-Furz Widget** für Home Screen: klein/mittel/groß, Zähler, Score, wechselnde Sprüche und direkter Recorder-Knopf
- **Control-Center-Control** „Furzaufnahme“ für sofortiges Öffnen des Recorders
- frei wählbarer Widget-Zeitraum: App-Standard, 24 h, 7 Tage, 30 Tage, aktuelle Woche oder insgesamt
- **100 lustige Sprüche** abhängig von Furzanzahl und Score
- optionale Standorterfassung pro Furz
- Reverse-Geocoding in eine lesbare Adresse
- eigene **Furz-Orte / Geofences** wie Zuhause, Arbeit oder Lieblingsort
- lokale **Furz-Heatmap** mit 24 h / 7 d / 30 d / Woche / Gesamt
- verbesserter Audio-Zuschnitt mit sichtbarer Auswahl, Schnittlinien, Wellenform und Probehören nur des gewählten Bereichs
- **AlarmKit-Furzwecker** mit täglichen oder frei wählbaren Wochentagen
- alternative normale lokale Erinnerungen
- **Windstille-Alarm** nach X Stunden ohne neuen Eintrag
- optionales **Furzfreunde-Backend** in Python
- Freunde hinzufügen/entfernen, Anfragen bestätigen
- gemeinsamer Feed, Kommentare und geteilte Audio-Aufnahmen
- 7-Tage-Furzliga mit Anzahl, Score, Ø Geruchsintensität und Bewertung
- freiwillige Standort- und Akkufreigabe
- Furz-Anstupser; Empfänger muss bestätigen, bevor lokal ein Alarm erzeugt wird

## Die klassische Furz-App bleibt komplett dabei

- hochwertige M4A-Aufnahme mit Live-Pegel/Wellenform
- Audio-Import über Dateien
- Name, Datum/Uhrzeit, Lautstärke, Geruch 1–5, Bewertung 1–5
- Ortstext, Situation, Tags, Notizen, Favoriten
- eigene Ordner
- Suche, Filter und Sortierung
- Kalender
- Charts/Statistiken
- Audio teilen
- JSON-Export inklusive optionaler Standortdaten
- Bestätigungsdialoge bei destruktiven Aktionen
- Liquid Glass auf iOS 26+
- Dark Mode, Dynamic Type, Haptics

## Datenschutz-Prinzip

Die App funktioniert weiterhin **vollständig lokal ohne Account**. Standortaufnahme, Furzfreunde, Standortfreigabe, Akkufreigabe und Audiofreigabe sind separate optionale Schalter. Ein lokal gespeicherter Standort wird nicht automatisch ans Backend übertragen.

Kontinuierliche Hintergrund-Standortfreigabe wird nur eingeschaltet, wenn das Furzfreunde-Backend **und** die Standortfreigabe aktiviert sind. iOS verlangt dafür die entsprechende „Immer“-Standortberechtigung.

## Sprachmemos importieren

iOS stellt Drittanbieter-Apps keine öffentliche API bereit, um die private Sprachmemos-Datenbank direkt auszulesen. Eine Sprachmemo über **Teilen → In Dateien sichern** exportieren und anschließend in der RJ Furz-App importieren.

## Privates Python-Backend

Siehe [`Backend/README.md`](Backend/README.md).

Kurz:

```bash
cd Backend
python -m pip install -r requirements.txt
python rj_furz_backend.py
```

Beim ersten Start erstellt das Script `furz_backend_config.json` mit einem zufällig generierten Hauptpasswort und stoppt. Konfiguration prüfen, `setup_complete` auf `true` setzen und erneut starten.

Für Internetzugriff: **HTTPS über Reverse Proxy** benutzen. Im privaten LAN akzeptiert die iOS-App auch eine explizite `http://IP:Port`-Adresse.

## Unsigned IPA mit GitHub Actions

1. Repository öffnen.
2. **Actions → Build RJ Furz-App v2 IPA → Run workflow**.
3. Artifact **RJ-FurzApp-v2-unsigned-IPA** herunterladen.
4. Darin liegt `RJ-FurzApp-v2-unsigned.ipa`.
5. Mit dem eigenen Signaturdienst signieren/installieren.

Der Workflow nutzt `macos-26`, Xcode 26.5 und XcodeGen. Code Signing wird beim CI-Build deaktiviert. Zusätzlich bricht der Workflow ab, falls die Widget-Extension nicht als `.appex` in die App eingebettet wurde.

### Wichtig für Widgets beim Sideloading

Die Haupt-App und Widget-Extension verwenden die App Group:

`group.eu.rjuhas.furzapp.shared`

Der Signaturdienst muss Widget-Extension und App-Group-Entitlements korrekt mitsignieren. Sonst kann die App selbst laufen, während das Widget den gemeinsamen Zähler nicht lesen kann.

## Entwicklung lokal

```bash
brew install xcodegen
xcodegen generate --spec project.yml
open RJFurzApp.xcodeproj
```

- App Bundle-ID: `eu.rjuhas.furzapp`
- Widget Bundle-ID: `eu.rjuhas.furzapp.widgets`
- Deployment Target: iOS 26.0
