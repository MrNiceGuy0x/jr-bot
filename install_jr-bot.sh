#!/usr/bin/env bash
set -euo pipefail

SCRIPT_VERSION="0.1.0"

echo "=================================================="
echo " JR-Bot Universal Installer"
echo " Version: ${SCRIPT_VERSION}"
echo "=================================================="
echo

# --------------------------------------------------
# Helper functions
# --------------------------------------------------

ask_required() {
    local prompt="$1"
    local value=""

    while [ -z "$value" ]; do
        read -rp "$prompt: " value </dev/tty
        if [ -z "$value" ]; then
            echo "Dieser Wert darf nicht leer sein."
        fi
    done

    echo "$value"
}

ask_secret_required() {
    local prompt="$1"
    local value=""

    while [ -z "$value" ]; do
        read -rsp "$prompt: " value </dev/tty
        echo
        if [ -z "$value" ]; then
            echo "Dieser Wert darf nicht leer sein."
        fi
    done

    echo "$value"
}

confirm() {
    local prompt="$1"
    local answer=""

    read -rp "$prompt [y/N]: " answer </dev/tty

    case "$answer" in
        y|Y|yes|YES|Yes)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

require_command() {
    local cmd="$1"

    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "Fehler: Benötigter Befehl fehlt: $cmd"
        exit 1
    fi
}

# --------------------------------------------------
# Basic checks
# --------------------------------------------------

if [ ! -e /dev/tty ]; then
    echo "Fehler: Kein interaktives Terminal verfügbar."
    echo "Bitte Installer zuerst herunterladen und manuell ausführen:"
    echo
    echo "curl -fsSL https://raw.githubusercontent.com/MrNiceGuy0x/jr-bot/main/install_jr-bot.sh -o install_jr-bot.sh"
    echo "chmod +x install_jr-bot.sh"
    echo "./install_jr-bot.sh"
    exit 1
fi

require_command curl
require_command bash

echo "Systemprüfung abgeschlossen."
echo

# --------------------------------------------------
# Onboarding
# --------------------------------------------------

echo "Onboarding"
echo "----------"
echo "Bitte gib die Bot-Konfiguration ein."
echo

DEFAULT_PROJECT="TRAX"
DEFAULT_BOT_NAME="TRX"
DEFAULT_INSTALL_DIR="/opt/bots/trx"
DEFAULT_SERVER_BASE="https://trax.blenk.co.at/handler"
DEFAULT_INTERVAL="60"

read -rp "Projektname [${DEFAULT_PROJECT}]: " PROJECT_NAME </dev/tty
PROJECT_NAME="${PROJECT_NAME:-$DEFAULT_PROJECT}"

read -rp "Botname [${DEFAULT_BOT_NAME}]: " BOT_NAME </dev/tty
BOT_NAME="${BOT_NAME:-$DEFAULT_BOT_NAME}"

read -rp "Installationsordner [${DEFAULT_INSTALL_DIR}]: " INSTALL_DIR </dev/tty
INSTALL_DIR="${INSTALL_DIR:-$DEFAULT_INSTALL_DIR}"

read -rp "Server Base URL [${DEFAULT_SERVER_BASE}]: " SERVER_BASE </dev/tty
SERVER_BASE="${SERVER_BASE:-$DEFAULT_SERVER_BASE}"

read -rp "Polling-Intervall in Sekunden [${DEFAULT_INTERVAL}]: " INTERVAL_SECONDS </dev/tty
INTERVAL_SECONDS="${INTERVAL_SECONDS:-$DEFAULT_INTERVAL}"

SERVER_TOKEN="$(ask_secret_required "SERVER_TOKEN eingeben")"
PING_TOKEN="$(ask_secret_required "PING_TOKEN eingeben")"

echo
echo "Konfiguration:"
echo "Projekt:              $PROJECT_NAME"
echo "Botname:              $BOT_NAME"
echo "Installationsordner:  $INSTALL_DIR"
echo "Server Base URL:      $SERVER_BASE"
echo "Polling-Intervall:    $INTERVAL_SECONDS Sekunden"
echo

if ! confirm "Installation mit diesen Werten starten?"; then
    echo "Installation abgebrochen."
    exit 0
fi

# --------------------------------------------------
# Prepare system packages
# --------------------------------------------------

echo
echo "Installiere Systempakete..."

if command -v apt-get >/dev/null 2>&1; then
    sudo apt-get update
    sudo apt-get install -y python3 python3-venv python3-pip curl ca-certificates
else
    echo "Warnung: apt-get nicht gefunden. Paketinstallation wird übersprungen."
fi

# --------------------------------------------------
# Create directory structure
# --------------------------------------------------

echo
echo "Erstelle Bot-Verzeichnisstruktur..."

sudo mkdir -p "$INSTALL_DIR"
sudo mkdir -p "$INSTALL_DIR/src"
sudo mkdir -p "$INSTALL_DIR/config"
sudo mkdir -p "$INSTALL_DIR/logs"
sudo mkdir -p "$INSTALL_DIR/state"

CURRENT_USER="$(id -un)"
sudo chown -R "$CURRENT_USER":"$CURRENT_USER" "$INSTALL_DIR"

# --------------------------------------------------
# Create venv
# --------------------------------------------------

echo
echo "Erstelle Python venv..."

python3 -m venv "$INSTALL_DIR/venv"

# shellcheck source=/dev/null
source "$INSTALL_DIR/venv/bin/activate"

python -m pip install --upgrade pip

# --------------------------------------------------
# requirements.txt
# --------------------------------------------------

echo
echo "Erstelle requirements.txt..."

cat > "$INSTALL_DIR/requirements.txt" <<'EOF'
requests
python-dotenv
EOF

pip install -r "$INSTALL_DIR/requirements.txt"

# --------------------------------------------------
# config.ini
# --------------------------------------------------

echo
echo "Erstelle lokale config.ini..."

cat > "$INSTALL_DIR/config/config.ini" <<EOF
[bot]
PROJECT_NAME = ${PROJECT_NAME}
BOT_NAME = ${BOT_NAME}

[server]
SERVER_BASE = ${SERVER_BASE}
SERVER_TOKEN = ${SERVER_TOKEN}
PING_TOKEN = ${PING_TOKEN}

[polling]
INTERVAL_SECONDS = ${INTERVAL_SECONDS}
LOG_LEVEL = INFO

[paths]
LOG_DIR = logs
STATE_DIR = state
EOF

chmod 600 "$INSTALL_DIR/config/config.ini"

# --------------------------------------------------
# Minimal job_runner.py placeholder
# --------------------------------------------------

echo
echo "Erstelle minimalen job_runner.py..."

cat > "$INSTALL_DIR/src/job_runner.py" <<'EOF'
#!/usr/bin/env python3
import configparser
from pathlib import Path
from datetime import datetime, timezone

BASE_DIR = Path(__file__).resolve().parents[1]
CONFIG_FILE = BASE_DIR / "config" / "config.ini"
LOG_FILE = BASE_DIR / "logs" / "bot.log"

def log(message: str) -> None:
    timestamp = datetime.now(timezone.utc).isoformat()
    LOG_FILE.parent.mkdir(parents=True, exist_ok=True)
    with LOG_FILE.open("a", encoding="utf-8") as f:
        f.write(f"[{timestamp}] {message}\n")
    print(message)

def main() -> None:
    config = configparser.ConfigParser()
    config.read(CONFIG_FILE)

    bot_name = config.get("bot", "BOT_NAME", fallback="UNKNOWN")
    project_name = config.get("bot", "PROJECT_NAME", fallback="UNKNOWN")
    server_base = config.get("server", "SERVER_BASE", fallback="")

    log(f"JR-Bot gestartet: project={project_name}, bot={bot_name}, server_base={server_base}")

if __name__ == "__main__":
    main()
EOF

chmod +x "$INSTALL_DIR/src/job_runner.py"

# --------------------------------------------------
# Optional systemd setup
# --------------------------------------------------

echo
if confirm "systemd Service und Timer einrichten?"; then
    SERVICE_NAME="$(echo "$BOT_NAME" | tr '[:upper:]' '[:lower:]')-runner"
    SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"
    TIMER_FILE="/etc/systemd/system/${SERVICE_NAME}.timer"

    echo "Erstelle systemd Service: ${SERVICE_FILE}"

    sudo tee "$SERVICE_FILE" >/dev/null <<EOF
[Unit]
Description=JR-Bot Runner (${BOT_NAME})
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
WorkingDirectory=${INSTALL_DIR}
ExecStart=${INSTALL_DIR}/venv/bin/python ${INSTALL_DIR}/src/job_runner.py
User=${CURRENT_USER}
EOF

    echo "Erstelle systemd Timer: ${TIMER_FILE}"

    sudo tee "$TIMER_FILE" >/dev/null <<EOF
[Unit]
Description=JR-Bot Timer (${BOT_NAME})

[Timer]
OnBootSec=60
OnUnitActiveSec=${INTERVAL_SECONDS}
AccuracySec=5
Persistent=true

[Install]
WantedBy=timers.target
EOF

    sudo systemctl daemon-reload
    sudo systemctl enable --now "${SERVICE_NAME}.timer"

    echo "systemd Timer aktiviert: ${SERVICE_NAME}.timer"
fi

# --------------------------------------------------
# Test run
# --------------------------------------------------

echo
if confirm "Testlauf jetzt ausführen?"; then
    "$INSTALL_DIR/venv/bin/python" "$INSTALL_DIR/src/job_runner.py"
fi

echo
echo "=================================================="
echo "Installation abgeschlossen."
echo "Bot:       $BOT_NAME"
echo "Projekt:   $PROJECT_NAME"
echo "Pfad:      $INSTALL_DIR"
echo "Config:    $INSTALL_DIR/config/config.ini"
echo "Logfile:   $INSTALL_DIR/logs/bot.log"
echo "=================================================="
