# Quickstart Guide

Schnellanleitung für die Installation und Inbetriebnahme des Alarm-Systems.

## Voraussetzungen

- Linux-Server (Ubuntu 20.04+ oder Debian 11+ empfohlen)
- Docker Engine 20.10+
- Docker Compose v2.0+
- Root- oder sudo-Zugriff
- Zugang zu einem IMAP-Postfach für Alarm-E-Mails
- Optional: Domain-Namen für SSL/TLS (Produktion)

## Installation in 10 Minuten

### Schritt 1: Docker installieren

Falls Docker noch nicht installiert ist:

```bash
# Docker Engine installieren
curl -fsSL https://get.docker.com -o get-docker.sh
sudo sh get-docker.sh

# Aktuellen Benutzer zur docker-Gruppe hinzufügen
sudo usermod -aG docker $USER

# Neuanmeldung erforderlich oder:
newgrp docker

# Docker Compose Plugin installieren (falls nicht vorhanden)
sudo apt-get update
sudo apt-get install docker-compose-plugin
```

### Schritt 2: Repository klonen

```bash
cd /opt
sudo git clone https://github.com/TimUx/alarm-system.git
cd alarm-system
sudo chown -R $USER:$USER .
```

### Schritt 3: Konfiguration erstellen

```bash
cp .env.example .env
nano .env  # oder vi/vim verwenden
```

**Minimale erforderliche Anpassungen:**

```bash
# IMAP-Zugangsdaten (PFLICHT)
ALARM_MAIL_IMAP_HOST=imap.ihr-provider.de
ALARM_MAIL_IMAP_USERNAME=alarm@ihre-domain.de
ALARM_MAIL_IMAP_PASSWORD=IhrSicheresPasswort

# API-Schlüssel generieren (PFLICHT)
# Führen Sie aus: openssl rand -hex 32
ALARM_MONITOR_API_KEY=<generierter-schlüssel-1>
ALARM_MESSENGER_API_SECRET_KEY=<generierter-schlüssel-2>
ALARM_MESSENGER_JWT_SECRET=<generierter-schlüssel-3>

# Server-URL für Messenger (PFLICHT)
# Ersetzen Sie mit Ihrer Server-IP oder Domain
ALARM_MESSENGER_SERVER_URL=http://192.168.1.100:3000

# Feuerwehr-Name (Optional)
FIRE_DEPARTMENT_NAME=Feuerwehr Ihre Stadt
```

**API-Schlüssel generieren:**

```bash
# Drei verschiedene Schlüssel generieren
openssl rand -hex 32  # Für ALARM_MONITOR_API_KEY
openssl rand -hex 32  # Für ALARM_MESSENGER_API_SECRET_KEY
openssl rand -hex 32  # Für ALARM_MESSENGER_JWT_SECRET
```

### Schritt 4: System starten

```bash
docker-compose up -d
```

### Schritt 5: Status prüfen

```bash
# Status der Container anzeigen
docker-compose ps

# Logs überwachen
docker-compose logs -f
```

Warten Sie, bis alle Container den Status `(healthy)` zeigen.

### Schritt 6: Admin-Benutzer erstellen

```bash
# Ersten Admin-Benutzer für Messenger-Interface erstellen
curl -X POST http://localhost:3000/api/admin/init \
  -H "Content-Type: application/json" \
  -d '{"username":"admin","password":"IhrAdminPasswort123!"}'
```

**Wichtig:** Dieser Befehl funktioniert nur beim ersten Mal!

### Schritt 7: Zugriff testen

**Dashboard öffnen:**
```
http://ihre-server-ip:8000
```

**Messenger Admin-Interface öffnen:**
```
http://ihre-server-ip:3000/admin/login.html
```

Login mit den in Schritt 6 erstellten Zugangsdaten.

## Mobile-App einrichten

### Schritt 1: QR-Code generieren

1. Im Browser zu `http://ihre-server-ip:3000/admin/` gehen
2. Anmelden mit Admin-Zugangsdaten
3. Button "QR-Code generieren" klicken
4. QR-Code wird angezeigt

### Schritt 2: Mobile-App installieren

Die Mobile-App muss separat gebaut werden. Siehe:
- [alarm-messenger Mobile App Dokumentation](https://github.com/TimUx/alarm-messenger/blob/main/docs/MOBILE.md)

### Schritt 3: Gerät registrieren

1. Mobile-App öffnen
2. QR-Code scannen (vom Admin-Interface)
3. Gerät wird automatisch registriert
4. Optional: Einsatzkraft-Informationen im Admin-Interface hinzufügen

## Test-Alarm senden

### Option 1: Manuell über API

```bash
# Test-Alarm an Monitor senden
curl -X POST http://localhost:8000/api/alarm \
  -H "Content-Type: application/json" \
  -H "X-API-Key: IHR_MONITOR_API_KEY" \
  -d '{
    "incident_number": "TEST-001",
    "timestamp": "'$(date -Iseconds)'",
    "keyword": "BRAND 3",
    "sub_keyword": "Personen in Gefahr",
    "diagnosis": "Wohnungsbrand - TESTMELDUNG",
    "remarks": "Dies ist ein Test",
    "location": {
      "street": "Teststraße",
      "house_number": "123",
      "city": "Teststadt",
      "latitude": 51.2345,
      "longitude": 9.8765
    },
    "aao": "LF Test 1;DLK Test"
  }'

# Test-Alarm an Messenger senden
curl -X POST http://localhost:3000/api/emergencies \
  -H "Content-Type: application/json" \
  -H "X-API-Key: IHR_MESSENGER_API_KEY" \
  -d '{
    "emergencyNumber": "TEST-001",
    "emergencyDate": "'$(date -Iseconds)'",
    "emergencyKeyword": "BRAND 3",
    "emergencyDescription": "Wohnungsbrand - TESTMELDUNG",
    "emergencyLocation": "Teststraße 123, Teststadt"
  }'
```

### Option 2: Test-E-Mail senden

Senden Sie eine Test-E-Mail im XML-Format an Ihr IMAP-Postfach:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<INCIDENT>
  <STICHWORT>TEST</STICHWORT>
  <ESTICHWORT_1>TESTMELDUNG</ESTICHWORT_1>
  <ESTICHWORT_2>Bitte ignorieren</ESTICHWORT_2>
  <ENR>TEST-001</ENR>
  <EBEGINN>08.12.2024 14:30:00</EBEGINN>
  <DIAGNOSE>Test-Alarm zur System-Überprüfung</DIAGNOSE>
  <EO_BEMERKUNG>Dies ist nur ein Test</EO_BEMERKUNG>
  <ORT>Teststadt</ORT>
  <STRASSE>Teststraße</STRASSE>
  <HAUSNUMMER>123</HAUSNUMMER>
  <KOORDINATE_LAT>51.2345</KOORDINATE_LAT>
  <KOORDINATE_LON>9.8765</KOORDINATE_LON>
  <AAO>LF Test 1;DLK Test</AAO>
</INCIDENT>
```

## Produktion: SSL/TLS aktivieren

Für Produktivbetrieb mit automatischem HTTPS:

### Schritt 1: Domain-Namen konfigurieren

DNS-Einträge erstellen:
```
monitor.ihre-domain.de  -> A  192.168.1.100
messenger.ihre-domain.de -> A  192.168.1.100
```

### Schritt 2: .env anpassen

```bash
nano .env
```

Folgende Zeilen anpassen:
```bash
ALARM_MONITOR_DOMAIN=monitor.ihre-domain.de
ALARM_MESSENGER_DOMAIN=messenger.ihre-domain.de
ALARM_MESSENGER_SERVER_URL=https://messenger.ihre-domain.de
```

### Schritt 3: Mit Caddy starten

```bash
# System stoppen
docker-compose down

# Mit Caddy-Profil starten
docker-compose --profile with-caddy up -d
```

### Schritt 4: Zugriff testen

```
https://monitor.ihre-domain.de
https://messenger.ihre-domain.de/admin/
```

Caddy holt automatisch Let's Encrypt Zertifikate.

## Troubleshooting

### Problem: Container startet nicht

```bash
# Logs überprüfen
docker-compose logs alarm-mail
docker-compose logs alarm-monitor
docker-compose logs alarm-messenger

# Container neu starten
docker-compose restart
```

### Problem: IMAP-Verbindung fehlgeschlagen

```bash
# Verbindung testen
docker-compose exec alarm-mail ping imap.ihr-provider.de

# IMAP-Zugangsdaten prüfen
cat .env | grep IMAP
```

### Problem: API-Authentifizierung fehlgeschlagen

```bash
# API-Schlüssel vergleichen
grep ALARM_MONITOR_API_KEY .env
grep ALARM_MESSENGER_API_SECRET_KEY .env

# Müssen identisch sein zwischen Services!
```

### Problem: Mobile-App kann sich nicht verbinden

1. **Server-URL prüfen:**
   ```bash
   grep ALARM_MESSENGER_SERVER_URL .env
   ```
   Muss von außen erreichbar sein!

2. **Firewall-Regeln prüfen:**
   ```bash
   sudo ufw status
   # Port 3000 muss offen sein
   ```

3. **Neue QR-Codes generieren** nach Änderung der SERVER_URL

### Problem: Dashboard zeigt keine Alarme

1. **API-Endpunkt testen:**
   ```bash
   curl http://localhost:8000/api/alarm
   ```

2. **Logs überprüfen:**
   ```bash
   docker-compose logs alarm-mail | grep -i error
   docker-compose logs alarm-monitor | grep -i error
   ```

## Wartung

### System aktualisieren

```bash
cd /opt/alarm-system

# Neue Images herunterladen
docker-compose pull

# Services neu starten
docker-compose up -d

# Alte Images aufräumen
docker image prune -a -f
```

### Backup erstellen

```bash
# Backup-Verzeichnis erstellen
mkdir -p backup

# Daten sichern
docker run --rm \
  -v alarm-system_alarm-monitor-data:/data \
  -v $(pwd)/backup:/backup \
  alpine tar czf /backup/monitor-$(date +%Y%m%d).tar.gz /data

docker run --rm \
  -v alarm-system_alarm-messenger-data:/data \
  -v $(pwd)/backup:/backup \
  alpine tar czf /backup/messenger-$(date +%Y%m%d).tar.gz /data

# .env Datei sichern
cp .env backup/.env.backup
```

### Logs rotieren

Docker rotiert Logs automatisch, aber für manuelle Bereinigung:

```bash
docker-compose logs --no-log-prefix > logs-$(date +%Y%m%d).txt
```

## Nächste Schritte

1. **Konfiguration anpassen**
   - Siehe [.env.example](.env.example) für alle Optionen
   - Gruppenfilter konfigurieren (optional)
   - Display-Dauer anpassen (optional)

2. **Mobile-Apps deployen**
   - [Mobile-App-Dokumentation](https://github.com/TimUx/alarm-messenger/blob/main/docs/MOBILE.md)
   - QR-Codes für alle Geräte generieren
   - Einsatzkraft-Informationen pflegen

3. **Monitoring einrichten**
   - Health-Checks überwachen
   - Backup-Automatisierung
   - Logging-Aggregation

4. **Dokumentation lesen**
   - [README.md](README.md) - Vollständige Dokumentation
   - [ARCHITECTURE.md](ARCHITECTURE.md) - Technische Details
   - Komponentenspezifische Docs in jeweiligen Repositories

## Support

Bei Problemen:

1. **Logs überprüfen:** `docker-compose logs -f`
2. **Health-Status prüfen:** `docker-compose ps`
3. **Issue erstellen:** https://github.com/TimUx/alarm-system/issues
4. **Dokumentation:** Siehe Links oben

## Cheat Sheet

```bash
# Starten
docker-compose up -d

# Stoppen
docker-compose down

# Status
docker-compose ps

# Logs
docker-compose logs -f

# Neu starten
docker-compose restart

# Mit Caddy starten
docker-compose --profile with-caddy up -d

# Aktualisieren
docker-compose pull && docker-compose up -d

# Backup
docker run --rm -v alarm-system_alarm-monitor-data:/data \
  -v $(pwd)/backup:/backup alpine tar czf /backup/backup.tar.gz /data
```
