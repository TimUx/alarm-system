# Architektur und Kommunikation

Dieses Dokument beschreibt die detaillierte Architektur und Kommunikationswege des Alarm-Systems.

## Systemübersicht

Das Alarm-System besteht aus drei Hauptkomponenten, die als Docker-Container betrieben werden und über ein gemeinsames Docker-Netzwerk kommunizieren.

## Komponenten-Details

### 1. alarm-mail

**Zweck:** IMAP-Poller und XML-Parser für Alarm-E-Mails

**Technology Stack:**
- Python 3.11
- Flask
- Gunicorn

**Kommunikation:**
- **Eingehend:** Keine (kein externer Port)
  - HTTP Health-Check (intern, Port 8000): `/health`
- **Ausgehend:**
  - IMAP-Server (Port 993/TCP, SSL)
  - alarm-monitor (HTTP, intern)
  - alarm-messenger (HTTP, intern)

**Docker-Image:** `ghcr.io/timux/alarm-mail:latest`

**Wichtige Umgebungsvariablen:**
```
ALARM_MAIL_IMAP_HOST
ALARM_MAIL_IMAP_USERNAME
ALARM_MAIL_IMAP_PASSWORD
ALARM_MAIL_ALARM_MONITOR_URL=http://alarm-monitor:8000
ALARM_MAIL_ALARM_MONITOR_API_KEY
ALARM_MAIL_ALARM_MESSENGER_URL=http://alarm-messenger:3000
ALARM_MAIL_ALARM_MESSENGER_API_KEY
```

**Hinweis:** alarm-mail läuft intern auf Port 8000 mit einer Flask-App, die einen `/health` Endpunkt bereitstellt. Der Port wird jedoch nicht nach außen exponiert, da kein externer Zugriff benötigt wird.

### 2. alarm-monitor

**Zweck:** Webbasiertes Dashboard zur Visualisierung von Alarmen

**Technology Stack:**
- Python 3.11
- Flask
- Gunicorn
- Leaflet.js (Karten)

**Kommunikation:**
- **Eingehend:**
  - Port 8000/TCP (extern): Web-Dashboard
  - HTTP POST `/api/alarm` (intern): Alarm-Empfang von alarm-mail
- **Ausgehend:**
  - alarm-messenger (HTTP GET, intern): Teilnehmer-Abfragen

**Docker-Image:** `ghcr.io/timux/alarm-monitor:copilot-integrate-alarm-messenger-function`

**Wichtige Umgebungsvariablen:**
```
ALARM_DASHBOARD_API_KEY
ALARM_DASHBOARD_MESSENGER_SERVER_URL=http://alarm-messenger:3000
ALARM_DASHBOARD_MESSENGER_API_KEY
```

**API-Endpunkte:**
- `POST /api/alarm` - Alarm empfangen (mit X-API-Key Header)
- `GET /api/alarm` - Aktuellen Alarm abrufen
- `GET /api/history` - Alarm-Historie abrufen
- `GET /api/alarm/participants/<incident_number>` - Teilnehmer eines Einsatzes
- `GET /health` - Health Check

### 3. alarm-messenger

**Zweck:** WebSocket-basierte Push-Benachrichtigungen für Mobile-Apps

**Technology Stack:**
- Node.js 18+
- Express
- TypeScript
- SQLite
- WebSocket

**Kommunikation:**
- **Eingehend:**
  - Port 3000/TCP (extern): Admin-UI, WebSocket, API
  - HTTP POST `/api/emergencies` (intern): Alarm-Empfang von alarm-mail
  - HTTP GET `/api/emergencies/:id/participants` (intern): Teilnehmer-Abfrage von alarm-monitor
- **Ausgehend:**
  - WebSocket Push zu Mobile-Geräten

**Docker-Image:** `ghcr.io/timux/alarm-messenger:latest`

**Wichtige Umgebungsvariablen:**
```
SERVER_URL (für QR-Code-Generierung)
API_SECRET_KEY
JWT_SECRET
```

**API-Endpunkte:**
- `POST /api/emergencies` - Neuen Einsatz erstellen (mit X-API-Key Header)
- `GET /api/emergencies` - Alle Einsätze abrufen
- `GET /api/emergencies/:id` - Spezifischen Einsatz abrufen
- `GET /api/emergencies/:id/participants` - Teilnehmer abrufen (mit X-API-Key)
- `GET /api/emergencies/:id/responses` - Alle Rückmeldungen
- `POST /api/emergencies/:id/responses` - Rückmeldung senden
- `POST /api/devices/registration-token` - QR-Code generieren
- `POST /api/devices/register` - Gerät registrieren
- `GET /health` - Health Check

## Kommunikationsflüsse

### 1. Alarm-Eingang und Verteilung

```
┌─────────────┐
│ Leitstelle  │
│ IMAP Server │
└──────┬──────┘
       │ SMTP/IMAP
       │ (Port 993)
       v
┌─────────────┐
│ alarm-mail  │ Pollt alle 60s (konfigurierbar)
│             │ Parst XML-E-Mails
└──────┬──────┘
       │
       ├─────────────────────────────────┐
       │                                 │
       │ POST /api/alarm                 │ POST /api/emergencies
       │ X-API-Key: MONITOR_KEY          │ X-API-Key: MESSENGER_KEY
       │                                 │
       v                                 v
┌─────────────┐                   ┌─────────────┐
│alarm-monitor│                   │alarm-       │
│             │                   │ messenger   │
└─────────────┘                   └──────┬──────┘
                                         │
                                         │ WebSocket Push
                                         v
                                  ┌─────────────┐
                                  │Mobile Geräte│
                                  └─────────────┘
```

**Payload-Format (alarm-mail → alarm-monitor):**
```json
{
  "incident_number": "2024-001",
  "timestamp": "2024-12-08T14:30:00",
  "keyword": "BRAND 3",
  "sub_keyword": "Personen in Gefahr",
  "diagnosis": "Wohnungsbrand",
  "remarks": "Starke Rauchentwicklung",
  "location": {
    "street": "Hauptstraße",
    "house_number": "123",
    "city": "Musterstadt",
    "district": "Nordviertel",
    "latitude": 51.2345,
    "longitude": 9.8765
  },
  "aao": "LF Musterstadt 1;DLK Musterstadt",
  "tme_codes": ["WIL26", "WIL41"]
}
```

**Payload-Format (alarm-mail → alarm-messenger):**
```json
{
  "emergencyNumber": "2024-001",
  "emergencyDate": "2024-12-08T14:30:00",
  "emergencyKeyword": "BRAND 3",
  "emergencyDescription": "Wohnungsbrand",
  "emergencyLocation": "Hauptstraße 123, 12345 Musterstadt",
  "groups": "WIL26,WIL41"
}
```

### 2. Rückmeldungen und Teilnehmer-Abfrage

```
Mobile Gerät                     alarm-messenger              alarm-monitor
    │                                   │                            │
    │ POST /api/emergencies/:id/responses                           │
    │ { status: 'accepted', ... }       │                            │
    ├──────────────────────────────────>│                            │
    │                                   │ Speichert in DB            │
    │                                   │                            │
    │                                   │ GET /api/emergencies/:id/participants
    │                                   │        X-API-Key           │
    │                                   │<───────────────────────────┤
    │                                   │                            │
    │                                   │ [Teilnehmer mit Details]   │
    │                                   ├───────────────────────────>│
    │                                   │                            │
    │                                   │                   Dashboard aktualisiert
```

**Teilnehmer-Response-Format:**
```json
[
  {
    "id": 1,
    "emergencyId": "emergency-uuid",
    "deviceId": "device-uuid",
    "status": "accepted",
    "timestamp": "2024-12-08T14:31:00Z",
    "responder": {
      "firstName": "Max",
      "lastName": "Mustermann",
      "qualifications": {
        "machinist": true,
        "agt": true,
        "paramedic": false
      },
      "leadershipRole": "groupLeader"
    }
  }
]
```

## Netzwerk-Konfiguration

### Docker-Netzwerk

Alle Services sind im `alarm-network` Bridge-Netzwerk verbunden:

```yaml
networks:
  alarm-network:
    driver: bridge
    name: alarm-network
```

**DNS-Auflösung:**
- `alarm-mail` → `alarm-mail:8000` (intern)
- `alarm-monitor` → `alarm-monitor:8000` (intern/extern)
- `alarm-messenger` → `alarm-messenger:3000` (intern/extern)

### Port-Mapping

| Container | Interner Port | Externer Port | Zweck |
|-----------|---------------|---------------|-------|
| alarm-mail | 8000 | - | Kein externer Zugriff nötig |
| alarm-monitor | 8000 | 8000 (konfigurierbar) | Dashboard Web-UI |
| alarm-messenger | 3000 | 3000 (konfigurierbar) | Admin-UI + WebSocket |
| caddy (optional) | 80/443 | 80/443 | Reverse Proxy |

### Firewall-Regeln

**Minimale Anforderungen:**

**Ausgehend (alarm-mail):**
- IMAP-Server: Port 993/TCP (SSL)

**Eingehend:**
- Port 8000/TCP: alarm-monitor Dashboard
- Port 3000/TCP: alarm-messenger Admin-UI + WebSocket

**Mit Caddy (empfohlen):**
- Port 80/TCP: HTTP (Redirect zu HTTPS)
- Port 443/TCP: HTTPS
- Port 443/UDP: HTTP/3 (optional)

## Authentifizierung und Autorisierung

### API-Schlüssel-Schema

Das System verwendet drei verschiedene API-Schlüssel:

1. **ALARM_MONITOR_API_KEY**
   - Verwendung: alarm-mail → alarm-monitor
   - Header: `X-API-Key: <key>`
   - Endpunkt: `POST /api/alarm`

2. **ALARM_MESSENGER_API_SECRET_KEY**
   - Verwendung: 
     - alarm-mail → alarm-messenger (`POST /api/emergencies`)
     - alarm-monitor → alarm-messenger (`GET /api/emergencies/:id/participants`)
   - Header: `X-API-Key: <key>`

3. **ALARM_MESSENGER_JWT_SECRET**
   - Verwendung: Admin-Interface-Login
   - Auth: JWT Token nach Login
   - Endpunkte: `/api/admin/*`

### Sicherheits-Best-Practices

1. **API-Schlüssel generieren:**
   ```bash
   openssl rand -hex 32
   ```

2. **Unterschiedliche Schlüssel verwenden:**
   - Jeder Service eigener Schlüssel
   - Niemals gleiche Schlüssel wiederverwenden

3. **Rotation:**
   - Regelmäßig Schlüssel rotieren
   - Bei Kompromittierung sofort ändern

4. **Übertragung:**
   - Intern: HTTP OK (Docker-Netzwerk isoliert)
   - Extern: Nur HTTPS (Caddy aktivieren)

## Data Flow Beispiel

### Vollständiger Alarm-Ablauf

```
T+0s    Leitstelle sendet E-Mail an IMAP-Postfach
        └─> E-Mail enthält XML mit Einsatzdaten

T+30s   alarm-mail pollt IMAP (alle 60s)
        └─> Neue E-Mail gefunden
        └─> XML geparst
        └─> Strukturierte Daten extrahiert

T+31s   alarm-mail sendet POST zu alarm-monitor
        ├─> HTTP POST http://alarm-monitor:8000/api/alarm
        ├─> Header: X-API-Key: monitor-key
        └─> Body: JSON mit Alarmdaten

T+31s   alarm-monitor empfängt Alarm
        ├─> API-Key validiert
        ├─> Daten in AlarmStore gespeichert
        ├─> Dashboard-Clients werden aktualisiert (Auto-Refresh)
        └─> Response: 200 OK

T+31s   alarm-mail sendet POST zu alarm-messenger
        ├─> HTTP POST http://alarm-messenger:3000/api/emergencies
        ├─> Header: X-API-Key: messenger-key
        └─> Body: JSON mit Einsatzdaten

T+31s   alarm-messenger empfängt Einsatz
        ├─> API-Key validiert
        ├─> Einsatz in SQLite-DB gespeichert
        ├─> WebSocket-Push an alle verbundenen Geräte
        └─> Response: 200 OK

T+32s   Mobile Geräte empfangen Push
        ├─> WebSocket Nachricht
        ├─> App zeigt Alarm-UI
        ├─> Alarmton wird abgespielt
        └─> Buttons: "Teilnehmen" / "Ablehnen"

T+45s   Einsatzkraft klickt "Teilnehmen"
        ├─> App sendet POST http://server:3000/api/emergencies/:id/responses
        └─> Status: "accepted"

T+45s   alarm-messenger speichert Rückmeldung
        └─> In SQLite-DB mit Einsatzkraft-Details

T+60s   alarm-monitor fragt Teilnehmer ab
        ├─> GET http://alarm-messenger:3000/api/emergencies/:id/participants
        ├─> Header: X-API-Key: messenger-key
        └─> Response: Liste der Teilnehmer mit Qualifikationen

T+60s   Dashboard zeigt Teilnehmer an
        ├─> Namen der Einsatzkräfte
        ├─> Qualifikationen (AGT, Maschinist, etc.)
        └─> Führungsrollen
```

## Fehlerbehandlung

### alarm-mail

**IMAP-Verbindungsfehler:**
- Retry mit exponential backoff
- Logging des Fehlers
- System läuft weiter (wartet auf nächsten Poll)

**API-Push-Fehler:**
- Logging des Fehlers
- Alarm wird trotzdem als "verarbeitet" markiert
- Kein Retry (E-Mail wird nicht erneut verarbeitet)

### alarm-monitor

**API-Authentifizierung fehlgeschlagen:**
- Response: 401 Unauthorized
- Logging mit Warnung

**Messenger nicht erreichbar:**
- Teilnehmer-Anzeige zeigt "Nicht verfügbar"
- Dashboard funktioniert weiterhin

### alarm-messenger

**WebSocket-Verbindung verloren:**
- Client reconnect automatisch
- Missed messages werden bei reconnect abgerufen

**Datenbank-Fehler:**
- Logging des Fehlers
- Response: 500 Internal Server Error

## Performance und Skalierung

### Ressourcen-Anforderungen

**Minimale Konfiguration:**
```
alarm-mail:      512 MB RAM, 0.5 CPU
alarm-monitor:   1 GB RAM, 1 CPU
alarm-messenger: 1 GB RAM, 1 CPU
```

**Empfohlen für Produktion:**
```
alarm-mail:      1 GB RAM, 1 CPU
alarm-monitor:   2 GB RAM, 2 CPU
alarm-messenger: 2 GB RAM, 2 CPU
```

### Load Characteristics

**alarm-mail:**
- Geringe Last (Polling alle 60s)
- Peak bei E-Mail-Verarbeitung

**alarm-monitor:**
- Geringe bis mittlere Last
- Abhängig von Anzahl der Dashboard-Clients
- Auto-Refresh alle 5 Sekunden

**alarm-messenger:**
- Mittlere Last bei vielen verbundenen Geräten
- WebSocket: persistent connections
- Empfohlen: Maximal 500 gleichzeitige Geräte pro Instanz

### Skalierung

**Horizontal:**
- alarm-messenger kann mit Load-Balancer skaliert werden
- Shared SQLite-DB erforderlich oder Migration zu PostgreSQL

**Vertical:**
- Erhöhen der CPU/RAM-Limits in docker-compose.yml

## Monitoring und Logging

### Health Checks

Alle Services haben Health-Check-Endpunkte:

```bash
curl http://localhost:8000/health  # alarm-mail
curl http://localhost:8000/health  # alarm-monitor
curl http://localhost:3000/health  # alarm-messenger
```

### Docker Health Status

```bash
docker-compose ps
# Zeigt (healthy) wenn alles OK
```

### Logging

**Logs anzeigen:**
```bash
docker-compose logs -f alarm-mail
docker-compose logs -f alarm-monitor
docker-compose logs -f alarm-messenger
```

**Log-Rotation:**
- Docker Standard-Log-Rotation aktiv
- Logs in JSON-Format

### Metriken

**Wichtige Metriken zum Überwachen:**
- alarm-mail: IMAP-Poll-Erfolgsrate, E-Mails verarbeitet
- alarm-monitor: Dashboard-Clients, API-Anfragen
- alarm-messenger: Verbundene Geräte, Push-Erfolgsrate

## Backup und Disaster Recovery

### Zu sichernde Daten

1. **alarm-monitor:**
   - Volume: `alarm-monitor-data`
   - Enthält: `alarm_history.json`

2. **alarm-messenger:**
   - Volume: `alarm-messenger-data`
   - Enthält: `alarm-messenger.db` (SQLite)

3. **Konfiguration:**
   - `.env` Datei
   - `caddy/Caddyfile`

### Backup-Strategie

```bash
# Automatisches Backup-Skript
docker run --rm \
  -v alarm-system_alarm-monitor-data:/data \
  -v $(pwd)/backup:/backup \
  alpine tar czf /backup/monitor-$(date +%Y%m%d).tar.gz /data

docker run --rm \
  -v alarm-system_alarm-messenger-data:/data \
  -v $(pwd)/backup:/backup \
  alpine tar czf /backup/messenger-$(date +%Y%m%d).tar.gz /data
```

### Recovery

```bash
# Restore
docker run --rm \
  -v alarm-system_alarm-monitor-data:/data \
  -v $(pwd)/backup:/backup \
  alpine tar xzf /backup/monitor-20241208.tar.gz -C /

docker run --rm \
  -v alarm-system_alarm-messenger-data:/data \
  -v $(pwd)/backup:/backup \
  alpine tar xzf /backup/messenger-20241208.tar.gz -C /
```

## Weiterführende Dokumentation

- [Docker Compose Referenz](https://docs.docker.com/compose/)
- [alarm-mail API](https://github.com/TimUx/alarm-mail)
- [alarm-monitor API](https://github.com/TimUx/alarm-monitor)
- [alarm-messenger API](https://github.com/TimUx/alarm-messenger/blob/main/docs/API.md)
