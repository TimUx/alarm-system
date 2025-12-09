# Automatisierte Docker Image Builds für GHCR

Dieses Dokument beschreibt, wie die automatisierten GitHub Actions Workflows eingerichtet werden, um die Docker Images für das Alarm-System automatisch zu bauen und zu GitHub Container Registry (GHCR) hochzuladen.

## Übersicht

Das Alarm-System besteht aus drei Hauptkomponenten, die jeweils als Docker Images bereitgestellt werden:

1. **alarm-mail** - IMAP Email Parser (`ghcr.io/timux/alarm-mail:latest`)
2. **alarm-monitor** - Dashboard (`ghcr.io/timux/alarm-monitor:latest`)
3. **alarm-messenger** - Push Notification System (`ghcr.io/timux/alarm-messenger:latest`)

Die GitHub Actions Workflows in diesem Repository dienen als Vorlagen, die in jedem der drei Komponenten-Repositories eingerichtet werden müssen.

## Voraussetzungen

Für jeden der drei Komponenten-Repositories (`alarm-mail`, `alarm-monitor`, `alarm-messenger`) müssen folgende Voraussetzungen erfüllt sein:

1. **Dockerfile vorhanden**: Jedes Repository muss ein `Dockerfile` im Root-Verzeichnis enthalten
2. **GHCR Package Permissions**: Das GitHub Container Registry Package muss entsprechende Berechtigungen haben
3. **GitHub Actions aktiviert**: GitHub Actions müssen für das Repository aktiviert sein

## Einrichtung der Workflows

### Schritt 1: Workflows in die Komponenten-Repositories kopieren

Für jedes der drei Repositories müssen die entsprechenden Workflow-Dateien kopiert werden:

#### Für alarm-mail Repository:
```bash
cd /pfad/zum/alarm-mail
mkdir -p .github/workflows
cp /pfad/zum/alarm-system/.github/workflows/build-alarm-mail.yml .github/workflows/build-and-push.yml
git add .github/workflows/build-and-push.yml
git commit -m "Add automated Docker image build and push workflow"
git push
```

#### Für alarm-monitor Repository:
```bash
cd /pfad/zum/alarm-monitor
mkdir -p .github/workflows
cp /pfad/zum/alarm-system/.github/workflows/build-alarm-monitor.yml .github/workflows/build-and-push.yml
git add .github/workflows/build-and-push.yml
git commit -m "Add automated Docker image build and push workflow"
git push
```

#### Für alarm-messenger Repository:
```bash
cd /pfad/zum/alarm-messenger
mkdir -p .github/workflows
cp /pfad/zum/alarm-system/.github/workflows/build-alarm-messenger.yml .github/workflows/build-and-push.yml
git add .github/workflows/build-and-push.yml
git commit -m "Add automated Docker image build and push workflow"
git push
```

### Schritt 2: GHCR Packages konfigurieren

Nach dem ersten Workflow-Lauf müssen die Container-Packages öffentlich gemacht werden:

1. Gehe zu https://github.com/TimUx?tab=packages
2. Wähle das entsprechende Package aus (z.B. `alarm-mail`)
3. Klicke auf "Package settings"
4. Scrolle zu "Danger Zone" → "Change visibility"
5. Wähle "Public" aus
6. Bestätige die Änderung

Wiederhole dies für alle drei Packages:
- `alarm-mail`
- `alarm-monitor`
- `alarm-messenger`

### Schritt 3: Workflows testen

Die Workflows werden automatisch ausgelöst bei:
- **Push auf main/master Branch**: Baut und pushed Image mit `latest` Tag
- **Release erstellen**: Baut und pushed Image mit Version-Tags
- **Manuell**: Über "Actions" → "Workflow auswählen" → "Run workflow"

#### Manueller Test:
1. Gehe zu https://github.com/TimUx/alarm-mail/actions (bzw. alarm-monitor, alarm-messenger)
2. Wähle "Build and Push to GHCR" Workflow
3. Klicke "Run workflow"
4. Wähle Branch (main/master)
5. Klicke "Run workflow"

## Workflow-Funktionen

### Automatische Triggers

Die Workflows werden automatisch ausgeführt bei:

```yaml
on:
  push:
    branches:
      - main
      - master
    paths:
      - '**'
      - '!README.md'
      - '!docs/**'
  release:
    types: [published]
  workflow_dispatch:
```

- **push**: Bei jedem Push auf main/master (außer reine Doku-Änderungen)
- **release**: Bei jedem veröffentlichten Release
- **workflow_dispatch**: Manueller Trigger über GitHub UI

### Tag-Strategie

Die Workflows erstellen folgende Docker Image Tags:

| Trigger | Tags | Beispiel |
|---------|------|----------|
| Push auf main | `latest`, `main`, `sha-abc123` | `ghcr.io/timux/alarm-mail:latest` |
| Push auf master | `latest`, `master`, `sha-abc123` | `ghcr.io/timux/alarm-mail:latest` |
| Release v1.2.3 | `1.2.3`, `1.2`, `1`, `latest`, `sha-abc123` | `ghcr.io/timux/alarm-mail:1.2.3` |
| PR #42 | `pr-42` | `ghcr.io/timux/alarm-mail:pr-42` |

### Multi-Platform Support

Die Workflows bauen Images für:
- `linux/amd64` (x86_64)
- `linux/arm64` (ARM64/aarch64)

Dies ermöglicht den Betrieb auf verschiedenen Plattformen wie:
- Standard x86_64 Servern
- ARM-basierten Servern (z.B. AWS Graviton, Raspberry Pi)

### Build-Cache

Die Workflows nutzen GitHub Actions Cache, um Build-Zeiten zu reduzieren:
```yaml
cache-from: type=gha
cache-to: type=gha,mode=max
```

## Überprüfung der Images

### Nach dem Workflow-Lauf

1. **In GitHub Actions**: 
   - Gehe zu "Actions" Tab des Repositories
   - Prüfe den Status des Workflow-Laufs (grüner Haken = erfolgreich)

2. **In GHCR**:
   - Gehe zu https://github.com/TimUx?tab=packages
   - Prüfe, ob das Image verfügbar ist
   - Prüfe die Tags (sollte mindestens `latest` enthalten)

3. **Lokal testen**:
   ```bash
   # Image pullen
   docker pull ghcr.io/timux/alarm-mail:latest
   
   # Image inspizieren
   docker images | grep alarm-mail
   docker inspect ghcr.io/timux/alarm-mail:latest
   
   # Container starten (Test)
   docker run --rm ghcr.io/timux/alarm-mail:latest --help
   ```

### Im alarm-system Repository testen

Nach dem Deployment der Images können Sie diese im alarm-system testen:

```bash
cd /pfad/zum/alarm-system

# Neueste Images pullen
docker-compose pull

# System starten
docker-compose up -d

# Status prüfen
docker-compose ps

# Logs überprüfen
docker-compose logs -f
```

## Troubleshooting

### Problem: Workflow schlägt fehl mit "permission denied"

**Lösung**: Prüfen Sie die Workflow-Permissions:
```yaml
permissions:
  contents: read
  packages: write
```

Diese sollten bereits in den Workflows vorhanden sein. Falls nicht, fügen Sie sie hinzu.

### Problem: Image kann nicht gepulled werden (404 Not Found)

**Ursache**: Package ist noch auf "private" gesetzt

**Lösung**: 
1. Gehe zu https://github.com/TimUx?tab=packages
2. Wähle Package aus
3. Ändere Visibility auf "Public"

### Problem: Build schlägt fehl mit "Dockerfile not found"

**Ursache**: Kein Dockerfile im Repository-Root

**Lösung**: Stellen Sie sicher, dass ein `Dockerfile` im Root-Verzeichnis des jeweiligen Repositories existiert.

### Problem: Multi-Platform Build dauert sehr lange

**Erklärung**: ARM64 Builds werden über QEMU emuliert, was langsamer ist

**Lösung**: Dies ist normal. Für schnellere Builds können Sie in der Workflow-Datei nur `linux/amd64` builden:
```yaml
platforms: linux/amd64
```

### Problem: Workflow wird bei Docs-Änderungen trotzdem ausgeführt

**Lösung**: Prüfen Sie die `paths` Konfiguration im Workflow:
```yaml
paths:
  - '**'
  - '!README.md'
  - '!docs/**'
```

Passen Sie die Ausnahmen nach Bedarf an.

## Weiterführende Dokumentation

### GitHub Actions
- [GitHub Actions Dokumentation](https://docs.github.com/en/actions)
- [Docker Build Push Action](https://github.com/docker/build-push-action)
- [Docker Metadata Action](https://github.com/docker/metadata-action)

### GitHub Container Registry
- [GHCR Dokumentation](https://docs.github.com/en/packages/working-with-a-github-packages-registry/working-with-the-container-registry)
- [Publishing Docker Images](https://docs.github.com/en/actions/publishing-packages/publishing-docker-images)

### Docker
- [Dockerfile Best Practices](https://docs.docker.com/develop/dev-best-practices/)
- [Multi-Platform Images](https://docs.docker.com/build/building/multi-platform/)

## Maintenance und Updates

### Automatische Updates

Die Workflows bauen und pushen automatisch bei jedem Commit auf main/master. Keine manuelle Intervention erforderlich.

### Versioned Releases

Für Produktions-Deployments empfiehlt sich die Verwendung von Release-Tags:

```bash
# In alarm-mail Repository
git tag -a v1.0.0 -m "Release v1.0.0"
git push origin v1.0.0
```

Dies triggert den Workflow und erstellt:
- `ghcr.io/timux/alarm-mail:1.0.0`
- `ghcr.io/timux/alarm-mail:1.0`
- `ghcr.io/timux/alarm-mail:1`
- `ghcr.io/timux/alarm-mail:latest`

### Pin Version in docker-compose.yml

Für Produktions-Stabilität können Sie spezifische Versions-Tags verwenden:

```yaml
services:
  alarm-mail:
    image: ghcr.io/timux/alarm-mail:1.0.0  # statt :latest
```

## Sicherheit

### Secrets

Die Workflows verwenden `GITHUB_TOKEN`, das automatisch von GitHub bereitgestellt wird. Keine zusätzlichen Secrets erforderlich.

### Image Signing (Optional)

Für zusätzliche Sicherheit können Image-Signing mit Cosign hinzugefügt werden. Siehe [Cosign Dokumentation](https://github.com/sigstore/cosign).

## Support

Bei Problemen mit den Workflows:
1. Prüfen Sie die Workflow-Logs in GitHub Actions
2. Erstellen Sie ein Issue im entsprechenden Repository
3. Siehe [CONTRIBUTING.md](../CONTRIBUTING.md) für weitere Hilfe

## Zusammenfassung

Nach der Einrichtung funktioniert der automatisierte Build-Prozess wie folgt:

```
┌─────────────────────┐
│ Developer           │
│ git push            │
└──────────┬──────────┘
           │
           v
┌─────────────────────┐
│ GitHub Actions      │
│ Workflow ausgeführt │
└──────────┬──────────┘
           │
           v
┌─────────────────────┐
│ Docker Image        │
│ gebaut              │
└──────────┬──────────┘
           │
           v
┌─────────────────────┐
│ GHCR                │
│ Image gepusht       │
└──────────┬──────────┘
           │
           v
┌─────────────────────┐
│ alarm-system        │
│ kann Image pullen   │
└─────────────────────┘
```

Jede Änderung an den Komponenten-Repositories wird automatisch als Docker Image gebaut und zu GHCR gepusht, sodass das alarm-system immer die neuesten Versionen verwenden kann.
