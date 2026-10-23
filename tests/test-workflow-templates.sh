#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TEMP_DIR"' EXIT

for component in alarm-mail alarm-monitor alarm-messenger; do
    test -f "$ROOT/.github/workflow-templates/build-$component.yml"
    test ! -f "$ROOT/.github/workflows/build-$component.yml"
    git init --quiet "$TEMP_DIR/$component"
    if [ "$component" = alarm-messenger ]; then
        mkdir -p "$TEMP_DIR/$component/server"
        touch "$TEMP_DIR/$component/server/Dockerfile"
    else
        touch "$TEMP_DIR/$component/Dockerfile"
    fi
done

# Decline commits: the test only exercises copying into isolated fixtures.
printf '%s\n' "$TEMP_DIR/alarm-mail" "$TEMP_DIR/alarm-monitor" \
    "$TEMP_DIR/alarm-messenger" n n n |
    bash "$ROOT/setup-workflows.sh" > "$TEMP_DIR/setup.log"

for component in alarm-mail alarm-monitor alarm-messenger; do
    cmp "$ROOT/.github/workflow-templates/build-$component.yml" \
        "$TEMP_DIR/$component/.github/workflows/build-and-push.yml"
done

grep -q 'Erfolgreich: 3' "$TEMP_DIR/setup.log"
grep -q 'Fehlgeschlagen: 0' "$TEMP_DIR/setup.log"
echo "All three workflow templates installed successfully."
