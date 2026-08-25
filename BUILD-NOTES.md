# Build Notes – RJ Furz-App 2.0

- Target: iOS 26.0+
- Xcode CI: 26.5
- SwiftUI + SwiftData + WidgetKit + AppIntents + AlarmKit + CoreLocation + MapKit
- Projektdatei wird mit XcodeGen aus `project.yml` erzeugt.
- Unsigned Device Build: `CODE_SIGNING_ALLOWED=NO`.
- IPA-Struktur: `Payload/RJ Furz-App.app` inklusive eingebetteter Widget-Extension.

## Sideload-Hinweis
Widgets benötigen beim anschließenden Signieren funktionierende Entitlements für Haupt-App und Widget-Extension sowie die gemeinsame App Group `group.eu.rjuhas.furzapp.shared`.

## Backend
`Backend/rj_furz_backend.py` ist unabhängig vom iOS-Build. Erster Start erzeugt die Konfiguration. `Backend/furz_backend_config.json` und `Backend/furz_data/` sind absichtlich per `.gitignore` ausgeschlossen.
