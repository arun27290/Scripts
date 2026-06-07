#!/bin/bash
# =============================================================================
#  DIFF REPORT SCRIPT — Pre vs Post Patch Comparison
#  Supports: RHEL / CentOS / Rocky / AlmaLinux | SUSE / SLES | Ubuntu / Debian
#  Author  : Linux Admin Team
#  Version : 1.0
#
#  Usage:
#    sudo /opt/patch-audit/diff_report.sh --pre <pre_dir> --post <post_dir>
#
#  Example:
#    sudo /opt/patch-audit/diff_report.sh \
#      --pre  /opt/patch-audit/snapshots/server01_pre_20250606_0900 \
#      --post /opt/patch-audit/snapshots/server01_post_20250606_1100
#
#  Auto mode (picks latest pre and post automatically):
#    sudo /opt/patch-audit/diff_report.sh --auto
# =============================================================================

# ─── Strict mode ──────────────────────────────────────────────────────────────
set -uo pipefail

# ─── Root check ───────────────────────────────────────────────────────────────
if [ "${EUID:-$(id -u)}" -ne 0 ]; then
    echo "ERROR: This script must be run as root (sudo)." >&2
    exit 1
fi

# ─── Colors ───────────────────────────────────────────────────────────────────
RED='\033[0;31m';   GREEN='\033[0;32m';  YELLOW='\033[1;33m'
BLUE='\033[0;34m';  CYAN='\033[0;36m';   WHITE='\033[1;37m'
BOLD='\033[1m';     DIM='\033[2m';       RESET='\033[0m'

# ─── Paths ────────────────────────────────────────────────────────────────────
BASE_DIR="/opt/patch-audit"
REPORT_DIR="${BASE_DIR}/reports"
HOSTNAME_SHORT=$(hostname -s)
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
PRE_DIR=""
POST_DIR=""
AUTO_MODE=0
START_TIME=$(date +%s)

# ─── Secure temp directory (replaces hardcoded /tmp names) ────────────────────
TMPWORK=$(mktemp -d /tmp/patch_diff_XXXXXX)
chmod 700 "$TMPWORK"

# ─── Trap: auto-cleanup temp dir on exit, interrupt, or error ─────────────────
cleanup() { rm -rf "$TMPWORK" 2>/dev/null; }
trap cleanup EXIT INT TERM

# ─── Parse Arguments ──────────────────────────────────────────────────────────
while [[ "$#" -gt 0 ]]; do
    case "$1" in
        --pre)  PRE_DIR="$2";  shift 2 ;;
        --post) POST_DIR="$2"; shift 2 ;;
        --auto) AUTO_MODE=1;   shift   ;;
        *) echo -e "${RED}Unknown option: $1${RESET}"; exit 1 ;;
    esac
done

# ─── Auto-detect snapshots ────────────────────────────────────────────────────
auto_detect() {
    PRE_DIR=$(ls -dt  "${BASE_DIR}/snapshots/${HOSTNAME_SHORT}_pre_"*  2>/dev/null | head -1)
    POST_DIR=$(ls -dt "${BASE_DIR}/snapshots/${HOSTNAME_SHORT}_post_"* 2>/dev/null | head -1)
}

[ "$AUTO_MODE" -eq 1 ] && auto_detect

# ─── Validate ─────────────────────────────────────────────────────────────────
validate() {
    local ok=1
    [ -z "$PRE_DIR"  ] && echo -e "${RED}[✘] --pre directory not specified or not found${RESET}"  && ok=0
    [ -z "$POST_DIR" ] && echo -e "${RED}[✘] --post directory not specified or not found${RESET}" && ok=0
    [ -n "$PRE_DIR"  ] && [ ! -d "$PRE_DIR"  ] && echo -e "${RED}[✘] Pre  dir not found : ${PRE_DIR}${RESET}"  && ok=0
    [ -n "$POST_DIR" ] && [ ! -d "$POST_DIR" ] && echo -e "${RED}[✘] Post dir not found : ${POST_DIR}${RESET}" && ok=0
    [ "$ok" -eq 0 ] && echo "" && echo "Usage: $0 --pre <dir> --post <dir>" && echo "       $0 --auto" && exit 1
}

validate

# ─── Detect OS from pre snapshot meta ─────────────────────────────────────────
OS_FAMILY="unknown"; OS_PRETTY="Linux"
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS_PRETTY="${PRETTY_NAME:-$NAME}"
    case "$ID" in
        rhel|centos|rocky|almalinux|fedora) OS_FAMILY="rhel" ;;
        sles|opensuse|opensuse-leap|opensuse-tumbleweed) OS_FAMILY="suse" ;;
        ubuntu|debian|linuxmint) OS_FAMILY="debian" ;;
    esac
fi

# ─── Output paths ─────────────────────────────────────────────────────────────
mkdir -p "$REPORT_DIR"
HTML_REPORT="${REPORT_DIR}/${HOSTNAME_SHORT}_diff_${TIMESTAMP}.html"

# ─── Banner ───────────────────────────────────────────────────────────────────
print_banner() {
    clear
    echo -e "${BOLD}${CYAN}"
    echo "  ╔══════════════════════════════════════════════════════════════════╗"
    echo "  ║           PATCH DIFF REPORT GENERATOR                           ║"
    echo "  ║           Pre vs Post Configuration Comparison                  ║"
    echo "  ╚══════════════════════════════════════════════════════════════════╝${RESET}"
    echo ""
    echo -e "  ${WHITE}${BOLD}Server    :${RESET}  ${GREEN}$(hostname -f)${RESET}"
    echo -e "  ${WHITE}${BOLD}Pre Dir   :${RESET}  ${DIM}${PRE_DIR}${RESET}"
    echo -e "  ${WHITE}${BOLD}Post Dir  :${RESET}  ${DIM}${POST_DIR}${RESET}"
    echo -e "  ${WHITE}${BOLD}Report    :${RESET}  ${CYAN}${HTML_REPORT}${RESET}"
    echo ""
    echo -e "  ${DIM}──────────────────────────────────────────────────────────────────${RESET}"
    echo ""
}

print_check() {
    local label="$1"; local result="$2"; local detail="$3"
    local padded=$(printf "%-38s" "$label")
    case "$result" in
        CHANGED)  echo -e "  ${YELLOW}[~]${RESET} ${WHITE}${padded}${RESET} ${YELLOW}CHANGED${RESET}   ${DIM}${detail}${RESET}" ;;
        SAME)     echo -e "  ${GREEN}[✔]${RESET} ${WHITE}${padded}${RESET} ${GREEN}NO CHANGE${RESET} ${DIM}${detail}${RESET}" ;;
        NEW)      echo -e "  ${CYAN}[+]${RESET} ${WHITE}${padded}${RESET} ${CYAN}NEW${RESET}       ${DIM}${detail}${RESET}" ;;
        REMOVED)  echo -e "  ${RED}[-]${RESET} ${WHITE}${padded}${RESET} ${RED}REMOVED${RESET}   ${DIM}${detail}${RESET}" ;;
        CRITICAL) echo -e "  ${RED}[!]${RESET} ${BOLD}${WHITE}${padded}${RESET} ${RED}${BOLD}CRITICAL${RESET}  ${DIM}${detail}${RESET}" ;;
        *)        echo -e "  ${DIM}[?]${RESET} ${WHITE}${padded}${RESET} ${DIM}UNKNOWN${RESET}" ;;
    esac
}

print_section() {
    echo ""
    echo -e "  ${BOLD}${CYAN}▶  $1${RESET}"
    echo -e "  ${DIM}  ──────────────────────────────────────────${RESET}"
}

# =============================================================================
#  DIFF FUNCTIONS
# =============================================================================

# Compare two files and return unified diff
file_diff() {
    local pre="$1"; local post="$2"
    diff --unified=0 "$pre" "$post" 2>/dev/null
}

# Count added/removed lines in a diff
count_changes() {
    local pre="$1"; local post="$2"
    local added=$(diff "$pre" "$post" 2>/dev/null | grep -c "^+" | grep -v "^+++" || echo 0)
    local removed=$(diff "$pre" "$post" 2>/dev/null | grep -c "^-" | grep -v "^---" || echo 0)
    echo "${added}:${removed}"
}

# ─── 01 Kernel diff ───────────────────────────────────────────────────────────
diff_kernel() {
    local pre_k=$(grep "^$(uname -r 2>/dev/null)" "${PRE_DIR}/02_kernel.txt" 2>/dev/null || head -2 "${PRE_DIR}/02_kernel.txt" 2>/dev/null | tail -1)
    local post_k=$(head -2 "${POST_DIR}/02_kernel.txt" 2>/dev/null | tail -1)
    local pre_ver=$(grep -m1 "^[0-9]" "${PRE_DIR}/02_kernel.txt" 2>/dev/null || awk 'NR==2{print}' "${PRE_DIR}/02_kernel.txt" 2>/dev/null)
    local post_ver=$(grep -m1 "^[0-9]" "${POST_DIR}/02_kernel.txt" 2>/dev/null || awk 'NR==2{print}' "${POST_DIR}/02_kernel.txt" 2>/dev/null)

    # Extract just running kernel lines
    pre_ver=$(grep -A1 "CURRENT KERNEL" "${PRE_DIR}/02_kernel.txt"  2>/dev/null | tail -1 | xargs)
    post_ver=$(grep -A1 "CURRENT KERNEL" "${POST_DIR}/02_kernel.txt" 2>/dev/null | tail -1 | xargs)

    KERNEL_PRE="$pre_ver"
    KERNEL_POST="$post_ver"
    KERNEL_CHANGED=0
    if [ "$pre_ver" != "$post_ver" ]; then
        KERNEL_CHANGED=1
        print_check "Kernel Version" "CRITICAL" "${pre_ver} → ${post_ver}"
    else
        print_check "Kernel Version" "SAME" "${post_ver}"
    fi
}

# ─── 02 Package diff ──────────────────────────────────────────────────────────
diff_packages() {
    local pre_f="${PRE_DIR}/09_packages.txt"
    local post_f="${POST_DIR}/09_packages.txt"

    # Extract only the package list lines (NAME|VERSION|RELEASE|ARCH format)
    grep "|" "$pre_f"  2>/dev/null | grep -v "^=" | grep -v "^Total" | sort > $TMPWORK/patch_pre_pkgs.txt
    grep "|" "$post_f" 2>/dev/null | grep -v "^=" | grep -v "^Total" | sort > $TMPWORK/patch_post_pkgs.txt

    # Get package names only for comparison
    awk -F'|' '{print $1}' $TMPWORK/patch_pre_pkgs.txt  | sort -u > $TMPWORK/patch_pre_names.txt
    awk -F'|' '{print $1}' $TMPWORK/patch_post_pkgs.txt | sort -u > $TMPWORK/patch_post_names.txt

    # Newly installed
    PKG_NEW=$(comm -13 $TMPWORK/patch_pre_names.txt $TMPWORK/patch_post_names.txt 2>/dev/null)
    PKG_NEW_COUNT=$(echo "$PKG_NEW" | grep -c . 2>/dev/null || echo 0)

    # Removed packages
    PKG_REMOVED=$(comm -23 $TMPWORK/patch_pre_names.txt $TMPWORK/patch_post_names.txt 2>/dev/null)
    PKG_REMOVED_COUNT=$(echo "$PKG_REMOVED" | grep -c . 2>/dev/null || echo 0)

    # Updated (same name, different version)
    PKG_UPDATED=""
    while IFS= read -r pkg; do
        pre_line=$(grep "^${pkg}|" $TMPWORK/patch_pre_pkgs.txt  2>/dev/null | head -1)
        post_line=$(grep "^${pkg}|" $TMPWORK/patch_post_pkgs.txt 2>/dev/null | head -1)
        if [ -n "$pre_line" ] && [ -n "$post_line" ] && [ "$pre_line" != "$post_line" ]; then
            pre_ver=$(echo "$pre_line"  | awk -F'|' '{print $2"-"$3}')
            post_ver=$(echo "$post_line" | awk -F'|' '{print $2"-"$3}')
            PKG_UPDATED="${PKG_UPDATED}${pkg}|${pre_ver}|${post_ver}\n"
        fi
    done < $TMPWORK/patch_pre_names.txt
    PKG_UPDATED_COUNT=$(printf "%b" "$PKG_UPDATED" | grep -c . 2>/dev/null || echo 0)

    local pre_total=$(grep "^Total:" "$pre_f"  2>/dev/null | awk '{print $2}')
    local post_total=$(grep "^Total:" "$post_f" 2>/dev/null | awk '{print $2}')

    if [ "${PKG_NEW_COUNT}" -gt 0 ] || [ "${PKG_REMOVED_COUNT}" -gt 0 ] || [ "${PKG_UPDATED_COUNT}" -gt 0 ]; then
        print_check "Packages — Upgraded" "CHANGED" "${PKG_UPDATED_COUNT} upgraded"
        [ "$PKG_NEW_COUNT"     -gt 0 ] && print_check "Packages — Newly Installed" "NEW"     "${PKG_NEW_COUNT} new"
        [ "$PKG_REMOVED_COUNT" -gt 0 ] && print_check "Packages — Removed"         "REMOVED" "${PKG_REMOVED_COUNT} removed"
    else
        print_check "Installed Packages" "SAME" "${post_total} packages, no changes"
    fi

    PKG_PRE_TOTAL="$pre_total"
    PKG_POST_TOTAL="$post_total"
    rm -f $TMPWORK/patch_pre_pkgs.txt $TMPWORK/patch_post_pkgs.txt $TMPWORK/patch_pre_names.txt $TMPWORK/patch_post_names.txt
}

# ─── 03 Services diff ─────────────────────────────────────────────────────────
diff_services() {
    local pre_f="${PRE_DIR}/10_services.txt"
    local post_f="${POST_DIR}/10_services.txt"

    grep "running" "$pre_f"  2>/dev/null | awk '{print $1}' | sort > $TMPWORK/patch_pre_svc.txt
    grep "running" "$post_f" 2>/dev/null | awk '{print $1}' | sort > $TMPWORK/patch_post_svc.txt

    SVC_NEW=$(comm -13 $TMPWORK/patch_pre_svc.txt $TMPWORK/patch_post_svc.txt 2>/dev/null)
    SVC_NEW_COUNT=$(echo "$SVC_NEW" | grep -c "\." 2>/dev/null || echo 0)
    SVC_STOPPED=$(comm -23 $TMPWORK/patch_pre_svc.txt $TMPWORK/patch_post_svc.txt 2>/dev/null)
    SVC_STOPPED_COUNT=$(echo "$SVC_STOPPED" | grep -c "\." 2>/dev/null || echo 0)

    local pre_fail=$(grep -c "failed" "$pre_f"  2>/dev/null || echo 0)
    local post_fail=$(grep -c "failed" "$post_f" 2>/dev/null || echo 0)
    SERVICES_FAILED_POST="$post_fail"

    if [ "${SVC_NEW_COUNT}" -gt 0 ] || [ "${SVC_STOPPED_COUNT}" -gt 0 ]; then
        [ "$SVC_NEW_COUNT"     -gt 0 ] && print_check "Services — Newly Started" "NEW"     "${SVC_NEW_COUNT} service(s) now running"
        [ "$SVC_STOPPED_COUNT" -gt 0 ] && print_check "Services — Stopped"       "CHANGED" "${SVC_STOPPED_COUNT} service(s) no longer running"
    else
        print_check "Running Services" "SAME" "no state changes detected"
    fi

    if [ "${post_fail:-0}" -gt "${pre_fail:-0}" ]; then
        print_check "Failed Services (POST)" "CRITICAL" "${post_fail} failed after patching (was ${pre_fail})"
    else
        print_check "Failed Services" "SAME" "${post_fail} failed"
    fi

    rm -f $TMPWORK/patch_pre_svc.txt $TMPWORK/patch_post_svc.txt
}

# ─── 04 Kernel / OS ───────────────────────────────────────────────────────────
diff_os() {
    local pre_os=$(grep "^OS Name" "${PRE_DIR}/01_os_info.txt"  2>/dev/null | cut -d: -f2- | xargs)
    local post_os=$(grep "^OS Name" "${POST_DIR}/01_os_info.txt" 2>/dev/null | cut -d: -f2- | xargs)
    if [ "$pre_os" != "$post_os" ]; then
        print_check "OS Version" "CRITICAL" "${pre_os} → ${post_os}"
    else
        print_check "OS Version" "SAME" "${post_os}"
    fi
}

# ─── 05 Network diff ──────────────────────────────────────────────────────────
diff_network() {
    local pre_f="${PRE_DIR}/06_network.txt"
    local post_f="${POST_DIR}/06_network.txt"
    local changes=$(count_changes "$pre_f" "$post_f")
    local added=$(echo "$changes" | cut -d: -f1)
    local removed=$(echo "$changes" | cut -d: -f2)
    NET_DIFF=$(file_diff "$pre_f" "$post_f")
    if [ -n "$NET_DIFF" ]; then
        print_check "Network Configuration" "CHANGED" "+${added} -${removed} lines"
    else
        print_check "Network Configuration" "SAME" "no changes"
    fi
}

# ─── 06 Firewall diff ─────────────────────────────────────────────────────────
diff_firewall() {
    local pre_f="${PRE_DIR}/08_firewall.txt"
    local post_f="${POST_DIR}/08_firewall.txt"
    FIREWALL_DIFF=$(file_diff "$pre_f" "$post_f")
    if [ -n "$FIREWALL_DIFF" ]; then
        local added=$(echo "$FIREWALL_DIFF"   | grep -c "^+" || echo 0)
        local removed=$(echo "$FIREWALL_DIFF" | grep -c "^-" || echo 0)
        print_check "Firewall Rules" "CHANGED" "+${added} -${removed} lines"
    else
        print_check "Firewall Rules" "SAME" "no rule changes"
    fi
}

# ─── 07 Open ports diff ───────────────────────────────────────────────────────
diff_ports() {
    local pre_f="${PRE_DIR}/07_ports.txt"
    local post_f="${POST_DIR}/07_ports.txt"

    grep "LISTEN" "$pre_f"  2>/dev/null | awk '{print $NF, $(NF-1)}' | sort > $TMPWORK/patch_pre_ports.txt
    grep "LISTEN" "$post_f" 2>/dev/null | awk '{print $NF, $(NF-1)}' | sort > $TMPWORK/patch_post_ports.txt

    PORTS_NEW=$(comm -13 $TMPWORK/patch_pre_ports.txt $TMPWORK/patch_post_ports.txt 2>/dev/null)
    PORTS_CLOSED=$(comm -23 $TMPWORK/patch_pre_ports.txt $TMPWORK/patch_post_ports.txt 2>/dev/null)
    PORTS_NEW_COUNT=$(echo "$PORTS_NEW"    | grep -c "[0-9]" 2>/dev/null || echo 0)
    PORTS_CLOSED_COUNT=$(echo "$PORTS_CLOSED" | grep -c "[0-9]" 2>/dev/null || echo 0)

    if [ "${PORTS_NEW_COUNT}" -gt 0 ] || [ "${PORTS_CLOSED_COUNT}" -gt 0 ]; then
        [ "$PORTS_NEW_COUNT"    -gt 0 ] && print_check "Open Ports — New"    "NEW"     "${PORTS_NEW_COUNT} new listening port(s)"
        [ "$PORTS_CLOSED_COUNT" -gt 0 ] && print_check "Open Ports — Closed" "CHANGED" "${PORTS_CLOSED_COUNT} port(s) no longer listening"
    else
        print_check "Open Ports" "SAME" "no port changes"
    fi
    rm -f $TMPWORK/patch_pre_ports.txt $TMPWORK/patch_post_ports.txt
}

# ─── 08 SELinux diff ──────────────────────────────────────────────────────────
diff_selinux() {
    local pre_sel=$(grep -m1 "^Enforcing\|^Permissive\|^Disabled" "${PRE_DIR}/11_selinux_apparmor.txt"  2>/dev/null || echo "N/A")
    local post_sel=$(grep -m1 "^Enforcing\|^Permissive\|^Disabled" "${POST_DIR}/11_selinux_apparmor.txt" 2>/dev/null || echo "N/A")
    SEL_PRE="$pre_sel"; SEL_POST="$post_sel"
    if [ "$pre_sel" != "$post_sel" ]; then
        print_check "SELinux / AppArmor" "CRITICAL" "${pre_sel} → ${post_sel}"
    else
        print_check "SELinux / AppArmor" "SAME" "${post_sel}"
    fi
}

# ─── 09 /etc Checksums diff ───────────────────────────────────────────────────
diff_etc() {
    local pre_f="${PRE_DIR}/14_etc_checksums.txt"
    local post_f="${POST_DIR}/14_etc_checksums.txt"

    grep "^[a-f0-9]" "$pre_f"  2>/dev/null | sort > $TMPWORK/patch_pre_etc.txt
    grep "^[a-f0-9]" "$post_f" 2>/dev/null | sort > $TMPWORK/patch_post_etc.txt

    # Files with changed checksums
    awk '{print $2, $1}' $TMPWORK/patch_pre_etc.txt  | sort > $TMPWORK/patch_pre_etc_inv.txt
    awk '{print $2, $1}' $TMPWORK/patch_post_etc.txt | sort > $TMPWORK/patch_post_etc_inv.txt

    ETC_MODIFIED=$(join -j 1 $TMPWORK/patch_pre_etc_inv.txt $TMPWORK/patch_post_etc_inv.txt 2>/dev/null | awk '$2 != $3 {print $1}' | head -50)
    ETC_NEW=$(comm -13 <(awk '{print $1}' $TMPWORK/patch_pre_etc_inv.txt | sort) <(awk '{print $1}' $TMPWORK/patch_post_etc_inv.txt | sort) 2>/dev/null | head -30)
    ETC_REMOVED=$(comm -23 <(awk '{print $1}' $TMPWORK/patch_pre_etc_inv.txt | sort) <(awk '{print $1}' $TMPWORK/patch_post_etc_inv.txt | sort) 2>/dev/null | head -30)

    ETC_MOD_COUNT=$(echo "$ETC_MODIFIED" | grep -c "/" 2>/dev/null || echo 0)
    ETC_NEW_COUNT=$(echo "$ETC_NEW"      | grep -c "/" 2>/dev/null || echo 0)
    ETC_REM_COUNT=$(echo "$ETC_REMOVED"  | grep -c "/" 2>/dev/null || echo 0)

    if [ "${ETC_MOD_COUNT}" -gt 0 ] || [ "${ETC_NEW_COUNT}" -gt 0 ] || [ "${ETC_REM_COUNT}" -gt 0 ]; then
        [ "$ETC_MOD_COUNT" -gt 0 ] && print_check "/etc Files Modified" "CHANGED" "${ETC_MOD_COUNT} config file(s) changed"
        [ "$ETC_NEW_COUNT" -gt 0 ] && print_check "/etc Files New"      "NEW"     "${ETC_NEW_COUNT} new config file(s)"
        [ "$ETC_REM_COUNT" -gt 0 ] && print_check "/etc Files Removed"  "REMOVED" "${ETC_REM_COUNT} config file(s) removed"
    else
        print_check "/etc Config Files" "SAME" "no checksum changes"
    fi
    rm -f $TMPWORK/patch_pre_etc.txt $TMPWORK/patch_post_etc.txt $TMPWORK/patch_pre_etc_inv.txt $TMPWORK/patch_post_etc_inv.txt
}

# ─── 10 Disk diff ─────────────────────────────────────────────────────────────
diff_disk() {
    local pre_f="${PRE_DIR}/05_disk.txt"
    local post_f="${POST_DIR}/05_disk.txt"
    grep "^/" "$pre_f"  2>/dev/null | awk '{print $1,$5}' | sort > $TMPWORK/patch_pre_disk.txt
    grep "^/" "$post_f" 2>/dev/null | awk '{print $1,$5}' | sort > $TMPWORK/patch_post_disk.txt
    DISK_DIFF=$(diff $TMPWORK/patch_pre_disk.txt $TMPWORK/patch_post_disk.txt 2>/dev/null)
    if [ -n "$DISK_DIFF" ]; then
        print_check "Disk Usage" "CHANGED" "mount point usage changed"
    else
        print_check "Disk Usage" "SAME" "no changes"
    fi
    rm -f $TMPWORK/patch_pre_disk.txt $TMPWORK/patch_post_disk.txt
}

# ─── 11 Users diff ────────────────────────────────────────────────────────────
diff_users() {
    local pre_f="${PRE_DIR}/13_users.txt"
    local post_f="${POST_DIR}/13_users.txt"
    grep "^.*:.*:.*:.*:.*:.*:" "$pre_f"  2>/dev/null | grep -v "^#" | sort > $TMPWORK/patch_pre_users.txt
    grep "^.*:.*:.*:.*:.*:.*:" "$post_f" 2>/dev/null | grep -v "^#" | sort > $TMPWORK/patch_post_users.txt
    USERS_NEW=$(comm -13 $TMPWORK/patch_pre_users.txt $TMPWORK/patch_post_users.txt 2>/dev/null | awk -F: '{print $1}' | tr '\n' ' ')
    USERS_REM=$(comm -23 $TMPWORK/patch_pre_users.txt $TMPWORK/patch_post_users.txt 2>/dev/null | awk -F: '{print $1}' | tr '\n' ' ')
    if [ -n "$USERS_NEW" ] || [ -n "$USERS_REM" ]; then
        [ -n "$USERS_NEW" ] && print_check "User Accounts — New"     "CRITICAL" "New users: ${USERS_NEW}"
        [ -n "$USERS_REM" ] && print_check "User Accounts — Removed" "CHANGED"  "Removed: ${USERS_REM}"
    else
        print_check "User Accounts" "SAME" "no account changes"
    fi
    rm -f $TMPWORK/patch_pre_users.txt $TMPWORK/patch_post_users.txt
}

# ─── 12 Cron diff ─────────────────────────────────────────────────────────────
diff_cron() {
    local pre_f="${PRE_DIR}/12_cron.txt"
    local post_f="${POST_DIR}/12_cron.txt"
    CRON_DIFF=$(file_diff "$pre_f" "$post_f")
    if [ -n "$CRON_DIFF" ]; then
        local added=$(echo "$CRON_DIFF"   | grep -c "^+" || echo 0)
        local removed=$(echo "$CRON_DIFF" | grep -c "^-" || echo 0)
        print_check "Cron Jobs / Timers" "CHANGED" "+${added} -${removed} lines"
    else
        print_check "Cron Jobs / Timers" "SAME" "no changes"
    fi
}

# ─── 13 Reboot check ──────────────────────────────────────────────────────────
diff_reboots() {
    local pre_up=$(grep "^up " "${PRE_DIR}/17_reboot_history.txt"  2>/dev/null | head -1 || \
                   grep "system boot" "${PRE_DIR}/17_reboot_history.txt" 2>/dev/null | head -1)
    local post_up=$(grep "^up " "${POST_DIR}/17_reboot_history.txt"  2>/dev/null | head -1 || \
                    grep "system boot" "${POST_DIR}/17_reboot_history.txt" 2>/dev/null | head -1)
    local pre_boots=$(grep -c "system boot\|reboot" "${PRE_DIR}/17_reboot_history.txt"  2>/dev/null || echo 0)
    local post_boots=$(grep -c "system boot\|reboot" "${POST_DIR}/17_reboot_history.txt" 2>/dev/null || echo 0)
    REBOOT_COUNT_PRE="$pre_boots"
    REBOOT_COUNT_POST="$post_boots"
    if [ "$post_boots" -gt "$pre_boots" ]; then
        print_check "System Reboots" "CHANGED" "Server was rebooted during patching ✓"
    else
        print_check "System Reboots" "SAME" "No reboot detected since pre-snapshot"
    fi
}

# =============================================================================
#  HTML GENERATION
# =============================================================================
html_escape() { sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g'; }

build_pkg_updated_rows() {
    if [ -z "$PKG_UPDATED" ]; then
        echo "<tr><td colspan='3' style='text-align:center;color:var(--text-dim);padding:20px'>No packages upgraded</td></tr>"
        return
    fi
    printf "%b" "$PKG_UPDATED" | grep "|" | while IFS='|' read -r name pre post; do
        echo "<tr><td>${name}</td><td class='ver-pre'>${pre}</td><td class='ver-post'>${post}</td></tr>"
    done
}

build_pkg_new_rows() {
    if [ -z "$PKG_NEW" ]; then
        echo "<tr><td colspan='2' style='text-align:center;color:var(--text-dim);padding:20px'>None</td></tr>"
        return
    fi
    echo "$PKG_NEW" | grep -v "^$" | while read -r name; do
        local ver=$(grep "^${name}|" "${POST_DIR}/09_packages.txt" 2>/dev/null | head -1 | awk -F'|' '{print $2}')
        echo "<tr><td>${name}</td><td class='ver-post'>${ver:-—}</td></tr>"
    done
}

build_pkg_removed_rows() {
    if [ -z "$PKG_REMOVED" ]; then
        echo "<tr><td colspan='2' style='text-align:center;color:var(--text-dim);padding:20px'>None</td></tr>"
        return
    fi
    echo "$PKG_REMOVED" | grep -v "^$" | while read -r name; do
        local ver=$(grep "^${name}|" "${PRE_DIR}/09_packages.txt" 2>/dev/null | head -1 | awk -F'|' '{print $2}')
        echo "<tr><td>${name}</td><td class='ver-pre'>${ver:-—}</td></tr>"
    done
}

build_etc_rows() {
    local list="$1"; local class="$2"
    if [ -z "$list" ]; then
        echo "<tr><td style='text-align:center;color:var(--text-dim);padding:12px'>None</td></tr>"
        return
    fi
    echo "$list" | grep "/" | while read -r f; do
        echo "<tr><td class='${class}'>${f}</td></tr>"
    done
}

build_diff_block() {
    local pre="$1"; local post="$2"
    diff --unified=3 "$pre" "$post" 2>/dev/null | html_escape | \
    sed 's/^+/<span class="diff-add">+/; s/^-/<span class="diff-del">-/; s/^@@/<span class="diff-hunk">@@/' | \
    sed 's/^<span class="diff-add">.*$/&<\/span>/; s/^<span class="diff-del">.*$/&<\/span>/; s/^<span class="diff-hunk">.*$/&<\/span>/'
}

generate_html() {
    local PRE_TS=$(basename "$PRE_DIR"  | sed 's/.*_pre_//')
    local POST_TS=$(basename "$POST_DIR" | sed 's/.*_post_//')
    local PRE_DATE=$(echo "$PRE_TS"  | sed 's/\([0-9]\{8\}\)_\([0-9]\{6\}\)/\1 \2/' | sed 's/\([0-9]\{4\}\)\([0-9]\{2\}\)\([0-9]\{2\}\) \([0-9]\{2\}\)\([0-9]\{2\}\)\([0-9]\{2\}\)/\1-\2-\3 \4:\5:\6/')
    local POST_DATE=$(echo "$POST_TS" | sed 's/\([0-9]\{8\}\)_\([0-9]\{6\}\)/\1 \2/' | sed 's/\([0-9]\{4\}\)\([0-9]\{2\}\)\([0-9]\{2\}\) \([0-9]\{2\}\)\([0-9]\{2\}\)\([0-9]\{2\}\)/\1-\2-\3 \4:\5:\6/')

    # Summary counts
    local total_changed=0
    local total_critical=0
    [ "$KERNEL_CHANGED" -eq 1 ] && total_changed=$((total_changed+1))
    [ "${PKG_UPDATED_COUNT:-0}"  -gt 0 ] && total_changed=$((total_changed+1))
    [ "${PKG_NEW_COUNT:-0}"      -gt 0 ] && total_changed=$((total_changed+1))
    [ "${PKG_REMOVED_COUNT:-0}"  -gt 0 ] && total_changed=$((total_changed+1))
    [ "${ETC_MOD_COUNT:-0}"      -gt 0 ] && total_changed=$((total_changed+1)) && total_critical=$((total_critical+1))
    [ "${SERVICES_FAILED_POST:-0}" -gt 0 ] && total_critical=$((total_critical+1))

    cat > "$HTML_REPORT" << HTMLEOF
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>Patch Diff Report — $(hostname -s) — $(date '+%Y-%m-%d')</title>
<!-- No external resources — fully offline/air-gapped safe -->
<style>
  :root {
    --bg:        #080c18;
    --bg2:       #0c1220;
    --bg3:       #111828;
    --border:    #1a2840;
    --add:       #00ff88;
    --del:       #ff4757;
    --changed:   #ffd166;
    --same:      #00d4ff;
    --critical:  #ff4757;
    --new:       #00ff88;
    --text:      #b8cfe0;
    --text-dim:  #486680;
    --text-hi:   #ffffff;
    --mono:      'Courier New', Courier, 'Lucida Console', monospace;
    --sans:      'Trebuchet MS', 'Segoe UI', Arial, sans-serif;
  }
  * { box-sizing:border-box; margin:0; padding:0; }
  body { background:var(--bg); color:var(--text); font-family:var(--sans); }

  /* Header */
  .header {
    background: linear-gradient(135deg, #080c18, #0d1525, #080c18);
    border-bottom: 1px solid var(--border);
    position: relative; overflow: hidden;
  }
  .header::before {
    content:''; position:absolute; inset:0;
    background:
      radial-gradient(ellipse 50% 100% at 90% 50%, rgba(255,71,87,0.05) 0%, transparent 70%),
      radial-gradient(ellipse 50% 80%  at 10% 50%, rgba(0,212,255,0.04) 0%, transparent 60%);
  }
  .header-inner {
    position:relative; max-width:1400px; margin:0 auto;
    padding:36px 48px 28px;
    display:flex; align-items:flex-start; justify-content:space-between;
    gap:24px; flex-wrap:wrap;
  }
  .badge {
    display:inline-flex; align-items:center; gap:8px;
    background:rgba(0,212,255,0.08); border:1px solid rgba(0,212,255,0.25);
    border-radius:4px; padding:4px 12px;
    font-family:var(--mono); font-size:10px; font-weight:600;
    color:#00d4ff; letter-spacing:0.15em; text-transform:uppercase; margin-bottom:14px;
  }
  .header h1 { font-family:var(--sans);font-size:2.2rem;font-weight:800;color:var(--text-hi);letter-spacing:-0.02em;margin-bottom:10px; }
  .header h1 span { color:#00d4ff; }
  .timeline {
    display:flex; align-items:center; gap:12px;
    font-family:var(--mono); font-size:11px; color:var(--text-dim); flex-wrap:wrap;
  }
  .tl-box {
    background:var(--bg3); border:1px solid var(--border);
    border-radius:6px; padding:8px 14px;
  }
  .tl-box strong { color:var(--text); display:block; font-size:12px; margin-bottom:2px; }
  .tl-arrow { color:var(--border); font-size:18px; }
  .header-right { display:flex; flex-direction:column; gap:8px; align-items:flex-end; }
  .meta-pill { background:var(--bg3);border:1px solid var(--border);border-radius:6px;padding:8px 16px;font-family:var(--mono);font-size:11px;color:var(--text-dim);text-align:right; }
  .meta-pill strong { color:var(--text); display:block; font-size:13px; }

  /* Summary cards */
  .summary-bar { background:var(--bg2); border-bottom:1px solid var(--border); }
  .summary-inner { max-width:1400px; margin:0 auto; padding:0 48px; display:grid; grid-template-columns:repeat(auto-fit, minmax(150px,1fr)); }
  .sum-card { padding:20px 24px; border-right:1px solid var(--border); }
  .sum-card:last-child { border-right:none; }
  .sum-label { font-family:var(--mono);font-size:10px;font-weight:600;letter-spacing:0.12em;text-transform:uppercase;color:var(--text-dim);margin-bottom:6px; }
  .sum-val { font-family:var(--mono);font-size:1.6rem;font-weight:700;line-height:1; }
  .sum-val.blue    { color:#00d4ff; }
  .sum-val.green   { color:var(--add); }
  .sum-val.yellow  { color:var(--changed); }
  .sum-val.red     { color:var(--critical); }
  .sum-val.orange  { color:#ff6b35; }
  .sum-sub { font-family:var(--mono); font-size:10px; color:var(--text-dim); margin-top:4px; }

  /* Layout */
  .main { max-width:1400px; margin:0 auto; padding:28px 48px 60px; display:grid; grid-template-columns:200px 1fr; gap:28px; }
  .sidebar { position:sticky; top:24px; align-self:flex-start; }
  .nav-group-label { font-family:var(--mono);font-size:9px;font-weight:700;letter-spacing:0.15em;text-transform:uppercase;color:var(--text-dim);padding:0 0 8px 10px;margin-top:18px; }
  .nav-group-label:first-child { margin-top:0; }
  .nav-item { display:flex;align-items:center;gap:8px;padding:7px 10px;border-radius:5px;cursor:pointer;font-family:var(--mono);font-size:11px;color:var(--text-dim);text-decoration:none;border:1px solid transparent;margin-bottom:2px;transition:all 0.15s; }
  .nav-item:hover { color:var(--text);background:var(--bg3);border-color:var(--border); }
  .nav-item.active { color:#00d4ff;background:rgba(0,212,255,0.06);border-color:rgba(0,212,255,0.2); }
  .nav-dot { width:6px;height:6px;border-radius:50%;flex-shrink:0; }
  .dot-changed  { background:var(--changed); }
  .dot-same     { background:var(--same); opacity:0.4; }
  .dot-critical { background:var(--critical); }
  .dot-new      { background:var(--new); }

  .content { min-width:0; }

  /* Diff section */
  .dsection { background:var(--bg2);border:1px solid var(--border);border-radius:10px;margin-bottom:16px;overflow:hidden;scroll-margin-top:24px; }
  .dsection-header { display:flex;align-items:center;justify-content:space-between;padding:14px 20px;background:var(--bg3);border-bottom:1px solid var(--border);cursor:pointer;user-select:none; }
  .dsection-header:hover { background:rgba(26,40,64,0.8); }
  .dtitle-row { display:flex;align-items:center;gap:10px; }
  .dicon { width:30px;height:30px;border-radius:7px;display:flex;align-items:center;justify-content:center;font-size:14px;flex-shrink:0; }
  .dicon.changed  { background:rgba(255,209,102,0.1); border:1px solid rgba(255,209,102,0.25); }
  .dicon.same     { background:rgba(0,212,255,0.06);  border:1px solid rgba(0,212,255,0.15); }
  .dicon.critical { background:rgba(255,71,87,0.1);   border:1px solid rgba(255,71,87,0.25); }
  .dicon.new      { background:rgba(0,255,136,0.08);  border:1px solid rgba(0,255,136,0.2); }
  .dtitle { font-family:var(--sans);font-size:13px;font-weight:700;color:var(--text-hi); }
  .dsubtitle { font-family:var(--mono);font-size:10px;color:var(--text-dim);margin-top:2px; }
  .dstatus-pill {
    font-family:var(--mono);font-size:10px;font-weight:700;
    padding:3px 10px;border-radius:4px;letter-spacing:0.06em;text-transform:uppercase;
  }
  .pill-changed  { background:rgba(255,209,102,0.12); color:var(--changed); border:1px solid rgba(255,209,102,0.3); }
  .pill-same     { background:rgba(0,212,255,0.06);   color:#00d4ff;        border:1px solid rgba(0,212,255,0.2); }
  .pill-critical { background:rgba(255,71,87,0.1);    color:var(--critical);border:1px solid rgba(255,71,87,0.3); }
  .pill-new      { background:rgba(0,255,136,0.08);   color:var(--new);     border:1px solid rgba(0,255,136,0.25); }
  .pill-removed  { background:rgba(255,107,53,0.08);  color:#ff6b35;        border:1px solid rgba(255,107,53,0.25); }
  .dtoggle { font-size:16px;color:var(--text-dim);transition:transform 0.2s; }
  .dtoggle.open { transform:rotate(180deg); }
  .dsection-body { display:none; padding:20px; }
  .dsection-body.open { display:block; }

  /* Tables */
  .diff-table { width:100%; border-collapse:collapse; font-family:var(--mono); font-size:11.5px; margin-bottom:16px; }
  .diff-table th { background:var(--bg3);color:var(--text-dim);font-weight:600;padding:8px 12px;text-align:left;border-bottom:1px solid var(--border);letter-spacing:0.05em;font-size:10px;text-transform:uppercase; }
  .diff-table td { padding:7px 12px;border-bottom:1px solid rgba(26,40,64,0.5);color:var(--text);vertical-align:top; }
  .diff-table tr:last-child td { border-bottom:none; }
  .diff-table tr:hover td { background:rgba(26,40,64,0.4); }
  .ver-pre  { color:#ff6b6b; }
  .ver-post { color:var(--add); }

  /* Diff code block */
  .diff-block { font-family:var(--mono);font-size:11px;line-height:1.7;background:var(--bg);border:1px solid var(--border);border-radius:6px;padding:16px;max-height:400px;overflow-y:auto;white-space:pre-wrap;word-break:break-all; }
  .diff-add  { color:var(--add); display:block; background:rgba(0,255,136,0.04); }
  .diff-del  { color:var(--del); display:block; background:rgba(255,71,87,0.04); }
  .diff-hunk { color:#00d4ff;   display:block; opacity:0.6; }
  .diff-block::-webkit-scrollbar{width:6px}
  .diff-block::-webkit-scrollbar-track{background:var(--bg2)}
  .diff-block::-webkit-scrollbar-thumb{background:var(--border);border-radius:3px}

  /* No change placeholder */
  .no-change { text-align:center;color:var(--text-dim);font-family:var(--mono);font-size:12px;padding:28px;background:var(--bg);border:1px solid var(--border);border-radius:6px; }

  /* Footer */
  .footer { border-top:1px solid var(--border);padding:24px 48px;max-width:1400px;margin:0 auto;display:flex;justify-content:space-between;align-items:center;font-family:var(--mono);font-size:11px;color:var(--text-dim); }

  @media(max-width:900px){.main{grid-template-columns:1fr;padding:16px}.sidebar{position:static}.header-inner,.summary-inner,.footer{padding-left:16px;padding-right:16px}}
</style>
</head>
<body>

<!-- HEADER -->
<div class="header">
  <div class="header-inner">
    <div>
      <div class="badge">⚡ PATCH DIFF REPORT</div>
      <h1>$(hostname -s) <span>diff</span></h1>
      <div class="timeline">
        <div class="tl-box"><strong>${PRE_DATE:-Pre-Patch}</strong>PRE-PATCH</div>
        <div class="tl-arrow">→</div>
        <div class="tl-box"><strong>${POST_DATE:-Post-Patch}</strong>POST-PATCH</div>
      </div>
    </div>
    <div class="header-right">
      <div class="meta-pill"><strong>$(hostname -f)</strong>Server</div>
      <div class="meta-pill"><strong>${OS_PRETTY}</strong>OS</div>
      <div class="meta-pill"><strong>$(date '+%Y-%m-%d %H:%M:%S')</strong>Report Generated</div>
    </div>
  </div>
</div>

<!-- SUMMARY BAR -->
<div class="summary-bar">
  <div class="summary-inner">
    <div class="sum-card">
      <div class="sum-label">Kernel</div>
      <div class="sum-val $([ "$KERNEL_CHANGED" -eq 1 ] && echo yellow || echo green)">$([ "$KERNEL_CHANGED" -eq 1 ] && echo "Changed" || echo "Same")</div>
      <div class="sum-sub">${KERNEL_PRE:-—} → ${KERNEL_POST:-—}</div>
    </div>
    <div class="sum-card">
      <div class="sum-label">Upgraded</div>
      <div class="sum-val yellow">${PKG_UPDATED_COUNT:-0}</div>
      <div class="sum-sub">packages</div>
    </div>
    <div class="sum-card">
      <div class="sum-label">New Pkgs</div>
      <div class="sum-val green">${PKG_NEW_COUNT:-0}</div>
      <div class="sum-sub">installed</div>
    </div>
    <div class="sum-card">
      <div class="sum-label">Removed</div>
      <div class="sum-val orange">${PKG_REMOVED_COUNT:-0}</div>
      <div class="sum-sub">packages</div>
    </div>
    <div class="sum-card">
      <div class="sum-label">/etc Changes</div>
      <div class="sum-val $([ "${ETC_MOD_COUNT:-0}" -gt 0 ] && echo red || echo green)">${ETC_MOD_COUNT:-0}</div>
      <div class="sum-sub">config files</div>
    </div>
    <div class="sum-card">
      <div class="sum-label">Failed Svc</div>
      <div class="sum-val $([ "${SERVICES_FAILED_POST:-0}" -gt 0 ] && echo red || echo green)">${SERVICES_FAILED_POST:-0}</div>
      <div class="sum-sub">post-patch</div>
    </div>
    <div class="sum-card">
      <div class="sum-label">Pre Pkgs</div>
      <div class="sum-val blue">${PKG_PRE_TOTAL:-—}</div>
      <div class="sum-sub">before patch</div>
    </div>
    <div class="sum-card">
      <div class="sum-label">Post Pkgs</div>
      <div class="sum-val blue">${PKG_POST_TOTAL:-—}</div>
      <div class="sum-sub">after patch</div>
    </div>
  </div>
</div>

<!-- MAIN -->
<div class="main">
  <aside class="sidebar">
    <div class="nav-group-label">System</div>
    <a class="nav-item active" href="#diff-kernel"  onclick="sa(this)"><span class="nav-dot $([ "$KERNEL_CHANGED" -eq 1 ] && echo dot-changed || echo dot-same)"></span>Kernel</a>
    <a class="nav-item"        href="#diff-os"      onclick="sa(this)"><span class="nav-dot dot-same"></span>OS Version</a>
    <a class="nav-item"        href="#diff-disk"    onclick="sa(this)"><span class="nav-dot $([ -n "$DISK_DIFF" ] && echo dot-changed || echo dot-same)"></span>Disk Usage</a>
    <div class="nav-group-label">Software</div>
    <a class="nav-item" href="#diff-pkgs-updated" onclick="sa(this)"><span class="nav-dot $([ "${PKG_UPDATED_COUNT:-0}" -gt 0 ] && echo dot-changed || echo dot-same)"></span>Upgraded Pkgs</a>
    <a class="nav-item" href="#diff-pkgs-new"     onclick="sa(this)"><span class="nav-dot $([ "${PKG_NEW_COUNT:-0}"     -gt 0 ] && echo dot-new     || echo dot-same)"></span>New Pkgs</a>
    <a class="nav-item" href="#diff-pkgs-removed" onclick="sa(this)"><span class="nav-dot $([ "${PKG_REMOVED_COUNT:-0}" -gt 0 ] && echo dot-critical || echo dot-same)"></span>Removed Pkgs</a>
    <a class="nav-item" href="#diff-services"     onclick="sa(this)"><span class="nav-dot $([ "${SERVICES_FAILED_POST:-0}" -gt 0 ] && echo dot-critical || echo dot-same)"></span>Services</a>
    <div class="nav-group-label">Network</div>
    <a class="nav-item" href="#diff-network"  onclick="sa(this)"><span class="nav-dot $([ -n "$NET_DIFF" ]      && echo dot-changed || echo dot-same)"></span>Network</a>
    <a class="nav-item" href="#diff-ports"    onclick="sa(this)"><span class="nav-dot $([ "${PORTS_NEW_COUNT:-0}" -gt 0 ] && echo dot-new || [ "${PORTS_CLOSED_COUNT:-0}" -gt 0 ] && echo dot-critical || echo dot-same)"></span>Open Ports</a>
    <a class="nav-item" href="#diff-firewall" onclick="sa(this)"><span class="nav-dot $([ -n "$FIREWALL_DIFF" ] && echo dot-changed || echo dot-same)"></span>Firewall</a>
    <div class="nav-group-label">Security</div>
    <a class="nav-item" href="#diff-selinux"  onclick="sa(this)"><span class="nav-dot $([ "$SEL_PRE" != "$SEL_POST" ] && echo dot-critical || echo dot-same)"></span>SELinux/AppArmor</a>
    <a class="nav-item" href="#diff-users"    onclick="sa(this)"><span class="nav-dot $([ -n "$USERS_NEW" ] && echo dot-critical || echo dot-same)"></span>Users</a>
    <a class="nav-item" href="#diff-etc"      onclick="sa(this)"><span class="nav-dot $([ "${ETC_MOD_COUNT:-0}" -gt 0 ] && echo dot-critical || echo dot-same)"></span>/etc Files</a>
    <div class="nav-group-label">Automation</div>
    <a class="nav-item" href="#diff-cron"     onclick="sa(this)"><span class="nav-dot $([ -n "$CRON_DIFF" ] && echo dot-changed || echo dot-same)"></span>Cron</a>
    <a class="nav-item" href="#diff-reboots"  onclick="sa(this)"><span class="nav-dot $([ "${REBOOT_COUNT_POST:-0}" -gt "${REBOOT_COUNT_PRE:-0}" ] && echo dot-new || echo dot-same)"></span>Reboots</a>
  </aside>

  <div class="content">

    <!-- Kernel -->
    <div class="dsection" id="diff-kernel">
      <div class="dsection-header" onclick="tog(this)">
        <div class="dtitle-row">
          <div class="dicon $([ "$KERNEL_CHANGED" -eq 1 ] && echo changed || echo same)">⚙</div>
          <div><div class="dtitle">Kernel Version</div><div class="dsubtitle">${KERNEL_PRE:-—} → ${KERNEL_POST:-—}</div></div>
        </div>
        <div style="display:flex;align-items:center;gap:10px">
          <span class="dstatus-pill $([ "$KERNEL_CHANGED" -eq 1 ] && echo pill-changed || echo pill-same)">$([ "$KERNEL_CHANGED" -eq 1 ] && echo "CHANGED" || echo "NO CHANGE")</span>
          <span class="dtoggle open">▼</span>
        </div>
      </div>
      <div class="dsection-body open">
$(if [ "$KERNEL_CHANGED" -eq 1 ]; then
cat << KEOF
        <table class="diff-table">
          <tr><th>Field</th><th>Pre-Patch</th><th>Post-Patch</th></tr>
          <tr><td>Running Kernel</td><td class="ver-pre">${KERNEL_PRE:-—}</td><td class="ver-post">${KERNEL_POST:-—}</td></tr>
        </table>
        <div class="diff-block">$(build_diff_block "${PRE_DIR}/02_kernel.txt" "${POST_DIR}/02_kernel.txt")</div>
KEOF
else
cat << NKEOF
        <div class="no-change">✔ &nbsp; Kernel unchanged — ${KERNEL_POST:-—}</div>
NKEOF
fi)
      </div>
    </div>

    <!-- OS -->
    <div class="dsection" id="diff-os">
      <div class="dsection-header" onclick="tog(this)">
        <div class="dtitle-row"><div class="dicon same">🖥</div><div><div class="dtitle">OS Version</div><div class="dsubtitle">${OS_PRETTY}</div></div></div>
        <div style="display:flex;align-items:center;gap:10px"><span class="dstatus-pill pill-same">NO CHANGE</span><span class="dtoggle">▼</span></div>
      </div>
      <div class="dsection-body">
        <div class="no-change">✔ &nbsp; OS version unchanged — ${OS_PRETTY}</div>
      </div>
    </div>

    <!-- Disk -->
    <div class="dsection" id="diff-disk">
      <div class="dsection-header" onclick="tog(this)">
        <div class="dtitle-row">
          <div class="dicon $([ -n "$DISK_DIFF" ] && echo changed || echo same)">🗄</div>
          <div><div class="dtitle">Disk Usage</div><div class="dsubtitle">Filesystem utilization comparison</div></div>
        </div>
        <div style="display:flex;align-items:center;gap:10px">
          <span class="dstatus-pill $([ -n "$DISK_DIFF" ] && echo pill-changed || echo pill-same)">$([ -n "$DISK_DIFF" ] && echo "CHANGED" || echo "NO CHANGE")</span>
          <span class="dtoggle">▼</span>
        </div>
      </div>
      <div class="dsection-body">
$(if [ -n "$DISK_DIFF" ]; then
echo "        <div class=\"diff-block\">$(build_diff_block "${PRE_DIR}/05_disk.txt" "${POST_DIR}/05_disk.txt")</div>"
else
echo "        <div class=\"no-change\">✔ &nbsp; Disk usage unchanged</div>"
fi)
      </div>
    </div>

    <!-- Packages Upgraded -->
    <div class="dsection" id="diff-pkgs-updated">
      <div class="dsection-header" onclick="tog(this)">
        <div class="dtitle-row">
          <div class="dicon $([ "${PKG_UPDATED_COUNT:-0}" -gt 0 ] && echo changed || echo same)">📦</div>
          <div><div class="dtitle">Packages — Upgraded</div><div class="dsubtitle">${PKG_UPDATED_COUNT:-0} package(s) version changed</div></div>
        </div>
        <div style="display:flex;align-items:center;gap:10px">
          <span class="dstatus-pill $([ "${PKG_UPDATED_COUNT:-0}" -gt 0 ] && echo pill-changed || echo pill-same)">${PKG_UPDATED_COUNT:-0} UPGRADED</span>
          <span class="dtoggle open">▼</span>
        </div>
      </div>
      <div class="dsection-body open">
        <table class="diff-table">
          <tr><th>Package</th><th>Version Before</th><th>Version After</th></tr>
          $(build_pkg_updated_rows)
        </table>
      </div>
    </div>

    <!-- Packages New -->
    <div class="dsection" id="diff-pkgs-new">
      <div class="dsection-header" onclick="tog(this)">
        <div class="dtitle-row">
          <div class="dicon $([ "${PKG_NEW_COUNT:-0}" -gt 0 ] && echo new || echo same)">📦</div>
          <div><div class="dtitle">Packages — Newly Installed</div><div class="dsubtitle">${PKG_NEW_COUNT:-0} new package(s)</div></div>
        </div>
        <div style="display:flex;align-items:center;gap:10px">
          <span class="dstatus-pill $([ "${PKG_NEW_COUNT:-0}" -gt 0 ] && echo pill-new || echo pill-same)">${PKG_NEW_COUNT:-0} NEW</span>
          <span class="dtoggle">▼</span>
        </div>
      </div>
      <div class="dsection-body">
        <table class="diff-table">
          <tr><th>Package</th><th>Version</th></tr>
          $(build_pkg_new_rows)
        </table>
      </div>
    </div>

    <!-- Packages Removed -->
    <div class="dsection" id="diff-pkgs-removed">
      <div class="dsection-header" onclick="tog(this)">
        <div class="dtitle-row">
          <div class="dicon $([ "${PKG_REMOVED_COUNT:-0}" -gt 0 ] && echo critical || echo same)">📦</div>
          <div><div class="dtitle">Packages — Removed</div><div class="dsubtitle">${PKG_REMOVED_COUNT:-0} package(s) removed</div></div>
        </div>
        <div style="display:flex;align-items:center;gap:10px">
          <span class="dstatus-pill $([ "${PKG_REMOVED_COUNT:-0}" -gt 0 ] && echo pill-removed || echo pill-same)">${PKG_REMOVED_COUNT:-0} REMOVED</span>
          <span class="dtoggle">▼</span>
        </div>
      </div>
      <div class="dsection-body">
        <table class="diff-table">
          <tr><th>Package</th><th>Version (removed)</th></tr>
          $(build_pkg_removed_rows)
        </table>
      </div>
    </div>

    <!-- Services -->
    <div class="dsection" id="diff-services">
      <div class="dsection-header" onclick="tog(this)">
        <div class="dtitle-row">
          <div class="dicon $([ "${SERVICES_FAILED_POST:-0}" -gt 0 ] && echo critical || echo same)">⚡</div>
          <div><div class="dtitle">Services</div><div class="dsubtitle">${SVC_NEW_COUNT:-0} new, ${SVC_STOPPED_COUNT:-0} stopped, ${SERVICES_FAILED_POST:-0} failed post-patch</div></div>
        </div>
        <div style="display:flex;align-items:center;gap:10px">
          <span class="dstatus-pill $([ "${SERVICES_FAILED_POST:-0}" -gt 0 ] && echo pill-critical || [ "${SVC_NEW_COUNT:-0}" -gt 0 ] || [ "${SVC_STOPPED_COUNT:-0}" -gt 0 ] && echo pill-changed || echo pill-same)">$([ "${SERVICES_FAILED_POST:-0}" -gt 0 ] && echo "CRITICAL" || [ "${SVC_NEW_COUNT:-0}" -gt 0 ] || [ "${SVC_STOPPED_COUNT:-0}" -gt 0 ] && echo "CHANGED" || echo "NO CHANGE")</span>
          <span class="dtoggle">▼</span>
        </div>
      </div>
      <div class="dsection-body">
$(if [ "${SVC_NEW_COUNT:-0}" -gt 0 ] || [ "${SVC_STOPPED_COUNT:-0}" -gt 0 ] || [ "${SERVICES_FAILED_POST:-0}" -gt 0 ]; then
cat << SVEOF
        <table class="diff-table">
          <tr><th>Service</th><th>Status Change</th></tr>
$(echo "$SVC_NEW"     | grep "\." | while read s; do echo "<tr><td>${s}</td><td class='ver-post'>Now Running</td></tr>"; done)
$(echo "$SVC_STOPPED" | grep "\." | while read s; do echo "<tr><td>${s}</td><td class='ver-pre'>Stopped</td></tr>";     done)
        </table>
        <div class="diff-block">$(build_diff_block "${PRE_DIR}/10_services.txt" "${POST_DIR}/10_services.txt")</div>
SVEOF
else
echo "        <div class=\"no-change\">✔ &nbsp; No service state changes detected</div>"
fi)
      </div>
    </div>

    <!-- Network -->
    <div class="dsection" id="diff-network">
      <div class="dsection-header" onclick="tog(this)">
        <div class="dtitle-row">
          <div class="dicon $([ -n "$NET_DIFF" ] && echo changed || echo same)">🌐</div>
          <div><div class="dtitle">Network Configuration</div><div class="dsubtitle">IPs, routes, DNS, /etc/hosts</div></div>
        </div>
        <div style="display:flex;align-items:center;gap:10px">
          <span class="dstatus-pill $([ -n "$NET_DIFF" ] && echo pill-changed || echo pill-same)">$([ -n "$NET_DIFF" ] && echo "CHANGED" || echo "NO CHANGE")</span>
          <span class="dtoggle">▼</span>
        </div>
      </div>
      <div class="dsection-body">
$([ -n "$NET_DIFF" ] && echo "        <div class=\"diff-block\">$(build_diff_block "${PRE_DIR}/06_network.txt" "${POST_DIR}/06_network.txt")</div>" || echo "        <div class=\"no-change\">✔ &nbsp; Network configuration unchanged</div>")
      </div>
    </div>

    <!-- Ports -->
    <div class="dsection" id="diff-ports">
      <div class="dsection-header" onclick="tog(this)">
        <div class="dtitle-row">
          <div class="dicon $([ "${PORTS_NEW_COUNT:-0}" -gt 0 ] && echo new || [ "${PORTS_CLOSED_COUNT:-0}" -gt 0 ] && echo critical || echo same)">🔌</div>
          <div><div class="dtitle">Open Ports</div><div class="dsubtitle">${PORTS_NEW_COUNT:-0} new, ${PORTS_CLOSED_COUNT:-0} closed</div></div>
        </div>
        <div style="display:flex;align-items:center;gap:10px">
          <span class="dstatus-pill $([ "${PORTS_NEW_COUNT:-0}" -gt 0 ] || [ "${PORTS_CLOSED_COUNT:-0}" -gt 0 ] && echo pill-changed || echo pill-same)">$([ "${PORTS_NEW_COUNT:-0}" -gt 0 ] || [ "${PORTS_CLOSED_COUNT:-0}" -gt 0 ] && echo "CHANGED" || echo "NO CHANGE")</span>
          <span class="dtoggle">▼</span>
        </div>
      </div>
      <div class="dsection-body">
$(if [ "${PORTS_NEW_COUNT:-0}" -gt 0 ] || [ "${PORTS_CLOSED_COUNT:-0}" -gt 0 ]; then
cat << PORTEOF
        <table class="diff-table">
          <tr><th>Port / Service</th><th>Change</th></tr>
$(echo "$PORTS_NEW"    | grep "[0-9]" | while read p; do echo "<tr><td>${p}</td><td class='ver-post'>New (Opened)</td></tr>"; done)
$(echo "$PORTS_CLOSED" | grep "[0-9]" | while read p; do echo "<tr><td>${p}</td><td class='ver-pre'>Closed</td></tr>"; done)
        </table>
PORTEOF
else
echo "        <div class=\"no-change\">✔ &nbsp; No port changes detected</div>"
fi)
      </div>
    </div>

    <!-- Firewall -->
    <div class="dsection" id="diff-firewall">
      <div class="dsection-header" onclick="tog(this)">
        <div class="dtitle-row">
          <div class="dicon $([ -n "$FIREWALL_DIFF" ] && echo changed || echo same)">🛡</div>
          <div><div class="dtitle">Firewall Rules</div><div class="dsubtitle">firewalld / iptables / ufw</div></div>
        </div>
        <div style="display:flex;align-items:center;gap:10px">
          <span class="dstatus-pill $([ -n "$FIREWALL_DIFF" ] && echo pill-changed || echo pill-same)">$([ -n "$FIREWALL_DIFF" ] && echo "CHANGED" || echo "NO CHANGE")</span>
          <span class="dtoggle">▼</span>
        </div>
      </div>
      <div class="dsection-body">
$([ -n "$FIREWALL_DIFF" ] && echo "        <div class=\"diff-block\">$(build_diff_block "${PRE_DIR}/08_firewall.txt" "${POST_DIR}/08_firewall.txt")</div>" || echo "        <div class=\"no-change\">✔ &nbsp; Firewall rules unchanged</div>")
      </div>
    </div>

    <!-- SELinux -->
    <div class="dsection" id="diff-selinux">
      <div class="dsection-header" onclick="tog(this)">
        <div class="dtitle-row">
          <div class="dicon $([ "$SEL_PRE" != "$SEL_POST" ] && echo critical || echo same)">🔒</div>
          <div><div class="dtitle">SELinux / AppArmor</div><div class="dsubtitle">${SEL_PRE:-N/A} → ${SEL_POST:-N/A}</div></div>
        </div>
        <div style="display:flex;align-items:center;gap:10px">
          <span class="dstatus-pill $([ "$SEL_PRE" != "$SEL_POST" ] && echo pill-critical || echo pill-same)">$([ "$SEL_PRE" != "$SEL_POST" ] && echo "CRITICAL" || echo "NO CHANGE")</span>
          <span class="dtoggle">▼</span>
        </div>
      </div>
      <div class="dsection-body">
$(if [ "$SEL_PRE" != "$SEL_POST" ]; then
echo "        <div class=\"diff-block\">$(build_diff_block "${PRE_DIR}/11_selinux_apparmor.txt" "${POST_DIR}/11_selinux_apparmor.txt")</div>"
else
echo "        <div class=\"no-change\">✔ &nbsp; SELinux/AppArmor status unchanged — ${SEL_POST:-N/A}</div>"
fi)
      </div>
    </div>

    <!-- Users -->
    <div class="dsection" id="diff-users">
      <div class="dsection-header" onclick="tog(this)">
        <div class="dtitle-row">
          <div class="dicon $([ -n "$USERS_NEW" ] && echo critical || echo same)">👤</div>
          <div><div class="dtitle">User Accounts</div><div class="dsubtitle">New: ${USERS_NEW:-none} &nbsp;|&nbsp; Removed: ${USERS_REM:-none}</div></div>
        </div>
        <div style="display:flex;align-items:center;gap:10px">
          <span class="dstatus-pill $([ -n "$USERS_NEW" ] && echo pill-critical || [ -n "$USERS_REM" ] && echo pill-removed || echo pill-same)">$([ -n "$USERS_NEW" ] && echo "CRITICAL" || [ -n "$USERS_REM" ] && echo "CHANGED" || echo "NO CHANGE")</span>
          <span class="dtoggle">▼</span>
        </div>
      </div>
      <div class="dsection-body">
$(if [ -n "$USERS_NEW" ] || [ -n "$USERS_REM" ]; then
echo "        <div class=\"diff-block\">$(build_diff_block "${PRE_DIR}/13_users.txt" "${POST_DIR}/13_users.txt")</div>"
else
echo "        <div class=\"no-change\">✔ &nbsp; No user account changes</div>"
fi)
      </div>
    </div>

    <!-- /etc Files -->
    <div class="dsection" id="diff-etc">
      <div class="dsection-header" onclick="tog(this)">
        <div class="dtitle-row">
          <div class="dicon $([ "${ETC_MOD_COUNT:-0}" -gt 0 ] && echo critical || echo same)">🔐</div>
          <div><div class="dtitle">/etc Configuration Files</div><div class="dsubtitle">${ETC_MOD_COUNT:-0} modified · ${ETC_NEW_COUNT:-0} new · ${ETC_REM_COUNT:-0} removed</div></div>
        </div>
        <div style="display:flex;align-items:center;gap:10px">
          <span class="dstatus-pill $([ "${ETC_MOD_COUNT:-0}" -gt 0 ] && echo pill-critical || [ "${ETC_NEW_COUNT:-0}" -gt 0 ] && echo pill-changed || echo pill-same)">$([ "${ETC_MOD_COUNT:-0}" -gt 0 ] && echo "CHANGED" || echo "NO CHANGE")</span>
          <span class="dtoggle open">▼</span>
        </div>
      </div>
      <div class="dsection-body open">
$(if [ "${ETC_MOD_COUNT:-0}" -gt 0 ] || [ "${ETC_NEW_COUNT:-0}" -gt 0 ] || [ "${ETC_REM_COUNT:-0}" -gt 0 ]; then
cat << ETCEOF
        <table class="diff-table" style="margin-bottom:12px">
          <tr><th colspan="1">Modified /etc Files (checksum changed)</th></tr>
          $(build_etc_rows "$ETC_MODIFIED" "ver-pre")
        </table>
        <table class="diff-table" style="margin-bottom:12px">
          <tr><th colspan="1">New /etc Files</th></tr>
          $(build_etc_rows "$ETC_NEW" "ver-post")
        </table>
        <table class="diff-table">
          <tr><th colspan="1">Removed /etc Files</th></tr>
          $(build_etc_rows "$ETC_REMOVED" "ver-pre")
        </table>
ETCEOF
else
echo "        <div class=\"no-change\">✔ &nbsp; No /etc file checksum changes detected</div>"
fi)
      </div>
    </div>

    <!-- Cron -->
    <div class="dsection" id="diff-cron">
      <div class="dsection-header" onclick="tog(this)">
        <div class="dtitle-row">
          <div class="dicon $([ -n "$CRON_DIFF" ] && echo changed || echo same)">🕐</div>
          <div><div class="dtitle">Cron Jobs & Timers</div><div class="dsubtitle">crontab, cron.d, systemd timers</div></div>
        </div>
        <div style="display:flex;align-items:center;gap:10px">
          <span class="dstatus-pill $([ -n "$CRON_DIFF" ] && echo pill-changed || echo pill-same)">$([ -n "$CRON_DIFF" ] && echo "CHANGED" || echo "NO CHANGE")</span>
          <span class="dtoggle">▼</span>
        </div>
      </div>
      <div class="dsection-body">
$([ -n "$CRON_DIFF" ] && echo "        <div class=\"diff-block\">$(build_diff_block "${PRE_DIR}/12_cron.txt" "${POST_DIR}/12_cron.txt")</div>" || echo "        <div class=\"no-change\">✔ &nbsp; No cron job changes</div>")
      </div>
    </div>

    <!-- Reboots -->
    <div class="dsection" id="diff-reboots">
      <div class="dsection-header" onclick="tog(this)">
        <div class="dtitle-row">
          <div class="dicon $([ "${REBOOT_COUNT_POST:-0}" -gt "${REBOOT_COUNT_PRE:-0}" ] && echo new || echo same)">🔄</div>
          <div><div class="dtitle">Reboot History</div><div class="dsubtitle">Pre: ${REBOOT_COUNT_PRE:-0} boots &nbsp;→&nbsp; Post: ${REBOOT_COUNT_POST:-0} boots</div></div>
        </div>
        <div style="display:flex;align-items:center;gap:10px">
          <span class="dstatus-pill $([ "${REBOOT_COUNT_POST:-0}" -gt "${REBOOT_COUNT_PRE:-0}" ] && echo pill-new || echo pill-same)">$([ "${REBOOT_COUNT_POST:-0}" -gt "${REBOOT_COUNT_PRE:-0}" ] && echo "REBOOTED" || echo "NO REBOOT")</span>
          <span class="dtoggle">▼</span>
        </div>
      </div>
      <div class="dsection-body">
        <div class="diff-block">$(build_diff_block "${PRE_DIR}/17_reboot_history.txt" "${POST_DIR}/17_reboot_history.txt")</div>
      </div>
    </div>

  </div><!-- end .content -->
</div><!-- end .main -->

<div class="footer">
  <span>Patch Diff Report &nbsp;·&nbsp; $(hostname -f) &nbsp;·&nbsp; Generated $(date '+%Y-%m-%d %H:%M:%S')</span>
  <span>Pre: $(basename $PRE_DIR) &nbsp;→&nbsp; Post: $(basename $POST_DIR)</span>
</div>

<script>
function tog(h){const b=h.nextElementSibling,t=h.querySelector('.dtoggle');b.classList.toggle('open');t.classList.toggle('open');}
function sa(el){document.querySelectorAll('.nav-item').forEach(i=>i.classList.remove('active'));el.classList.add('active');}
document.querySelectorAll('.nav-item[href^="#"]').forEach(a=>{a.addEventListener('click',function(e){e.preventDefault();const t=document.querySelector(this.getAttribute('href'));if(t){t.scrollIntoView({behavior:'smooth',block:'start'});const b=t.querySelector('.dsection-body'),tg=t.querySelector('.dtoggle');if(b&&!b.classList.contains('open')){b.classList.add('open');tg&&tg.classList.add('open');}}});});
</script>
</body></html>
HTMLEOF
}

# =============================================================================
#  MAIN
# =============================================================================
main() {
    print_banner

    print_section "System Checks"
    diff_kernel
    diff_os
    diff_disk
    diff_reboots

    print_section "Software & Services"
    diff_packages
    diff_services

    print_section "Network & Ports"
    diff_network
    diff_ports
    diff_firewall

    print_section "Security & Compliance"
    diff_selinux
    diff_users
    diff_etc
    diff_cron

    echo ""
    echo -e "  ${BOLD}${CYAN}▶  Generating HTML Diff Report...${RESET}"
    echo -e "  ${DIM}  ──────────────────────────────────────────${RESET}"
    generate_html
    echo -e "  ${GREEN}[✔]${RESET} ${WHITE}HTML Diff Report Generated${RESET}"

    local END_TIME=$(date +%s)
    local DURATION=$((END_TIME - START_TIME))

    echo ""
    echo -e "  ${DIM}──────────────────────────────────────────────────────────────────${RESET}"
    echo ""
    echo -e "  ${BOLD}${GREEN}✔  DIFF REPORT COMPLETE${RESET}"
    echo ""
    echo -e "  ${WHITE}HTML Report   :${RESET} ${CYAN}${HTML_REPORT}${RESET}"
    echo -e "  ${WHITE}Duration      :${RESET} ${CYAN}${DURATION} seconds${RESET}"
    echo ""
    echo -e "  ${BOLD}Summary:${RESET}"
    echo -e "  ${YELLOW}  Kernel    :${RESET} $([ "$KERNEL_CHANGED" -eq 1 ] && echo "${RED}CHANGED${RESET} (${KERNEL_PRE} → ${KERNEL_POST})" || echo "${GREEN}Unchanged${RESET}")"
    echo -e "  ${YELLOW}  Upgraded  :${RESET} ${PKG_UPDATED_COUNT:-0} packages"
    echo -e "  ${YELLOW}  New Pkgs  :${RESET} ${PKG_NEW_COUNT:-0} packages"
    echo -e "  ${YELLOW}  Removed   :${RESET} ${PKG_REMOVED_COUNT:-0} packages"
    echo -e "  ${YELLOW}  /etc Files:${RESET} ${ETC_MOD_COUNT:-0} changed"
    echo -e "  ${YELLOW}  Svc Failed:${RESET} $([ "${SERVICES_FAILED_POST:-0}" -gt 0 ] && echo "${RED}${SERVICES_FAILED_POST} FAILED${RESET}" || echo "${GREEN}None${RESET}")"
    echo ""
}

main "$@"
