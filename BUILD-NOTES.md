# Build Notes

## Golden-Master-Struktur
Dieses Projekt folgt dem bereitgestellten RJ iOS Golden Master:

GitHub Actions → macOS 26 → Xcode 26.5 → XcodeGen → Release/iphoneos → `CODE_SIGNING_ALLOWED=NO` → `.app` → `Payload/` → unsigned IPA.

## Wichtige technische Entscheidungen

- Deployment Target iOS 26.0, weil die App Liquid Glass nativ verwendet.
- SwiftData für strukturierte lokale Metadaten.
- Audios liegen separat in `Application Support/RJFurzAudio`.
- Furzwecker verwenden `UserNotifications` und keine Critical Alerts. Dadurch werden keine speziellen Apple-Entitlements benötigt.
- Kein direkter Zugriff auf Apple Sprachmemos, weil dafür keine öffentliche Datenbank-API existiert.
- Keine Secrets, Zertifikate oder Provisioning Profiles im Repository.

## Temporäre CI-Validierung
Beim initialen automatisierten Aufbau darf der Workflow zusätzlich auf `push` reagieren, damit der erste Build direkt geprüft werden kann. Nach erfolgreicher Prüfung wird der finale Workflow wieder auf ausschließlich `workflow_dispatch` zurückgesetzt.
