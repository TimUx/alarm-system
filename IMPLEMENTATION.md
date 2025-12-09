# Implementierung: Automatisierte Docker Image Workflows für GHCR

## Problem
Das alarm-system Repository referenziert Docker Images von GHCR (GitHub Container Registry):
- `ghcr.io/timux/alarm-mail:latest`
- `ghcr.io/timux/alarm-monitor:latest`
- `ghcr.io/timux/alarm-messenger:latest`

Diese Images müssen automatisch aus den entsprechenden Quell-Repositories gebaut und zu GHCR gepusht werden, damit das alarm-system und die Anleitungen funktionieren.

## Lösung
Es wurden GitHub Actions Workflows erstellt, die automatisch Docker Images bauen und zu GHCR pushen.

## Implementierte Komponenten

### 1. GitHub Actions Workflows (`.github/workflows/`)
Drei Workflow-Vorlagen für die Komponenten-Repositories:

#### `build-alarm-mail.yml`
- Baut Docker Image für alarm-mail
- Pusht zu `ghcr.io/timux/alarm-mail`
- Unterstützt Linux/amd64 und Linux/arm64

#### `build-alarm-monitor.yml`
- Baut Docker Image für alarm-monitor
- Pusht zu `ghcr.io/timux/alarm-monitor`
- Unterstützt Linux/amd64 und Linux/arm64

#### `build-alarm-messenger.yml`
- Baut Docker Image für alarm-messenger
- Pusht zu `ghcr.io/timux/alarm-messenger`
- Unterstützt Linux/amd64 und Linux/arm64

**Features aller Workflows:**
- ✅ Automatischer Trigger bei Push auf main/master
- ✅ Automatischer Trigger bei Release-Erstellung
- ✅ Manueller Trigger möglich (workflow_dispatch)
- ✅ Multi-Platform Build (amd64, arm64)
- ✅ GitHub Actions Cache für schnellere Builds
- ✅ Intelligente Tag-Strategie (latest, version, sha)
- ✅ Keine Secrets erforderlich (verwendet GITHUB_TOKEN)

### 2. Setup-Script (`setup-workflows.sh`)
Ein interaktives Bash-Script zum einfachen Deployment der Workflows:

**Features:**
- ✅ Führt durch den Setup-Prozess
- ✅ Validiert Voraussetzungen (Git-Repo, Dockerfile)
- ✅ Kopiert Workflow-Dateien automatisch
- ✅ Optional: Committet und pusht Änderungen
- ✅ Robuste Fehlerbehandlung
- ✅ Farbcodierte Ausgabe für bessere Lesbarkeit
- ✅ Unterstützt mehrere Repositories in einem Durchlauf

**Verwendung:**
```bash
./setup-workflows.sh
```

### 3. Dokumentation

#### `docs/DOCKER_IMAGE_WORKFLOWS.md` (9.9 KB)
Umfassende Dokumentation mit:
- Übersicht und Voraussetzungen
- Schritt-für-Schritt Einrichtungsanleitung
- Automatisches vs. manuelles Setup
- Workflow-Funktionen und Konfiguration
- Tag-Strategie und Multi-Platform Support
- Überprüfung der Images
- Troubleshooting-Guide
- Sicherheits-Best-Practices
- Maintenance und Updates

#### `.github/workflows/README.md` (2.9 KB)
Kurzreferenz für die Workflows:
- Übersicht der Workflow-Dateien
- Schnellstart-Anleitung
- Was die Workflows tun
- Trigger und Ergebnisse

#### Aktualisiertes `README.md`
- Link zur neuen Dokumentation hinzugefügt

## Technische Details

### Workflow-Struktur
```yaml
on:
  push:
    branches: [main, master]
    paths: ['**', '!README.md', '!docs/**']
  release:
    types: [published]
  workflow_dispatch:

jobs:
  build-and-push:
    - Checkout Code
    - Login zu GHCR
    - Extract Metadata (Tags)
    - Setup Docker Buildx
    - Build & Push Image (multi-platform)
    - Output Digest
```

### Tag-Strategie
| Event | Erzeugte Tags | Beispiel |
|-------|---------------|----------|
| Push auf main | latest, main, sha-abc123 | ghcr.io/timux/alarm-mail:latest |
| Release v1.2.3 | 1.2.3, 1.2, 1, latest, sha-abc123 | ghcr.io/timux/alarm-mail:1.2.3 |
| PR #42 | pr-42 | ghcr.io/timux/alarm-mail:pr-42 |

### Multi-Platform Support
- **linux/amd64**: Standard x86_64 Server
- **linux/arm64**: ARM-basierte Server (AWS Graviton, Raspberry Pi)

### Sicherheit
- ✅ Verwendet automatisches `GITHUB_TOKEN`
- ✅ Keine zusätzlichen Secrets erforderlich
- ✅ Keine Schwachstellen von CodeQL gefunden
- ✅ Permissions auf Minimum beschränkt (read:contents, write:packages)

## Deployment-Anleitung

### Schritt 1: Workflows deployen
Die Workflow-Dateien müssen in die jeweiligen Komponenten-Repositories kopiert werden:

**Option A: Automatisch (Empfohlen)**
```bash
./setup-workflows.sh
```

**Option B: Manuell**
```bash
# Für alarm-mail
cd ../alarm-mail
mkdir -p .github/workflows
cp ../alarm-system/.github/workflows/build-alarm-mail.yml .github/workflows/build-and-push.yml
git add .github/workflows/build-and-push.yml
git commit -m "Add automated Docker image build workflow"
git push

# Wiederholen für alarm-monitor und alarm-messenger
```

### Schritt 2: GHCR Packages öffentlich machen
Nach dem ersten Workflow-Lauf:

1. Gehe zu https://github.com/TimUx?tab=packages
2. Wähle Package (alarm-mail, alarm-monitor, oder alarm-messenger)
3. Settings → Change visibility → Public
4. Wiederhole für alle drei Packages

### Schritt 3: Testen
```bash
# Images pullen
docker pull ghcr.io/timux/alarm-mail:latest
docker pull ghcr.io/timux/alarm-monitor:latest
docker pull ghcr.io/timux/alarm-messenger:latest

# Im alarm-system testen
cd alarm-system
docker-compose pull
docker-compose up -d
```

## Ergebnis
Nach der Implementierung:
- ✅ Jeder Push auf main/master baut automatisch neue Images
- ✅ Images werden zu GHCR gepusht
- ✅ alarm-system kann Images direkt von GHCR pullen
- ✅ Anleitungen funktionieren out-of-the-box
- ✅ Multi-Platform Support (amd64, arm64)
- ✅ Keine manuelle Intervention erforderlich

## Nächste Schritte (für Benutzer)

1. **Workflows deployen**: 
   - `./setup-workflows.sh` ausführen
   - Oder manuell in die Komponenten-Repos kopieren

2. **Packages konfigurieren**:
   - Nach erstem Workflow-Lauf Packages öffentlich machen

3. **Testen**:
   - Images pullen und alarm-system starten

4. **Optional - Versioned Releases**:
   - Git Tags für stabile Versionen erstellen
   - Workflows bauen automatisch versionierte Images

## Dateien

```
alarm-system/
├── .github/
│   └── workflows/
│       ├── README.md                    # Workflow-Übersicht
│       ├── build-alarm-mail.yml         # Workflow für alarm-mail
│       ├── build-alarm-monitor.yml      # Workflow für alarm-monitor
│       └── build-alarm-messenger.yml    # Workflow für alarm-messenger
├── docs/
│   └── DOCKER_IMAGE_WORKFLOWS.md        # Vollständige Dokumentation
├── setup-workflows.sh                   # Automatisches Setup-Script
└── README.md                            # Aktualisiert mit Link zur Doku
```

## Validierung

### Syntax-Checks
- ✅ Alle YAML-Workflows validiert
- ✅ Bash-Script Syntax geprüft

### Code Review
- ✅ Workflow Step IDs korrigiert
- ✅ Setup-Script verbessert (Working Directory, Code-Duplikation)

### Security Scan
- ✅ CodeQL: Keine Schwachstellen gefunden

## Support
Für Fragen oder Probleme:
- Siehe `docs/DOCKER_IMAGE_WORKFLOWS.md` (vollständige Dokumentation)
- Siehe `.github/workflows/README.md` (Schnellreferenz)
- GitHub Issues erstellen
