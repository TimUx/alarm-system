# GitHub Actions Workflows für Docker Image Builds

Dieser Ordner enthält GitHub Actions Workflow-Vorlagen für das automatische Bauen und Pushen von Docker Images zu GitHub Container Registry (GHCR).

## Workflow-Dateien

- **build-alarm-mail.yml** - Workflow für alarm-mail Repository
- **build-alarm-monitor.yml** - Workflow für alarm-monitor Repository  
- **build-alarm-messenger.yml** - Workflow für alarm-messenger Repository (baut aus `server/` Kontext)

**Hinweis:** Der alarm-messenger Workflow ist für Repositories konfiguriert, bei denen das Dockerfile im `server/` Unterordner liegt, da dort alle backend-relevanten Daten sind.

## Verwendung

Diese Workflows sind **Vorlagen**, die in die jeweiligen Komponenten-Repositories kopiert werden müssen:

1. Kopieren Sie die entsprechende Workflow-Datei in das Ziel-Repository unter `.github/workflows/`
2. Committen und pushen Sie die Workflow-Datei
3. Der Workflow wird automatisch bei jedem Push auf main/master ausgeführt

## Vollständige Dokumentation

Siehe [docs/DOCKER_IMAGE_WORKFLOWS.md](../docs/DOCKER_IMAGE_WORKFLOWS.md) für:
- Detaillierte Einrichtungsanleitung
- Schritt-für-Schritt Anweisungen
- Troubleshooting
- Best Practices

## Schnellstart

### Automatische Installation (Empfohlen)

Verwenden Sie das Setup-Skript für eine einfache Installation:

```bash
./setup-workflows.sh
```

Das Skript führt Sie durch den gesamten Setup-Prozess.

### Manuelle Installation

#### Für alarm-mail Repository:
```bash
cd /pfad/zum/alarm-mail
mkdir -p .github/workflows
cp /pfad/zum/alarm-system/.github/workflows/build-alarm-mail.yml .github/workflows/build-and-push.yml
git add .github/workflows/build-and-push.yml
git commit -m "Add automated Docker image build workflow"
git push
```

### Für alarm-monitor Repository:
```bash
cd /pfad/zum/alarm-monitor
mkdir -p .github/workflows
cp /pfad/zum/alarm-system/.github/workflows/build-alarm-monitor.yml .github/workflows/build-and-push.yml
git add .github/workflows/build-and-push.yml
git commit -m "Add automated Docker image build workflow"
git push
```

#### Für alarm-messenger Repository:
```bash
cd /pfad/zum/alarm-messenger
mkdir -p .github/workflows
cp /pfad/zum/alarm-system/.github/workflows/build-alarm-messenger.yml .github/workflows/build-and-push.yml
git add .github/workflows/build-and-push.yml
git commit -m "Add automated Docker image build workflow"
git push
```

**Hinweis:** Der alarm-messenger Workflow baut aus dem `server/` Kontext, da dort das Dockerfile und alle backend-relevanten Daten liegen.

## Was die Workflows tun

Die Workflows:
1. ✅ Checken den Code aus
2. ✅ Loggen sich bei GHCR ein
3. ✅ Bauen das Docker Image für Linux/amd64 und Linux/arm64
4. ✅ Taggen das Image mit verschiedenen Tags (latest, version, sha)
5. ✅ Pushen das Image zu ghcr.io/timux/*
6. ✅ Nutzen GitHub Actions Cache für schnellere Builds

## Trigger

Die Workflows werden ausgeführt bei:
- **Push** auf main/master Branch (automatisch)
- **Release** erstellen (automatisch)
- **Manuell** über GitHub Actions UI

## Ergebnisse

Nach erfolgreichem Workflow-Lauf sind die Images verfügbar unter:
- `ghcr.io/timux/alarm-mail:latest`
- `ghcr.io/timux/alarm-monitor:latest`
- `ghcr.io/timux/alarm-messenger:latest`

Diese können dann direkt in `docker-compose.yml` verwendet werden (was bereits der Fall ist).

## Support

Für Fragen und Probleme siehe:
- [Vollständige Dokumentation](../docs/DOCKER_IMAGE_WORKFLOWS.md)
- [GitHub Issues](https://github.com/TimUx/alarm-system/issues)
