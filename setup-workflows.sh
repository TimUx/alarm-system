#!/bin/bash

# Setup Script für automatisierte Docker Image Workflows
# Dieses Skript hilft bei der Einrichtung der GitHub Actions Workflows
# in den alarm-mail, alarm-monitor und alarm-messenger Repositories

set -e

echo "=================================================="
echo "Alarm System - Docker Image Workflow Setup"
echo "=================================================="
echo ""

# Farben für bessere Lesbarkeit
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Funktion zum Kopieren des Workflows
setup_workflow() {
    local repo_name=$1
    local repo_path=$2
    local workflow_file=$3
    local original_dir=$(pwd)
    
    echo -e "${YELLOW}Setting up workflow for ${repo_name}...${NC}"
    
    # Prüfen ob Repository-Pfad existiert
    if [ ! -d "$repo_path" ]; then
        echo -e "${RED}✗ Repository nicht gefunden: $repo_path${NC}"
        echo "  Bitte klonen Sie zuerst das Repository:"
        echo "  git clone https://github.com/TimUx/${repo_name}.git $repo_path"
        echo ""
        return 1
    fi
    
    # Wechseln ins Repository
    cd "$repo_path" || {
        echo -e "${RED}✗ Konnte nicht ins Verzeichnis wechseln: $repo_path${NC}"
        cd "$original_dir"
        return 1
    }
    
    # Prüfen ob es ein Git-Repository ist
    if [ ! -d ".git" ]; then
        echo -e "${RED}✗ Kein Git-Repository: $repo_path${NC}"
        cd "$original_dir"
        return 1
    fi
    
    # Prüfen ob Dockerfile vorhanden ist
    if [ ! -f "Dockerfile" ]; then
        echo -e "${RED}✗ Kein Dockerfile gefunden in $repo_path${NC}"
        echo "  Der Workflow benötigt ein Dockerfile im Root-Verzeichnis."
        cd "$original_dir"
        return 1
    fi
    
    # Workflows-Verzeichnis erstellen
    mkdir -p .github/workflows
    
    # Workflow-Datei kopieren
    cp "$workflow_file" .github/workflows/build-and-push.yml
    
    echo -e "${GREEN}✓ Workflow-Datei kopiert${NC}"
    
    # Git Status anzeigen
    echo ""
    echo "Git Status:"
    git status --short
    echo ""
    
    # Benutzer fragen ob committen
    read -p "Möchten Sie die Änderungen committen und pushen? (y/n) " -n 1 -r
    echo ""
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        git add .github/workflows/build-and-push.yml
        git commit -m "Add automated Docker image build and push workflow"
        git push
        echo -e "${GREEN}✓ Workflow committed und gepusht${NC}"
        echo ""
        echo "Der Workflow ist jetzt aktiv!"
        echo "Gehen Sie zu https://github.com/TimUx/${repo_name}/actions um den Status zu sehen."
    else
        echo "Commit übersprungen. Sie können später manuell committen:"
        echo "  cd $repo_path"
        echo "  git add .github/workflows/build-and-push.yml"
        echo "  git commit -m 'Add automated Docker image build workflow'"
        echo "  git push"
    fi
    
    # Zurück zum ursprünglichen Verzeichnis
    cd "$original_dir"
    
    echo ""
    return 0
}

# Hauptprogramm
echo "Dieses Skript hilft Ihnen, die GitHub Actions Workflows für automatische"
echo "Docker Image Builds in die Komponenten-Repositories einzurichten."
echo ""
echo "Voraussetzungen:"
echo "  - Die Repositories müssen lokal geklont sein"
echo "  - Jedes Repository muss ein Dockerfile im Root haben"
echo "  - Sie müssen Push-Rechte auf die Repositories haben"
echo ""

# Aktuelles Verzeichnis speichern
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
WORKFLOWS_DIR="$SCRIPT_DIR/.github/workflows"

# Prüfen ob Workflow-Dateien existieren
if [ ! -f "$WORKFLOWS_DIR/build-alarm-mail.yml" ]; then
    echo -e "${RED}✗ Workflow-Dateien nicht gefunden in $WORKFLOWS_DIR${NC}"
    echo "  Bitte führen Sie dieses Skript aus dem alarm-system Repository Root aus."
    exit 1
fi

echo "Workflow-Vorlagen gefunden in: $WORKFLOWS_DIR"
echo ""

# Repository-Pfade abfragen
echo "Bitte geben Sie die Pfade zu den Repositories ein:"
echo "(oder drücken Sie Enter zum Überspringen)"
echo ""

# Repository-Konfiguration
declare -A REPOS
REPOS[alarm-mail]=""
REPOS[alarm-monitor]=""
REPOS[alarm-messenger]=""

read -p "Pfad zu alarm-mail Repository (z.B. ../alarm-mail): " REPOS[alarm-mail]
read -p "Pfad zu alarm-monitor Repository (z.B. ../alarm-monitor): " REPOS[alarm-monitor]
read -p "Pfad zu alarm-messenger Repository (z.B. ../alarm-messenger): " REPOS[alarm-messenger]

echo ""
echo "=================================================="
echo "Setup wird durchgeführt..."
echo "=================================================="
echo ""

SUCCESS_COUNT=0
FAIL_COUNT=0

# Repositories verarbeiten
for repo_name in "${!REPOS[@]}"; do
    repo_path="${REPOS[$repo_name]}"
    if [ -n "$repo_path" ]; then
        workflow_file="$WORKFLOWS_DIR/build-${repo_name}.yml"
        if setup_workflow "$repo_name" "$repo_path" "$workflow_file"; then
            ((SUCCESS_COUNT++))
        else
            ((FAIL_COUNT++))
        fi
    fi
done

# Zusammenfassung
echo "=================================================="
echo "Setup abgeschlossen"
echo "=================================================="
echo -e "${GREEN}Erfolgreich: $SUCCESS_COUNT${NC}"
echo -e "${RED}Fehlgeschlagen: $FAIL_COUNT${NC}"
echo ""

if [ $SUCCESS_COUNT -gt 0 ]; then
    echo "Nächste Schritte:"
    echo ""
    echo "1. Warten Sie, bis die Workflows ausgeführt werden (beim nächsten Push)"
    echo "   oder führen Sie sie manuell aus über GitHub Actions UI"
    echo ""
    echo "2. Nach dem ersten Workflow-Lauf müssen die Packages öffentlich gemacht werden:"
    echo "   - Gehen Sie zu https://github.com/TimUx?tab=packages"
    echo "   - Wählen Sie das Package aus"
    echo "   - Klicken Sie auf 'Package settings'"
    echo "   - Ändern Sie 'Visibility' auf 'Public'"
    echo ""
    echo "3. Testen Sie die Images:"
    echo "   docker pull ghcr.io/timux/alarm-mail:latest"
    echo "   docker pull ghcr.io/timux/alarm-monitor:latest"
    echo "   docker pull ghcr.io/timux/alarm-messenger:latest"
    echo ""
    echo "Weitere Informationen:"
    echo "  - docs/DOCKER_IMAGE_WORKFLOWS.md (vollständige Dokumentation)"
    echo "  - .github/workflows/README.md (Workflow-Übersicht)"
fi

echo ""
echo "Vielen Dank für die Verwendung des Alarm-Systems!"
