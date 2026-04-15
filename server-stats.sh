#!/bin/bash
# server-stats.sh (con integración SECCION9 Panel)
# Portable: Ubuntu, Debian, CentOS, RHEL, Alpine, Arch, and others

# ─── Colors ───────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

# ─── OS Detection ─────────────────────────────────────────────────────────────
if [ -f /etc/os-release ]; then
    . /etc/os-release
    os_name="${NAME:-Unknown}"
    os_version="${VERSION:-${VERSION_ID:-}}"
elif command -v lsb_release >/dev/null 2>&1; then
    os_name=$(lsb_release -si)
    os_version=$(lsb_release -sr)
elif [ -f /etc/redhat-release ]; then
    os_name=$(cat /etc/redhat-release)
    os_version=""
else
    os_name="Unknown"
    os_version=""
fi

# ─── CPU Usage ────────────────────────────────────────────────────────────────
get_cpu_usage() {
    local cpu1 cpu2
    read -r _ user1 nice1 system1 idle1 iowait1 irq1 softirq1 rest1 < /proc/stat
    sleep 1
    read -r _ user2 nice2 system2 idle2 iowait2 irq2 softirq2 rest2 < /proc/stat

    local idle_delta=$(( (idle2 + iowait2) - (idle1 + iowait1) ))
    local total_delta=$(( (user2 + nice2 + system2 + idle2 + iowait2 + irq2 + softirq2) \
                        - (user1 + nice1 + system1 + idle1 + iowait1 + irq1 + softirq1) ))

    if [ "$total_delta" -eq 0 ]; then
        echo "0.00"
    else
        awk "BEGIN { printf \"%.2f\", (1 - $idle_delta/$total_delta) * 100 }"
    fi
}

total_cpu=$(get_cpu_usage)

# ─── Memory ───────────────────────────────────────────────────────────────────
mem_total_kb=$(awk '/^MemTotal:/ { print $2 }' /proc/meminfo)
mem_available_kb=$(awk '/^MemAvailable:/ { print $2 }' /proc/meminfo)
mem_used_kb=$(( mem_total_kb - mem_available_kb ))

total_mem=$(( mem_total_kb / 1024 ))
used_mem=$(( mem_used_kb / 1024 ))
free_mem_mb=$(( mem_available_kb / 1024 ))
memory_usage=$(awk "BEGIN { printf \"%.2f\", $mem_used_kb / $mem_total_kb * 100 }")

# ─── Disk Usage ───────────────────────────────────────────────────────────────
disk_line=$(LC_ALL=C df -k / | awk 'NR==2')
disk_total_kb=$(echo "$disk_line" | awk '{ print $2 }')
disk_used_kb=$(echo  "$disk_line" | awk '{ print $3 }')
disk_free_kb=$(echo  "$disk_line" | awk '{ print $4 }')
disk_pct=$(echo     "$disk_line" | awk '{ print $5 }')

total_disk=$(awk "BEGIN { printf \"%.2f\", $disk_total_kb / 1024 / 1024 }")
used_disk=$(awk  "BEGIN { printf \"%.2f\", $disk_used_kb  / 1024 / 1024 }")
free_disk=$(awk  "BEGIN { printf \"%.2f\", $disk_free_kb  / 1024 / 1024 }")

# ─── Top 5 Processes ──────────────────────────────────────────────────────────
top_5_cpu=$(ps aux --sort=-%cpu 2>/dev/null | awk 'NR>1 && NR<=6 { printf "  PID %-7s CPU %-6s %s\n", $2, $3"%", $11 }')
top_5_mem=$(ps aux --sort=-%mem 2>/dev/null | awk 'NR>1 && NR<=6 { printf "  PID %-7s MEM %-6s %s\n", $2, $4"%", $11 }')

# ─── System Info ──────────────────────────────────────────────────────────────
uptime_str=$(uptime -p 2>/dev/null || uptime | sed 's/.*up /up /' | cut -d',' -f1-2)
load_avg=$(uptime | awk -F'load average[s]*:' '{ print $2 }' | sed 's/^ *//')
logged_users=$(who 2>/dev/null | awk '{ print $1 }' | sort -u | tr '\n' ' ')
[ -z "$logged_users" ] && logged_users="(none)"

# ─── Failed Login Attempts ────────────────────────────────────────────────────
failed_logins=""
for logfile in /var/log/auth.log /var/log/secure /var/log/messages /var/log/syslog; do
    if [ -r "$logfile" ]; then
        result=$(grep -i "pam_unix.*fail\|Failed password" "$logfile" 2>/dev/null | tail -5)
        [ -n "$result" ] && { failed_logins="$result"; break; }
    fi
done
if [ -z "$failed_logins" ] && command -v journalctl >/dev/null 2>&1; then
    failed_logins=$(journalctl _SYSTEMD_UNIT=sshd.service + SYSLOG_IDENTIFIER=sshd 2>/dev/null \
        | grep -i "pam_unix.*fail\|Failed password" | tail -5)
fi
[ -z "$failed_logins" ] && failed_logins="  (no failed login data available)"

# ──────────────────────────────────────────────────────────────────────────────
# SECCION9 PANEL INTEGRATION
# ──────────────────────────────────────────────────────────────────────────────
panel_api_mem="N/A"
panel_nginx_mem="N/A"
panel_wg_status="inactive"
panel_wg_peers=0

# API memory (systemd)
if systemctl is-active --quiet seccion9-api 2>/dev/null; then
    mem_bytes=$(systemctl show -p MemoryCurrent seccion9-api 2>/dev/null | cut -d= -f2)
    if [ -n "$mem_bytes" ] && [ "$mem_bytes" -gt 0 ]; then
        panel_api_mem="$(( mem_bytes / 1024 / 1024 )) MB"
    else
        # fallback to ps
        api_pid=$(pgrep -f "python.*main.py" | head -1)
        if [ -n "$api_pid" ]; then
            rss_kb=$(ps -o rss= -p "$api_pid" 2>/dev/null)
            panel_api_mem="$(( rss_kb / 1024 )) MB"
        fi
    fi
else
    panel_api_mem="not running"
fi

# Nginx memory
nginx_pid=$(pgrep -f "nginx: master" | head -1)
if [ -n "$nginx_pid" ]; then
    rss_kb=$(ps -o rss= -p "$nginx_pid" 2>/dev/null)
    panel_nginx_mem="$(( rss_kb / 1024 )) MB"
else
    panel_nginx_mem="not running"
fi

# WireGuard status (interface wg0 by default, fallback to any)
if command -v wg >/dev/null 2>&1; then
    wg_iface=$(wg show interfaces 2>/dev/null | awk '{print $1}')
    if [ -n "$wg_iface" ]; then
        panel_wg_status="active ($wg_iface)"
        panel_wg_peers=$(wg show "$wg_iface" peers 2>/dev/null | wc -l)
    fi
fi

# ─── Output ───────────────────────────────────────────────────────────────────
printf "${CYAN}=== Server Performance Stats ===${NC}\n"
printf "${BLUE}Last update: %s${NC}\n\n" "$(date)"

printf "${YELLOW}=== CPU Usage ===${NC}\n"
printf "  Total CPU Usage : %s %%\n\n" "$total_cpu"

printf "${YELLOW}=== Memory Usage ===${NC}\n"
printf "  Total Memory    : %s MB\n" "$total_mem"
printf "  Used Memory     : %s MB\n" "$used_mem"
printf "  Available Memory: %s MB\n" "$free_mem_mb"
printf "  Memory Usage    : %s %%\n\n" "$memory_usage"

printf "${YELLOW}=== Disk Usage (/) ===${NC}\n"
printf "  Total Disk      : %s GB\n" "$total_disk"
printf "  Used Disk       : %s GB\n" "$used_disk"
printf "  Free Disk       : %s GB\n" "$free_disk"
printf "  Disk Usage      : %s\n\n" "$disk_pct"

printf "${YELLOW}=== Top 5 Processes by CPU ===${NC}\n"
printf "%s\n\n" "$top_5_cpu"

printf "${YELLOW}=== Top 5 Processes by Memory ===${NC}\n"
printf "%s\n\n" "$top_5_mem"

printf "${GREEN}=== SECCION9 Panel Status ===${NC}\n"
printf "  API (seccion9)   : %s\n" "$panel_api_mem"
printf "  Nginx            : %s\n" "$panel_nginx_mem"
printf "  WireGuard        : %s (%d peers)\n\n" "$panel_wg_status" "$panel_wg_peers"

printf "${YELLOW}=== System Information ===${NC}\n"
printf "  OS              : %s %s\n" "$os_name" "$os_version"
printf "  Uptime          : %s\n" "$uptime_str"
printf "  Load Average    : %s\n" "$load_avg"
printf "  Logged-in Users : %s\n\n" "$logged_users"

printf "${RED}=== Recent Failed Login Attempts ===${NC}\n"
printf "%s\n\n" "$failed_logins"

printf "${PURPLE}=== End of Report ===${NC}\n"
