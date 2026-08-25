# RJ Furzfreunde Backend 💨

## Schnellstart

```bash
python -m pip install -r requirements.txt
python rj_furz_backend.py
```

Beim **ersten Start** wird `furz_backend_config.json` erzeugt und das Programm beendet sich. Prüfe dort insbesondere `server_password` und `port`, setze danach `setup_complete` auf `true` und starte das Script erneut.

Danach trägst du in der iOS-App unter **Mehr → Furzfreunde** deine HTTPS-Domain (oder `http://IP:Port` im privaten LAN), den Benutzernamen und das Server-Hauptpasswort ein.

### Daten

Alle Daten liegen neben dem Script im Ordner `furz_data/`:

- `users/<name>.json` – Benutzer, Freundschaften, Freigaben, Anstupser
- `farts/<name>.json` – geteilte Furz-Metadaten und Kommentare
- `audio/<name>/` – freiwillig freigegebene Audio-Dateien
- `sessions.json` – zeitlich begrenzte Sitzungstokens

Ein Benutzer kann in der App sein Backend-Konto löschen. Für eine manuelle Notfall-Löschung kannst du bei gestopptem Server die zugehörigen Benutzer-/Furz-/Audio-Dateien entfernen; nach Neustart werden verwaiste Freundschaftseinträge beim normalen Gebrauch ignoriert.

### Sicherheit

Das Backend ist für einen kleinen privaten, vertrauenswürdigen Kreis gedacht. Alle Konten verwenden – wie gewünscht – **Benutzername + gemeinsames Server-Hauptpasswort**. Wer das Hauptpasswort kennt, kann sich daher grundsätzlich als ein existierender Benutzer anmelden. Gib das Passwort nur Personen, denen du vollständig vertraust.

Für Zugriff über das Internet solltest du zwingend HTTPS über nginx, Caddy oder einen vergleichbaren Reverse Proxy nutzen und die Python-Portfreigabe nicht ungeschützt direkt ins Internet stellen.

Standort, Akku und Audio werden vom iPhone jeweils separat freigegeben. Das Backend kann keinen Alarm heimlich auf einem fremden Gerät setzen: ein Anstupser wird nur gespeichert; das empfangende iPhone fragt vor der lokalen AlarmKit-Erstellung nach Bestätigung.
