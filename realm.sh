#!/bin/bash
set -o pipefail

# ==================================================
# Realm Manager - RUST HYBRID EDITION (v2.0)
# Core: Realm (Rust) | Zero-Copy Relay
# Focus:
#  - ENGINE: Swapped Gost (Go) with Realm (Rust)
#  - CONFIG: TOML Format Support
#  - PERFORMANCE: Zero-Allocation & Kernel Splice
#  - SYSTEM: Multi-OS Support (apt/dnf/pacman)
#  - LOGS: Journald Optimized & Logrotate
# ==================================================

# --- Shortcut ---
SHORTCUT_BIN="/usr/local/bin/irealm"
REPO_URL="https://raw.githubusercontent.com/Sir-Adnan/Realm-Tunnel-Manager/main/realm.sh"

# --- Colors (Safe Palette) ---
NC='\033[0m'
BOLD='\033[1m'
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
HI_CYAN='\033[0;96m'
HI_PINK='\033[0;95m'
HI_GREEN='\033[0;92m'

# --- Icons ---
ICON_ROCKET="🚀"
ICON_GEAR="🔧"
ICON_LOGS="📊"
ICON_TRASH="🗑️"
ICON_EXIT="🚪"
ICON_CPU="🧠"
ICON_RAM="💾"
ICON_NET="🌐"
ICON_INSTALL="💿"
ICON_RESTART="🔄"
ICON_RUST="🦀"

# --- Paths ---
CONFIG_DIR="/etc/realm"
CONFIG_FILE="/etc/realm/config.toml"
SERVICE_FILE="/etc/systemd/system/realm.service"
REALM_BIN="/usr/local/bin/realm"
LOG_POLICY_STATE_FILE="/etc/realm/.journald_policy"
JOURNALD_CONF_FILE="/etc/systemd/journald.conf.d/99-realm-manager.conf"
WATCHDOG_LOGROTATE_FILE="/etc/logrotate.d/realm-watchdog"

# --- Root Check ---
if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}Error: Please run as root.${NC}"
   exit 1
fi

# ==================================================
#  SMALL UTILS
# ==================================================

confirm_yes() {
    local ans="$1"
    [[ "$ans" =~ ^[Yy]([Ee][Ss])?$ ]]
}

ask_input() { echo -ne "  ${HI_PINK}➤ $1 : ${NC}"; }
section_title() { echo -e "\n  ${BOLD}${HI_CYAN}:: $1 ::${NC}"; }
info_msg() { echo -e "  ${YELLOW}ℹ${NC} ${BLUE}$1${NC}"; }

normalize_ip() {
    local input_ip=$1
    # Check for IPv6 format
    if [[ "$input_ip" == *":"* ]]; then
        if [[ "$input_ip" == *[* ]]; then echo "$input_ip"; else echo "[$input_ip]"; fi
    else
        echo "$input_ip"
    fi
}

validate_port() { [[ "$1" =~ ^[0-9]+$ ]] && [ "$1" -ge 1 ] && [ "$1" -le 65535 ]; }

backup_config() { cp "$CONFIG_FILE" "${CONFIG_FILE}.bak" 2>/dev/null; }

# --- MODIFIED: Verbose installation (Shows output) ---
install_core_dependencies() {
    echo -e "${BLUE}Updating package lists & Installing core tools...${NC}"
    if command -v apt-get >/dev/null 2>&1; then
        apt-get update && apt-get install -y curl openssl lsof nano netcat-openbsd vnstat logrotate cron
    elif command -v dnf >/dev/null 2>&1; then
        dnf install -y curl openssl lsof nano nmap-ncat vnstat logrotate cronie
    elif command -v yum >/dev/null 2>&1; then
        yum install -y curl openssl lsof nano nmap-ncat vnstat logrotate cronie
    elif command -v pacman >/dev/null 2>&1; then
        pacman -Sy --noconfirm curl openssl lsof nano gnu-netcat vnstat logrotate cronie
    else
        echo -e "${RED}Unsupported package manager. Install dependencies manually.${NC}"
        return 1
    fi
    return 0
}

apply_journald_limits() {
    local max_use="$1"
    local keep_free="$2"
    local max_file="$3"

    mkdir -p /etc/systemd/journald.conf.d
    cat <<EOF > "$JOURNALD_CONF_FILE"
[Journal]
SystemMaxUse=$max_use
SystemKeepFree=$keep_free
SystemMaxFileSize=$max_file
RateLimitIntervalSec=30s
RateLimitBurst=1000
EOF
    systemctl restart systemd-journald >/dev/null 2>&1
    journalctl --vacuum-size="$max_use" >/dev/null 2>&1
}

# ==================================================
#  VISUAL ENGINE
# ==================================================

draw_logo() {
    echo -e "${HI_CYAN}"
    echo "    ____  _________    __    __  ___"
    echo "   / __ \/ ____/   |  / /   /  |/  /"
    echo "  / /_/ / __/ / /| | / /   / /|_/ / "
    echo " / _, _/ /___/ ___ |/ /___/ /  / /  "
    echo "/_/ |_/_____/_/  |_/_____/_/  /_/   "
    echo "                                    "
    echo -e "     ${PURPLE}R U S T   E D I T I O N   ${BOLD}v 2.0${NC}"
    echo -e "         ${HI_PINK}High Performance Relay${NC}"
    echo ""
}

draw_line() {
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

print_option() {
    local id="$1"
    local icon="$2"
    local title="$3"
    local desc="$4"
    local total_width=45
    local title_len=${#title}
    local dots_count=$((total_width - title_len))
    local dots=""
    for ((i=0; i<dots_count; i++)); do dots="${dots}."; done
    echo -e "  ${HI_CYAN}[${id}]${NC} ${icon} ${BOLD}${title}${NC} ${BLUE}${dots}${NC} ${YELLOW}${desc}${NC}"
}

show_guide() {
    local title="$1"
    local text="$2"
    echo ""
    echo -e "  ${HI_PINK}╔══════════════════════════════════════════════════════════╗${NC}"
    echo -e "  ${HI_PINK}║${NC} ${HI_CYAN}GUIDE:${NC} ${BOLD}$title${NC}"
    echo -e "  ${HI_PINK}╠══════════════════════════════════════════════════════════╝${NC}"
    echo -e "  ${HI_PINK}║${NC} $text"
    echo -e "  ${HI_PINK}╚══════════════════════════════════════════════════════════${NC}"
    echo ""
}

show_warning() {
    echo -e "  ${RED}⚠ WARNING:${NC} ${YELLOW}Realm is L4 Only. No Decryption/WSS supported!${NC}"
}

# --------------------------------------------------
# Dashboard Caching
# --------------------------------------------------
CACHE_TTL=5
LAST_STATS_TS=0
C_SERVER_IP=""
C_RAM_USAGE=""
C_LOAD=""
C_TUNNELS="0"

refresh_stats_if_needed() {
    local now
    now=$(date +%s)
    if (( now - LAST_STATS_TS < CACHE_TTL )); then
        return 0
    fi
    LAST_STATS_TS=$now

    C_SERVER_IP=$(hostname -I 2>/dev/null | awk '{print $1}')
    C_RAM_USAGE=$(free -h 2>/dev/null | awk '/Mem:/ {print $3 "/" $2}')
    C_LOAD=$(awk '{print $1}' /proc/loadavg 2>/dev/null)

    if [ -f "$CONFIG_FILE" ]; then
        local t
        t=$(grep -c "\[\[endpoints\]\]" "$CONFIG_FILE")
        [[ -z "$t" ]] && t="0"
        C_TUNNELS="$t"
    else
        C_TUNNELS="0"
    fi
}

draw_dashboard() {
    clear
    draw_logo
    draw_line

    refresh_stats_if_needed

    local STATUS
    if systemctl is-active --quiet realm; then
        STATUS="${HI_GREEN}ACTIVE${NC}"
    else
        STATUS="${RED}OFFLINE${NC}"
    fi

    local DEBUG_MODE
    if grep -q "^StandardOutput=journal" "$SERVICE_FILE" 2>/dev/null; then
        DEBUG_MODE="${YELLOW}[DEBUG ON]${NC}"
    else
        DEBUG_MODE="${HI_GREEN}[SILENT]${NC}"
    fi

    echo -e "  ${ICON_NET} IP: ${BOLD}${C_SERVER_IP}${NC}"
    echo -e "  ${ICON_RAM} RAM: ${BOLD}${C_RAM_USAGE}${NC}   ${ICON_CPU} Load: ${BOLD}${C_LOAD}${NC}"
    echo -e "  ${ICON_GEAR} Status: ${STATUS}   ${ICON_LOGS} Mode: ${DEBUG_MODE}   ${ICON_RUST} Tunnels: ${HI_GREEN}${C_TUNNELS}${NC}"

    draw_line
    echo ""

    print_option "1" "$ICON_ROCKET" "Add Relay" "TCP + UDP Forward"
    print_option "2" "$ICON_TRASH" "Delete Relay" "Remove Active"
    print_option "3" "$ICON_NET" "Show Config" "View TOML File"
    print_option "4" "$ICON_GEAR" "Edit Config" "Manual (Nano)"
    print_option "5" "$ICON_LOGS" "Logs" "Disk & Debug"
    print_option "6" "$ICON_RESTART" "Auto-Restart" "Watchdog (Light)"
    print_option "7" "$ICON_TRASH" "Uninstall" "Remove All"
    print_option "0" "$ICON_EXIT" "Exit" "Close Script"

    echo ""
    draw_line
    printf "  ${HI_PINK}➤ Select Option : ${NC}"
}

# ==================================================
#  DEPENDENCIES & REALM
# ==================================================

install_dependencies() {
    local NEED_INSTALL=false
    if ! command -v systemctl >/dev/null 2>&1; then
        echo -e "${RED}systemd/systemctl is required but not found.${NC}"
        exit 1
    fi

    if ! command -v curl &> /dev/null || ! command -v lsof &> /dev/null || ! command -v nc &> /dev/null; then
        NEED_INSTALL=true
    fi

    if [ "$NEED_INSTALL" = true ]; then
        install_core_dependencies || exit 1
    fi

    if ! command -v realm &> /dev/null; then
        echo -e "${BLUE}Downloading Realm (Rust)...${NC}"
        
        # Determine Architecture
        local ARCH_RAW RELEASE_FILE
        ARCH_RAW=$(uname -m)
        if [[ "$ARCH_RAW" == "x86_64" ]]; then
            RELEASE_FILE="realm-x86_64-unknown-linux-gnu.tar.gz"
        elif [[ "$ARCH_RAW" == "aarch64" ]]; then
            RELEASE_FILE="realm-aarch64-unknown-linux-gnu.tar.gz"
        else
            echo -e "${RED}Unsupported architecture: $ARCH_RAW${NC}"
            exit 1
        fi

        local DL_URL="https://github.com/zhboner/realm/releases/latest/download/$RELEASE_FILE"
        local TMP_DIR
        TMP_DIR=$(mktemp -d)

        echo -e "  ${YELLOW}Fetching from GitHub...${NC}"
        if curl -L -o "$TMP_DIR/realm.tar.gz" -fsSL "$DL_URL"; then
            tar -xf "$TMP_DIR/realm.tar.gz" -C "$TMP_DIR"
            mv "$TMP_DIR/realm" "$REALM_BIN"
            chmod +x "$REALM_BIN"
            rm -rf "$TMP_DIR"
            echo -e "${HI_GREEN}Realm installed successfully.${NC}"
        else
            echo -e "${RED}Download failed. Check internet connection.${NC}"
            rm -rf "$TMP_DIR"
            exit 1
        fi
    fi

    mkdir -p "$CONFIG_DIR"
    
    # Initialize Config if missing
    if [ ! -f "$CONFIG_FILE" ]; then
        echo "[network]" > "$CONFIG_FILE"
        echo "no_tcp = false" >> "$CONFIG_FILE"
        echo "use_udp = true" >> "$CONFIG_FILE"
        echo "" >> "$CONFIG_FILE"
    fi
}

setup_shortcut() {
    if [ ! -s "$SHORTCUT_BIN" ]; then
        echo ""
        draw_line
        echo -e "  ${ICON_INSTALL}  ${BOLD}Setup 'irealm' Shortcut?${NC}"
        echo -e "  ${BLUE}Allows you to run the manager by typing 'irealm'.${NC}"
        echo ""

        echo -ne "  ${HI_PINK}➤ Install (y/yes to confirm)? : ${NC}"
        read -r install_opt
        install_opt=${install_opt:-y}

        if confirm_yes "$install_opt"; then
            echo -e "  ${YELLOW}Downloading script to $SHORTCUT_BIN...${NC}"
            
            # اینجا مطمئن می‌شویم که REPO_URL تعریف شده باشد
            if [ -z "$REPO_URL" ]; then
                REPO_URL="https://raw.githubusercontent.com/Sir-Adnan/Realm-Tunnel-Manager/main/realm.sh"
            fi

            curl -L -o "$SHORTCUT_BIN" -fsSL "$REPO_URL"
            
            if [ -s "$SHORTCUT_BIN" ]; then
                chmod +x "$SHORTCUT_BIN"
                echo -e "  ${HI_GREEN}✔ Installed! Type 'irealm' to run.${NC}"
                sleep 2
            else
                echo -e "  ${RED}✖ Download failed. Check internet connection.${NC}"
                sleep 2
            fi
        fi
    fi
}

check_port_safety() {
    local port=$1
    if grep -q "listen =.*:$port\"" "$CONFIG_FILE"; then
        echo -e "  ${RED}✖ Port $port is already in config!${NC}"; return 1
    fi
    if lsof -i :"$port" > /dev/null 2>&1; then
        echo -e "  ${RED}✖ Port $port is busy in system!${NC}"; return 1
    fi
    return 0
}

apply_config() {
    echo -e "\n${BLUE}--- Reloading Service ---${NC}"
    systemctl restart realm
    sleep 1
    if systemctl is-active --quiet realm; then
        echo -e "  ${HI_GREEN}✔ Success! Service is running.${NC}"
        read -r -p "  Press Enter to continue..."
    else
        echo -e "  ${RED}✖ Failed! Check config syntax.${NC}"
        journalctl -u realm -n 5 --no-pager
        read -r -p "  Press Enter..."
    fi
    LAST_STATS_TS=0
}

# ==================================================
#  SYSTEMD SERVICE
# ==================================================

create_service() {
    cat <<EOF > "$SERVICE_FILE"
[Unit]
Description=Realm Relay Service (Rust)
After=network-online.target
Wants=network-online.target systemd-networkd-wait-online.service

[Service]
Type=simple
User=root
ExecStart=$REALM_BIN -c $CONFIG_FILE

# --- TOTAL SILENCE ---
StandardOutput=null
StandardError=null

Restart=always
RestartSec=3
LimitNOFILE=1048576

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl enable realm >/dev/null 2>&1
}

# ==================================================
#  LOG OPTIMIZATION
# ==================================================

auto_clean_logs() {
    local MAX_USE="120M"
    local KEEP_FREE="200M"
    local MAX_FILE="20M"
    local policy

    if [ ! -f "$LOG_POLICY_STATE_FILE" ]; then
        # Default enable for performance
        echo "enabled" > "$LOG_POLICY_STATE_FILE"
    fi

    policy=$(cat "$LOG_POLICY_STATE_FILE" 2>/dev/null)
    if [[ "$policy" == "enabled" ]]; then
        apply_journald_limits "$MAX_USE" "$KEEP_FREE" "$MAX_FILE"
    fi
}

toggle_debug_mode() {
    echo ""
    if grep -q "^StandardOutput=null" "$SERVICE_FILE" 2>/dev/null; then
        sed -i 's/^StandardOutput=null/StandardOutput=journal/' "$SERVICE_FILE"
        sed -i 's/^StandardError=null/StandardError=journal/' "$SERVICE_FILE"
        systemctl daemon-reload
        systemctl restart realm
        echo -e "  ${YELLOW}⚠ DEBUG MODE ENABLED.${NC}"
    else
        sed -i 's/^StandardOutput=journal/StandardOutput=null/' "$SERVICE_FILE"
        sed -i 's/^StandardError=journal/StandardError=null/' "$SERVICE_FILE"
        systemctl daemon-reload
        systemctl restart realm
        echo -e "  ${HI_GREEN}✔ SILENT MODE ENABLED.${NC}"
    fi
    sleep 2
}

# ==================================================
#  CORE FUNCTIONS
# ==================================================

add_relay() {
    draw_dashboard
    section_title "ADD RELAY"
    show_guide "Realm Forwarding" \
    "Transfers TCP & UDP traffic with Zero-Copy.\n  ${BOLD}Usage:${NC} Perfect for tunneling to GRE/Kharej server."

    echo ""
    ask_input "Local Port"; read -r lport
    validate_port "$lport" || { echo -e "  ${RED}Bad Port${NC}"; sleep 1; return; }
    check_port_safety "$lport" || { sleep 1; return; }

    echo ""
    ask_input "Remote IP"; read -r raw_ip
    dip=$(normalize_ip "$raw_ip")
    ask_input "Remote Port"; read -r dport
    validate_port "$dport" || { echo -e "  ${RED}Bad Dest Port${NC}"; sleep 1; return; }

    backup_config
    
    # Append to TOML
    echo "" >> "$CONFIG_FILE"
    echo "[[endpoints]]" >> "$CONFIG_FILE"
    echo "listen = \"0.0.0.0:$lport\"" >> "$CONFIG_FILE"
    echo "remote = \"$dip:$dport\"" >> "$CONFIG_FILE"

    apply_config
}

delete_relay() {
    draw_dashboard
    section_title "DELETE RELAY"
    
    # Extract Listening ports for display
    # Grep 'listen' lines, remove quotes/text, sort
    mapfile -t ports < <(grep "listen =" "$CONFIG_FILE" | grep -oE "[0-9]+" | sort -u)

    if [ ${#ports[@]} -eq 0 ]; then
        echo -e "  ${YELLOW}No active relays found.${NC}"
        sleep 1
        return
    fi

    printf "  ${BLUE}%-6s %-15s${NC}\n" "ID" "LOCAL PORT"
    echo -e "  ${BLUE}──────────────────────${NC}"
    
    local i=0
    for port in "${ports[@]}"; do
        printf "  ${HI_CYAN}[%d]${NC}    ${BOLD}%-15s${NC}\n" "$i" "$port"
        ((i++))
    done

    echo ""
    ask_input "Enter ID (c to cancel)"; read -r idx
    [[ "$idx" == "c" || "$idx" == "C" ]] && return

    if [[ "$idx" =~ ^[0-9]+$ ]] && [ "$idx" -lt "${#ports[@]}" ]; then
        local target_port="${ports[$idx]}"
        backup_config
        
        # Logic to delete block in TOML using sed
        # We look for the listen line, then try to delete the surrounding block
        # Since TOML blocks start with [[endpoints]], we delete from [[endpoints]] 
        # that contains our port until the next [[endpoints]] or EOF.
        
        # Simple approach: Read file, exclude the block matching the port
        # Using a temporary file
        local tmp_conf=$(mktemp)
        local skip=0
        
        while IFS= read -r line; do
            if [[ "$line" == "[[endpoints]]" ]]; then
                skip=0 # Reset skip on new block header start
            fi
            
            # Check if this block is the one we want to delete (peek ahead logic is hard in shell)
            # Alternate logic: Use specific sed pattern
            
        done < "$CONFIG_FILE"
        
        # Better Sed approach:
        # 1. Find line number of the port
        local line_num
        line_num=$(grep -n "listen = \"0.0.0.0:$target_port\"" "$CONFIG_FILE" | cut -d: -f1 | head -n1)
        
        if [[ -n "$line_num" ]]; then
            # Delete the line before (header) and the 2 lines after (config)
            # Assuming standard 3-4 line block structure created by this script
            local start_del=$((line_num - 1))
            local end_del=$((line_num + 2))
            sed -i "${start_del},${end_del}d" "$CONFIG_FILE"
            
            # Clean up empty newlines
            sed -i '/^\s*$/d' "$CONFIG_FILE"
            
            apply_config
        else
            echo -e "  ${RED}Error locating block.${NC}"
            sleep 1
        fi
    fi
}

show_config() {
    clear
    section_title "CURRENT CONFIG (TOML)"
    cat "$CONFIG_FILE" | less
}

# ==================================================
#  WATCHDOG
# ==================================================

setup_watchdog() {
    draw_dashboard
    section_title "REALM WATCHDOG"
    
    local cores
    cores=$(nproc 2>/dev/null)
    [[ -z "$cores" || "$cores" -le 0 ]] && cores=1
    local default_threshold=$((cores * 4)) # Realm is efficient, allow higher load

    echo -e "  ${YELLOW}Default threshold = ${default_threshold}${NC}"
    ask_input "Enable Watchdog? (y/yes)"; read -r confirm
    confirm=${confirm:-y}
    if ! confirm_yes "$confirm"; then return; fi

    ask_input "Load threshold"; read -r thr
    [[ -z "$thr" ]] && thr="$default_threshold"

    if ! command -v crontab >/dev/null 2>&1; then
        echo -e "  ${RED}crontab not found.${NC}"; sleep 2; return
    fi

    cat <<'EOF' > /usr/local/bin/realm_watchdog.sh
#!/bin/bash
THRESHOLD_FILE="/etc/realm/watchdog_threshold"
LOG="/var/log/realm_watchdog.log"
thr=4
if [ -f "$THRESHOLD_FILE" ]; then thr=$(cat "$THRESHOLD_FILE" | tr -dc '0-9'); fi
load1=$(awk '{print int($1)}' /proc/loadavg)
if [ "$load1" -ge "$thr" ]; then
  systemctl restart realm
  echo "$(date): Load High (${load1}). Restarted." >> "$LOG"
fi
EOF
    chmod +x /usr/local/bin/realm_watchdog.sh
    echo "$thr" > /etc/realm/watchdog_threshold

    (crontab -l 2>/dev/null; echo "* * * * * /usr/local/bin/realm_watchdog.sh") | sort -u | crontab -

    cat <<EOF > "$WATCHDOG_LOGROTATE_FILE"
/var/log/realm_watchdog.log {
    weekly
    rotate 2
    compress
    missingok
    copytruncate
}
EOF
    echo -e "\n  ${HI_GREEN}✔ Watchdog Activated.${NC}"
    sleep 2
}

menu_uninstall() {
    draw_dashboard
    section_title "UNINSTALL REALM MANAGER"
    echo -e "  ${RED}⚠ WARNING: Removes Realm, Configs, Logs!${NC}"
    ask_input "Confirm (y/yes)"; read -r c
    if confirm_yes "$c"; then
        systemctl stop realm >/dev/null 2>&1
        systemctl disable realm >/dev/null 2>&1
        rm -f /usr/local/bin/realm_watchdog.sh
        rm -f "$WATCHDOG_LOGROTATE_FILE"
        crontab -l 2>/dev/null | grep -v "realm_watchdog.sh" | crontab - 2>/dev/null
        rm -rf "$CONFIG_DIR" "$SERVICE_FILE" "$SHORTCUT_BIN" "$REALM_BIN"
        systemctl daemon-reload
        echo -e "\n  ${HI_GREEN}✔ Uninstalled.${NC}"
        exit 0
    fi
}

menu_exit() {
    clear
    echo -e "\n  ${HI_PINK}Goodbye! 👋${NC}"
    exit 0
}

# ==================================================
#  LOGS MENU
# ==================================================

logs_menu() {
    while true; do
        draw_dashboard
        section_title "LOGS CONTROL"
        
        echo -e "  ${HI_CYAN}[1]${NC} Follow Realm Logs (Live)"
        echo -e "  ${HI_CYAN}[2]${NC} Journal Disk Usage"
        echo -e "  ${HI_CYAN}[3]${NC} Vacuum Logs"
        echo -e "  ${HI_CYAN}[4]${NC} Toggle Debug Mode (ON/OFF)"
        echo -e "  ${HI_CYAN}[0]${NC} Back"
        echo ""
        draw_line
        ask_input "Select"; read -r lopt

        case $lopt in
            1) journalctl -u realm -f ;;
            2) journalctl --disk-usage; read -r -p "  Press Enter..." ;;
            3) journalctl --vacuum-size=100M; read -r -p "  Press Enter..." ;;
            4) toggle_debug_mode ;;
            0) return ;;
        esac
    done
}

# ==================================================
#  MAIN LOOP
# ==================================================

install_dependencies
create_service
auto_clean_logs
setup_shortcut

while true; do
    draw_dashboard
    read -r opt
    case $opt in
        1) add_relay ;;
        2) delete_relay ;;
        3) show_config ;;
        4) backup_config; nano "$CONFIG_FILE"; apply_config ;;
        5) logs_menu ;;
        6) setup_watchdog ;;
        7) menu_uninstall ;;
        0) menu_exit ;;
        *) sleep 0.3 ;;
    esac
done
