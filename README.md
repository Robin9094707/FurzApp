# RJ Furz-App 💨

Eine vollständig native SwiftUI-App für iPhone/iPad, um eigene Furz-Aufnahmen aufzunehmen, zu importieren, zu bewerten, zu organisieren und langfristig lokal zu archivieren.

## Highlights

- Mikrofonaufnahme als hochwertige M4A-Datei
- Live-Wellenform beim Aufnehmen
- Audio-Player mit Wellenform, Scrubbing und 0,75×–1,5× Tempo
- Audio-Zuschnitt mit sicherem Ersetzen erst nach erfolgreichem Export
- Audio-Import über den iOS-Dateiauswahldialog (`UTType.audio`)
- Manuelle Einträge ohne Audio
- Name, Datum/Uhrzeit, Lautstärke, Geruchsintensität, persönliche 1–5-Bewertung
- Ort, Situation, Tags, Notizen und Favoriten
- Eigene Ordner, z. B. Arbeit / Zuhause / harte Fürze / leise Fürze
- Suche, Filter, Favoritenfilter und mehrere Sortierungen
- Kalenderansicht pro Tag
- Charts-Statistik mit 14-Tage-Verlauf und Lautstärke-Verteilung
- Furzwecker/Erinnerungen: täglich oder frei gewählte Wochentage
- Teilen einzelner Audio-Dateien
- JSON-Metadatenexport
- kompletter Reset mit Bestätigungsdialog
- lokaler Debug-Log
- Liquid Glass auf iOS 26+
- Dark Mode, Dynamic Type, VoiceOver-freundliche Labels und Haptics
- komplett lokal, kein Account und kein Server nötig

## Sprachmemos-Import

iOS stellt Drittanbieter-Apps keine öffentliche API bereit, um die private Sprachmemos-Datenbank direkt auszulesen. Exportiere eine Sprachmemo daher über **Teilen → In Dateien sichern** und importiere die Audiodatei anschließend in der RJ Furz-App. Andere Audio-Dateien aus Dateien funktionieren genauso.

## Build als unsigned IPA mit GitHub Actions

1. Repository auf GitHub öffnen.
2. **Actions → Build RJ Furz-App IPA → Run workflow**.
3. Nach erfolgreichem Build das Artifact **RJ-FurzApp-unsigned-IPA** öffnen.
4. Darin liegt `RJ-FurzApp-unsigned.ipa`.
5. Die IPA anschließend mit deinem eigenen Signaturdienst signieren/installieren.

Der Workflow nutzt `macos-26`, Xcode 26.5, XcodeGen und baut explizit mit deaktivierter Code-Signierung.

## Entwicklung lokal

```bash
brew install xcodegen
xcodegen generate --spec project.yml
open RJFurzApp.xcodeproj
```

Bundle-ID: `eu.rjuhas.furzapp`

Deployment Target: iOS 26.0
