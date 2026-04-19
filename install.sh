#!/usr/bin/env bash

# Sicherstellen, dass das Skript immer mit Bash läuft (auch bei Aufruf via `sh install.sh`)
if [ -z "${BASH_VERSION:-}" ]; then
    exec /usr/bin/env bash "$0" "$@"
fi

# =============================================================================
# install.sh – Alarm-System: Vollautomatisches 1-Click Installationsskript
#
# Unterstützte Architekturen : x86_64, aarch64 (arm64), armv7l, armv6l
# Unterstützte Distributionen: Debian, Ubuntu, Raspberry Pi OS,
#                              Fedora, RHEL, CentOS, Rocky, AlmaLinux,
#                              Arch Linux, Manjaro,
#                              openSUSE Leap/Tumbleweed,
#                              Alpine Linux
#
# Verwendung:
#   curl -fsSL https://raw.githubusercontent.com/TimUx/alarm-system/main/install.sh | bash
#   – oder –
#   chmod +x install.sh && ./install.sh
#
# Das Skript darf NICHT als root ausgeführt werden (sudo wird intern verwendet).
# =============================================================================

set -euo pipefail

# ---------------------------------------------------------------------------
# Farb-Hilfsfunktionen
# ---------------------------------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

step()    { echo -e "\n${BLUE}${BOLD}▶  $*${NC}"; }
ok()      { echo -e "  ${GREEN}✔  $*${NC}"; }
warn()    { echo -e "  ${YELLOW}⚠  $*${NC}"; }
info()    { echo -e "  ${CYAN}ℹ  $*${NC}"; }
die()     { echo -e "\n${RED}${BOLD}✘  FEHLER: $*${NC}\n" >&2; exit 1; }
sep()     { echo -e "${BOLD}─────────────────────────────────────────────────────────────${NC}"; }

# ---------------------------------------------------------------------------
# Skript darf nicht als root laufen
# ---------------------------------------------------------------------------
[[ $EUID -eq 0 ]] && die "Bitte NICHT als root ausführen. Starte das Skript als normalen Benutzer mit sudo-Rechten."
command -v sudo >/dev/null 2>&1 || die "sudo ist nicht installiert."

# Wenn stdin kein Terminal ist (z.B. curl | bash), stdin von /dev/tty neu öffnen,
# damit read-Befehle nicht die Skript-Eingabe konsumieren, sondern interaktiv lesen.
if [[ ! -t 0 ]]; then
    exec < /dev/tty || die "Kein interaktives Terminal gefunden. Bitte Skript direkt in einem interaktiven Terminal ausführen."
fi

SCRIPT_USER="${USER}"
INSTALL_DIR="/opt/alarm-system"
STATE_FILE="${HOME}/.alarm-system-install.conf"

# ---------------------------------------------------------------------------
# Banner
# ---------------------------------------------------------------------------
clear
echo -e "${BOLD}"
echo "╔═══════════════════════════════════════════════════════════╗"
echo "║        🚒  Alarm-System  –  Installations-Assistent       ║"
echo "║           github.com/TimUx/alarm-system                   ║"
echo "╚═══════════════════════════════════════════════════════════╝"
echo -e "${NC}"
echo -e "  Benutzer        : ${CYAN}${SCRIPT_USER}${NC}"
echo -e "  Zielverzeichnis : ${CYAN}${INSTALL_DIR}${NC}"
echo -e "  Datum/Zeit      : ${CYAN}$(date '+%d.%m.%Y %H:%M:%S')${NC}"
sep

# ---------------------------------------------------------------------------
# Hilfsfunktionen – Eingabe
# ---------------------------------------------------------------------------

# prompt_value <variable> <Fragetext> [Standardwert] [secret=false]
prompt_value() {
    local _var="$1"
    local _prompt="$2"
    local _default="${3:-}"
    local _secret="${4:-false}"
    local _value=""

    while true; do
        if [[ "$_secret" == "true" ]]; then
            read -rsp "  ${_prompt}${_default:+ [Vorschlag: ***]}: " _value || true
            echo
        else
            read -rp "  ${_prompt}${_default:+ [Standard: ${_default}]}: " _value || true
        fi
        _value="${_value:-${_default}}"
        if [[ -n "$_value" ]]; then
            printf -v "$_var" '%s' "$_value"
            return 0
        fi
        warn "Eingabe darf nicht leer sein."
    done
}

# prompt_optional <variable> <Fragetext> [Standardwert]
prompt_optional() {
    local _var="$1"
    local _prompt="$2"
    local _default="${3:-}"
    local _value=""
    read -rp "  ${_prompt}${_default:+ [Standard: ${_default}]}: " _value || true
    printf -v "$_var" '%s' "${_value:-${_default}}"
}

# yes_no <Fragetext> [y|n]  → gibt 0 bei ja, 1 bei nein zurück
yes_no() {
    local _prompt="$1"
    local _default="${2:-y}"
    local _yn
    while true; do
        read -rp "  ${_prompt} [${_default^^}]: " _yn
        _yn="${_yn:-${_default}}"
        case "${_yn,,}" in
            y|j|ja|yes)  return 0 ;;
            n|nein|no)   return 1 ;;
            *) warn "Bitte 'y' (ja) oder 'n' (nein) eingeben." ;;
        esac
    done
}

# ---------------------------------------------------------------------------
# Gespeicherte Eingaben: Hilfsfunktionen
# ---------------------------------------------------------------------------

# bool_to_yn <value>  → gibt "y" oder "n" zurück (für yes_no-Standardwerte)
bool_to_yn() { [[ "${1:-false}" == "true" ]] && echo "y" || echo "n"; }

# load_state: Lädt gespeicherte Eingaben aus STATE_FILE als Shell-Variablen
load_state() {
    if [[ -f "${STATE_FILE}" ]]; then
        # shellcheck disable=SC1090
        source "${STATE_FILE}" || true
        info "Gespeicherte Konfiguration geladen: ${STATE_FILE}"
        info "Vorherige Eingaben werden als Standardwerte angezeigt."
    fi
}

# save_state: Schreibt alle Eingabe-Variablen in STATE_FILE (chmod 600)
save_state() {
    local _vars=(
        INSTALL_DIR TZ
        INSTALL_MONITOR INSTALL_MESSENGER INSTALL_MAIL INSTALL_CADDY INSTALL_KIOSK KIOSK_URL
        ALARM_MONITOR_PORT ALARM_MONITOR_API_KEY ALARM_MONITOR_SETTINGS_PASSWORD ALARM_MONITOR_DISPLAY_DURATION ALARM_MONITOR_DOMAIN
        ALARM_MONITOR_ORS_API_KEY ALARM_MONITOR_METRICS_TOKEN ALARM_MONITOR_HISTORY_FILE ALARM_MONITOR_SETTINGS_FILE
        ALARM_MONITOR_GRUPPEN ALARM_MONITOR_FIRE_DEPARTMENT_NAME
        ALARM_MONITOR_DEFAULT_LATITUDE ALARM_MONITOR_DEFAULT_LONGITUDE ALARM_MONITOR_DEFAULT_LOCATION_NAME
        ALARM_MONITOR_CALENDAR_URLS
        ALARM_MONITOR_NTFY_TOPIC_URL ALARM_MONITOR_NTFY_POLL_INTERVAL ALARM_MONITOR_MESSAGES_FILE ALARM_MONITOR_MESSAGE_MAX_TTL_HOURS
        ALARM_MESSENGER_PORT ALARM_MESSENGER_ORGANIZATION_NAME ALARM_MESSENGER_API_SECRET_KEY
        ALARM_MESSENGER_JWT_SECRET ALARM_MESSENGER_SESSION_SECRET ALARM_MESSENGER_SERVER_URL
        ALARM_MESSENGER_CORS_ORIGINS ALARM_MESSENGER_DOMAIN
        ALARM_MESSENGER_ENABLE_FCM ALARM_MESSENGER_FCM_SERVICE_ACCOUNT_PATH
        ALARM_MESSENGER_ENABLE_APNS ALARM_MESSENGER_APNS_KEY_PATH ALARM_MESSENGER_APNS_KEY_ID
        ALARM_MESSENGER_APNS_TEAM_ID ALARM_MESSENGER_APNS_TOPIC ALARM_MESSENGER_APNS_PRODUCTION
        MESSENGER_ADMIN_USER MESSENGER_ADMIN_PASSWORD
        ALARM_MAIL_IMAP_HOST ALARM_MAIL_IMAP_PORT ALARM_MAIL_IMAP_USE_SSL
        ALARM_MAIL_IMAP_USERNAME ALARM_MAIL_IMAP_PASSWORD
        ALARM_MAIL_IMAP_MAILBOX ALARM_MAIL_IMAP_SEARCH ALARM_MAIL_POLL_INTERVAL
        ALARM_MAIL_HTTP_TIMEOUT ALARM_MAIL_LOG_LEVEL ALARM_MAIL_DEDUP_TTL ALARM_MAIL_DEDUP_DB
        ALARM_MAIL_TARGET_COUNT
    )
    {
        echo "# Alarm-System Install-Zustand – gespeichert am $(date '+%d.%m.%Y %H:%M:%S')"
        echo "# Wird von install.sh als Standardwerte beim nächsten Aufruf verwendet."
        echo ""
        for _v in "${_vars[@]}"; do
            printf '%s=%q\n' "$_v" "${!_v:-}"
        done
        for ((_i=1; _i<=ALARM_MAIL_TARGET_COUNT; _i++)); do
            for _suffix in TYPE URL API_KEY GROUPS; do
                _v="ALARM_MAIL_TARGET_${_i}_${_suffix}"
                printf '%s=%q\n' "$_v" "${!_v:-}"
            done
        done
    } > "${STATE_FILE}"
    chmod 600 "${STATE_FILE}"
    ok "Eingaben gespeichert: ${STATE_FILE}"
}

# ---------------------------------------------------------------------------
# Architekturen & Paketmanager erkennen
# ---------------------------------------------------------------------------
detect_system() {
    ARCH="$(uname -m)"
    OS_ID=""
    PKG_MGR=""
    PKG_INSTALL=""
    PKG_UPDATE=""

    if [[ -f /etc/os-release ]]; then
        # shellcheck disable=SC1091
        . /etc/os-release
        OS_ID="${ID:-unknown}"
    fi

    # Raspberry Pi erkennen
    IS_RPI=false
    if grep -qi "raspberry pi" /proc/cpuinfo 2>/dev/null || [[ "$OS_ID" == "raspbian" ]]; then
        IS_RPI=true
    fi

    # Paketmanager auswählen
    if command -v apt-get >/dev/null 2>&1; then
        PKG_MGR="apt"
        PKG_UPDATE="sudo apt-get update -qq"
        PKG_INSTALL="sudo apt-get install -y -qq"
    elif command -v dnf >/dev/null 2>&1; then
        PKG_MGR="dnf"
        PKG_UPDATE="sudo dnf makecache -q"
        PKG_INSTALL="sudo dnf install -y -q"
    elif command -v yum >/dev/null 2>&1; then
        PKG_MGR="yum"
        PKG_UPDATE="sudo yum makecache -q"
        PKG_INSTALL="sudo yum install -y -q"
    elif command -v pacman >/dev/null 2>&1; then
        PKG_MGR="pacman"
        PKG_UPDATE="sudo pacman -Sy --noconfirm"
        PKG_INSTALL="sudo pacman -S --noconfirm --needed"
    elif command -v zypper >/dev/null 2>&1; then
        PKG_MGR="zypper"
        PKG_UPDATE="sudo zypper refresh -q"
        PKG_INSTALL="sudo zypper install -y -q"
    elif command -v apk >/dev/null 2>&1; then
        PKG_MGR="apk"
        PKG_UPDATE="sudo apk update -q"
        PKG_INSTALL="sudo apk add -q"
    else
        die "Kein unterstützter Paketmanager gefunden (apt/dnf/yum/pacman/zypper/apk)."
    fi

    info "Architektur : ${ARCH}"
    info "Distribution: ${OS_ID:-unbekannt} (Paketmanager: ${PKG_MGR})"
}

# ---------------------------------------------------------------------------
# Schritt 1: Systemerkennung
# ---------------------------------------------------------------------------
step "Systemerkennung"
detect_system

# Standardwerte für erste Ausführung; werden durch gespeicherten Zustand überschrieben.
INSTALL_MONITOR="${INSTALL_MONITOR:-true}"
INSTALL_MESSENGER="${INSTALL_MESSENGER:-true}"
INSTALL_MAIL="${INSTALL_MAIL:-true}"
INSTALL_CADDY="${INSTALL_CADDY:-false}"
INSTALL_KIOSK="${INSTALL_KIOSK:-false}"
KIOSK_URL="${KIOSK_URL:-http://localhost:8000}"
TZ="${TZ:-Europe/Berlin}"
ALARM_MESSENGER_ENABLE_FCM="${ALARM_MESSENGER_ENABLE_FCM:-false}"
ALARM_MESSENGER_ENABLE_APNS="${ALARM_MESSENGER_ENABLE_APNS:-false}"
ALARM_MESSENGER_APNS_PRODUCTION="${ALARM_MESSENGER_APNS_PRODUCTION:-false}"
ALARM_MONITOR_SETTINGS_PASSWORD="${ALARM_MONITOR_SETTINGS_PASSWORD:-}"
ALARM_MONITOR_ORS_API_KEY="${ALARM_MONITOR_ORS_API_KEY:-}"
ALARM_MONITOR_METRICS_TOKEN="${ALARM_MONITOR_METRICS_TOKEN:-}"
ALARM_MONITOR_HISTORY_FILE="${ALARM_MONITOR_HISTORY_FILE:-}"
ALARM_MONITOR_SETTINGS_FILE="${ALARM_MONITOR_SETTINGS_FILE:-}"
ALARM_MONITOR_GRUPPEN="${ALARM_MONITOR_GRUPPEN:-}"
ALARM_MONITOR_FIRE_DEPARTMENT_NAME="${ALARM_MONITOR_FIRE_DEPARTMENT_NAME:-}"
ALARM_MONITOR_DEFAULT_LATITUDE="${ALARM_MONITOR_DEFAULT_LATITUDE:-}"
ALARM_MONITOR_DEFAULT_LONGITUDE="${ALARM_MONITOR_DEFAULT_LONGITUDE:-}"
ALARM_MONITOR_DEFAULT_LOCATION_NAME="${ALARM_MONITOR_DEFAULT_LOCATION_NAME:-}"
ALARM_MONITOR_CALENDAR_URLS="${ALARM_MONITOR_CALENDAR_URLS:-}"
ALARM_MONITOR_NTFY_TOPIC_URL="${ALARM_MONITOR_NTFY_TOPIC_URL:-}"
ALARM_MONITOR_NTFY_POLL_INTERVAL="${ALARM_MONITOR_NTFY_POLL_INTERVAL:-}"
ALARM_MONITOR_MESSAGES_FILE="${ALARM_MONITOR_MESSAGES_FILE:-}"
ALARM_MONITOR_MESSAGE_MAX_TTL_HOURS="${ALARM_MONITOR_MESSAGE_MAX_TTL_HOURS:-}"
ALARM_MAIL_HTTP_TIMEOUT="${ALARM_MAIL_HTTP_TIMEOUT:-}"
ALARM_MAIL_LOG_LEVEL="${ALARM_MAIL_LOG_LEVEL:-}"
ALARM_MAIL_DEDUP_TTL="${ALARM_MAIL_DEDUP_TTL:-}"
ALARM_MAIL_DEDUP_DB="${ALARM_MAIL_DEDUP_DB:-}"
ALARM_MAIL_TARGET_COUNT="${ALARM_MAIL_TARGET_COUNT:-0}"
load_state

# ---------------------------------------------------------------------------
# Schritt 2: Komponentenauswahl
# ---------------------------------------------------------------------------
step "Komponentenauswahl"
echo ""
echo -e "  Verfügbare Komponenten:"
echo -e "    ${CYAN}1)${NC} alarm-monitor   – Einsatz-Dashboard (Web)"
echo -e "    ${CYAN}2)${NC} alarm-messenger – Push-Benachrichtigungen (Mobile App)"
echo -e "    ${CYAN}3)${NC} alarm-mail      – IMAP-E-Mail-Parser (schickt Alarme weiter)"
echo -e "    ${CYAN}4)${NC} Caddy           – Reverse Proxy mit automatischem HTTPS (optional)"
echo ""
info "alarm-mail benötigt mindestens ein Ziel (lokal installierter Dienst oder externer Endpunkt)."
echo ""

yes_no "alarm-monitor installieren?" "$(bool_to_yn "${INSTALL_MONITOR}")" && INSTALL_MONITOR=true || INSTALL_MONITOR=false
yes_no "alarm-messenger installieren?" "$(bool_to_yn "${INSTALL_MESSENGER}")" && INSTALL_MESSENGER=true || INSTALL_MESSENGER=false
yes_no "alarm-mail installieren?" "$(bool_to_yn "${INSTALL_MAIL}")" && INSTALL_MAIL=true || INSTALL_MAIL=false

if [[ "$INSTALL_MONITOR" == "false" && "$INSTALL_MESSENGER" == "false" && "$INSTALL_MAIL" == "false" ]]; then
    die "Mindestens eine Komponente muss ausgewählt werden."
fi

if [[ "$INSTALL_MAIL" == "true" && "$INSTALL_MONITOR" == "false" && "$INSTALL_MESSENGER" == "false" ]]; then
    info "Keine lokalen Ziel-Dienste gewählt. Du wirst in Schritt 7 externe Ziele konfigurieren."
fi

yes_no "Caddy Reverse Proxy (HTTPS) konfigurieren?" "$(bool_to_yn "${INSTALL_CADDY}")" && INSTALL_CADDY=true || INSTALL_CADDY=false

# ---------------------------------------------------------------------------
# Schritt 3: Kiosk-Modus
# ---------------------------------------------------------------------------
step "Kiosk-Modus (Browser-Vollbildanzeige)"
echo ""
info "Für eine dedizierte Anzeige (z.B. Raspberry Pi, Intel NUC) kann ein Kiosk-Browser"
info "im Vollbildmodus mit minimalen GUI-Ressourcen konfiguriert werden."
echo ""
if yes_no "Kiosk-Modus konfigurieren?" "$(bool_to_yn "${INSTALL_KIOSK}")"; then
    INSTALL_KIOSK=true
    if [[ "$INSTALL_MONITOR" == "true" ]]; then
        prompt_optional KIOSK_URL "URL für Kiosk-Browser" "${KIOSK_URL:-http://localhost:8000}"
    else
        prompt_value KIOSK_URL "URL für Kiosk-Browser" "${KIOSK_URL:-}" false
    fi
else
    INSTALL_KIOSK=false
fi

# ---------------------------------------------------------------------------
# Schritt 4: Allgemeine Konfiguration
# ---------------------------------------------------------------------------
step "Allgemeine Konfiguration"

prompt_optional TZ "Zeitzone (IANA-Format)" "${TZ:-Europe/Berlin}"
prompt_value INSTALL_DIR "Installationsverzeichnis" "${INSTALL_DIR}" false

# ---------------------------------------------------------------------------
# Schritt 5: alarm-monitor Konfiguration
# ---------------------------------------------------------------------------
if [[ "$INSTALL_MONITOR" == "true" ]]; then
    step "alarm-monitor Konfiguration"

    MONITOR_API_KEY_SUGGESTION="$(openssl rand -hex 32 2>/dev/null || od -An -tx1 -N32 /dev/urandom | tr -d ' \n' | tr '[:upper:]' '[:lower:]')"
    prompt_value ALARM_MONITOR_API_KEY \
        "API-Schlüssel für alarm-monitor" \
        "${ALARM_MONITOR_API_KEY:-${MONITOR_API_KEY_SUGGESTION}}" "true"

    prompt_optional ALARM_MONITOR_PORT "Port für alarm-monitor Dashboard" "${ALARM_MONITOR_PORT:-8000}"
    prompt_optional ALARM_MONITOR_DISPLAY_DURATION "Alarm-Anzeigedauer (Minuten)" "${ALARM_MONITOR_DISPLAY_DURATION:-30}"

    MONITOR_SETTINGS_PW_SUGGESTION="$(openssl rand -hex 16 2>/dev/null || od -An -tx1 -N16 /dev/urandom | tr -d ' \n' | tr '[:upper:]' '[:lower:]')"
    prompt_value ALARM_MONITOR_SETTINGS_PASSWORD \
        "Passwort für die Einstellungsseite" \
        "${ALARM_MONITOR_SETTINGS_PASSWORD:-${MONITOR_SETTINGS_PW_SUGGESTION}}" "true"

    prompt_optional ALARM_MONITOR_ORS_API_KEY "OpenRouteService API-Schlüssel (optional, für Routing/Navigation)" "${ALARM_MONITOR_ORS_API_KEY:-}"
    prompt_optional ALARM_MONITOR_METRICS_TOKEN "Prometheus Metrics Token (optional, für /api/metrics)" "${ALARM_MONITOR_METRICS_TOKEN:-}"
    prompt_optional ALARM_MONITOR_HISTORY_FILE "Pfad zur Alarm-Historie JSON-Datei (optional)" "${ALARM_MONITOR_HISTORY_FILE:-}"
    prompt_optional ALARM_MONITOR_SETTINGS_FILE "Pfad zur Einstellungs-JSON-Datei (optional)" "${ALARM_MONITOR_SETTINGS_FILE:-}"
    prompt_optional ALARM_MONITOR_GRUPPEN "Gruppen-Konfiguration (optional, kommagetrennt)" "${ALARM_MONITOR_GRUPPEN:-}"

    if [[ -n "${ALARM_MONITOR_CALENDAR_URLS:-}" ]]; then
        CALENDAR_ENABLED_DEFAULT="y"
    else
        CALENDAR_ENABLED_DEFAULT="n"
    fi
    if yes_no "Kalender-Integration nutzen?" "${CALENDAR_ENABLED_DEFAULT}"; then
        prompt_optional ALARM_MONITOR_CALENDAR_URLS "Kalender-URLs (optional, komma- oder zeilengetrennt)" "${ALARM_MONITOR_CALENDAR_URLS:-}"
    else
        ALARM_MONITOR_CALENDAR_URLS=""
    fi

    if [[ -n "${ALARM_MONITOR_NTFY_TOPIC_URL:-}" || -n "${ALARM_MONITOR_NTFY_POLL_INTERVAL:-}" || -n "${ALARM_MONITOR_MESSAGES_FILE:-}" || -n "${ALARM_MONITOR_MESSAGE_MAX_TTL_HOURS:-}" ]]; then
        NTFY_ENABLED_DEFAULT="y"
    else
        NTFY_ENABLED_DEFAULT="n"
    fi
    if yes_no "ntfy.sh Integration nutzen?" "${NTFY_ENABLED_DEFAULT}"; then
        prompt_optional ALARM_MONITOR_NTFY_TOPIC_URL "ntfy Topic-URL (optional)" "${ALARM_MONITOR_NTFY_TOPIC_URL:-}"
        prompt_optional ALARM_MONITOR_NTFY_POLL_INTERVAL "ntfy Abfrage-Intervall in Sekunden (optional)" "${ALARM_MONITOR_NTFY_POLL_INTERVAL:-}"
        prompt_optional ALARM_MONITOR_MESSAGES_FILE "Pfad zur Nachrichten-Datei (optional)" "${ALARM_MONITOR_MESSAGES_FILE:-}"
        prompt_optional ALARM_MONITOR_MESSAGE_MAX_TTL_HOURS "Maximale Nachrichten-TTL in Stunden (optional)" "${ALARM_MONITOR_MESSAGE_MAX_TTL_HOURS:-}"
    else
        ALARM_MONITOR_NTFY_TOPIC_URL=""
        ALARM_MONITOR_NTFY_POLL_INTERVAL=""
        ALARM_MONITOR_MESSAGES_FILE=""
        ALARM_MONITOR_MESSAGE_MAX_TTL_HOURS=""
    fi

    prompt_optional ALARM_MONITOR_FIRE_DEPARTMENT_NAME "Name der Feuerwehr / Wache (optional, kann auch im Web-Interface gesetzt werden)" "${ALARM_MONITOR_FIRE_DEPARTMENT_NAME:-}"
    prompt_optional ALARM_MONITOR_DEFAULT_LATITUDE "Standard-Breitengrad für Wetteranzeige (optional, z.B. 48.1374)" "${ALARM_MONITOR_DEFAULT_LATITUDE:-}"
    prompt_optional ALARM_MONITOR_DEFAULT_LONGITUDE "Standard-Längengrad für Wetteranzeige (optional, z.B. 11.5755)" "${ALARM_MONITOR_DEFAULT_LONGITUDE:-}"
    prompt_optional ALARM_MONITOR_DEFAULT_LOCATION_NAME "Standard-Ortsname für Wetteranzeige (optional, z.B. München)" "${ALARM_MONITOR_DEFAULT_LOCATION_NAME:-}"

    if [[ "$INSTALL_CADDY" == "true" ]]; then
        prompt_value ALARM_MONITOR_DOMAIN "Domain für alarm-monitor (z.B. monitor.feuerwehr.example.com)" "${ALARM_MONITOR_DOMAIN:-}" false
    fi
fi

# ---------------------------------------------------------------------------
# Schritt 6: alarm-messenger Konfiguration
# ---------------------------------------------------------------------------
if [[ "$INSTALL_MESSENGER" == "true" ]]; then
    step "alarm-messenger Konfiguration"

    MESSENGER_API_KEY_SUGGESTION="$(openssl rand -hex 32 2>/dev/null || od -An -tx1 -N32 /dev/urandom | tr -d ' \n' | tr '[:upper:]' '[:lower:]')"
    JWT_SECRET_SUGGESTION="$(openssl rand -hex 32 2>/dev/null || od -An -tx1 -N32 /dev/urandom | tr -d ' \n' | tr '[:upper:]' '[:lower:]')"
    SESSION_SECRET_SUGGESTION="$(openssl rand -hex 32 2>/dev/null || od -An -tx1 -N32 /dev/urandom | tr -d ' \n' | tr '[:upper:]' '[:lower:]')"

    prompt_value ALARM_MESSENGER_API_SECRET_KEY \
        "API-Schlüssel für alarm-messenger" \
        "${ALARM_MESSENGER_API_SECRET_KEY:-${MESSENGER_API_KEY_SUGGESTION}}" "true"

    prompt_value ALARM_MESSENGER_JWT_SECRET \
        "JWT-Secret für Admin-Interface" \
        "${ALARM_MESSENGER_JWT_SECRET:-${JWT_SECRET_SUGGESTION}}" "true"

    prompt_value ALARM_MESSENGER_SESSION_SECRET \
        "Session-Secret für Admin-Session-Verwaltung" \
        "${ALARM_MESSENGER_SESSION_SECRET:-${SESSION_SECRET_SUGGESTION}}" "true"

    prompt_optional ALARM_MESSENGER_PORT "Port für alarm-messenger" "${ALARM_MESSENGER_PORT:-3000}"
    prompt_value ALARM_MESSENGER_ORGANIZATION_NAME "Name der Organisation / Feuerwehr" "${ALARM_MESSENGER_ORGANIZATION_NAME:-Feuerwehr Musterstadt}" false

    # Server-URL für QR-Code-Generierung
    SERVER_IP="$(hostname -I 2>/dev/null | awk '{print $1}' || echo "localhost")"
    MESSENGER_URL_SUGGESTION="http://${SERVER_IP}:${ALARM_MESSENGER_PORT:-3000}"
    prompt_value ALARM_MESSENGER_SERVER_URL \
        "Externe Server-URL für QR-Code (von außen erreichbar)" \
        "${ALARM_MESSENGER_SERVER_URL:-${MESSENGER_URL_SUGGESTION}}" false

    prompt_optional ALARM_MESSENGER_CORS_ORIGINS "CORS-Origins (kommagetrennt, * = alle)" "${ALARM_MESSENGER_CORS_ORIGINS:-*}"

    if [[ "$INSTALL_CADDY" == "true" ]]; then
        prompt_value ALARM_MESSENGER_DOMAIN "Domain für alarm-messenger (z.B. messenger.feuerwehr.example.com)" "${ALARM_MESSENGER_DOMAIN:-}" false
    fi

    echo ""
    info "Push-Benachrichtigungen (optional – für bessere Hintergrundlieferung auf Mobilgeräten)"

    if yes_no "Firebase Cloud Messaging (FCM) für Android aktivieren?" "$(bool_to_yn "${ALARM_MESSENGER_ENABLE_FCM}")"; then
        ALARM_MESSENGER_ENABLE_FCM=true
        prompt_value ALARM_MESSENGER_FCM_SERVICE_ACCOUNT_PATH "Pfad zur Firebase Service-Account JSON-Datei" "${ALARM_MESSENGER_FCM_SERVICE_ACCOUNT_PATH:-}" false
    else
        ALARM_MESSENGER_ENABLE_FCM=false
    fi

    if yes_no "Apple Push Notification Service (APNs) für iOS aktivieren?" "$(bool_to_yn "${ALARM_MESSENGER_ENABLE_APNS}")"; then
        ALARM_MESSENGER_ENABLE_APNS=true
        prompt_value ALARM_MESSENGER_APNS_KEY_PATH "Pfad zur APNs .p8 Key-Datei" "${ALARM_MESSENGER_APNS_KEY_PATH:-}" false
        prompt_value ALARM_MESSENGER_APNS_KEY_ID "APNs Key-ID (10 Zeichen)" "${ALARM_MESSENGER_APNS_KEY_ID:-}" false
        prompt_value ALARM_MESSENGER_APNS_TEAM_ID "Apple Team-ID (10 Zeichen)" "${ALARM_MESSENGER_APNS_TEAM_ID:-}" false
        prompt_value ALARM_MESSENGER_APNS_TOPIC "APNs Topic (Bundle-ID, z.B. com.alarmmessenger)" "${ALARM_MESSENGER_APNS_TOPIC:-}" false
        yes_no "APNs Produktionsumgebung verwenden? (nein = Sandbox/Test)" "$(bool_to_yn "${ALARM_MESSENGER_APNS_PRODUCTION}")" \
            && ALARM_MESSENGER_APNS_PRODUCTION=true || ALARM_MESSENGER_APNS_PRODUCTION=false
    else
        ALARM_MESSENGER_ENABLE_APNS=false
    fi

    # Admin-Benutzer für Messenger
    echo ""
    step "alarm-messenger Admin-Benutzer"
    info "Dieser Benutzer wird nach dem Start automatisch angelegt (nur beim ersten Start)."
    prompt_value MESSENGER_ADMIN_USER "Admin-Benutzername" "${MESSENGER_ADMIN_USER:-admin}" false
    prompt_value MESSENGER_ADMIN_PASSWORD "Admin-Passwort" "${MESSENGER_ADMIN_PASSWORD:-}" "true"
fi

# ---------------------------------------------------------------------------
# Schritt 7: alarm-mail Konfiguration
# ---------------------------------------------------------------------------
if [[ "$INSTALL_MAIL" == "true" ]]; then
    step "alarm-mail Konfiguration (IMAP)"

    prompt_value ALARM_MAIL_IMAP_HOST "IMAP-Server (z.B. imap.gmail.com)" "${ALARM_MAIL_IMAP_HOST:-}" false
    prompt_optional ALARM_MAIL_IMAP_PORT "IMAP-Port" "${ALARM_MAIL_IMAP_PORT:-993}"
    prompt_optional ALARM_MAIL_IMAP_USE_SSL "IMAP SSL verwenden (true/false)" "${ALARM_MAIL_IMAP_USE_SSL:-true}"
    prompt_value ALARM_MAIL_IMAP_USERNAME "IMAP-Benutzername / E-Mail-Adresse" "${ALARM_MAIL_IMAP_USERNAME:-}" false
    prompt_value ALARM_MAIL_IMAP_PASSWORD "IMAP-Passwort" "${ALARM_MAIL_IMAP_PASSWORD:-}" "true"
    prompt_optional ALARM_MAIL_IMAP_MAILBOX "IMAP-Postfach / Ordner" "${ALARM_MAIL_IMAP_MAILBOX:-INBOX}"
    prompt_optional ALARM_MAIL_IMAP_SEARCH "IMAP-Suchkriterium" "${ALARM_MAIL_IMAP_SEARCH:-UNSEEN}"
    prompt_optional ALARM_MAIL_POLL_INTERVAL "Abfrageintervall in Sekunden" "${ALARM_MAIL_POLL_INTERVAL:-60}"
    prompt_optional ALARM_MAIL_HTTP_TIMEOUT "HTTP-Timeout in Sekunden (optional, Standard: 10)" "${ALARM_MAIL_HTTP_TIMEOUT:-}"
    prompt_optional ALARM_MAIL_LOG_LEVEL "Log-Level (DEBUG/INFO/WARNING/ERROR, optional, Standard: INFO)" "${ALARM_MAIL_LOG_LEVEL:-}"
    prompt_optional ALARM_MAIL_DEDUP_TTL "Deduplizierungs-TTL in Sekunden (optional, Standard: 300)" "${ALARM_MAIL_DEDUP_TTL:-}"
    prompt_optional ALARM_MAIL_DEDUP_DB "Pfad zur SQLite-Deduplizierungs-DB (optional)" "${ALARM_MAIL_DEDUP_DB:-}"

    # --- Ziel-Konfiguration (Multitarget) ---
    echo ""
    step "alarm-mail Ziele konfigurieren"
    info "alarm-mail kann Alarme an mehrere Ziele (alarm-monitor / alarm-messenger) weiterleiten."
    info "Jedes Ziel kann optional auf bestimmte Alarmgruppen eingeschränkt werden."
    echo ""

    # Bei Erstkonfiguration: lokal installierte Dienste als Ziele vorbelegen
    if [[ "${ALARM_MAIL_TARGET_COUNT:-0}" -eq 0 ]]; then
        _t=0
        if [[ "$INSTALL_MONITOR" == "true" ]]; then
            _t=$((_t + 1))
            printf -v "ALARM_MAIL_TARGET_${_t}_TYPE"    '%s' "alarm-monitor"
            printf -v "ALARM_MAIL_TARGET_${_t}_URL"     '%s' "http://alarm-monitor:8000"
            printf -v "ALARM_MAIL_TARGET_${_t}_API_KEY" '%s' "${ALARM_MONITOR_API_KEY:-}"
            printf -v "ALARM_MAIL_TARGET_${_t}_GROUPS"  '%s' ""
            info "Ziel ${_t} vorbelegt: alarm-monitor → http://alarm-monitor:8000"
            _gvar="ALARM_MAIL_TARGET_${_t}_GROUPS"
            prompt_optional "$_gvar" "Alarmgruppen-Filter für Ziel ${_t} (kommagetrennt, leer = alle)" "${!_gvar:-}"
        fi
        if [[ "$INSTALL_MESSENGER" == "true" ]]; then
            _t=$((_t + 1))
            printf -v "ALARM_MAIL_TARGET_${_t}_TYPE"    '%s' "alarm-messenger"
            printf -v "ALARM_MAIL_TARGET_${_t}_URL"     '%s' "http://alarm-messenger:3000"
            printf -v "ALARM_MAIL_TARGET_${_t}_API_KEY" '%s' "${ALARM_MESSENGER_API_SECRET_KEY:-}"
            printf -v "ALARM_MAIL_TARGET_${_t}_GROUPS"  '%s' ""
            info "Ziel ${_t} vorbelegt: alarm-messenger → http://alarm-messenger:3000"
            _gvar="ALARM_MAIL_TARGET_${_t}_GROUPS"
            prompt_optional "$_gvar" "Alarmgruppen-Filter für Ziel ${_t} (kommagetrennt, leer = alle)" "${!_gvar:-}"
        fi
        ALARM_MAIL_TARGET_COUNT=$_t
    else
        info "Bereits konfigurierte Ziele:"
        for ((_i=1; _i<=ALARM_MAIL_TARGET_COUNT; _i++)); do
            _tv="ALARM_MAIL_TARGET_${_i}_TYPE"; _uv="ALARM_MAIL_TARGET_${_i}_URL"
            _gv="ALARM_MAIL_TARGET_${_i}_GROUPS"
            _gdisp="${!_gv:-}"; [[ -n "$_gdisp" ]] && _gdisp=" (Gruppen: ${_gdisp})" || _gdisp=" (alle Gruppen)"
            info "  Ziel ${_i}: ${!_tv} → ${!_uv}${_gdisp}"
        done
    fi

    # Weitere (externe) Ziele hinzufügen
    while yes_no "Weiteres Ziel hinzufügen?" "n"; do
        ALARM_MAIL_TARGET_COUNT=$((ALARM_MAIL_TARGET_COUNT + 1))
        _n=$ALARM_MAIL_TARGET_COUNT
        echo ""
        info "Neues Ziel ${_n}:"
        _tv="ALARM_MAIL_TARGET_${_n}_TYPE"
        _uv="ALARM_MAIL_TARGET_${_n}_URL"
        _akv="ALARM_MAIL_TARGET_${_n}_API_KEY"
        _gv="ALARM_MAIL_TARGET_${_n}_GROUPS"
        prompt_optional "$_tv"  "Ziel-Typ (alarm-monitor/alarm-messenger)" "${!_tv:-alarm-monitor}"
        prompt_value   "$_uv"  "Ziel-URL (z.B. https://monitor.example.com)" "${!_uv:-}" false
        prompt_value   "$_akv" "API-Key" "${!_akv:-}" true
        prompt_optional "$_gv"  "Alarmgruppen-Filter (kommagetrennt, leer = alle)" "${!_gv:-}"
    done

    if [[ "${ALARM_MAIL_TARGET_COUNT:-0}" -eq 0 ]]; then
        die "alarm-mail benötigt mindestens ein Ziel."
    fi
fi

# ---------------------------------------------------------------------------
# Zusammenfassung vor der Installation
# ---------------------------------------------------------------------------
# Eingaben speichern (auch wenn die Installation abgebrochen wird)
save_state

echo ""
sep
echo -e "${BOLD}  Installationsübersicht${NC}"
sep
echo -e "  Installationsverzeichnis : ${CYAN}${INSTALL_DIR}${NC}"
echo -e "  Zeitzone                 : ${CYAN}${TZ}${NC}"
echo -e "  Architektur              : ${CYAN}${ARCH}${NC}"
echo -e "  Paketmanager             : ${CYAN}${PKG_MGR}${NC}"
echo ""
echo -e "  Komponenten:"
[[ "$INSTALL_MONITOR"   == "true" ]] && echo -e "    ${GREEN}✔${NC} alarm-monitor   (Port ${ALARM_MONITOR_PORT:-8000})"
[[ "$INSTALL_MESSENGER" == "true" ]] && echo -e "    ${GREEN}✔${NC} alarm-messenger (Port ${ALARM_MESSENGER_PORT:-3000})"
[[ "$INSTALL_MAIL"      == "true" ]] && echo -e "    ${GREEN}✔${NC} alarm-mail"
[[ "$INSTALL_CADDY"     == "true" ]] && echo -e "    ${GREEN}✔${NC} Caddy (Reverse Proxy / HTTPS)"
[[ "$INSTALL_KIOSK"     == "true" ]] && echo -e "    ${GREEN}✔${NC} Kiosk-Browser → ${KIOSK_URL}"
sep
echo ""
yes_no "Installation jetzt starten?" "y" || { echo "Abgebrochen."; exit 0; }

# ===========================================================================
#  AB HIER: SYSTEMÄNDERUNGEN
# ===========================================================================

# ---------------------------------------------------------------------------
# Schritt A: Systemabhängigkeiten installieren
# ---------------------------------------------------------------------------
step "Systempakete installieren"
eval "${PKG_UPDATE}" 2>/dev/null || true

# Basis-Pakete je nach Paketmanager
case "$PKG_MGR" in
    apt)
        eval "${PKG_INSTALL} git curl wget ca-certificates gnupg lsb-release unzip"
        ;;
    dnf|yum)
        eval "${PKG_INSTALL} git curl wget ca-certificates gnupg2 unzip"
        ;;
    pacman)
        eval "${PKG_INSTALL} git curl wget ca-certificates gnupg unzip"
        ;;
    zypper)
        eval "${PKG_INSTALL} git curl wget ca-certificates gpg2 unzip"
        ;;
    apk)
        eval "${PKG_INSTALL} git curl wget ca-certificates gnupg unzip"
        ;;
esac
ok "Basis-Pakete installiert."

# ---------------------------------------------------------------------------
# Schritt A2: Systemlokalisierung konfigurieren (Deutsch)
# ---------------------------------------------------------------------------
step "Systemlokalisierung konfigurieren (Sprache: Deutsch, Tastatur: de, Zeitzone: ${TZ})"

case "$PKG_MGR" in
    apt)
        eval "${PKG_INSTALL} locales keyboard-configuration console-setup" 2>/dev/null || true
        # Locale: de_DE.UTF-8 aktivieren
        if ! grep -q "^de_DE.UTF-8 UTF-8" /etc/locale.gen 2>/dev/null; then
            sudo sed -i 's/^#\s*de_DE\.UTF-8 UTF-8/de_DE.UTF-8 UTF-8/' /etc/locale.gen
            # Falls sed nichts gefunden hat (Zeile fehlte), einfach anhängen
            grep -q "^de_DE.UTF-8 UTF-8" /etc/locale.gen 2>/dev/null \
                || echo "de_DE.UTF-8 UTF-8" | sudo tee -a /etc/locale.gen > /dev/null
        fi
        sudo locale-gen de_DE.UTF-8 2>/dev/null || true
        sudo update-locale LANG=de_DE.UTF-8 LC_ALL=de_DE.UTF-8 LANGUAGE=de_DE:de 2>/dev/null || true
        # Tastatur-Layout auf Deutsch setzen
        if [[ -f /etc/default/keyboard ]]; then
            sudo sed -i 's/^XKBLAYOUT=.*/XKBLAYOUT="de"/' /etc/default/keyboard
            sudo sed -i 's/^XKBVARIANT=.*/XKBVARIANT=""/' /etc/default/keyboard
        else
            printf 'XKBLAYOUT="de"\nXKBVARIANT=""\nXKBOPTIONS=""\n' \
                | sudo tee /etc/default/keyboard > /dev/null
        fi
        sudo dpkg-reconfigure -f noninteractive keyboard-configuration 2>/dev/null || true
        sudo setupcon 2>/dev/null || true
        ;;
    dnf|yum)
        eval "${PKG_INSTALL} glibc-langpack-de" 2>/dev/null || true
        sudo localectl set-locale LANG=de_DE.UTF-8 LC_ALL=de_DE.UTF-8 LANGUAGE=de_DE:de 2>/dev/null || true
        sudo localectl set-keymap de 2>/dev/null || true
        sudo localectl set-x11-keymap de "" "" "" 2>/dev/null || true
        ;;
    pacman)
        # Locale aktivieren
        if ! grep -q "^de_DE.UTF-8 UTF-8" /etc/locale.gen 2>/dev/null; then
            sudo sed -i 's/^#de_DE\.UTF-8 UTF-8/de_DE.UTF-8 UTF-8/' /etc/locale.gen
        fi
        sudo locale-gen 2>/dev/null || true
        echo 'LANG=de_DE.UTF-8' | sudo tee /etc/locale.conf > /dev/null
        # Konsolen-Tastatur
        if [[ -f /etc/vconsole.conf ]]; then
            sudo sed -i 's/^KEYMAP=.*/KEYMAP=de-latin1/' /etc/vconsole.conf
        else
            echo 'KEYMAP=de-latin1' | sudo tee /etc/vconsole.conf > /dev/null
        fi
        sudo localectl set-x11-keymap de 2>/dev/null || true
        ;;
    zypper)
        eval "${PKG_INSTALL} glibc-locale-de" 2>/dev/null || true
        sudo localectl set-locale LANG=de_DE.UTF-8 2>/dev/null || true
        sudo localectl set-keymap de 2>/dev/null || true
        sudo localectl set-x11-keymap de "" "" "" 2>/dev/null || true
        ;;
    apk)
        eval "${PKG_INSTALL} musl-locales musl-locales-lang" 2>/dev/null || true
        if grep -q "^LANG=" /etc/environment 2>/dev/null; then
            sudo sed -i 's/^LANG=.*/LANG=de_DE.UTF-8/' /etc/environment
        else
            echo 'LANG=de_DE.UTF-8' | sudo tee -a /etc/environment > /dev/null
        fi
        # Tastatur-Layout (X11, falls vorhanden)
        sudo localectl set-x11-keymap de 2>/dev/null || true
        ;;
esac

# Zeitzone system-weit setzen (zusätzlich zur TZ-Umgebungsvariable in Docker)
sudo timedatectl set-timezone "${TZ}" 2>/dev/null \
    || sudo ln -sf "/usr/share/zoneinfo/${TZ}" /etc/localtime 2>/dev/null \
    || true

ok "Lokalisierung konfiguriert: de_DE.UTF-8 / Tastatur: de / Zeitzone: ${TZ}"

# ---------------------------------------------------------------------------
# Schritt B: Docker installieren
# ---------------------------------------------------------------------------
step "Docker installieren / prüfen"

if command -v docker >/dev/null 2>&1; then
    info "Docker bereits installiert: $(docker --version)"
else
    info "Docker wird über das offizielle Installationsskript installiert …"

    # get.docker.com unterstützt apt- und rpm-basierte Systeme (inkl. Raspberry Pi OS)
    if [[ "$PKG_MGR" == "apt" || "$PKG_MGR" == "dnf" || "$PKG_MGR" == "yum" ]]; then
        curl -fsSL https://get.docker.com -o /tmp/get-docker.sh
        sudo sh /tmp/get-docker.sh
        rm -f /tmp/get-docker.sh
    elif [[ "$PKG_MGR" == "pacman" ]]; then
        eval "${PKG_INSTALL} docker"
    elif [[ "$PKG_MGR" == "zypper" ]]; then
        eval "${PKG_INSTALL} docker"
    elif [[ "$PKG_MGR" == "apk" ]]; then
        eval "${PKG_INSTALL} docker"
    fi
    ok "Docker installiert."
fi

# Docker Compose (als Plugin oder Standalone)
if ! docker compose version >/dev/null 2>&1; then
    info "Docker Compose Plugin wird installiert …"
    case "$PKG_MGR" in
        apt)    eval "${PKG_INSTALL} docker-compose-plugin" ;;
        dnf|yum) eval "${PKG_INSTALL} docker-compose-plugin" 2>/dev/null \
                   || eval "${PKG_INSTALL} docker-compose" ;;
        *)      eval "${PKG_INSTALL} docker-compose" 2>/dev/null || true ;;
    esac
    ok "Docker Compose installiert."
else
    info "Docker Compose bereits verfügbar: $(docker compose version)"
fi

# Benutzer zur Docker-Gruppe hinzufügen
sudo usermod -aG docker "${SCRIPT_USER}"

# Docker starten und aktivieren
sudo systemctl enable docker 2>/dev/null || true
sudo systemctl start  docker 2>/dev/null || true
ok "Docker-Dienst aktiviert und gestartet."

# ---------------------------------------------------------------------------
# Schritt C: Verzeichnisstruktur anlegen
# ---------------------------------------------------------------------------
step "Verzeichnisstruktur anlegen"
sudo mkdir -p "${INSTALL_DIR}"
sudo chown -R "${SCRIPT_USER}:${SCRIPT_USER}" "${INSTALL_DIR}"
mkdir -p "${INSTALL_DIR}"/{backup,logs}
ok "Verzeichnisse angelegt: ${INSTALL_DIR}"

# ---------------------------------------------------------------------------
# Schritt D: .env Datei generieren
# ---------------------------------------------------------------------------
step ".env Konfigurationsdatei generieren"

ENV_FILE="${INSTALL_DIR}/.env"

cat > "${ENV_FILE}" <<EOF
# =============================================================================
# Alarm-System Konfiguration
# Generiert am: $(date '+%d.%m.%Y %H:%M:%S')
# =============================================================================

# Zeitzone
TZ=${TZ}

EOF

if [[ "$INSTALL_MONITOR" == "true" ]]; then
    cat >> "${ENV_FILE}" <<EOF
# =============================================================================
# ALARM-MONITOR
# =============================================================================
ALARM_MONITOR_PORT=${ALARM_MONITOR_PORT:-8000}
ALARM_MONITOR_API_KEY=${ALARM_MONITOR_API_KEY}
ALARM_MONITOR_SETTINGS_PASSWORD=${ALARM_MONITOR_SETTINGS_PASSWORD}
ALARM_MONITOR_DISPLAY_DURATION=${ALARM_MONITOR_DISPLAY_DURATION:-30}
${ALARM_MONITOR_DOMAIN:+ALARM_MONITOR_DOMAIN=${ALARM_MONITOR_DOMAIN}}
${ALARM_MONITOR_ORS_API_KEY:+ALARM_MONITOR_ORS_API_KEY=${ALARM_MONITOR_ORS_API_KEY}}
${ALARM_MONITOR_METRICS_TOKEN:+ALARM_MONITOR_METRICS_TOKEN=${ALARM_MONITOR_METRICS_TOKEN}}
${ALARM_MONITOR_HISTORY_FILE:+ALARM_MONITOR_HISTORY_FILE=${ALARM_MONITOR_HISTORY_FILE}}
${ALARM_MONITOR_SETTINGS_FILE:+ALARM_MONITOR_SETTINGS_FILE=${ALARM_MONITOR_SETTINGS_FILE}}
${ALARM_MONITOR_GRUPPEN:+ALARM_MONITOR_GRUPPEN=${ALARM_MONITOR_GRUPPEN}}
${ALARM_MONITOR_CALENDAR_URLS:+ALARM_MONITOR_CALENDAR_URLS=${ALARM_MONITOR_CALENDAR_URLS}}
${ALARM_MONITOR_NTFY_TOPIC_URL:+ALARM_MONITOR_NTFY_TOPIC_URL=${ALARM_MONITOR_NTFY_TOPIC_URL}}
${ALARM_MONITOR_NTFY_POLL_INTERVAL:+ALARM_MONITOR_NTFY_POLL_INTERVAL=${ALARM_MONITOR_NTFY_POLL_INTERVAL}}
${ALARM_MONITOR_MESSAGES_FILE:+ALARM_MONITOR_MESSAGES_FILE=${ALARM_MONITOR_MESSAGES_FILE}}
${ALARM_MONITOR_MESSAGE_MAX_TTL_HOURS:+ALARM_MONITOR_MESSAGE_MAX_TTL_HOURS=${ALARM_MONITOR_MESSAGE_MAX_TTL_HOURS}}
${ALARM_MONITOR_FIRE_DEPARTMENT_NAME:+ALARM_MONITOR_FIRE_DEPARTMENT_NAME=${ALARM_MONITOR_FIRE_DEPARTMENT_NAME}}
${ALARM_MONITOR_DEFAULT_LATITUDE:+ALARM_MONITOR_DEFAULT_LATITUDE=${ALARM_MONITOR_DEFAULT_LATITUDE}}
${ALARM_MONITOR_DEFAULT_LONGITUDE:+ALARM_MONITOR_DEFAULT_LONGITUDE=${ALARM_MONITOR_DEFAULT_LONGITUDE}}
${ALARM_MONITOR_DEFAULT_LOCATION_NAME:+ALARM_MONITOR_DEFAULT_LOCATION_NAME=${ALARM_MONITOR_DEFAULT_LOCATION_NAME}}

EOF
fi

if [[ "$INSTALL_MESSENGER" == "true" ]]; then
    cat >> "${ENV_FILE}" <<EOF
# =============================================================================
# ALARM-MESSENGER
# =============================================================================
ALARM_MESSENGER_PORT=${ALARM_MESSENGER_PORT:-3000}
ALARM_MESSENGER_SERVER_URL=${ALARM_MESSENGER_SERVER_URL}
ALARM_MESSENGER_ORGANIZATION_NAME=${ALARM_MESSENGER_ORGANIZATION_NAME}
ALARM_MESSENGER_API_SECRET_KEY=${ALARM_MESSENGER_API_SECRET_KEY}
ALARM_MESSENGER_JWT_SECRET=${ALARM_MESSENGER_JWT_SECRET}
ALARM_MESSENGER_SESSION_SECRET=${ALARM_MESSENGER_SESSION_SECRET}
ALARM_MESSENGER_CORS_ORIGINS=${ALARM_MESSENGER_CORS_ORIGINS:-*}
${ALARM_MESSENGER_DOMAIN:+ALARM_MESSENGER_DOMAIN=${ALARM_MESSENGER_DOMAIN}}

# Push-Benachrichtigungen
ALARM_MESSENGER_ENABLE_FCM=${ALARM_MESSENGER_ENABLE_FCM:-false}
ALARM_MESSENGER_ENABLE_APNS=${ALARM_MESSENGER_ENABLE_APNS:-false}
EOF

    if [[ "${ALARM_MESSENGER_ENABLE_FCM:-false}" == "true" ]]; then
        echo "ALARM_MESSENGER_FCM_SERVICE_ACCOUNT_PATH=${ALARM_MESSENGER_FCM_SERVICE_ACCOUNT_PATH}" >> "${ENV_FILE}"
    fi

    if [[ "${ALARM_MESSENGER_ENABLE_APNS:-false}" == "true" ]]; then
        cat >> "${ENV_FILE}" <<EOF
ALARM_MESSENGER_APNS_KEY_PATH=${ALARM_MESSENGER_APNS_KEY_PATH}
ALARM_MESSENGER_APNS_KEY_ID=${ALARM_MESSENGER_APNS_KEY_ID}
ALARM_MESSENGER_APNS_TEAM_ID=${ALARM_MESSENGER_APNS_TEAM_ID}
ALARM_MESSENGER_APNS_TOPIC=${ALARM_MESSENGER_APNS_TOPIC}
ALARM_MESSENGER_APNS_PRODUCTION=${ALARM_MESSENGER_APNS_PRODUCTION:-false}
EOF
    fi
    echo "" >> "${ENV_FILE}"
fi

if [[ "$INSTALL_MAIL" == "true" ]]; then
    cat >> "${ENV_FILE}" <<EOF
# =============================================================================
# ALARM-MAIL (IMAP)
# =============================================================================
ALARM_MAIL_IMAP_HOST=${ALARM_MAIL_IMAP_HOST}
ALARM_MAIL_IMAP_PORT=${ALARM_MAIL_IMAP_PORT:-993}
ALARM_MAIL_IMAP_USE_SSL=${ALARM_MAIL_IMAP_USE_SSL:-true}
ALARM_MAIL_IMAP_USERNAME=${ALARM_MAIL_IMAP_USERNAME}
ALARM_MAIL_IMAP_PASSWORD=${ALARM_MAIL_IMAP_PASSWORD}
ALARM_MAIL_IMAP_MAILBOX=${ALARM_MAIL_IMAP_MAILBOX:-INBOX}
ALARM_MAIL_IMAP_SEARCH=${ALARM_MAIL_IMAP_SEARCH:-UNSEEN}
ALARM_MAIL_POLL_INTERVAL=${ALARM_MAIL_POLL_INTERVAL:-60}
${ALARM_MAIL_HTTP_TIMEOUT:+ALARM_MAIL_HTTP_TIMEOUT=${ALARM_MAIL_HTTP_TIMEOUT}}
${ALARM_MAIL_LOG_LEVEL:+ALARM_MAIL_LOG_LEVEL=${ALARM_MAIL_LOG_LEVEL}}
${ALARM_MAIL_DEDUP_TTL:+ALARM_MAIL_DEDUP_TTL=${ALARM_MAIL_DEDUP_TTL}}
${ALARM_MAIL_DEDUP_DB:+ALARM_MAIL_DEDUP_DB=${ALARM_MAIL_DEDUP_DB}}

EOF
    for ((_i=1; _i<=ALARM_MAIL_TARGET_COUNT; _i++)); do
        _tv="ALARM_MAIL_TARGET_${_i}_TYPE"
        _uv="ALARM_MAIL_TARGET_${_i}_URL"
        _akv="ALARM_MAIL_TARGET_${_i}_API_KEY"
        _gv="ALARM_MAIL_TARGET_${_i}_GROUPS"
        cat >> "${ENV_FILE}" <<EOF
ALARM_MAIL_TARGET_${_i}_TYPE=${!_tv}
ALARM_MAIL_TARGET_${_i}_URL=${!_uv}
ALARM_MAIL_TARGET_${_i}_API_KEY=${!_akv}
EOF
        [[ -n "${!_gv:-}" ]] && echo "ALARM_MAIL_TARGET_${_i}_GROUPS=${!_gv}" >> "${ENV_FILE}"
    done
    echo "" >> "${ENV_FILE}"
fi

chmod 600 "${ENV_FILE}"
ok ".env Datei erstellt: ${ENV_FILE} (Berechtigungen: 600)"

# ---------------------------------------------------------------------------
# Schritt E: docker-compose.yml generieren
# ---------------------------------------------------------------------------
step "docker-compose.yml generieren"

COMPOSE_FILE="${INSTALL_DIR}/docker-compose.yml"

# Kopfbereich
cat > "${COMPOSE_FILE}" <<'COMPOSE_HEADER'
# =============================================================================
# Alarm-System – Docker Compose Konfiguration
# Generiert durch install.sh
# =============================================================================
networks:
  alarm-network:
    driver: bridge
    name: alarm-network

volumes:
COMPOSE_HEADER

[[ "$INSTALL_MONITOR"   == "true" ]] && echo "  alarm-monitor-data:"   >> "${COMPOSE_FILE}" && echo "    driver: local" >> "${COMPOSE_FILE}"
[[ "$INSTALL_MESSENGER" == "true" ]] && echo "  alarm-messenger-data:" >> "${COMPOSE_FILE}" && echo "    driver: local" >> "${COMPOSE_FILE}"
[[ "$INSTALL_CADDY"     == "true" ]] && printf "  caddy-data:\n    driver: local\n  caddy-config:\n    driver: local\n" >> "${COMPOSE_FILE}"

echo "" >> "${COMPOSE_FILE}"
echo "services:" >> "${COMPOSE_FILE}"

# alarm-monitor
if [[ "$INSTALL_MONITOR" == "true" ]]; then
    cat >> "${COMPOSE_FILE}" <<'EOF'

  # Alarm Monitor – Dashboard für die Anzeige von Einsätzen
  alarm-monitor:
    image: ghcr.io/timux/alarm-monitor:latest
    container_name: alarm-monitor
    restart: unless-stopped
    ports:
      - "${ALARM_MONITOR_PORT:-8000}:8000"
    networks:
      - alarm-network
    environment:
      - ALARM_DASHBOARD_API_KEY=${ALARM_MONITOR_API_KEY}
      - ALARM_DASHBOARD_SETTINGS_PASSWORD=${ALARM_MONITOR_SETTINGS_PASSWORD}
EOF

    if [[ "$INSTALL_MESSENGER" == "true" ]]; then
        cat >> "${COMPOSE_FILE}" <<'EOF'
      - ALARM_DASHBOARD_MESSENGER_SERVER_URL=http://alarm-messenger:3000
      - ALARM_DASHBOARD_MESSENGER_API_KEY=${ALARM_MESSENGER_API_SECRET_KEY}
EOF
    fi

    cat >> "${COMPOSE_FILE}" <<'EOF'
      - ALARM_DASHBOARD_DISPLAY_DURATION_MINUTES=${ALARM_MONITOR_DISPLAY_DURATION:-30}
EOF

    # Optional parameters – only written to compose if configured
    [[ -n "${ALARM_MONITOR_GRUPPEN:-}" ]]               && echo "      - ALARM_DASHBOARD_GRUPPEN=\${ALARM_MONITOR_GRUPPEN}" >> "${COMPOSE_FILE}"
    [[ -n "${ALARM_MONITOR_CALENDAR_URLS:-}" ]]         && echo "      - ALARM_DASHBOARD_CALENDAR_URLS=\${ALARM_MONITOR_CALENDAR_URLS}" >> "${COMPOSE_FILE}"
    [[ -n "${ALARM_MONITOR_NTFY_TOPIC_URL:-}" ]]        && echo "      - ALARM_DASHBOARD_NTFY_TOPIC_URL=\${ALARM_MONITOR_NTFY_TOPIC_URL}" >> "${COMPOSE_FILE}"
    [[ -n "${ALARM_MONITOR_NTFY_POLL_INTERVAL:-}" ]]    && echo "      - ALARM_DASHBOARD_NTFY_POLL_INTERVAL=\${ALARM_MONITOR_NTFY_POLL_INTERVAL}" >> "${COMPOSE_FILE}"
    [[ -n "${ALARM_MONITOR_MESSAGES_FILE:-}" ]]         && echo "      - ALARM_DASHBOARD_MESSAGES_FILE=\${ALARM_MONITOR_MESSAGES_FILE}" >> "${COMPOSE_FILE}"
    [[ -n "${ALARM_MONITOR_MESSAGE_MAX_TTL_HOURS:-}" ]] && echo "      - ALARM_DASHBOARD_MESSAGE_MAX_TTL_HOURS=\${ALARM_MONITOR_MESSAGE_MAX_TTL_HOURS}" >> "${COMPOSE_FILE}"
    [[ -n "${ALARM_MONITOR_FIRE_DEPARTMENT_NAME:-}" ]]  && echo "      - ALARM_DASHBOARD_FIRE_DEPARTMENT_NAME=\${ALARM_MONITOR_FIRE_DEPARTMENT_NAME}" >> "${COMPOSE_FILE}"
    [[ -n "${ALARM_MONITOR_DEFAULT_LATITUDE:-}" ]]      && echo "      - ALARM_DASHBOARD_DEFAULT_LATITUDE=\${ALARM_MONITOR_DEFAULT_LATITUDE}" >> "${COMPOSE_FILE}"
    [[ -n "${ALARM_MONITOR_DEFAULT_LONGITUDE:-}" ]]     && echo "      - ALARM_DASHBOARD_DEFAULT_LONGITUDE=\${ALARM_MONITOR_DEFAULT_LONGITUDE}" >> "${COMPOSE_FILE}"
    [[ -n "${ALARM_MONITOR_DEFAULT_LOCATION_NAME:-}" ]] && echo "      - ALARM_DASHBOARD_DEFAULT_LOCATION_NAME=\${ALARM_MONITOR_DEFAULT_LOCATION_NAME}" >> "${COMPOSE_FILE}"

    cat >> "${COMPOSE_FILE}" <<'EOF'
      - TZ=${TZ:-Europe/Berlin}
    volumes:
      - alarm-monitor-data:/app/instance
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8000/health"]
      interval: 30s
      timeout: 5s
      start_period: 30s
      retries: 3
EOF
fi

# alarm-messenger
if [[ "$INSTALL_MESSENGER" == "true" ]]; then
    cat >> "${COMPOSE_FILE}" <<'EOF'

  # Alarm Messenger – Push-Benachrichtigungen für mobile Geräte
  alarm-messenger:
    image: ghcr.io/timux/alarm-messenger:latest
    container_name: alarm-messenger
    restart: unless-stopped
    ports:
      - "${ALARM_MESSENGER_PORT:-3000}:3000"
    networks:
      - alarm-network
    environment:
      - NODE_ENV=production
      - PORT=3000
      - DATABASE_PATH=/app/data/alarm-messenger.db
      - SERVER_URL=${ALARM_MESSENGER_SERVER_URL:-http://localhost:3000}
      - ORGANIZATION_NAME=${ALARM_MESSENGER_ORGANIZATION_NAME:-Feuerwehr Musterstadt}
      - API_SECRET_KEY=${ALARM_MESSENGER_API_SECRET_KEY}
      - JWT_SECRET=${ALARM_MESSENGER_JWT_SECRET}
      - SESSION_SECRET=${ALARM_MESSENGER_SESSION_SECRET}
      - CORS_ORIGINS=${ALARM_MESSENGER_CORS_ORIGINS:-*}
      - ENABLE_FCM=${ALARM_MESSENGER_ENABLE_FCM:-false}
      - FCM_SERVICE_ACCOUNT_PATH=${ALARM_MESSENGER_FCM_SERVICE_ACCOUNT_PATH:-}
      - ENABLE_APNS=${ALARM_MESSENGER_ENABLE_APNS:-false}
      - APNS_KEY_PATH=${ALARM_MESSENGER_APNS_KEY_PATH:-}
      - APNS_KEY_ID=${ALARM_MESSENGER_APNS_KEY_ID:-}
      - APNS_TEAM_ID=${ALARM_MESSENGER_APNS_TEAM_ID:-}
      - APNS_TOPIC=${ALARM_MESSENGER_APNS_TOPIC:-}
      - APNS_PRODUCTION=${ALARM_MESSENGER_APNS_PRODUCTION:-false}
      - TZ=${TZ:-Europe/Berlin}
    volumes:
      - alarm-messenger-data:/app/data
    healthcheck:
      test: ["CMD", "node", "-e", "require('http').get('http://localhost:3000/health', (r) => {process.exit(r.statusCode === 200 ? 0 : 1)})"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 40s
EOF
fi

# alarm-mail
if [[ "$INSTALL_MAIL" == "true" ]]; then
    cat >> "${COMPOSE_FILE}" <<'EOF'

  # Alarm Mail – Liest IMAP und leitet Alarme weiter
  alarm-mail:
    image: ghcr.io/timux/alarm-mail:latest
    container_name: alarm-mail
    restart: unless-stopped
    networks:
      - alarm-network
    environment:
      - ALARM_MAIL_IMAP_HOST=${ALARM_MAIL_IMAP_HOST}
      - ALARM_MAIL_IMAP_PORT=${ALARM_MAIL_IMAP_PORT:-993}
      - ALARM_MAIL_IMAP_USE_SSL=${ALARM_MAIL_IMAP_USE_SSL:-true}
      - ALARM_MAIL_IMAP_USERNAME=${ALARM_MAIL_IMAP_USERNAME}
      - ALARM_MAIL_IMAP_PASSWORD=${ALARM_MAIL_IMAP_PASSWORD}
      - ALARM_MAIL_IMAP_MAILBOX=${ALARM_MAIL_IMAP_MAILBOX:-INBOX}
      - ALARM_MAIL_IMAP_SEARCH=${ALARM_MAIL_IMAP_SEARCH:-UNSEEN}
      - ALARM_MAIL_POLL_INTERVAL=${ALARM_MAIL_POLL_INTERVAL:-60}
      - TZ=${TZ:-Europe/Berlin}
EOF

    # Multitarget-Umgebungsvariablen
    for ((_i=1; _i<=ALARM_MAIL_TARGET_COUNT; _i++)); do
        _tv="ALARM_MAIL_TARGET_${_i}_TYPE"
        _uv="ALARM_MAIL_TARGET_${_i}_URL"
        _akv="ALARM_MAIL_TARGET_${_i}_API_KEY"
        _gv="ALARM_MAIL_TARGET_${_i}_GROUPS"
        cat >> "${COMPOSE_FILE}" <<EOF
      - ALARM_MAIL_TARGET_${_i}_TYPE=\${ALARM_MAIL_TARGET_${_i}_TYPE}
      - ALARM_MAIL_TARGET_${_i}_URL=\${ALARM_MAIL_TARGET_${_i}_URL}
      - ALARM_MAIL_TARGET_${_i}_API_KEY=\${ALARM_MAIL_TARGET_${_i}_API_KEY}
EOF
        [[ -n "${!_gv:-}" ]] && echo "      - ALARM_MAIL_TARGET_${_i}_GROUPS=\${ALARM_MAIL_TARGET_${_i}_GROUPS}" >> "${COMPOSE_FILE}"
    done

    cat >> "${COMPOSE_FILE}" <<'EOF'
    healthcheck:
      test: ["CMD", "pgrep", "-f", "alarm-mail"]
      interval: 60s
      timeout: 10s
      start_period: 30s
      retries: 3
EOF

    _has_depends=false
    [[ "$INSTALL_MONITOR"   == "true" ]] && _has_depends=true
    [[ "$INSTALL_MESSENGER" == "true" ]] && _has_depends=true
    if [[ "$_has_depends" == "true" ]]; then
        echo "    depends_on:" >> "${COMPOSE_FILE}"
        if [[ "$INSTALL_MONITOR" == "true" ]]; then
            cat >> "${COMPOSE_FILE}" <<'EOF'
      alarm-monitor:
        condition: service_healthy
EOF
        fi
        if [[ "$INSTALL_MESSENGER" == "true" ]]; then
            cat >> "${COMPOSE_FILE}" <<'EOF'
      alarm-messenger:
        condition: service_healthy
EOF
        fi
    fi
fi

# Caddy
if [[ "$INSTALL_CADDY" == "true" ]]; then
    mkdir -p "${INSTALL_DIR}/caddy"

    cat >> "${COMPOSE_FILE}" <<'EOF'

  # Caddy – Reverse Proxy mit automatischem HTTPS
  caddy:
    image: caddy:2-alpine
    container_name: alarm-caddy
    restart: unless-stopped
    ports:
      - "80:80"
      - "443:443"
      - "443:443/udp"
    networks:
      - alarm-network
    volumes:
      - ./caddy/Caddyfile:/etc/caddy/Caddyfile:ro
      - caddy-data:/data
      - caddy-config:/config
    environment:
      - ALARM_MONITOR_DOMAIN=${ALARM_MONITOR_DOMAIN:-monitor.example.com}
      - ALARM_MESSENGER_DOMAIN=${ALARM_MESSENGER_DOMAIN:-messenger.example.com}
    depends_on:
EOF
    [[ "$INSTALL_MONITOR"   == "true" ]] && echo "      - alarm-monitor"   >> "${COMPOSE_FILE}"
    [[ "$INSTALL_MESSENGER" == "true" ]] && echo "      - alarm-messenger" >> "${COMPOSE_FILE}"
    cat >> "${COMPOSE_FILE}" <<'EOF'
    profiles:
      - with-caddy
EOF

    # Caddyfile generieren
    CADDYFILE="${INSTALL_DIR}/caddy/Caddyfile"
    cat > "${CADDYFILE}" <<'CADDY_EOF'
# Caddy Konfiguration – generiert durch install.sh
CADDY_EOF

    if [[ "$INSTALL_MONITOR" == "true" ]]; then
        cat >> "${CADDYFILE}" <<'CADDY_EOF'

{$ALARM_MONITOR_DOMAIN:monitor.example.com} {
    tls {}
    reverse_proxy alarm-monitor:8000 {
        header_up X-Real-IP {remote_host}
        header_up X-Forwarded-For {remote_host}
        header_up X-Forwarded-Proto {scheme}
    }
    log {
        output file /var/log/caddy/monitor-access.log
        format json
    }
}
CADDY_EOF
    fi

    if [[ "$INSTALL_MESSENGER" == "true" ]]; then
        cat >> "${CADDYFILE}" <<'CADDY_EOF'

{$ALARM_MESSENGER_DOMAIN:messenger.example.com} {
    tls {}
    reverse_proxy alarm-messenger:3000 {
        header_up Connection {>Connection}
        header_up Upgrade {>Upgrade}
        header_up X-Real-IP {remote_host}
        header_up X-Forwarded-For {remote_host}
        header_up X-Forwarded-Proto {scheme}
        transport http {
            read_timeout 1h
            write_timeout 1h
        }
    }
    log {
        output file /var/log/caddy/messenger-access.log
        format json
    }
}
CADDY_EOF
    fi

    ok "Caddyfile erstellt: ${CADDYFILE}"
fi

ok "docker-compose.yml erstellt: ${COMPOSE_FILE}"

# ---------------------------------------------------------------------------
# Schritt F: Hilfsskripte generieren
# ---------------------------------------------------------------------------
step "Hilfsskripte generieren"

# update.sh
cat > "${INSTALL_DIR}/update.sh" <<'EOF'
#!/usr/bin/env bash
# update.sh – Alarm-System aktualisieren
set -euo pipefail
cd "$(dirname "$0")"
echo "🔄  Docker Images werden aktualisiert …"
docker compose pull
docker compose up -d
echo "🧹  Veraltete Images aufräumen …"
docker image prune -f
echo "✔  Update abgeschlossen."
docker compose ps
EOF
chmod +x "${INSTALL_DIR}/update.sh"

# backup.sh
cat > "${INSTALL_DIR}/backup.sh" <<'EOF'
#!/usr/bin/env bash
# backup.sh – Alarm-System Daten sichern
set -euo pipefail
cd "$(dirname "$0")"
BACKUP_DIR="$(dirname "$0")/backup"
mkdir -p "${BACKUP_DIR}"
DATE="$(date -u +%Y%m%d_%H%M%S_UTC)"

backup_volume() {
    local VOL="$1"
    local FILE="${BACKUP_DIR}/${VOL}-${DATE}.tar.gz"
    docker run --rm \
        -v "${VOL}:/data" \
        -v "${BACKUP_DIR}:/backup" \
        alpine tar czf "/backup/${VOL}-${DATE}.tar.gz" /data
    echo "  ✔  ${FILE}"
}

echo "📦  Backup wird erstellt …"
docker volume ls --format '{{.Name}}' | grep '^alarm-' | while read -r vol; do
    backup_volume "$vol"
done

cp .env "${BACKUP_DIR}/.env.backup.${DATE}" 2>/dev/null && echo "  ✔  .env gesichert" || true

# Backups älter als 30 Tage löschen
find "${BACKUP_DIR}" -name "*.tar.gz" -mtime +30 -delete 2>/dev/null || true

echo "✔  Backup abgeschlossen: ${BACKUP_DIR}"
EOF
chmod +x "${INSTALL_DIR}/backup.sh"

# status.sh
cat > "${INSTALL_DIR}/status.sh" <<'EOF'
#!/usr/bin/env bash
# status.sh – Systemstatus anzeigen
set -euo pipefail
cd "$(dirname "$0")"
echo ""
echo "─── Container-Status ──────────────────────────────────────────"
docker compose ps
echo ""
echo "─── Resource-Verbrauch ────────────────────────────────────────"
docker stats --no-stream --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}"
echo ""
EOF
chmod +x "${INSTALL_DIR}/status.sh"

# logs.sh
cat > "${INSTALL_DIR}/logs.sh" <<'EOF'
#!/usr/bin/env bash
# logs.sh – Logs aller Dienste anzeigen
cd "$(dirname "$0")"
docker compose logs --tail=100 -f "$@"
EOF
chmod +x "${INSTALL_DIR}/logs.sh"

# os-update.sh
cat > "${INSTALL_DIR}/os-update.sh" <<'EOF'
#!/usr/bin/env bash
# os-update.sh – Betriebssystem-Pakete aktualisieren
# Wird automatisch wöchentlich via Cron ausgeführt (Sonntag 02:30 Uhr).
set -euo pipefail
LOG="/var/log/alarm-system-os-update.log"
log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG"; }

log "OS-Update gestartet"

if command -v apt-get >/dev/null 2>&1; then
    apt-get update -qq
    DEBIAN_FRONTEND=noninteractive apt-get dist-upgrade -y -q
    apt-get autoremove -y -q
    apt-get clean -q
elif command -v dnf >/dev/null 2>&1; then
    dnf upgrade -y -q
    dnf autoremove -y -q
elif command -v yum >/dev/null 2>&1; then
    yum upgrade -y -q
elif command -v pacman >/dev/null 2>&1; then
    pacman -Syu --noconfirm --quiet
elif command -v zypper >/dev/null 2>&1; then
    zypper refresh -q && zypper update -y -q
elif command -v apk >/dev/null 2>&1; then
    apk update -q && apk upgrade -q
else
    log "FEHLER: Kein unterstützter Paketmanager gefunden."
    exit 1
fi

log "OS-Update abgeschlossen"

# Docker-Engine explizit upgraden
# Deckt sowohl get.docker.com (docker-ce) als auch Distro-Pakete (docker.io/docker) ab.
# Für pacman/zypper/apk ist Docker durch die allgemeine Systemaktualisierung oben bereits abgedeckt.
log "Docker-Engine upgraden"
# --only-upgrade (apt): aktualisiert nur bereits installierte Pakete – keine Neu-Installationen.
# Da docker-ce (get.docker.com) und docker.io (Distro) sich gegenseitig ausschließen, wird
# jeweils nur das tatsächlich installierte Paket aktualisiert; das andere wird ignoriert.
# || true stellt sicher, dass der Cron-Job nicht abbricht, falls kein Docker-Paket gefunden wird.
if command -v apt-get >/dev/null 2>&1; then
    DEBIAN_FRONTEND=noninteractive apt-get install --only-upgrade -y \
        docker-ce docker-ce-cli docker-ce-rootless-extras containerd.io \
        docker-compose-plugin docker.io 2>/dev/null || true
elif command -v dnf >/dev/null 2>&1; then
    dnf upgrade -y docker-ce docker-ce-cli containerd.io docker-compose-plugin \
        docker 2>/dev/null || true
elif command -v yum >/dev/null 2>&1; then
    yum upgrade -y docker-ce docker-ce-cli containerd.io docker-compose-plugin \
        docker 2>/dev/null || true
fi
log "Docker-Engine Upgrade abgeschlossen"
EOF
chmod +x "${INSTALL_DIR}/os-update.sh"

ok "Hilfsskripte erstellt: update.sh, os-update.sh, backup.sh, status.sh, logs.sh"

# ---------------------------------------------------------------------------
# Schritt G: Kiosk-Modus konfigurieren
# ---------------------------------------------------------------------------
if [[ "$INSTALL_KIOSK" == "true" ]]; then
    step "Kiosk-Modus konfigurieren"

    # Notwendige Pakete für X / Kiosk installieren
    case "$PKG_MGR" in
        apt)
            eval "${PKG_INSTALL} xorg xinit openbox unclutter xdotool"
            # Emoji- und Unicode-Schriftarten für korrekte Darstellung von Wetter-Symbolen
            eval "${PKG_INSTALL} fonts-noto-color-emoji fonts-noto-core" 2>/dev/null || \
                eval "${PKG_INSTALL} fonts-noto-color-emoji" 2>/dev/null || true
            # Chromium: Name unterscheidet sich je nach Distro/Arch
            if eval "${PKG_INSTALL} chromium-browser" 2>/dev/null; then
                KIOSK_BIN="chromium-browser"
            elif eval "${PKG_INSTALL} chromium" 2>/dev/null; then
                KIOSK_BIN="chromium"
            else
                warn "Kein Chromium-Paket gefunden – bitte manuell installieren."
                KIOSK_BIN="chromium"
            fi
            ;;
        dnf|yum)
            eval "${PKG_INSTALL} xorg-x11-server-Xorg openbox unclutter chromium"
            # Emoji- und Unicode-Schriftarten für korrekte Darstellung von Wetter-Symbolen
            eval "${PKG_INSTALL} google-noto-emoji-color-fonts google-noto-emoji-fonts" 2>/dev/null || \
                eval "${PKG_INSTALL} google-noto-emoji-color-fonts" 2>/dev/null || true
            KIOSK_BIN="chromium-browser"
            command -v chromium >/dev/null 2>&1 && KIOSK_BIN="chromium"
            ;;
        pacman)
            eval "${PKG_INSTALL} xorg-server openbox unclutter chromium"
            # Emoji- und Unicode-Schriftarten für korrekte Darstellung von Wetter-Symbolen
            eval "${PKG_INSTALL} noto-fonts-emoji noto-fonts" 2>/dev/null || true
            KIOSK_BIN="chromium"
            ;;
        zypper)
            eval "${PKG_INSTALL} xorg-x11-server openbox unclutter chromium"
            # Emoji- und Unicode-Schriftarten für korrekte Darstellung von Wetter-Symbolen
            eval "${PKG_INSTALL} google-noto-coloremoji-fonts google-noto-fonts" 2>/dev/null || \
                eval "${PKG_INSTALL} google-noto-coloremoji-fonts" 2>/dev/null || true
            KIOSK_BIN="chromium"
            ;;
        apk)
            eval "${PKG_INSTALL} xorg-server openbox unclutter chromium"
            # Emoji- und Unicode-Schriftarten für korrekte Darstellung von Wetter-Symbolen
            eval "${PKG_INSTALL} font-noto-emoji font-noto" 2>/dev/null || \
                eval "${PKG_INSTALL} font-noto-emoji" 2>/dev/null || true
            KIOSK_BIN="chromium-browser"
            ;;
    esac

    # Schriftarten-Cache aktualisieren (damit neue Fonts sofort erkannt werden)
    command -v fc-cache >/dev/null 2>&1 && fc-cache -f 2>/dev/null || true

    # Kiosk-Startskript
    KIOSK_SCRIPT="${INSTALL_DIR}/kiosk.sh"
    cat > "${KIOSK_SCRIPT}" <<EOF
#!/usr/bin/env bash
# kiosk.sh – Kiosk-Browser starten
# Wartet bis alarm-monitor erreichbar ist, dann startet der Kiosk-Browser.

KIOSK_URL="${KIOSK_URL}"
BROWSER="${KIOSK_BIN}"
MAX_WAIT=120   # Sekunden
WAITED=0

echo "Warte auf \${KIOSK_URL} …"
until curl -fs "\${KIOSK_URL}/health" >/dev/null 2>&1 || [ \$WAITED -ge \$MAX_WAIT ]; do
    sleep 3
    WAITED=\$((WAITED+3))
done

EOF

    cat >> "${KIOSK_SCRIPT}" <<EOF
# Chromium-Profil vorbereiten (verhindert "abgestürzt"-Dialog)
PROFILE_DIR="\${XDG_RUNTIME_DIR:-\${HOME}/.cache}/kiosk-profile"
mkdir -p "\${PROFILE_DIR}/Default"
chmod 700 "\${PROFILE_DIR}"
cat > "\${PROFILE_DIR}/Default/Preferences" <<'PREF' 2>/dev/null || true
{
  "profile": {"exit_type": "Normal", "exited_cleanly": true},
  "translate": {"enabled": false},
  "translate_blocked_languages": ["de"]
}
PREF

# Cache beim Start leeren (stellt sicher, dass aktuelle App-Versionen geladen werden)
clear_browser_cache() {
    rm -rf "\${PROFILE_DIR}/Default/Cache" \
           "\${PROFILE_DIR}/Default/Code Cache" \
           "\${PROFILE_DIR}/Default/Service Worker" \
           "\${PROFILE_DIR}/Default/GPUCache" \
           2>/dev/null || true
}
clear_browser_cache

# Cache auch beim Beenden leeren
# Hinweis: kein 'exec', damit der EXIT-Trap nach Browser-Ende greift
trap 'clear_browser_cache' EXIT

\${BROWSER} \\
    --kiosk \\
    --noerrdialogs \\
    --disable-infobars \\
    --disable-translate \\
    --disable-features=TranslateUI \\
    --lang=de \\
    --disable-session-crashed-bubble \\
    --disable-restore-session-state \\
    --disable-component-update \\
    --autoplay-policy=no-user-gesture-required \\
    --disable-hang-monitor \\
    --disable-background-timer-throttling \\
    --disable-renderer-backgrounding \\
    --inhibit-sleep \\
    --user-data-dir="\${PROFILE_DIR}" \\
    "\${KIOSK_URL}"
EOF
    chmod +x "${KIOSK_SCRIPT}"

    # Openbox-Autostart
    mkdir -p "${HOME}/.config/openbox"
    cat > "${HOME}/.config/openbox/autostart" <<EOF
# Sprache und Tastaturlayout (Deutsch)
export LANG=de_DE.UTF-8
setxkbmap de &

# Bildschirmschoner & DPMS deaktivieren
xset s off &
xset s noblank &
xset -dpms &

# Mauszeiger ausblenden
unclutter -idle 0.1 -root &

# Kiosk-Browser starten
${KIOSK_SCRIPT} &
EOF

    # Automatischen X-Start beim Login (tty1) konfigurieren
    BASH_PROFILE="${HOME}/.bash_profile"
    touch "${BASH_PROFILE}"
    if ! grep -q "startx" "${BASH_PROFILE}" 2>/dev/null; then
        cat >> "${BASH_PROFILE}" <<'PROFILE_EOF'

# X-Server automatisch auf tty1 starten
if [ -z "$DISPLAY" ] && [ "$(tty)" = "/dev/tty1" ]; then
    exec startx -- -nocursor
fi
PROFILE_EOF
    fi

    # Autologin via systemd (getty)
    AUTOLOGIN_DIR="/etc/systemd/system/getty@tty1.service.d"
    sudo mkdir -p "${AUTOLOGIN_DIR}"
    sudo tee "${AUTOLOGIN_DIR}/autologin.conf" > /dev/null <<EOF
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin ${SCRIPT_USER} --noclear %I \$TERM
EOF

    sudo systemctl daemon-reload
    sudo systemctl enable "getty@tty1.service" 2>/dev/null || true

    # -----------------------------------------------------------------------
    # Konsolen-Blanking deaktivieren (Raspberry Pi & systemd-getty)
    # Verhindert, dass der Framebuffer/Konsole vor X-Start in den Standby geht.
    # -----------------------------------------------------------------------
    for CMDLINE_TXT in /boot/firmware/cmdline.txt /boot/cmdline.txt; do
        if [[ -f "${CMDLINE_TXT}" ]]; then
            if ! grep -q "consoleblank=0" "${CMDLINE_TXT}" 2>/dev/null; then
                sudo sed -i 's/$/ consoleblank=0/' "${CMDLINE_TXT}"
                ok "consoleblank=0 zu ${CMDLINE_TXT} hinzugefügt (verhindert Konsolen-Standby)."
            else
                info "consoleblank=0 ist bereits in ${CMDLINE_TXT} gesetzt."
            fi
            break
        fi
    done

    # -----------------------------------------------------------------------
    # X11 Xorg-Konfiguration: DPMS & Screensaver dauerhaft deaktivieren
    # Diese Einstellung gilt auf X-Server-Ebene und überschreibt xset-Aufrufe.
    # -----------------------------------------------------------------------
    sudo mkdir -p /etc/X11/xorg.conf.d
    sudo tee /etc/X11/xorg.conf.d/10-noblank.conf > /dev/null <<'XORGEOF'
# Bildschirmschoner und DPMS (Display Power Management) dauerhaft deaktivieren.
# Verhindert, dass der Kiosk-Display in den Standby oder Screensaver-Modus wechselt.
Section "ServerFlags"
    Option "BlankTime"    "0"
    Option "StandbyTime"  "0"
    Option "SuspendTime"  "0"
    Option "OffTime"      "0"
EndSection

Section "Monitor"
    Identifier "Monitor0"
    Option "DPMS" "false"
EndSection
XORGEOF
    ok "/etc/X11/xorg.conf.d/10-noblank.conf erstellt (DPMS dauerhaft deaktiviert)."

    # -----------------------------------------------------------------------
    # watchdog.sh – überwacht Dienste-Gesundheit und Kiosk-Prozess
    # -----------------------------------------------------------------------
    WATCHDOG_SCRIPT="${INSTALL_DIR}/watchdog.sh"
    cat > "${WATCHDOG_SCRIPT}" <<EOF
#!/usr/bin/env bash
# watchdog.sh – Überwacht Alarm-System-Dienste und den Kiosk-Browser

MONITOR_URL="http://localhost:${ALARM_MONITOR_PORT:-8000}"
CHECK_INTERVAL=30
LOG_FILE="/var/log/alarm-system-watchdog.log"

log() { echo "[\$(date '+%Y-%m-%d %H:%M:%S')] \$*" >> "\$LOG_FILE"; }

log "Watchdog gestartet"

while true; do
    # Docker-Dienste prüfen
    if ! curl -sf --max-time 5 "\${MONITOR_URL}/health" > /dev/null 2>&1; then
        log "WARNUNG: alarm-monitor nicht erreichbar – starte Docker-Dienste neu"
        cd "${INSTALL_DIR}" && docker compose restart >> "\$LOG_FILE" 2>&1
    fi

    # X-Display prüfen (nur wenn kiosk läuft)
    if command -v xdpyinfo >/dev/null 2>&1; then
        if ! DISPLAY=:0 xdpyinfo > /dev/null 2>&1; then
            log "WARNUNG: X-Display nicht aktiv – starte kiosk-watchdog-check"
            systemctl --user restart kiosk.service 2>/dev/null || true
        else
            # DPMS und Bildschirmschoner periodisch deaktivieren (verhindert Standby/Blanking)
            DISPLAY=:0 XAUTHORITY="${HOME}/.Xauthority" xset s off 2>/dev/null || true
            DISPLAY=:0 XAUTHORITY="${HOME}/.Xauthority" xset s noblank 2>/dev/null || true
            DISPLAY=:0 XAUTHORITY="${HOME}/.Xauthority" xset -dpms 2>/dev/null || true
        fi
    fi

    sleep "\$CHECK_INTERVAL"
done
EOF
    chmod +x "${WATCHDOG_SCRIPT}"
    ok "watchdog.sh erstellt."

    # -----------------------------------------------------------------------
    # kiosk.service – systemd-Unit für den Kiosk-Browser
    # -----------------------------------------------------------------------
    sudo tee /etc/systemd/system/kiosk.service > /dev/null <<EOF
[Unit]
Description=Alarm-System Kiosk Browser
After=network-online.target alarm-system.service
Wants=network-online.target

[Service]
Type=simple
User=${SCRIPT_USER}
Environment=DISPLAY=:0
Environment=XAUTHORITY=${HOME}/.Xauthority
WorkingDirectory=${INSTALL_DIR}
ExecStartPre=/bin/sleep 5
ExecStart=${KIOSK_SCRIPT}
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF
    ok "kiosk.service erstellt."

    # -----------------------------------------------------------------------
    # kiosk-watchdog.service
    # -----------------------------------------------------------------------
    sudo tee /etc/systemd/system/kiosk-watchdog.service > /dev/null <<EOF
[Unit]
Description=Alarm-System Kiosk Watchdog
After=kiosk.service alarm-system.service
Requires=alarm-system.service

[Service]
Type=simple
User=${SCRIPT_USER}
WorkingDirectory=${INSTALL_DIR}
ExecStart=${WATCHDOG_SCRIPT}
Restart=always
RestartSec=15
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF
    ok "kiosk-watchdog.service erstellt."

    # -----------------------------------------------------------------------
    # alarm-sound.sh + alarm-sound.service (nur wenn alarm-monitor installiert)
    # -----------------------------------------------------------------------
    if [[ "$INSTALL_MONITOR" == "true" ]]; then
        SOUND_DIR="${INSTALL_DIR}/sounds"
        SOUND_FILE="${SOUND_DIR}/alarm.wav"
        ALARM_SOUND_SCRIPT="${INSTALL_DIR}/alarm-sound.sh"
        sudo mkdir -p "${SOUND_DIR}"
        sudo chown "${SCRIPT_USER}:${SCRIPT_USER}" "${SOUND_DIR}"

        cat > "${ALARM_SOUND_SCRIPT}" <<EOF
#!/usr/bin/env bash
# alarm-sound.sh – Überwacht neue Alarme und spielt Sound ab

DASHBOARD_URL="http://localhost:${ALARM_MONITOR_PORT:-8000}"
SOUND_FILE="${SOUND_FILE}"
STATE_FILE="/tmp/last_alarm_id"
CHECK_INTERVAL=10
LOG_FILE="/var/log/alarm-sound.log"

log() { echo "[\$(date '+%Y-%m-%d %H:%M:%S')] \$*" >> "\$LOG_FILE"; }

log "Alarm-Sound-Service gestartet"

LAST_ID=\$(curl -sf "\${DASHBOARD_URL}/api/alarms/latest" 2>/dev/null | \\
          python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('id',0))" 2>/dev/null || echo "0")
echo "\$LAST_ID" > "\$STATE_FILE"
log "Initialer letzter Alarm-ID: \$LAST_ID"

while true; do
    sleep "\$CHECK_INTERVAL"
    LATEST=\$(curl -sf --max-time 5 "\${DASHBOARD_URL}/api/alarms/latest" 2>/dev/null)
    [ -z "\$LATEST" ] && continue

    CURRENT_ID=\$(echo "\$LATEST" | \\
        python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('id',0))" 2>/dev/null || echo "0")
    SAVED_ID=\$(cat "\$STATE_FILE" 2>/dev/null || echo "0")

    if [ "\$CURRENT_ID" != "\$SAVED_ID" ] && [ "\$CURRENT_ID" -gt "\$SAVED_ID" ] 2>/dev/null; then
        log "Neuer Alarm erkannt (ID: \$CURRENT_ID) – spiele Sound ab"
        echo "\$CURRENT_ID" > "\$STATE_FILE"
        for i in 1 2 3; do
            aplay -q "\$SOUND_FILE" 2>/dev/null || sox "\$SOUND_FILE" -d 2>/dev/null || true
            sleep 0.5
        done
    fi
done
EOF
        chmod +x "${ALARM_SOUND_SCRIPT}"
        ok "alarm-sound.sh erstellt."

        # Test-Alarmton generieren
        if [[ ! -f "${SOUND_FILE}" ]]; then
            if command -v sox >/dev/null 2>&1; then
                sox -n "${SOUND_FILE}" \
                    synth 1 sine 880 synth 0.3 sine 1200 gain -3 2>/dev/null \
                    && ok "Test-Alarm-Ton erstellt (sox): ${SOUND_FILE}" \
                    || warn "Test-Ton konnte nicht generiert werden."
            elif command -v ffmpeg >/dev/null 2>&1; then
                ffmpeg -y -f lavfi \
                    -i "sine=frequency=880:duration=1" \
                    -ar 44100 -ac 1 "${SOUND_FILE}" \
                    >/dev/null 2>&1 \
                    && ok "Test-Alarm-Ton erstellt (ffmpeg): ${SOUND_FILE}" \
                    || warn "ffmpeg: Test-Ton konnte nicht generiert werden."
            elif command -v python3 >/dev/null 2>&1; then
                python3 - "${SOUND_FILE}" <<'PYEOF'
import sys, wave, math, array, struct
out = sys.argv[1]
rate = 44100
freqs = [(880, 0.7), (1200, 0.3)]   # (Hz, Sekunden)
samples = array.array('h')
for freq, dur in freqs:
    n = int(rate * dur)
    samples.extend(
        int(32767 * math.sin(2 * math.pi * freq * t / rate)) for t in range(n)
    )
with wave.open(out, 'w') as wf:
    wf.setnchannels(1)
    wf.setsampwidth(2)
    wf.setframerate(rate)
    wf.writeframes(samples.tobytes())
PYEOF
                # shellcheck disable=SC2181
                if [[ $? -eq 0 ]]; then
                    ok "Test-Alarm-Ton erstellt (python3): ${SOUND_FILE}"
                else
                    warn "python3: Test-Ton konnte nicht generiert werden."
                fi
            else
                warn "Kein geeignetes Tool (sox, ffmpeg, python3) gefunden – alarm.wav bitte manuell unter ${SOUND_FILE} ablegen."
            fi
        else
            info "alarm.wav bereits vorhanden – übersprungen."
        fi

        sudo tee /etc/systemd/system/alarm-sound.service > /dev/null <<EOF
[Unit]
Description=Alarm-System Sound-Alert
After=alarm-system.service network-online.target
Wants=network-online.target

[Service]
Type=simple
User=${SCRIPT_USER}
WorkingDirectory=${INSTALL_DIR}
ExecStart=${ALARM_SOUND_SCRIPT}
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF
        ok "alarm-sound.service erstellt."
    fi

    # -----------------------------------------------------------------------
    # Alle neuen Services aktivieren
    # -----------------------------------------------------------------------
    sudo systemctl daemon-reload
    sudo systemctl enable kiosk.service kiosk-watchdog.service 2>/dev/null || true
    [[ "$INSTALL_MONITOR" == "true" ]] && sudo systemctl enable alarm-sound.service 2>/dev/null || true
    ok "Kiosk-Services aktiviert (starten automatisch nach Neustart)."

    # -----------------------------------------------------------------------
    # Wöchentlicher Neustart (Sonntag 03:00 Uhr) – hält den Kiosk frisch
    # -----------------------------------------------------------------------
    # Alten täglichen Eintrag entfernen, falls vorhanden
    sudo crontab -l 2>/dev/null | grep -vF "0 3 * * * /sbin/reboot" | sudo crontab - 2>/dev/null || true
    if ! sudo crontab -l 2>/dev/null | grep -qF "0 3 * * 0 /sbin/reboot"; then
        (sudo crontab -l 2>/dev/null; echo "0 3 * * 0 /sbin/reboot") | sudo crontab -
        ok "Cron-Job für wöchentlichen Neustart (Sonntag 03:00 Uhr) eingerichtet."
    else
        info "Wöchentlicher Reboot-Cron bereits vorhanden."
    fi

    ok "Kiosk-Modus konfiguriert."
    info "Beim nächsten Neustart startet ${KIOSK_BIN} automatisch → ${KIOSK_URL}"
fi

# ---------------------------------------------------------------------------
# Schritt G2: alarm-system.service – Docker Compose automatisch starten
# ---------------------------------------------------------------------------
step "Systemd-Service alarm-system.service einrichten"

sudo tee /etc/systemd/system/alarm-system.service > /dev/null <<EOF
[Unit]
Description=Alarm-System Docker Compose
Documentation=https://github.com/TimUx/alarm-system
After=docker.service network-online.target
Requires=docker.service
Wants=network-online.target

[Service]
Type=oneshot
User=${SCRIPT_USER}
WorkingDirectory=${INSTALL_DIR}
ExecStart=/usr/bin/docker compose up -d
ExecStop=/usr/bin/docker compose down
RemainAfterExit=yes
Restart=on-failure
RestartSec=30
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable alarm-system.service 2>/dev/null || true
ok "alarm-system.service aktiviert (startet automatisch nach Neustart)."

# ---------------------------------------------------------------------------
# Schritt G3: Raspberry Pi Optimierungen
# ---------------------------------------------------------------------------
if [[ "$IS_RPI" == "true" ]]; then
    step "Raspberry Pi Optimierungen"

    # Plymouth Splashscreen (Debian/Raspberry Pi OS)
    if [[ "$PKG_MGR" == "apt" ]]; then
        eval "${PKG_INSTALL} plymouth plymouth-themes" 2>/dev/null || true
        sudo mkdir -p /usr/share/plymouth/themes/alarm-system

        sudo tee /usr/share/plymouth/themes/alarm-system/alarm-system.plymouth > /dev/null <<'PLYM'
[Plymouth Theme]
Name=Alarm-System
Description=Alarm-System Ladebildschirm
ModuleName=script

[script]
ImageDir=/usr/share/plymouth/themes/alarm-system
ScriptFile=/usr/share/plymouth/themes/alarm-system/alarm-system.script
PLYM

        sudo tee /usr/share/plymouth/themes/alarm-system/alarm-system.script > /dev/null <<'PLYMSCRIPT'
Window.SetBackgroundTopColor(0.8, 0.1, 0.1);
Window.SetBackgroundBottomColor(0.5, 0.0, 0.0);

title_image = Image.Text("Alarm-System lädt...", 1.0, 1.0, 1.0);
title_sprite = Sprite();
title_sprite.SetImage(title_image);
title_sprite.SetPosition(Window.GetWidth()/2 - title_image.GetWidth()/2, Window.GetHeight()/2 - 30, 10000);

subtitle_image = Image.Text("Bitte warten...", 0.8, 0.8, 0.8);
subtitle_sprite = Sprite();
subtitle_sprite.SetImage(subtitle_image);
subtitle_sprite.SetPosition(Window.GetWidth()/2 - subtitle_image.GetWidth()/2, Window.GetHeight()/2 + 10, 10000);
PLYMSCRIPT

        sudo update-alternatives --install \
            /usr/share/plymouth/themes/default.plymouth \
            default.plymouth \
            /usr/share/plymouth/themes/alarm-system/alarm-system.plymouth 100 2>/dev/null || true
        sudo update-alternatives --set \
            default.plymouth \
            /usr/share/plymouth/themes/alarm-system/alarm-system.plymouth 2>/dev/null || true
        sudo update-initramfs -u 2>/dev/null || warn "update-initramfs fehlgeschlagen – Plymouth ohne Wirkung bis zum nächsten Kernel-Update."
        ok "Plymouth-Splashscreen eingerichtet."
    fi

    # Stille Boot-Parameter (/boot/firmware/cmdline.txt oder /boot/cmdline.txt)
    for CMDLINE_FILE in /boot/firmware/cmdline.txt /boot/cmdline.txt; do
        if [[ -f "$CMDLINE_FILE" ]]; then
            if ! grep -q "quiet splash" "$CMDLINE_FILE"; then
                # cmdline.txt is a single line; use echo + truncation to avoid sed '$' edge-cases
                CMDLINE_CURRENT="$(cat "$CMDLINE_FILE")"
                echo "${CMDLINE_CURRENT% } quiet splash plymouth.ignore-serial-consoles logo.nologo vt.global_cursor_default=0" \
                    | sudo tee "$CMDLINE_FILE" > /dev/null
                ok "Stille Boot-Parameter gesetzt: ${CMDLINE_FILE}"
            else
                info "Boot-Parameter bereits vorhanden: ${CMDLINE_FILE}"
            fi
            break
        fi
    done

    # config.txt Optimierungen
    for CONFIG_FILE in /boot/firmware/config.txt /boot/config.txt; do
        if [[ -f "$CONFIG_FILE" ]]; then
            # GPU-Speicher auf 128 MB (ausreichend für Kiosk/Browser)
            if grep -q "^gpu_mem=" "$CONFIG_FILE"; then
                sudo sed -i 's/^gpu_mem=.*/gpu_mem=128/' "$CONFIG_FILE"
            else
                printf '\n# GPU-Speicher (Kiosk-Modus)\ngpu_mem=128\n' | sudo tee -a "$CONFIG_FILE" > /dev/null
            fi
            # HDMI erzwingen (kein Blank-Screen wenn Monitor später angeschlossen wird)
            if ! grep -q "hdmi_force_hotplug" "$CONFIG_FILE"; then
                printf '\n# HDMI erzwingen\nhdmi_force_hotplug=1\nhdmi_group=1\nhdmi_mode=16\n' | sudo tee -a "$CONFIG_FILE" > /dev/null
            fi
            # Bluetooth deaktivieren (reduziert Ressourcen/Störquellen)
            if ! grep -q "disable-bt" "$CONFIG_FILE"; then
                echo "dtoverlay=disable-bt" | sudo tee -a "$CONFIG_FILE" > /dev/null
            fi
            ok "Raspberry Pi config.txt optimiert: ${CONFIG_FILE}"
            break
        fi
    done

    # Unnötige Dienste deaktivieren
    # Hinweis: apt-daily-Timer werden deaktiviert, damit unerwünschte Updates den Kiosk nicht
    # unterbrechen. OS-Updates werden stattdessen durch den wöchentlichen Cron-Job (Schritt G4)
    # kontrolliert eingespielt (Sonntag 02:30 Uhr, vor dem wöchentlichen Neustart um 03:00 Uhr).
    for svc in bluetooth.service hciuart.service avahi-daemon.service triggerhappy.service \
               apt-daily.service apt-daily-upgrade.service apt-daily.timer apt-daily-upgrade.timer; do
        sudo systemctl disable --now "$svc" 2>/dev/null || true
    done
    ok "Unnötige Dienste deaktiviert (Bluetooth, Avahi, apt-daily …)."
    info "apt-daily-Timer deaktiviert – OS-Updates werden durch den wöchentlichen Cron-Job (Schritt G4) erledigt."

    ok "Raspberry Pi Optimierungen abgeschlossen."
fi

# ---------------------------------------------------------------------------
# Schritt G4: Automatische wöchentliche Updates
# ---------------------------------------------------------------------------
step "Automatische wöchentliche Updates einrichten"

# OS-Update: Sonntag 02:30 Uhr (root-Cron, da apt/dnf root benötigt)
OS_UPDATE_CRON="30 2 * * 0 ${INSTALL_DIR}/os-update.sh"
if ! sudo crontab -l 2>/dev/null | grep -qF "${INSTALL_DIR}/os-update.sh"; then
    (sudo crontab -l 2>/dev/null; echo "${OS_UPDATE_CRON}") | sudo crontab -
    ok "OS-Update Cron eingerichtet (Sonntag 02:30 Uhr)."
else
    info "OS-Update Cron bereits vorhanden."
fi

# Docker-Update: Sonntag 02:45 Uhr (läuft als SCRIPT_USER, daher im User-Cron)
DOCKER_UPDATE_CRON="45 2 * * 0 ${INSTALL_DIR}/update.sh >> /var/log/alarm-system-docker-update.log 2>&1"
if ! crontab -u "${SCRIPT_USER}" -l 2>/dev/null | grep -qF "${INSTALL_DIR}/update.sh"; then
    (crontab -u "${SCRIPT_USER}" -l 2>/dev/null; echo "${DOCKER_UPDATE_CRON}") | crontab -u "${SCRIPT_USER}" -
    ok "Docker-Update Cron eingerichtet (Sonntag 02:45 Uhr)."
else
    info "Docker-Update Cron bereits vorhanden."
fi

# ---------------------------------------------------------------------------
# Schritt H: Docker Images ziehen
# ---------------------------------------------------------------------------
step "Docker Images herunterladen"
sudo sh -c "cd '${INSTALL_DIR}' && docker compose pull"
ok "Images heruntergeladen."

# ---------------------------------------------------------------------------
# Schritt I: Dienste starten
# ---------------------------------------------------------------------------
step "Dienste starten"
if [[ "$INSTALL_CADDY" == "true" ]]; then
    sudo sh -c "cd '${INSTALL_DIR}' && docker compose --profile with-caddy up -d"
else
    sudo sh -c "cd '${INSTALL_DIR}' && docker compose up -d"
fi
ok "Dienste gestartet."

# ---------------------------------------------------------------------------
# Schritt J: Warten bis Dienste bereit sind
# ---------------------------------------------------------------------------
step "Warte auf Dienste …"
MAX_WAIT=120

wait_for_health() {
    local NAME="$1"
    local URL="$2"
    local -i waited=0
    echo -n "  Warte auf ${NAME}"
    while ! curl -fs "${URL}" >/dev/null 2>&1; do
        sleep 3
        waited=$((waited+3))
        echo -n "."
        if [[ $waited -ge $MAX_WAIT ]]; then
            echo ""
            warn "${NAME} antwortet nach ${MAX_WAIT}s noch nicht. Bitte Logs prüfen: ${INSTALL_DIR}/logs.sh"
            return 1
        fi
    done
    echo ""
    ok "${NAME} ist bereit."
}

[[ "$INSTALL_MONITOR"   == "true" ]] && wait_for_health "alarm-monitor"   "http://localhost:${ALARM_MONITOR_PORT:-8000}/health"   || true
[[ "$INSTALL_MESSENGER" == "true" ]] && wait_for_health "alarm-messenger" "http://localhost:${ALARM_MESSENGER_PORT:-3000}/health" || true

# ---------------------------------------------------------------------------
# Schritt K: Admin-Benutzer für alarm-messenger anlegen
# ---------------------------------------------------------------------------
if [[ "$INSTALL_MESSENGER" == "true" ]]; then
    step "alarm-messenger Admin-Benutzer anlegen"
    INIT_RESPONSE="$(curl -sf -X POST \
        "http://localhost:${ALARM_MESSENGER_PORT:-3000}/api/admin/init" \
        -H "Content-Type: application/json" \
        -d "{\"username\":\"${MESSENGER_ADMIN_USER}\",\"password\":\"${MESSENGER_ADMIN_PASSWORD}\"}" \
        2>&1 || true)"

    if echo "${INIT_RESPONSE}" | grep -qi "error\|already"; then
        warn "Admin-Benutzer konnte nicht angelegt werden oder existiert bereits."
        info "Response: ${INIT_RESPONSE}"
    else
        ok "Admin-Benutzer '${MESSENGER_ADMIN_USER}' angelegt."
    fi
fi

# ---------------------------------------------------------------------------
# Abschluss: Zusammenfassung
# ---------------------------------------------------------------------------
echo ""
sep
echo -e "${BOLD}${GREEN}  ✔  Installation abgeschlossen!${NC}"
sep
echo ""
echo -e "${BOLD}  Installationsverzeichnis: ${CYAN}${INSTALL_DIR}${NC}"
echo ""

if [[ "$INSTALL_MONITOR" == "true" ]]; then
    echo -e "  ${BOLD}alarm-monitor Dashboard:${NC}"
    echo -e "    ${CYAN}http://$(hostname -I 2>/dev/null | awk '{print $1}' || echo 'localhost'):${ALARM_MONITOR_PORT:-8000}${NC}"
    if [[ "$INSTALL_CADDY" == "true" && -n "${ALARM_MONITOR_DOMAIN:-}" ]]; then
        echo -e "    ${CYAN}https://${ALARM_MONITOR_DOMAIN}${NC} (nach DNS-Konfiguration)"
    fi
    echo ""
fi

if [[ "$INSTALL_MESSENGER" == "true" ]]; then
    echo -e "  ${BOLD}alarm-messenger Admin-Interface:${NC}"
    echo -e "    ${CYAN}http://$(hostname -I 2>/dev/null | awk '{print $1}' || echo 'localhost'):${ALARM_MESSENGER_PORT:-3000}/admin/login.html${NC}"
    echo -e "    Login: ${CYAN}${MESSENGER_ADMIN_USER:-admin}${NC} / (gewähltes Passwort)"
    if [[ "$INSTALL_CADDY" == "true" && -n "${ALARM_MESSENGER_DOMAIN:-}" ]]; then
        echo -e "    ${CYAN}https://${ALARM_MESSENGER_DOMAIN}/admin/login.html${NC} (nach DNS-Konfiguration)"
    fi
    echo ""
fi

echo -e "  ${BOLD}Nützliche Befehle:${NC}"
echo -e "    ${CYAN}${INSTALL_DIR}/status.sh${NC}      – Container-Status & Ressourcen"
echo -e "    ${CYAN}${INSTALL_DIR}/logs.sh${NC}        – Live-Logs"
echo -e "    ${CYAN}${INSTALL_DIR}/update.sh${NC}      – Docker Images manuell aktualisieren"
echo -e "    ${CYAN}sudo ${INSTALL_DIR}/os-update.sh${NC} – OS-Pakete manuell aktualisieren"
echo -e "    ${CYAN}${INSTALL_DIR}/backup.sh${NC}      – Backup erstellen"
echo -e "    ${CYAN}cd ${INSTALL_DIR} && docker compose ps${NC}"
echo -e "  ${BOLD}Automatische Updates (wöchentlich, Sonntag):${NC}"
echo -e "    02:30 – OS-Update  (${INSTALL_DIR}/os-update.sh)"
echo -e "    02:45 – Docker-Update  (${INSTALL_DIR}/update.sh)"
echo ""

if [[ "$INSTALL_KIOSK" == "true" ]]; then
    echo -e "  ${BOLD}Kiosk-Modus:${NC}"
    echo -e "    Neustart erforderlich für automatischen X-Start."
    echo -e "    ${CYAN}sudo reboot${NC}"
    echo -e "    Wöchentlicher Neustart: Sonntag 03:00 Uhr (Cron)"
    echo ""
fi

if [[ "$INSTALL_CADDY" == "true" ]]; then
    echo -e "  ${BOLD}Caddy (HTTPS):${NC}"
    echo -e "    Starten mit: ${CYAN}cd ${INSTALL_DIR} && docker compose --profile with-caddy up -d${NC}"
    echo -e "    DNS-Einträge müssen auf diese Server-IP zeigen."
    echo ""
fi

echo -e "  ${BOLD}Test-Alarm senden:${NC}"
if [[ "$INSTALL_MONITOR" == "true" ]]; then
    cat <<EOF
    curl -X POST http://localhost:${ALARM_MONITOR_PORT:-8000}/api/alarm \\
      -H "Content-Type: application/json" \\
      -H "X-API-Key: ${ALARM_MONITOR_API_KEY}" \\
      -d '{"incident_number":"TEST-001","timestamp":"$(date -Iseconds)","keyword":"BRAND 3","diagnosis":"Test-Alarm","location":{"street":"Teststraße","house_number":"1","city":"Teststadt","latitude":51.0,"longitude":9.0}}'
EOF
fi
echo ""
sep
echo -e "  Konfigurationsdatei : ${CYAN}${INSTALL_DIR}/.env${NC}"
echo -e "  docker-compose.yml  : ${CYAN}${INSTALL_DIR}/docker-compose.yml${NC}"
sep
echo ""
