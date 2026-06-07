#!/bin/bash
# =============================================================================
#  PRE-PATCH SNAPSHOT SCRIPT
#  Supports: RHEL / CentOS / Rocky / AlmaLinux | SUSE / SLES | Ubuntu / Debian
#  Author  : Linux Admin Team
#  Version : 1.0
# =============================================================================

# ─── Strict mode ──────────────────────────────────────────────────────────────
set -uo pipefail

# ─── Root check ───────────────────────────────────────────────────────────────
if [ "${EUID:-$(id -u)}" -ne 0 ]; then
    echo "ERROR: This script must be run as root (sudo)." >&2
    exit 1
fi

# ─── Colors ───────────────────────────────────────────────────────────────────
RED='\033[0;31m';    GREEN='\033[0;32m';   YELLOW='\033[1;33m'
BLUE='\033[0;34m';   CYAN='\033[0;36m';    WHITE='\033[1;37m'
BOLD='\033[1m';      DIM='\033[2m';        RESET='\033[0m'
BG_DARK='\033[48;5;234m'

# ─── Base Paths ───────────────────────────────────────────────────────────────
BASE_DIR="/opt/patch-audit"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
HOSTNAME_SHORT=$(hostname -s)
SNAPSHOT_DIR="${BASE_DIR}/snapshots/${HOSTNAME_SHORT}_pre_${TIMESTAMP}"
REPORT_DIR="${BASE_DIR}/reports"
HTML_REPORT="${REPORT_DIR}/${HOSTNAME_SHORT}_pre_${TIMESTAMP}.html"
LOG_FILE="${SNAPSHOT_DIR}/snapshot.log"
START_TIME=$(date +%s)

# ─── Setup Directories ────────────────────────────────────────────────────────
mkdir -p "$SNAPSHOT_DIR" "$REPORT_DIR"

# ─── Logging ──────────────────────────────────────────────────────────────────
log() { echo "$1" | tee -a "$LOG_FILE"; }

# ─── OS Detection ─────────────────────────────────────────────────────────────
detect_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS_NAME="$NAME"
        OS_ID="$ID"
        OS_VERSION="${VERSION_ID:-unknown}"
        OS_PRETTY="${PRETTY_NAME:-$NAME}"
    else
        OS_NAME="Unknown"; OS_ID="unknown"; OS_VERSION="unknown"; OS_PRETTY="Unknown Linux"
    fi
    case "$OS_ID" in
        rhel|centos|rocky|almalinux|fedora) OS_FAMILY="rhel" ;;
        sles|opensuse|opensuse-leap|opensuse-tumbleweed) OS_FAMILY="suse" ;;
        ubuntu|debian|linuxmint) OS_FAMILY="debian" ;;
        *) OS_FAMILY="unknown" ;;
    esac
}

# ─── Print Banner ─────────────────────────────────────────────────────────────
print_banner() {
    clear
    echo -e "${BOLD}${CYAN}"
    echo "  ╔══════════════════════════════════════════════════════════════════╗"
    echo "  ║            PRE-PATCH CONFIGURATION SNAPSHOT TOOL                ║"
    echo "  ║                  Linux Infrastructure Team                      ║"
    echo "  ╚══════════════════════════════════════════════════════════════════╝${RESET}"
    echo ""
    echo -e "  ${WHITE}${BOLD}Server   :${RESET}  ${GREEN}$(hostname -f)${RESET}"
    echo -e "  ${WHITE}${BOLD}OS       :${RESET}  ${GREEN}${OS_PRETTY}${RESET}"
    echo -e "  ${WHITE}${BOLD}Date     :${RESET}  ${GREEN}$(date '+%Y-%m-%d %H:%M:%S')${RESET}"
    echo -e "  ${WHITE}${BOLD}Snapshot :${RESET}  ${DIM}${SNAPSHOT_DIR}${RESET}"
    echo -e "  ${WHITE}${BOLD}Report   :${RESET}  ${DIM}${HTML_REPORT}${RESET}"
    echo ""
    echo -e "  ${DIM}──────────────────────────────────────────────────────────────────${RESET}"
    echo ""
}

# ─── Status Printer ───────────────────────────────────────────────────────────
print_status() {
    local label="$1"
    local status="$2"
    local detail="$3"
    local padded=$(printf "%-35s" "$label")
    if [ "$status" = "OK" ]; then
        echo -e "  ${GREEN}[✔]${RESET} ${WHITE}${padded}${RESET} ${GREEN}CAPTURED${RESET}  ${DIM}${detail}${RESET}"
    elif [ "$status" = "SKIP" ]; then
        echo -e "  ${YELLOW}[~]${RESET} ${WHITE}${padded}${RESET} ${YELLOW}SKIPPED${RESET}   ${DIM}${detail}${RESET}"
    else
        echo -e "  ${RED}[✘]${RESET} ${WHITE}${padded}${RESET} ${RED}FAILED${RESET}    ${DIM}${detail}${RESET}"
    fi
}

print_section() {
    echo ""
    echo -e "  ${BOLD}${BLUE}▶  $1${RESET}"
    echo -e "  ${DIM}  ──────────────────────────────────────────${RESET}"
}

# =============================================================================
#  CAPTURE FUNCTIONS
# =============================================================================

# 01 — OS & System Info
capture_os_info() {
    local f="${SNAPSHOT_DIR}/01_os_info.txt"
    {
        echo "=== OS INFORMATION ==="
        echo "Hostname         : $(hostname -f)"
        echo "Short Hostname   : $(hostname -s)"
        echo "OS Name          : ${OS_PRETTY}"
        echo "OS Family        : ${OS_FAMILY}"
        echo "OS Version       : ${OS_VERSION}"
        echo "OS ID            : ${OS_ID}"
        echo "Capture Date     : $(date '+%Y-%m-%d %H:%M:%S')"
        echo "Timezone         : $(timedatectl 2>/dev/null | grep 'Time zone' | awk '{print $3}' || date +%Z)"
        echo "System Locale    : $(locale 2>/dev/null | grep LANG= | head -1)"
        echo ""
        echo "=== UPTIME & LOAD ==="
        uptime
        echo ""
        echo "=== LAST REBOOT ==="
        last reboot | head -5
        echo ""
        echo "=== WHO IS LOGGED IN ==="
        who
    } > "$f" 2>&1
    print_status "OS & System Information" "OK" "$(hostname -f) | ${OS_PRETTY}"
}

# 02 — Kernel
capture_kernel() {
    local f="${SNAPSHOT_DIR}/02_kernel.txt"
    {
        echo "=== CURRENT KERNEL ==="
        uname -r
        echo ""
        echo "=== FULL UNAME ==="
        uname -a
        echo ""
        echo "=== INSTALLED KERNELS ==="
        case "$OS_FAMILY" in
            rhel)  rpm -qa | grep -E "^kernel-[0-9]" | sort ;;
            suse)  rpm -qa | grep -E "^kernel-" | sort ;;
            debian) dpkg -l | grep -E "linux-image" | awk '{print $2,$3}' ;;
        esac
        echo ""
        echo "=== KERNEL MODULES LOADED ==="
        lsmod | head -60
        echo ""
        echo "=== KERNEL PARAMETERS (sysctl) ==="
        sysctl -a 2>/dev/null | sort
    } > "$f" 2>&1
    local kver=$(uname -r)
    print_status "Kernel Information" "OK" "Running: ${kver}"
}

# 03 — CPU
capture_cpu() {
    local f="${SNAPSHOT_DIR}/03_cpu.txt"
    {
        echo "=== CPU SUMMARY ==="
        lscpu
        echo ""
        echo "=== CPU COUNT ==="
        echo "Physical CPUs    : $(lscpu | grep '^Socket(s):' | awk '{print $2}')"
        echo "Cores per Socket : $(lscpu | grep '^Core(s) per socket:' | awk '{print $4}')"
        echo "Total vCPUs      : $(nproc)"
        echo "Threads per Core : $(lscpu | grep '^Thread(s) per core:' | awk '{print $4}')"
        echo ""
        echo "=== CPU INFO (raw) ==="
        cat /proc/cpuinfo | grep -E "processor|model name|cpu MHz|cache size|physical id|core id" | sort -u
        echo ""
        echo "=== CURRENT CPU USAGE ==="
        top -bn1 | head -5
        echo ""
        echo "=== LOAD AVERAGE ==="
        cat /proc/loadavg
    } > "$f" 2>&1
    local cpus=$(nproc)
    local model=$(lscpu | grep "Model name" | head -1 | sed 's/Model name.*: *//')
    print_status "CPU Information" "OK" "${cpus} vCPUs | ${model:0:40}"
}

# 04 — Memory & Swap
capture_memory() {
    local f="${SNAPSHOT_DIR}/04_memory.txt"
    {
        echo "=== MEMORY OVERVIEW ==="
        free -h
        echo ""
        echo "=== MEMORY DETAILS (bytes) ==="
        free -b
        echo ""
        echo "=== /proc/meminfo ==="
        cat /proc/meminfo
        echo ""
        echo "=== SWAP DETAILS ==="
        swapon --show 2>/dev/null || echo "No swap configured"
        echo ""
        echo "=== TOP MEMORY CONSUMERS ==="
        ps aux --sort=-%mem | head -15
    } > "$f" 2>&1
    local memtotal=$(free -h | grep Mem | awk '{print $2}')
    local memused=$(free -h | grep Mem | awk '{print $3}')
    print_status "Memory & Swap" "OK" "Total: ${memtotal} | Used: ${memused}"
}

# 05 — Disk & Storage
capture_disk() {
    local f="${SNAPSHOT_DIR}/05_disk.txt"
    {
        echo "=== DISK USAGE (df) ==="
        df -hT
        echo ""
        echo "=== DISK USAGE (inodes) ==="
        df -i
        echo ""
        echo "=== BLOCK DEVICES ==="
        lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINT,MODEL,VENDOR,SERIAL 2>/dev/null || lsblk
        echo ""
        echo "=== NUMBER OF DISKS ==="
        echo "Physical disks   : $(lsblk -d -o NAME,TYPE | grep -c disk)"
        lsblk -d -o NAME,SIZE,TYPE,MODEL | grep disk
        echo ""
        echo "=== DISK DETAILS (fdisk) ==="
        fdisk -l 2>/dev/null | grep -E "^Disk /dev|^Disk identifier|sectors"
        echo ""
        echo "=== FSTAB ==="
        cat /etc/fstab
        echo ""
        echo "=== CURRENT MOUNTS ==="
        findmnt --real
        echo ""
        echo "=== LVM — Physical Volumes ==="
        pvs 2>/dev/null || echo "LVM not in use or pvs not available"
        echo ""
        echo "=== LVM — Volume Groups ==="
        vgs 2>/dev/null || echo "LVM not in use or vgs not available"
        echo ""
        echo "=== LVM — Logical Volumes ==="
        lvs 2>/dev/null || echo "LVM not in use or lvs not available"
        echo ""
        echo "=== MULTIPATH STATUS ==="
        multipath -ll 2>/dev/null || echo "Multipath not configured"
        echo ""
        echo "=== NFS / CIFS MOUNTS ==="
        mount | grep -E "nfs|cifs|smb" || echo "No NFS/CIFS mounts found"
    } > "$f" 2>&1
    local disks=$(lsblk -d -o NAME,TYPE 2>/dev/null | grep -c disk)
    local dfout=$(df -h / | tail -1 | awk '{print $3"/"$2" ("$5" used)"}')
    print_status "Disk & Storage" "OK" "${disks} disk(s) | Root: ${dfout}"
}

# 06 — Network
capture_network() {
    local f="${SNAPSHOT_DIR}/06_network.txt"
    {
        echo "=== HOSTNAME & FQDN ==="
        echo "Hostname : $(hostname)"
        echo "FQDN     : $(hostname -f 2>/dev/null || hostname)"
        echo ""
        echo "=== NETWORK INTERFACES ==="
        ip addr show
        echo ""
        echo "=== ROUTING TABLE ==="
        ip route show
        echo ""
        echo "=== ARP TABLE ==="
        arp -n 2>/dev/null || ip neigh show
        echo ""
        echo "=== DNS CONFIGURATION ==="
        cat /etc/resolv.conf
        echo ""
        echo "=== /etc/hosts ==="
        cat /etc/hosts
        echo ""
        echo "=== NETWORK BONDING/TEAMING ==="
        cat /proc/net/bonding/* 2>/dev/null || echo "No bonding configured"
        echo ""
        echo "=== NETWORK INTERFACE STATS ==="
        ip -s link show
    } > "$f" 2>&1
    local ips=$(ip -4 addr show | grep inet | grep -v 127 | awk '{print $2}' | tr '\n' ' ')
    print_status "Network Configuration" "OK" "${ips}"
}

# 07 — Open Ports
capture_ports() {
    local f="${SNAPSHOT_DIR}/07_ports.txt"
    {
        echo "=== OPEN PORTS & LISTENING SERVICES ==="
        ss -tulpn 2>/dev/null || netstat -tulpn 2>/dev/null
        echo ""
        echo "=== ALL ESTABLISHED CONNECTIONS ==="
        ss -tnp 2>/dev/null | head -40
        echo ""
        echo "=== SOCKET SUMMARY ==="
        ss -s 2>/dev/null
    } > "$f" 2>&1
    local portcount=$(ss -tulpn 2>/dev/null | grep -c LISTEN || echo "?")
    print_status "Open Ports & Connections" "OK" "${portcount} listening port(s)"
}

# 08 — Firewall
capture_firewall() {
    local f="${SNAPSHOT_DIR}/08_firewall.txt"
    {
        echo "=== FIREWALL STATUS ==="
        if command -v firewall-cmd &>/dev/null; then
            echo "--- FirewallD ---"
            firewall-cmd --state 2>/dev/null
            firewall-cmd --list-all 2>/dev/null
            firewall-cmd --list-all-zones 2>/dev/null
        fi
        if command -v ufw &>/dev/null; then
            echo "--- UFW ---"
            ufw status verbose 2>/dev/null
        fi
        echo ""
        echo "=== IPTABLES RULES ==="
        iptables -L -n -v 2>/dev/null || echo "iptables not available"
        echo ""
        echo "=== IP6TABLES RULES ==="
        ip6tables -L -n -v 2>/dev/null || echo "ip6tables not available"
    } > "$f" 2>&1
    print_status "Firewall Rules" "OK" "firewalld/iptables/ufw captured"
}

# 09 — Installed Packages
capture_packages() {
    local f="${SNAPSHOT_DIR}/09_packages.txt"
    {
        echo "=== INSTALLED PACKAGES ==="
        case "$OS_FAMILY" in
            rhel)
                rpm -qa --queryformat '%{NAME}|%{VERSION}|%{RELEASE}|%{ARCH}\n' | sort
                ;;
            suse)
                rpm -qa --queryformat '%{NAME}|%{VERSION}|%{RELEASE}|%{ARCH}\n' | sort
                ;;
            debian)
                dpkg-query -W -f='${Package}|${Version}|${Architecture}\n' | sort
                ;;
        esac
        echo ""
        echo "=== PACKAGE COUNT ==="
        case "$OS_FAMILY" in
            rhel|suse) echo "Total: $(rpm -qa | wc -l) packages" ;;
            debian)    echo "Total: $(dpkg -l | grep '^ii' | wc -l) packages" ;;
        esac
        echo ""
        echo "=== PATCH / UPDATE HISTORY ==="
        case "$OS_FAMILY" in
            rhel)
                dnf history list 2>/dev/null | head -30 || yum history list 2>/dev/null | head -30
                ;;
            suse)
                zypper patches 2>/dev/null | head -30
                cat /var/log/zypp/history 2>/dev/null | tail -50
                ;;
            debian)
                grep -E "install|upgrade|remove" /var/log/apt/history.log 2>/dev/null | tail -50
                ;;
        esac
        echo ""
        echo "=== PENDING UPDATES ==="
        case "$OS_FAMILY" in
            rhel)  dnf check-update 2>/dev/null | head -30 || yum check-update 2>/dev/null | head -30 ;;
            suse)  zypper list-updates 2>/dev/null | head -30 ;;
            debian) apt list --upgradable 2>/dev/null | head -30 ;;
        esac
    } > "$f" 2>&1
    local pkgcount
    case "$OS_FAMILY" in
        rhel|suse) pkgcount=$(rpm -qa | wc -l) ;;
        debian)    pkgcount=$(dpkg -l | grep '^ii' | wc -l) ;;
        *)         pkgcount="?" ;;
    esac
    print_status "Installed Packages" "OK" "${pkgcount} packages installed"
}

# 10 — Running Services
capture_services() {
    local f="${SNAPSHOT_DIR}/10_services.txt"
    {
        echo "=== ALL SYSTEMD SERVICES (enabled) ==="
        systemctl list-unit-files --type=service --state=enabled 2>/dev/null
        echo ""
        echo "=== RUNNING SERVICES ==="
        systemctl list-units --type=service --state=running 2>/dev/null
        echo ""
        echo "=== FAILED SERVICES ==="
        systemctl list-units --state=failed 2>/dev/null
        echo ""
        echo "=== ALL UNIT FILES ==="
        systemctl list-unit-files 2>/dev/null
    } > "$f" 2>&1
    local running=$(systemctl list-units --type=service --state=running 2>/dev/null | grep -c "running" || echo "?")
    local failed=$(systemctl list-units --state=failed 2>/dev/null | grep -c "failed" || echo "0")
    print_status "Systemd Services" "OK" "${running} running | ${failed} failed"
}

# 11 — SELinux / AppArmor
capture_security_policy() {
    local f="${SNAPSHOT_DIR}/11_selinux_apparmor.txt"
    {
        echo "=== SELinux STATUS ==="
        if command -v getenforce &>/dev/null; then
            getenforce
            sestatus 2>/dev/null
            echo ""
            echo "SELinux Config:"
            cat /etc/selinux/config 2>/dev/null
        else
            echo "SELinux not installed"
        fi
        echo ""
        echo "=== AppArmor STATUS ==="
        if command -v apparmor_status &>/dev/null; then
            apparmor_status 2>/dev/null
        elif command -v aa-status &>/dev/null; then
            aa-status 2>/dev/null
        else
            echo "AppArmor not installed"
        fi
    } > "$f" 2>&1
    local selinux_status="N/A"
    command -v getenforce &>/dev/null && selinux_status=$(getenforce 2>/dev/null)
    print_status "SELinux / AppArmor" "OK" "SELinux: ${selinux_status}"
}

# 12 — Cron Jobs
capture_cron() {
    local f="${SNAPSHOT_DIR}/12_cron.txt"
    {
        echo "=== SYSTEM CRONTAB ==="
        cat /etc/crontab 2>/dev/null
        echo ""
        echo "=== CRON.D DIRECTORY ==="
        ls -la /etc/cron.d/ 2>/dev/null
        for cf in /etc/cron.d/*; do
            echo "--- $cf ---"
            cat "$cf" 2>/dev/null
        done
        echo ""
        echo "=== CRON DIRECTORIES ==="
        echo "-- cron.hourly --"
        ls -la /etc/cron.hourly/ 2>/dev/null
        echo "-- cron.daily --"
        ls -la /etc/cron.daily/ 2>/dev/null
        echo "-- cron.weekly --"
        ls -la /etc/cron.weekly/ 2>/dev/null
        echo "-- cron.monthly --"
        ls -la /etc/cron.monthly/ 2>/dev/null
        echo ""
        echo "=== ROOT CRONTAB ==="
        crontab -l 2>/dev/null || echo "No root crontab"
        echo ""
        echo "=== ALL USER CRONTABS ==="
        for user in $(cut -d: -f1 /etc/passwd); do
            crontab -l -u "$user" 2>/dev/null && echo "[user: $user]"
        done
        echo ""
        echo "=== SYSTEMD TIMERS ==="
        systemctl list-timers --all 2>/dev/null
    } > "$f" 2>&1
    print_status "Cron Jobs & Timers" "OK" "system + user crontabs captured"
}

# 13 — User Accounts & Sudo
capture_users() {
    local f="${SNAPSHOT_DIR}/13_users.txt"
    {
        echo "=== ALL USER ACCOUNTS ==="
        cat /etc/passwd
        echo ""
        echo "=== ALL GROUPS ==="
        cat /etc/group
        echo ""
        echo "=== SUDO CONFIGURATION ==="
        cat /etc/sudoers 2>/dev/null
        echo ""
        echo "=== SUDOERS.D ==="
        ls -la /etc/sudoers.d/ 2>/dev/null
        for f2 in /etc/sudoers.d/*; do
            echo "--- $f2 ---"
            cat "$f2" 2>/dev/null
        done
        echo ""
        echo "=== USERS WITH LOGIN SHELL ==="
        grep -vE '/nologin|/false|/sync' /etc/passwd | grep -v '^#'
        echo ""
        echo "=== USERS WITH UID 0 (root equiv) ==="
        awk -F: '$3==0 {print $1}' /etc/passwd
        echo ""
        echo "=== PASSWORD AGING ==="
        chage -l root 2>/dev/null
        echo ""
        echo "=== LAST LOGINS ==="
        last | head -20
        echo ""
        echo "=== FAILED LOGIN ATTEMPTS ==="
        lastb 2>/dev/null | head -10 || echo "lastb requires root or not available"
        echo ""
        echo "=== SSH AUTHORIZED KEYS (root) ==="
        cat /root/.ssh/authorized_keys 2>/dev/null || echo "None or not accessible"
    } > "$f" 2>&1
    local usercount=$(grep -vE '/nologin|/false' /etc/passwd | grep -v '^#' | wc -l)
    print_status "User Accounts & Sudo" "OK" "${usercount} login-capable accounts"
}

# 14 — /etc Config Checksums
capture_etc_checksums() {
    local f="${SNAPSHOT_DIR}/14_etc_checksums.txt"
    {
        echo "=== /etc CONFIGURATION FILE CHECKSUMS (MD5) ==="
        echo "Generated: $(date)"
        echo ""
        find /etc -type f -readable 2>/dev/null | sort | while read fpath; do
            md5sum "$fpath" 2>/dev/null
        done
    } > "$f" 2>&1
    local count=$(wc -l < "$f")
    print_status "/etc Config Checksums" "OK" "${count} files checksummed"
}

# 15 — RPM/DPKG Integrity
capture_package_integrity() {
    local f="${SNAPSHOT_DIR}/15_pkg_integrity.txt"
    {
        echo "=== PACKAGE INTEGRITY VERIFICATION ==="
        case "$OS_FAMILY" in
            rhel|suse)
                echo "--- RPM Verify (changed files) ---"
                rpm -Va 2>/dev/null | head -100
                ;;
            debian)
                echo "--- DPKG Verify ---"
                dpkg --verify 2>/dev/null | head -100 || echo "dpkg --verify not supported on this version"
                ;;
        esac
    } > "$f" 2>&1
    print_status "Package Integrity Check" "OK" "RPM/DPKG verify complete"
}

# 16 — Key Log Baselines
capture_logs() {
    local f="${SNAPSHOT_DIR}/16_log_baseline.txt"
    {
        echo "=== SYSTEM LOG BASELINE (last 50 lines) ==="
        echo ""
        echo "--- /var/log/messages or syslog ---"
        tail -50 /var/log/messages 2>/dev/null || tail -50 /var/log/syslog 2>/dev/null || echo "Not available"
        echo ""
        echo "--- /var/log/dmesg (kernel ring buffer) ---"
        dmesg | tail -50 2>/dev/null
        echo ""
        echo "--- Journalctl (last 50) ---"
        journalctl -n 50 --no-pager 2>/dev/null
        echo ""
        echo "--- Auth log (last 30) ---"
        tail -30 /var/log/secure 2>/dev/null || tail -30 /var/log/auth.log 2>/dev/null || echo "Not available"
    } > "$f" 2>&1
    print_status "System Log Baseline" "OK" "messages/dmesg/journal/auth captured"
}

# 17 — Reboot History & Uptime
capture_reboot_history() {
    local f="${SNAPSHOT_DIR}/17_reboot_history.txt"
    {
        echo "=== REBOOT HISTORY ==="
        last reboot | head -20
        echo ""
        echo "=== SHUTDOWN HISTORY ==="
        last -x shutdown 2>/dev/null | head -10
        echo ""
        echo "=== CURRENT UPTIME ==="
        uptime
        echo ""
        echo "=== SYSTEM BOOT TIME ==="
        who -b 2>/dev/null || systemctl show --property=UserspaceTimestamp 2>/dev/null
    } > "$f" 2>&1
    local uptime_val=$(uptime -p 2>/dev/null || uptime | sed 's/.*up /up /' | cut -d, -f1-2)
    print_status "Reboot & Uptime History" "OK" "${uptime_val}"
}

# =============================================================================
#  HTML REPORT GENERATOR
# =============================================================================
generate_html_report() {
    echo ""
    echo -e "  ${BOLD}${CYAN}▶  Generating HTML Report...${RESET}"
    echo -e "  ${DIM}  ──────────────────────────────────────────${RESET}"

    local diskcount=$(lsblk -d -o NAME,TYPE 2>/dev/null | grep -c disk)
    local pkgcount
    case "$OS_FAMILY" in
        rhel|suse) pkgcount=$(rpm -qa | wc -l) ;;
        debian)    pkgcount=$(dpkg -l | grep '^ii' | wc -l) ;;
        *) pkgcount="?" ;;
    esac
    local running_svc=$(systemctl list-units --type=service --state=running 2>/dev/null | grep -c "running" || echo "0")
    local failed_svc=$(systemctl list-units --state=failed 2>/dev/null | grep -c "failed" || echo "0")
    local mem_total=$(free -h | grep Mem | awk '{print $2}')
    local mem_used=$(free -h | grep Mem | awk '{print $3}')
    local mem_pct=$(free | grep Mem | awk '{printf "%.0f", $3/$2*100}')
    local swap_total=$(free -h | grep Swap | awk '{print $2}')
    local cpu_count=$(nproc)
    local cpu_model=$(lscpu | grep "Model name" | head -1 | sed 's/Model name.*: *//' | xargs)
    local disk_root=$(df -h / | tail -1 | awk '{print $5}' | tr -d '%')
    local selinux_s="N/A"
    command -v getenforce &>/dev/null && selinux_s=$(getenforce 2>/dev/null)
    local load_avg=$(cat /proc/loadavg | awk '{print $1, $2, $3}')
    local kernel_ver=$(uname -r)
    local uptime_val=$(uptime -p 2>/dev/null || uptime | sed 's/.*up //' | cut -d, -f1-2)
    local open_ports=$(ss -tulpn 2>/dev/null | grep -c LISTEN || echo "0")

    # Read section files
    read_file() { cat "$1" 2>/dev/null | sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g'; }

    cat > "$HTML_REPORT" << HTMLEOF
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>Pre-Patch Snapshot — $(hostname -s) — $(date '+%Y-%m-%d')</title>
<!-- No external resources — fully offline/air-gapped safe -->
<style>
  :root {
    --bg:        #0a0e1a;
    --bg2:       #0f1525;
    --bg3:       #151d30;
    --border:    #1e2d4a;
    --accent:    #00d4ff;
    --accent2:   #00ff88;
    --accent3:   #ff6b35;
    --warn:      #ffd166;
    --danger:    #ff4757;
    --text:      #c8d6e5;
    --text-dim:  #5a7a99;
    --text-hi:   #ffffff;
    --mono:      'Courier New', Courier, 'Lucida Console', monospace;
    --sans:      'Trebuchet MS', 'Segoe UI', Arial, sans-serif;
  }
  * { box-sizing: border-box; margin: 0; padding: 0; }
  body {
    background: var(--bg);
    color: var(--text);
    font-family: var(--sans);
    min-height: 100vh;
  }

  /* ── Header ── */
  .header {
    background: linear-gradient(135deg, #0a0e1a 0%, #0d1829 50%, #0a1520 100%);
    border-bottom: 1px solid var(--border);
    padding: 0;
    position: relative;
    overflow: hidden;
  }
  .header::before {
    content: '';
    position: absolute; inset: 0;
    background:
      radial-gradient(ellipse 60% 80% at 80% 50%, rgba(0,212,255,0.06) 0%, transparent 70%),
      radial-gradient(ellipse 40% 60% at 20% 80%, rgba(0,255,136,0.04) 0%, transparent 60%);
  }
  .header-inner {
    position: relative;
    max-width: 1400px;
    margin: 0 auto;
    padding: 36px 48px 32px;
    display: flex;
    align-items: flex-start;
    justify-content: space-between;
    gap: 32px;
    flex-wrap: wrap;
  }
  .header-left {}
  .badge {
    display: inline-flex;
    align-items: center;
    gap: 8px;
    background: rgba(0,212,255,0.1);
    border: 1px solid rgba(0,212,255,0.3);
    border-radius: 4px;
    padding: 4px 12px;
    font-family: var(--mono);
    font-size: 10px;
    font-weight: 600;
    color: var(--accent);
    letter-spacing: 0.15em;
    text-transform: uppercase;
    margin-bottom: 16px;
  }
  .badge-dot {
    width: 6px; height: 6px;
    border-radius: 50%;
    background: var(--accent);
    animation: pulse 2s infinite;
  }
  @keyframes pulse {
    0%,100% { opacity:1; transform: scale(1); }
    50%      { opacity:0.5; transform: scale(1.3); }
  }
  .header h1 {
    font-family: var(--sans);
    font-size: 2.4rem;
    font-weight: 800;
    color: var(--text-hi);
    letter-spacing: -0.02em;
    line-height: 1.1;
    margin-bottom: 8px;
  }
  .header h1 span { color: var(--accent); }
  .header-sub {
    font-family: var(--mono);
    font-size: 12px;
    color: var(--text-dim);
    letter-spacing: 0.05em;
  }
  .header-meta {
    display: flex;
    flex-direction: column;
    gap: 8px;
    align-items: flex-end;
  }
  .meta-pill {
    background: var(--bg3);
    border: 1px solid var(--border);
    border-radius: 6px;
    padding: 8px 16px;
    font-family: var(--mono);
    font-size: 11px;
    color: var(--text-dim);
    text-align: right;
  }
  .meta-pill strong { color: var(--text); display: block; font-size: 13px; }

  /* ── Stat Cards ── */
  .stats-bar {
    background: var(--bg2);
    border-bottom: 1px solid var(--border);
  }
  .stats-inner {
    max-width: 1400px;
    margin: 0 auto;
    padding: 0 48px;
    display: grid;
    grid-template-columns: repeat(auto-fit, minmax(160px, 1fr));
    gap: 0;
  }
  .stat-card {
    padding: 20px 24px;
    border-right: 1px solid var(--border);
    position: relative;
    transition: background 0.2s;
  }
  .stat-card:last-child { border-right: none; }
  .stat-card:hover { background: var(--bg3); }
  .stat-label {
    font-family: var(--mono);
    font-size: 10px;
    font-weight: 600;
    letter-spacing: 0.12em;
    text-transform: uppercase;
    color: var(--text-dim);
    margin-bottom: 6px;
  }
  .stat-value {
    font-family: var(--mono);
    font-size: 1.5rem;
    font-weight: 700;
    color: var(--text-hi);
    line-height: 1;
  }
  .stat-value.accent  { color: var(--accent); }
  .stat-value.green   { color: var(--accent2); }
  .stat-value.orange  { color: var(--accent3); }
  .stat-value.warn    { color: var(--warn); }
  .stat-value.danger  { color: var(--danger); }
  .stat-sub {
    font-family: var(--mono);
    font-size: 10px;
    color: var(--text-dim);
    margin-top: 4px;
  }
  .bar-wrap {
    margin-top: 6px;
    height: 3px;
    background: var(--border);
    border-radius: 2px;
    overflow: hidden;
  }
  .bar-fill { height: 100%; border-radius: 2px; }

  /* ── Layout ── */
  .main {
    max-width: 1400px;
    margin: 0 auto;
    padding: 32px 48px 64px;
    display: grid;
    grid-template-columns: 220px 1fr;
    gap: 32px;
  }

  /* ── Sidebar Nav ── */
  .sidebar {
    position: sticky;
    top: 24px;
    align-self: flex-start;
  }
  .nav-group-label {
    font-family: var(--mono);
    font-size: 9px;
    font-weight: 700;
    letter-spacing: 0.15em;
    text-transform: uppercase;
    color: var(--text-dim);
    padding: 0 0 8px 12px;
    margin-top: 20px;
  }
  .nav-group-label:first-child { margin-top: 0; }
  .nav-item {
    display: flex;
    align-items: center;
    gap: 10px;
    padding: 8px 12px;
    border-radius: 6px;
    cursor: pointer;
    font-family: var(--mono);
    font-size: 11px;
    color: var(--text-dim);
    transition: all 0.15s;
    text-decoration: none;
    border: 1px solid transparent;
    margin-bottom: 2px;
  }
  .nav-item:hover {
    color: var(--text);
    background: var(--bg3);
    border-color: var(--border);
  }
  .nav-item.active {
    color: var(--accent);
    background: rgba(0,212,255,0.08);
    border-color: rgba(0,212,255,0.25);
  }
  .nav-icon { font-size: 13px; width: 16px; text-align: center; }

  /* ── Content ── */
  .content { min-width: 0; }
  .section {
    background: var(--bg2);
    border: 1px solid var(--border);
    border-radius: 10px;
    margin-bottom: 20px;
    overflow: hidden;
    scroll-margin-top: 24px;
  }
  .section-header {
    display: flex;
    align-items: center;
    justify-content: space-between;
    padding: 16px 24px;
    background: var(--bg3);
    border-bottom: 1px solid var(--border);
    cursor: pointer;
    user-select: none;
  }
  .section-header:hover { background: rgba(30,45,74,0.8); }
  .section-title-row {
    display: flex;
    align-items: center;
    gap: 12px;
  }
  .section-icon {
    width: 32px; height: 32px;
    border-radius: 8px;
    display: flex; align-items: center; justify-content: center;
    font-size: 15px;
    background: rgba(0,212,255,0.1);
    border: 1px solid rgba(0,212,255,0.2);
    flex-shrink: 0;
  }
  .section-title {
    font-family: var(--sans);
    font-size: 14px;
    font-weight: 700;
    color: var(--text-hi);
  }
  .section-subtitle {
    font-family: var(--mono);
    font-size: 10px;
    color: var(--text-dim);
    margin-top: 2px;
  }
  .section-toggle {
    font-size: 18px;
    color: var(--text-dim);
    transition: transform 0.2s;
  }
  .section-toggle.open { transform: rotate(180deg); }
  .section-body {
    display: none;
    padding: 20px 24px;
  }
  .section-body.open { display: block; }
  .section-body pre {
    font-family: var(--mono);
    font-size: 11.5px;
    line-height: 1.7;
    color: var(--text);
    white-space: pre-wrap;
    word-break: break-word;
    background: var(--bg);
    border: 1px solid var(--border);
    border-radius: 6px;
    padding: 16px 20px;
    max-height: 500px;
    overflow-y: auto;
  }
  .section-body pre::-webkit-scrollbar { width: 6px; }
  .section-body pre::-webkit-scrollbar-track { background: var(--bg2); }
  .section-body pre::-webkit-scrollbar-thumb { background: var(--border); border-radius: 3px; }

  /* ── Info Grid ── */
  .info-grid {
    display: grid;
    grid-template-columns: repeat(auto-fit, minmax(280px, 1fr));
    gap: 12px;
    margin-bottom: 16px;
  }
  .info-card {
    background: var(--bg);
    border: 1px solid var(--border);
    border-radius: 8px;
    padding: 14px 18px;
  }
  .info-row {
    display: flex;
    justify-content: space-between;
    align-items: baseline;
    padding: 5px 0;
    border-bottom: 1px solid rgba(30,45,74,0.5);
    font-family: var(--mono);
    font-size: 11.5px;
  }
  .info-row:last-child { border-bottom: none; }
  .info-key { color: var(--text-dim); }
  .info-val { color: var(--text-hi); font-weight: 600; text-align: right; max-width: 60%; word-break: break-all; }
  .info-val.ok     { color: var(--accent2); }
  .info-val.warn   { color: var(--warn); }
  .info-val.danger { color: var(--danger); }

  /* ── Tags ── */
  .tag {
    display: inline-block;
    padding: 2px 8px;
    border-radius: 4px;
    font-family: var(--mono);
    font-size: 10px;
    font-weight: 600;
    margin: 2px;
  }
  .tag-green  { background: rgba(0,255,136,0.1); color: var(--accent2); border: 1px solid rgba(0,255,136,0.2); }
  .tag-blue   { background: rgba(0,212,255,0.1); color: var(--accent);  border: 1px solid rgba(0,212,255,0.2); }
  .tag-orange { background: rgba(255,107,53,0.1); color: var(--accent3); border: 1px solid rgba(255,107,53,0.2); }
  .tag-red    { background: rgba(255,71,87,0.1); color: var(--danger);  border: 1px solid rgba(255,71,87,0.2); }
  .tag-warn   { background: rgba(255,209,102,0.1); color: var(--warn);  border: 1px solid rgba(255,209,102,0.2); }

  /* ── Footer ── */
  .footer {
    border-top: 1px solid var(--border);
    padding: 24px 48px;
    max-width: 1400px;
    margin: 0 auto;
    display: flex;
    justify-content: space-between;
    align-items: center;
    font-family: var(--mono);
    font-size: 11px;
    color: var(--text-dim);
  }

  /* ── Responsive ── */
  @media (max-width: 900px) {
    .main { grid-template-columns: 1fr; padding: 16px; }
    .sidebar { position: static; }
    .header-inner, .stats-inner, .footer { padding-left: 16px; padding-right: 16px; }
  }
</style>
</head>
<body>

<!-- HEADER -->
<div class="header">
  <div class="header-inner">
    <div class="header-left">
      <div class="badge"><span class="badge-dot"></span>PRE-PATCH SNAPSHOT</div>
      <h1>$(hostname -s)<span>.</span></h1>
      <div class="header-sub">$(hostname -f 2>/dev/null || hostname) &nbsp;·&nbsp; ${OS_PRETTY} &nbsp;·&nbsp; Kernel $(uname -r)</div>
    </div>
    <div class="header-meta">
      <div class="meta-pill"><strong>$(date '+%Y-%m-%d %H:%M:%S')</strong>Capture Timestamp</div>
      <div class="meta-pill"><strong>${OS_FAMILY^^}</strong>OS Family</div>
      <div class="meta-pill"><strong>$(date +%Z)</strong>Timezone</div>
    </div>
  </div>
</div>

<!-- STATS BAR -->
<div class="stats-bar">
  <div class="stats-inner">
    <div class="stat-card">
      <div class="stat-label">vCPUs</div>
      <div class="stat-value accent">${cpu_count}</div>
      <div class="stat-sub">${cpu_model:0:22}...</div>
    </div>
    <div class="stat-card">
      <div class="stat-label">Memory Used</div>
      <div class="stat-value $([ "${mem_pct:-0}" -gt 85 ] && echo danger || [ "${mem_pct:-0}" -gt 65 ] && echo warn || echo green)">${mem_used} / ${mem_total}</div>
      <div class="bar-wrap"><div class="bar-fill" style="width:${mem_pct:-0}%; background:$([ "${mem_pct:-0}" -gt 85 ] && echo 'var(--danger)' || [ "${mem_pct:-0}" -gt 65 ] && echo 'var(--warn)' || echo 'var(--accent2)')"></div></div>
      <div class="stat-sub">${mem_pct}% utilization</div>
    </div>
    <div class="stat-card">
      <div class="stat-label">Disks</div>
      <div class="stat-value orange">${diskcount}</div>
      <div class="stat-sub">block device(s)</div>
    </div>
    <div class="stat-card">
      <div class="stat-label">Root Disk</div>
      <div class="stat-value $([ "${disk_root:-0}" -gt 85 ] && echo danger || [ "${disk_root:-0}" -gt 65 ] && echo warn || echo accent)">${disk_root}%</div>
      <div class="bar-wrap"><div class="bar-fill" style="width:${disk_root:-0}%; background:$([ "${disk_root:-0}" -gt 85 ] && echo 'var(--danger)' || [ "${disk_root:-0}" -gt 65 ] && echo 'var(--warn)' || echo 'var(--accent)')"></div></div>
      <div class="stat-sub">/ filesystem</div>
    </div>
    <div class="stat-card">
      <div class="stat-label">Packages</div>
      <div class="stat-value accent">${pkgcount}</div>
      <div class="stat-sub">installed</div>
    </div>
    <div class="stat-card">
      <div class="stat-label">Services</div>
      <div class="stat-value green">${running_svc}</div>
      <div class="stat-sub">running &nbsp;<span style="color:$([ "${failed_svc:-0}" -gt 0 ] && echo 'var(--danger)' || echo 'var(--text-dim)')">${failed_svc} failed</span></div>
    </div>
    <div class="stat-card">
      <div class="stat-label">Open Ports</div>
      <div class="stat-value warn">${open_ports}</div>
      <div class="stat-sub">listening</div>
    </div>
    <div class="stat-card">
      <div class="stat-label">Load Avg</div>
      <div class="stat-value accent">${load_avg%% *}</div>
      <div class="stat-sub">${load_avg}</div>
    </div>
  </div>
</div>

<!-- MAIN -->
<div class="main">

  <!-- SIDEBAR -->
  <aside class="sidebar">
    <div class="nav-group-label">System</div>
    <a class="nav-item active" href="#os-info"    onclick="setActive(this)"><span class="nav-icon">🖥</span>OS & System</a>
    <a class="nav-item"        href="#kernel"     onclick="setActive(this)"><span class="nav-icon">⚙</span>Kernel</a>
    <a class="nav-item"        href="#cpu"        onclick="setActive(this)"><span class="nav-icon">🔲</span>CPU</a>
    <a class="nav-item"        href="#memory"     onclick="setActive(this)"><span class="nav-icon">💾</span>Memory</a>
    <a class="nav-item"        href="#disk"       onclick="setActive(this)"><span class="nav-icon">🗄</span>Disk & Storage</a>

    <div class="nav-group-label">Network</div>
    <a class="nav-item" href="#network"   onclick="setActive(this)"><span class="nav-icon">🌐</span>Network</a>
    <a class="nav-item" href="#ports"     onclick="setActive(this)"><span class="nav-icon">🔌</span>Open Ports</a>
    <a class="nav-item" href="#firewall"  onclick="setActive(this)"><span class="nav-icon">🛡</span>Firewall</a>

    <div class="nav-group-label">Software</div>
    <a class="nav-item" href="#packages"  onclick="setActive(this)"><span class="nav-icon">📦</span>Packages</a>
    <a class="nav-item" href="#services"  onclick="setActive(this)"><span class="nav-icon">⚡</span>Services</a>
    <a class="nav-item" href="#integrity" onclick="setActive(this)"><span class="nav-icon">🔍</span>Pkg Integrity</a>

    <div class="nav-group-label">Security</div>
    <a class="nav-item" href="#selinux"   onclick="setActive(this)"><span class="nav-icon">🔒</span>SELinux/AppArmor</a>
    <a class="nav-item" href="#users"     onclick="setActive(this)"><span class="nav-icon">👤</span>Users & Sudo</a>
    <a class="nav-item" href="#checksums" onclick="setActive(this)"><span class="nav-icon">🔐</span>/etc Checksums</a>

    <div class="nav-group-label">Automation</div>
    <a class="nav-item" href="#cron"      onclick="setActive(this)"><span class="nav-icon">🕐</span>Cron & Timers</a>

    <div class="nav-group-label">Audit</div>
    <a class="nav-item" href="#logs"     onclick="setActive(this)"><span class="nav-icon">📋</span>Log Baseline</a>
    <a class="nav-item" href="#reboots"  onclick="setActive(this)"><span class="nav-icon">🔄</span>Reboot History</a>
  </aside>

  <!-- CONTENT SECTIONS -->
  <div class="content">

    <!-- OS Info -->
    <div class="section" id="os-info">
      <div class="section-header" onclick="toggleSection(this)">
        <div class="section-title-row">
          <div class="section-icon">🖥</div>
          <div>
            <div class="section-title">OS & System Information</div>
            <div class="section-subtitle">$(hostname -f) &nbsp;·&nbsp; ${OS_PRETTY}</div>
          </div>
        </div>
        <div class="section-toggle open">▼</div>
      </div>
      <div class="section-body open">
        <div class="info-grid">
          <div class="info-card">
            <div class="info-row"><span class="info-key">Hostname</span><span class="info-val">$(hostname -s)</span></div>
            <div class="info-row"><span class="info-key">FQDN</span><span class="info-val">$(hostname -f 2>/dev/null || hostname)</span></div>
            <div class="info-row"><span class="info-key">OS</span><span class="info-val">${OS_PRETTY}</span></div>
            <div class="info-row"><span class="info-key">OS Family</span><span class="info-val ok">${OS_FAMILY^^}</span></div>
            <div class="info-row"><span class="info-key">Version</span><span class="info-val">${OS_VERSION}</span></div>
          </div>
          <div class="info-card">
            <div class="info-row"><span class="info-key">Timezone</span><span class="info-val">$(timedatectl 2>/dev/null | grep 'Time zone' | awk '{print $3}' || date +%Z)</span></div>
            <div class="info-row"><span class="info-key">Uptime</span><span class="info-val ok">${uptime_val}</span></div>
            <div class="info-row"><span class="info-key">Load Avg (1/5/15)</span><span class="info-val">${load_avg}</span></div>
            <div class="info-row"><span class="info-key">Capture Date</span><span class="info-val">$(date '+%Y-%m-%d %H:%M:%S')</span></div>
          </div>
        </div>
        <pre>$(read_file "${SNAPSHOT_DIR}/01_os_info.txt")</pre>
      </div>
    </div>

    <!-- Kernel -->
    <div class="section" id="kernel">
      <div class="section-header" onclick="toggleSection(this)">
        <div class="section-title-row">
          <div class="section-icon">⚙</div>
          <div>
            <div class="section-title">Kernel Information</div>
            <div class="section-subtitle">$(uname -r) &nbsp;·&nbsp; $(uname -m)</div>
          </div>
        </div>
        <div class="section-toggle">▼</div>
      </div>
      <div class="section-body">
        <pre>$(read_file "${SNAPSHOT_DIR}/02_kernel.txt")</pre>
      </div>
    </div>

    <!-- CPU -->
    <div class="section" id="cpu">
      <div class="section-header" onclick="toggleSection(this)">
        <div class="section-title-row">
          <div class="section-icon">🔲</div>
          <div>
            <div class="section-title">CPU Information</div>
            <div class="section-subtitle">${cpu_count} vCPUs &nbsp;·&nbsp; ${cpu_model:0:50}</div>
          </div>
        </div>
        <div class="section-toggle">▼</div>
      </div>
      <div class="section-body">
        <div class="info-grid">
          <div class="info-card">
            <div class="info-row"><span class="info-key">Model</span><span class="info-val">${cpu_model:0:35}</span></div>
            <div class="info-row"><span class="info-key">Total vCPUs</span><span class="info-val ok">${cpu_count}</span></div>
            <div class="info-row"><span class="info-key">Physical Sockets</span><span class="info-val">$(lscpu | grep '^Socket' | awk '{print $2}')</span></div>
            <div class="info-row"><span class="info-key">Cores/Socket</span><span class="info-val">$(lscpu | grep 'Core.*per socket' | awk '{print $4}')</span></div>
            <div class="info-row"><span class="info-key">Threads/Core</span><span class="info-val">$(lscpu | grep 'Thread.*per core' | awk '{print $4}')</span></div>
            <div class="info-row"><span class="info-key">Architecture</span><span class="info-val">$(uname -m)</span></div>
          </div>
        </div>
        <pre>$(read_file "${SNAPSHOT_DIR}/03_cpu.txt")</pre>
      </div>
    </div>

    <!-- Memory -->
    <div class="section" id="memory">
      <div class="section-header" onclick="toggleSection(this)">
        <div class="section-title-row">
          <div class="section-icon">💾</div>
          <div>
            <div class="section-title">Memory & Swap</div>
            <div class="section-subtitle">${mem_used} used of ${mem_total} &nbsp;·&nbsp; ${mem_pct}% utilization</div>
          </div>
        </div>
        <div class="section-toggle">▼</div>
      </div>
      <div class="section-body">
        <div class="info-grid">
          <div class="info-card">
            <div class="info-row"><span class="info-key">Total RAM</span><span class="info-val">${mem_total}</span></div>
            <div class="info-row"><span class="info-key">Used</span><span class="info-val $([ "${mem_pct:-0}" -gt 85 ] && echo danger || [ "${mem_pct:-0}" -gt 65 ] && echo warn || echo ok)">${mem_used}</span></div>
            <div class="info-row"><span class="info-key">Free</span><span class="info-val">$(free -h | grep Mem | awk '{print $4}')</span></div>
            <div class="info-row"><span class="info-key">Utilization</span><span class="info-val">${mem_pct}%</span></div>
            <div class="info-row"><span class="info-key">Swap Total</span><span class="info-val">${swap_total}</span></div>
            <div class="info-row"><span class="info-key">Swap Used</span><span class="info-val">$(free -h | grep Swap | awk '{print $3}')</span></div>
          </div>
        </div>
        <pre>$(read_file "${SNAPSHOT_DIR}/04_memory.txt")</pre>
      </div>
    </div>

    <!-- Disk -->
    <div class="section" id="disk">
      <div class="section-header" onclick="toggleSection(this)">
        <div class="section-title-row">
          <div class="section-icon">🗄</div>
          <div>
            <div class="section-title">Disk & Storage</div>
            <div class="section-subtitle">${diskcount} disk(s) assigned &nbsp;·&nbsp; LVM, mounts, fstab, multipath captured</div>
          </div>
        </div>
        <div class="section-toggle">▼</div>
      </div>
      <div class="section-body">
        <div class="info-grid">
          <div class="info-card">
            <div class="info-row"><span class="info-key">Physical Disks</span><span class="info-val orange">${diskcount}</span></div>
            <div class="info-row"><span class="info-key">Root (/) Usage</span><span class="info-val $([ "${disk_root:-0}" -gt 85 ] && echo danger || [ "${disk_root:-0}" -gt 65 ] && echo warn || echo ok)">${disk_root}%</span></div>
            <div class="info-row"><span class="info-key">Root Size</span><span class="info-val">$(df -h / | tail -1 | awk '{print $2}')</span></div>
            <div class="info-row"><span class="info-key">Root Free</span><span class="info-val">$(df -h / | tail -1 | awk '{print $4}')</span></div>
          </div>
          <div class="info-card">
$(df -hT | grep -v tmpfs | grep -v devtmpfs | tail -n +2 | while read line; do
    mp=$(echo "$line" | awk '{print $7}')
    used=$(echo "$line" | awk '{print $6}' | tr -d '%')
    size=$(echo "$line" | awk '{print $3}')
    usedh=$(echo "$line" | awk '{print $4}')
    color="ok"
    [ "${used:-0}" -gt 85 ] 2>/dev/null && color="danger"
    [ "${used:-0}" -gt 65 ] 2>/dev/null && [ "${used:-0}" -le 85 ] 2>/dev/null && color="warn"
    echo "            <div class=\"info-row\"><span class=\"info-key\">${mp:-/}</span><span class=\"info-val ${color}\">${usedh} / ${size} (${used}%)</span></div>"
done)
          </div>
        </div>
        <pre>$(read_file "${SNAPSHOT_DIR}/05_disk.txt")</pre>
      </div>
    </div>

    <!-- Network -->
    <div class="section" id="network">
      <div class="section-header" onclick="toggleSection(this)">
        <div class="section-title-row">
          <div class="section-icon">🌐</div>
          <div>
            <div class="section-title">Network Configuration</div>
            <div class="section-subtitle">$(ip -4 addr show | grep inet | grep -v 127 | awk '{print $2}' | tr '\n' ' ')</div>
          </div>
        </div>
        <div class="section-toggle">▼</div>
      </div>
      <div class="section-body">
        <pre>$(read_file "${SNAPSHOT_DIR}/06_network.txt")</pre>
      </div>
    </div>

    <!-- Ports -->
    <div class="section" id="ports">
      <div class="section-header" onclick="toggleSection(this)">
        <div class="section-title-row">
          <div class="section-icon">🔌</div>
          <div>
            <div class="section-title">Open Ports & Connections</div>
            <div class="section-subtitle">${open_ports} listening ports</div>
          </div>
        </div>
        <div class="section-toggle">▼</div>
      </div>
      <div class="section-body">
        <pre>$(read_file "${SNAPSHOT_DIR}/07_ports.txt")</pre>
      </div>
    </div>

    <!-- Firewall -->
    <div class="section" id="firewall">
      <div class="section-header" onclick="toggleSection(this)">
        <div class="section-title-row">
          <div class="section-icon">🛡</div>
          <div>
            <div class="section-title">Firewall Rules</div>
            <div class="section-subtitle">firewalld / iptables / ufw</div>
          </div>
        </div>
        <div class="section-toggle">▼</div>
      </div>
      <div class="section-body">
        <pre>$(read_file "${SNAPSHOT_DIR}/08_firewall.txt")</pre>
      </div>
    </div>

    <!-- Packages -->
    <div class="section" id="packages">
      <div class="section-header" onclick="toggleSection(this)">
        <div class="section-title-row">
          <div class="section-icon">📦</div>
          <div>
            <div class="section-title">Installed Packages</div>
            <div class="section-subtitle">${pkgcount} packages &nbsp;·&nbsp; patch history &nbsp;·&nbsp; pending updates</div>
          </div>
        </div>
        <div class="section-toggle">▼</div>
      </div>
      <div class="section-body">
        <pre>$(read_file "${SNAPSHOT_DIR}/09_packages.txt")</pre>
      </div>
    </div>

    <!-- Services -->
    <div class="section" id="services">
      <div class="section-header" onclick="toggleSection(this)">
        <div class="section-title-row">
          <div class="section-icon">⚡</div>
          <div>
            <div class="section-title">Systemd Services</div>
            <div class="section-subtitle">${running_svc} running &nbsp;·&nbsp; ${failed_svc} failed</div>
          </div>
        </div>
        <div class="section-toggle">▼</div>
      </div>
      <div class="section-body">
        <pre>$(read_file "${SNAPSHOT_DIR}/10_services.txt")</pre>
      </div>
    </div>

    <!-- SELinux -->
    <div class="section" id="selinux">
      <div class="section-header" onclick="toggleSection(this)">
        <div class="section-title-row">
          <div class="section-icon">🔒</div>
          <div>
            <div class="section-title">SELinux / AppArmor</div>
            <div class="section-subtitle">Status: ${selinux_s}</div>
          </div>
        </div>
        <div class="section-toggle">▼</div>
      </div>
      <div class="section-body">
        <pre>$(read_file "${SNAPSHOT_DIR}/11_selinux_apparmor.txt")</pre>
      </div>
    </div>

    <!-- Cron -->
    <div class="section" id="cron">
      <div class="section-header" onclick="toggleSection(this)">
        <div class="section-title-row">
          <div class="section-icon">🕐</div>
          <div>
            <div class="section-title">Cron Jobs & Systemd Timers</div>
            <div class="section-subtitle">system crontab, cron.d, user crontabs, timers</div>
          </div>
        </div>
        <div class="section-toggle">▼</div>
      </div>
      <div class="section-body">
        <pre>$(read_file "${SNAPSHOT_DIR}/12_cron.txt")</pre>
      </div>
    </div>

    <!-- Users -->
    <div class="section" id="users">
      <div class="section-header" onclick="toggleSection(this)">
        <div class="section-title-row">
          <div class="section-icon">👤</div>
          <div>
            <div class="section-title">User Accounts & Sudo</div>
            <div class="section-subtitle">passwd, groups, sudoers, last logins</div>
          </div>
        </div>
        <div class="section-toggle">▼</div>
      </div>
      <div class="section-body">
        <pre>$(read_file "${SNAPSHOT_DIR}/13_users.txt")</pre>
      </div>
    </div>

    <!-- Checksums -->
    <div class="section" id="checksums">
      <div class="section-header" onclick="toggleSection(this)">
        <div class="section-title-row">
          <div class="section-icon">🔐</div>
          <div>
            <div class="section-title">/etc Configuration Checksums</div>
            <div class="section-subtitle">MD5 hashes of all /etc files — baseline for post-patch comparison</div>
          </div>
        </div>
        <div class="section-toggle">▼</div>
      </div>
      <div class="section-body">
        <pre>$(read_file "${SNAPSHOT_DIR}/14_etc_checksums.txt")</pre>
      </div>
    </div>

    <!-- Package Integrity -->
    <div class="section" id="integrity">
      <div class="section-header" onclick="toggleSection(this)">
        <div class="section-title-row">
          <div class="section-icon">🔍</div>
          <div>
            <div class="section-title">Package Integrity Check</div>
            <div class="section-subtitle">RPM verify / DPKG verify — tampered file detection</div>
          </div>
        </div>
        <div class="section-toggle">▼</div>
      </div>
      <div class="section-body">
        <pre>$(read_file "${SNAPSHOT_DIR}/15_pkg_integrity.txt")</pre>
      </div>
    </div>

    <!-- Logs -->
    <div class="section" id="logs">
      <div class="section-header" onclick="toggleSection(this)">
        <div class="section-title-row">
          <div class="section-icon">📋</div>
          <div>
            <div class="section-title">System Log Baseline</div>
            <div class="section-subtitle">messages / syslog / dmesg / journal / auth — pre-patch baseline</div>
          </div>
        </div>
        <div class="section-toggle">▼</div>
      </div>
      <div class="section-body">
        <pre>$(read_file "${SNAPSHOT_DIR}/16_log_baseline.txt")</pre>
      </div>
    </div>

    <!-- Reboots -->
    <div class="section" id="reboots">
      <div class="section-header" onclick="toggleSection(this)">
        <div class="section-title-row">
          <div class="section-icon">🔄</div>
          <div>
            <div class="section-title">Reboot & Uptime History</div>
            <div class="section-subtitle">Last reboots, shutdowns, current uptime</div>
          </div>
        </div>
        <div class="section-toggle">▼</div>
      </div>
      <div class="section-body">
        <pre>$(read_file "${SNAPSHOT_DIR}/17_reboot_history.txt")</pre>
      </div>
    </div>

  </div><!-- end .content -->
</div><!-- end .main -->

<!-- FOOTER -->
<div class="footer">
  <span>Generated by Pre-Patch Snapshot Tool &nbsp;·&nbsp; $(hostname -f) &nbsp;·&nbsp; $(date '+%Y-%m-%d %H:%M:%S')</span>
  <span>Snapshot: ${SNAPSHOT_DIR}</span>
</div>

<script>
function toggleSection(header) {
  const body = header.nextElementSibling;
  const toggle = header.querySelector('.section-toggle');
  body.classList.toggle('open');
  toggle.classList.toggle('open');
}
function setActive(el) {
  document.querySelectorAll('.nav-item').forEach(i => i.classList.remove('active'));
  el.classList.add('active');
}
// Smooth scroll offset
document.querySelectorAll('.nav-item[href^="#"]').forEach(a => {
  a.addEventListener('click', function(e) {
    e.preventDefault();
    const target = document.querySelector(this.getAttribute('href'));
    if (target) {
      target.scrollIntoView({ behavior: 'smooth', block: 'start' });
      // Auto expand section
      const body = target.querySelector('.section-body');
      const toggle = target.querySelector('.section-toggle');
      if (body && !body.classList.contains('open')) {
        body.classList.add('open');
        toggle && toggle.classList.add('open');
      }
    }
  });
});
</script>
</body>
</html>
HTMLEOF

    echo -e "  ${GREEN}[✔]${RESET} ${WHITE}HTML Report Generated${RESET}  ${DIM}${HTML_REPORT}${RESET}"
}

# =============================================================================
#  MAIN
# =============================================================================
main() {
    detect_os
    print_banner

    print_section "System & Hardware"
    capture_os_info
    capture_kernel
    capture_cpu
    capture_memory

    print_section "Storage"
    capture_disk

    print_section "Network & Security"
    capture_network
    capture_ports
    capture_firewall
    capture_security_policy

    print_section "Software & Services"
    capture_packages
    capture_services
    capture_package_integrity

    print_section "Security & Users"
    capture_etc_checksums
    capture_users

    print_section "Automation & Audit"
    capture_cron
    capture_logs
    capture_reboot_history

    # Generate HTML
    generate_html_report

    # Final Summary
    local END_TIME=$(date +%s)
    local DURATION=$((END_TIME - START_TIME))

    echo ""
    echo -e "  ${DIM}──────────────────────────────────────────────────────────────────${RESET}"
    echo ""
    echo -e "  ${BOLD}${GREEN}✔  PRE-PATCH SNAPSHOT COMPLETE${RESET}"
    echo ""
    echo -e "  ${WHITE}Snapshot Dir  :${RESET} ${DIM}${SNAPSHOT_DIR}${RESET}"
    echo -e "  ${WHITE}HTML Report   :${RESET} ${GREEN}${HTML_REPORT}${RESET}"
    echo -e "  ${WHITE}Duration      :${RESET} ${CYAN}${DURATION} seconds${RESET}"
    echo -e "  ${WHITE}Captured At   :${RESET} $(date '+%Y-%m-%d %H:%M:%S')"
    echo ""
    echo -e "  ${YELLOW}★  Safe to proceed with patching. Run post_patch.sh after completion.${RESET}"
    echo ""

    # Write summary JSON for later use by diff script
    cat > "${SNAPSHOT_DIR}/snapshot_meta.json" << METAEOF
{
  "type": "pre",
  "hostname": "$(hostname -f)",
  "os_pretty": "${OS_PRETTY}",
  "os_family": "${OS_FAMILY}",
  "kernel": "$(uname -r)",
  "timestamp": "$(date '+%Y-%m-%d %H:%M:%S')",
  "snapshot_dir": "${SNAPSHOT_DIR}",
  "html_report": "${HTML_REPORT}",
  "packages": "${pkgcount:-0}",
  "running_services": "${running_svc:-0}",
  "failed_services": "${failed_svc:-0}",
  "disks": "${diskcount:-0}",
  "open_ports": "${open_ports:-0}"
}
METAEOF
}

main "$@"
