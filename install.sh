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
        INSTALL_MONITOR INSTALL_MESSENGER INSTALL_MAIL INSTALL_CADDY INSTALL_KIOSK KIOSK_URL INSTALL_HDMI_CEC
        ALARM_MONITOR_PORT ALARM_MONITOR_API_KEY ALARM_MONITOR_SETTINGS_PASSWORD ALARM_MONITOR_DISPLAY_DURATION_MINUTES ALARM_MONITOR_DOMAIN
        ALARM_MONITOR_ORS_API_KEY ALARM_MONITOR_METRICS_TOKEN ALARM_MONITOR_HISTORY_FILE ALARM_MONITOR_SETTINGS_FILE
        ALARM_MONITOR_GRUPPEN ALARM_MONITOR_FIRE_DEPARTMENT_NAME
        ALARM_MONITOR_DEFAULT_LATITUDE ALARM_MONITOR_DEFAULT_LONGITUDE ALARM_MONITOR_DEFAULT_LOCATION_NAME
        ALARM_MONITOR_CALENDAR_URLS
        ALARM_MONITOR_SHOW_LAST_ALARM ALARM_MONITOR_WARNINGS_MIN_LEVEL ALARM_MONITOR_DWD_WARNINGS_MOCK
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
# HDMI-CEC: Pakete, Pfade und Zugriff
# ---------------------------------------------------------------------------

# install_hdmi_cec_packages  →  Installiert cec-client je nach Paketmanager
install_hdmi_cec_packages() {
    local _installed=false
    case "$PKG_MGR" in
        apt)
            if eval "${PKG_INSTALL} cec-utils" 2>/dev/null; then
                _installed=true
            fi
            ;;
        dnf|yum)
            if eval "${PKG_INSTALL} libcec" 2>/dev/null; then
                _installed=true
            fi
            ;;
        pacman)
            if eval "${PKG_INSTALL} libcec" 2>/dev/null; then
                _installed=true
            fi
            ;;
        zypper)
            if eval "${PKG_INSTALL} libcec" 2>/dev/null; then
                _installed=true
            fi
            ;;
        apk)
            if eval "${PKG_INSTALL} libcec" 2>/dev/null; then
                _installed=true
            fi
            ;;
    esac
    if [[ "$_installed" == "true" ]]; then
        ok "HDMI-CEC Pakete installiert."
        return 0
    fi
    warn "HDMI-CEC Pakete konnten nicht installiert werden."
    return 1
}

# detect_hdmi_cec_paths  →  Setzt CEC_CLIENT_PATH, CEC_DEVICE_PATH, CEC_LIB_MOUNTS
detect_hdmi_cec_paths() {
    CEC_CLIENT_PATH="$(command -v cec-client 2>/dev/null || true)"
    CEC_DEVICE_PATH=""
    CEC_LIB_MOUNTS=()

    for _dev in /dev/cec0 /dev/cec1; do
        if [[ -e "$_dev" ]]; then
            CEC_DEVICE_PATH="$_dev"
            break
        fi
    done
    # Standardpfad, falls Gerät erst nach Neustart/HDMI-Hotplug erscheint
    [[ -z "$CEC_DEVICE_PATH" ]] && CEC_DEVICE_PATH="/dev/cec0"

    if [[ -n "$CEC_CLIENT_PATH" ]]; then
        while IFS= read -r _lib; do
            [[ -f "$_lib" ]] && CEC_LIB_MOUNTS+=("$_lib")
        done < <(ldd "$CEC_CLIENT_PATH" 2>/dev/null \
            | awk '/=> \//{print $3}' \
            | grep -E 'libcec|libp8-platform' || true)
    fi

    ALARM_MONITOR_CEC_CLIENT_PATH="${CEC_CLIENT_PATH:-/usr/bin/cec-client}"
    ALARM_MONITOR_CEC_DEVICE="${CEC_DEVICE_PATH}"
}

# configure_hdmi_cec_access  →  udev-Regel und Gruppenmitgliedschaft
configure_hdmi_cec_access() {
    if getent group video >/dev/null 2>&1; then
        sudo usermod -aG video "${SCRIPT_USER}" 2>/dev/null || true
        ok "Benutzer '${SCRIPT_USER}' zur Gruppe 'video' hinzugefügt (CEC-Zugriff)."
    fi

    sudo tee /etc/udev/rules.d/99-alarm-system-cec.rules > /dev/null <<'UDEV'
# HDMI-CEC Geräte für Alarm-System (alarm-monitor)
KERNEL=="cec[0-9]*", MODE="0660", GROUP="video"
UDEV
    sudo udevadm control --reload-rules 2>/dev/null || true
    sudo udevadm trigger 2>/dev/null || true
    ok "udev-Regel für HDMI-CEC eingerichtet."
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
INSTALL_HDMI_CEC="${INSTALL_HDMI_CEC:-false}"
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
ALARM_MONITOR_SHOW_LAST_ALARM="${ALARM_MONITOR_SHOW_LAST_ALARM:-true}"
ALARM_MONITOR_WARNINGS_MIN_LEVEL="${ALARM_MONITOR_WARNINGS_MIN_LEVEL:-3}"
ALARM_MONITOR_DWD_WARNINGS_MOCK="${ALARM_MONITOR_DWD_WARNINGS_MOCK:-false}"
ALARM_MAIL_HTTP_TIMEOUT="${ALARM_MAIL_HTTP_TIMEOUT:-}"
ALARM_MAIL_LOG_LEVEL="${ALARM_MAIL_LOG_LEVEL:-}"
ALARM_MAIL_DEDUP_TTL="${ALARM_MAIL_DEDUP_TTL:-}"
ALARM_MAIL_DEDUP_DB="${ALARM_MAIL_DEDUP_DB:-}"
ALARM_MAIL_TARGET_COUNT="${ALARM_MAIL_TARGET_COUNT:-0}"
load_state

# Abwärtskompatibilität: alter Variablenname aus früheren install.sh-Versionen
ALARM_MONITOR_DISPLAY_DURATION_MINUTES="${ALARM_MONITOR_DISPLAY_DURATION_MINUTES:-${ALARM_MONITOR_DISPLAY_DURATION:-30}}"

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
# Schritt 3b: HDMI-CEC (Monitor/TV Steuerung)
# ---------------------------------------------------------------------------
if [[ "$INSTALL_MONITOR" == "true" ]]; then
    step "HDMI-CEC (Monitor/TV per HDMI steuern)"
    echo ""
    info "Mit HDMI-CEC kann alarm-monitor z.B. den Monitor/TV bei einem Alarm"
    info "einschalten und nach Idle-Zeit wieder in den Standby versetzen."
    info "Voraussetzung: HDMI-Kabel mit CEC-Unterstützung (z.B. Raspberry Pi → TV/Monitor)."
    echo ""
    _cec_default="n"
    if [[ "$INSTALL_KIOSK" == "true" || "$IS_RPI" == "true" ]]; then
        _cec_default="y"
    fi
    if yes_no "HDMI-CEC Unterstützung einrichten?" "${_cec_default}"; then
        INSTALL_HDMI_CEC=true
    else
        INSTALL_HDMI_CEC=false
    fi
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
    prompt_optional ALARM_MONITOR_DISPLAY_DURATION_MINUTES "Alarm-Anzeigedauer (Minuten)" "${ALARM_MONITOR_DISPLAY_DURATION_MINUTES:-30}"

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

    echo ""
    info "DWD-Unwetterwarnungen werden im Ruhezustand automatisch angezeigt (Standard: ab Warnstufe 3)."
    if yes_no "Letzten Einsatz im Ruhezustand anzeigen?" "$(bool_to_yn "${ALARM_MONITOR_SHOW_LAST_ALARM}")"; then
        ALARM_MONITOR_SHOW_LAST_ALARM=true
    else
        ALARM_MONITOR_SHOW_LAST_ALARM=false
    fi
    prompt_optional ALARM_MONITOR_WARNINGS_MIN_LEVEL \
        "Mindest-DWD-Warnstufe für Anzeige (1–4, Standard: 3)" \
        "${ALARM_MONITOR_WARNINGS_MIN_LEVEL:-3}"

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
[[ "$INSTALL_HDMI_CEC"  == "true" ]] && echo -e "    ${GREEN}✔${NC} HDMI-CEC (Monitor/TV Steuerung für alarm-monitor)"
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
# Schritt B2: HDMI-CEC Pakete installieren (für alarm-monitor)
# ---------------------------------------------------------------------------
if [[ "${INSTALL_HDMI_CEC:-false}" == "true" ]]; then
    step "HDMI-CEC Pakete installieren"
    if install_hdmi_cec_packages; then
        detect_hdmi_cec_paths
        configure_hdmi_cec_access
        if [[ -n "${CEC_CLIENT_PATH:-}" ]]; then
            ok "cec-client gefunden: ${CEC_CLIENT_PATH}"
        else
            warn "cec-client nicht im PATH – Paketinstallation prüfen."
        fi
        if [[ -e "${CEC_DEVICE_PATH:-/dev/cec0}" ]]; then
            ok "CEC-Gerät gefunden: ${CEC_DEVICE_PATH}"
        else
            info "CEC-Gerät (${CEC_DEVICE_PATH:-/dev/cec0}) noch nicht vorhanden – erscheint ggf. nach Neustart mit angeschlossenem HDMI."
        fi
    else
        warn "HDMI-CEC deaktiviert – Paketinstallation fehlgeschlagen."
        INSTALL_HDMI_CEC=false
    fi
fi

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
ALARM_MONITOR_DISPLAY_DURATION_MINUTES=${ALARM_MONITOR_DISPLAY_DURATION_MINUTES:-30}
${ALARM_MONITOR_SHOW_LAST_ALARM:+ALARM_MONITOR_SHOW_LAST_ALARM=${ALARM_MONITOR_SHOW_LAST_ALARM}}
${ALARM_MONITOR_WARNINGS_MIN_LEVEL:+ALARM_MONITOR_WARNINGS_MIN_LEVEL=${ALARM_MONITOR_WARNINGS_MIN_LEVEL}}
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
${INSTALL_HDMI_CEC:+ALARM_MONITOR_CEC_ENABLED=true}
${INSTALL_HDMI_CEC:+ALARM_MONITOR_CEC_CLIENT_PATH=${ALARM_MONITOR_CEC_CLIENT_PATH:-/usr/bin/cec-client}}
${INSTALL_HDMI_CEC:+ALARM_MONITOR_CEC_DEVICE=${ALARM_MONITOR_CEC_DEVICE:-/dev/cec0}}

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
      - ALARM_MONITOR_API_KEY=${ALARM_MONITOR_API_KEY}
      - ALARM_MONITOR_SETTINGS_PASSWORD=${ALARM_MONITOR_SETTINGS_PASSWORD}
EOF

    if [[ "$INSTALL_MESSENGER" == "true" ]]; then
        cat >> "${COMPOSE_FILE}" <<'EOF'
      - ALARM_MONITOR_MESSENGER_SERVER_URL=http://alarm-messenger:3000
      - ALARM_MONITOR_MESSENGER_API_KEY=${ALARM_MESSENGER_API_SECRET_KEY}
EOF
    fi

    cat >> "${COMPOSE_FILE}" <<'EOF'
      - ALARM_MONITOR_DISPLAY_DURATION_MINUTES=${ALARM_MONITOR_DISPLAY_DURATION_MINUTES:-30}
EOF

    # Optional parameters – only written to compose if configured
    [[ "${ALARM_MONITOR_SHOW_LAST_ALARM:-true}" == "false" ]] && echo "      - ALARM_MONITOR_SHOW_LAST_ALARM=false" >> "${COMPOSE_FILE}"
    [[ -n "${ALARM_MONITOR_WARNINGS_MIN_LEVEL:-}" && "${ALARM_MONITOR_WARNINGS_MIN_LEVEL}" != "3" ]] && echo "      - ALARM_MONITOR_WARNINGS_MIN_LEVEL=\${ALARM_MONITOR_WARNINGS_MIN_LEVEL}" >> "${COMPOSE_FILE}"
    [[ "${ALARM_MONITOR_DWD_WARNINGS_MOCK:-false}" == "true" ]] && echo "      - ALARM_MONITOR_DWD_WARNINGS_MOCK=true" >> "${COMPOSE_FILE}"
    [[ -n "${ALARM_MONITOR_GRUPPEN:-}" ]]               && echo "      - ALARM_MONITOR_GRUPPEN=\${ALARM_MONITOR_GRUPPEN}" >> "${COMPOSE_FILE}"
    [[ -n "${ALARM_MONITOR_CALENDAR_URLS:-}" ]]           && echo "      - ALARM_MONITOR_CALENDAR_URLS=\${ALARM_MONITOR_CALENDAR_URLS}" >> "${COMPOSE_FILE}"
    [[ -n "${ALARM_MONITOR_NTFY_TOPIC_URL:-}" ]]          && echo "      - ALARM_MONITOR_NTFY_TOPIC_URL=\${ALARM_MONITOR_NTFY_TOPIC_URL}" >> "${COMPOSE_FILE}"
    [[ -n "${ALARM_MONITOR_NTFY_POLL_INTERVAL:-}" ]]      && echo "      - ALARM_MONITOR_NTFY_POLL_INTERVAL=\${ALARM_MONITOR_NTFY_POLL_INTERVAL}" >> "${COMPOSE_FILE}"
    [[ -n "${ALARM_MONITOR_MESSAGES_FILE:-}" ]]           && echo "      - ALARM_MONITOR_MESSAGES_FILE=\${ALARM_MONITOR_MESSAGES_FILE}" >> "${COMPOSE_FILE}"
    [[ -n "${ALARM_MONITOR_MESSAGE_MAX_TTL_HOURS:-}" ]]   && echo "      - ALARM_MONITOR_MESSAGE_MAX_TTL_HOURS=\${ALARM_MONITOR_MESSAGE_MAX_TTL_HOURS}" >> "${COMPOSE_FILE}"
    [[ -n "${ALARM_MONITOR_FIRE_DEPARTMENT_NAME:-}" ]]    && echo "      - ALARM_MONITOR_FIRE_DEPARTMENT_NAME=\${ALARM_MONITOR_FIRE_DEPARTMENT_NAME}" >> "${COMPOSE_FILE}"
    [[ -n "${ALARM_MONITOR_DEFAULT_LATITUDE:-}" ]]        && echo "      - ALARM_MONITOR_DEFAULT_LATITUDE=\${ALARM_MONITOR_DEFAULT_LATITUDE}" >> "${COMPOSE_FILE}"
    [[ -n "${ALARM_MONITOR_DEFAULT_LONGITUDE:-}" ]]       && echo "      - ALARM_MONITOR_DEFAULT_LONGITUDE=\${ALARM_MONITOR_DEFAULT_LONGITUDE}" >> "${COMPOSE_FILE}"
    [[ -n "${ALARM_MONITOR_DEFAULT_LOCATION_NAME:-}" ]]  && echo "      - ALARM_MONITOR_DEFAULT_LOCATION_NAME=\${ALARM_MONITOR_DEFAULT_LOCATION_NAME}" >> "${COMPOSE_FILE}"
    [[ -n "${ALARM_MONITOR_ORS_API_KEY:-}" ]]             && echo "      - ALARM_MONITOR_ORS_API_KEY=\${ALARM_MONITOR_ORS_API_KEY}" >> "${COMPOSE_FILE}"
    [[ -n "${ALARM_MONITOR_METRICS_TOKEN:-}" ]]           && echo "      - ALARM_MONITOR_METRICS_TOKEN=\${ALARM_MONITOR_METRICS_TOKEN}" >> "${COMPOSE_FILE}"
    [[ -n "${ALARM_MONITOR_HISTORY_FILE:-}" ]]           && echo "      - ALARM_MONITOR_HISTORY_FILE=\${ALARM_MONITOR_HISTORY_FILE}" >> "${COMPOSE_FILE}"
    [[ -n "${ALARM_MONITOR_SETTINGS_FILE:-}" ]]           && echo "      - ALARM_MONITOR_SETTINGS_FILE=\${ALARM_MONITOR_SETTINGS_FILE}" >> "${COMPOSE_FILE}"

    if [[ "${INSTALL_HDMI_CEC:-false}" == "true" ]]; then
        cat >> "${COMPOSE_FILE}" <<'EOF'
      - ALARM_MONITOR_CEC_ENABLED=true
EOF
        echo "      - ALARM_MONITOR_CEC_CLIENT_PATH=${ALARM_MONITOR_CEC_CLIENT_PATH:-/usr/bin/cec-client}" >> "${COMPOSE_FILE}"
        echo "      - ALARM_MONITOR_CEC_DEVICE=${ALARM_MONITOR_CEC_DEVICE:-/dev/cec0}" >> "${COMPOSE_FILE}"
    fi

    cat >> "${COMPOSE_FILE}" <<'EOF'
      - TZ=${TZ:-Europe/Berlin}
    volumes:
      - alarm-monitor-data:/app/instance
EOF

    if [[ "${INSTALL_HDMI_CEC:-false}" == "true" ]]; then
        if [[ -n "${ALARM_MONITOR_CEC_CLIENT_PATH:-}" && -f "${ALARM_MONITOR_CEC_CLIENT_PATH}" ]]; then
            echo "      - ${ALARM_MONITOR_CEC_CLIENT_PATH}:${ALARM_MONITOR_CEC_CLIENT_PATH}:ro" >> "${COMPOSE_FILE}"
        fi
        for _cec_lib in "${CEC_LIB_MOUNTS[@]}"; do
            echo "      - ${_cec_lib}:${_cec_lib}:ro" >> "${COMPOSE_FILE}"
        done
        cat >> "${COMPOSE_FILE}" <<EOF
    devices:
      - ${ALARM_MONITOR_CEC_DEVICE:-/dev/cec0}
EOF
        if [[ -e /dev/vchiq ]]; then
            echo "      - /dev/vchiq" >> "${COMPOSE_FILE}"
        fi
    fi

    cat >> "${COMPOSE_FILE}" <<'EOF'
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
            eval "${PKG_INSTALL} xorg-x11-server-Xorg openbox unclutter chromium xdotool"
            # Emoji- und Unicode-Schriftarten für korrekte Darstellung von Wetter-Symbolen
            eval "${PKG_INSTALL} google-noto-emoji-color-fonts google-noto-emoji-fonts" 2>/dev/null || \
                eval "${PKG_INSTALL} google-noto-emoji-color-fonts" 2>/dev/null || true
            KIOSK_BIN="chromium-browser"
            command -v chromium >/dev/null 2>&1 && KIOSK_BIN="chromium"
            ;;
        pacman)
            eval "${PKG_INSTALL} xorg-server openbox unclutter chromium xdotool"
            # Emoji- und Unicode-Schriftarten für korrekte Darstellung von Wetter-Symbolen
            eval "${PKG_INSTALL} noto-fonts-emoji noto-fonts" 2>/dev/null || true
            KIOSK_BIN="chromium"
            ;;
        zypper)
            eval "${PKG_INSTALL} xorg-x11-server openbox unclutter chromium xdotool"
            # Emoji- und Unicode-Schriftarten für korrekte Darstellung von Wetter-Symbolen
            eval "${PKG_INSTALL} google-noto-coloremoji-fonts google-noto-fonts" 2>/dev/null || \
                eval "${PKG_INSTALL} google-noto-coloremoji-fonts" 2>/dev/null || true
            KIOSK_BIN="chromium"
            ;;
        apk)
            eval "${PKG_INSTALL} xorg-server openbox unclutter chromium xdotool"
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
    --remote-debugging-address=127.0.0.1 \\
    --remote-debugging-port=9222 \\
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
DEBUG_JSON_URL="http://127.0.0.1:9222/json"
ERROR_COUNT_FILE="/tmp/alarm-kiosk-error-count"
MAX_RELOAD_ATTEMPTS=2
PROFILE_DIR="\${XDG_RUNTIME_DIR:-\${HOME}/.cache}/kiosk-profile"

log() { echo "[\$(date '+%Y-%m-%d %H:%M:%S')] \$*" >> "\$LOG_FILE"; }

log "Watchdog gestartet"

read_error_count() {
    cat "\$ERROR_COUNT_FILE" 2>/dev/null || echo "0"
}

write_error_count() {
    echo "\$1" > "\$ERROR_COUNT_FILE"
}

is_browser_error_page() {
    local pages
    pages=\$(curl -sf --max-time 3 "\$DEBUG_JSON_URL" 2>/dev/null || true)
    [ -z "\$pages" ] && return 1
    echo "\$pages" | grep -Eqi 'chrome-error://|ERR_|Fehlercode[^0-9]*[0-9]+|Aw, Snap|Oh nein'
}

reload_kiosk_browser() {
    local win_id
    command -v xdotool >/dev/null 2>&1 || return 1
    win_id=\$(DISPLAY=:0 XAUTHORITY="\${HOME}/.Xauthority" xdotool search --onlyvisible --class 'chromium|Chromium|google-chrome|Google-chrome' 2>/dev/null | head -n1)
    [ -n "\$win_id" ] || return 1
    DISPLAY=:0 XAUTHORITY="\${HOME}/.Xauthority" xdotool windowactivate "\$win_id" key --clearmodifiers ctrl+r 2>/dev/null
}

restart_kiosk_browser() {
    local killed_any="false"
    log "AKTION: Browser-Prozess wird beendet (systemd startet kiosk.service automatisch neu)"
    while read -r pid _; do
        [ -n "\$pid" ] || continue
        kill "\$pid" 2>/dev/null || true
        killed_any="true"
    done < <(pgrep -af 'chromium|chromium-browser|google-chrome' | grep -F -- "\$PROFILE_DIR" || true)
    [ "\$killed_any" = "true" ] || log "INFO: Kein passender Kiosk-Browser-Prozess zum Beenden gefunden"
}

while true; do
    # Docker-Dienste prüfen
    if ! curl -sf --max-time 5 "\${MONITOR_URL}/health" > /dev/null 2>&1; then
        log "WARNUNG: alarm-monitor nicht erreichbar – starte Docker-Dienste neu"
        cd "${INSTALL_DIR}" && docker compose restart >> "\$LOG_FILE" 2>&1
    fi

    # X-Display prüfen (nur wenn kiosk läuft)
    if command -v xdpyinfo >/dev/null 2>&1; then
        if ! DISPLAY=:0 xdpyinfo > /dev/null 2>&1; then
            log "WARNUNG: X-Display nicht aktiv – Browser-Prozess wird zur Recovery beendet"
            restart_kiosk_browser
        else
            # DPMS und Bildschirmschoner periodisch deaktivieren (verhindert Standby/Blanking)
            DISPLAY=:0 XAUTHORITY="${HOME}/.Xauthority" xset s off 2>/dev/null || true
            DISPLAY=:0 XAUTHORITY="${HOME}/.Xauthority" xset s noblank 2>/dev/null || true
            DISPLAY=:0 XAUTHORITY="${HOME}/.Xauthority" xset -dpms 2>/dev/null || true

            # Browser-Fehlerseiten erkennen (z. B. "Fehlercode: 5")
            if is_browser_error_page; then
                ERROR_COUNT=\$(read_error_count)
                ERROR_COUNT=\$((ERROR_COUNT + 1))
                write_error_count "\$ERROR_COUNT"
                log "WARNUNG: Browser-Fehlerseite erkannt (Versuch \$ERROR_COUNT/\$MAX_RELOAD_ATTEMPTS)"

                if [ "\$ERROR_COUNT" -le "\$MAX_RELOAD_ATTEMPTS" ]; then
                    if reload_kiosk_browser; then
                        log "AKTION: Browser-Reload (Ctrl+R) ausgelöst"
                    else
                        log "WARNUNG: Reload nicht möglich – Browser wird stattdessen neu gestartet"
                        restart_kiosk_browser
                    fi
                else
                    log "WARNUNG: Fehler bleibt bestehen – Browser wird neu gestartet"
                    restart_kiosk_browser
                    write_error_count "0"
                fi
            else
                write_error_count "0"
            fi
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

        # Wappen-Bild (crest.png) aus eingebettetem Base64 ins Theme-Verzeichnis dekodieren
        base64 -d <<'CRESTB64' | sudo tee /usr/share/plymouth/themes/alarm-system/crest.png > /dev/null
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
lmnd1On/AVRRD/7ZCMBZAAAAAElFTkSuQmCC
CRESTB64

        sudo tee /usr/share/plymouth/themes/alarm-system/alarm-system.script > /dev/null <<'PLYMSCRIPT'
# Hintergrundfarben passend zum Feuerwehr-Wappen (oben Dunkelrot, unten fast Schwarz)
Window.SetBackgroundTopColor(0.55, 0.05, 0.05);
Window.SetBackgroundBottomColor(0.18, 0.02, 0.02);

logo_scale = 2.0;
logo_gap   = 40;
title_scale    = 5.6;
subtitle_scale = 3.2;
line_gap = 36;

logo_orig = Image("crest.png");
logo_w = Math.Int(logo_orig.GetWidth()  * logo_scale);
logo_h = Math.Int(logo_orig.GetHeight() * logo_scale);
logo_img = logo_orig.Scale(logo_w, logo_h);
logo_sprite = Sprite();
logo_sprite.SetImage(logo_img);

title_image = Image.Text("Alarm-System lädt...", 1.0, 1.0, 1.0);
title_sprite = Sprite();
title_sprite.SetImage(title_image);
title_sprite.SetXScale(title_scale);
title_sprite.SetYScale(title_scale);

subtitle_image = Image.Text("Bitte warten...", 0.8, 0.8, 0.8);
subtitle_sprite = Sprite();
subtitle_sprite.SetImage(subtitle_image);
subtitle_sprite.SetXScale(subtitle_scale);
subtitle_sprite.SetYScale(subtitle_scale);

title_w    = title_image.GetWidth()    * title_scale;
title_h    = title_image.GetHeight()   * title_scale;
subtitle_w = subtitle_image.GetWidth() * subtitle_scale;
subtitle_h = subtitle_image.GetHeight()* subtitle_scale;

block_h   = logo_h + logo_gap + title_h + line_gap + subtitle_h;
block_top = (Window.GetHeight() - block_h) / 2;

logo_x = (Window.GetWidth() - logo_w) / 2;
logo_y = block_top;

title_x = (Window.GetWidth() - title_w) / 2;
title_y = block_top + logo_h + logo_gap;

subtitle_x = (Window.GetWidth() - subtitle_w) / 2;
subtitle_y = title_y + title_h + line_gap;

logo_sprite.SetPosition(logo_x, logo_y, 10000);
title_sprite.SetPosition(title_x, title_y, 10000);
subtitle_sprite.SetPosition(subtitle_x, subtitle_y, 10000);
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
            # HDMI-CEC aktivieren (falls zuvor deaktiviert)
            if [[ "${INSTALL_HDMI_CEC:-false}" == "true" ]]; then
                if grep -q "^hdmi_ignore_cec=1" "$CONFIG_FILE"; then
                    sudo sed -i 's/^hdmi_ignore_cec=1/hdmi_ignore_cec=0/' "$CONFIG_FILE"
                    ok "HDMI-CEC in config.txt aktiviert (hdmi_ignore_cec=0)."
                fi
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

if [[ "$INSTALL_HDMI_CEC" == "true" ]]; then
    echo -e "  ${BOLD}HDMI-CEC:${NC}"
    echo -e "    cec-client: ${CYAN}${ALARM_MONITOR_CEC_CLIENT_PATH:-/usr/bin/cec-client}${NC}"
    echo -e "    Gerät:      ${CYAN}${ALARM_MONITOR_CEC_DEVICE:-/dev/cec0}${NC}"
    echo -e "    Steuerung erfolgt durch alarm-monitor (Einschalten bei Alarm, Standby nach Idle)."
    echo -e "    Test: ${CYAN}echo 'pow 0' | cec-client -s -d 1${NC}  (Monitor einschalten)"
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
