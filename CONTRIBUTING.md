# Contributing to Alarm System

Vielen Dank für Ihr Interesse, zum Alarm System beizutragen!

## Komponenten-spezifische Beiträge

Da das Alarm System aus drei separaten Komponenten besteht, richten Sie Ihre Beiträge bitte an das entsprechende Repository:

- **alarm-mail:** https://github.com/TimUx/alarm-mail
- **alarm-monitor:** https://github.com/TimUx/alarm-monitor
- **alarm-messenger:** https://github.com/TimUx/alarm-messenger

## Beiträge zu diesem Repository

Dieses Repository (`alarm-system`) ist für die zentrale Integration und Orchestrierung verantwortlich. Beiträge hier sollten sich auf folgende Bereiche konzentrieren:

### Willkommene Beiträge

1. **Dokumentation**
   - Verbesserungen an README.md
   - Erweiterungen der ARCHITECTURE.md
   - Neue Anleitungen oder Tutorials
   - Übersetzungen

2. **Docker Compose Konfiguration**
   - Verbesserungen der docker-compose.yml
   - Neue Service-Konfigurationen
   - Optimierungen der Netzwerk-Konfiguration

3. **Deployment-Tools**
   - Verbesserungen am validate-config.sh
   - Neue Makefile-Targets
   - Deployment-Skripte für verschiedene Plattformen

4. **Beispiel-Konfigurationen**
   - Beispiele für verschiedene Deployment-Szenarien
   - Best-Practice-Konfigurationen
   - Alternative Reverse-Proxy-Setups (neben Caddy)

### Bevor Sie beginnen

1. **Prüfen Sie bestehende Issues**
   - Schauen Sie, ob Ihre Idee bereits diskutiert wird
   - Kommentieren Sie in bestehenden Issues

2. **Erstellen Sie ein Issue**
   - Beschreiben Sie Ihre geplanten Änderungen
   - Warten Sie auf Feedback
   - Diskutieren Sie den Ansatz

3. **Testen Sie Ihre Änderungen**
   - Stellen Sie sicher, dass `docker compose config` ohne Fehler läuft
   - Testen Sie `./validate-config.sh`
   - Dokumentieren Sie Ihre Tests

### Pull Request Process

1. **Fork und Branch**
   ```bash
   git clone https://github.com/IHR-USERNAME/alarm-system.git
   cd alarm-system
   git checkout -b feature/ihre-feature-beschreibung
   ```

2. **Änderungen vornehmen**
   - Folgen Sie dem bestehenden Code-Stil
   - Aktualisieren Sie Dokumentation
   - Fügen Sie Kommentare hinzu wo nötig

3. **Testen**
   ```bash
   # Syntax-Check
   docker compose config --quiet
   
   # Validation
   ./validate-config.sh
   
   # Functional test (wenn möglich)
   docker compose up -d
   docker compose ps
   docker compose logs
   docker compose down
   ```

4. **Commit**
   ```bash
   git add .
   git commit -m "feat: kurze beschreibung ihrer änderung"
   ```

   Commit-Message-Format:
   - `feat:` - Neue Features
   - `fix:` - Bugfixes
   - `docs:` - Dokumentations-Änderungen
   - `refactor:` - Code-Refactoring
   - `test:` - Test-Änderungen
   - `chore:` - Build/Tools-Änderungen

5. **Push und PR**
   ```bash
   git push origin feature/ihre-feature-beschreibung
   ```
   
   Erstellen Sie dann einen Pull Request auf GitHub mit:
   - Klare Beschreibung der Änderungen
   - Referenz zu relevanten Issues
   - Screenshots (wenn UI-bezogen)
   - Test-Ergebnisse

### Code-Review

- Seien Sie offen für Feedback
- Änderungen können angefragt werden
- Diskutieren Sie konstruktiv
- Geduld - Reviews brauchen Zeit

## Dokumentations-Standards

### README.md

- Halten Sie die Struktur bei
- Verwenden Sie klare Überschriften
- Fügen Sie Code-Beispiele hinzu
- Aktualisieren Sie das Inhaltsverzeichnis

### ARCHITECTURE.md

- Technische Details gehören hierher
- Diagramme im ASCII-Art-Format
- API-Dokumentation mit Beispielen
- Sequenzdiagramme für Flows

### QUICKSTART.md

- Schritt-für-Schritt-Anleitungen
- Getestet und verifiziert
- Kopier-bare Befehle
- Troubleshooting-Tipps

## Docker Compose Standards

### Services

```yaml
service-name:
  image: registry/image:tag  # Bevorzugt gegenüber build
  container_name: beschreibender-name
  restart: unless-stopped  # Standard für Produktion
  networks:
    - alarm-network
  environment:
    - VAR_NAME=${ENV_VAR:-default}  # Immer mit Default
  volumes:
    - volume-name:/path/in/container
  healthcheck:
    test: ["CMD", "curl", "-f", "http://localhost:port/health"]
    interval: 30s
    timeout: 5s
    start_period: 30s
    retries: 3
```

### Netzwerke

- Verwenden Sie `alarm-network` für alle internen Services
- Dokumentieren Sie Kommunikationswege
- Mapping nur für externe Ports

### Volumes

- Named Volumes für Persistenz
- Dokumentieren Sie was gespeichert wird
- Bind-Mounts nur für Konfiguration

## Umgebungsvariablen

### Naming Convention

```
SERVICE_CATEGORY_SPECIFIC_NAME
```

Beispiele:
- `ALARM_MAIL_IMAP_HOST`
- `ALARM_MONITOR_API_KEY`
- `ALARM_MESSENGER_SERVER_URL`

### .env.example

- Jede Variable mit Kommentar
- Gruppierung nach Service
- Pflichtfelder kennzeichnen
- Beispielwerte angeben
- Sicherheitshinweise hinzufügen

## Testing

### Manuelle Tests

1. **Syntax-Validierung**
   ```bash
   docker compose config --quiet
   ```

2. **Start-Test**
   ```bash
   docker compose up -d
   docker compose ps  # Alle healthy?
   ```

3. **Kommunikations-Test**
   ```bash
   docker compose exec alarm-mail curl http://alarm-monitor:8000/health
   docker compose exec alarm-mail curl http://alarm-messenger:3000/health
   ```

4. **Cleanup**
   ```bash
   docker compose down -v
   ```

### Automatische Tests

Wenn Sie automatische Tests hinzufügen möchten:
- Verwenden Sie Shell-Skripte
- Dokumentieren Sie Testfälle
- Machen Sie Tests wiederholbar

## Fragen?

- **Issues:** https://github.com/TimUx/alarm-system/issues
- **Discussions:** https://github.com/TimUx/alarm-system/discussions

## Code of Conduct

- Seien Sie respektvoll
- Konstruktives Feedback
- Inklusiv und weltoffen
- Professionell bleiben

## Lizenz

Indem Sie beitragen, stimmen Sie zu, dass Ihre Beiträge unter der MIT-Lizenz lizenziert werden.
