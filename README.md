# Alarm System - Zentrale Integration

Komplettes Alarmierungssystem mit Monitor, Messenger und Mail Parser als integrierte Docker-Compose-Lösung.

## Übersicht

Dieses Repository stellt die zentrale Konfiguration und Docker-Compose-Orchestrierung für das vollständige Feuerwehr-Alarmierungssystem bereit. Es integriert drei spezialisierte Komponenten in einem einheitlichen Setup:

### Systemarchitektur

```
┌─────────────────┐
│  IMAP Postfach  │ (Leitstelle sendet Alarm-E-Mails)
│  (Feuerwehr)    │
└────────┬────────┘
         │
         v
┌─────────────────┐
│  alarm-mail     │ Service pollt IMAP und parst XML
│  Service        │ (Keine externe Ports)
└────────┬────────┘
         │
         ├──────────────────────┐
         │                      │
         v                      v
┌─────────────────┐    ┌─────────────────┐
│ alarm-monitor   │◄───┤ alarm-messenger │
│  Dashboard      │    │  Push Notify    │
│  Port: 8000     │    │  Port: 3000     │
└─────────────────┘    └─────────┬───────┘
         │                       │
         │                       │ WebSocket
         v                       v
  Web Browser           Mobile Geräte (iOS/Android)
```

### Komponenten

1. **[alarm-mail](https://github.com/TimUx/alarm-mail)**
   - Pollt IMAP-Postfach nach Alarm-E-Mails
   - Parst XML-formatierte Einsatzinformationen
   - Leitet Alarme an Monitor und Messenger weiter
   - Keine externen Ports erforderlich

2. **[alarm-monitor](https://github.com/TimUx/alarm-monitor/tree/copilot/integrate-alarm-messenger-function)**
   - Webbasiertes Dashboard zur Alarmvisualisierung
   - Zeigt Karten, Wetter, Einsatzkräfte
   - Ruft Rückmeldungen vom Messenger ab
   - Port: 8000 (extern zugänglich)

3. **[alarm-messenger](https://github.com/TimUx/alarm-messenger)**
   - WebSocket-basierte Push-Benachrichtigungen
   - Mobile App für iOS und Android
   - Admin-Interface zur Geräteverwaltung
   - QR-Code-basierte Geräteregistrierung
   - Port: 3000 (extern zugänglich für Admin-UI und WebSocket)

### Kommunikationsübersicht

#### Interne Kommunikation (Docker-Netzwerk)
Alle Services kommunizieren über das interne `alarm-network` Docker-Netzwerk:

| Von | Nach | Endpunkt | Auth | Zweck |
|-----|------|----------|------|-------|
| alarm-mail | alarm-monitor | `POST /api/alarm` | X-API-Key | Alarm senden |
| alarm-mail | alarm-messenger | `POST /api/emergencies` | X-API-Key | Alarm senden |
| alarm-monitor | alarm-messenger | `GET /api/emergencies/:id/participants` | X-API-Key | Rückmeldungen abrufen |

#### Externe Kommunikation
Nur folgende Dienste benötigen externe Ports:

| Service | Port | Zweck | Nutzer |
|---------|------|-------|--------|
| alarm-monitor | 8000 | Dashboard Web-UI | Browser |
| alarm-messenger | 3000 | Admin-UI + WebSocket | Browser + Mobile Apps |
| caddy (optional) | 80/443 | Reverse Proxy mit SSL | Alle |

## Schnellstart

### Voraussetzungen

- Docker Engine 20.10+
- Docker Compose v2.0+
- Zugang zu einem IMAP-Postfach für Alarm-E-Mails

### Installation

1. **Repository klonen**
   ```bash
   git clone https://github.com/TimUx/alarm-system.git
   cd alarm-system
   ```

2. **Konfiguration erstellen**
   ```bash
   cp .env.example .env
   ```

3. **.env anpassen**
   
   Mindestens folgende Werte müssen angepasst werden:
   
   ```bash
   # IMAP-Zugangsdaten
   ALARM_MAIL_IMAP_HOST=imap.example.com
   ALARM_MAIL_IMAP_USERNAME=alarm@example.com
   ALARM_MAIL_IMAP_PASSWORD=ihr-sicheres-passwort
   
   # API-Schlüssel generieren (mit openssl rand -hex 32)
   ALARM_MONITOR_API_KEY=generierter-schlüssel-für-monitor
   ALARM_MESSENGER_API_SECRET_KEY=generierter-schlüssel-für-messenger
   ALARM_MESSENGER_JWT_SECRET=generierter-jwt-secret
   
   # Server-URL für Messenger (für QR-Code-Generierung)
   ALARM_MESSENGER_SERVER_URL=http://ihre-server-ip:3000
   ```
   
   **Tipp:** Verwenden Sie `make generate-keys` um sichere API-Schlüssel zu generieren.

4. **Konfiguration validieren (empfohlen)**
   ```bash
   ./validate-config.sh
   # oder
   make validate
   ```
   
   Das Skript prüft, ob alle erforderlichen Einstellungen korrekt sind.

5. **System starten**
   ```bash
   docker-compose up -d
   # oder mit Makefile
   make start
   ```

6. **Logs überwachen**
   ```bash
   docker-compose logs -f
   # oder mit Makefile
   make logs
   ```

7. **Zugriff auf Dienste**
   - Dashboard: http://localhost:8000
   - Messenger Admin: http://localhost:3000/admin/

### Erster Start - Admin-Benutzer erstellen

Für das Messenger-Admin-Interface muss zunächst ein Admin-Benutzer erstellt werden:

```bash
curl -X POST http://localhost:3000/api/admin/init \
  -H "Content-Type: application/json" \
  -d '{"username":"admin","password":"ihr-sicheres-passwort"}'
```

Danach können Sie sich unter `http://localhost:3000/admin/login.html` anmelden.

## Deployment mit SSL/TLS (Produktion)

Für Produktionsbetrieb mit automatischem HTTPS empfiehlt sich die Verwendung des integrierten Caddy-Reverse-Proxys:

1. **.env erweitern**
   ```bash
   ALARM_MONITOR_DOMAIN=monitor.ihre-domain.de
   ALARM_MESSENGER_DOMAIN=messenger.ihre-domain.de
   ALARM_MESSENGER_SERVER_URL=https://messenger.ihre-domain.de
   ```

2. **DNS-Einträge erstellen**
   - `monitor.ihre-domain.de` → Server-IP
   - `messenger.ihre-domain.de` → Server-IP

3. **Mit Caddy starten**
   ```bash
   docker-compose --profile with-caddy up -d
   ```

Caddy holt automatisch Let's Encrypt Zertifikate und erneuert diese.

## Konfiguration

Alle Konfigurationen erfolgen über Umgebungsvariablen in der `.env` Datei.

### Wichtige Einstellungen

#### IMAP-Konfiguration (Pflicht)
```bash
ALARM_MAIL_IMAP_HOST=imap.example.com
ALARM_MAIL_IMAP_USERNAME=alarm@example.com
ALARM_MAIL_IMAP_PASSWORD=geheim
ALARM_MAIL_POLL_INTERVAL=60  # Abrufintervall in Sekunden
```

#### API-Schlüssel (Pflicht)
```bash
# Generieren mit: openssl rand -hex 32
ALARM_MONITOR_API_KEY=zufälliger-schlüssel-32-zeichen
ALARM_MESSENGER_API_SECRET_KEY=anderer-zufälliger-schlüssel
ALARM_MESSENGER_JWT_SECRET=jwt-geheimnis-für-admin
```

**Wichtig:** Die API-Schlüssel müssen zwischen den Services übereinstimmen!

### Vollständige Konfigurationsreferenz

Siehe [.env.example](./.env.example) für alle verfügbaren Optionen mit Erklärungen.

## Betrieb und Wartung

### Helper-Tools

Das Repository enthält hilfreiche Tools für die Verwaltung:

**Makefile-Befehle:**
```bash
make help          # Zeigt alle verfügbaren Befehle
make setup         # Erstellt .env aus .env.example
make validate      # Validiert Konfiguration
make start         # Startet alle Services
make start-ssl     # Startet mit Caddy SSL/TLS
make stop          # Stoppt alle Services
make restart       # Startet Services neu
make status        # Zeigt Service-Status
make logs          # Zeigt Logs aller Services
make logs-mail     # Zeigt nur alarm-mail Logs
make update        # Aktualisiert Images und startet neu
make backup        # Erstellt Backup aller Daten
make generate-keys # Generiert sichere API-Schlüssel
```

**Validierungs-Skript:**
```bash
./validate-config.sh
```
Prüft:
- Ob .env vorhanden und korrekt konfiguriert ist
- Ob alle Pflichtfelder gesetzt sind
- Ob API-Schlüssel sicher genug sind
- Ob Docker installiert ist
- Ob Ports verfügbar sind

### Status überprüfen
```bash
docker-compose ps
```

### Logs anzeigen
```bash
# Alle Services
docker-compose logs -f

# Einzelner Service
docker-compose logs -f alarm-mail
docker-compose logs -f alarm-monitor
docker-compose logs -f alarm-messenger
```

### Services neu starten
```bash
docker-compose restart
```

### System aktualisieren
```bash
# Images neu herunterladen
docker-compose pull

# Services neu starten
docker-compose up -d
```

### System stoppen
```bash
docker-compose down
```

### Daten sichern
```bash
# Datenbank und Konfigurationen sind in Docker Volumes gespeichert
docker volume ls | grep alarm

# Backup erstellen
docker run --rm -v alarm-system_alarm-monitor-data:/data \
  -v $(pwd)/backup:/backup alpine tar czf /backup/monitor-data.tar.gz /data

docker run --rm -v alarm-system_alarm-messenger-data:/data \
  -v $(pwd)/backup:/backup alpine tar czf /backup/messenger-data.tar.gz /data
```

## Troubleshooting

### Alarm-Mail empfängt keine E-Mails

1. **IMAP-Verbindung testen**
   ```bash
   docker-compose logs alarm-mail
   ```
   Suchen Sie nach Verbindungsfehlern.

2. **IMAP-Zugangsdaten prüfen**
   ```bash
   # .env überprüfen
   grep IMAP .env
   ```

3. **Netzwerk testen**
   ```bash
   docker-compose exec alarm-mail ping imap.example.com
   ```

### Alarm-Monitor zeigt keine Alarme

1. **API-Schlüssel überprüfen**
   ```bash
   # Müssen identisch sein
   grep ALARM_MONITOR_API_KEY .env
   ```

2. **Logs prüfen**
   ```bash
   docker-compose logs alarm-monitor | grep -i "unauthorized\|error"
   ```

### Messenger sendet keine Push-Benachrichtigungen

1. **WebSocket-Verbindung prüfen**
   - Browser-Konsole öffnen (F12)
   - Nach WebSocket-Fehlern suchen

2. **Server-URL validieren**
   ```bash
   grep ALARM_MESSENGER_SERVER_URL .env
   # Muss von Mobile-Geräten erreichbar sein!
   ```

3. **Geräteregistrierung testen**
   - QR-Code im Admin-Interface generieren
   - Mit Mobile-App scannen
   - Logs überprüfen

### Ports bereits belegt

Wenn Ports 8000 oder 3000 bereits belegt sind:

```bash
# .env anpassen
ALARM_MONITOR_PORT=8080
ALARM_MESSENGER_PORT=3030
```

## Mobile App Setup

Die Mobile App für iOS und Android befindet sich im [alarm-messenger Repository](https://github.com/TimUx/alarm-messenger/tree/main/mobile).

### Geräteregistrierung

1. Admin meldet sich im Admin-Interface an
2. QR-Code generieren unter `/admin/`
3. Mobile App öffnen und QR-Code scannen
4. Gerät wird automatisch registriert
5. WebSocket-Verbindung wird hergestellt

### Mobile App Build

Siehe [alarm-messenger/docs/MOBILE.md](https://github.com/TimUx/alarm-messenger/blob/main/docs/MOBILE.md) für Details zum Build-Prozess.

## Sicherheit

### Best Practices

1. **Starke API-Schlüssel verwenden**
   ```bash
   openssl rand -hex 32
   ```

2. **HTTPS in Produktion aktivieren**
   - Caddy-Profil verwenden
   - Gültige Domain-Namen konfigurieren

3. **Firewall-Regeln setzen**
   ```bash
   # Nur notwendige Ports öffnen
   ufw allow 80/tcp   # HTTP (Caddy)
   ufw allow 443/tcp  # HTTPS (Caddy)
   ```

4. **Zugriff beschränken**
   - Monitor nur im lokalen Netzwerk
   - Messenger über VPN oder IP-Whitelist

5. **Regelmäßige Updates**
   ```bash
   docker-compose pull
   docker-compose up -d
   ```

### Secrets Management

Niemals API-Schlüssel in Git committen! Die `.env` Datei ist in `.gitignore` enthalten.

## Entwicklung

### Lokale Entwicklung

Für Entwicklung an einzelnen Komponenten siehe die jeweiligen Repositories:

- [alarm-mail Development](https://github.com/TimUx/alarm-mail#entwicklung)
- [alarm-monitor Development](https://github.com/TimUx/alarm-monitor#entwicklung)
- [alarm-messenger Development](https://github.com/TimUx/alarm-messenger#projektstruktur)

### Custom Images verwenden

Um lokale Entwicklungsversionen zu nutzen:

```yaml
# docker-compose.override.yml erstellen
version: '3.8'
services:
  alarm-monitor:
    build: ./path/to/local/alarm-monitor
    image: alarm-monitor:dev
```

## Support und Beiträge

- **Issues:** https://github.com/TimUx/alarm-system/issues
- **Discussions:** https://github.com/TimUx/alarm-system/discussions

Für komponentenspezifische Fragen siehe die jeweiligen Repositories.

## Lizenz

MIT License - siehe [LICENSE](LICENSE) Datei.

## Architektur-Details

### Netzwerk

Alle Services sind im `alarm-network` Bridge-Netzwerk verbunden:

```bash
docker network inspect alarm-system_alarm-network
```

### Persistenz

Folgende Docker Volumes speichern persistente Daten:

- `alarm-monitor-data`: Alarm-Historie und Konfiguration
- `alarm-messenger-data`: SQLite-Datenbank mit Geräten und Einsätzen
- `caddy-data`: SSL-Zertifikate und Caddy-Daten
- `caddy-config`: Caddy-Konfiguration

### Health Checks

Alle Services haben Health Checks konfiguriert:

```bash
docker-compose ps
# STATUS zeigt (healthy) wenn alles OK ist
```

### Service Dependencies

Das System startet in der richtigen Reihenfolge:

1. alarm-monitor und alarm-messenger starten parallel
2. alarm-mail wartet auf beide (depends_on mit health checks)
3. caddy (optional) startet wenn Monitor und Messenger bereit sind

## Weiterführende Dokumentation

- [alarm-mail README](https://github.com/TimUx/alarm-mail/blob/main/README.md)
- [alarm-monitor README](https://github.com/TimUx/alarm-monitor/blob/main/README.md)
- [alarm-messenger README](https://github.com/TimUx/alarm-messenger/blob/main/README.md)
- [alarm-messenger API Docs](https://github.com/TimUx/alarm-messenger/blob/main/docs/API.md)
- [Docker Image CI/CD Setup](docs/DOCKER_IMAGE_WORKFLOWS.md) - Automatisierte Image Builds für GHCR
