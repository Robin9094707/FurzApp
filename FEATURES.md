# RJ Furz-App 2.0 – Feature-Matrix

## Archiv & Audio
- Aufnahme M4A / 44.1 kHz / AAC
- Live-Pegel
- Import von Audio-Dateien
- Wellenform-Player, Scrubbing, Geschwindigkeit
- Live-Zuschnitt: sichtbare Start-/Endlinien, Auswahl-Probehören, Abspielposition
- sichere Export-/Replace-Strategie
- Teilen von Audio
- Favoriten, Ordner, Tags, Suche, Filter, Sortierung

## Furz-Metadaten
- Datum/Uhrzeit
- Lautstärke: Leise / Mittel / Laut / Nuklear
- Geruch 1–5
- persönliche Bewertung 1–5
- Dauer, Situation, Notizen
- Furz-Score
- optionale Koordinaten, Adresse und Geofence-Name

## Widgets & Controls
- WidgetKit Extension
- kleines/mittleres/großes Furzzähler-Widget
- 24 h / 7 d / 30 d / Woche / Gesamt
- App-Standard für Widget-Zeitraum
- 100 Sprüche
- App Group für Zähler-Snapshot
- AppIntent-Schnellaufnahme
- Control-Center-Control

## Orte
- freiwillige When-In-Use-Ortung
- freiwillige Always-/Background-Ortung ausschließlich für aktivierte Partnerfreigabe
- Reverse-Geocoding
- eigene Geofences
- automatische Zuordnung zum nächstpassenden Furz-Ort
- Kartenansicht pro Furz
- lokale Raster-Heatmap mit variabler Punktgröße/-intensität

## Erinnerungen
- AlarmKit echter Systemalarm
- tägliche Wiederholung
- frei gewählte Wochentage
- normale lokale Benachrichtigung als Alternative
- Windstille-/Inaktivitäts-Erinnerung
- Partner-Anstupser nur nach Bestätigung

## Furzfreunde
- Backend standardmäßig aus
- Domain oder IP:Port
- serverweites Hauptpasswort + Benutzername
- Sitzungstoken im iOS Keychain
- Freundschaftsanfragen
- Freunde entfernen mit Bestätigung
- Konto löschen mit Bestätigung
- gemeinsamer Feed
- Audiofreigabe optional
- Kommentare
- Rangliste / Score / Geruchs- und Bewertungsdurchschnitt
- Standortfreigabe optional
- Akkufreigabe optional
- letzter Furz / letzter Standortzeitpunkt
- Furz-Anstupser mit Empfänger-Zustimmung

## Python-Backend
- FastAPI + Uvicorn
- First-run config generator
- lesbare JSON-Datenablage
- Audio-Dateien separat
- Token-Ablauf
- Größenlimit für Uploads
- keine öffentliche Fremdregistrierung ohne Hauptpasswort
- Integration-Smoke-Test durchgeführt
