#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

SCRIPT_NAME="dmitbox.sh"
SCRIPT_VERSION="2026.08.14"
AD_TEXT="DMIT 交流群  https://t.me/DmitChat"

# managed files
TUNE_SYSCTL_FILE="/etc/sysctl.d/99-dmit-tcp-tune.conf"
DMIT_TCP_DEFAULT_FILE="/etc/sysctl.d/99-dmit-tcp-dmitdefault.conf"
IPV6_SYSCTL_FILE="/etc/sysctl.d/99-dmit-ipv6.conf"
IPV6_FIX_SYSCTL_FILE="/etc/sysctl.d/99-dmit-ipv6-fix.conf"
GAI_CONF="/etc/gai.conf"
BACKUP_BASE="/root/dmit-backup"
TCP_SYSCTL_BACKUP="${BACKUP_BASE}/tcp-sysctl.orig"
IPV6_SYSCTL_BACKUP="${BACKUP_BASE}/ipv6-sysctl.orig"

# Dynamic TCP fitting (reviewed tcpfit release; never execute mutable main directly)
TCPFIT_REVIEWED_VERSION="0.5.4"
TCPFIT_REVIEWED_SHA256="e89f21326552358f524869c8884e0d4f515137b313c0b5e81f7133381300d55f"
TCPFIT_RELEASE_URL="https://github.com/Kylin010/tcpfit/releases/download/v${TCPFIT_REVIEWED_VERSION}/tcpfit.sh"
TCPFIT_INSTALL_PATH="/usr/local/bin/tcpfit"
TCPFIT_SYSCTL_FILE="/etc/sysctl.d/99-tcpfit.conf"
TCPFIT_STATE_DIR="/var/lib/tcpfit"
TCPFIT_QDISC_SERVICE="/etc/systemd/system/tcpfit-qdisc.service"
TCPFIT_BACKUP_DIR="${BACKUP_BASE}/tcpfit"

# MTU persistent via systemd
MTU_SERVICE="/etc/systemd/system/dmit-mtu.service"
MTU_VALUE_FILE="/etc/dmit-mtu.conf"
MTU_ORIG_FILE="${BACKUP_BASE}/mtu.orig"

# DNS backup
RESOLV_BACKUP="${BACKUP_BASE}/resolv.conf.orig"

# SSH backup & drop-in
SSH_ORIG_TGZ="${BACKUP_BASE}/ssh-orig.tgz"
SSH_DROPIN_ORIG_MARKER="${BACKUP_BASE}/ssh-dropin-existed.orig"
SSH_DROPIN_DIR="/etc/ssh/sshd_config.d"
SSH_DROPIN_FILE="${SSH_DROPIN_DIR}/00-dmitbox.conf"
SSH_LEGACY_DROPIN_FILE="${SSH_DROPIN_DIR}/99-dmitbox.conf"
SSH_KEYS_BACKUP_DIR="${BACKUP_BASE}/ssh-keys"
SSH_EPHEMERAL_KEY_BASE="/tmp"

# cloud-init safety (avoid losing SSH after enabling cloud-init on non-cloud images)
CLOUDINIT_DISABLE_NET_FILE="/etc/cloud/cloud.cfg.d/99-dmitbox-disable-network-config.cfg"
CLOUDINIT_DISABLE_PKG_FILE="/etc/cloud/cloud.cfg.d/99-dmitbox-disable-apt.cfg"

# cloud-init / ip-change (DMIT default-like)
DMITBOX_PVE_CFG="/etc/cloud/cloud.cfg.d/99_dmitbox_pve.cfg"
DMITBOX_SEED_SCRIPT="/usr/local/sbin/dmitbox-cloud-seed.sh"
DMITBOX_SEED_SERVICE="/etc/systemd/system/dmitbox-cloud-seed.service"
DMITBOX_NET_ROLLBACK_SCRIPT="/usr/local/sbin/dmitbox-net-rollback.sh"
DMITBOX_NET_ROLLBACK_SERVICE="/etc/systemd/system/dmitbox-net-rollback.service"
DMITBOX_IPCHANGE_BACKUP_POINTER="/etc/dmitbox-ipchange-backup.path"
DMITBOX_IPCHANGE_BACKUP_MARKER="${DMITBOX_IPCHANGE_BACKUP_MARKER:-$DMITBOX_IPCHANGE_BACKUP_POINTER}"

# IPv6 pool + persist
IPV6_POOL_CONF="/etc/dmit-ipv6-pool.conf"
IPV6_POOL_SERVICE="/etc/systemd/system/dmit-ipv6-pool.service"

# IPv6 random outbound (nftables NAT66)
IPV6_RAND_CONF="/etc/dmit-ipv6-rand.conf"
IPV6_RAND_NFT="/etc/nftables.d/dmitbox-ipv6-rand.nft"
IPV6_RAND_SERVICE="/etc/systemd/system/dmit-ipv6-rand.service"

# system maintenance
SWAP_FILE="/swapfile"
SWAP_CONF="/etc/dmitbox-swap.conf"
SWAPPINESS_FILE="/etc/sysctl.d/99-dmitbox-swappiness.conf"
FSTAB_SWAP_BACKUP="${BACKUP_BASE}/fstab.before-dmitbox-swap"
FAIL2BAN_JAIL_FILE="/etc/fail2ban/jail.d/99-dmitbox-sshd.local"
FAIL2BAN_BACKUP="${BACKUP_BASE}/fail2ban-sshd.orig"
FAIL2BAN_ORIG_MARKER="${BACKUP_BASE}/fail2ban-sshd-existed.orig"

# secure static website
SECURE_SITE_CONF="/etc/dmitbox-secure-site.conf"
SECURE_SITE_ROOT="/var/www/dmitbox-secure-site"
SECURE_SITE_NGINX_CONF="/etc/nginx/conf.d/dmitbox-secure-site.conf"
SECURE_SITE_NGINX_LIMIT_CONF="/etc/nginx/conf.d/00-dmitbox-secure-site-zones.conf"
SECURE_SITE_NGINX_ACTIVE_CONF="/etc/nginx/conf.d/dmitbox-secure-site-domain.conf"
# Kept outside every Nginx include directory so even broad `include *` rules cannot load it.
SECURE_SITE_NGINX_PAUSED_CONF="/etc/dmitbox-secure-site-domain.paused.conf"
SECURE_SITE_HTTPS_PORT="443"
SECURE_SITE_CERT_HOOK="/etc/letsencrypt/renewal-hooks/deploy/dmitbox-secure-site-nginx.sh"
SECURE_SITE_CERT_CRON="/etc/cron.d/dmitbox-certbot-renew"
SECURE_SITE_CERT_PERIODIC="/etc/periodic/daily/dmitbox-certbot-renew"
SECURE_SITE_DNS_WATCH="/usr/local/sbin/dmitbox-site-dns-watch"
SECURE_SITE_DNS_WATCH_CRON="/etc/cron.d/dmitbox-site-dns-watch"
SECURE_SITE_DNS_WATCH_PERIODIC="/etc/periodic/hourly/dmitbox-site-dns-watch"
SECURE_SITE_DNS_WATCH_SERVICE="/etc/systemd/system/dmitbox-site-dns-watch.service"
SECURE_SITE_DNS_WATCH_TIMER="/etc/systemd/system/dmitbox-site-dns-watch.timer"
SECURE_SITE_DNS_WATCH_ALPINE_CRONTAB="/etc/crontabs/root"
SECURE_SITE_DNS_STATUS="/var/lib/dmitbox/secure-site-dns.status"
SECURE_SITE_BACKUP_DIR="${BACKUP_BASE}/secure-site"
SECURE_SITE_INIT_DIR="/etc/init.d"
SECURE_SITE_SYSTEMD_RUNTIME_DIR="/run/systemd/system"
SECURE_SITE_HOSTS_FILE="/etc/hosts"
SECURE_SITE_HOSTS_BACKUP="/etc/dmitbox-secure-site-hosts.backup.json"
SECURE_SITE_HOSTS_TAG="dmitbox-secure-site-local-origin"

# HTTPS reverse proxy
REVERSE_PROXY_CONF_DIR="/etc/dmitbox-reverse-proxy.d"
REVERSE_PROXY_NGINX_DIR="/etc/nginx/conf.d"
REVERSE_PROXY_MAP_CONF="/etc/nginx/conf.d/00-dmitbox-reverse-proxy-map.conf"
REVERSE_PROXY_ACME_ROOT="/var/www/dmitbox-reverse-proxy-acme"
REVERSE_PROXY_BACKUP_DIR="${BACKUP_BASE}/reverse-proxy"

# common firewall management (only records rules created by this script)
COMMON_FIREWALL_REGISTRY="/etc/dmitbox-firewall.rules"
COMMON_FIREWALL_MARKER="# managed by dmitbox.sh - common firewall rules"
COMMON_FIREWALL_CREATED=0
COMMON_FIREWALL_BACKEND=""
COMMON_FIREWALL_BACKUP_DIR="${BACKUP_BASE}/firewall"
COMMON_FIREWALL_LAST_BACKUP=""

# Runtime detection (having systemctl installed does not mean systemd is PID 1)
SYSTEMD_RUNTIME_DIR="/run/systemd/system"

RUN_MODE="${RUN_MODE:-menu}" # menu | cli

# colors (no red)
c_reset="\033[0m"
c_dim="\033[2m"
c_bold="\033[1m"
c_green="\033[32m"
c_yellow="\033[33m"
c_cyan="\033[36m"
c_white="\033[37m"
MENU_AFTER_HEADER=0

if [[ -n "${NO_COLOR:-}" || "${TERM:-}" == "dumb" ]]; then
  c_reset=""
  c_dim=""
  c_bold=""
  c_green=""
  c_yellow=""
  c_cyan=""
  c_white=""
fi

ok()   { echo -e "${c_green}✔${c_reset} $*"; }
info() { echo -e "${c_cyan}➜${c_reset} $*"; }
warn() { echo -e "${c_yellow}⚠${c_reset} $*"; }

need_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    warn "请用 root 运行：sudo bash ${SCRIPT_NAME}"
    exit 1
  fi
}

have_cmd() { command -v "$1" >/dev/null 2>&1; }
ts_now() { date +"%Y%m%d-%H%M%S"; }
ensure_dir() { mkdir -p "$1"; }

command_with_timeout() {
  local seconds="${1:-8}"
  shift || return 1
  is_uint_in_range "$seconds" 1 3600 || seconds=8
  if have_cmd timeout; then
    timeout "$seconds" "$@"
  else
    "$@"
  fi
}

has_tty() {
  [[ -r /dev/tty ]] && ( : </dev/tty ) 2>/dev/null
}

is_uint_in_range() {
  local value="${1:-}" min="${2:-0}" max="${3:-2147483647}"
  [[ "$value" =~ ^[0-9]{1,10}$ ]] || return 1
  value=$((10#$value))
  (( value >= min && value <= max ))
}

valid_username() {
  local user="${1:-}"
  [[ "$user" =~ ^[a-z_][a-z0-9_-]{0,31}$ ]]
}

read_tty() {
  local __var="$1" __prompt="$2" __default="${3:-}"
  local __val=""
  if [[ "$__prompt" == "请输入编号 > " ]]; then
    printf -v __prompt '%b' "  ${c_bold}${c_white}请选择${c_reset} ${c_cyan}›${c_reset} "
  fi
  if has_tty; then
    read -r -p "$__prompt" __val </dev/tty || true
  else
    read -r -p "$__prompt" __val || true
  fi
  __val="${__val:-$__default}"
  printf -v "$__var" "%s" "$__val"
}

read_tty_secret() {
  local __var="$1" __prompt="$2"
  local __val=""
  if has_tty; then
    read -r -s -p "$__prompt" __val </dev/tty || true
    echo >&2 || true
  else
    read -r -s -p "$__prompt" __val || true
    echo >&2 || true
  fi
  printf -v "$__var" "%s" "$__val"
}

soft_clear() {
  printf "\033[2J\033[H" 2>/dev/null || true
  printf "\033[3J" 2>/dev/null || true
  if have_cmd clear; then clear >/dev/null 2>&1 || true; fi
}

pause_for_return() {
  local msg="${1:-↩ 按回车返回...}" answer=""
  [[ "$RUN_MODE" == "menu" ]] || return 0
  echo
  printf "%s" "$msg"
  # read_tty() always prefers /dev/tty.  Keep pause prompts on the same input
  # source so pipe/process-substitution launch methods cannot consume Enter
  # from a different stdin stream.
  if has_tty; then
    IFS= read -r answer </dev/tty || true
  elif [[ -t 0 ]]; then
    IFS= read -r answer || true
  else
    sleep 2
  fi
  echo
}

pause_up() {
  pause_for_return "↩ 按回车返回..."
}

pause_main() {
  pause_for_return "↩ 按回车继续..."
}





write_file() {
  local path="$1"
  local content="$2"
  umask 022
  mkdir -p "$(dirname "$path")"
  printf "%s\n" "$content" > "$path"
}

sysctl_apply_all() { sysctl --system >/dev/null 2>&1 || true; }

# ---------------- pkg helper ----------------
run_with_spinner() {
  # usage: run_with_spinner "title" cmd...
  local title="$1"; shift
  local log=""
  log="/tmp/dmitbox-$(ts_now).log"

  info "$title"
  echo -e "${c_dim}  处理中，请稍候；需要时可按 Ctrl+C 中断。详细日志：${log}${c_reset}"

  ("$@") >"$log" 2>&1 &
  local pid=$!
  local spin="|/-\\"
  local i=0
  while kill -0 "$pid" >/dev/null 2>&1; do
    local j=$(( i % 4 ))
    # shellcheck disable=SC2059
    printf "\r${c_dim}…安装/配置进行中 %c  (log: %s)${c_reset}" "${spin:j:1}" "$log"
    sleep 0.2
    i=$((i+1))
  done
  local rc=0
  wait "$pid" || rc=$?
  printf "\r\033[K" || true
  if [[ $rc -ne 0 ]]; then
    warn "命令返回非 0（rc=$rc）。最近日志如下："
    tail -n 40 "$log" 2>/dev/null || true
  else
    ok "完成"
  fi
  return $rc
}

pkg_install() {
  local pkgs=("$@")
  [[ "${#pkgs[@]}" -eq 0 ]] && return 0

  # In menu mode, keep user informed (otherwise apt/dnf may look "stuck").
  local quiet="1"
  [[ "${RUN_MODE:-menu}" == "menu" ]] && quiet="0"

  # Avoid interactive prompts (needrestart/dpkg conffile prompts)
  export DEBIAN_FRONTEND=noninteractive
  export NEEDRESTART_MODE=a

  if have_cmd apt-get; then
    if [[ "$quiet" == "0" ]]; then
      info "正在安装：${pkgs[*]}"
      run_with_spinner "apt-get update" apt-get -o DPkg::Lock::Timeout=30 -y update || true
      run_with_spinner "apt-get install ${pkgs[*]}" \
        apt-get -o DPkg::Lock::Timeout=30 -y \
        -o Dpkg::Options::=--force-confdef \
        -o Dpkg::Options::=--force-confold \
        install "${pkgs[@]}" || true
    else
      apt-get -o DPkg::Lock::Timeout=30 -qq update >/dev/null 2>&1 || true
      apt-get -o DPkg::Lock::Timeout=30 -y install "${pkgs[@]}" >/dev/null 2>&1 || true
    fi
    return 0
  fi

  if have_cmd dnf; then
    [[ "$quiet" == "0" ]] && info "正在安装：${pkgs[*]}（可能需要一点时间）"
    if [[ "$quiet" == "0" ]]; then dnf -y install "${pkgs[@]}" || true; else dnf -y install "${pkgs[@]}" >/dev/null 2>&1 || true; fi
    return 0
  fi

  if have_cmd yum; then
    [[ "$quiet" == "0" ]] && info "正在安装：${pkgs[*]}（可能需要一点时间）"
    if [[ "$quiet" == "0" ]]; then yum -y install "${pkgs[@]}" || true; else yum -y install "${pkgs[@]}" >/dev/null 2>&1 || true; fi
    return 0
  fi

  if have_cmd apk; then
    [[ "$quiet" == "0" ]] && info "正在安装：${pkgs[*]}（可能需要一点时间）"
    if [[ "$quiet" == "0" ]]; then apk add --no-cache "${pkgs[@]}" || true; else apk add --no-cache "${pkgs[@]}" >/dev/null 2>&1 || true; fi
    return 0
  fi

  warn "未识别包管理器：请手动安装 ${pkgs[*]}"
}

# ---------------- helpers ----------------
default_iface() {
  local ifc=""
  ifc="$(ip -4 route 2>/dev/null | awk '/^default/{print $5; exit}' || true)"
  [[ -n "$ifc" ]] && { echo "$ifc"; return 0; }
  ifc="$(ip -6 route 2>/dev/null | awk '/^default/{print $5; exit}' || true)"
  [[ -n "$ifc" ]] && { echo "$ifc"; return 0; }
  echo "eth0"
}

ipv6_status() {
  local a d
  a="$(sysctl -n net.ipv6.conf.all.disable_ipv6 2>/dev/null || echo "N/A")"
  d="$(sysctl -n net.ipv6.conf.default.disable_ipv6 2>/dev/null || echo "N/A")"
  echo "all=$a default=$d"
}

has_ipv6_global_addr() { ip -6 addr show scope global 2>/dev/null | grep -q "inet6 "; }
has_ipv6_default_route() { ip -6 route show default 2>/dev/null | grep -q "^default "; }

libc_kind() {
  if have_cmd getconf && getconf GNU_LIBC_VERSION >/dev/null 2>&1; then echo "glibc"; return 0; fi
  if have_cmd ldd && ldd --version 2>&1 | head -n 1 | grep -qi musl; then echo "musl"; return 0; fi
  if have_cmd ldd && ldd --version 2>&1 | grep -qi "glibc"; then echo "glibc"; return 0; fi
  echo "unknown"
}

is_systemd() { have_cmd systemctl && [[ -d "$SYSTEMD_RUNTIME_DIR" ]]; }
is_resolved_active() { is_systemd && systemctl is-active --quiet systemd-resolved 2>/dev/null; }

curl4_ok() { have_cmd curl && curl -4 -sS --max-time 5 ip.sb >/dev/null 2>&1; }
curl6_ok() { have_cmd curl && curl -6 -sS --max-time 5 ip.sb >/dev/null 2>&1; }

dns_resolve_ok() {
  if have_cmd getent; then getent hosts ip.sb >/dev/null 2>&1 && return 0; fi
  have_cmd curl && curl -sS --max-time 5 ip.sb >/dev/null 2>&1
}

human_bytes() {
  local bytes="${1:-0}"
  [[ "$bytes" =~ ^[0-9]+$ ]] || bytes="0"
  if have_cmd numfmt; then
    numfmt --to=iec-i --suffix=B "$bytes" 2>/dev/null || echo "${bytes} B"
  else
    awk -v b="$bytes" 'BEGIN {
      split("B KiB MiB GiB TiB", u, " "); i=1;
      while (b >= 1024 && i < 5) { b /= 1024; i++ }
      printf "%.1f %s", b, u[i]
    }'
  fi
}

os_pretty_name() {
  if [[ -r /etc/os-release ]]; then
    (
      # shellcheck disable=SC1091
      . /etc/os-release
      echo "${PRETTY_NAME:-${NAME:-Linux}}"
    )
  else
    echo "Linux"
  fi
}

confirm_word() {
  local expected="$1" prompt="$2" answer=""
  read_tty answer "$prompt" ""
  [[ "$answer" == "$expected" ]]
}

# ---------------- banner ----------------
menu_width() {
  local columns="${DMITBOX_MENU_COLUMNS:-${COLUMNS:-}}" width=0
  if ! is_uint_in_range "$columns" 20 1000; then
    columns="$(tput cols 2>/dev/null || true)"
  fi
  if ! is_uint_in_range "$columns" 20 1000; then
    columns="$(stty size </dev/tty 2>/dev/null | awk '{print $2}' || true)"
  fi
  is_uint_in_range "$columns" 20 1000 || columns=80
  width=$((columns - 4))
  (( width < 56 )) && width=56
  (( width > 92 )) && width=92
  printf '%s\n' "$width"
}

menu_repeat() {
  local character="${1:-─}" count="${2:-0}" output="" i=0
  is_uint_in_range "$count" 0 1000 || count=0
  for ((i=0; i<count; i++)); do output+="$character"; done
  printf '%s' "$output"
}

menu_display_width() {
  local text="${1:-}" clean="" width=""
  clean="$(printf '%b' "$text" | sed -E $'s/\x1B\\[[0-9;]*[[:alpha:]]//g')"
  width="$( (export LC_ALL=C.UTF-8; printf '%s' "$clean" | wc -L) 2>/dev/null || true)"
  if [[ "$width" =~ ^[0-9]+$ ]]; then
    printf '%s\n' "$width"
  else
    printf '%s\n' "${#clean}"
  fi
}

menu_wrap_segments() {
  local text="${1:-}" max_width="${2:-50}" rest="" segment="" line="" candidate=""
  is_uint_in_range "$max_width" 10 1000 || max_width=50
  if (( $(menu_display_width "$text") <= max_width )); then
    printf '%s\n' "$text"
    return 0
  fi
  rest="$text"
  while [[ "$rest" == *" · "* ]]; do
    segment="${rest%% · *}"
    rest="${rest#* · }"
    candidate="$segment"
    [[ -n "$line" ]] && candidate="${line} · ${segment}"
    if [[ -n "$line" ]] && (( $(menu_display_width "$candidate") > max_width )); then
      printf '%s\n' "$line"
      line="$segment"
    else
      line="$candidate"
    fi
  done
  candidate="$rest"
  [[ -n "$line" ]] && candidate="${line} · ${rest}"
  if [[ -n "$line" ]] && (( $(menu_display_width "$candidate") > max_width )); then
    printf '%s\n' "$line"
    printf '%s\n' "$rest"
  else
    printf '%s\n' "$candidate"
  fi
}

menu_rule() {
  local width=""
  width="$(menu_width)"
  printf "  ${c_dim}%s${c_reset}\n" "$(menu_repeat '─' "$width")"
}

menu_box_top() {
  local width="$1" left='╭─ DMIT BOX ' right=" v${SCRIPT_VERSION} ─╮" fill=0
  fill=$((width - $(menu_display_width "$left") - $(menu_display_width "$right")))
  (( fill < 1 )) && fill=1
  printf "  ${c_cyan}${c_bold}╭─ DMIT BOX %s v%s ─╮${c_reset}\n" \
    "$(menu_repeat '─' "$fill")" "$SCRIPT_VERSION"
}

menu_box_rule() {
  local width="$1" left="${2:-├}" right="${3:-┤}"
  printf "  ${c_cyan}%s%s%s${c_reset}\n" "$left" "$(menu_repeat '─' "$((width - 2))")" "$right"
}

menu_box_row() {
  local text="$1" width="$2" text_width=0 padding=0
  text_width="$(menu_display_width "$text")"
  padding=$((width - text_width - 6))
  if (( padding < 0 )); then
    printf "  ${c_cyan}│${c_reset}  "
    printf '%b\n' "$text"
    return 0
  fi
  printf "  ${c_cyan}│${c_reset}  "
  printf '%b' "$text"
  printf '%*s' "$padding" ''
  printf "  ${c_cyan}│${c_reset}\n"
}

menu_compact_uptime() {
  local seconds="${1:-}" days=0 hours=0 minutes=0
  [[ "$seconds" =~ ^[0-9]+$ ]] || { printf 'N/A\n'; return 1; }
  seconds=$((10#$seconds))
  days=$((seconds / 86400))
  hours=$(((seconds % 86400) / 3600))
  minutes=$(((seconds % 3600) / 60))
  if (( days > 0 )); then
    printf '%s天%s小时\n' "$days" "$hours"
  elif (( hours > 0 )); then
    printf '%s小时%s分\n' "$hours" "$minutes"
  elif (( minutes > 0 )); then
    printf '%s分钟\n' "$minutes"
  else
    printf '<1分钟\n'
  fi
}

menu_runtime_status() {
  local layout_width="${1:-$(menu_width)}"
  local uptime_seconds="" uptime_text="N/A" load_one="N/A" cpu_count="N/A"
  local mem_percent="N/A" disk_percent="N/A"
  local load_display="N/A" mem_display="N/A" disk_display="N/A"
  local load_color="$c_green" mem_color="$c_green" disk_color="$c_green"

  uptime_seconds="$(awk '{print int($1)}' /proc/uptime 2>/dev/null || true)"
  if [[ "$uptime_seconds" =~ ^[0-9]+$ ]]; then
    uptime_text="$(menu_compact_uptime "$uptime_seconds")"
  fi

  load_one="$(awk '{print $1}' /proc/loadavg 2>/dev/null || true)"
  [[ "$load_one" =~ ^[0-9]+([.][0-9]+)?$ ]] || load_one="N/A"
  cpu_count="$(getconf _NPROCESSORS_ONLN 2>/dev/null || nproc 2>/dev/null || true)"
  is_uint_in_range "$cpu_count" 1 1048576 || cpu_count="N/A"

  mem_percent="$(awk '
    /^MemTotal:/ {total=$2}
    /^MemAvailable:/ {available=$2}
    /^MemFree:/ {free_mem=$2}
    /^Buffers:/ {buffers=$2}
    /^Cached:/ {cached=$2}
    END {
      if (!available) available=free_mem+buffers+cached
      if (total > 0) printf "%.0f", (total-available)*100/total
    }
  ' /proc/meminfo 2>/dev/null || true)"
  is_uint_in_range "$mem_percent" 0 100 || mem_percent="N/A"

  disk_percent="$(LC_ALL=C df -P / 2>/dev/null | awk 'NR == 2 {gsub(/%/, "", $5); print $5}' || true)"
  is_uint_in_range "$disk_percent" 0 100 || disk_percent="N/A"

  if [[ "$load_one" != "N/A" && "$cpu_count" != "N/A" ]] && \
     awk -v load="$load_one" -v cpus="$cpu_count" 'BEGIN {exit !(load >= cpus)}'; then
    load_color="$c_yellow"
  fi
  if [[ "$load_one" != "N/A" && "$cpu_count" != "N/A" ]]; then
    load_display="${load_one}/${cpu_count}核"
  fi
  if [[ "$mem_percent" != "N/A" ]] && (( mem_percent >= 80 )); then mem_color="$c_yellow"; fi
  if [[ "$disk_percent" != "N/A" ]] && (( disk_percent >= 85 )); then disk_color="$c_yellow"; fi
  [[ "$mem_percent" == "N/A" ]] || mem_display="${mem_percent}%"
  [[ "$disk_percent" == "N/A" ]] || disk_display="${disk_percent}%"

  if (( layout_width < 68 )); then
    printf "${c_dim}运行${c_reset} ${c_cyan}%s${c_reset}" "$uptime_text"
    printf "  ${c_dim}· 负载${c_reset} ${load_color}%s${c_reset}\n" "$load_display"
    printf "${c_dim}内存${c_reset} ${mem_color}%s${c_reset}" "$mem_display"
    printf "  ${c_dim}· 根盘${c_reset} ${disk_color}%s${c_reset}\n" "$disk_display"
  else
    printf "${c_dim}运行${c_reset} ${c_cyan}%s${c_reset}" "$uptime_text"
    printf "  ${c_dim}· 负载${c_reset} ${load_color}%s${c_reset}" "$load_display"
    printf "  ${c_dim}· 内存${c_reset} ${mem_color}%s${c_reset}" "$mem_display"
    printf "  ${c_dim}· 根盘${c_reset} ${disk_color}%s${c_reset}\n" "$disk_display"
  fi
}

menu_header() {
  local title="$1" subtitle="${2:-}" width="" status_line="" subtitle_line=""
  soft_clear
  width="$(menu_width)"
  menu_box_top "$width"
  menu_box_row "${c_bold}${c_white}${title}${c_reset}" "$width"
  if [[ -n "$subtitle" ]]; then
    while IFS= read -r subtitle_line; do
      [[ -n "$subtitle_line" ]] && menu_box_row "${c_dim}${subtitle_line}${c_reset}" "$width"
    done < <(menu_wrap_segments "$subtitle" "$((width - 6))")
  fi
  menu_box_rule "$width"
  while IFS= read -r status_line; do
    [[ -n "$status_line" ]] && menu_box_row "$status_line" "$width"
  done < <(menu_runtime_status "$width")
  menu_box_rule "$width"
  menu_box_row "${c_dim}社区${c_reset}  ${c_green}${AD_TEXT}${c_reset}" "$width"
  menu_box_row "${c_cyan}bash <(curl -sL https://url.wuyang.skin/DMIT)${c_reset}" "$width"
  menu_box_rule "$width" '╰' '╯'
  MENU_AFTER_HEADER=1
}

menu_section() {
  local title="$1" width="" used=0 fill=0
  width="$(menu_width)"
  used=$((4 + $(menu_display_width "$title")))
  fill=$((width - used))
  (( fill < 3 )) && fill=3
  echo
  MENU_AFTER_HEADER=0
  printf "  ${c_cyan}${c_bold}▸ %s${c_reset} ${c_dim}%s${c_reset}\n" \
    "$title" "$(menu_repeat '─' "$fill")"
}

menu_item() {
  local key="$1" title="$2" detail="${3:-}" width="" item_width=0
  if (( MENU_AFTER_HEADER == 1 )); then
    echo
    MENU_AFTER_HEADER=0
  fi
  width="$(menu_width)"
  item_width=$((10 + $(menu_display_width "$title") + $(menu_display_width "$detail")))
  printf "  ${c_cyan}${c_bold}[%2s]${c_reset}  ${c_bold}${c_white}%s${c_reset}" "$key" "$title"
  if [[ -n "$detail" ]] && (( item_width > width )); then
    printf "\n        ${c_dim}└─ %s${c_reset}" "$detail"
  elif [[ -n "$detail" ]]; then
    printf "  ${c_dim}› %s${c_reset}" "$detail"
  fi
  printf "\n"
}

menu_back_item() {
  echo
  menu_item "0" "返回上级"
  menu_rule
}

banner() {
  menu_header "DMIT 工具箱" "网络优化 · 安全防护 · 站点服务 · 系统维护"
}

sub_banner() {
  menu_rule
  echo -e "  ${c_dim}社区${c_reset}  ${c_green}${AD_TEXT}${c_reset}"
  echo "bash <(curl -sL https://url.wuyang.skin/DMIT)"
  menu_rule
}

# ---------------- 环境快照 ----------------
env_snapshot() {
  ensure_dir "$BACKUP_BASE"
  local bdir=""
  bdir="${BACKUP_BASE}/snapshot-$(ts_now)"
  ensure_dir "$bdir"
  info "环境快照 → ${bdir}"

  for p in /etc/sysctl.conf /etc/sysctl.d /etc/gai.conf /etc/modprobe.d /etc/default/grub /etc/network /etc/netplan /etc/systemd/network /etc/resolv.conf /etc/ssh/sshd_config /etc/ssh/sshd_config.d /etc/ufw /etc/firewalld "$COMMON_FIREWALL_REGISTRY"; do
    if [[ -e "$p" ]]; then
      mkdir -p "${bdir}$(dirname "$p")"
      cp -a "$p" "${bdir}${p}" 2>/dev/null || true
    fi
  done

  {
    echo "time=$(date)"
    echo "uname=$(uname -a)"
    echo "libc=$(libc_kind)"
    echo "iface=$(default_iface)"
    echo "timezone=$( (timedatectl show -p Timezone --value 2>/dev/null || cat /etc/timezone 2>/dev/null || true) )"
    echo "time_sync=$(time_sync_status_text 2>/dev/null || echo unavailable)"
    echo "ipv6_sysctl=$(ipv6_status)"
    echo
    echo "== ip -br a =="; ip -br a 2>/dev/null || true
    echo
    echo "== ip -4 route =="; ip -4 route 2>/dev/null || true
    echo
    echo "== ip -6 addr =="; ip -6 addr show 2>/dev/null || true
    echo
    echo "== ip -6 route =="; ip -6 route show 2>/dev/null || true
    echo
    echo "== resolv.conf =="; sed -n '1,80p' /etc/resolv.conf 2>/dev/null || true
    echo
    echo "== qdisc =="; tc qdisc show 2>/dev/null || true
    echo
    echo "== bbr =="; cat /proc/sys/net/ipv4/tcp_available_congestion_control 2>/dev/null || true
    echo
    echo "== sshd -T (if available) =="; (sshd -T 2>/dev/null | sed -n '1,220p' || true)
    echo
    echo "== firewall managers =="
    (LC_ALL=C ufw status verbose 2>/dev/null || true)
    (firewall-cmd --state 2>/dev/null || true)
    (firewall-cmd --get-active-zones 2>/dev/null || true)
    echo
    echo "== nftables tables =="; (nft list tables 2>/dev/null || true)
    echo
    echo "== iptables policies =="; (iptables -S 2>/dev/null | sed -n '1,160p' || true)
  } > "${bdir}/state.txt"

  ok "已保存：${bdir}"
  echo "查看：less -S ${bdir}/state.txt"
}

# ---------------- 时区：中国 ----------------
set_timezone_china() {
  info "时区：设置为中国（Asia/Shanghai）"
  pkg_install tzdata

  if have_cmd timedatectl; then
    timedatectl set-timezone Asia/Shanghai >/dev/null 2>&1 || true
  fi

  if [[ -e /usr/share/zoneinfo/Asia/Shanghai ]]; then
    ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime || true
    echo "Asia/Shanghai" > /etc/timezone 2>/dev/null || true
  fi

  local tz
  tz="$( (timedatectl show -p Timezone --value 2>/dev/null || cat /etc/timezone 2>/dev/null || echo "unknown") )"
  ok "当前时区：$tz"
}

# ---------------- 重启网络服务 ----------------
restart_network_services_best_effort() {
  if ! is_systemd; then
    warn "无 systemd：跳过网络服务重启"
    return 0
  fi

  local restarted=0
  if systemctl is-active --quiet systemd-networkd 2>/dev/null; then
    info "重启：systemd-networkd"
    systemctl restart systemd-networkd >/dev/null 2>&1 || true
    restarted=1
  fi
  if systemctl is-active --quiet NetworkManager 2>/dev/null; then
    info "重启：NetworkManager"
    systemctl restart NetworkManager >/dev/null 2>&1 || true
    restarted=1
  fi
  if systemctl is-active --quiet networking 2>/dev/null; then
    info "重启：networking"
    systemctl restart networking >/dev/null 2>&1 || true
    restarted=1
  fi

  if [[ "$restarted" -eq 0 ]]; then
    info "尝试重启常见网络服务（忽略错误）"
    systemctl restart networking >/dev/null 2>&1 || true
    systemctl restart systemd-networkd >/dev/null 2>&1 || true
    systemctl restart NetworkManager >/dev/null 2>&1 || true
  fi
}

# ---------------- IPv6 随机出网：暂停/恢复 ----------------
ipv6_rand_pause_keep_conf() {
  if have_cmd nft; then
    nft delete table inet dmitbox_rand6 >/dev/null 2>&1 || true
  fi
  if is_systemd; then
    systemctl stop dmit-ipv6-rand.service >/dev/null 2>&1 || true
  fi
}

ipv6_rand_resume_if_configured() {
  [[ -f "$IPV6_RAND_CONF" ]] || return 0
  [[ -f "$IPV6_RAND_NFT" ]] || return 0

  ipv6_rand_load_conf || return 0

  local i
  for ((i=0;i<N;i++)); do
    local addr_var="ADDR_${i}"
    local addr_val="${!addr_var:-}"
    [[ -n "$addr_val" ]] || continue
    if ! ipv6_addr_exists "$IFACE" "$addr_val"; then
      ip -6 addr add "${addr_val}/128" dev "$IFACE" >/dev/null 2>&1 || true
    fi
  done

  ipv6_rand_apply_nft_runtime || { warn "随机出网恢复失败（nft 未加载）"; return 0; }

  if is_systemd && [[ -f "$IPV6_RAND_SERVICE" ]]; then
    systemctl restart dmit-ipv6-rand.service >/dev/null 2>&1 || true
  fi

  ok "已自动恢复：随机出网 IPv6（之前启用过）"
}

# ---------------- IPv6 开关 ----------------
ipv6_managed_keys() {
  printf '%s\n' \
    net.ipv6.conf.all.disable_ipv6 \
    net.ipv6.conf.default.disable_ipv6 \
    net.ipv6.conf.lo.disable_ipv6 \
    net.ipv6.conf.all.accept_ra \
    net.ipv6.conf.default.accept_ra \
    net.ipv6.conf.all.autoconf \
    net.ipv6.conf.default.autoconf
}

ipv6_backup_runtime_once() {
  [[ -s "$IPV6_SYSCTL_BACKUP" ]] && return 0
  ensure_dir "$BACKUP_BASE"
  local tmp="${IPV6_SYSCTL_BACKUP}.tmp.$$" key value saved=0
  : > "$tmp"
  while IFS= read -r key; do
    value="$(sysctl -n "$key" 2>/dev/null || true)"
    [[ -n "$value" ]] || continue
    printf '%s=%s\n' "$key" "$value" >> "$tmp"
    saved=$((saved + 1))
  done < <(ipv6_managed_keys)
  if (( saved == 0 )); then
    rm -f "$tmp" >/dev/null 2>&1 || true
    warn "未能读取当前 IPv6 sysctl 参数，已取消修改"
    return 1
  fi
  chmod 600 "$tmp" >/dev/null 2>&1 || true
  mv -f "$tmp" "$IPV6_SYSCTL_BACKUP"
  ok "已备份修改前 IPv6 参数：$IPV6_SYSCTL_BACKUP"
}

ipv6_restore_runtime_backup() {
  [[ -s "$IPV6_SYSCTL_BACKUP" ]] || return 1
  local line key value restored=0 failed=0
  while IFS= read -r line; do
    [[ "$line" == *=* ]] || continue
    key="${line%%=*}"
    value="${line#*=}"
    ipv6_managed_keys | grep -Fxq "$key" || continue
    if sysctl -w "${key}=${value}" >/dev/null 2>&1; then
      restored=$((restored + 1))
    else
      failed=$((failed + 1))
    fi
  done < "$IPV6_SYSCTL_BACKUP"
  (( restored > 0 )) || return 1
  (( failed == 0 )) || warn "有 ${failed} 项 IPv6 参数当前无法恢复"
}

ipv6_disable() {
  info "IPv6：关闭（系统级禁用）"
  ipv6_backup_runtime_once || return 1
  ipv6_rand_pause_keep_conf || true

  rm -f "$IPV6_FIX_SYSCTL_FILE" || true

  write_file "$IPV6_SYSCTL_FILE" \
"net.ipv6.conf.all.disable_ipv6=1
net.ipv6.conf.default.disable_ipv6=1
net.ipv6.conf.lo.disable_ipv6=1"
  sysctl_apply_all
  ok "IPv6 已关闭（sysctl: $(ipv6_status)）"
}

_ipv6_enable_runtime_all_ifaces() {
  for f in /proc/sys/net/ipv6/conf/*/disable_ipv6; do
    [[ -e "$f" ]] || continue
    echo 0 > "$f" 2>/dev/null || true
  done
}

_ipv6_find_disable_sources() {
  echo -e "${c_yellow}${c_bold}--- IPv6 开启失败排查 ---${c_reset}"
  echo -e "${c_dim}[启动参数]${c_reset} $(cat /proc/cmdline 2>/dev/null || true)"
  if grep -qw "ipv6.disable=1" /proc/cmdline 2>/dev/null; then
    warn "发现 ipv6.disable=1：必须改 GRUB/引导并重启"
  fi
  echo
  echo -e "${c_dim}[sysctl 覆盖]${c_reset}"
  (grep -RIn --line-number -E 'net\.ipv6\.conf\.(all|default|lo)\.disable_ipv6[[:space:]]*=[[:space:]]*1' \
    /etc/sysctl.conf /etc/sysctl.d 2>/dev/null || true) | sed -n '1,140p'
  echo
  echo -e "${c_dim}[模块黑名单]${c_reset}"
  (grep -RIn --line-number -E '^[[:space:]]*blacklist[[:space:]]+ipv6|^[[:space:]]*install[[:space:]]+ipv6[[:space:]]+/bin/true' \
    /etc/modprobe.d 2>/dev/null || true) | sed -n '1,140p'
  echo -e "${c_yellow}${c_bold}------------------------${c_reset}"
}


_ipv6_ra_status() {
  local ar da aa da2
  ar="$(sysctl -n net.ipv6.conf.all.accept_ra 2>/dev/null || echo "N/A")"
  da="$(sysctl -n net.ipv6.conf.default.accept_ra 2>/dev/null || echo "N/A")"
  aa="$(sysctl -n net.ipv6.conf.all.autoconf 2>/dev/null || echo "N/A")"
  da2="$(sysctl -n net.ipv6.conf.default.autoconf 2>/dev/null || echo "N/A")"
  echo "accept_ra: all=${ar} default=${da} | autoconf: all=${aa} default=${da2}"
}

_grub_rebuild_best_effort() {
  if have_cmd update-grub; then
    update-grub >/dev/null 2>&1 || true
    return 0
  fi
  if have_cmd grub2-mkconfig; then
    if [[ -f /boot/grub2/grub.cfg ]]; then
      grub2-mkconfig -o /boot/grub2/grub.cfg >/dev/null 2>&1 || true
    elif [[ -f /boot/grub/grub.cfg ]]; then
      grub2-mkconfig -o /boot/grub/grub.cfg >/dev/null 2>&1 || true
    else
      grub2-mkconfig -o /boot/grub2/grub.cfg >/dev/null 2>&1 || true
    fi
    return 0
  fi
  return 0
}

_ipv6_remove_cmdline_disable_from_file() {
  local f="$1"
  [[ -f "$f" ]] || return 0
  # remove token ipv6.disable=1 (keep file readable)
  sed -i 's/\<ipv6\.disable=1\>//g; s/[[:space:]]\{2,\}/ /g; s/" \+/"/g' "$f" 2>/dev/null || true
}

ipv6_hard_repair() {
  info "IPv6：强力修复（DD 后常见：修 GRUB/黑名单/RA/SLAAC）"
  ipv6_backup_runtime_once || return 1

  ensure_dir "$BACKUP_BASE"
  local bdir=""
  bdir="${BACKUP_BASE}/ipv6-hardfix-$(ts_now)"
  ensure_dir "$bdir"
  cp -a /etc/default/grub "$bdir/" 2>/dev/null || true
  cp -a /etc/default/grub.d "$bdir/" 2>/dev/null || true
  cp -a /etc/modprobe.d "$bdir/" 2>/dev/null || true
  cp -a /etc/sysctl.conf "$bdir/" 2>/dev/null || true
  cp -a /etc/sysctl.d "$bdir/" 2>/dev/null || true
  ok "已备份关键配置 → ${bdir}"

  local need_reboot=0

  # 1) cmdline disable
  if grep -qw "ipv6.disable=1" /proc/cmdline 2>/dev/null; then
    warn "检测到启动参数 ipv6.disable=1：将尝试从 GRUB 配置中移除（需重启生效）"
    _ipv6_remove_cmdline_disable_from_file /etc/default/grub
    shopt -s nullglob
    for f in /etc/default/grub.d/*.cfg; do
      _ipv6_remove_cmdline_disable_from_file "$f"
    done
    shopt -u nullglob
    _grub_rebuild_best_effort
    need_reboot=1
  fi

  # 2) modprobe blacklist
  shopt -s nullglob
  for f in /etc/modprobe.d/*.conf; do
    [[ -f "$f" ]] || continue
    if grep -Eq '^[[:space:]]*(blacklist[[:space:]]+ipv6|install[[:space:]]+ipv6[[:space:]]+/bin/true)' "$f" 2>/dev/null; then
      warn "发现 ipv6 模块黑名单：$f（将注释相关行）"
      sed -i -E 's/^[[:space:]]*(blacklist[[:space:]]+ipv6)/# ipv6fix: \1/g; s/^[[:space:]]*(install[[:space:]]+ipv6[[:space:]]+\/bin\/true)/# ipv6fix: \1/g' "$f" 2>/dev/null || true
    fi
  done
  shopt -u nullglob

  # 3) sysctl fix (persist)
  write_file "$IPV6_FIX_SYSCTL_FILE" "# managed by ${SCRIPT_NAME} (ipv6 hardfix)
net.ipv6.conf.all.disable_ipv6=0
net.ipv6.conf.default.disable_ipv6=0
net.ipv6.conf.lo.disable_ipv6=0
# DD 后常见：不接收 RA / 不做 SLAAC
net.ipv6.conf.all.accept_ra=2
net.ipv6.conf.default.accept_ra=2
net.ipv6.conf.all.autoconf=1
net.ipv6.conf.default.autoconf=1"

  # runtime apply
  if have_cmd modprobe; then modprobe ipv6 >/dev/null 2>&1 || true; fi
  sysctl -w net.ipv6.conf.all.disable_ipv6=0 >/dev/null 2>&1 || true
  sysctl -w net.ipv6.conf.default.disable_ipv6=0 >/dev/null 2>&1 || true
  sysctl -w net.ipv6.conf.lo.disable_ipv6=0 >/dev/null 2>&1 || true
  sysctl -w net.ipv6.conf.all.accept_ra=2 >/dev/null 2>&1 || true
  sysctl -w net.ipv6.conf.default.accept_ra=2 >/dev/null 2>&1 || true
  sysctl -w net.ipv6.conf.all.autoconf=1 >/dev/null 2>&1 || true
  sysctl -w net.ipv6.conf.default.autoconf=1 >/dev/null 2>&1 || true
  _ipv6_enable_runtime_all_ifaces
  sysctl_apply_all

  restart_network_services_best_effort
  sleep 2

  # then run normal enable flow (includes pool apply + status)
  ipv6_enable || true

  if [[ "$need_reboot" -eq 1 ]]; then
    warn "已修改 GRUB 去除 ipv6.disable=1：必须重启后 IPv6 才可能恢复"
  fi
}

ipv6_enable() {
  info "IPv6：开启（自动重拉地址/默认路由）"
  ipv6_backup_runtime_once || return 1

  rm -f "$IPV6_SYSCTL_FILE" || true

  # persist: DD 后常见需要开启 RA/SLAAC（不然没默认路由/没自动地址）
  write_file "$IPV6_FIX_SYSCTL_FILE" "# managed by ${SCRIPT_NAME} (ipv6 fix)
net.ipv6.conf.all.disable_ipv6=0
net.ipv6.conf.default.disable_ipv6=0
net.ipv6.conf.lo.disable_ipv6=0
net.ipv6.conf.all.accept_ra=2
net.ipv6.conf.default.accept_ra=2
net.ipv6.conf.all.autoconf=1
net.ipv6.conf.default.autoconf=1"

  if have_cmd modprobe; then
    modprobe ipv6 >/dev/null 2>&1 || true
  fi

  sysctl -w net.ipv6.conf.all.disable_ipv6=0 >/dev/null 2>&1 || true
  sysctl -w net.ipv6.conf.default.disable_ipv6=0 >/dev/null 2>&1 || true
  sysctl -w net.ipv6.conf.lo.disable_ipv6=0 >/dev/null 2>&1 || true
  sysctl -w net.ipv6.conf.all.accept_ra=2 >/dev/null 2>&1 || true
  sysctl -w net.ipv6.conf.default.accept_ra=2 >/dev/null 2>&1 || true
  sysctl -w net.ipv6.conf.all.autoconf=1 >/dev/null 2>&1 || true
  sysctl -w net.ipv6.conf.default.autoconf=1 >/dev/null 2>&1 || true
  _ipv6_enable_runtime_all_ifaces
  sysctl_apply_all

  restart_network_services_best_effort
  sleep 2
  _ipv6_enable_runtime_all_ifaces

  ipv6_pool_apply_from_conf >/dev/null 2>&1 || true

  local st; st="$(ipv6_status)"

  echo -e "${c_dim}--- IPv6 状态快照 ---${c_reset}"
  echo -e "${c_dim}sysctl:${c_reset} $st"
  echo -e "${c_dim}RA/SLAAC:${c_reset} $(_ipv6_ra_status)"
  echo -e "${c_dim}地址:${c_reset}"
  ip -6 addr show 2>/dev/null || true
  echo -e "${c_dim}路由:${c_reset}"
  ip -6 route show 2>/dev/null || true
  echo -e "${c_dim}---------------------${c_reset}"

  if echo "$st" | grep -q "all=0" && echo "$st" | grep -q "default=0" \
     && has_ipv6_global_addr && has_ipv6_default_route; then
    ok "IPv6 已可用（有公网 IPv6 + 默认路由）"
    ipv6_rand_resume_if_configured || true
  else
    warn "IPv6 未完整（缺公网 IPv6 或默认路由）"
    warn "如果 DMIT 面板未分配 IPv6，本机不会凭空生成公网 IPv6"
    _ipv6_find_disable_sources
  fi
}

# ---------------- IPv4/IPv6 优先级（glibc） ----------------
gai_backup_once() {
  ensure_dir "$BACKUP_BASE"
  if [[ -f "$GAI_CONF" ]] && [[ ! -f "${BACKUP_BASE}/gai.conf.orig" ]]; then
    cp -a "$GAI_CONF" "${BACKUP_BASE}/gai.conf.orig" || true
    ok "已备份 gai.conf.orig"
  fi
}

prefer_ipv4() {
  info "网络：优先 IPv4（系统解析优先级）"
  local kind; kind="$(libc_kind)"
  if [[ "$kind" != "glibc" ]]; then
    warn "非 glibc：此方式无效（Alpine/musl 常见），可用：关闭 IPv6 或应用层 -4"
    return 0
  fi
  gai_backup_once
  touch "$GAI_CONF"
  sed -i -E '/^[[:space:]]*precedence[[:space:]]+::ffff:0:0\/96[[:space:]]+[0-9]+[[:space:]]*$/d' "$GAI_CONF"
  printf "\n# %s managed: prefer IPv4\nprecedence ::ffff:0:0/96  100\n" "$SCRIPT_NAME" >> "$GAI_CONF"
  ok "已设置：IPv4 优先"
}

prefer_ipv6() {
  info "网络：优先 IPv6（恢复默认倾向）"
  local kind; kind="$(libc_kind)"
  if [[ "$kind" != "glibc" ]]; then
    warn "非 glibc：此方式无效；要更强制 IPv6：确保 IPv6 可用，并应用层 -6"
    return 0
  fi
  gai_backup_once
  touch "$GAI_CONF"
  sed -i -E '/^[[:space:]]*#[[:space:]]*'"${SCRIPT_NAME}"'[[:space:]]*managed: prefer IPv4[[:space:]]*$/d' "$GAI_CONF" || true
  sed -i -E '/^[[:space:]]*precedence[[:space:]]+::ffff:0:0\/96[[:space:]]+[0-9]+[[:space:]]*$/d' "$GAI_CONF" || true
  ok "已恢复：IPv6 倾向（默认）"
}

restore_gai_default() {
  info "网络：恢复 gai.conf（回到备份状态）"
  if [[ -f "${BACKUP_BASE}/gai.conf.orig" ]]; then
    cp -a "${BACKUP_BASE}/gai.conf.orig" "$GAI_CONF" || true
    ok "已恢复 gai.conf.orig"
  else
    warn "未找到 gai.conf.orig：改为移除脚本写入规则"
    prefer_ipv6 || true
  fi
}

# ---------------- BBR / TCP ----------------
tcp_available_congestion_controls() {
  cat /proc/sys/net/ipv4/tcp_available_congestion_control 2>/dev/null
}

bbr_check() {
  echo "================ BBR 检测 ================"
  echo "kernel=$(uname -r)"
  local avail cur
  avail="$(tcp_available_congestion_controls 2>/dev/null || true)"
  cur="$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || echo "N/A")"
  echo "当前=${cur}"
  echo "可用=${avail:-N/A}"
  if echo " $avail " | grep -q " bbr "; then
    ok "支持 bbr（实现取决于内核）"
  else
    warn "未看到 bbr（可能内核不含/模块不可用）"
  fi
  echo "=========================================="
}

tcp_managed_keys() {
  printf '%s\n' \
    net.core.default_qdisc \
    net.ipv4.tcp_congestion_control \
    net.core.netdev_max_backlog \
    net.core.somaxconn \
    net.ipv4.tcp_max_syn_backlog \
    net.core.rmem_max \
    net.core.wmem_max \
    net.ipv4.tcp_rmem \
    net.ipv4.tcp_wmem \
    net.ipv4.tcp_mtu_probing \
    net.ipv4.tcp_fastopen \
    net.ipv4.tcp_syncookies \
    net.ipv4.tcp_adv_win_scale \
    net.ipv4.tcp_sack \
    net.ipv4.tcp_timestamps \
    kernel.panic \
    vm.swappiness
}

tcp_runtime_snapshot_write() {
  local destination="$1" tmp="" key="" value="" saved=0
  tmp="${destination}.tmp.$$"
  ensure_dir "$(dirname "$destination")" || return 1
  : > "$tmp" || return 1

  while IFS= read -r key; do
    value="$(sysctl -n "$key" 2>/dev/null || true)"
    [[ -n "$value" ]] || continue
    printf '%s=%s\n' "$key" "$value" >> "$tmp" || {
      rm -f -- "$tmp" >/dev/null 2>&1 || true
      return 1
    }
    saved=$((saved + 1))
  done < <(tcp_managed_keys)

  if (( saved == 0 )); then
    rm -f -- "$tmp" >/dev/null 2>&1 || true
    return 1
  fi
  chmod 600 "$tmp" >/dev/null 2>&1 || true
  mv -f -- "$tmp" "$destination"
}

tcp_runtime_snapshot_restore() {
  local source="$1" line="" key="" value="" restored=0 failed=0
  [[ -s "$source" && ! -L "$source" ]] || return 1

  while IFS= read -r line; do
    [[ "$line" == *=* ]] || continue
    key="${line%%=*}"
    value="${line#*=}"
    tcp_managed_keys | grep -Fxq "$key" || continue
    if sysctl -w "${key}=${value}" >/dev/null 2>&1; then
      restored=$((restored + 1))
    else
      failed=$((failed + 1))
    fi
  done < "$source"

  (( restored > 0 )) || return 1
  (( failed == 0 )) || return 2
  return 0
}

tcp_backup_runtime_once() {
  [[ -s "$TCP_SYSCTL_BACKUP" ]] && return 0

  ensure_dir "$BACKUP_BASE"
  if ! tcp_runtime_snapshot_write "$TCP_SYSCTL_BACKUP"; then
    warn "未能读取当前 TCP/sysctl 参数，已取消修改"
    return 1
  fi
  ok "已备份修改前 TCP/sysctl 参数：$TCP_SYSCTL_BACKUP"
}

tcp_restore_runtime_backup() {
  [[ -s "$TCP_SYSCTL_BACKUP" ]] || return 1
  local rc=0
  tcp_runtime_snapshot_restore "$TCP_SYSCTL_BACKUP" || rc=$?
  return "$rc"
}

tcp_fixed_profile_content() {
  cat <<'EOF'
# managed by dmitbox.sh - fixed common TCP tuning
# Static compatibility profile: no bandwidth or RTT measurement.
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr

net.core.netdev_max_backlog = 16384
net.core.somaxconn = 8192
net.ipv4.tcp_max_syn_backlog = 8192

net.core.rmem_max = 67108864
net.core.wmem_max = 67108864
net.ipv4.tcp_rmem = 4096 87380 67108864
net.ipv4.tcp_wmem = 4096 65536 67108864

net.ipv4.tcp_mtu_probing = 1
net.ipv4.tcp_fastopen = 3
net.ipv4.tcp_syncookies = 1
EOF
}

tcp_value_normalize() {
  awk '{$1=$1; print}' <<< "${1:-}"
}

tcp_fixed_profile_keys() {
  tcp_fixed_profile_content | awk -F= '
    /^[[:space:]]*#/ || /^[[:space:]]*$/ {next}
    {
      key=$1
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", key)
      if (key != "") print key
    }'
}

tcp_fixed_runtime_verify() {
  local line="" key="" expected="" actual=""
  while IFS= read -r line; do
    [[ "$line" == *=* ]] || continue
    key="${line%%=*}"
    expected="${line#*=}"
    key="$(tcp_value_normalize "$key")"
    expected="$(tcp_value_normalize "$expected")"
    [[ -n "$key" ]] || continue
    actual="$(sysctl -n "$key" 2>/dev/null || true)"
    actual="$(tcp_value_normalize "$actual")"
    [[ -n "$actual" && "$actual" == "$expected" ]] || return 1
  done < <(tcp_fixed_profile_content | sed -E '/^[[:space:]]*(#|$)/d')
  return 0
}

tcp_fixed_status_text() {
  if tcpfit_tuning_active; then
    printf '未启用（动态调优生效）\n'
  elif [[ -s "$TUNE_SYSCTL_FILE" ]]; then
    if tcp_fixed_runtime_verify; then
      printf '已应用且运行正常\n'
    else
      printf '已配置但运行值不一致\n'
    fi
  else
    printf '未应用\n'
  fi
}

tcp_fixed_preflight() {
  local available="" key="" unsupported=()
  if tcpfit_tuning_active; then
    warn "动态实测调优正在生效，不能叠加固定通用调优"
    info "请先进入【动态实测调优】按 tcpfit 快照完整回滚"
    return 1
  fi
  have_cmd sysctl || { warn "系统缺少 sysctl，无法应用 TCP 参数"; return 1; }
  if [[ -L "$TUNE_SYSCTL_FILE" || -L "$DMIT_TCP_DEFAULT_FILE" ]]; then
    warn "检测到 TCP 配置路径是符号链接，为避免覆盖未知文件已取消"
    return 1
  fi
  if have_cmd modprobe; then
    modprobe tcp_bbr >/dev/null 2>&1 || true
    modprobe sch_fq >/dev/null 2>&1 || true
  fi
  available="$(tcp_available_congestion_controls 2>/dev/null || true)"
  case " ${available} " in
    *" bbr "*) ;;
    *)
      warn "当前内核未提供 BBR，固定通用调优已取消"
      info "可先使用【检测 BBR 支持】确认；本脚本不会为此替换第三方内核"
      return 1
      ;;
  esac
  while IFS= read -r key; do
    [[ -n "$key" ]] || continue
    sysctl -n "$key" >/dev/null 2>&1 || unsupported+=("$key")
  done < <(tcp_fixed_profile_keys)
  if (( ${#unsupported[@]} > 0 )); then
    warn "当前内核缺少固定配置所需参数，未写入任何配置："
    printf '    - %s\n' "${unsupported[@]}"
    return 1
  fi
  return 0
}

tcp_fixed_transaction_restore() {
  local rollback="$1" rc=0
  if [[ -f "$rollback/had-fixed" ]]; then
    cp -a "$rollback/fixed.conf" "$TUNE_SYSCTL_FILE" || rc=1
  else
    rm -f -- "$TUNE_SYSCTL_FILE" >/dev/null 2>&1 || rc=1
  fi
  if [[ -f "$rollback/had-dmit" ]]; then
    cp -a "$rollback/dmit.conf" "$DMIT_TCP_DEFAULT_FILE" || rc=1
  else
    rm -f -- "$DMIT_TCP_DEFAULT_FILE" >/dev/null 2>&1 || rc=1
  fi
  sysctl_apply_all
  tcp_runtime_snapshot_restore "$rollback/runtime.snapshot" >/dev/null 2>&1 || rc=1
  return "$rc"
}

tcp_fixed_apply() {
  local rollback="" candidate="" staged="" log="" ifc="" root_qdisc="" rc=0
  tcp_fixed_preflight || return 1

  if [[ -s "$TUNE_SYSCTL_FILE" ]] && \
     cmp -s "$TUNE_SYSCTL_FILE" <(tcp_fixed_profile_content) && \
     tcp_fixed_runtime_verify; then
    ok "固定通用调优已经正常生效，无需重复应用"
    return 0
  fi

  menu_section "固定配置预览"
  print_kv "拥塞控制 / 队列" "BBR / FQ"
  print_kv "TCP 缓冲上限" "64 MiB（固定值）"
  print_kv "连接队列" "somaxconn 8192 / SYN backlog 8192"
  print_kv "其他" "MTU 探测、TCP Fast Open、SYN Cookie"
  print_kv "固定状态" "$(tcp_fixed_status_text)"
  ifc="$(default_iface)"
  if have_cmd tc && [[ -n "$ifc" ]]; then
    root_qdisc="$(tc qdisc show dev "$ifc" 2>/dev/null | awk '/ root / {print $2; exit}' || true)"
    [[ -n "$root_qdisc" ]] && print_kv "当前出口队列" "${ifc} / ${root_qdisc}"
  fi
  warn "该模式不测速，也不会按带宽、RTT 或内存推导参数；适合作为快速兼容预设"
  info "不会覆盖当前网卡已有的 CAKE、HTB、TBF、NetEm 等手工 tc 规则"
  [[ -s "$DMIT_TCP_DEFAULT_FILE" ]] && info "现有 DMIT 默认参数将切换为固定通用参数"
  confirm_word "FIXED" "确认应用固定通用调优请输入 FIXED > " || { info "已取消"; return 0; }

  tcp_backup_runtime_once || return 1
  rollback="$(mktemp -d /tmp/dmitbox-tcp-fixed.XXXXXX)" || {
    warn "无法创建临时回滚点"
    return 1
  }
  candidate="${rollback}/candidate.conf"
  log="${rollback}/sysctl.log"
  tcp_fixed_profile_content > "$candidate" || {
    warn "无法生成固定调优配置"
    rm -rf -- "$rollback"
    return 1
  }
  chmod 600 "$candidate" >/dev/null 2>&1 || true
  if ! tcp_runtime_snapshot_write "$rollback/runtime.snapshot"; then
    warn "创建临时运行参数快照失败，未进行修改"
    rm -rf -- "$rollback"
    return 1
  fi
  if [[ -e "$TUNE_SYSCTL_FILE" ]]; then
    write_file "$rollback/had-fixed" 1
    cp -a "$TUNE_SYSCTL_FILE" "$rollback/fixed.conf" || rc=1
  fi
  if [[ -e "$DMIT_TCP_DEFAULT_FILE" ]]; then
    write_file "$rollback/had-dmit" 1
    cp -a "$DMIT_TCP_DEFAULT_FILE" "$rollback/dmit.conf" || rc=1
  fi
  if (( rc != 0 )); then
    warn "创建配置文件回滚点失败，未进行修改"
    rm -rf -- "$rollback"
    return 1
  fi

  ensure_dir "$(dirname "$TUNE_SYSCTL_FILE")" || rc=1
  staged="${TUNE_SYSCTL_FILE}.new.$$"
  if (( rc == 0 )); then
    cp "$candidate" "$staged" || rc=1
    chmod 644 "$staged" >/dev/null 2>&1 || rc=1
    mv -f -- "$staged" "$TUNE_SYSCTL_FILE" || rc=1
    rm -f -- "$DMIT_TCP_DEFAULT_FILE" >/dev/null 2>&1 || rc=1
  fi
  if (( rc == 0 )); then
    sysctl -p "$TUNE_SYSCTL_FILE" > "$log" 2>&1 || rc=$?
  fi
  if (( rc == 0 )) && ! tcp_fixed_runtime_verify; then
    rc=1
    printf '%s\n' '应用后运行值校验不一致' >> "$log"
  fi
  if (( rc != 0 )); then
    warn "固定通用调优应用失败，正在恢复修改前状态"
    tail -n 20 "$log" 2>/dev/null || true
    tcp_fixed_transaction_restore "$rollback" || \
      warn "自动回滚不完整，请进入【恢复修改前参数】再次恢复"
    rm -f -- "$staged" >/dev/null 2>&1 || true
    rm -rf -- "$rollback"
    return 1
  fi

  rm -rf -- "$rollback"
  ok "固定通用调优已应用并通过逐项运行值校验"
  info "持久配置：${TUNE_SYSCTL_FILE}"
  if [[ -n "$root_qdisc" && "$root_qdisc" != "fq" ]]; then
    info "当前网卡仍使用 ${root_qdisc}；脚本未覆盖已有活动 tc 队列"
  fi
  bbr_check
}

tcp_restore_default() {
  local restore_rc=0
  if tcpfit_tuning_active; then
    warn "动态实测调优正在生效，不能同时套用 DMITBox 参数恢复"
    info "请先进入【TCP / BBR → 动态实测调优】按 tcpfit 快照回滚"
    return 1
  fi
  info "TCP：恢复脚本修改前的参数"
  if ! rm -f -- "$TUNE_SYSCTL_FILE" "$DMIT_TCP_DEFAULT_FILE" >/dev/null 2>&1; then
    warn "无法移除脚本管理的 TCP 持久配置，已停止恢复"
    return 1
  fi
  sysctl_apply_all
  tcp_restore_runtime_backup || restore_rc=$?
  case "$restore_rc" in
    0) ok "已恢复脚本首次修改前的 TCP/sysctl 参数" ;;
    2) warn "原始备份已读取，但部分参数当前内核不支持或恢复失败" ;;
    *)
      warn "未找到可用的原始参数备份：已移除持久调优文件并重新加载系统 sysctl"
      warn "不同发行版默认值不同，不再强行写入过时的 pfifo_fast；重启后由系统默认配置接管"
      ;;
  esac
  bbr_check
}

tcp_restore_dmit_default() {
  if tcpfit_tuning_active; then
    warn "动态实测调优正在生效，不能同时套用 DMIT 默认参数"
    info "请先进入【TCP / BBR → 动态实测调优】按 tcpfit 快照回滚"
    return 1
  fi
  info "TCP：恢复 DMIT 默认 TCP"
  tcp_backup_runtime_once || return 1
  rm -f "$TUNE_SYSCTL_FILE" >/dev/null 2>&1 || true

  write_file "$DMIT_TCP_DEFAULT_FILE" \
"net.core.rmem_max = 67108848
net.core.wmem_max = 67108848
net.core.somaxconn = 4096
net.ipv4.tcp_max_syn_backlog = 4096
net.ipv4.tcp_congestion_control = bbr
net.ipv4.tcp_rmem = 16384 16777216 536870912
net.ipv4.tcp_wmem = 16384 16777216 536870912
net.ipv4.tcp_adv_win_scale = -2
net.ipv4.tcp_sack = 1
net.ipv4.tcp_timestamps = 1
kernel.panic = -1
vm.swappiness = 0"
  sysctl_apply_all
  ok "已应用 DMIT 默认 TCP 参数"
  bbr_check
}

# ---------------- 动态 TCP 实测调优（tcpfit） ----------------
tcpfit_tuning_active() {
  [[ -s "$TCPFIT_SYSCTL_FILE" || -s "$TCPFIT_QDISC_SERVICE" ]]
}

tcpfit_file_sha256() {
  local path="$1"
  [[ -f "$path" && ! -L "$path" ]] || return 1
  if have_cmd sha256sum; then
    sha256sum "$path" 2>/dev/null | awk '{print tolower($1); exit}'
  elif have_cmd shasum; then
    shasum -a 256 "$path" 2>/dev/null | awk '{print tolower($1); exit}'
  elif have_cmd openssl; then
    openssl dgst -sha256 "$path" 2>/dev/null | awk '{print tolower($NF); exit}'
  else
    return 1
  fi
}

tcpfit_installed_version() {
  [[ -f "$TCPFIT_INSTALL_PATH" && ! -L "$TCPFIT_INSTALL_PATH" ]] || return 1
  awk -F'"' '/^VERSION="[0-9]+\.[0-9]+\.[0-9]+"$/ {print $2; exit}' \
    "$TCPFIT_INSTALL_PATH" 2>/dev/null
}

tcpfit_tool_recognized() {
  local version=""
  [[ -f "$TCPFIT_INSTALL_PATH" && ! -L "$TCPFIT_INSTALL_PATH" ]] || return 1
  IFS= read -r version < "$TCPFIT_INSTALL_PATH" || true
  [[ "$version" == '#!/usr/bin/env bash' || "$version" == '#!/bin/bash' ]] || return 1
  version="$(tcpfit_installed_version || true)"
  [[ -n "$version" ]] || return 1
  grep -Fq '# tcpfit' "$TCPFIT_INSTALL_PATH" 2>/dev/null
}

tcpfit_is_reviewed_install() {
  local digest=""
  digest="$(tcpfit_file_sha256 "$TCPFIT_INSTALL_PATH" 2>/dev/null || true)"
  [[ -n "$digest" && "$digest" == "$TCPFIT_REVIEWED_SHA256" ]]
}

tcpfit_status_summary() {
  local version="" state="未调优"
  tcpfit_tuning_active && state="已调优"
  if [[ ! -e "$TCPFIT_INSTALL_PATH" ]]; then
    printf '未安装 · %s\n' "$state"
    return 0
  fi
  if [[ -L "$TCPFIT_INSTALL_PATH" ]] || ! tcpfit_tool_recognized; then
    printf '安装路径冲突 · %s\n' "$state"
    return 0
  fi
  version="$(tcpfit_installed_version || true)"
  if tcpfit_is_reviewed_install; then
    printf 'v%s 已校验 · %s\n' "$version" "$state"
  else
    printf 'v%s 非内置审核版 · %s\n' "$version" "$state"
  fi
}

tcpfit_install_reviewed() {
  local tmp_dir="" downloaded="" digest="" version="" backup="" replacement=""

  if tcpfit_is_reviewed_install; then
    ok "动态调优工具已是审核版 v${TCPFIT_REVIEWED_VERSION}，无需重复安装"
    return 0
  fi

  if [[ -L "$TCPFIT_INSTALL_PATH" ]]; then
    warn "${TCPFIT_INSTALL_PATH} 是符号链接，为避免覆盖未知目标已取消"
    return 1
  fi
  if [[ -e "$TCPFIT_INSTALL_PATH" ]]; then
    version="$(tcpfit_installed_version || true)"
    if tcpfit_tool_recognized; then
      warn "检测到现有 tcpfit v${version}，与内置审核版校验值不同"
    else
      warn "${TCPFIT_INSTALL_PATH} 已被其他文件占用"
    fi
    info "替换前会将原文件备份到 ${TCPFIT_BACKUP_DIR}"
    confirm_word "REPLACE" "确认替换请输入 REPLACE > " || { info "已取消"; return 0; }
  fi

  local -a missing=()
  have_cmd curl || missing+=(curl)
  have_cmd bash || missing+=(bash)
  have_cmd sha256sum || missing+=(coreutils)
  have_cmd install || missing+=(coreutils)
  if (( ${#missing[@]} > 0 )); then
    info "将安装动态调优工具所需依赖：${missing[*]}"
    pkg_install "${missing[@]}"
  fi
  have_cmd curl && have_cmd bash && have_cmd sha256sum && have_cmd install || {
    warn "缺少 curl、bash、sha256sum 或 install，无法安全安装"
    return 1
  }

  tmp_dir="$(mktemp -d /tmp/dmitbox-tcpfit.XXXXXX)" || {
    warn "无法创建临时目录"
    return 1
  }
  downloaded="${tmp_dir}/tcpfit.sh"
  info "正在下载 tcpfit v${TCPFIT_REVIEWED_VERSION} 正式发布文件……"
  if ! curl -fsSL --connect-timeout 10 --max-time 90 --retry 2 \
       "$TCPFIT_RELEASE_URL" -o "$downloaded"; then
    warn "动态调优工具下载失败，未修改系统"
    rm -rf -- "$tmp_dir"
    return 1
  fi
  digest="$(tcpfit_file_sha256 "$downloaded" 2>/dev/null || true)"
  if [[ "$digest" != "$TCPFIT_REVIEWED_SHA256" ]]; then
    warn "SHA-256 校验失败，已拒绝执行和安装"
    rm -rf -- "$tmp_dir"
    return 1
  fi
  if ! bash -n "$downloaded" || \
     ! grep -Fqx "VERSION=\"${TCPFIT_REVIEWED_VERSION}\"" "$downloaded"; then
    warn "发布文件内容或语法校验失败，已拒绝安装"
    rm -rf -- "$tmp_dir"
    return 1
  fi

  if [[ -e "$TCPFIT_INSTALL_PATH" ]]; then
    ensure_dir "$TCPFIT_BACKUP_DIR" || {
      warn "无法创建备份目录，已取消替换"
      rm -rf -- "$tmp_dir"
      return 1
    }
    backup="${TCPFIT_BACKUP_DIR}/tcpfit-$(ts_now)-$$"
    if ! cp -a "$TCPFIT_INSTALL_PATH" "$backup"; then
      warn "现有工具备份失败，已取消替换"
      rm -rf -- "$tmp_dir"
      return 1
    fi
    chmod 600 "$backup" >/dev/null 2>&1 || true
    info "原工具已备份：${backup}"
  fi

  ensure_dir "$(dirname "$TCPFIT_INSTALL_PATH")" || {
    warn "无法创建安装目录"
    rm -rf -- "$tmp_dir"
    return 1
  }
  replacement="${TCPFIT_INSTALL_PATH}.new.$$"
  if ! install -m 755 "$downloaded" "$replacement" || \
     ! mv -f "$replacement" "$TCPFIT_INSTALL_PATH"; then
    warn "动态调优工具安装失败"
    rm -f -- "$replacement" >/dev/null 2>&1 || true
    rm -rf -- "$tmp_dir"
    return 1
  fi
  rm -rf -- "$tmp_dir"

  if ! tcpfit_is_reviewed_install; then
    warn "安装后的文件校验异常，已停止后续操作"
    return 1
  fi
  ok "动态调优工具已安全安装：tcpfit v${TCPFIT_REVIEWED_VERSION}"
  info "来源：Kylin010/tcpfit 正式发布文件（已固定版本并校验 SHA-256）"
}

tcpfit_require_tool() {
  if [[ ! -e "$TCPFIT_INSTALL_PATH" ]]; then
    info "尚未安装动态调优工具，将先安装审核版"
    tcpfit_install_reviewed || return 1
  fi
  if [[ -L "$TCPFIT_INSTALL_PATH" ]] || ! tcpfit_tool_recognized; then
    warn "${TCPFIT_INSTALL_PATH} 不是可识别的 tcpfit 文件"
    info "请使用本菜单的【安装或修复工具】处理路径冲突"
    return 1
  fi
  if ! tcpfit_is_reviewed_install; then
    warn "当前 tcpfit 不是本脚本内置审核版；可能是你自行更新或安装的版本"
    info "如不确定来源，请先选择【安装或修复工具】恢复审核版"
  fi
}

tcpfit_prepare_switch() {
  tcpfit_tuning_active && return 0
  if [[ -s "$TUNE_SYSCTL_FILE" || -s "$DMIT_TCP_DEFAULT_FILE" ]]; then
    warn "检测到固定通用或 DMIT 默认 TCP 参数，不能与动态参数叠加"
    info "切换时将先按首次备份恢复原参数，再由 tcpfit 创建独立快照"
    confirm_word "DYNAMIC" "确认切换到动态调优请输入 DYNAMIC > " || {
      info "已取消切换"
      return 1
    }
    tcp_restore_default || return 1
    [[ ! -e "$TUNE_SYSCTL_FILE" && ! -e "$DMIT_TCP_DEFAULT_FILE" ]] || {
      warn "旧式参数文件尚未完全移除，已取消动态调优"
      return 1
    }
  fi
}

tcpfit_run_interactive() {
  if ! is_systemd; then
    warn "动态调优的持久化与回滚依赖 systemd，当前系统不支持"
    return 1
  fi
  if ! have_cmd ip; then
    warn "缺少 iproute2（ip 命令），请先安装后再运行动态调优"
    return 1
  fi
  tcpfit_require_tool || return 1
  tcpfit_prepare_switch || return 1
  if ! has_tty; then
    warn "动态实测需要交互终端，当前环境无法运行"
    return 1
  fi

  local ifc="" root_qdisc=""
  ifc="$(default_iface)"
  if have_cmd tc && [[ -n "$ifc" ]]; then
    root_qdisc="$(tc qdisc show dev "$ifc" 2>/dev/null | awk '/ root / {print $2; exit}' || true)"
  fi

  menu_section "运行说明"
  info "tcpfit 会按带宽、RTT、内存和用途推导 BDP 与缓冲区"
  info "可使用 iperf3 实测限速器拐点，并按结果选择 HTB + FQ 出口整形"
  info "关键缓冲区与整形值由实测推导；其余队列和连接项使用 tcpfit 基础配置"
  [[ -n "$root_qdisc" ]] && print_kv "当前出口队列" "${ifc} / ${root_qdisc}"
  warn "实测会产生真实网络流量：高速端口完整扫描可能消耗数 GB 至数十 GB"
  warn "调优会修改 sysctl、qdisc 和路由初始窗口；低权限 LXC/OpenVZ 可能不支持"
  warn "若你已手工配置 CAKE、HTB、TBF、NetEm 或其他 tc 规则，请取消并先备份规则"
  info "完整流程通常约 1-10 分钟，最长运行 60 分钟；Ctrl+C 可中断并返回工具箱"
  info "首次改动前会保存 tcpfit 独立快照，可从本菜单完整回滚"
  info "Swap 请继续使用 DMITBox 的 Swap 管理；在 tcpfit 中选择跳过加 Swap"
  confirm_word "TUNE" "确认打开动态调优请输入 TUNE > " || { info "已取消"; return 0; }

  local rc=0
  remote_script_execute "$TCPFIT_INSTALL_PATH" 3600 "动态调优" || rc=$?
  if (( rc == 124 || rc == 130 )); then
    return "$rc"
  elif (( rc != 0 )); then
    warn "动态调优工具异常退出（退出码：${rc}）"
    return "$rc"
  fi
  ok "已退出动态调优工具"
}

tcpfit_show_status() {
  menu_header "动态 TCP 状态" "机器画像 · BDP 参数 · qdisc 与快照"
  print_kv "工具状态" "$(tcpfit_status_summary)"
  print_kv "参数文件" "$([[ -s "$TCPFIT_SYSCTL_FILE" ]] && echo 已应用 || echo 未应用)"
  print_kv "整形服务" "$([[ -s "$TCPFIT_QDISC_SERVICE" ]] && echo 已配置 || echo 未配置)"
  print_kv "回滚快照" "$([[ -s "${TCPFIT_STATE_DIR}/pre-tune.snapshot" ]] && echo 已保存 || echo 未保存)"
  [[ -e "$TCPFIT_INSTALL_PATH" ]] || {
    info "工具尚未安装；开始动态调优时可自动安装审核版"
    return 0
  }
  tcpfit_require_tool || return 1
  echo
  command_with_timeout 20 "$TCPFIT_INSTALL_PATH" status || {
    warn "读取 tcpfit 详细状态失败或超时"
    return 1
  }
}

tcpfit_shape_off() {
  tcpfit_require_tool || return 1
  if [[ ! -s "$TCPFIT_QDISC_SERVICE" ]]; then
    info "当前没有 tcpfit 出口整形，无需移除"
    return 0
  fi
  warn "只移除 HTB 出口整形；动态 sysctl 与 BBR/FQ 基础调优会保留"
  confirm_word "OFF" "确认移除整形请输入 OFF > " || { info "已取消"; return 0; }
  command_with_timeout 60 "$TCPFIT_INSTALL_PATH" shape --off || {
    warn "移除出口整形失败，请查看 tcpfit 状态"
    return 1
  }
  [[ ! -s "$TCPFIT_QDISC_SERVICE" ]] || {
    warn "整形服务文件仍存在，请人工检查"
    return 1
  }
  ok "tcpfit 出口整形已移除，动态基础调优仍保留"
}

tcpfit_rollback_all() {
  tcpfit_require_tool || return 1
  if ! tcpfit_tuning_active; then
    info "当前没有正在生效的 tcpfit 动态调优"
    return 0
  fi
  if [[ ! -s "${TCPFIT_STATE_DIR}/pre-tune.snapshot" ]]; then
    warn "找不到调优前快照，为避免错误恢复已取消"
    return 1
  fi
  warn "将按 tcpfit 首次快照逐项恢复 sysctl，并移除其 qdisc、服务和持久配置"
  info "不会删除 Swap；Swap 仍由 DMITBox 单独管理"
  confirm_word "ROLLBACK" "确认完整回滚请输入 ROLLBACK > " || { info "已取消"; return 0; }
  command_with_timeout 180 "$TCPFIT_INSTALL_PATH" rollback || {
    warn "动态调优回滚失败，请查看状态后重试"
    return 1
  }
  if tcpfit_tuning_active; then
    warn "仍检测到动态调优配置，请人工检查 ${TCPFIT_SYSCTL_FILE}"
    return 1
  fi
  ok "动态 TCP 调优已按原始快照完整回滚"
}

tcpfit_menu() {
  while true; do
    menu_header "动态实测调优" "tcpfit · BDP 推导 · 限速器拐点 · 快照回滚"
    menu_section "当前状态"
    print_kv "动态调优" "$(tcpfit_status_summary)"
    menu_section "安装与调优"
    menu_item "1" "安装或修复工具" "正式发布版、固定版本与 SHA-256 校验"
    menu_item "2" "打开动态调优" "实测 BDP、带宽、限速器拐点与效果验证"
    menu_item "3" "查看动态状态" "当前参数、出口整形、快照与系统状态"
    menu_section "恢复"
    menu_item "4" "仅移除出口整形" "保留动态 BDP 缓冲与 BBR/FQ"
    menu_item "5" "完整回滚动态调优" "严格按首次快照恢复，不猜系统默认值"
    menu_back_item

    local c=""
    read_tty c "请输入编号 > " ""
    case "$c" in
      1) tcpfit_install_reviewed || true; pause_up ;;
      2) tcpfit_run_interactive || true; pause_up ;;
      3) tcpfit_show_status || true; pause_up ;;
      4) tcpfit_shape_off || true; pause_up ;;
      5) tcpfit_rollback_all || true; pause_up ;;
      0|q|Q) return 0 ;;
      *) warn "无效选项"; pause_up ;;
    esac
  done
}

# ---------------- DNS 切换/恢复 ----------------
dns_backup_once() {
  ensure_dir "$BACKUP_BASE"
  if [[ -e /etc/resolv.conf ]] && [[ ! -e "$RESOLV_BACKUP" ]]; then
    cp -a /etc/resolv.conf "$RESOLV_BACKUP" 2>/dev/null || true
    ok "已备份 resolv.conf.orig"
  fi
}

dns_apply_resolved() {
  local ifc="$1"; shift
  local dns_list=("$@")
  resolvectl dns "$ifc" "${dns_list[@]}" >/dev/null 2>&1 || true
  resolvectl flush-caches >/dev/null 2>&1 || true
}

dns_apply_resolvconf() {
  local dns_list=("$@")
  dns_backup_once
  {
    echo "# managed by ${SCRIPT_NAME}"
    for d in "${dns_list[@]}"; do echo "nameserver $d"; done
    echo "options timeout:2 attempts:2"
  } > /etc/resolv.conf
}

dns_set() {
  local which="$1"; local ifc="$2"
  local dns1 dns2
  case "$which" in
    cloudflare) dns1="1.1.1.1"; dns2="1.0.0.1" ;;
    google) dns1="8.8.8.8"; dns2="8.8.4.4" ;;
    quad9) dns1="9.9.9.9"; dns2="149.112.112.112" ;;
    *) warn "未知 DNS 方案"; return 1 ;;
  esac

  info "DNS：切换到 ${which}"
  if is_resolved_active && have_cmd resolvectl; then
    dns_apply_resolved "$ifc" "$dns1" "$dns2"
    ok "已通过 systemd-resolved 应用（$ifc）"
  else
    dns_apply_resolvconf "$dns1" "$dns2"
    ok "已写入 /etc/resolv.conf"
  fi

  if dns_resolve_ok; then ok "DNS 解析：正常"; else warn "DNS 解析：仍异常（可试另一组 DNS）"; fi
}

dns_switch_menu() {
  local ifc; ifc="$(default_iface)"
  while true; do
    menu_header "DNS 服务器" "当前网卡：${ifc} · 选择要应用的公共 DNS"
    menu_section "公共 DNS"
    menu_item "1" "Cloudflare" "1.1.1.1 / 1.0.0.1"
    menu_item "2" "Google" "8.8.8.8 / 8.8.4.4"
    menu_item "3" "Quad9" "9.9.9.9 / 149.112.112.112"
    menu_back_item
    local c=""
    read_tty c "请输入编号 > " ""
    case "$c" in
      1) dns_set "cloudflare" "$ifc"; pause_up ;;
      2) dns_set "google" "$ifc"; pause_up ;;
      3) dns_set "quad9" "$ifc"; pause_up ;;
      0|q|Q) return 0 ;;
      *) warn "无效选项"; pause_up ;;
    esac
  done
}

dns_restore() {
  local ifc; ifc="$(default_iface)"
  info "DNS：恢复到脚本运行前的状态"
  if is_resolved_active && have_cmd resolvectl; then
    resolvectl revert "$ifc" >/dev/null 2>&1 || true
    resolvectl flush-caches >/dev/null 2>&1 || true
    ok "已对 $ifc 执行 resolvectl revert"
  fi

  if [[ -e "$RESOLV_BACKUP" ]]; then
    cp -a "$RESOLV_BACKUP" /etc/resolv.conf 2>/dev/null 2>&1 || true
    ok "已恢复 /etc/resolv.conf（来自备份）"
  else
    warn "未找到备份：$RESOLV_BACKUP"
  fi

  if dns_resolve_ok; then ok "DNS 解析：正常"; else warn "DNS 解析：仍异常（检查上游/防火墙）"; fi
}

# ---------------- MTU 自动探测/设置 ----------------
mtu_current() {
  local ifc; ifc="$(default_iface)"
  ip link show "$ifc" 2>/dev/null | awk '/mtu/{for(i=1;i<=NF;i++) if($i=="mtu"){print $(i+1); exit}}' || true
}

mtu_backup_once() {
  [[ -s "$MTU_ORIG_FILE" ]] && return 0
  local ifc cur
  ifc="$(default_iface)"
  cur="$(mtu_current || true)"
  is_uint_in_range "$cur" 576 65535 || { warn "无法读取当前 MTU，已取消修改"; return 1; }
  ensure_dir "$BACKUP_BASE"
  write_file "$MTU_ORIG_FILE" "IFACE=${ifc}
MTU=${cur}"
  ok "已备份原始 MTU：${ifc}=${cur}"
}

mtu_restore_original() {
  [[ -s "$MTU_ORIG_FILE" ]] || return 1
  local ifc mtu
  ifc="$(sed -n 's/^IFACE=//p' "$MTU_ORIG_FILE" 2>/dev/null | head -n1)"
  mtu="$(sed -n 's/^MTU=//p' "$MTU_ORIG_FILE" 2>/dev/null | head -n1)"
  [[ -n "$ifc" ]] || return 1
  is_uint_in_range "$mtu" 576 65535 || return 1
  ip link show "$ifc" >/dev/null 2>&1 || { warn "原网卡 ${ifc} 不存在，无法恢复 MTU"; return 1; }
  ip link set dev "$ifc" mtu "$mtu" >/dev/null 2>&1 || return 1
  ok "已恢复原始 MTU：${ifc}=${mtu}"
}

ping_payload_ok_v4() {
  local host="$1" payload="$2"
  ping -4 -c 1 -W 1 -M "do" -s "$payload" "$host" >/dev/null 2>&1
}

mtu_probe_v4_value() {
  local host="1.1.1.1"
  if ! ping -4 -c 1 -W 1 "$host" >/dev/null 2>&1; then host="8.8.8.8"; fi
  if ! ping -4 -c 1 -W 1 "$host" >/dev/null 2>&1; then
    echo -e "${c_yellow}⚠ IPv4 ping 不通，无法探测 MTU（先检查网络）${c_reset}" >&2
    return 1
  fi

  echo -e "${c_cyan}➜${c_reset} MTU 探测：对 ${host} 做 DF 探测" >&2
  local lo=1200 hi=1472 mid best=0
  while [[ $lo -le $hi ]]; do
    mid=$(( (lo + hi) / 2 ))
    if ping_payload_ok_v4 "$host" "$mid"; then
      best="$mid"; lo=$((mid + 1))
    else
      hi=$((mid - 1))
    fi
  done

  if [[ "$best" -le 0 ]]; then
    echo -e "${c_yellow}⚠ 未探测到可用值${c_reset}" >&2
    return 1
  fi

  local mtu=$((best + 28))
  echo -e "${c_green}✔${c_reset} 推荐 MTU=${mtu}" >&2
  echo "$mtu"
}

mtu_apply_runtime() {
  local mtu="$1"
  is_uint_in_range "$mtu" 576 65535 || { warn "MTU 必须在 576-65535 之间"; return 1; }
  mtu_backup_once || return 1
  local ifc; ifc="$(default_iface)"
  info "MTU：临时设置（$ifc → $mtu）"
  if ! ip link set dev "$ifc" mtu "$mtu" >/dev/null 2>&1; then
    warn "设置失败：请确认网卡名/权限/MTU 值是否合理"
    return 1
  fi
  ok "已临时生效（当前 MTU=$(mtu_current || echo N/A)）"
}

mtu_enable_persist_systemd() {
  local mtu="$1"
  local ifc; ifc="$(default_iface)"
  if ! is_systemd; then
    warn "无 systemd：无法用 service 持久化"
    return 1
  fi

  write_file "$MTU_VALUE_FILE" "IFACE=${ifc}
MTU=${mtu}
"
  write_file "$MTU_SERVICE" \
"[Unit]
Description=DMIT MTU Apply
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/bin/sh -c '. ${MTU_VALUE_FILE} 2>/dev/null || exit 0; ip link set dev \"\$IFACE\" mtu \"\$MTU\"'
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
"
  systemctl daemon-reload >/dev/null 2>&1 || true
  systemctl enable dmit-mtu.service >/dev/null 2>&1 || true
  systemctl restart dmit-mtu.service >/dev/null 2>&1 || true
  ok "已持久化（systemd）：dmit-mtu.service"
}

mtu_disable_persist() {
  info "MTU：移除持久化设置（恢复由系统接管）"
  if is_systemd; then
    systemctl disable dmit-mtu.service >/dev/null 2>&1 || true
    systemctl stop dmit-mtu.service >/dev/null 2>&1 || true
    rm -f "$MTU_SERVICE" "$MTU_VALUE_FILE" || true
    systemctl daemon-reload >/dev/null 2>&1 || true
    ok "已移除 dmit-mtu.service"
  else
    warn "无 systemd：无需移除 service"
  fi
  warn "运行时 MTU 不会自动回到 1500，如需可执行：ip link set dev $(default_iface) mtu 1500"
}

mtu_menu() {
  while true; do
    local cur; cur="$(mtu_current || echo "")"
    menu_header "MTU 管理" "网卡：$(default_iface) · 当前 MTU：${cur:-N/A}"
    menu_section "检测与设置"
    menu_item "1" "自动探测" "仅显示推荐值，不修改配置"
    menu_item "2" "手动设置" "临时生效，重启后失效"
    menu_item "3" "探测并应用" "临时生效，重启后失效"
    menu_item "4" "探测并持久化" "当前生效并设置开机自动应用"
    menu_section "恢复"
    menu_item "5" "移除持久化" "取消 dmit-mtu.service"
    menu_back_item
    local c=""
    read_tty c "请输入编号 > " ""

    case "$c" in
      1)
        local mtu=""
        mtu="$(mtu_probe_v4_value || true)"
        if [[ -n "${mtu:-}" ]]; then
          ok "推荐 MTU：$mtu"
        fi
        pause_up
        ;;
      2)
        local mtu=""
        read_tty mtu "输入 MTU（如 1500/1480/1460/1450）> " ""
        [[ "$mtu" =~ ^[0-9]+$ ]] || { warn "输入无效"; pause_up; continue; }
        mtu_apply_runtime "$mtu" || true
        pause_up
        ;;
      3)
        local mtu=""
        mtu="$(mtu_probe_v4_value || true)"
        if [[ -n "${mtu:-}" ]]; then
          mtu_apply_runtime "$mtu" || true
        else
          warn "探测失败：未设置"
        fi
        pause_up
        ;;
      4)
        local mtu=""
        mtu="$(mtu_probe_v4_value || true)"
        if [[ -n "${mtu:-}" ]]; then
          mtu_apply_runtime "$mtu" || true
          mtu_enable_persist_systemd "$mtu" || true
        else
          warn "探测失败：未设置"
        fi
        pause_up
        ;;
      5) mtu_disable_persist || true; pause_up ;;
      0|q|Q) return 0 ;;
      *) warn "无效选项"; pause_up ;;
    esac
  done
}

# ---------------- 一键网络体检 / 体检+自动修复 ----------------
print_kv() { printf "%-20s %s\n" "$1" "$2"; }

health_check_core() {
  local ifc; ifc="$(default_iface)"
  local ipv6_sysctl; ipv6_sysctl="$(ipv6_status)"
  local v6_addr="NO" v6_route="NO" v4_net="NO" v6_net="NO" dns_ok="NO"

  has_ipv6_global_addr && v6_addr="YES"
  has_ipv6_default_route && v6_route="YES"
  curl4_ok && v4_net="YES"
  curl6_ok && v6_net="YES"
  dns_resolve_ok && dns_ok="YES"

  echo -e "${c_bold}${c_white}网络体检${c_reset}  ${c_dim}(接口: $ifc)${c_reset}"
  echo -e "${c_green}${AD_TEXT}${c_reset}"
  echo -e "${c_dim}----------------------------------------------${c_reset}"

  print_kv "IPv4 出网"       "$( [[ "$v4_net" == "YES" ]] && echo -e "${c_green}正常${c_reset}" || echo -e "${c_yellow}异常${c_reset}" )"
  print_kv "DNS 解析"        "$( [[ "$dns_ok" == "YES" ]] && echo -e "${c_green}正常${c_reset}" || echo -e "${c_yellow}异常${c_reset}" )"
  print_kv "IPv6 sysctl 开关" "$ipv6_sysctl"
  print_kv "IPv6 公网地址"   "$( [[ "$v6_addr" == "YES" ]] && echo -e "${c_green}有${c_reset}" || echo -e "${c_yellow}无${c_reset}" )"
  print_kv "IPv6 默认路由"   "$( [[ "$v6_route" == "YES" ]] && echo -e "${c_green}有${c_reset}" || echo -e "${c_yellow}无${c_reset}" )"
  print_kv "IPv6 出网"       "$( [[ "$v6_net" == "YES" ]] && echo -e "${c_green}正常${c_reset}" || echo -e "${c_yellow}异常${c_reset}" )"
  print_kv "当前 MTU"        "$(mtu_current || echo N/A)"
  echo -e "${c_dim}----------------------------------------------${c_reset}"

  if [[ "$dns_ok" != "YES" && "$v4_net" == "YES" ]]; then
    warn "像 DNS 问题：试试【DNS 切换】"
  fi
  if [[ "$v6_addr" == "NO" || "$v6_route" == "NO" ]]; then
    warn "IPv6 缺地址/路由：试试【体检+自动修复】或【开启 IPv6】"
  fi
}

health_check_only() {
  health_check_core
  ok "体检完成（未改动任何配置）"
}

health_check_autofix() {
  local fixed=0
  health_check_core
  echo
  info "自动修复：尝试重拉 IPv6 / 刷新 DNS（不做高风险改动）"

  if ! has_ipv6_global_addr || ! has_ipv6_default_route; then
    info "IPv6 不完整：执行【开启 IPv6（重拉地址/路由）】"
    ipv6_enable || true
    fixed=1
  fi

  if is_resolved_active && have_cmd resolvectl; then
    info "刷新 systemd-resolved DNS 缓存"
    resolvectl flush-caches >/dev/null 2>&1 || true
    fixed=1
  fi

  echo
  health_check_core
  if [[ "$fixed" -eq 1 ]]; then
    ok "已执行自动修复动作"
  else
    ok "无需修复"
  fi
}

# ---------------- IPv6 /64 地址池 + 随机出网 ----------------
ipv6_prefix64_normalize() {
  local raw="${1%%/*}" left="" right="" missing=0 part=""
  local -a full=() left_parts=() right_parts=()

  raw="${raw%%%*}"
  [[ -n "$raw" && "$raw" != *.* ]] || return 1

  if [[ "$raw" == *::* ]]; then
    [[ "${raw#*::}" != *::* ]] || return 1
    left="${raw%%::*}"
    right="${raw#*::}"
    [[ -z "$left" ]] || IFS=':' read -r -a left_parts <<< "$left"
    [[ -z "$right" ]] || IFS=':' read -r -a right_parts <<< "$right"
    missing=$((8 - ${#left_parts[@]} - ${#right_parts[@]}))
    (( missing >= 1 )) || return 1
    full=("${left_parts[@]}")
    while (( missing > 0 )); do
      full+=("0")
      missing=$((missing - 1))
    done
    full+=("${right_parts[@]}")
  else
    IFS=':' read -r -a full <<< "$raw"
    (( ${#full[@]} == 8 )) || return 1
  fi

  (( ${#full[@]} == 8 )) || return 1
  for part in "${full[@]}"; do
    [[ "$part" =~ ^[0-9A-Fa-f]{1,4}$ ]] || return 1
  done

  printf '%x:%x:%x:%x\n' \
    "$((16#${full[0]}))" "$((16#${full[1]}))" \
    "$((16#${full[2]}))" "$((16#${full[3]}))"
}

ipv6_prefix64_guess() {
  local ifc="${1:-$(default_iface)}"
  local a=""
  a="$(ip -6 addr show dev "$ifc" scope global 2>/dev/null | awk '/inet6/{print $2}' | grep -E '/64$' | head -n1 || true)"
  if [[ -n "$a" ]]; then
    ipv6_prefix64_normalize "$a" && return 0
  fi
  a="$(ip -6 route show 2>/dev/null | awk -v i="$ifc" '$1 ~ /\/64$/ && $0 ~ ("dev " i) {print $1; exit}' || true)"
  if [[ -n "$a" ]]; then
    ipv6_prefix64_normalize "$a" && return 0
  fi
  return 1
}

ipv6_list_global_128() {
  local ifc="${1:-$(default_iface)}"
  ip -6 addr show dev "$ifc" scope global 2>/dev/null \
    | awk '/inet6/{print $2}' \
    | grep -E '/128$' \
    | sed 's#/128##g'
}

ipv6_addr_exists() {
  local ifc="${1:-$(default_iface)}" addr="$2"
  ip -6 addr show dev "$ifc" 2>/dev/null | grep -q "inet6 ${addr}/128"
}

ipv6_rand_host_64() {
  if have_cmd hexdump; then
    hexdump -n8 -e '4/2 "%04x " 1' /dev/urandom 2>/dev/null | awk '{print $1 ":" $2 ":" $3 ":" $4}'
    return 0
  fi
  printf "%04x:%04x:%04x:%04x" $((RANDOM%65536)) $((RANDOM%65536)) $((RANDOM%65536)) $((RANDOM%65536))
}

ipv6_add_128() {
  local addr="$1" ifc="${2:-$(default_iface)}"
  local valid="${3:-forever}" pref="${4:-forever}"
  if [[ "$valid" == "forever" ]]; then
    ip -6 addr add "${addr}/128" dev "$ifc" >/dev/null 2>&1 || return 1
  else
    ip -6 addr add "${addr}/128" dev "$ifc" valid_lft "$valid" preferred_lft "$pref" >/dev/null 2>&1 || return 1
  fi
  ok "已添加：${addr}/128  (dev ${ifc})"
  return 0
}

ipv6_del_128() {
  local addr="$1" ifc="${2:-$(default_iface)}"
  ip -6 addr del "${addr}/128" dev "$ifc" >/dev/null 2>&1 || true
  ok "已删除：${addr}/128"
}

ipv6_gen_n_128() {
  local n="$1" mode="${2:-persist}"
  is_uint_in_range "$n" 1 256 || { warn "数量必须在 1-256 之间"; return 1; }
  local ifc; ifc="$(default_iface)"
  local p64; p64="$(ipv6_prefix64_guess "$ifc" || true)"
  [[ -n "${p64:-}" ]] || { warn "未识别到 /64 前缀（请确认有 /64 地址或 ::/64 路由）"; return 1; }

  local valid="forever" pref="forever"
  if [[ "$mode" == "temp" ]]; then
    valid="3600"
    pref="1200"
  fi

  local made=0 tries=0
  while [[ "$made" -lt "$n" && "$tries" -lt $((n*50)) ]]; do
    tries=$((tries+1))
    local host; host="$(ipv6_rand_host_64)"
    local addr="${p64}:${host}"
    if ipv6_addr_exists "$ifc" "$addr"; then
      continue
    fi
    if ipv6_add_128 "$addr" "$ifc" "$valid" "$pref"; then
      made=$((made+1))
    fi
  done

  if [[ "$made" -lt "$n" ]]; then
    warn "只生成了 ${made}/${n} 个（可能系统限制或重复过多）"
    return 1
  fi
  ok "完成：生成 ${made} 个 /128（${mode}）"
}

ipv6_pool_write_conf() {
  local ifc="$1" prefix64="$2" n="$3"; shift 3
  local addrs=("$@")
  {
    echo "IFACE=${ifc}"
    echo "PREFIX64=${prefix64}"
    echo "N=${n}"
    local i
    for ((i=0;i<n;i++)); do
      echo "ADDR_${i}=${addrs[$i]}"
    done
  } > "$IPV6_POOL_CONF"
}

ipv6_pool_load_conf() {
  [[ -f "$IPV6_POOL_CONF" ]] || return 1
  # shellcheck disable=SC1090
  . "$IPV6_POOL_CONF"
  [[ -n "${IFACE:-}" && -n "${PREFIX64:-}" && -n "${N:-}" ]] || return 1
  return 0
}

ipv6_pool_apply_from_conf() {
  ipv6_pool_load_conf || return 1
  local i
  for ((i=0;i<N;i++)); do
    local v="ADDR_${i}"
    local addr="${!v:-}"
    [[ -n "$addr" ]] || continue
    if ! ipv6_addr_exists "$IFACE" "$addr"; then
      ip -6 addr add "${addr}/128" dev "$IFACE" >/dev/null 2>&1 || true
    fi
  done
  ok "已应用地址池（确保 /128 都挂在 ${IFACE}）"
}

ipv6_pool_persist_enable() {
  if ! is_systemd; then
    warn "无 systemd：已仅运行时生效；如需开机自启，请自行写入网络启动脚本"
    return 0
  fi
  write_file "$IPV6_POOL_SERVICE" \
"[Unit]
Description=DMIT IPv6 Pool Apply
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/bin/sh -c '. ${IPV6_POOL_CONF} 2>/dev/null || exit 0; for i in \$(seq 0 \$((N-1))); do eval a=\\\"\\\${ADDR_\$i}\\\"; [ -n \"\$a\" ] || continue; ip -6 addr add \"\$a/128\" dev \"\$IFACE\" >/dev/null 2>&1 || true; done'
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
"
  systemctl daemon-reload >/dev/null 2>&1 || true
  systemctl enable dmit-ipv6-pool.service >/dev/null 2>&1 || true
  systemctl restart dmit-ipv6-pool.service >/dev/null 2>&1 || true
  ok "已持久化：dmit-ipv6-pool.service"
}

ipv6_pool_disable() {
  if ipv6_pool_load_conf; then
    local i
    for ((i=0;i<N;i++)); do
      local v="ADDR_${i}"
      local addr="${!v:-}"
      [[ -n "$addr" ]] || continue
      ip -6 addr del "${addr}/128" dev "$IFACE" >/dev/null 2>&1 || true
    done
  fi

  rm -f "$IPV6_POOL_CONF" >/dev/null 2>&1 || true

  if is_systemd; then
    systemctl disable dmit-ipv6-pool.service >/dev/null 2>&1 || true
    systemctl stop dmit-ipv6-pool.service >/dev/null 2>&1 || true
    rm -f "$IPV6_POOL_SERVICE" >/dev/null 2>&1 || true
    systemctl daemon-reload >/dev/null 2>&1 || true
    # systemd 会保留已删除单元的失败状态；同步清理，避免健康检查显示
    # "not-found failed"。这里只处理本脚本管理的单元，不影响其他服务。
    systemctl reset-failed dmit-ipv6-pool.service >/dev/null 2>&1 || true
  fi
  ok "已关闭 IPv6 地址池（并清理持久化）"
}

ipv6_pool_status() {
  echo -e "${c_bold}${c_white}IPv6 地址池状态${c_reset}"
  local ifc; ifc="$(default_iface)"
  local p64; p64="$(ipv6_prefix64_guess "$ifc" || true)"
  echo -e "${c_dim}IFACE:${c_reset} ${ifc}"
  echo -e "${c_dim}PREFIX64:${c_reset} ${p64:-unknown}"
  echo
  echo -e "${c_dim}当前网卡 /64 与 /128：${c_reset}"
  ip -6 addr show dev "$ifc" scope global 2>/dev/null | sed -n '1,200p' || true
  echo
  echo -e "${c_dim}当前 /128 列表：${c_reset}"
  ipv6_list_global_128 "$ifc" || true
  echo
  if [[ -f "$IPV6_POOL_CONF" ]]; then
    echo -e "${c_dim}池配置：${c_reset} ${IPV6_POOL_CONF}"
    sed -n '1,120p' "$IPV6_POOL_CONF" 2>/dev/null || true
  else
    echo -e "${c_dim}池配置：${c_reset} (未启用)"
  fi
}

# ---------- 随机出网（每个新连接随机 /128） ----------
ipv6_rand_write_conf() {
  local ifc="$1" prefix64="$2" n="$3"
  shift 3
  local addrs=("$@")

  mkdir -p "$(dirname "$IPV6_RAND_CONF")" "$(dirname "$IPV6_RAND_NFT")" >/dev/null 2>&1 || true
  {
    echo "IFACE=${ifc}"
    echo "PREFIX64=${prefix64}::/64"
    echo "N=${n}"
    local i
    for ((i=0;i<n;i++)); do
      echo "ADDR_${i}=${addrs[$i]}"
    done
  } > "$IPV6_RAND_CONF"
}

ipv6_rand_load_conf() {
  [[ -f "$IPV6_RAND_CONF" ]] || return 1
  # shellcheck disable=SC1090
  . "$IPV6_RAND_CONF"
  [[ -n "${IFACE:-}" && -n "${PREFIX64:-}" && -n "${N:-}" ]] || return 1
  return 0
}

ipv6_rand_render_nft() {
  {
    echo "table inet dmitbox_rand6 {"
    echo "  chain outmark {"
    echo "    type route hook output priority mangle; policy accept;"
    echo "    ct state new oifname \"${IFACE}\" ip6 daddr != ${PREFIX64} ip6 daddr != fe80::/10 ip6 daddr != ff00::/8 ct mark set numgen random mod ${N};"
    echo "  }"
    echo "  chain post {"
    echo "    type nat hook postrouting priority srcnat; policy accept;"
    local i
    for ((i=0;i<N;i++)); do
      local addr_var="ADDR_${i}"
      local addr_val="${!addr_var:-}"
      echo "    oifname \"${IFACE}\" ct mark ${i} ip6 daddr != ${PREFIX64} ip6 daddr != fe80::/10 ip6 daddr != ff00::/8 snat to ${addr_val};"
    done
    echo "  }"
    echo "}"
  }
}

ipv6_rand_apply_nft_runtime() {
  pkg_install nftables >/dev/null 2>&1 || true
  have_cmd nft || { warn "未找到 nft 命令，无法启用随机出网 IPv6"; return 1; }

  mkdir -p "$(dirname "$IPV6_RAND_NFT")" >/dev/null 2>&1 || true
  ipv6_rand_render_nft > "$IPV6_RAND_NFT"

  if ! nft -c -f "$IPV6_RAND_NFT" >/dev/null 2>&1; then
    warn "nft 规则语法校验失败：$IPV6_RAND_NFT"
    echo
    nl -ba "$IPV6_RAND_NFT" | sed -n '1,200p'
    echo
    warn "你也可以手动跑：nft -c -f $IPV6_RAND_NFT"
    return 1
  fi

  nft delete table inet dmitbox_rand6 >/dev/null 2>&1 || true
  if ! nft -f "$IPV6_RAND_NFT" >/dev/null 2>&1; then
    warn "nft 规则加载失败：$IPV6_RAND_NFT"
    return 1
  fi

  ok "已启用（runtime）：每个新连接随机选择出网 IPv6（N=${N}）"
  return 0
}

ipv6_rand_persist_systemd() {
  is_systemd || { warn "无 systemd：已仅 runtime 生效（重启会丢）"; return 0; }

  write_file "$IPV6_RAND_SERVICE" \
"[Unit]
Description=DMIT IPv6 Random Outbound (per-connection)
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/bin/sh -c 'nft delete table inet dmitbox_rand6 >/dev/null 2>&1 || true; nft -f ${IPV6_RAND_NFT} >/dev/null 2>&1 || true'
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
"
  systemctl daemon-reload >/dev/null 2>&1 || true
  systemctl enable dmit-ipv6-rand.service >/dev/null 2>&1 || true
  systemctl restart dmit-ipv6-rand.service >/dev/null 2>&1 || true
  ok "已持久化（systemd）：dmit-ipv6-rand.service"
}

ipv6_rand_enable_from_pool() {
  local want_n="$1"
  is_uint_in_range "$want_n" 2 256 || { warn "随机池大小必须在 2-256 之间"; return 1; }
  local ifc; ifc="$(default_iface)"
  local p64; p64="$(ipv6_prefix64_guess "$ifc" || true)"
  [[ -n "${p64:-}" ]] || { warn "未识别到 /64 前缀（prefix64）"; return 1; }

  local addrs=()
  while IFS= read -r ip; do
    [[ -n "$ip" ]] && addrs+=("$ip")
  done < <(ipv6_list_global_128 "$ifc")

  if [[ "${#addrs[@]}" -lt "$want_n" ]]; then
    warn "当前 /128 数量不足：需要 ${want_n} 个，但只有 ${#addrs[@]} 个"
    warn "请先在 IPv6 地址池里新增一些 /128，再启用随机出网"
    return 1
  fi

  local chosen=("${addrs[@]:0:$want_n}")
  ipv6_rand_write_conf "$ifc" "$p64" "$want_n" "${chosen[@]}"
  ipv6_rand_load_conf || { warn "写入配置失败"; return 1; }
  ipv6_rand_apply_nft_runtime || return 1
  ipv6_rand_persist_systemd || true

  echo -e "${c_dim}已使用以下出网 IPv6 池：${c_reset}"
  printf "%s\n" "${chosen[@]}"
  return 0
}

ipv6_rand_disable() {
  if have_cmd nft; then
    nft delete table inet dmitbox_rand6 >/dev/null 2>&1 || true
  fi

  rm -f "$IPV6_RAND_NFT" >/dev/null 2>&1 || true
  rm -f "$IPV6_RAND_CONF" >/dev/null 2>&1 || true

  if is_systemd; then
    systemctl disable dmit-ipv6-rand.service >/dev/null 2>&1 || true
    systemctl stop dmit-ipv6-rand.service >/dev/null 2>&1 || true
    rm -f "$IPV6_RAND_SERVICE" >/dev/null 2>&1 || true
    systemctl daemon-reload >/dev/null 2>&1 || true
  fi

  ok "已关闭随机出网 IPv6（并清理持久化）"
}

ipv6_rand_selftest() {
  local n="${1:-10}"
  (( n >= 2 )) || n=10

  pkg_install curl >/dev/null 2>&1 || true
  have_cmd curl || { warn "未安装 curl，无法自检"; return 1; }

  if ! curl6_ok; then
    warn "IPv6 出网异常（curl -6 失败），先修复 IPv6 再自检"
    return 1
  fi

  local url="ip.sb"
  local tmp="/tmp/dmitbox_rand6_test.$$.txt"
  : > "$tmp"

  info "自检：连续 ${n} 次 curl -6 ${url}（观察源 IPv6 是否变化）"
  local i
  for ((i=1;i<=n;i++)); do
    local ip
    ip="$(curl -6 -sS --max-time 6 "$url" 2>/dev/null | tr -d '\r' | head -n1 || true)"
    echo "$ip" >> "$tmp"
    printf "%2d) %s\n" "$i" "${ip:-FAIL}"
    sleep 0.3
  done

  echo
  local total uniq
  total="$(grep -cve '^$' "$tmp" || true)"
  uniq="$(grep -v '^$' "$tmp" | sort -u | wc -l | tr -d ' ')"

  echo -e "${c_bold}结果：${c_reset} 共 ${total} 次，出现 ${uniq} 个不同的源 IPv6"
  echo -e "${c_dim}去重列表：${c_reset}"
  grep -v '^$' "$tmp" | sort -u | sed -n '1,120p'

  if [[ "$uniq" -ge 2 ]]; then
    ok "随机出网看起来在变化 ✅"
  else
    warn "看起来没有变化：可能未启用随机出网 / 连接复用 / 目标站缓存（建议多测几次或换目标站）"
    echo -e "${c_dim}可替换目标：curl -6 -s https://ifconfig.co${c_reset}"
  fi

  rm -f "$tmp" >/dev/null 2>&1 || true
  return 0
}

ipv6_rand_status() {
  echo -e "${c_bold}${c_white}随机出网 IPv6 状态${c_reset}"
  if [[ -f "$IPV6_RAND_CONF" ]]; then
    echo -e "${c_dim}配置：${c_reset}${IPV6_RAND_CONF}"
    sed -n '1,120p' "$IPV6_RAND_CONF" 2>/dev/null || true
  else
    echo -e "${c_dim}未启用（配置文件不存在）${c_reset}"
  fi
  echo
  echo -e "${c_dim}nft 规则：${c_reset}"
  if have_cmd nft; then
    nft list table inet dmitbox_rand6 2>/dev/null || echo "(无)"
    echo
    echo -e "${c_dim}语法校验（nft -c）：${c_reset}"
    nft -c -f "$IPV6_RAND_NFT" >/dev/null 2>&1 && echo "OK" || echo "FAIL (查看：nl -ba $IPV6_RAND_NFT | sed -n '1,120p')"
  else
    echo "(未安装 nft)"
  fi
  echo
  echo -e "${c_dim}快速验证（多次 curl 观察 src 是否变化）：${c_reset}"
  echo "  for i in {1..6}; do curl -6 -s ip.sb; echo; done"
}

ipv6_pool_generate_and_enable_rand() {
  local n="$1"
  is_uint_in_range "$n" 2 256 || { warn "数量必须在 2-256 之间"; return 1; }
  local ifc; ifc="$(default_iface)"
  local p64; p64="$(ipv6_prefix64_guess "$ifc" || true)"
  [[ -n "${p64:-}" ]] || { warn "未识别到 /64 前缀"; return 1; }

  info "一键：生成 ${n} 个 /128（持久）并启用随机出网"
  local made=0 tries=0
  local addrs=()
  while [[ "$made" -lt "$n" && "$tries" -lt $((n*60)) ]]; do
    tries=$((tries+1))
    local host; host="$(ipv6_rand_host_64)"
    local addr="${p64}:${host}"
    if ipv6_addr_exists "$ifc" "$addr"; then
      continue
    fi
    if ipv6_add_128 "$addr" "$ifc" "forever" "forever"; then
      addrs+=("$addr")
      made=$((made+1))
    fi
  done

  if [[ "$made" -lt "$n" ]]; then
    warn "只生成了 ${made}/${n} 个"
    return 1
  fi

  ipv6_pool_write_conf "$ifc" "$p64" "$n" "${addrs[@]}"
  ipv6_pool_persist_enable || true

  ipv6_rand_write_conf "$ifc" "$p64" "$n" "${addrs[@]}"
  if ! ipv6_rand_load_conf || ! ipv6_rand_apply_nft_runtime; then
    warn "IPv6 地址池已生成，但随机出网启用失败；请查看菜单中的随机出网状态"
    return 1
  fi
  ipv6_rand_persist_systemd || true

  ok "完成：已生成 /128 池并启用随机出网"
}

ipv6_tools_menu() {
  local ifc; ifc="$(default_iface)"
  while true; do
    menu_header "IPv6 /64 地址池" "网卡：${ifc} · /128 地址与随机出网管理"
    menu_section "地址池"
    menu_item "1" "查看地址池状态" "/64 前缀、/128 地址与持久化配置"
    menu_item "2" "新增长期 /128" "运行时长期有效，重启后失效"
    menu_item "3" "新增临时 /128" "1 小时有效"
    menu_item "4" "删除一个 /128" "手动输入地址"
    menu_item "5" "关闭并清理地址池" "删除池内 /128 并取消持久化"
    menu_section "随机出网"
    menu_item "6" "从现有地址启用" "选择前 N 个 /128"
    menu_item "7" "一键生成并启用" "推荐：生成 N 个 /128 后立即启用"
    menu_item "8" "查看运行状态" "配置、nft 规则与语法检查"
    menu_item "9" "运行自检" "连续请求并检查源 IPv6 是否变化"
    menu_item "10" "关闭随机出网" "清理 nft 规则与持久化服务"
    menu_back_item
    local c=""
    read_tty c "请输入编号 > " ""

    case "$c" in
      1) ipv6_pool_status; pause_up ;;
      2)
        local n=""
        read_tty n "生成多少个 /128（默认 3）> " "3"
        is_uint_in_range "$n" 1 256 || { warn "数量必须在 1-256 之间"; pause_up; continue; }
        ipv6_gen_n_128 "$n" "persist" || true
        pause_up
        ;;
      3)
        local n=""
        read_tty n "生成多少个 /128（默认 1）> " "1"
        is_uint_in_range "$n" 1 256 || { warn "数量必须在 1-256 之间"; pause_up; continue; }
        ipv6_gen_n_128 "$n" "temp" || true
        pause_up
        ;;
      4)
        local a=""
        read_tty a "输入要删除的 /128（如 2605:...:....）> " ""
        [[ -n "$a" ]] || { warn "不能为空"; pause_up; continue; }
        ipv6_del_128 "$a" "$ifc" || true
        pause_up
        ;;
      5) ipv6_pool_disable || true; pause_up ;;
      6)
        local n=""
        read_tty n "随机池大小 N（建议 3~10，默认 5）> " "5"
        is_uint_in_range "$n" 2 256 || { warn "N 必须在 2-256 之间"; pause_up; continue; }
        ipv6_rand_enable_from_pool "$n" || true
        pause_up
        ;;
      7)
        local n=""
        read_tty n "生成并随机出网：N（建议 3~10，默认 5）> " "5"
        is_uint_in_range "$n" 2 256 || { warn "N 必须在 2-256 之间"; pause_up; continue; }
        ipv6_pool_generate_and_enable_rand "$n" || true
        pause_up
        ;;
      8) ipv6_rand_status; pause_up ;;
      9)
        local n=""
        read_tty n "自检次数（默认 10）> " "10"
        is_uint_in_range "$n" 2 100 || n="10"
        ipv6_rand_selftest "$n" || true
        pause_up
        ;;
      10) ipv6_rand_disable || true; pause_up ;;
      0|q|Q) return 0 ;;
      *) warn "无效选项"; pause_up ;;
    esac
  done
}


# ======================================================================
# Cloud-init / QEMU Guest Agent（换 IP 防失联）
# ======================================================================

# --- cloud-init safety helpers ---
cloudinit_qga_detect_static_network() {
  # Return 0 if static networking is detected (higher risk cloud-init overrides),
  # Return 1 otherwise.
  # ifupdown
  if [[ -f /etc/network/interfaces ]]; then
    grep -Eqi '^[[:space:]]*iface[[:space:]].+[[:space:]]static' /etc/network/interfaces && return 0
    grep -Eqi '^[[:space:]]*address[[:space:]]+' /etc/network/interfaces && return 0
  fi
  if compgen -G "/etc/network/interfaces.d/*" >/dev/null 2>&1; then
    grep -RIn --line-number -E '^[[:space:]]*iface[[:space:]].+[[:space:]]static|^[[:space:]]*address[[:space:]]+' /etc/network/interfaces.d 2>/dev/null | head -n 1 >/dev/null 2>&1 && return 0
  fi

  # netplan
  if [[ -d /etc/netplan ]]; then
    grep -RIn --line-number -E '^[[:space:]]*addresses:|dhcp4:[[:space:]]*false|dhcp6:[[:space:]]*false' /etc/netplan 2>/dev/null | head -n 1 >/dev/null 2>&1 && return 0
  fi

  # NetworkManager
  if have_cmd nmcli; then
    nmcli -t -f NAME,IP4.METHOD con show --active 2>/dev/null | grep -q ':manual$' && return 0
  fi

  return 1
}

cloudinit_qga_has_instance_state() {
  [[ -d /var/lib/cloud/instance ]] && [[ -n "$(ls -A /var/lib/cloud/instance 2>/dev/null || true)" ]]
}

cloudinit_qga_safe_disable_network_if_needed() {
  # If we just installed cloud-init on a DD/non-cloud system with static IP,
  # cloud-init may generate DHCP config on next boot and break SSH.
  # To be safe, we default-disable cloud-init network management unless the user explicitly enables it.
  [[ -f "$CLOUDINIT_DISABLE_NET_FILE" ]] && return 0

  if ! have_cmd cloud-init; then return 0; fi
  # Only apply safe-disable when there is no prior cloud-init instance state (fresh install)
  if cloudinit_qga_has_instance_state; then return 0; fi

  if cloudinit_qga_detect_static_network; then
    ensure_dir "/etc/cloud/cloud.cfg.d"
    write_file "$CLOUDINIT_DISABLE_NET_FILE" "network: {config: disabled}"
    ok "已启用安全保护：默认禁止 cloud-init 接管网络（避免重启后 SSH 失联）"
    warn "如果你要使用面板【换 IP】功能：请在本菜单选择【开启 cloud-init 网络接管】后，再执行 cloud-init clean 并重启。"
  fi
}

cloudinit_qga_enable_network_management() {
  # Remove our disable file and also neutralize other 'network: {config: disabled}' lines if any.
  local changed="0"
  ensure_dir "$BACKUP_BASE"
  local bdir=""
  bdir="${BACKUP_BASE}/cloudinit-enable-$(ts_now)"
  ensure_dir "$bdir"

  if [[ -f "$CLOUDINIT_DISABLE_NET_FILE" ]]; then
    cp -a "$CLOUDINIT_DISABLE_NET_FILE" "$bdir/" 2>/dev/null || true
    rm -f "$CLOUDINIT_DISABLE_NET_FILE" 2>/dev/null || true
    changed="1"
  fi

  # Also comment out any other disabling lines (rare but possible)
  if [[ -d /etc/cloud/cloud.cfg.d ]]; then
    local f
    while IFS= read -r f; do
      [[ -f "$f" ]] || continue
      cp -a "$f" "$bdir/" 2>/dev/null || true
      sed -i -E 's/network:[[:space:]]*\{config:[[:space:]]*disabled\}/# dmitbox: network config enabled/g' "$f" 2>/dev/null || true
      changed="1"
    done < <(grep -RIl "network: {config: disabled}" /etc/cloud/cloud.cfg.d 2>/dev/null || true)
  fi
  if [[ -f /etc/cloud/cloud.cfg ]]; then
    if grep -q "network: {config: disabled}" /etc/cloud/cloud.cfg 2>/dev/null; then
      cp -a /etc/cloud/cloud.cfg "$bdir/" 2>/dev/null || true
      sed -i -E 's/network:[[:space:]]*\{config:[[:space:]]*disabled\}/# dmitbox: network config enabled/g' /etc/cloud/cloud.cfg 2>/dev/null || true
      changed="1"
    fi
  fi

  if [[ "$changed" == "1" ]]; then
    ok "已开启 cloud-init 网络接管（备份在：$bdir）"
  else
    ok "未发现 cloud-init 网络禁用项（无需开启）"
  fi
}

cloudinit_qga_find_net_disabled() {
  local hit="0"
  if [[ -d /etc/cloud/cloud.cfg.d ]]; then
    if grep -RIn --line-number "network:[[:space:]]*\{config:[[:space:]]*disabled\}" /etc/cloud/cloud.cfg.d 2>/dev/null | head -n 1 >/dev/null 2>&1; then
      hit="1"
    fi
  fi
  if [[ -f /etc/cloud/cloud.cfg ]]; then
    grep -qE "network:[[:space:]]*\{config:[[:space:]]*disabled\}" /etc/cloud/cloud.cfg 2>/dev/null && hit="1"
  fi
  echo "$hit"
}

cloudinit_qga_status() {
  echo
  echo -e "${c_bold}${c_white}换 IP 防失联：Cloud-init / QEMU Guest Agent 状态${c_reset}"
  sub_banner

  local ci="NO" qga="NO" qgas="N/A" net_dis="NO"
  have_cmd cloud-init && ci="YES"
  (have_cmd qemu-ga || have_cmd qemu-guest-agent) && qga="YES"

  if is_systemd; then
    if systemctl is-active --quiet qemu-guest-agent 2>/dev/null; then qgas="active"; else qgas="inactive"; fi
  else
    qgas="(non-systemd)"
  fi

  [[ "$(cloudinit_qga_find_net_disabled)" == "1" ]] && net_dis="YES"

  print_kv "cloud-init 已安装" "$( [[ "$ci" == "YES" ]] && echo -e "${c_green}是${c_reset}" || echo -e "${c_yellow}否${c_reset}" )"
  print_kv "qemu-guest-agent 已安装" "$( [[ "$qga" == "YES" ]] && echo -e "${c_green}是${c_reset}" || echo -e "${c_yellow}否${c_reset}" )"
  print_kv "qemu-guest-agent 运行" "$qgas"
  print_kv "cloud-init 网络被禁用" "$( [[ "$net_dis" == "YES" ]] && echo -e "${c_yellow}是${c_reset}" || echo -e "${c_green}否${c_reset}" )"

  if [[ -f "$CLOUDINIT_DISABLE_NET_FILE" ]]; then
    print_kv "dmitbox 安全保护(禁用接管)" "$(echo -e "${c_yellow}已启用${c_reset}")"
  fi

  echo
  if [[ "$ci" == "YES" ]]; then
echo -e "${c_dim}cloud-init status（仅供参考）：${c_reset}"
local st=""
st="$(cloud-init status --long 2>/dev/null || true)"
# 输出前几行，避免刷屏
echo "$st" | sed -n '1,10p'
if echo "$st" | grep -q '^status: error'; then
  # 取 detail 的第一行（通常就是失败模块）
  local detail=""
  detail="$(echo "$st" | awk 'BEGIN{p=0} /^detail:/{p=1;next} p{print; exit}')"
  if echo "$detail" | grep -q 'package-update-upgrade-install'; then
    warn "cloud-init 报错来源：package-update-upgrade-install（apt-get update 失败）。这通常不影响网络/换 IP，只影响开机时自动更新软件包。"
    echo -e "${c_dim}可选修复：运行 apt-get update 查看真实原因；若不想每次开机触发，可在本脚本里选择【禁用 cloud-init 自动 apt 更新】。${c_reset}"
  else
    warn "cloud-init 报错详情：${detail:-unknown}"
    echo -e "${c_dim}建议查看：tail -n 80 /var/log/cloud-init.log${c_reset}"
  fi
fi
  else
    warn "cloud-init 未安装：DD 系统后换 IP 很容易失联（建议先安装）"
  fi

  if [[ "$net_dis" == "YES" ]]; then
    warn "检测到 cloud-init 网络被禁用：面板换 IP 后可能不会自动更新网卡配置"
    warn "可在本脚本里执行：【修复 cloud-init 网络禁用】并建议重启"
  fi

  echo
  echo -e "${c_dim}说明：DMIT 面板的【换 IP】通常依赖 cloud-init 重新下发网络配置；缺少 cloud-init/QGA 或网络被禁用，可能导致换 IP 后 SSH 直接失联。${c_reset}"
}

cloudinit_qga_install() {
  info "安装/启用：cloud-init + qemu-guest-agent（换 IP 防失联）"
  warn "若安装过程看起来卡住：请先耐心等待下载/安装；也可以按 Ctrl+C 中断并返回菜单。"

  local interrupted="0"
  trap 'interrupted="1"' INT

  pkg_install cloud-init qemu-guest-agent

  trap - INT
  [[ "$interrupted" == "1" ]] && { warn "已中断安装，返回菜单"; return 0; }

  if ! have_cmd cloud-init; then
    warn "cloud-init 安装失败或软件源中无此包，未继续配置"
    return 1
  fi

  if is_systemd; then
    systemctl enable --now qemu-guest-agent >/dev/null 2>&1 || true
    # cloud-init/cloud-final 多为 oneshot：首次运行可能很久（且我们把输出吞掉了），
    # 会让菜单看起来“卡在完成”。因此改成：启用 + 后台启动（不阻塞菜单）。
    systemctl enable cloud-init cloud-config cloud-final >/dev/null 2>&1 || true
    [[ "${RUN_MODE:-menu}" == "menu" ]] && info "启动 cloud-init（后台，不阻塞菜单）"
    systemctl start --no-block cloud-init cloud-config cloud-final >/dev/null 2>&1 || true
  fi

  if have_cmd qemu-ga || have_cmd qemu-guest-agent; then
    ok "cloud-init 与 QEMU Guest Agent 已安装"
  else
    warn "cloud-init 已安装，但未检测到 QEMU Guest Agent 可执行文件"
  fi
  cloudinit_qga_safe_disable_network_if_needed || true
  cloudinit_qga_status
}

cloudinit_qga_fix_network_disabled() {
  info "开启：cloud-init 网络接管（解除 network: {config: disabled}）"
  cloudinit_qga_enable_network_management
  warn "建议：执行 cloud-init clean 后重启一次，让网络元数据重新生效"
}

cloudinit_clean_and_hint_reboot() {
  if ! have_cmd cloud-init; then
    warn "cloud-init 未安装：无法 clean。可先执行【安装/启用 cloud-init + QGA】"
    return 0
  fi
  info "执行：cloud-init clean（清理旧状态，便于重新应用网络元数据）"
  cloud-init clean --logs >/dev/null 2>&1 || cloud-init clean >/dev/null 2>&1 || true
  ok "已执行 cloud-init clean"
  warn "通常建议重启一次（尤其是刚 DD 或刚换 IP 后）：reboot"
}

cloudinit_disable_pkg_updates() {
  info "禁用：cloud-init 自动 apt 更新/升级（避免 status:error）"
  if [[ ! -d /etc/cloud/cloud.cfg.d ]]; then
    mkdir -p /etc/cloud/cloud.cfg.d
  fi
  cat >"$CLOUDINIT_DISABLE_PKG_FILE" <<'EOF'
# managed by dmitbox
# Disable cloud-init package update/upgrade on boot.
# This avoids 'cloud-init status: error' caused by transient apt-get update failures.
package_update: false
package_upgrade: false
package_reboot_if_required: false
EOF
  ok "已写入 $CLOUDINIT_DISABLE_PKG_FILE"
  warn "提示：这不会影响 cloud-init 下发网络/SSH key；只是不再自动执行 apt-get update/upgrade。"
}


cloudinit_qga_write_dmit_pve_cfg() {
  ensure_dir "/etc/cloud/cloud.cfg.d"
  # Match DMIT default-like behavior observed on original images:
  # - cloud-id: nocloud
  # - datasource_list: [ NoCloud, ConfigDrive, None ]
  # - prefer NoCloud label "cidata"
  write_file "$DMITBOX_PVE_CFG" "datasource_list: [ NoCloud, ConfigDrive, None ]
datasource:
  NoCloud:
    fs_label: cidata
"
  chmod 644 "$DMITBOX_PVE_CFG" >/dev/null 2>&1 || true
}

cloudinit_qga_install_seed_helper_systemd() {
  is_systemd || return 0
  # Helper: mount NoCloud/ConfigDrive seed media (iso/vfat) early, then stage into /var/lib/cloud/seed/nocloud-net
  # shellcheck disable=SC2016
  write_file "$DMITBOX_SEED_SCRIPT" '#!/usr/bin/env bash
set -euo pipefail

seed_dir="/var/lib/cloud/seed/nocloud-net"
run_dir="/run/dmitbox-seed"
mkdir -p "$seed_dir" "$run_dir"

# Candidate labels used by common NoCloud / ConfigDrive implementations
labels=(cidata CIDATA config-2 CONFIG-2 configdrive CONFIGDRIVE)

find_dev_by_label() {
  local lbl="$1"
  local p="/dev/disk/by-label/$lbl"
  [[ -e "$p" ]] && readlink -f "$p" && return 0
  return 1
}

dev=""
for lbl in "${labels[@]}"; do
  if d=$(find_dev_by_label "$lbl"); then dev="$d"; break; fi
done

# Fallback: any iso9660 block device
if [[ -z "$dev" ]] && command -v blkid >/dev/null 2>&1; then
  dev=$(blkid -t TYPE=iso9660 -o device 2>/dev/null | head -n1 || true)
fi

[[ -z "$dev" ]] && exit 0

# Mount read-only (best-effort)
umount "$run_dir" >/dev/null 2>&1 || true
mount -o ro "$dev" "$run_dir" >/dev/null 2>&1 || exit 0

# NoCloud seed layout: user-data/meta-data/network-config at root
if [[ -f "$run_dir/meta-data" || -f "$run_dir/user-data" || -f "$run_dir/network-config" ]]; then
  for f in meta-data user-data network-config vendor-data; do
    [[ -f "$run_dir/$f" ]] && cp -f "$run_dir/$f" "$seed_dir/$f" >/dev/null 2>&1 || true
  done
  umount "$run_dir" >/dev/null 2>&1 || true
  exit 0
fi

# ConfigDrive (OpenStack): try to stage if present (best effort)
if [[ -d "$run_dir/openstack/latest" ]]; then
  # cloud-init can read ConfigDrive directly; we do not need to transform here.
  umount "$run_dir" >/dev/null 2>&1 || true
  exit 0
fi

umount "$run_dir" >/dev/null 2>&1 || true
exit 0
'
  chmod +x "$DMITBOX_SEED_SCRIPT" >/dev/null 2>&1 || true

  write_file "$DMITBOX_SEED_SERVICE" "[Unit]
Description=DMITBox stage cloud-init seed (NoCloud/ConfigDrive)
DefaultDependencies=no
Before=cloud-init-local.service
Wants=cloud-init-local.service

[Service]
Type=oneshot
ExecStart=$DMITBOX_SEED_SCRIPT

[Install]
WantedBy=cloud-init-local.service
"
  systemctl daemon-reload >/dev/null 2>&1 || true
  systemctl enable dmitbox-cloud-seed.service >/dev/null 2>&1 || true
}

cloudinit_qga_prepare_network_for_cloudinit_debian_ifupdown() {
  # DMIT default Debian images typically let cloud-init generate /etc/network/interfaces.d/* (ifupdown).
  # Only apply on Debian-like with ifupdown available and no active netplan yaml.
  have_cmd apt-get || return 0

  # If netplan yamls exist, don't force-convert (too risky).
  if [[ -d /etc/netplan ]] && ls /etc/netplan/*.yaml >/dev/null 2>&1; then
    warn "检测到 netplan 配置：不强制切换到 ifupdown（避免误伤）。"
    return 0
  fi

  # Ensure ifupdown installed
  pkg_install ifupdown >/dev/null 2>&1 || pkg_install ifupdown2 >/dev/null 2>&1 || true

  # Backup current network config
  ensure_dir "$BACKUP_BASE"
  local bdir=""
  bdir="${BACKUP_BASE}/ipchange-dmitdefault-$(ts_now)"
  ensure_dir "$bdir"
  cp -a /etc/network "$bdir/" 2>/dev/null || true
  echo "$bdir" > "$DMITBOX_IPCHANGE_BACKUP_POINTER" 2>/dev/null || true

  # Minimal interfaces allowing cloud-init to drop config into interfaces.d
  ensure_dir /etc/network/interfaces.d
  write_file /etc/network/interfaces "auto lo
iface lo inet loopback

source /etc/network/interfaces.d/*
"
  chmod 644 /etc/network/interfaces >/dev/null 2>&1 || true

  # Remove any previous cloud-init generated file; it will be regenerated on boot from datasource
  rm -f /etc/network/interfaces.d/*cloud-init* 2>/dev/null || true

  # Ensure networking service enabled
  if is_systemd; then
    systemctl enable networking >/dev/null 2>&1 || true
  fi

  ok "已准备 ifupdown 结构：cloud-init 将在 /etc/network/interfaces.d/ 写入网卡配置"
  warn "提示：如果云端 metadata/seed 不可用，可能导致启动后无网；脚本已安装自动回滚保护。"
}

cloudinit_qga_install_net_rollback_protection() {
  is_systemd || return 0

  # shellcheck disable=SC2016
  write_file "$DMITBOX_NET_ROLLBACK_SCRIPT" '#!/usr/bin/env bash
set -euo pipefail

log="/var/log/dmitbox-net-rollback.log"
ptr="/etc/dmitbox-ipchange-backup.path"

echo "[$(date -Is)] rollback-check start" >> "$log"

# wait a bit for cloud-init + networking to settle
sleep 90

# if there is a default route and at least one global IPv4, we consider it OK
if ip -4 route show default 2>/dev/null | grep -q "default"; then
  if ip -4 addr show scope global 2>/dev/null | grep -q "inet "; then
    echo "[$(date -Is)] network looks OK, no rollback" >> "$log"
    exit 0
  fi
fi

echo "[$(date -Is)] network NOT OK, attempting rollback" >> "$log"

bdir=""
[[ -f "$ptr" ]] && bdir="$(cat "$ptr" 2>/dev/null || true)"
if [[ -z "$bdir" || ! -d "$bdir" ]]; then
  # fallback: pick latest backup
  bdir="$(ls -dt /root/dmit-backup/ipchange-dmitdefault-* 2>/dev/null | head -n1 || true)"
fi

if [[ -n "$bdir" && -d "$bdir/network" ]]; then
  rm -rf /etc/network 2>/dev/null || true
  cp -a "$bdir/network" /etc/network 2>/dev/null || true
  echo "[$(date -Is)] restored /etc/network from $bdir" >> "$log"
fi

# restart best-effort
systemctl restart networking 2>/dev/null || true
systemctl restart systemd-networkd 2>/dev/null || true
systemctl restart NetworkManager 2>/dev/null || true

echo "[$(date -Is)] rollback done" >> "$log"
exit 0
'
  chmod +x "$DMITBOX_NET_ROLLBACK_SCRIPT" >/dev/null 2>&1 || true

  write_file "$DMITBOX_NET_ROLLBACK_SERVICE" "[Unit]
Description=DMITBox network rollback protection (after cloud-init)
After=cloud-final.service network-online.target
Wants=cloud-final.service network-online.target

[Service]
Type=oneshot
ExecStart=$DMITBOX_NET_ROLLBACK_SCRIPT

[Install]
WantedBy=multi-user.target
"
  systemctl daemon-reload >/dev/null 2>&1 || true
  systemctl enable dmitbox-net-rollback.service >/dev/null 2>&1 || true
}

cloudinit_qga_preserve_ssh_auth() {
  # 目标：DD 后启用 cloud-init 时，尽量不改变现有 SSH 登录方式，避免重启锁死
  # - 尽量“保持/放宽”而不是收紧：如无法判断，默认认为允许密码登录（更不容易锁死）
  # - 永远禁止 cloud-init 删除 SSH host keys（避免指纹变化）
  mkdir -p /etc/cloud/cloud.cfg.d

  # 1) 尝试检测当前 SSH 是否允许密码登录
  local pa="unknown"
  if command -v sshd >/dev/null 2>&1; then
    # sshd -T 在不同系统/版本可能需要 root；这里容错
    pa="$(sshd -T 2>/dev/null | awk '/^passwordauthentication /{print $2; exit}')"
  fi
  if [[ "$pa" != "yes" && "$pa" != "no" ]]; then
    # 退化检测：扫描 sshd_config 及 drop-in
    local files=()
    [[ -f /etc/ssh/sshd_config ]] && files+=("/etc/ssh/sshd_config")
    if [[ -d /etc/ssh/sshd_config.d ]]; then
      while IFS= read -r -d '' f; do files+=("$f"); done < <(find /etc/ssh/sshd_config.d -maxdepth 1 -type f -name '*.conf' -print0 2>/dev/null || true)
    fi
    local hit=""
    if (( ${#files[@]} > 0 )); then
      hit="$(awk '
        BEGIN{IGNORECASE=1}
        $1 ~ /^PasswordAuthentication$/ {val=tolower($2); last=val}
        END{ if(last!="") print last; }
      ' "${files[@]}" 2>/dev/null || true)"
    fi
    if [[ "$hit" == "yes" || "$hit" == "no" ]]; then
      pa="$hit"
    else
      pa="unknown"
    fi
  fi

  # 2) 写入 cloud-init drop-in：禁止删 key；如果系统允许/不确定允许密码，则显式开启 ssh_pwauth
  local cfg="/etc/cloud/cloud.cfg.d/99-dmitbox-ssh.yaml"
  {
    echo "# Created by dmitbox: keep SSH reachable after enabling cloud-init"
    echo "disable_root: false"
    # 关键：不要让 cloud-init 删除 /etc/ssh/ssh_host_*（否则指纹变化）
    echo "ssh_deletekeys: false"
    # 如果原本允许密码，或无法判断，则开启（更不容易锁死）
    if [[ "$pa" == "yes" || "$pa" == "unknown" ]]; then
      echo "ssh_pwauth: true"
    fi
  } > "$cfg"

  # 3) 额外保险：写 sshd drop-in（优先不改主配置），只在“允许/不确定”时写入放宽项
  local dropdir="/etc/ssh/sshd_config.d"
  local dropfile=""
  if [[ -d "$dropdir" ]]; then
    dropfile="$dropdir/99-dmitbox-keep-access.conf"
    {
      echo "# Created by dmitbox: keep SSH access (avoid lockout after cloud-init/network change)"
      # 只放宽，不收紧；如果用户本来禁用了密码，我们也不强行开启
      if [[ "$pa" == "yes" || "$pa" == "unknown" ]]; then
        echo "PasswordAuthentication yes"
        echo "KbdInteractiveAuthentication yes"
        echo "ChallengeResponseAuthentication yes"
      fi
      # root 登录策略：如果用户用 root 登录，避免被默认策略挡住（仅放宽）
      echo "PermitRootLogin yes"
      echo "PubkeyAuthentication yes"
    } > "$dropfile"
  else
    # 没有 drop-in 的老系统：追加到 sshd_config（带 marker，方便回滚）
    if [[ -f /etc/ssh/sshd_config ]]; then
      if ! grep -q "DMITBOX-KEEP-ACCESS" /etc/ssh/sshd_config 2>/dev/null; then
        {
          echo ""
          echo "# --- DMITBOX-KEEP-ACCESS (added to avoid lockout) ---"
          if [[ "$pa" == "yes" || "$pa" == "unknown" ]]; then
            echo "PasswordAuthentication yes"
            echo "KbdInteractiveAuthentication yes"
            echo "ChallengeResponseAuthentication yes"
          fi
          echo "PermitRootLogin yes"
          echo "PubkeyAuthentication yes"
          echo "# --- DMITBOX-KEEP-ACCESS END ---"
        } >> /etc/ssh/sshd_config
      fi
    fi
  fi

  # 4) 立即尝试重载/重启 ssh（失败也不致命；并且加超时，避免 systemctl 卡住导致菜单无法返回）
  if is_systemd && have_cmd systemctl; then
    if have_cmd timeout; then
      timeout 3s systemctl reload  --no-block ssh  >/dev/null 2>&1 || true
      timeout 3s systemctl reload  --no-block sshd >/dev/null 2>&1 || true
      timeout 5s systemctl restart --no-block ssh  >/dev/null 2>&1 || true
      timeout 5s systemctl restart --no-block sshd >/dev/null 2>&1 || true
    else
      systemctl reload  --no-block ssh  >/dev/null 2>&1 || true
      systemctl reload  --no-block sshd >/dev/null 2>&1 || true
      systemctl restart --no-block ssh  >/dev/null 2>&1 || true
      systemctl restart --no-block sshd >/dev/null 2>&1 || true
    fi
  fi


  echo "已写入 cloud-init SSH 保活配置：$cfg"
  [[ -n "$dropfile" ]] && echo "已写入 sshd drop-in：$dropfile"
  echo "提示：如果你原来就是【仅密钥登录】，上述配置不会影响；如果你用密码登录，这能显著降低重启后无法登录的概率。"
}


# 让 cloud-init 只做“网络相关”的事，避免 DD 后因 user-data/模块默认行为导致：
# - SSH host key 被删除/重建（指纹变化）
# - sshd 被改成禁用密码/禁用 root（端口通但登不上）
# - set-passwords/users-groups 触发账号/密码/锁定变化
# - package-update-upgrade-install 在首启自动跑 apt（改动太大 + 可能报错导致 cloud-init status:error）
cloudinit_qga_dd_lockdown_network_only() {
  need_root
  local cfg="/etc/cloud/cloud.cfg"
  local ts; ts="$(date +%Y%m%d-%H%M%S)"

  if [[ -f "$cfg" ]]; then
    local bak="${cfg}.dmitbox.bak.${ts}"
    cp -a "$cfg" "$bak"

    # DD 系统最容易踩坑：cloud-init 重新跑 users/ssh 等模块后，可能导致无法 SSH 或指纹变化。
    # 这里直接从主 cloud.cfg 里移除这些模块，保留 cloud-init 的网络接管能力。
    sed -i -E \
      -e '/^[[:space:]]*-[[:space:]]*(users-groups|ssh|set-passwords|ssh-import-id)[[:space:]]*$/d' \
      -e '/^[[:space:]]*-[[:space:]]*(ssh-authkey-fingerprints|keys-to-console)[[:space:]]*$/d' \
      -e '/^[[:space:]]*-[[:space:]]*(package-update-upgrade-install|apt-configure|apt-pipelining)[[:space:]]*$/d' \
      "$cfg"

    echo "已对 $cfg 做 DD 安全加固（备份：$bak）"
  else
    echo "未找到 $cfg，跳过 cloud-init 模块加固（不常见）。"
  fi

  # 防止 cloud-init 删除/重建 SSH HostKey（避免指纹变化）
  mkdir -p /etc/cloud/cloud.cfg.d
  cat > /etc/cloud/cloud.cfg.d/99_dmitbox_ssh_safety.cfg <<'YAML'
ssh_deletekeys: false
YAML
  chmod 0644 /etc/cloud/cloud.cfg.d/99_dmitbox_ssh_safety.cfg

  # 兜底：固化当前 sshd 的最终生效配置（含 include），避免后续被改成不能登录
  cloudinit_qga_preserve_ssh_auth
}



cloudinit_qga_apply_dmit_default_ipchange_mode() {
  info "DD 后适配：DMIT 默认换 IP 模式（NoCloud/ConfigDrive + cloud-init 接管网络）"
  warn "这会让 cloud-init 像 DMIT 原版镜像一样接管网卡配置，以便面板换 IP 不失联。"
  warn "已内置【自动回滚保护】：若重启后无网，会自动恢复原网络配置（见 /var/log/dmitbox-net-rollback.log）。"

  cloudinit_qga_install || {
    have_cmd cloud-init || { warn "缺少 cloud-init，无法继续换 IP 适配"; return 1; }
  }
  cloudinit_qga_preserve_ssh_auth
  # 关键：DD 后优先启用“network-only”锁定，避免 cloud-init 触碰 SSH/用户/密码/包更新。
  cloudinit_qga_dd_lockdown_network_only
  cloudinit_disable_pkg_updates || true
  cloudinit_qga_enable_network_management
  cloudinit_qga_write_dmit_pve_cfg
  cloudinit_qga_install_seed_helper_systemd
  cloudinit_qga_install_net_rollback_protection

  # Debian/ifupdown alignment (best effort)
  cloudinit_qga_prepare_network_for_cloudinit_debian_ifupdown || true

  # Force cloud-init to re-run network on next boot
  cloudinit_clean_and_hint_reboot

  ok "已完成 DMIT 默认换IP模式适配"
  warn "下一步：reboot（重启后 cloud-init 会读取 NoCloud/ConfigDrive 元数据并生成网卡配置）"
  warn "面板换 IP 后：一般需要 reboot 一次让新网络生效（与 DMIT 原版一致）"
}

cloudinit_qga_menu() {
  while true; do
    menu_header "换 IP 防失联" "cloud-init · QEMU Guest Agent · 网络回滚保护"
    menu_section "状态与安装"
    menu_item "1" "检测当前状态" "cloud-init、QGA 与网络接管状态"
    menu_item "2" "安装并启用组件" "安装 cloud-init 与 QEMU Guest Agent"
    menu_section "网络接管"
    menu_item "3" "开启网络接管" "解除 network: {config: disabled}"
    menu_item "4" "清理 cloud-init 状态" "换 IP 前后执行，随后重启"
    menu_item "5" "适配 DMIT 默认模式" "NoCloud/ConfigDrive + 自动回滚保护"
    menu_item "6" "禁用开机 apt 更新" "避免非关键 status:error"
    menu_back_item
    local c=""
    read_tty c "请输入编号 > " ""
    case "$c" in
      1) cloudinit_qga_status; pause_up ;;
      2) cloudinit_qga_install || true; pause_up ;;
      3) cloudinit_qga_fix_network_disabled || true; pause_up ;;
      4) cloudinit_clean_and_hint_reboot || true; pause_up ;;
      5) cloudinit_qga_apply_dmit_default_ipchange_mode || true; pause_up ;;

      6) cloudinit_disable_pkg_updates || true; pause_up ;;
      0|q|Q) return 0 ;;
      *) warn "无效选项"; pause_up ;;
    esac
  done
}

# ======================================================================
# SSH（仅管理本脚本 drop-in；生效验证、失败回滚与防锁死）
# ======================================================================

ssh_pkg_install() {
  if ! have_cmd sshd && [[ -x /usr/sbin/sshd ]]; then
    export PATH="$PATH:/usr/sbin:/sbin"
  fi
  if have_cmd sshd && have_cmd ssh-keygen; then return 0; fi
  if have_cmd apk; then
    pkg_install openssh
  elif have_cmd apt-get; then
    pkg_install openssh-server openssh-client
  elif have_cmd dnf || have_cmd yum; then
    pkg_install openssh-server openssh-clients
  else
    pkg_install openssh-server
  fi
  if ! have_cmd sshd && [[ -x /usr/sbin/sshd ]]; then
    export PATH="$PATH:/usr/sbin:/sbin"
  fi
  have_cmd sshd || { warn "OpenSSH Server 安装失败，未继续修改 SSH"; return 1; }
  have_cmd ssh-keygen || { warn "OpenSSH 客户端工具安装失败，未继续修改 SSH"; return 1; }
}

ssh_backup_once() {
  [[ -d /etc/ssh && ! -L /etc/ssh ]] || { warn "/etc/ssh 不是可安全备份的普通目录"; return 1; }
  [[ ! -e /etc/ssh/sshd_config || ( -f /etc/ssh/sshd_config && ! -L /etc/ssh/sshd_config ) ]] || {
    warn "sshd_config 不是可安全备份的普通文件"
    return 1
  }
  [[ ! -e "$SSH_DROPIN_DIR" || ( -d "$SSH_DROPIN_DIR" && ! -L "$SSH_DROPIN_DIR" ) ]] || {
    warn "sshd_config.d 不是可安全管理的普通目录"
    return 1
  }
  have_cmd find || { warn "系统缺少 find，无法安全检查 SSH 配置路径"; return 1; }
  if [[ -n "$(find /etc/ssh -type l -print -quit 2>/dev/null || true)" ]]; then
    warn "/etc/ssh 中存在符号链接，为避免备份或恢复越界，已取消自动修改"
    return 1
  fi
  ensure_dir "$BACKUP_BASE"
  chmod 700 "$BACKUP_BASE" >/dev/null 2>&1 || { warn "无法保护 SSH 备份目录权限"; return 1; }
  [[ ! -e "$SSH_ORIG_TGZ" ]] || chmod 600 "$SSH_ORIG_TGZ" >/dev/null 2>&1 || return 1
  [[ ! -e "$SSH_DROPIN_ORIG_MARKER" ]] || chmod 600 "$SSH_DROPIN_ORIG_MARKER" >/dev/null 2>&1 || return 1
  if [[ -s "$SSH_ORIG_TGZ" ]] && ! ssh_backup_archive_safe "$SSH_ORIG_TGZ"; then
    warn "现有 SSH 原始备份损坏或范围异常，已取消配置修改：$SSH_ORIG_TGZ"
    return 1
  fi
  if [[ ! -s "$SSH_ORIG_TGZ" ]]; then
    ssh_validate_config || { warn "当前 SSH 配置无效，未创建原始备份，也未继续修改"; return 1; }
    info "SSH：备份原始配置 → $SSH_ORIG_TGZ"
    if [[ -e "$SSH_DROPIN_FILE" || -e "$SSH_LEGACY_DROPIN_FILE" ]]; then
      write_file "$SSH_DROPIN_ORIG_MARKER" "1"
    else
      write_file "$SSH_DROPIN_ORIG_MARKER" "0"
    fi
    chmod 600 "$SSH_DROPIN_ORIG_MARKER" >/dev/null 2>&1 || return 1
    local paths=()
    local relative_paths=() path=""
    [[ -f /etc/ssh/sshd_config ]] && paths+=(/etc/ssh/sshd_config)
    [[ -d /etc/ssh/sshd_config.d ]] && paths+=(/etc/ssh/sshd_config.d)
    if (( ${#paths[@]} == 0 )); then
      warn "未找到 SSH 配置，无法创建备份"
      return 1
    fi
    for path in "${paths[@]}"; do relative_paths+=("${path#/}"); done
    if ! ( umask 077; tar -C / -czf "$SSH_ORIG_TGZ" "${relative_paths[@]}" ) 2>/dev/null; then
      rm -f "$SSH_ORIG_TGZ" >/dev/null 2>&1 || true
      rm -f "$SSH_DROPIN_ORIG_MARKER" >/dev/null 2>&1 || true
      warn "SSH 配置备份失败，已取消后续修改"
      return 1
    fi
    if ! ssh_backup_archive_safe "$SSH_ORIG_TGZ"; then
      rm -f "$SSH_ORIG_TGZ" "$SSH_DROPIN_ORIG_MARKER" >/dev/null 2>&1 || true
      warn "SSH 配置含符号链接、特殊文件或异常路径，未保留不安全备份"
      return 1
    fi
    chmod 600 "$SSH_ORIG_TGZ" >/dev/null 2>&1 || { warn "无法保护 SSH 备份文件权限"; return 1; }
    ok "SSH 原始配置已备份"
  fi
}

ssh_backup_archive_safe() {
  local archive="${1:-}" member="" found=0
  [[ -s "$archive" ]] || return 1
  tar -tzf "$archive" >/dev/null 2>&1 || return 1
  while IFS= read -r member; do
    [[ -n "$member" ]] || continue
    found=1
    [[ "$member" != /* ]] || return 1
    [[ "/$member/" != *"/../"* ]] || return 1
    [[ "$member" == "etc/ssh" || "$member" == etc/ssh/* ]] || return 1
  done < <(tar -tzf "$archive" 2>/dev/null) || return 1
  if tar -tvzf "$archive" 2>/dev/null | awk 'substr($1,1,1) !~ /^[-d]$/ {unsafe=1} END{exit !unsafe}'; then
    return 1
  fi
  (( found == 1 ))
}

ssh_backup_archive_has_member() {
  local archive="$1" wanted="$2" member=""
  ssh_backup_archive_safe "$archive" || return 1
  while IFS= read -r member; do
    [[ "${member%/}" == "${wanted%/}" ]] && return 0
  done < <(tar -tzf "$archive" 2>/dev/null)
  return 1
}

ssh_validate_config() {
  have_cmd sshd || { warn "未找到 sshd，无法校验配置"; return 1; }
  [[ -d /run ]] && mkdir -p /run/sshd >/dev/null 2>&1 || true
  local output=""
  output="$(sshd -t 2>&1)" || {
    warn "sshd 配置校验失败"
    [[ -n "$output" ]] && printf '%s\n' "$output" | sed -n '1,12p'
    return 1
  }
}

ssh_service_name() {
  local name=""
  if is_systemd; then
    for name in ssh sshd; do
      command_with_timeout 6 systemctl is-active --quiet "${name}.service" >/dev/null 2>&1 && {
        printf '%s\n' "$name"
        return 0
      }
    done
    for name in ssh sshd; do
      command_with_timeout 6 systemctl cat "${name}.service" >/dev/null 2>&1 && {
        printf '%s\n' "$name"
        return 0
      }
    done
  elif have_cmd rc-service; then
    for name in sshd ssh; do
      [[ -x "/etc/init.d/${name}" ]] && { printf '%s\n' "$name"; return 0; }
    done
  elif have_cmd service; then
    for name in ssh sshd; do
      service "$name" status >/dev/null 2>&1 && { printf '%s\n' "$name"; return 0; }
    done
    for name in ssh sshd; do
      [[ -x "/etc/init.d/${name}" ]] && { printf '%s\n' "$name"; return 0; }
    done
  fi
  return 1
}

sshd_restart() {
  ssh_validate_config || return 1
  local service_name=""
  service_name="$(ssh_service_name 2>/dev/null || true)"
  [[ -n "$service_name" ]] || { warn "未找到可管理的 SSH 服务，配置未重新加载"; return 1; }

  if is_systemd; then
    if command_with_timeout 20 systemctl is-active --quiet "${service_name}.service" >/dev/null 2>&1; then
      command_with_timeout 25 systemctl reload "${service_name}.service" >/dev/null 2>&1 || \
        command_with_timeout 25 systemctl restart "${service_name}.service" >/dev/null 2>&1 || return 1
    else
      command_with_timeout 25 systemctl start "${service_name}.service" >/dev/null 2>&1 || return 1
    fi
    command_with_timeout 8 systemctl is-active --quiet "${service_name}.service" >/dev/null 2>&1 || return 1
  elif have_cmd rc-service; then
    command_with_timeout 25 rc-service "$service_name" reload >/dev/null 2>&1 || \
      command_with_timeout 25 rc-service "$service_name" restart >/dev/null 2>&1 || return 1
    command_with_timeout 8 rc-service "$service_name" status >/dev/null 2>&1 || return 1
  else
    command_with_timeout 25 service "$service_name" reload >/dev/null 2>&1 || \
      command_with_timeout 25 service "$service_name" restart >/dev/null 2>&1 || return 1
    command_with_timeout 8 service "$service_name" status >/dev/null 2>&1 || return 1
  fi
}

sshd_status_hint() {
  echo -e "${c_dim}--- SSH 当前生效配置（节选）---${c_reset}"
  if have_cmd sshd; then
    command_with_timeout 8 sshd -T 2>/dev/null | grep -Ei \
      '^(port|passwordauthentication|permitrootlogin|pubkeyauthentication|authenticationmethods|kbdinteractiveauthentication|challengeresponseauthentication|usepam|maxauthtries|logingracetime|permituserenvironment|x11forwarding|allowtcpforwarding|authorizedkeysfile)[[:space:]]' || true
  else
    warn "未找到 sshd 命令，改为简单 grep："
    grep -ERini 'Port|PasswordAuthentication|PubkeyAuthentication|KbdInteractiveAuthentication|ChallengeResponseAuthentication|UsePAM|PermitRootLogin|AuthenticationMethods' /etc/ssh/sshd_config /etc/ssh/sshd_config.d 2>/dev/null || true
  fi
  echo -e "${c_dim}--------------------------------${c_reset}"
}

ssh_effective_config() {
  local user="${1:-root}" port="22" addr="127.0.0.1" laddr="127.0.0.1" host_name=""
  local connection_fields=()
  have_cmd sshd || return 1
  if [[ -n "${SSH_CONNECTION:-}" ]]; then
    IFS=' ' read -r -a connection_fields <<< "$SSH_CONNECTION"
    if (( ${#connection_fields[@]} >= 4 )); then
      if [[ "${connection_fields[0]}" != */* ]] && valid_ip_or_cidr "${connection_fields[0]}"; then addr="${connection_fields[0]}"; fi
      if [[ "${connection_fields[2]}" != */* ]] && valid_ip_or_cidr "${connection_fields[2]}"; then laddr="${connection_fields[2]}"; fi
    fi
  fi
  port="$(ssh_current_ports 2>/dev/null | awk '{print $1}')"
  is_uint_in_range "$port" 1 65535 || port=22
  host_name="$addr"
  command_with_timeout 8 sshd -T -C \
    "user=${user},host=${host_name},addr=${addr},laddr=${laddr},lport=${port}" 2>/dev/null || \
    command_with_timeout 8 sshd -T 2>/dev/null
}

ssh_effective_context_source() {
  local connection_fields=()
  if [[ -n "${SSH_CONNECTION:-}" ]]; then
    IFS=' ' read -r -a connection_fields <<< "$SSH_CONNECTION"
    if (( ${#connection_fields[@]} >= 1 )) && [[ "${connection_fields[0]}" != */* ]] && valid_ip_or_cidr "${connection_fields[0]}"; then
      printf '%s\n' "${connection_fields[0]}"
      return 0
    fi
  fi
  printf '127.0.0.1（本机默认上下文）\n'
}

ssh_effective_value() {
  local key="${1,,}" user="${2:-root}"
  ssh_effective_config "$user" | awk -v wanted="$key" '$1==wanted {$1=""; sub(/^[[:space:]]+/, ""); print; exit}'
}

ssh_effective_value_or() {
  local key="$1" user="${2:-root}" fallback="${3:-未知}" value=""
  value="$(ssh_effective_value "$key" "$user" 2>/dev/null || true)"
  printf '%s\n' "${value:-$fallback}"
}

ssh_effective_text_value() {
  local key="${1,,}"
  awk -v wanted="$key" '$1==wanted {$1=""; sub(/^[[:space:]]+/, ""); print; exit}'
}

ssh_effective_text_value_or() {
  local key="$1" fallback="${2:-未知}" value=""
  value="$(ssh_effective_text_value "$key")"
  printf '%s\n' "${value:-$fallback}"
}

ssh_effective_value_matches() {
  local key="${1,,}" expected="${2,,}" user="${3:-root}" value=""
  value="$(ssh_effective_value "$key" "$user" 2>/dev/null || true)"
  value="${value,,}"
  if [[ "$key" == "port" ]]; then
    ssh_effective_config "$user" | awk -v wanted="$expected" '$1=="port" && $2==wanted {found=1} END {exit !found}'
    return $?
  fi
  if [[ "$key" == "permitrootlogin" && "$expected" == "prohibit-password" ]]; then
    [[ "$value" == "prohibit-password" || "$value" == "without-password" ]]
    return $?
  fi
  [[ "$value" == "$expected" ]]
}

ssh_verify_effective_setting() {
  local key="$1" expected="$2" user="${3:-root}"
  if ssh_effective_value_matches "$key" "$expected" "$user"; then return 0; fi
  warn "SSH 设置未实际生效：${key} 期望 ${expected}，当前 $(ssh_effective_value "$key" "$user" 2>/dev/null || echo N/A)"
  info "脚本没有删除其他 SSH 配置；请检查更早出现的主配置或 drop-in 冲突"
  return 1
}

ssh_verify_authentication_path() {
  local method="${1,,}" user="${2:-root}" value="" alternative=""
  local alternatives=()
  value="$(ssh_effective_value authenticationmethods "$user" 2>/dev/null || true)"
  value="${value,,}"
  [[ -n "$value" ]] || value="any"
  IFS=' ' read -r -a alternatives <<< "$value"
  for alternative in "${alternatives[@]}"; do
    [[ "$alternative" == "any" || "$alternative" == "$method" ]] && return 0
  done
  warn "当前 AuthenticationMethods=${value}，不能保证 ${user} 单独使用 ${method} 登录"
  info "脚本不会降低其他软件设置的多因素认证要求，已取消本次策略变更"
  return 1
}

# 便携删除配置行（避免 sed -i /I 在某些系统不兼容）
conf_strip_keys_in_file() {
  local f="$1"; shift
  [[ -f "$f" ]] || return 0
  local tmp=""
  tmp="$(mktemp /tmp/dmitbox-ssh-conf.XXXXXX)" || return 1
  awk -v KEYS="$(printf "%s|" "$@")" '
    BEGIN{
      n=split(KEYS,a,"|");
      for(i=1;i<=n;i++){ if(a[i]!=""){ k[tolower(a[i])]=1; } }
    }
    {
      line=$0
      # keep comments
      if(line ~ /^[[:space:]]*#/){ print line; next }
      # detect key as first token
      m=line
      sub(/^[[:space:]]+/,"",m)
      split(m,toks,/([[:space:]]+|=)/)
      key=tolower(toks[1])
      if(key in k){
        next
      }
      print line
    }
  ' "$f" > "$tmp" 2>/dev/null || { rm -f "$tmp" >/dev/null 2>&1 || true; return 1; }
  cat "$tmp" > "$f" 2>/dev/null || { rm -f "$tmp" >/dev/null 2>&1 || true; return 1; }
  rm -f "$tmp" >/dev/null 2>&1 || true
}

ssh_dropin_ensure() {
  [[ ! -e "$SSH_DROPIN_DIR" || ( -d "$SSH_DROPIN_DIR" && ! -L "$SSH_DROPIN_DIR" ) ]] || {
    warn "SSH drop-in 路径不是可安全管理的普通目录：$SSH_DROPIN_DIR"
    return 1
  }
  ensure_dir "$SSH_DROPIN_DIR" || return 1
  [[ ! -e "$SSH_DROPIN_FILE" || ( -f "$SSH_DROPIN_FILE" && ! -L "$SSH_DROPIN_FILE" ) ]] || {
    warn "SSH 管理配置不是普通文件，脚本不会接管：$SSH_DROPIN_FILE"
    return 1
  }
  [[ ! -e "$SSH_LEGACY_DROPIN_FILE" || ( -f "$SSH_LEGACY_DROPIN_FILE" && ! -L "$SSH_LEGACY_DROPIN_FILE" ) ]] || {
    warn "旧版 SSH 管理路径不是普通文件，脚本不会接管：$SSH_LEGACY_DROPIN_FILE"
    return 1
  }
  if [[ -e "$SSH_DROPIN_FILE" ]] && ! grep -Fq "managed by ${SCRIPT_NAME}" "$SSH_DROPIN_FILE" 2>/dev/null; then
    warn "SSH 管理文件路径已被其他配置占用，脚本不会覆盖：$SSH_DROPIN_FILE"
    return 1
  fi
  if [[ ! -e "$SSH_DROPIN_FILE" && -f "$SSH_LEGACY_DROPIN_FILE" ]] && \
     grep -Fq "managed by ${SCRIPT_NAME}" "$SSH_LEGACY_DROPIN_FILE" 2>/dev/null; then
    mv "$SSH_LEGACY_DROPIN_FILE" "$SSH_DROPIN_FILE" || return 1
    info "已将旧版 SSH 配置迁移为优先加载的 00-dmitbox.conf"
  fi
  if [[ ! -f "$SSH_DROPIN_FILE" ]]; then
    write_file "$SSH_DROPIN_FILE" "# managed by ${SCRIPT_NAME}"
  fi
  if [[ -f "$SSH_LEGACY_DROPIN_FILE" ]] && grep -Fq "managed by ${SCRIPT_NAME}" "$SSH_LEGACY_DROPIN_FILE" 2>/dev/null; then
    rm -f "$SSH_LEGACY_DROPIN_FILE" || { warn "无法清理本脚本旧版 SSH 管理文件"; return 1; }
    info "已清理本脚本旧版 99-dmitbox.conf，其他 SSH 配置未改动"
  fi
  chown root:root "$SSH_DROPIN_FILE" >/dev/null 2>&1 || { warn "无法设置 SSH 管理配置所有者"; return 1; }
  chmod 600 "$SSH_DROPIN_FILE" >/dev/null 2>&1 || { warn "无法设置 SSH 管理配置权限"; return 1; }
}

ssh_dropin_set_kv() {
  local key="$1" val="$2"
  [[ "$key" =~ ^[A-Za-z][A-Za-z0-9]*$ ]] || return 1
  [[ -n "$val" && "$val" != *$'\n'* && "$val" != *$'\r'* ]] || return 1
  ssh_dropin_ensure || return 1
  # 只清理本脚本管理文件中的同名旧行。
  conf_strip_keys_in_file "$SSH_DROPIN_FILE" "$key" || return 1
  printf "%s %s\n" "$key" "$val" >> "$SSH_DROPIN_FILE" || return 1
  chmod 600 "$SSH_DROPIN_FILE" >/dev/null 2>&1 || return 1
}

ssh_dropin_set_many() {
  (( $# > 0 && $# % 2 == 0 )) || return 1
  while (( $# > 0 )); do
    ssh_dropin_set_kv "$1" "$2" || return 1
    shift 2
  done
}

ssh_managed_snapshot_create() {
  local snapshot=""
  snapshot="$(mktemp -d /tmp/dmitbox-ssh-config.XXXXXX)" || return 1
  if [[ -e "$SSH_DROPIN_FILE" ]]; then
    cp -a "$SSH_DROPIN_FILE" "$snapshot/00-dmitbox.conf" || { rm -rf -- "$snapshot"; return 1; }
  else
    touch "$snapshot/.00-missing"
  fi
  if [[ -e "$SSH_LEGACY_DROPIN_FILE" ]]; then
    cp -a "$SSH_LEGACY_DROPIN_FILE" "$snapshot/99-dmitbox.conf" || { rm -rf -- "$snapshot"; return 1; }
  else
    touch "$snapshot/.99-missing"
  fi
  printf '%s\n' "$snapshot"
}

ssh_managed_snapshot_restore() {
  local snapshot="$1"
  [[ "$snapshot" == /tmp/dmitbox-ssh-config.* && -d "$snapshot" ]] || return 1
  rm -f "$SSH_DROPIN_FILE" "$SSH_LEGACY_DROPIN_FILE" || return 1
  if [[ -f "$snapshot/00-dmitbox.conf" ]]; then
    cp -a "$snapshot/00-dmitbox.conf" "$SSH_DROPIN_FILE" || return 1
  fi
  if [[ -f "$snapshot/99-dmitbox.conf" ]]; then
    cp -a "$snapshot/99-dmitbox.conf" "$SSH_LEGACY_DROPIN_FILE" || return 1
  fi
}

ssh_managed_snapshot_discard() {
  local snapshot="$1"
  [[ "$snapshot" == /tmp/dmitbox-ssh-config.* && -d "$snapshot" ]] || return 0
  rm -rf -- "$snapshot"
}

# 防止 ssh.socket 抢占 22（即便现在 inactive，也避免后续被 enable）
ssh_socket_disable_if_any() {
  is_systemd || return 0
  if command_with_timeout 8 systemctl list-unit-files 2>/dev/null | awk '{print $1}' | grep -qx "ssh.socket"; then
    if command_with_timeout 6 systemctl is-enabled --quiet ssh.socket 2>/dev/null; then
      warn "检测到 ssh.socket 已启用：将 disable（否则端口可能被固定在 22）"
      command_with_timeout 20 systemctl disable --now ssh.socket >/dev/null 2>&1 || {
        warn "无法停用 ssh.socket，已取消端口修改"
        return 1
      }
    else
      command_with_timeout 10 systemctl stop ssh.socket >/dev/null 2>&1 || true
    fi
  fi
}

ssh_random_pass() { tr -dc 'A-Za-z0-9' < /dev/urandom | head -c 18 || true; }

ssh_set_user_password() {
  local user="$1" passwd="$2"
  id "$user" >/dev/null 2>&1 || { warn "用户不存在：$user"; return 1; }
  [[ -n "$passwd" ]] || { warn "密码不能为空"; return 1; }

  if have_cmd chpasswd; then
    if ! printf '%s:%s\n' "$user" "$passwd" | chpasswd; then
      warn "设置 ${user} 密码失败"
      return 1
    fi
  elif have_cmd passwd; then
    if ! printf "%s\n%s\n" "$passwd" "$passwd" | passwd "$user" >/dev/null 2>&1; then
      warn "设置 ${user} 密码失败"
      return 1
    fi
  else
    warn "系统缺少 chpasswd/passwd，无法设置密码"
    return 1
  fi
}

ssh_group_exists() {
  local group="${1:-}"
  [[ "$group" =~ ^[a-z_][a-z0-9_-]{0,31}$ ]] || return 1
  if have_cmd getent; then
    getent group "$group" >/dev/null 2>&1
  else
    awk -F: -v wanted="$group" '$1==wanted {found=1} END{exit !found}' /etc/group 2>/dev/null
  fi
}

ssh_create_user_with_password() {
  local user="$1"
  local passwd="$2"
  local admin_group=""

  valid_username "$user" || { warn "用户名无效：仅支持小写字母/数字/_/-，且必须以字母或下划线开头（最长 32 位）"; return 1; }

  if ! id "$user" >/dev/null 2>&1; then
    info "创建用户：$user"
    if have_cmd useradd; then
      useradd -m -s /bin/bash "$user" >/dev/null 2>&1 || { warn "useradd 创建用户失败"; return 1; }
    elif have_cmd adduser; then
      adduser -D "$user" >/dev/null 2>&1 || \
        adduser --disabled-password --gecos "" "$user" >/dev/null 2>&1 || { warn "adduser 创建用户失败"; return 1; }
    else
      warn "没有 useradd/adduser，无法创建用户"
      return 1
    fi
  fi

  id "$user" >/dev/null 2>&1 || { warn "用户创建失败：$user"; return 1; }
  ssh_user_login_shell_usable "$user" || { warn "用户 ${user} 的登录 Shell 不可用，未设置 SSH 密码"; return 1; }
  ssh_set_user_password "$user" "$passwd" || return 1

  ok "已设置 ${user} 密码"
  echo -e "${c_green}${user} 密码：${passwd}${c_reset}"

  if ssh_group_exists sudo; then admin_group="sudo"; elif ssh_group_exists wheel; then admin_group="wheel"; fi
  if [[ -z "$admin_group" ]]; then
    warn "系统没有 sudo/wheel 管理组，请按系统需要手动授权"
  elif have_cmd usermod; then
    usermod -aG "$admin_group" "$user" >/dev/null 2>&1 || warn "用户已创建，但加入 ${admin_group} 组失败"
  elif have_cmd adduser; then
    adduser "$user" "$admin_group" >/dev/null 2>&1 || warn "用户已创建，但加入 ${admin_group} 组失败"
  else
    warn "未自动加入 sudo/wheel 管理组，请按系统需要手动授权"
  fi
}

ssh_apply_base_hardening() {
  # 只修改本脚本自己的 drop-in；不删除主配置或其他软件的设置。
  ssh_dropin_ensure || return 1
  ssh_dropin_set_many \
    "KbdInteractiveAuthentication" "no" \
    "ChallengeResponseAuthentication" "no" \
    "PermitEmptyPasswords" "no" \
    "MaxAuthTries" "3" \
    "LoginGraceTime" "30"
}

ssh_managed_change_abort() {
  local snapshot="$1" reason="${2:-SSH 配置未能安全应用}"
  warn "$reason；正在恢复本次修改前的 SSH 配置"
  if ssh_managed_snapshot_restore "$snapshot"; then
    ssh_validate_config >/dev/null 2>&1 || warn "恢复后的 SSH 配置仍需人工检查"
    sshd_restart >/dev/null 2>&1 || warn "旧配置已恢复，但 SSH 服务未能自动重新加载"
  else
    warn "自动恢复本次 SSH 配置失败，请保持当前会话并立即人工检查"
  fi
  ssh_managed_snapshot_discard "$snapshot"
  return 1
}

ssh_managed_change_finish() {
  local snapshot="$1" keep_snapshot="${2:-0}"
  ssh_validate_config || {
    ssh_managed_change_abort "$snapshot" "新配置未通过 sshd -t"
    return 1
  }
  if ! sshd_restart; then
    ssh_managed_change_abort "$snapshot" "SSH 服务重新加载失败"
    return 1
  fi
  [[ "$keep_snapshot" == "1" ]] || ssh_managed_snapshot_discard "$snapshot"
}

ssh_user_home() {
  local user="${1:-}" entry="" home=""
  valid_username "$user" || return 1
  if have_cmd getent; then
    entry="$(getent passwd "$user" 2>/dev/null || true)"
  else
    entry="$(awk -F: -v wanted="$user" '$1==wanted {print; exit}' /etc/passwd 2>/dev/null || true)"
  fi
  home="$(printf '%s\n' "$entry" | awk -F: 'NF>=6 {print $6; exit}')"
  [[ "$home" == /* && "$home" != "/" ]] || return 1
  printf '%s\n' "$home"
}

ssh_user_login_shell() {
  local user="${1:-}" entry="" shell=""
  valid_username "$user" || return 1
  if have_cmd getent; then
    entry="$(getent passwd "$user" 2>/dev/null || true)"
  else
    entry="$(awk -F: -v wanted="$user" '$1==wanted {print; exit}' /etc/passwd 2>/dev/null || true)"
  fi
  shell="$(printf '%s\n' "$entry" | awk -F: 'NF>=7 {print $7; exit}')"
  [[ "$shell" == /* ]] || return 1
  printf '%s\n' "$shell"
}

ssh_user_login_shell_usable() {
  local user="${1:-}" shell=""
  shell="$(ssh_user_login_shell "$user")" || return 1
  case "$shell" in */nologin|*/false) return 1 ;; esac
  [[ -x "$shell" ]]
}

ssh_normalize_path() {
  local path="${1:-}"
  [[ "$path" == /* ]] || return 1
  if have_cmd readlink && readlink -m -- / >/dev/null 2>&1; then
    readlink -m -- "$path"
  elif have_cmd realpath && realpath -m -- / >/dev/null 2>&1; then
    realpath -m -- "$path"
  else
    [[ "/$path/" != *"/../"* && "/$path/" != *"/./"* ]] || return 1
    printf '%s\n' "$path"
  fi
}

ssh_authorized_key_path_expand() {
  local user="$1" spec="$2" home="" home_real="" path="" uid="" marker="__DMITBOX_PERCENT__"
  home="$(ssh_user_home "$user")" || return 1
  home_real="$(ssh_normalize_path "$home")" || return 1
  uid="$(id -u "$user" 2>/dev/null || true)"
  [[ -n "$uid" ]] || return 1
  [[ -n "$spec" && "$spec" != "none" ]] || return 1

  spec="${spec//%%/$marker}"
  spec="${spec//%h/$home}"
  spec="${spec//%u/$user}"
  spec="${spec//%U/$uid}"
  spec="${spec//$marker/%}"
  [[ "$spec" != *%* ]] || return 1
  if [[ "$spec" == /* ]]; then path="$spec"; else path="${home}/${spec}"; fi
  path="$(ssh_normalize_path "$path")" || return 1

  # 密钥管理只触碰用户家目录内的文件，拒绝系统级共享路径。
  [[ "$path" == "$home_real"/* ]] || return 1
  printf '%s\n' "$path"
}

ssh_authorized_keys_paths() {
  local user="${1:-root}" configured="" spec="" path="" seen=$'\n'
  local specs=()
  valid_username "$user" || return 1
  id "$user" >/dev/null 2>&1 || return 1
  configured="$(ssh_effective_value "authorizedkeysfile" "$user" 2>/dev/null || true)"
  [[ -n "$configured" ]] || configured=".ssh/authorized_keys .ssh/authorized_keys2"
  IFS=' ' read -r -a specs <<< "$configured"
  for spec in "${specs[@]}"; do
    path="$(ssh_authorized_key_path_expand "$user" "$spec" 2>/dev/null || true)"
    [[ -n "$path" ]] || continue
    [[ "$seen" == *$'\n'"$path"$'\n'* ]] && continue
    printf '%s\n' "$path"
    seen+="${path}"$'\n'
  done
}

ssh_authorized_keys_path() {
  local user="${1:-root}" path=""
  path="$(ssh_authorized_keys_paths "$user" | sed -n '1p')"
  [[ -n "$path" ]] || return 1
  printf '%s\n' "$path"
}

ssh_key_line_fingerprint() {
  local line="${1:-}" tmp="" output=""
  have_cmd ssh-keygen || return 1
  [[ -n "$line" && ${#line} -le 65536 && "$line" != *$'\n'* && "$line" != *$'\r'* ]] || return 1
  tmp="$(mktemp /tmp/dmitbox-ssh-key.XXXXXX)" || return 1
  chmod 600 "$tmp" >/dev/null 2>&1 || true
  printf '%s\n' "$line" > "$tmp"
  output="$(ssh-keygen -lf "$tmp" 2>/dev/null)" || { rm -f -- "$tmp"; return 1; }
  rm -f -- "$tmp"
  [[ -n "$output" ]] || return 1
  printf '%s\n' "$output"
}

ssh_public_key_validate() {
  local key="${1:-}" type="" fingerprint=""
  [[ -n "$key" && "$key" != *$'\n'* && "$key" != *$'\r'* && ${#key} -le 16384 ]] || return 1
  type="${key%%[[:space:]]*}"
  case "$type" in
    ssh-ed25519|ssh-rsa|ecdsa-sha2-*|sk-ssh-ed25519@openssh.com|sk-ecdsa-sha2-*@openssh.com) ;;
    *) return 1 ;;
  esac
  fingerprint="$(ssh_key_line_fingerprint "$key")" || return 1
  printf '%s\n' "$fingerprint"
}

ssh_valid_key_count_path() {
  local path="${1:-}" line="" count=0
  [[ -f "$path" && ! -L "$path" ]] || { printf '0\n'; return 0; }
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%$'\r'}"
    ssh_key_line_fingerprint "$line" >/dev/null 2>&1 && count=$((count + 1))
  done < "$path"
  printf '%s\n' "$count"
}

ssh_user_valid_key_count() {
  local user="${1:-root}" path="" count=0 part=0
  while IFS= read -r path; do
    [[ -n "$path" ]] || continue
    part="$(ssh_valid_key_count_path "$path")"
    is_uint_in_range "$part" 0 100000 || part=0
    count=$((count + part))
  done < <(ssh_authorized_keys_paths "$user" 2>/dev/null || true)
  printf '%s\n' "$count"
}

ssh_authorized_keys_backup() {
  local user="$1" path="$2" backup=""
  [[ -f "$path" && ! -L "$path" ]] || return 0
  ensure_dir "$SSH_KEYS_BACKUP_DIR"
  chmod 700 "$SSH_KEYS_BACKUP_DIR" >/dev/null 2>&1 || true
  backup="$(mktemp "${SSH_KEYS_BACKUP_DIR}/$(ts_now)-${user}-authorized_keys.XXXXXX")" || {
    warn "无法创建登录密钥备份文件，已取消修改"
    return 1
  }
  cp -a -- "$path" "$backup" || {
    rm -f -- "$backup" >/dev/null 2>&1 || true
    warn "登录密钥备份失败，已取消修改"
    return 1
  }
  chmod 600 "$backup" >/dev/null 2>&1 || true
  printf '%s\n' "$backup"
}

ssh_authorized_keys_change_abort() {
  local user="$1" path="$2" backup="${3:-}" existed="${4:-1}"
  if [[ -n "$backup" && -f "$backup" ]]; then
    cp -a -- "$backup" "$path" >/dev/null 2>&1 || {
      warn "登录密钥修改失败，且自动恢复备份失败：$backup"
      return 1
    }
    ssh_fix_authorized_keys_permissions "$user" "$path" >/dev/null 2>&1 || true
    warn "登录密钥修改失败，已恢复修改前内容"
  elif [[ "$existed" == "0" ]]; then
    rm -f -- "$path" >/dev/null 2>&1 || true
    warn "登录密钥修改失败，已撤销本次新建文件"
  else
    warn "登录密钥修改失败，请保持当前会话并人工检查：$path"
  fi
  return 1
}

ssh_fix_authorized_keys_permissions() {
  local user="$1" path="$2" home="" home_real="" dir="" group="" component="" parent="" owner=""
  valid_username "$user" || return 1
  id "$user" >/dev/null 2>&1 || return 1
  home="$(ssh_user_home "$user")" || return 1
  home_real="$(ssh_normalize_path "$home")" || return 1
  path="$(ssh_normalize_path "$path")" || return 1
  [[ "$path" == "$home_real"/* ]] || { warn "拒绝修改用户家目录外的密钥文件：$path"; return 1; }
  [[ ! -L "$path" ]] || { warn "密钥文件是符号链接，已拒绝自动修改"; return 1; }
  [[ ! -e "$path" || -f "$path" ]] || { warn "密钥路径不是普通文件：$path"; return 1; }
  if [[ -e "$path" ]]; then
    owner="$(stat -c '%U' "$path" 2>/dev/null || true)"
    [[ "$owner" == "$user" || "$owner" == "root" ]] || { warn "密钥文件所有者异常，已拒绝接管：${owner:-未知}"; return 1; }
  fi
  dir="$(dirname "$path")"
  [[ ! -L "$dir" ]] || { warn "密钥目录是符号链接，已拒绝自动修改"; return 1; }
  group="$(id -gn "$user" 2>/dev/null || true)"
  [[ -n "$group" ]] || return 1

  ( umask 077; mkdir -p -- "$dir" ) || return 1
  component="$dir"
  while [[ "$component" == "$home_real" || "$component" == "$home_real"/* ]]; do
    owner="$(stat -c '%U' "$component" 2>/dev/null || true)"
    [[ "$owner" == "$user" || "$owner" == "root" ]] || {
      warn "密钥路径目录所有者异常，已拒绝接管：${owner:-未知} / $component"
      return 1
    }
    chmod go-w "$component" >/dev/null 2>&1 || return 1
    [[ "$component" == "$home_real" ]] && break
    parent="$(dirname "$component")"
    [[ "$parent" != "$component" ]] || break
    component="$parent"
  done
  ( umask 077; touch -- "$path" ) || return 1
  if [[ "$dir" != "$home_real" ]]; then
    chown "$user:$group" "$dir" >/dev/null 2>&1 || return 1
    chmod 700 "$dir" >/dev/null 2>&1 || return 1
  fi
  chown "$user:$group" "$path" >/dev/null 2>&1 || return 1
  chmod 600 "$path" >/dev/null 2>&1 || return 1
  if have_cmd restorecon; then restorecon -F "$dir" "$path" >/dev/null 2>&1 || true; fi
}

ssh_list_authorized_keys() {
  local user="${1:-root}" path="" line="" fingerprint="" index=0 file_count=0
  valid_username "$user" || { warn "用户名无效：$user"; return 1; }
  id "$user" >/dev/null 2>&1 || { warn "用户不存在：$user"; return 1; }
  have_cmd ssh-keygen || ssh_pkg_install || return 1

  echo -e "${c_dim}--- ${user} 的登录密钥 ---${c_reset}"
  while IFS= read -r path; do
    [[ -n "$path" ]] || continue
    file_count=$((file_count + 1))
    print_kv "密钥文件" "$path"
    if [[ ! -e "$path" ]]; then
      info "文件尚未创建"
      continue
    fi
    if [[ -L "$path" || ! -f "$path" ]]; then
      warn "不是可安全管理的普通文件"
      continue
    fi
    while IFS= read -r line || [[ -n "$line" ]]; do
      line="${line%$'\r'}"
      fingerprint="$(ssh_key_line_fingerprint "$line" 2>/dev/null || true)"
      [[ -n "$fingerprint" ]] || continue
      index=$((index + 1))
      printf '  [%2d] %s\n' "$index" "$fingerprint"
    done < "$path"
  done < <(ssh_authorized_keys_paths "$user" 2>/dev/null || true)
  (( file_count > 0 )) || { warn "当前 AuthorizedKeysFile 路径不在用户家目录内，脚本不会自动管理"; return 1; }
  if (( index == 0 )); then warn "未发现有效公钥"; else ok "共发现 ${index} 个有效公钥"; fi
}

ssh_ephemeral_key_dir_create() {
  local base="${SSH_EPHEMERAL_KEY_BASE:-/tmp}"
  [[ "$base" == /* && "$base" != "/" && -d "$base" && ! -L "$base" ]] || return 1
  ( umask 077; mktemp -d "${base%/}/dmitbox-ssh-generated.XXXXXX" )
}

ssh_ephemeral_key_cleanup() {
  local dir="${1:-}" base="${SSH_EPHEMERAL_KEY_BASE:-/tmp}" dir_real="" base_real=""
  [[ "$base" == /* && "$base" != "/" && -d "$base" && ! -L "$base" ]] || return 1
  [[ "$dir" == /* && -d "$dir" && ! -L "$dir" ]] || return 0
  base_real="$(ssh_normalize_path "$base" 2>/dev/null || true)"
  dir_real="$(ssh_normalize_path "$dir" 2>/dev/null || true)"
  [[ -n "$base_real" && -n "$dir_real" ]] || return 1
  [[ "$(dirname "$dir_real")" == "$base_real" && "$(basename "$dir_real")" == dmitbox-ssh-generated.* ]] || return 1
  rm -rf -- "$dir_real"
}

ssh_copy_private_key_to_clipboard() {
  local private_file="${1:-}" encoded=""
  [[ "${DMITBOX_DISABLE_OSC52:-0}" != "1" ]] || return 1
  [[ -f "$private_file" && ! -L "$private_file" && -r "$private_file" ]] || return 1
  have_cmd base64 || return 1
  has_tty || return 1
  encoded="$(base64 < "$private_file" 2>/dev/null | tr -d '\r\n')"
  [[ -n "$encoded" && ${#encoded} -le 32768 ]] || return 1
  printf '\033]52;c;%s\a' "$encoded" > /dev/tty 2>/dev/null || return 1
}

ssh_generate_authorized_key() {
  local user="${1:-root}" target_path=""
  valid_username "$user" || { warn "用户名无效：$user"; return 1; }
  id "$user" >/dev/null 2>&1 || { warn "用户不存在：$user"; return 1; }
  ssh_user_login_shell_usable "$user" || { warn "${user} 的登录 Shell 不可用，已取消"; return 1; }
  ssh_pkg_install || return 1
  target_path="$(ssh_authorized_keys_path "$user" 2>/dev/null || true)"
  [[ -n "$target_path" ]] || {
    warn "AuthorizedKeysFile 位于用户家目录外或被设为 none，无法安全自动安装"
    return 1
  }

  warn "将为 ${user} 自动生成一把新的 Ed25519 登录密钥"
  warn "私钥无密码，便于直接登录；保存后可在本地用 ssh-keygen -p 添加密码"
  info "私钥只在本次流程中临时生成，不会保存到服务器备份目录"
  confirm_word "GENERATE" "确认生成请输入 GENERATE > " || { warn "已取消"; return 0; }

  (
    local key_dir="" private_file="" public_file="" public_key="" fingerprint="" save_name="" copied=0 private_shown=0
    key_dir="$(ssh_ephemeral_key_dir_create)" || { warn "无法创建安全的临时密钥目录"; return 1; }
    trap 'ssh_ephemeral_key_cleanup "$key_dir" >/dev/null 2>&1 || true; (( private_shown == 0 )) || soft_clear' EXIT
    trap 'exit 129' HUP
    trap 'exit 130' INT
    trap 'exit 143' TERM

    private_file="${key_dir}/id_ed25519"
    public_file="${private_file}.pub"
    save_name="dmitbox-${user}-$(date +%Y%m%d-%H%M%S).key"
    if ! ssh-keygen -q -t ed25519 -a 100 -N "" \
      -C "dmitbox-${user}-$(date +%Y%m%d)" -f "$private_file"; then
      warn "Ed25519 密钥生成失败"
      return 1
    fi
    chmod 600 "$private_file" "$public_file" >/dev/null 2>&1 || { warn "无法保护临时密钥权限"; return 1; }
    public_key="$(<"$public_file")"
    fingerprint="$(ssh_public_key_validate "$public_key" 2>/dev/null || true)"
    [[ -n "$fingerprint" ]] || { warn "生成的公钥未通过校验"; return 1; }

    if ssh_copy_private_key_to_clipboard "$private_file"; then copied=1; fi
    menu_section "一次性私钥"
    if (( copied )); then
      ok "已尝试复制到本地剪贴板；若 SSH 客户端不支持，请复制下面完整内容"
    else
      info "请复制下面从 BEGIN 到 END 的全部内容"
    fi
    warn "不要把私钥发送给别人，也不要保存在聊天记录或公开网盘"
    info "确认保存或取消后会自动清屏，并尝试清除终端回滚区"
    private_shown=1
    printf '\n%s\n' "$(<"$private_file")"
    echo
    print_kv "建议文件名" "$save_name"
    print_kv "文件权限" "chmod 600 $save_name"
    print_kv "密钥指纹" "$fingerprint"
    info "保存完成后输入 SAVED；未确认不会安装公钥"
    if ! confirm_word "SAVED" "确认私钥已安全保存请输入 SAVED > "; then
      warn "未确认保存，公钥没有安装；临时私钥将立即清理"
      return 1
    fi
    if ! ssh_add_authorized_key "$user" "$public_key"; then
      warn "公钥安装失败；临时私钥将立即清理"
      return 1
    fi
    soft_clear
    private_shown=0
    ok "自动生成并安装完成"
    print_kv "密钥指纹" "$fingerprint"
    info "请保持当前会话，另开终端测试：ssh -i ${save_name} -p $(ssh_current_ports | awk '{print $1}') ${user}@服务器IP"
    warn "确认新密钥可以登录后，再关闭当前 SSH 会话"
  )
}

ssh_add_authorized_key() {
  local user="$1" key="$2" path="" fingerprint="" blob="" backup="" tmp="" existed=0
  valid_username "$user" || { warn "用户名无效：$user"; return 1; }
  id "$user" >/dev/null 2>&1 || { warn "用户不存在：$user"; return 1; }
  ssh_pkg_install || return 1
  key="${key#"${key%%[![:space:]]*}"}"
  key="${key%"${key##*[![:space:]]}"}"
  fingerprint="$(ssh_public_key_validate "$key" 2>/dev/null || true)"
  [[ -n "$fingerprint" ]] || { warn "公钥格式无效；请粘贴完整的一行 OpenSSH 公钥"; return 1; }
  path="$(ssh_authorized_keys_path "$user" 2>/dev/null || true)"
  [[ -n "$path" ]] || { warn "AuthorizedKeysFile 位于用户家目录外或被设为 none，已拒绝自动修改"; return 1; }
  [[ -e "$path" ]] && existed=1
  ssh_fix_authorized_keys_permissions "$user" "$path" || { warn "无法安全准备密钥文件"; return 1; }
  blob="$(awk '{print $2}' <<< "$key")"
  if awk -v wanted="$blob" '{for(i=1;i<=NF;i++) if($i==wanted) found=1} END{exit !found}' "$path" 2>/dev/null; then
    info "该公钥已存在，无需重复添加"
    printf '  %s\n' "$fingerprint"
    return 0
  fi
  if (( existed )); then
    backup="$(ssh_authorized_keys_backup "$user" "$path")" || return 1
  fi
  tmp="$(mktemp "$(dirname "$path")/.dmitbox-authorized-keys.XXXXXX")" || return 1
  { cat -- "$path" 2>/dev/null || true; [[ ! -s "$path" ]] || printf '\n'; printf '%s\n' "$key"; } > "$tmp"
  mv -f -- "$tmp" "$path" || { rm -f -- "$tmp"; return 1; }
  ssh_fix_authorized_keys_permissions "$user" "$path" || {
    ssh_authorized_keys_change_abort "$user" "$path" "$backup" "$existed"
    return 1
  }
  ok "已添加 ${user} 登录公钥"
  printf '  %s\n' "$fingerprint"
  [[ -n "$backup" ]] && info "修改前备份：$backup"
  [[ "${key%%[[:space:]]*}" == "ssh-rsa" ]] && warn "这是旧式 ssh-rsa 公钥；新部署更建议使用 Ed25519"
  return 0
}

ssh_remove_authorized_key() {
  local user="$1" requested="${2:-}" path="" line="" fingerprint="" backup="" tmp=""
  local line_no=0 index=0 selected_line=0
  local key_lines=() key_files=() key_fingerprints=() key_contents=()
  valid_username "$user" || { warn "用户名无效：$user"; return 1; }
  id "$user" >/dev/null 2>&1 || { warn "用户不存在：$user"; return 1; }
  have_cmd ssh-keygen || ssh_pkg_install || return 1

  while IFS= read -r path; do
    [[ -f "$path" && ! -L "$path" ]] || continue
    line_no=0
    while IFS= read -r line || [[ -n "$line" ]]; do
      line_no=$((line_no + 1))
      line="${line%$'\r'}"
      fingerprint="$(ssh_key_line_fingerprint "$line" 2>/dev/null || true)"
      [[ -n "$fingerprint" ]] || continue
      index=$((index + 1))
      key_lines+=("$line_no")
      key_files+=("$path")
      key_fingerprints+=("$fingerprint")
      key_contents+=("$line")
      printf '  [%2d] %s\n' "$index" "$fingerprint"
    done < "$path"
  done < <(ssh_authorized_keys_paths "$user" 2>/dev/null || true)

  if (( index == 0 )); then warn "没有可移除的有效公钥"; return 1; fi
  if (( index == 1 )); then
    warn "已阻止移除最后一个有效公钥；请先添加替代密钥，避免 SSH 锁死"
    return 1
  fi
  if [[ -z "$requested" ]]; then read_tty requested "选择要移除的密钥编号 > " ""; fi
  is_uint_in_range "$requested" 1 "$index" || { warn "密钥编号无效"; return 1; }
  requested=$((10#$requested))
  path="${key_files[$((requested - 1))]}"
  selected_line="${key_lines[$((requested - 1))]}"
  warn "将移除：${key_fingerprints[$((requested - 1))]}"
  confirm_word "REMOVE" "确认请输入 REMOVE > " || { warn "已取消"; return 0; }
  line="$(sed -n "${selected_line}p" "$path" 2>/dev/null || true)"
  line="${line%$'\r'}"
  if [[ "$line" != "${key_contents[$((requested - 1))]}" ]]; then
    warn "确认期间密钥文件发生变化，已取消移除；请重新查看后再试"
    return 1
  fi
  backup="$(ssh_authorized_keys_backup "$user" "$path")" || return 1
  tmp="$(mktemp "$(dirname "$path")/.dmitbox-authorized-keys.XXXXXX")" || return 1
  awk -v remove_line="$selected_line" 'NR!=remove_line {print}' "$path" > "$tmp" || { rm -f -- "$tmp"; return 1; }
  mv -f -- "$tmp" "$path" || { rm -f -- "$tmp"; return 1; }
  ssh_fix_authorized_keys_permissions "$user" "$path" || {
    ssh_authorized_keys_change_abort "$user" "$path" "$backup" "1"
    return 1
  }
  ok "已移除所选公钥；其他密钥未改动"
  info "修改前备份：$backup"
}

ssh_repair_authorized_keys() {
  local user="${1:-root}" path="" repaired=0
  valid_username "$user" || { warn "用户名无效：$user"; return 1; }
  id "$user" >/dev/null 2>&1 || { warn "用户不存在：$user"; return 1; }
  while IFS= read -r path; do
    [[ -n "$path" ]] || continue
    [[ -e "$path" ]] || continue
    ssh_fix_authorized_keys_permissions "$user" "$path" || return 1
    print_kv "已修复" "${path} (600)"
    repaired=$((repaired + 1))
  done < <(ssh_authorized_keys_paths "$user" 2>/dev/null || true)
  if (( repaired == 0 )); then
    path="$(ssh_authorized_keys_path "$user" 2>/dev/null || true)"
    [[ -n "$path" ]] || { warn "没有可安全管理的 AuthorizedKeysFile 路径"; return 1; }
    ssh_fix_authorized_keys_permissions "$user" "$path" || return 1
    print_kv "已创建" "${path} (600)"
  fi
  ok "密钥目录与文件权限已校正；未改动密钥内容"
}

ssh_show_effective_configuration() {
  local user="${1:-root}" effective="${2:-}" root_effective="${3:-}" service_name="" service_state="未知" ports=""
  valid_username "$user" || { warn "用户名无效：$user"; return 1; }
  id "$user" >/dev/null 2>&1 || { warn "用户不存在：$user"; return 1; }
  have_cmd sshd || { warn "未找到 OpenSSH Server"; return 1; }
  ssh_validate_config || return 1
  if [[ -z "$effective" ]]; then
    effective="$(ssh_effective_config "$user")" || { warn "无法读取 sshd 最终生效配置"; return 1; }
  fi
  [[ -n "$root_effective" ]] || root_effective="$effective"
  if [[ "$user" != "root" && -z "${3:-}" ]]; then
    root_effective="$(ssh_effective_config root 2>/dev/null || true)"
    [[ -n "$root_effective" ]] || root_effective="$effective"
  fi
  service_name="$(ssh_service_name 2>/dev/null || true)"
  if [[ -n "$service_name" ]]; then
    if is_systemd; then
      if command_with_timeout 6 systemctl is-active --quiet "${service_name}.service" >/dev/null 2>&1; then service_state="运行中"; else service_state="未运行"; fi
    elif have_cmd rc-service; then
      if command_with_timeout 6 rc-service "$service_name" status >/dev/null 2>&1; then service_state="运行中"; else service_state="未运行"; fi
    elif have_cmd service; then
      if command_with_timeout 6 service "$service_name" status >/dev/null 2>&1; then service_state="运行中"; else service_state="未运行"; fi
    fi
  fi
  ports="$(awk '$1=="port" {out=(out ? out " " : "") $2} END{print out}' <<< "$effective")"
  print_kv "检查用户" "$user"
  print_kv "匹配来源" "$(ssh_effective_context_source)"
  print_kv "SSH 服务" "${service_name:-未识别} / ${service_state}"
  print_kv "监听端口配置" "${ports:-未知}"
  print_kv "密码认证" "$(ssh_effective_text_value_or passwordauthentication 未知 <<< "$effective")"
  print_kv "交互认证" "$(ssh_effective_text_value_or kbdinteractiveauthentication 未知 <<< "$effective")"
  print_kv "公钥认证" "$(ssh_effective_text_value_or pubkeyauthentication 未知 <<< "$effective")"
  print_kv "认证组合" "$(ssh_effective_text_value_or authenticationmethods any <<< "$effective")"
  print_kv "PAM" "$(ssh_effective_text_value_or usepam 未知 <<< "$effective")"
  print_kv "登录 Shell" "$(ssh_user_login_shell "$user" 2>/dev/null || echo 未知)"
  print_kv "root 登录" "$(ssh_effective_text_value_or permitrootlogin 未知 <<< "$root_effective")"
  print_kv "空密码" "$(ssh_effective_text_value_or permitemptypasswords 未知 <<< "$effective")"
  print_kv "最大认证次数" "$(ssh_effective_text_value_or maxauthtries 未知 <<< "$effective")"
  print_kv "登录宽限时间" "$(ssh_effective_text_value_or logingracetime 未知 <<< "$effective")"
  print_kv "密钥文件" "$(ssh_effective_text_value_or authorizedkeysfile 未知 <<< "$effective")"
  print_kv "TCP 转发" "$(ssh_effective_text_value_or allowtcpforwarding 未知 <<< "$effective")"
  print_kv "Agent 转发" "$(ssh_effective_text_value_or allowagentforwarding 未知 <<< "$effective")"
  print_kv "X11 转发" "$(ssh_effective_text_value_or x11forwarding 未知 <<< "$effective")"
  print_kv "用户环境变量" "$(ssh_effective_text_value_or permituserenvironment 未知 <<< "$effective")"
  print_kv "允许用户" "$(ssh_effective_text_value_or allowusers 未限制 <<< "$effective")"
  print_kv "拒绝用户" "$(ssh_effective_text_value_or denyusers 未设置 <<< "$effective")"
  print_kv "允许用户组" "$(ssh_effective_text_value_or allowgroups 未限制 <<< "$effective")"
  print_kv "拒绝用户组" "$(ssh_effective_text_value_or denygroups 未设置 <<< "$effective")"
  if [[ -f "$SSH_DROPIN_FILE" ]]; then
    print_kv "脚本管理配置" "$SSH_DROPIN_FILE"
  else
    print_kv "脚本管理配置" "未创建"
  fi
}

ssh_mode_is_group_world_writable() {
  local path="${1:-}" mode="" value=0
  [[ -e "$path" ]] || return 1
  mode="$(stat -c '%a' "$path" 2>/dev/null || true)"
  [[ "$mode" =~ ^[0-7]{3,4}$ ]] || return 1
  value=$((8#$mode))
  (( (value & 022) != 0 ))
}

ssh_security_audit() {
  local user="${1:-root}" effective="" root_effective="" value="" path="" dir="" owner="" count=0 warnings=0 ports="" port=""
  local port_list=()
  valid_username "$user" || { warn "用户名无效：$user"; return 1; }
  id "$user" >/dev/null 2>&1 || { warn "用户不存在：$user"; return 1; }
  have_cmd sshd || { warn "未找到 OpenSSH Server，无法执行安全体检"; return 1; }
  have_cmd ssh-keygen || { warn "未找到 ssh-keygen，密钥检查将受限"; }

  menu_section "配置与服务"
  if ssh_validate_config; then
    ok "sshd 配置语法正常"
  else
    warn "配置无效时无法可靠计算最终认证策略；请先修复上方错误"
    return 1
  fi
  effective="$(ssh_effective_config "$user" 2>/dev/null || true)"
  [[ -n "$effective" ]] || { warn "无法读取 sshd 最终生效配置，体检已停止"; return 1; }
  root_effective="$effective"
  if [[ "$user" != "root" ]]; then
    root_effective="$(ssh_effective_config root 2>/dev/null || true)"
    [[ -n "$root_effective" ]] || root_effective="$effective"
  fi
  ssh_show_effective_configuration "$user" "$effective" "$root_effective" || warnings=$((warnings + 1))
  ports="$(awk '$1=="port" {out=(out ? out " " : "") $2} END{print out}' <<< "$effective")"
  IFS=' ' read -r -a port_list <<< "$ports"
  for port in "${port_list[@]}"; do
    [[ -n "$port" ]] || continue
    if port_in_use "$port"; then ok "TCP/${port} 当前存在监听"; else warn "TCP/${port} 未检测到监听"; warnings=$((warnings + 1)); fi
  done

  menu_section "认证风险"
  if ssh_user_login_shell_usable "$user"; then ok "${user} 的登录 Shell 可用"; else warn "${user} 的登录 Shell 不可用或被设为 nologin/false"; warnings=$((warnings + 1)); fi
  value="$(ssh_effective_text_value passwordauthentication <<< "$effective")"
  if [[ "$value" == "yes" ]]; then warn "密码认证已开启，建议配好密钥后使用推荐加固"; warnings=$((warnings + 1)); else ok "密码认证未开启"; fi
  value="$(ssh_effective_text_value kbdinteractiveauthentication <<< "$effective")"
  if [[ "$value" == "yes" ]]; then warn "键盘交互认证已开启，可能仍允许口令类认证"; warnings=$((warnings + 1)); else ok "键盘交互认证未开启"; fi
  value="$(ssh_effective_text_value pubkeyauthentication <<< "$effective")"
  if [[ "$value" != "yes" ]]; then warn "公钥认证未开启"; warnings=$((warnings + 1)); else ok "公钥认证已开启"; fi
  value="$(ssh_effective_text_value authenticationmethods <<< "$effective")"
  [[ -n "$value" ]] && print_kv "认证组合" "$value"
  value="$(ssh_effective_text_value permitrootlogin <<< "$root_effective")"
  case "$value" in
    no|prohibit-password|without-password|forced-commands-only) ok "root 未开放直接密码登录（${value}）" ;;
    *) warn "root 登录策略偏宽松：${value:-未知}"; warnings=$((warnings + 1)) ;;
  esac
  value="$(ssh_effective_text_value permitemptypasswords <<< "$effective")"
  if [[ "$value" == "yes" ]]; then warn "检测到允许空密码"; warnings=$((warnings + 1)); else ok "空密码登录已禁止"; fi
  value="$(ssh_effective_text_value maxauthtries <<< "$effective")"
  if is_uint_in_range "$value" 1 100 && (( 10#$value <= 4 )); then ok "最大认证尝试次数合理（${value}）"; else warn "最大认证尝试次数偏高或未知：${value:-未知}"; warnings=$((warnings + 1)); fi

  menu_section "密钥与权限"
  count="$(ssh_user_valid_key_count "$user")"
  if is_uint_in_range "$count" 1 100000; then ok "${user} 共发现 ${count} 个有效登录公钥"; else warn "${user} 未发现有效登录公钥"; warnings=$((warnings + 1)); fi
  while IFS= read -r path; do
    [[ -e "$path" ]] || continue
    if [[ -L "$path" || ! -f "$path" ]]; then
      warn "密钥路径不是普通文件：$path"
      warnings=$((warnings + 1))
    elif ssh_mode_is_group_world_writable "$path"; then
      warn "密钥文件可被组或其他用户写入：$path"
      warnings=$((warnings + 1))
    else
      print_kv "密钥权限" "$(stat -c '%a %U:%G' "$path" 2>/dev/null || echo 未知)  $path"
    fi
    owner="$(stat -c '%U' "$path" 2>/dev/null || true)"
    if [[ -n "$owner" && "$owner" != "$user" && "$owner" != "root" ]]; then
      warn "密钥文件所有者异常：${owner} / $path"
      warnings=$((warnings + 1))
    fi
    dir="$(dirname "$path")"
    if [[ "$dir" != "$(ssh_user_home "$user" 2>/dev/null || true)" ]]; then
      if ssh_mode_is_group_world_writable "$dir"; then
        warn "密钥目录可被组或其他用户写入：$dir"
        warnings=$((warnings + 1))
      fi
      owner="$(stat -c '%U' "$dir" 2>/dev/null || true)"
      if [[ -n "$owner" && "$owner" != "$user" && "$owner" != "root" ]]; then
        warn "密钥目录所有者异常：${owner} / $dir"
        warnings=$((warnings + 1))
      fi
    fi
  done < <(ssh_authorized_keys_paths "$user" 2>/dev/null || true)
  path="$(ssh_user_home "$user" 2>/dev/null || true)"
  if [[ -n "$path" ]] && ssh_mode_is_group_world_writable "$path"; then
    warn "用户家目录可被组或其他用户写入，StrictModes 可能拒绝密钥：$path"
    warnings=$((warnings + 1))
  fi
  owner="$(stat -c '%U' "$path" 2>/dev/null || true)"
  if [[ -n "$owner" && "$owner" != "$user" && "$owner" != "root" ]]; then
    warn "用户家目录所有者异常：${owner} / $path"
    warnings=$((warnings + 1))
  fi
  if [[ -f /etc/ssh/sshd_config ]] && ssh_mode_is_group_world_writable /etc/ssh/sshd_config; then
    warn "/etc/ssh/sshd_config 可被非 root 写入"
    warnings=$((warnings + 1))
  fi
  if [[ -f "$SSH_DROPIN_FILE" ]] && ssh_mode_is_group_world_writable "$SSH_DROPIN_FILE"; then
    warn "脚本管理的 SSH 配置可被非 root 写入：$SSH_DROPIN_FILE"
    warnings=$((warnings + 1))
  fi

  menu_section "体检结论"
  if (( warnings == 0 )); then
    ok "未发现常见 SSH 配置风险"
  else
    warn "共发现 ${warnings} 项需要关注；体检只读取状态，没有修改配置"
  fi
}

ssh_apply_recommended_hardening() {
  local user="${1:-root}" count=0 snapshot=""
  valid_username "$user" || { warn "用户名无效：$user"; return 1; }
  id "$user" >/dev/null 2>&1 || { warn "用户不存在：$user"; return 1; }
  ssh_pkg_install || return 1
  if ! ssh_user_login_shell_usable "$user"; then
    warn "${user} 的登录 Shell 不可用或被设为 nologin/false，已取消加固"
    return 1
  fi
  count="$(ssh_user_valid_key_count "$user")"
  if ! is_uint_in_range "$count" 1 100000; then
    warn "${user} 没有可验证的本地公钥"
    info "进入自动生成流程；私钥保存并安装成功后才能继续加固"
    ssh_generate_authorized_key "$user" || return 1
    count="$(ssh_user_valid_key_count "$user")"
    is_uint_in_range "$count" 1 100000 || { warn "仍未发现有效公钥，已取消加固"; return 1; }
  fi
  ssh_backup_once || return 1
  warn "将关闭所有用户的密码/交互认证，并保留公钥登录"
  info "同时禁止空密码、主机信任认证、用户环境变量与 X11 转发"
  warn "root 将只允许公钥；不会禁用 TCP 转发或 Agent 转发"
  warn "请保持当前会话，完成后另开窗口验证 ${user} 的密钥登录"
  if [[ "$user" != "root" ]] && ! id -nG "$user" 2>/dev/null | tr ' ' '\n' | grep -Eq '^(sudo|wheel)$'; then
    warn "${user} 未检测到 sudo/wheel 管理组；加固后可能无法执行管理操作"
  fi
  confirm_word "HARDEN" "确认加固请输入 HARDEN > " || { warn "已取消"; return 0; }
  ssh_repair_authorized_keys "$user" || { warn "密钥权限检查失败，未修改 SSH 策略"; return 1; }

  snapshot="$(ssh_managed_snapshot_create)" || { warn "无法创建本次 SSH 配置快照"; return 1; }
  ssh_apply_base_hardening || { ssh_managed_change_abort "$snapshot" "无法写入 SSH 加固配置"; return 1; }
  ssh_dropin_set_many \
    "PasswordAuthentication" "no" \
    "KbdInteractiveAuthentication" "no" \
    "ChallengeResponseAuthentication" "no" \
    "PubkeyAuthentication" "yes" \
    "PermitRootLogin" "prohibit-password" \
    "StrictModes" "yes" \
    "HostbasedAuthentication" "no" \
    "IgnoreRhosts" "yes" \
    "PermitUserEnvironment" "no" \
    "X11Forwarding" "no" || {
      ssh_managed_change_abort "$snapshot" "无法完整写入推荐加固配置"
      return 1
    }

  if ! ssh_validate_config || \
     ! ssh_verify_effective_setting "PasswordAuthentication" "no" "$user" || \
     ! ssh_verify_effective_setting "KbdInteractiveAuthentication" "no" "$user" || \
     ! ssh_verify_effective_setting "PubkeyAuthentication" "yes" "$user" || \
     ! ssh_verify_effective_setting "PermitRootLogin" "prohibit-password" "root" || \
     ! ssh_verify_authentication_path "publickey" "$user"; then
    ssh_managed_change_abort "$snapshot" "推荐加固策略未按预期生效"
    return 1
  fi
  ssh_managed_change_finish "$snapshot" || return 1
  ok "SSH 推荐加固已安全应用"
  info "请不要关闭当前会话；先另开终端验证：ssh -p $(ssh_current_ports | awk '{print $1}') ${user}@服务器IP"
}

ssh_login_activity() {
  local output=""
  menu_section "最近成功登录"
  if have_cmd last; then
    output="$(command_with_timeout 10 last -ai -n 15 2>/dev/null || command_with_timeout 10 last 2>/dev/null | sed -n '1,15p' || true)"
    [[ -n "$output" ]] && printf '%s\n' "$output" || info "没有可显示的 wtmp 登录记录"
  else
    warn "系统缺少 last 命令"
  fi

  menu_section "最近失败登录"
  if have_cmd lastb; then
    output="$(command_with_timeout 10 lastb -ai -n 15 2>/dev/null || true)"
    [[ -n "$output" ]] && printf '%s\n' "$output" || info "没有可显示的 btmp 失败记录"
  else
    info "系统没有 lastb，改查认证日志"
  fi

  menu_section "24 小时认证日志"
  output=""
  if have_cmd journalctl; then
    output="$(command_with_timeout 12 journalctl -u ssh.service -u sshd.service --since '-24 hours' --no-pager -n 200 2>/dev/null | grep -Ei 'Accepted|Failed|Invalid user|authentication failure|Disconnected from authenticating' | tail -n 40 || true)"
  fi
  if [[ -z "$output" ]]; then
    local log_file=""
    for log_file in /var/log/auth.log /var/log/secure; do
      [[ -r "$log_file" ]] || continue
      output="$(tail -n 500 "$log_file" 2>/dev/null | grep -Ei 'Accepted|Failed|Invalid user|authentication failure|Disconnected from authenticating' | tail -n 40 || true)"
      [[ -n "$output" ]] && break
    done
  fi
  [[ -n "$output" ]] && printf '%s\n' "$output" || info "最近 24 小时没有匹配的认证日志，或日志不可读"
  info "日志仅供排查；来源 IP 可能经过跳板机、NAT 或代理"
}

ssh_keys_menu() {
  while true; do
    menu_header "SSH 登录密钥" "自动生成 · 已有密钥导入 · 权限修复 · 防止误删最后密钥"
    menu_section "密钥管理"
    menu_item "1" "查看登录密钥" "列出指纹，不显示完整密钥内容"
    menu_item "2" "自动生成登录密钥" "默认方式；一次性显示私钥并自动安装公钥"
    menu_item "3" "导入已有公钥" "仅在已有本地密钥时使用，校验并自动去重"
    menu_item "4" "移除登录公钥" "按指纹选择，禁止删除最后一个密钥"
    menu_item "5" "修复密钥权限" ".ssh 目录 700、密钥文件 600，并移除路径写入风险"
    menu_back_item
    local c="" user="" key=""
    read_tty c "请输入编号 > " ""
    case "$c" in
      1)
        read_tty user "用户名（默认 root）> " "root"
        ssh_list_authorized_keys "$user" || true
        pause_up
        ;;
      2)
        read_tty user "用户名（默认 root）> " "root"
        ssh_generate_authorized_key "$user" || true
        pause_up
        ;;
      3)
        read_tty user "用户名（默认 root）> " "root"
        read_tty key "粘贴一整行 OpenSSH 公钥 > " ""
        ssh_add_authorized_key "$user" "$key" || true
        pause_up
        ;;
      4)
        read_tty user "用户名（默认 root）> " "root"
        ssh_remove_authorized_key "$user" || true
        pause_up
        ;;
      5)
        read_tty user "用户名（默认 root）> " "root"
        ssh_repair_authorized_keys "$user" || true
        pause_up
        ;;
      0|q|Q) return 0 ;;
      *) warn "无效选项"; pause_up ;;
    esac
  done
}

ssh_safe_enable_password_for_user_keep_root_key() {
  local user="${1:-dmit}" snapshot=""
  valid_username "$user" || { warn "用户名无效：$user"; return 1; }
  [[ "$user" != "root" ]] || { warn "此功能只创建普通用户；如需 root 密码，请选择“开启密码登录”"; return 1; }
  ssh_pkg_install || return 1
  ssh_backup_once || return 1

  warn "推荐模式：普通用户密码登录；root 禁止密码（仅密钥）"
  warn "密码认证属于全局开关：其他未被 SSH 策略禁止且已设置密码的普通账号也可能使用密码"
  warn "建议保持当前 SSH 会话不要断开，确认新用户可登录后再退出"

  local p; p="$(ssh_random_pass)"
  [[ -z "${p:-}" ]] && { warn "生成随机密码失败"; return 1; }

  snapshot="$(ssh_managed_snapshot_create)" || { warn "无法创建本次 SSH 配置快照"; return 1; }
  ssh_apply_base_hardening || { ssh_managed_change_abort "$snapshot" "无法写入 SSH 加固配置"; return 1; }
  ssh_dropin_set_many \
    "PasswordAuthentication" "yes" \
    "PubkeyAuthentication" "yes" \
    "PermitRootLogin" "prohibit-password" || {
      ssh_managed_change_abort "$snapshot" "无法完整写入 SSH 登录策略"
      return 1
    }

  if ! ssh_validate_config || \
     ! ssh_verify_effective_setting "PasswordAuthentication" "yes" "$user" || \
     ! ssh_verify_effective_setting "PubkeyAuthentication" "yes" "$user" || \
     ! ssh_verify_effective_setting "PermitRootLogin" "prohibit-password" "root" || \
     ! ssh_verify_authentication_path "any" "$user" || \
     ! ssh_verify_authentication_path "publickey" "root"; then
    ssh_managed_change_abort "$snapshot" "SSH 登录策略未按预期生效"
    return 1
  fi
  if ! ssh_create_user_with_password "$user" "$p"; then
    ssh_managed_change_abort "$snapshot" "用户或密码创建失败"
    return 1
  fi
  if ! ssh_managed_change_finish "$snapshot"; then
    warn "SSH 策略已回滚；已创建的 ${user} 账号及其密码不会被自动删除"
    return 1
  fi
  ok "SSH 已安全重新加载（推荐模式已生效）"
  sshd_status_hint
}

ssh_enable_password_keep_key_for_user() {
  local user="${1:-root}"
  local mode="${2:-random}" # random|custom
  local passwd="${3:-}" snapshot="" root_policy="prohibit-password"

  valid_username "$user" || { warn "用户名无效：$user"; return 1; }
  id "$user" >/dev/null 2>&1 || { warn "用户不存在：$user"; return 1; }
  ssh_user_login_shell_usable "$user" || { warn "${user} 的登录 Shell 不可用，已取消"; return 1; }
  ssh_pkg_install || return 1
  ssh_backup_once || return 1

  warn "中等模式：开启密码登录（保留密钥登录）"
  warn "密码认证属于全局开关；选择非 root 用户时，root 仍会保持禁止密码"
  warn "建议保持当前 SSH 会话不要断开，确认密码可登录后再退出"

  if [[ "$mode" == "random" ]]; then passwd="$(ssh_random_pass)"; fi
  [[ -z "${passwd:-}" ]] && { warn "密码为空：取消"; return 1; }

  snapshot="$(ssh_managed_snapshot_create)" || { warn "无法创建本次 SSH 配置快照"; return 1; }
  ssh_apply_base_hardening || { ssh_managed_change_abort "$snapshot" "无法写入 SSH 配置"; return 1; }
  if [[ "$user" == "root" ]]; then root_policy="yes"; fi
  ssh_dropin_set_many \
    "PasswordAuthentication" "yes" \
    "PubkeyAuthentication" "yes" \
    "PermitRootLogin" "$root_policy" || {
      ssh_managed_change_abort "$snapshot" "无法完整写入 SSH 登录策略"
      return 1
    }

  if ! ssh_validate_config || \
     ! ssh_verify_effective_setting "PasswordAuthentication" "yes" "$user" || \
     ! ssh_verify_effective_setting "PubkeyAuthentication" "yes" "$user" || \
     ! ssh_verify_effective_setting "PermitRootLogin" "$root_policy" "root" || \
     ! ssh_verify_authentication_path "any" "$user"; then
    ssh_managed_change_abort "$snapshot" "SSH 登录策略未按预期生效"
    return 1
  fi
  if [[ "$root_policy" != "yes" ]] && ! ssh_verify_authentication_path "publickey" "root"; then
    ssh_managed_change_abort "$snapshot" "root 公钥登录路径未按预期保留"
    return 1
  fi
  if ! ssh_set_user_password "$user" "$passwd"; then
    ssh_managed_change_abort "$snapshot" "用户密码设置失败"
    return 1
  fi
  ok "已设置用户密码：${user}"
  if [[ "$mode" == "random" ]]; then echo -e "${c_green}随机密码：${passwd}${c_reset}"; fi
  if ! ssh_managed_change_finish "$snapshot"; then
    warn "SSH 策略已回滚；${user} 的账号密码已经更新，请妥善保存"
    return 1
  fi
  if [[ "$user" == "root" ]]; then
    ok "SSH 已安全重新加载（root 密码与密钥均可）"
  else
    ok "SSH 已安全重新加载（${user} 可使用密码；root 仍仅允许密钥）"
  fi
  sshd_status_hint
}

ssh_password_only_disable_key_risky() {
  local user="${1:-root}"
  local mode="${2:-random}" # random|custom
  local passwd="${3:-}" snapshot="" root_policy="prohibit-password"

  valid_username "$user" || { warn "用户名无效：$user"; return 1; }
  id "$user" >/dev/null 2>&1 || { warn "用户不存在：$user"; return 1; }
  ssh_user_login_shell_usable "$user" || { warn "${user} 的登录 Shell 不可用，已取消"; return 1; }
  ssh_pkg_install || return 1
  ssh_backup_once || return 1

  warn "高风险模式：仅密码登录（禁用密钥）"
  warn "该设置会全局禁用 SSH 公钥认证，而不只影响所选用户"
  warn "有锁门风险：务必保持当前 SSH 会话不断开"
  local ans=""
  read_tty ans "确认继续请输入 YES > " ""
  if [[ "${ans}" != "YES" ]]; then
    warn "已取消"
    return 0
  fi

  if [[ "$mode" == "random" ]]; then passwd="$(ssh_random_pass)"; fi
  [[ -z "${passwd:-}" ]] && { warn "密码为空：取消"; return 1; }

  snapshot="$(ssh_managed_snapshot_create)" || { warn "无法创建本次 SSH 配置快照"; return 1; }
  ssh_apply_base_hardening || { ssh_managed_change_abort "$snapshot" "无法写入 SSH 配置"; return 1; }
  if [[ "$user" == "root" ]]; then root_policy="yes"; fi
  ssh_dropin_set_many \
    "PasswordAuthentication" "yes" \
    "PubkeyAuthentication" "no" \
    "PermitRootLogin" "$root_policy" || {
      ssh_managed_change_abort "$snapshot" "无法完整写入 SSH 登录策略"
      return 1
    }

  if ! ssh_validate_config || \
     ! ssh_verify_effective_setting "PasswordAuthentication" "yes" "$user" || \
     ! ssh_verify_effective_setting "PubkeyAuthentication" "no" "$user" || \
     ! ssh_verify_effective_setting "PermitRootLogin" "$root_policy" "root" || \
     ! ssh_verify_authentication_path "password" "$user"; then
    ssh_managed_change_abort "$snapshot" "SSH 登录策略未按预期生效"
    return 1
  fi
  if ! ssh_set_user_password "$user" "$passwd"; then
    ssh_managed_change_abort "$snapshot" "用户密码设置失败"
    return 1
  fi
  ok "已设置用户密码：${user}"
  if [[ "$mode" == "random" ]]; then echo -e "${c_green}随机密码：${passwd}${c_reset}"; fi
  if ! ssh_managed_change_finish "$snapshot"; then
    warn "SSH 策略已回滚；${user} 的账号密码已经更新，请妥善保存"
    return 1
  fi
  ok "SSH 已安全重新加载（仅密码登录）"
  sshd_status_hint
}

ssh_restore_snapshot_create() {
  local snapshot=""
  snapshot="$(mktemp -d /tmp/dmitbox-ssh-restore.XXXXXX)" || return 1
  mkdir -p "$snapshot/current" || { rm -rf -- "$snapshot"; return 1; }
  cp -a /etc/ssh/. "$snapshot/current/" || { rm -rf -- "$snapshot"; return 1; }
  printf '%s\n' "$snapshot"
}

ssh_restore_snapshot_discard() {
  local snapshot="${1:-}"
  [[ "$snapshot" == /tmp/dmitbox-ssh-restore.* && -d "$snapshot" ]] || return 0
  rm -rf -- "$snapshot"
}

ssh_restore_snapshot_apply() {
  local snapshot="$1" archive="$2" member="" relative="" target=""
  [[ "$snapshot" == /tmp/dmitbox-ssh-restore.* && -d "$snapshot/current" ]] || return 1
  ssh_backup_archive_safe "$archive" || return 1
  while IFS= read -r member; do
    [[ "$member" == etc/ssh/* ]] || continue
    relative="${member#etc/ssh/}"
    [[ -n "$relative" && "$relative" != */ ]] || continue
    if [[ ! -e "$snapshot/current/$relative" && ! -L "$snapshot/current/$relative" ]]; then
      target="/etc/ssh/$relative"
      [[ -f "$target" && ! -L "$target" ]] && rm -f -- "$target" || true
    fi
  done < <(tar -tzf "$archive" 2>/dev/null)
  cp -a "$snapshot/current/." /etc/ssh/
}

ssh_restore_key_login() {
  local snapshot=""
  info "SSH：恢复原来的配置（从备份还原）"
  if [[ -s "$SSH_ORIG_TGZ" ]]; then
    [[ -d /etc/ssh && ! -L /etc/ssh ]] || { warn "/etc/ssh 不是可安全恢复的普通目录"; return 1; }
    [[ ! -e "$SSH_DROPIN_DIR" || ( -d "$SSH_DROPIN_DIR" && ! -L "$SSH_DROPIN_DIR" ) ]] || {
      warn "sshd_config.d 不是可安全恢复的普通目录"
      return 1
    }
    have_cmd find || { warn "系统缺少 find，无法安全检查 SSH 恢复路径"; return 1; }
    if [[ -n "$(find /etc/ssh -type l -print -quit 2>/dev/null || true)" ]]; then
      warn "/etc/ssh 中存在符号链接，为避免恢复越界，已取消恢复"
      return 1
    fi
    if ! ssh_backup_archive_safe "$SSH_ORIG_TGZ"; then
      warn "SSH 备份损坏或包含越界路径，未执行恢复：$SSH_ORIG_TGZ"
      return 1
    fi
    snapshot="$(ssh_restore_snapshot_create)" || { warn "无法创建恢复前快照，已取消恢复"; return 1; }
    rm -f "$SSH_DROPIN_FILE" "$SSH_LEGACY_DROPIN_FILE" 2>/dev/null || true
    if ! tar -xzf "$SSH_ORIG_TGZ" -C / 2>/dev/null; then
      warn "SSH 配置解压失败，正在恢复操作前配置"
      ssh_restore_snapshot_apply "$snapshot" "$SSH_ORIG_TGZ" || warn "自动恢复操作前配置失败，请立即人工检查"
      ssh_restore_snapshot_discard "$snapshot"
      return 1
    fi
    ssh_backup_archive_has_member "$SSH_ORIG_TGZ" "${SSH_DROPIN_FILE#/}" || rm -f "$SSH_DROPIN_FILE" 2>/dev/null || true
    ssh_backup_archive_has_member "$SSH_ORIG_TGZ" "${SSH_LEGACY_DROPIN_FILE#/}" || rm -f "$SSH_LEGACY_DROPIN_FILE" 2>/dev/null || true
    if ! ssh_validate_config; then
      warn "备份配置未通过 sshd -t，正在恢复操作前配置"
      ssh_restore_snapshot_apply "$snapshot" "$SSH_ORIG_TGZ" || warn "自动恢复操作前配置失败，请立即人工检查"
      ssh_restore_snapshot_discard "$snapshot"
      return 1
    fi
    if ! sshd_restart; then
      warn "SSH 服务未能加载备份配置，正在恢复操作前配置"
      if ssh_restore_snapshot_apply "$snapshot" "$SSH_ORIG_TGZ"; then
        sshd_restart >/dev/null 2>&1 || warn "操作前配置已恢复，但 SSH 服务未能自动重新加载"
      else
        warn "自动恢复操作前配置失败，请保持当前会话并立即人工检查"
      fi
      ssh_restore_snapshot_discard "$snapshot"
      return 1
    fi
    ssh_restore_snapshot_discard "$snapshot"
    ok "已恢复 SSH 原始配置并安全重新加载"
    sshd_status_hint
  else
    warn "未找到备份：$SSH_ORIG_TGZ"
  fi
}

ssh_current_ports() {
  if have_cmd sshd; then
    sshd -T 2>/dev/null | awk '$1=="port"{print $2}' | tr '\n' ' ' | sed 's/[[:space:]]*$//'
    return 0
  fi
  local ports=""
  ports="$(grep -RihE '^[[:space:]]*Port[[:space:]]+' /etc/ssh/sshd_config /etc/ssh/sshd_config.d 2>/dev/null | awk '{print $2}' | tr '\n' ' ' | sed 's/[[:space:]]*$//')"
  echo "${ports:-22}"
}

port_in_use() {
  local p="$1"
  if have_cmd ss; then
    ss -lntp 2>/dev/null | awk '{print $4}' | grep -Eq "[:.]${p}$" && return 0
  elif have_cmd netstat; then
    netstat -lntp 2>/dev/null | awk '{print $4}' | grep -Eq "[:.]${p}$" && return 0
  fi
  return 1
}

firewall_open_port_best_effort() {
  local p="$1" backend="" rc=0 zone="-" netfilter_risk="none"
  is_uint_in_range "$p" 1 65535 || return 1
  p=$((10#$p))
  backend="$(common_firewall_active_backend)" || rc=$?
  if (( rc == 2 )); then
    warn "UFW 与 firewalld 同时启用，无法安全放行 SSH 新端口"
    return 1
  fi
  if (( rc != 0 )); then
    netfilter_risk="$(common_firewall_netfilter_risk)"
    case "$netfilter_risk" in
      input|unknown)
        warn "已有规则可能影响本机入站，脚本不会向未知链盲目插入规则"
        common_firewall_netfilter_show_inventory
        info "请先在“常用防火墙”中完成安全启用，或人工在原规则中放行 ${p}/tcp"
        return 1
        ;;
      forwarding)
        info "只检测到转发/NAT/输出规则，不负责拦截本机 INPUT"
        info "当前没有启用中的本机防火墙，无需新增 ${p}/tcp 放行规则"
        return 0
        ;;
      *)
        info "未启用本机防火墙，无需新增 ${p}/tcp 放行规则"
        return 0
        ;;
    esac
  fi
  if [[ "$backend" == "firewalld" ]]; then
    zone="$(common_firewall_firewalld_zone)" || { warn "无法确定 firewalld 入站区域"; return 1; }
  fi
  common_firewall_apply_rule "$backend" allow-port tcp "$p" - "$zone" || return 1
  ok "${backend} 已允许 SSH 新端口：${p}/tcp"
}

ssh_set_port() {
  local newp="$1" snapshot="" attempt=0

  is_uint_in_range "$newp" 1 65535 || { warn "端口必须是 1-65535 的数字"; return 1; }
  newp=$((10#$newp))
  if (( newp < 1024 )); then warn "不建议使用 1024 以下端口"; fi

  local cur_ports; cur_ports="$(ssh_current_ports || echo "22")"
  if echo " $cur_ports " | grep -q " ${newp} "; then
    warn "端口 ${newp} 已在 SSH 当前配置中"
    return 0
  fi

  if port_in_use "$newp"; then
    warn "端口 ${newp} 似乎已被占用（请换一个）"
    return 1
  fi

  ssh_pkg_install || return 1
  ssh_backup_once || return 1

  warn "更换 SSH 端口会影响新连接"
  warn "强烈建议保持当前 SSH 会话不要断开"
  warn "请先测试：ssh -p ${newp} user@你的IP"

  if ! firewall_open_port_best_effort "$newp"; then
    warn "无法确认防火墙已放行新端口，SSH 配置未修改"
    return 1
  fi
  ssh_socket_disable_if_any || return 1
  snapshot="$(ssh_managed_snapshot_create)" || { warn "无法创建本次 SSH 配置快照"; return 1; }
  ssh_dropin_ensure || { ssh_managed_change_abort "$snapshot" "无法准备 SSH drop-in"; return 1; }
  ssh_dropin_set_kv "Port" "$newp" || { ssh_managed_change_abort "$snapshot" "无法写入 SSH 新端口"; return 1; }

  if ! ssh_validate_config || ! ssh_verify_effective_setting "Port" "$newp" "root"; then
    ssh_managed_change_abort "$snapshot" "SSH 新端口未通过配置验证"
    return 1
  fi
  ssh_managed_change_finish "$snapshot" 1 || return 1
  for ((attempt=1; attempt<=8; attempt++)); do
    port_in_use "$newp" && break
    sleep 1
  done
  if ! port_in_use "$newp"; then
    ssh_managed_change_abort "$snapshot" "SSH 服务重新加载后仍未监听 ${newp}/tcp"
    return 1
  fi
  ssh_managed_snapshot_discard "$snapshot"
  ok "SSH 已切换并确认监听新端口 → ${newp}"

  echo -e "${c_dim}--- 立即验证 ---${c_reset}"
  sshd -T 2>/dev/null | grep -Ei 'port|passwordauthentication|permitrootlogin|pubkeyauthentication|authenticationmethods' || true
  ss -lntp 2>/dev/null | grep -E "sshd|:${newp}\b|:22\b" || true

  echo -e "${c_green}提示：请用新端口测试登录成功后，再退出当前会话${c_reset}"
  echo -e "${c_dim}当前端口：$(ssh_current_ports)${c_reset}"
}

ssh_menu() {
  while true; do
    menu_header "SSH 安全" "安全体检 · 密钥管理 · 防锁死加固 · 登录审计"
    menu_section "检查与记录"
    menu_item "1" "SSH 安全体检" "配置语法、认证风险、监听与密钥权限"
    menu_item "2" "查看生效配置" "按指定用户计算最终认证策略"
    menu_item "3" "最近登录记录" "成功、失败与近 24 小时认证日志"
    menu_section "密钥与加固"
    menu_item "4" "登录密钥管理" "查看、添加、移除与权限修复"
    menu_item "5" "一键推荐加固" "验证公钥后关闭密码认证，失败自动回滚"
    menu_item "6" "创建普通用户" "普通用户密码登录，root 保持仅密钥"
    menu_item "7" "开启密码登录" "保留公钥；非 root 操作不放开 root 密码"
    menu_section "连接与恢复"
    menu_item "8" "更换 SSH 端口" "验证监听并安全处理常用防火墙"
    menu_item "9" "恢复原始配置" "从首次修改前的备份还原"
    menu_section "高风险"
    menu_item "10" "仅密码登录" "禁用公钥，可能导致无法登录"
    menu_back_item
    local c=""
    read_tty c "请输入编号 > " ""
    case "$c" in
      1)
        local u=""
        read_tty u "检查用户（默认 root）> " "root"
        ssh_security_audit "$u" || true
        pause_up
        ;;
      2)
        local u=""
        read_tty u "检查用户（默认 root）> " "root"
        ssh_show_effective_configuration "$u" || true
        pause_up
        ;;
      3) ssh_login_activity || true; pause_up ;;
      4) ssh_keys_menu ;;
      5)
        local u=""
        read_tty u "确保可用公钥的用户（默认 root）> " "root"
        ssh_apply_recommended_hardening "$u" || true
        pause_up
        ;;
      6)
        local u=""
        read_tty u "新用户名（默认 dmit）> " "dmit"
        ssh_safe_enable_password_for_user_keep_root_key "$u" || true
        pause_up
        ;;
      7)
        local u="" m="" p=""
        read_tty u "用户名（默认 root）> " "root"
        echo "  1) 随机密码"
        echo "  2) 自定义密码"
        read_tty m "选择> " ""
        if [[ "$m" == "1" ]]; then
          ssh_enable_password_keep_key_for_user "$u" "random" "" || true
        elif [[ "$m" == "2" ]]; then
          read_tty_secret p "设置密码（输入不回显）> "
          ssh_enable_password_keep_key_for_user "$u" "custom" "$p" || true
        else
          warn "无效选项"
        fi
        pause_up
        ;;
      8)
        echo -e "${c_dim}当前 SSH 端口：$(ssh_current_ports)${c_reset}"
        local p=""
        read_tty p "输入新端口（建议 20000-59999）> " ""
        ssh_set_port "$p" || true
        pause_up
        ;;
      9)
        if confirm_word "RESTORE" "确认恢复首次备份请输入 RESTORE > "; then
          ssh_restore_key_login || true
        else
          warn "已取消"
        fi
        pause_up
        ;;
      10)
        local u="" m="" p=""
        read_tty u "用户名（默认 root）> " "root"
        echo "  1) 随机密码"
        echo "  2) 自定义密码"
        read_tty m "选择> " ""
        if [[ "$m" == "1" ]]; then
          ssh_password_only_disable_key_risky "$u" "random" "" || true
        elif [[ "$m" == "2" ]]; then
          read_tty_secret p "设置密码（输入不回显）> "
          ssh_password_only_disable_key_risky "$u" "custom" "$p" || true
        else
          warn "无效选项"
        fi
        pause_up
        ;;
      0|q|Q) return 0 ;;
      *) warn "无效选项"; pause_up ;;
    esac
  done
}

# ---------------- 测试：运行外部脚本 ----------------
remote_script_duration_text() {
  local seconds="${1:-600}"
  is_uint_in_range "$seconds" 1 86400 || seconds=600
  if (( seconds % 60 == 0 )); then
    printf '%s 分钟\n' "$((seconds / 60))"
  else
    printf '%s 秒\n' "$seconds"
  fi
}

remote_script_ensure_dependencies() {
  local cmd="$1" item="" label=""
  local missing_packages=() missing_commands=()
  if [[ "$cmd" == *curl* ]] && ! have_cmd curl; then
    missing_packages+=(curl); missing_commands+=(curl)
  fi
  if [[ "$cmd" == *wget* ]] && ! have_cmd wget; then
    missing_packages+=(wget); missing_commands+=(wget)
  fi
  if ! have_cmd bash; then
    missing_packages+=(bash); missing_commands+=(bash)
  fi
  if ! have_cmd timeout; then
    missing_packages+=(coreutils); missing_commands+=(timeout)
  fi

  if (( ${#missing_packages[@]} == 0 )); then
    ok "运行环境已就绪，无需安装依赖"
    return 0
  fi

  for item in "${missing_commands[@]}"; do
    if [[ -n "$label" ]]; then label+=", "; fi
    label+="$item"
  done
  info "缺少运行依赖：${label}；将合并安装一次"
  pkg_install "${missing_packages[@]}"
  for item in "${missing_commands[@]}"; do
    have_cmd "$item" || { warn "${item} 安装失败，已取消测试"; return 1; }
  done
}

remote_script_timeout_supports_foreground() {
  have_cmd timeout || return 1
  timeout --help 2>&1 | grep -q -- '--foreground'
}

remote_script_execute() {
  local cmd="$1" max_seconds="$2" task_label="${3:-测试}" rc=0 interrupted=0 previous_int=""
  is_uint_in_range "$max_seconds" 1 86400 || max_seconds=900
  previous_int="$(trap -p INT || true)"
  trap 'interrupted=1' INT

  if remote_script_timeout_supports_foreground; then
    timeout --foreground --signal=TERM --kill-after=10 "$max_seconds" \
      bash -o pipefail -lc "$cmd" </dev/tty || rc=$?
  elif have_cmd timeout; then
    timeout "$max_seconds" bash -o pipefail -lc "$cmd" </dev/tty || rc=$?
  else
    bash -o pipefail -lc "$cmd" </dev/tty || rc=$?
  fi

  # Third-party scripts sometimes leave echo/canonical mode or ANSI state
  # changed. Restore a usable terminal before showing the toolbox prompt.
  if has_tty && have_cmd stty; then
    stty sane </dev/tty >/dev/tty 2>&1 || true
  fi
  printf '%b' "$c_reset" 2>/dev/null || true
  trap - INT
  [[ -n "$previous_int" ]] && eval "$previous_int"
  if (( interrupted == 1 || rc == 130 )); then
    warn "已中断本次${task_label}；即将返回工具箱"
    return 130
  fi
  if (( rc == 124 || rc == 137 || rc == 143 )); then
    warn "${task_label}超过最长运行时间，已自动停止；即将返回工具箱"
    return 124
  fi
  return "$rc"
}

run_remote_script() {
  local title="$1"
  local cmd="$2"
  local note="${3:-}"
  local max_seconds="${4:-900}" answer="" rc=0
  is_uint_in_range "$max_seconds" 30 86400 || max_seconds=900

  echo
  echo -e "${c_bold}${c_white}${title}${c_reset}"
  [[ -n "$note" ]] && echo -e "${c_yellow}${note}${c_reset}"
  echo -e "${c_dim}执行命令：${cmd}${c_reset}"
  warn "注意：这会从网络拉取并运行脚本（请自行确认来源可信）"
  info "预计耗时取决于网络和测试项目，最长运行 $(remote_script_duration_text "$max_seconds")"
  info "运行期间可能暂时没有输出；按 Ctrl+C 只中断本次测试并返回工具箱"

  if ! has_tty; then
    warn "当前无可交互 TTY（可能是 curl|bash 场景 / 无 -t 终端），为安全起见：已取消执行"
    return 0
  fi
  read_tty answer "按回车开始，输入 q 取消 > " ""
  [[ "$answer" != "q" && "$answer" != "Q" ]] || { info "已取消测试"; return 0; }

  remote_script_ensure_dependencies "$cmd" || return 1
  echo
  info "${title}正在运行，请稍候……"
  remote_script_execute "$cmd" "$max_seconds" || rc=$?
  if (( rc != 0 )); then
    if (( rc != 124 && rc != 130 )); then
      warn "${title}执行失败（退出码：${rc}）；即将返回工具箱"
    fi
    return "$rc"
  fi
  ok "${title}执行完成"
}

tests_menu() {
  while true; do
    menu_header "性能与网络测试" "外部测试脚本将在执行前再次确认"
    menu_section "性能"
    menu_item "1" "Geekbench 5" "CPU 性能测试"
    menu_item "2" "Bench.sh" "系统与网络综合测试"
    menu_section "网络"
    menu_item "3" "三网回程" "路由结果仅供参考"
    menu_item "4" "TcpQuality" "全国三网 TCP 质量检测"
    menu_item "5" "NodeQuality" "节点综合质量测试"
    menu_item "6" "Telegram 延迟" "TG 数据中心延迟测试"
    menu_item "7" "流媒体解锁" "检测常见流媒体可用性"
    menu_back_item
    local c=""
    read_tty c "请输入编号 > " ""
    case "$c" in
      1) run_remote_script "GB5 性能测试"  "bash <(wget -qO- --timeout=15 --tries=2 https://raw.githubusercontent.com/i-abc/GB5/main/gb5-test.sh)" "" 1800 || true; pause_up ;;
      2) run_remote_script "Bench 综合测试" "bash <(curl -fsSL --connect-timeout 10 --max-time 60 --retry 2 https://bench.sh)" "" 1800 || true; pause_up ;;
      3) run_remote_script "三网回程测试" "bash <(curl -fsSL --connect-timeout 10 --max-time 60 --retry 2 https://raw.githubusercontent.com/ludashi2020/backtrace/main/install.sh)" "备注：路由结果仅供参考" 900 || true; pause_up ;;
      4) run_remote_script "TcpQuality（TCP 质量检测）" "curl -fsSL --connect-timeout 10 --max-time 60 --retry 2 https://raw.githubusercontent.com/ibsgss/TcpQuality/main/runTcpQuality.sh | env TERM=xterm bash" "" 1800 || true; pause_up ;;
      5) run_remote_script "NodeQuality 测试" "bash <(curl -fsSL --connect-timeout 10 --max-time 60 --retry 2 https://run.NodeQuality.com)" "" 1800 || true; pause_up ;;
      6) run_remote_script "Telegram 延迟测试" "bash <(curl -fsSL --connect-timeout 10 --max-time 60 --retry 2 https://sub.777337.xyz/tgdc.sh)" "" 300 || true; pause_up ;;
      7) run_remote_script "流媒体解锁检测" "bash <(curl -fsSL --connect-timeout 10 --max-time 60 --retry 2 https://raw.githubusercontent.com/lmc999/RegionRestrictionCheck/main/check.sh)" "来源：lmc999/RegionRestrictionCheck（GitHub）" 600 || true; pause_up ;;
      0|q|Q) return 0 ;;
      *) warn "无效选项"; pause_up ;;
    esac
  done
}

# ---------------- 一键DD重装系统 ----------------
dd_reinstall() {
  if ! has_tty; then
    warn "当前无可交互 TTY（可能是 curl|bash 场景），为安全起见：已取消"
    return 0
  fi

  local c="" flag="" ver="" port="" mode="" pwd=""
  menu_header "DD 重装系统" "InstallNET.sh · 此操作将清空系统盘"
  warn "风险极高：建议先准备 VNC、救援模式或面板控制台"
  warn "开始后 SSH 可能中断"
  menu_section "Debian / Ubuntu"
  menu_item "1" "Debian 11"
  menu_item "2" "Debian 12"
  menu_item "3" "Debian 13"
  menu_item "4" "Ubuntu 22.04"
  menu_item "5" "Ubuntu 24.04"
  menu_section "其他发行版"
  menu_item "6" "CentOS 7"
  menu_item "7" "CentOS 8"
  menu_item "8" "Rocky Linux 9"
  menu_item "9" "AlmaLinux 9"
  menu_item "10" "Alpine edge"
  menu_back_item
  read_tty c "请输入编号 > " ""
  case "$c" in
    1)  flag="-debian";     ver="11" ;;
    2)  flag="-debian";     ver="12" ;;
    3)  flag="-debian";     ver="13" ;;
    4)  flag="-ubuntu";     ver="22.04" ;;
    5)  flag="-ubuntu";     ver="24.04" ;;
    6)  flag="-centos";     ver="7" ;;
    7)  flag="-centos";     ver="8" ;;
    8)  flag="-rockylinux"; ver="9" ;;
    9)  flag="-almalinux";  ver="9" ;;
    10) flag="-alpine";     ver="edge" ;;
    0|q|Q) return 0 ;;
    *) warn "无效选项"; return 0 ;;
  esac

  local cur_port
  cur_port="$(ssh_current_ports | awk '{print $1}' || true)"
  cur_port="${cur_port:-22}"
  read_tty port "SSH 端口（默认 ${cur_port}）> " "$cur_port"
  is_uint_in_range "$port" 1 65535 || { warn "SSH 端口必须是 1-65535 的数字"; return 0; }
  port=$((10#$port))

  echo
  echo "  1) 随机密码"
  echo "  2) 自定义密码"
  read_tty mode "选择> " "1"
  if [[ "$mode" == "1" ]]; then
    pwd="K$(ssh_random_pass)"
    (( ${#pwd} >= 12 )) || { warn "随机密码生成失败"; return 1; }
  elif [[ "$mode" == "2" ]]; then
    read_tty_secret pwd "设置密码（输入不回显）> "
    [[ -n "${pwd:-}" ]] || { warn "密码不能为空"; return 0; }
  else
    warn "无效选项"
    return 0
  fi

  echo
  echo -e "${c_bold}${c_white}即将执行（确认信息）${c_reset}"
  echo -e "系统：${flag} ${ver}"
  echo -e "SSH端口：${port}"
  echo -e "root密码：${c_green}${pwd}${c_reset}"
  echo -e "${c_yellow}⚠ 数据将被清空！${c_reset}"
  echo
  local ans=""
  read_tty ans "确认继续请输入 DD > " ""
  if [[ "$ans" != "DD" ]]; then
    warn "已取消"
    return 0
  fi

  if have_cmd apt-get; then
    apt-get -y update >/dev/null 2>&1 || true
    apt-get -y install wget >/dev/null 2>&1 || true
  elif have_cmd yum; then
    yum -y install wget >/dev/null 2>&1 || true
  elif have_cmd dnf; then
    dnf -y install wget >/dev/null 2>&1 || true
  elif have_cmd apk; then
    apk update >/dev/null 2>&1 || true
    apk add bash wget >/dev/null 2>&1 || true
    sed -i 's/root:\/bin\/ash/root:\/bin\/bash/g' /etc/passwd 2>/dev/null || true
  fi

  info "下载 InstallNET.sh..."
  have_cmd wget || { warn "wget 安装失败，已取消 DD"; return 1; }
  if ! wget --no-check-certificate -qO /tmp/InstallNET.sh 'https://raw.githubusercontent.com/leitbogioro/Tools/master/Linux_reinstall/InstallNET.sh'; then
    warn "InstallNET.sh 下载失败，未开始重装"
    return 1
  fi
  [[ -s /tmp/InstallNET.sh ]] || { warn "下载文件为空，未开始重装"; return 1; }
  chmod a+x /tmp/InstallNET.sh || { warn "无法设置执行权限，未开始重装"; return 1; }

  warn "开始执行重装脚本（可能会进入安装流程/重启）"
  bash /tmp/InstallNET.sh "${flag}" "${ver}" -port "${port}" -pwd "${pwd}" || true
}

# ======================================================================
# 系统状态 / 进程 / 端口
# ======================================================================
system_overview() {
  menu_header "系统状态总览" "硬件资源 · 网络接口 · 磁盘与运行状态"

  local cpu_model="" cpu_count="" virt="" uptime_text="" load_text=""
  local ifc="" rx="0" tx="0" timezone="" time_sync="N/A"
  cpu_model="$(awk -F: '/model name|Hardware|Processor/{gsub(/^[[:space:]]+/, "", $2); print $2; exit}' /proc/cpuinfo 2>/dev/null || true)"
  cpu_count="$(getconf _NPROCESSORS_ONLN 2>/dev/null || nproc 2>/dev/null || echo N/A)"
  virt="$(systemd-detect-virt 2>/dev/null || true)"
  uptime_text="$(uptime -p 2>/dev/null || awk '{printf "%.1f 天", $1/86400}' /proc/uptime 2>/dev/null || echo N/A)"
  load_text="$(awk '{print $1 " / " $2 " / " $3}' /proc/loadavg 2>/dev/null || echo N/A)"
  timezone="$(timedatectl show -p Timezone --value 2>/dev/null || cat /etc/timezone 2>/dev/null || echo N/A)"
  time_sync="$(time_sync_status_text 2>/dev/null || echo N/A)"
  ifc="$(default_iface)"
  [[ -r "/sys/class/net/${ifc}/statistics/rx_bytes" ]] && rx="$(cat "/sys/class/net/${ifc}/statistics/rx_bytes")"
  [[ -r "/sys/class/net/${ifc}/statistics/tx_bytes" ]] && tx="$(cat "/sys/class/net/${ifc}/statistics/tx_bytes")"

  menu_section "系统"
  print_kv "操作系统" "$(os_pretty_name)"
  print_kv "内核" "$(uname -r) ($(uname -m))"
  print_kv "虚拟化" "${virt:-none}"
  print_kv "CPU" "${cpu_model:-N/A}"
  print_kv "CPU 线程" "$cpu_count"
  print_kv "运行时间" "$uptime_text"
  print_kv "系统负载" "$load_text"
  print_kv "时区 / 时间同步" "${timezone} / ${time_sync}"

  menu_section "内存与 Swap"
  if have_cmd free; then
    free -h
  else
    sed -n '1,8p' /proc/meminfo 2>/dev/null || true
  fi

  menu_section "磁盘容量"
  df -hT -x tmpfs -x devtmpfs 2>/dev/null | sed -n '1,18p' || df -h 2>/dev/null || true
  echo
  echo -e "${c_dim}inode 使用率：${c_reset}"
  df -ih -x tmpfs -x devtmpfs 2>/dev/null | sed -n '1,18p' || true

  menu_section "网络"
  print_kv "默认网卡" "$ifc"
  print_kv "累计接收 / 发送" "$(human_bytes "$rx") / $(human_bytes "$tx")"
  print_kv "TCP 拥塞控制" "$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || echo N/A)"
  ip -br address show 2>/dev/null || true
  echo
  ip -4 route show default 2>/dev/null || true
  ip -6 route show default 2>/dev/null || true
}

processes_top_cpu() {
  menu_header "CPU 占用进程" "按当前 CPU 使用率排序，显示前 15 项"
  if have_cmd ps; then
    local output=""
    output="$(ps -eo pid,ppid,user,stat,%cpu,%mem,etime,comm --sort=-%cpu 2>/dev/null || true)"
    if [[ -n "$output" ]]; then
      sed -n '1,16p' <<< "$output"
    else
      warn "当前 ps 不支持排序参数，显示基础进程列表"
      ps 2>/dev/null | sed -n '1,16p' || true
    fi
  else
    warn "系统没有 ps 命令"
  fi
}

processes_top_memory() {
  menu_header "内存占用进程" "按当前内存使用率排序，显示前 15 项"
  if have_cmd ps; then
    local output=""
    output="$(ps -eo pid,ppid,user,stat,%mem,rss,etime,comm --sort=-%mem 2>/dev/null || true)"
    if [[ -n "$output" ]]; then
      sed -n '1,16p' <<< "$output"
    else
      warn "当前 ps 不支持排序参数，显示基础进程列表"
      ps 2>/dev/null | sed -n '1,16p' || true
    fi
  else
    warn "系统没有 ps 命令"
  fi
}

listening_ports() {
  menu_header "监听端口" "TCP / UDP 监听地址、PID 与程序"
  if have_cmd ss; then
    ss -lntup 2>/dev/null || ss -lntu 2>/dev/null || true
  elif have_cmd netstat; then
    netstat -lntup 2>/dev/null || netstat -lntu 2>/dev/null || true
  else
    warn "缺少 ss/netstat；可安装 iproute2 或 net-tools"
  fi
}

port_lookup() {
  local port="" output=""
  read_tty port "输入端口（1-65535）> " ""
  is_uint_in_range "$port" 1 65535 || { warn "端口必须在 1-65535 之间"; return 1; }
  port=$((10#$port))

  menu_header "端口 ${port} 诊断" "查看监听程序及相关连接"
  if have_cmd ss; then
    output="$(ss -H -lntup "sport = :${port}" 2>/dev/null || true)"
    if [[ -n "$output" ]]; then
      echo "$output"
    else
      warn "未发现监听 ${port} 端口的程序"
    fi
    echo
    echo -e "${c_dim}相关 TCP 连接：${c_reset}"
    ss -H -ntup 2>/dev/null | grep -E "[:.]${port}([[:space:]]|$)" | sed -n '1,80p' || true
  elif have_cmd netstat; then
    output="$(netstat -lntup 2>/dev/null | grep -E "[:.]${port}[[:space:]]" || true)"
    if [[ -n "$output" ]]; then echo "$output"; else warn "未发现监听 ${port} 端口的程序"; fi
  else
    warn "缺少 ss/netstat，无法诊断端口"
    return 1
  fi
}

port_listener_for_protocol() {
  local port="$1" protocol="$2" output=""
  [[ "$protocol" == "tcp" || "$protocol" == "udp" ]] || return 1
  if have_cmd ss; then
    if [[ "$protocol" == "tcp" ]]; then
      output="$(ss -H -ltnp "sport = :${port}" 2>/dev/null || true)"
      [[ -n "$output" ]] || output="$(ss -H -ltnp 2>/dev/null | awk -v port="$port" '$4 ~ (":" port "$")' || true)"
    else
      output="$(ss -H -lunp "sport = :${port}" 2>/dev/null || true)"
      [[ -n "$output" ]] || output="$(ss -H -lunp 2>/dev/null | awk -v port="$port" '$4 ~ (":" port "$")' || true)"
    fi
    printf '%s\n' "$output" | awk 'NF'
  elif have_cmd netstat; then
    if [[ "$protocol" == "tcp" ]]; then
      netstat -lntp 2>/dev/null | awk -v port="$port" '$4 ~ (":" port "$")'
    else
      netstat -lnup 2>/dev/null | awk -v port="$port" '$4 ~ (":" port "$")'
    fi
  fi
}

port_listener_is_loopback_only() {
  local output="$1" port="$2" line="" local_address="" found=0
  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    # ss/netstat place the local address in column 4 when one protocol is queried.
    local_address="$(awk '{print $4}' <<< "$line")"
    [[ -n "$local_address" ]] || continue
    found=1
    case "$local_address" in
      127.*:"$port"|"[::1]:${port}"|"::1:${port}"|localhost:"$port") ;;
      *) return 1 ;;
    esac
  done <<< "$output"
  (( found == 1 ))
}

firewall_allow_port_safe() {
  local port="$1" protocol="${2:-tcp}" backend="" backend_rc=0 zone="-" netfilter_risk="none"
  is_uint_in_range "$port" 1 65535 || return 1
  [[ "$protocol" == "tcp" || "$protocol" == "udp" ]] || return 1
  port=$((10#$port))

  # Remove only the named rules created by old DMITBox site guards.  Never
  # flush a user's nftables/iptables ruleset.
  secure_site_guard_remove_firewall_rules || return 1

  backend="$(common_firewall_active_backend)" || backend_rc=$?
  if (( backend_rc == 2 )); then
    warn "UFW 与 firewalld 同时启用，已拒绝修改"
    return 2
  fi
  if (( backend_rc != 0 )); then
    netfilter_risk="$(common_firewall_netfilter_risk)"
    case "$netfilter_risk" in
      input|unknown)
        warn "已有规则可能影响本机入站；脚本不会向未知链盲目插入规则"
        common_firewall_netfilter_show_inventory
        return 2
        ;;
      forwarding)
        info "只检测到转发/NAT/输出规则，不会拦截本机监听端口"
        info "未发现启用中的本机防火墙；无需新增本机放行规则"
        return 0
        ;;
      *)
        info "未发现启用中的本机防火墙；无需新增本机放行规则"
        return 0
        ;;
    esac
  fi
  if [[ "$backend" == "firewalld" ]]; then
    zone="$(common_firewall_firewalld_zone)" || { warn "无法确定 firewalld 入站区域"; return 1; }
  fi
  common_firewall_apply_rule "$backend" allow-port "$protocol" "$port" - "$zone" || {
    warn "${backend} 放行失败"
    return 1
  }
  ok "${backend} 已放行 ${port}/${protocol}"
}

port_access_repair() {
  local port="" protocol="tcp" output="" had_legacy=0
  menu_header "端口访问修复" "监听地址 · 旧版规则 · 本机防火墙"
  read_tty port "输入无法访问的端口（1-65535）> " ""
  is_uint_in_range "$port" 1 65535 || { warn "端口必须在 1-65535 之间"; return 1; }
  port=$((10#$port))
  read_tty protocol "协议 tcp/udp（默认 tcp）> " "tcp"
  protocol="${protocol,,}"
  [[ "$protocol" == "tcp" || "$protocol" == "udp" ]] || { warn "协议只能是 tcp 或 udp"; return 1; }

  if secure_site_legacy_firewall_present; then
    had_legacy=1
    warn "发现旧版建站功能遗留的防火墙拦截规则"
  fi
  if ! secure_site_guard_remove_firewall_rules; then
    warn "旧版 DMITBox 规则未能完整清理，已停止"
    return 1
  fi
  if (( had_legacy == 1 )); then
    ok "已删除旧版 dmitbox_cdn_guard / DMITBOX_CDN_GUARD 规则"
  else
    ok "未发现旧版建站防火墙拦截规则"
  fi

  output="$(port_listener_for_protocol "$port" "$protocol")"
  menu_section "监听检查"
  if [[ -z "$output" ]]; then
    warn "没有程序监听 ${port}/${protocol}；这不是防火墙放行能修复的问题"
    info "请先启动对应服务，并确认它配置的端口与协议正确"
    return 1
  fi
  echo "$output"
  if port_listener_is_loopback_only "$output" "$port"; then
    warn "服务只监听本机回环地址，外部无法访问"
    info "请将该服务的监听地址改为 0.0.0.0、:: 或服务器公网地址，然后重启服务"
    return 1
  fi
  ok "服务正在非回环地址监听 ${port}/${protocol}"

  menu_section "防火墙"
  warn "下一步只新增 ${port}/${protocol} 的精确放行，不会清空其他规则"
  confirm_word "OPEN" "确认放行请输入 OPEN > " || { info "已取消新增规则；旧版遗留规则仍已清理"; return 0; }
  firewall_allow_port_safe "$port" "$protocol" || return $?
  info "如果外网仍无法访问，请在 VPS 服务商控制台的安全组/云防火墙中放行 ${port}/${protocol}"
  info "还应检查服务自身的访问控制、容器端口映射和上游网络策略"
}

process_inspect_and_stop() {
  local pid="" cmdline="" answer=""
  read_tty pid "输入 PID > " ""
  is_uint_in_range "$pid" 2 4194304 || { warn "PID 无效（不允许操作 PID 1）"; return 1; }
  pid=$((10#$pid))
  [[ "$pid" -ne "$$" && "$pid" -ne "$PPID" ]] || { warn "不能操作当前工具箱进程"; return 1; }
  kill -0 "$pid" >/dev/null 2>&1 || { warn "PID ${pid} 不存在或无权访问"; return 1; }

  menu_header "进程 ${pid}" "查看详情；可选择发送安全终止信号 SIGTERM"
  ps -p "$pid" -o pid,ppid,user,group,stat,%cpu,%mem,rss,vsz,lstart,etime,comm 2>/dev/null || true
  cmdline="$(tr '\0' ' ' < "/proc/${pid}/cmdline" 2>/dev/null || true)"
  print_kv "命令行" "${cmdline:-N/A}"
  print_kv "可执行文件" "$(readlink -f "/proc/${pid}/exe" 2>/dev/null || echo N/A)"
  print_kv "工作目录" "$(readlink -f "/proc/${pid}/cwd" 2>/dev/null || echo N/A)"
  echo
  read_tty answer "如需停止该进程请输入 TERM，直接回车取消 > " ""
  [[ "$answer" == "TERM" ]] || { info "已取消"; return 0; }
  if kill -TERM "$pid" 2>/dev/null; then
    sleep 1
    if kill -0 "$pid" >/dev/null 2>&1; then
      warn "已发送 SIGTERM，但进程仍在运行；未自动发送 SIGKILL"
    else
      ok "进程 ${pid} 已停止"
    fi
  else
    warn "无法向 PID ${pid} 发送 SIGTERM"
    return 1
  fi
}

failed_services_status() {
  menu_header "系统服务健康" "失败服务 · 重启提示 · 时间同步"
  info "正在检查系统服务、时间同步与重启状态，请稍候……"
  if is_systemd; then
    # 兼容旧版本：服务文件已删除后，systemd 仍可能缓存 failed 状态。
    # 仅在本脚本管理的 IPv6 地址池单元已确认为 not-found 且仍为 failed 时清理。
    local ipv6_pool_load_state=""
    ipv6_pool_load_state="$(command_with_timeout 5 systemctl show \
      --property=LoadState --value dmit-ipv6-pool.service 2>/dev/null || true)"
    if [[ "$ipv6_pool_load_state" == "not-found" ]] && \
       command_with_timeout 5 systemctl is-failed --quiet dmit-ipv6-pool.service \
         >/dev/null 2>&1; then
      if command_with_timeout 5 systemctl reset-failed dmit-ipv6-pool.service \
           >/dev/null 2>&1; then
        info "已自动清理旧版遗留的 IPv6 地址池服务失败记录"
      fi
    fi

    menu_section "失败的 systemd 服务"
    local service_rc=0
    command_with_timeout 10 systemctl --failed --no-pager --plain 2>/dev/null || service_rc=$?
    if (( service_rc == 124 )); then
      warn "读取 systemd 失败服务超时，已跳过；工具箱不会继续卡住"
    elif (( service_rc != 0 )); then
      warn "暂时无法读取 systemd 失败服务"
    fi
  else
    warn "当前系统不是 systemd，无法统一读取失败服务"
  fi

  menu_section "时间同步"
  info "正在确认时间同步状态……"
  time_sync_show_status || true

  menu_section "是否需要重启"
  if [[ -f /var/run/reboot-required ]]; then
    warn "系统提示需要重启"
    sed -n '1,20p' /var/run/reboot-required.pkgs 2>/dev/null || true
  elif have_cmd needs-restarting; then
    local rc=0
    command_with_timeout 15 needs-restarting -r >/dev/null 2>&1 || rc=$?
    if [[ "$rc" -eq 0 ]]; then
      ok "当前无需重启"
    elif [[ "$rc" -eq 124 ]]; then
      warn "重启状态检查超时，已跳过"
    else
      warn "系统可能需要重启"
    fi
  else
    info "未发现 reboot-required 标记"
  fi
  ok "系统健康检查完成"
}

system_status_menu() {
  while true; do
    menu_header "系统状态与端口" "资源总览 · 进程排行 · 端口与服务诊断"
    menu_section "系统状态"
    menu_item "1" "系统总览" "CPU、内存、磁盘、inode、网络与流量"
    menu_item "2" "服务健康" "失败服务、时间同步与重启提示"
    menu_section "进程"
    menu_item "3" "CPU 占用排行" "显示前 15 个进程"
    menu_item "4" "内存占用排行" "显示前 15 个进程"
    menu_item "5" "查看或停止进程" "显示 PID 详情，可发送 SIGTERM"
    menu_section "端口"
    menu_item "6" "查看全部监听端口" "TCP / UDP、PID 与程序"
    menu_item "7" "按端口诊断" "查询监听程序和相关连接"
    menu_item "8" "端口访问修复" "清理旧版规则并安全放行指定端口"
    menu_back_item

    local c=""
    read_tty c "请输入编号 > " ""
    case "$c" in
      1) system_overview || true; pause_up ;;
      2) failed_services_status || true; pause_up ;;
      3) processes_top_cpu || true; pause_up ;;
      4) processes_top_memory || true; pause_up ;;
      5) process_inspect_and_stop || true; pause_up ;;
      6) listening_ports || true; pause_up ;;
      7) port_lookup || true; pause_up ;;
      8) port_access_repair || true; pause_up ;;
      0|q|Q) return 0 ;;
      *) warn "无效选项"; pause_up ;;
    esac
  done
}

# ======================================================================
# Swap
# ======================================================================
swap_status() {
  menu_header "Swap 状态" "当前内存、Swap 设备、容量与优先级"
  if have_cmd free; then free -h; fi
  echo
  if have_cmd swapon; then
    swapon --show 2>/dev/null || true
  else
    cat /proc/swaps 2>/dev/null || true
  fi
  echo
  print_kv "swappiness" "$(sysctl -n vm.swappiness 2>/dev/null || echo N/A)"
  print_kv "脚本 Swap 文件" "$( [[ -f "$SWAP_CONF" ]] && echo 已管理 || echo 未管理 )"
}

fstab_swap_backup_once() {
  [[ -s "$FSTAB_SWAP_BACKUP" ]] && return 0
  [[ -f /etc/fstab ]] || { warn "未找到 /etc/fstab"; return 1; }
  ensure_dir "$BACKUP_BASE"
  cp -a /etc/fstab "$FSTAB_SWAP_BACKUP" || { warn "备份 /etc/fstab 失败"; return 1; }
  ok "已备份 /etc/fstab：$FSTAB_SWAP_BACKUP"
}

fstab_remove_managed_swap() {
  [[ -f /etc/fstab ]] || return 0
  local tmp="/etc/.fstab.dmitbox.$$"
  awk -v path="$SWAP_FILE" '!(($1 == path) && ($3 == "swap")) {print}' /etc/fstab > "$tmp" || {
    rm -f "$tmp" >/dev/null 2>&1 || true
    return 1
  }
  chmod 644 "$tmp" >/dev/null 2>&1 || true
  if ! mv -f "$tmp" /etc/fstab; then
    rm -f "$tmp" >/dev/null 2>&1 || true
    return 1
  fi
}

fstab_set_managed_swap() {
  [[ -f /etc/fstab ]] || return 1
  local tmp="/etc/.fstab.dmitbox.$$"
  if ! awk -v path="$SWAP_FILE" '!(($1 == path) && ($3 == "swap")) {print}' /etc/fstab > "$tmp"; then
    rm -f "$tmp" >/dev/null 2>&1 || true
    return 1
  fi
  if ! printf '%s none swap sw 0 0\n' "$SWAP_FILE" >> "$tmp"; then
    rm -f "$tmp" >/dev/null 2>&1 || true
    return 1
  fi
  chmod 644 "$tmp" >/dev/null 2>&1 || true
  if ! mv -f "$tmp" /etc/fstab; then
    rm -f "$tmp" >/dev/null 2>&1 || true
    return 1
  fi
}

swapfile_is_active() {
  awk -v path="$SWAP_FILE" 'NR > 1 && $1 == path {found=1} END{exit !found}' /proc/swaps 2>/dev/null
}

swapfile_rollback_new() {
  local old_file="$1"
  swapoff "$SWAP_FILE" >/dev/null 2>&1 || true
  rm -f "$SWAP_FILE" >/dev/null 2>&1 || true
  if [[ -e "$old_file" ]]; then
    mv "$old_file" "$SWAP_FILE" || true
    swapon "$SWAP_FILE" >/dev/null 2>&1 || true
  fi
}

swapfile_restore_conf_backup() {
  local conf_backup="$1"
  if [[ -n "$conf_backup" && -e "$conf_backup" ]]; then
    mv -f "$conf_backup" "$SWAP_CONF" || {
      warn "原 Swap 管理标记恢复失败：${conf_backup}"
      return 1
    }
  else
    rm -f "$SWAP_CONF" >/dev/null 2>&1 || true
  fi
}

swapfile_create() {
  local size_mb="" default_mb="1024" action="CREATE" verb="创建" tmp_file="${SWAP_FILE}.dmitbox.new"
  local old_file="${SWAP_FILE}.dmitbox.old.$$" conf_backup="" free_mb="0" fs_type=""

  if [[ -e "$SWAP_FILE" && ! -f "$SWAP_CONF" ]]; then
    warn "${SWAP_FILE} 已存在但不是本脚本创建的文件，为避免覆盖已取消"
    return 1
  fi
  if [[ -f "$SWAP_CONF" ]]; then
    action="RESIZE"
    verb="调整"
  fi

  read_tty size_mb "输入 Swap 大小（MiB，默认 ${default_mb}）> " "$default_mb"
  is_uint_in_range "$size_mb" 256 65536 || { warn "Swap 大小必须在 256-65536 MiB 之间"; return 1; }
  size_mb=$((10#$size_mb))
  free_mb="$(df -Pm / 2>/dev/null | awk 'NR==2{print $4}' || echo 0)"
  is_uint_in_range "$free_mb" 0 9999999999 || free_mb="0"
  if (( free_mb < size_mb + 128 )); then
    warn "可用空间不足：需要至少 $((size_mb + 128)) MiB，当前约 ${free_mb} MiB"
    return 1
  fi

  warn "将${verb} ${SWAP_FILE} 为 ${size_mb} MiB"
  confirm_word "$action" "确认请输入 ${action} > " || { warn "已取消"; return 0; }

  pkg_install util-linux
  if ! have_cmd mkswap || ! have_cmd swapon || ! have_cmd swapoff; then
    warn "缺少 mkswap/swapon/swapoff，无法继续"
    return 1
  fi
  fstab_swap_backup_once || return 1
  rm -f "$tmp_file" >/dev/null 2>&1 || true

  fs_type="$(findmnt -no FSTYPE / 2>/dev/null || true)"
  if [[ "$fs_type" == "btrfs" ]]; then
    touch "$tmp_file"
    if have_cmd chattr; then
      chattr +C "$tmp_file" >/dev/null 2>&1 || true
    fi
  fi
  if have_cmd fallocate; then
    fallocate -l "${size_mb}M" "$tmp_file" 2>/dev/null || true
  fi
  if [[ ! -s "$tmp_file" ]]; then
    info "fallocate 不可用，改用 dd 创建（可能需要一些时间）"
    dd if=/dev/zero of="$tmp_file" bs=1M count="$size_mb" conv=fsync 2>/dev/null || {
      rm -f "$tmp_file" >/dev/null 2>&1 || true
      warn "Swap 文件创建失败"
      return 1
    }
  fi
  chmod 600 "$tmp_file"
  mkswap "$tmp_file" >/dev/null || { rm -f "$tmp_file"; warn "mkswap 失败"; return 1; }

  if [[ -e "$SWAP_FILE" ]]; then
    if swapfile_is_active && ! swapoff "$SWAP_FILE"; then
      rm -f "$tmp_file" >/dev/null 2>&1 || true
      warn "无法停用原 Swap，已取消调整"
      return 1
    fi
    mv "$SWAP_FILE" "$old_file" || { rm -f "$tmp_file"; return 1; }
  fi
  mv "$tmp_file" "$SWAP_FILE" || {
    if [[ -e "$old_file" ]]; then
      mv "$old_file" "$SWAP_FILE" || true
      swapon "$SWAP_FILE" >/dev/null 2>&1 || true
    fi
    return 1
  }

  if ! swapon "$SWAP_FILE"; then
    warn "新 Swap 启用失败，正在恢复原文件"
    rm -f "$SWAP_FILE" >/dev/null 2>&1 || true
    if [[ -e "$old_file" ]]; then
      mv "$old_file" "$SWAP_FILE"
      swapon "$SWAP_FILE" >/dev/null 2>&1 || true
    fi
    return 1
  fi
  if [[ -f "$SWAP_CONF" ]]; then
    conf_backup="${SWAP_CONF}.dmitbox.old.$$"
    if ! cp -a "$SWAP_CONF" "$conf_backup"; then
      warn "无法备份原 Swap 管理标记，正在恢复原文件"
      swapfile_rollback_new "$old_file"
      return 1
    fi
  fi
  if ! write_file "$SWAP_CONF" "PATH=${SWAP_FILE}
SIZE_MIB=${size_mb}
CREATED=$(date -Is)"; then
    warn "Swap 管理标记写入失败，正在恢复原文件"
    swapfile_rollback_new "$old_file"
    swapfile_restore_conf_backup "$conf_backup" || true
    return 1
  fi
  if ! fstab_set_managed_swap; then
    warn "更新 /etc/fstab 失败，正在恢复原 Swap"
    swapfile_rollback_new "$old_file"
    swapfile_restore_conf_backup "$conf_backup" || true
    return 1
  fi
  rm -f "$old_file" >/dev/null 2>&1 || true
  if [[ -n "$conf_backup" ]]; then
    rm -f "$conf_backup" >/dev/null 2>&1 || true
  fi
  chmod 600 "$SWAP_CONF" >/dev/null 2>&1 || true
  ok "Swap 已启用并持久化：${SWAP_FILE} (${size_mb} MiB)"
  swapon --show 2>/dev/null || true
}

swapfile_remove() {
  [[ -f "$SWAP_CONF" ]] || { warn "脚本没有管理 ${SWAP_FILE}，拒绝删除未知 Swap 文件"; return 1; }
  [[ -e "$SWAP_FILE" ]] || { warn "${SWAP_FILE} 不存在，仅清理配置"; }
  warn "将停用并删除脚本创建的 ${SWAP_FILE}"
  confirm_word "REMOVE" "确认请输入 REMOVE > " || { warn "已取消"; return 0; }
  fstab_swap_backup_once || return 1
  if swapfile_is_active && ! swapoff "$SWAP_FILE"; then
    warn "Swap 正在使用且无法停用，未删除文件"
    return 1
  fi
  fstab_remove_managed_swap || { warn "无法更新 /etc/fstab，未删除文件"; return 1; }
  if ! rm -f "$SWAP_FILE"; then
    warn "Swap 已停用，但文件删除失败：${SWAP_FILE}"
    return 1
  fi
  rm -f "$SWAP_CONF" >/dev/null 2>&1 || true
  ok "脚本创建的 Swap 已删除"
}

swappiness_set() {
  local value=""
  read_tty value "输入 vm.swappiness（0-100，默认 10）> " "10"
  is_uint_in_range "$value" 0 100 || { warn "swappiness 必须在 0-100 之间"; return 1; }
  value=$((10#$value))
  write_file "$SWAPPINESS_FILE" "# managed by ${SCRIPT_NAME}
vm.swappiness=${value}"
  if sysctl -w "vm.swappiness=${value}" >/dev/null 2>&1; then
    ok "swappiness 已设置为 ${value}"
  else
    warn "运行时设置失败，但已写入持久化配置"
    return 1
  fi
}

swap_menu() {
  while true; do
    menu_header "Swap 管理" "Swap 文件 · 容量调整 · swappiness"
    menu_section "状态"
    menu_item "1" "查看 Swap 状态" "设备、容量、使用量和优先级"
    menu_section "管理"
    menu_item "2" "创建或调整 Swap" "仅管理 ${SWAP_FILE}，支持 256 MiB-64 GiB"
    menu_item "3" "删除脚本 Swap" "仅删除脚本创建的 ${SWAP_FILE}"
    menu_item "4" "设置 swappiness" "范围 0-100，默认建议 10"
    menu_back_item

    local c=""
    read_tty c "请输入编号 > " ""
    case "$c" in
      1) swap_status || true; pause_up ;;
      2) swapfile_create || true; pause_up ;;
      3) swapfile_remove || true; pause_up ;;
      4) swappiness_set || true; pause_up ;;
      0|q|Q) return 0 ;;
      *) warn "无效选项"; pause_up ;;
    esac
  done
}

# ======================================================================
# 安全清理 / 系统更新
# ======================================================================
cleanup_preview() {
  menu_header "安全清理预览" "只统计可安全清理的缓存与日志，不删除文件"
  menu_section "根分区"
  df -h / 2>/dev/null || true
  menu_section "软件包缓存"
  [[ -d /var/cache/apt/archives ]] && print_kv "APT 缓存" "$(du -sh /var/cache/apt/archives 2>/dev/null | awk '{print $1}' || echo N/A)"
  [[ -d /var/cache/dnf ]] && print_kv "DNF 缓存" "$(du -sh /var/cache/dnf 2>/dev/null | awk '{print $1}' || echo N/A)"
  [[ -d /var/cache/yum ]] && print_kv "YUM 缓存" "$(du -sh /var/cache/yum 2>/dev/null | awk '{print $1}' || echo N/A)"
  [[ -d /var/cache/apk ]] && print_kv "APK 缓存" "$(du -sh /var/cache/apk 2>/dev/null | awk '{print $1}' || echo N/A)"
  menu_section "systemd journal"
  if have_cmd journalctl; then
    journalctl --disk-usage 2>/dev/null || true
    echo -e "${c_dim}执行清理时保留最近 7 天，并限制归档日志约 200 MiB。${c_reset}"
  else
    info "当前系统没有 journalctl"
  fi
  menu_section "临时文件"
  if have_cmd systemd-tmpfiles; then
    info "将调用 systemd-tmpfiles --clean，仅按系统既定保留策略清理"
  else
    info "没有 systemd-tmpfiles，不会直接删除 /tmp 内容"
  fi
  echo
  info "不会执行 autoremove、删除当前内核、清理数据库或 Docker 数据"
}

cleanup_execute() {
  cleanup_preview
  echo
  confirm_word "CLEAN" "确认清理请输入 CLEAN > " || { warn "已取消"; return 0; }

  local before="0" after="0" freed_kb="0"
  before="$(df -Pk / 2>/dev/null | awk 'NR==2{print $4}' || echo 0)"
  if have_cmd apt-get; then
    info "清理 APT 下载缓存"
    apt-get clean >/dev/null 2>&1 || warn "APT 缓存清理失败"
  elif have_cmd dnf; then
    info "清理 DNF 缓存"
    dnf clean all >/dev/null 2>&1 || warn "DNF 缓存清理失败"
  elif have_cmd yum; then
    info "清理 YUM 缓存"
    yum clean all >/dev/null 2>&1 || warn "YUM 缓存清理失败"
  elif have_cmd apk; then
    info "清理 APK 缓存"
    apk cache clean >/dev/null 2>&1 || warn "APK 缓存清理失败"
  fi

  if have_cmd journalctl; then
    info "压缩并清理旧 journal（保留 7 天 / 约 200 MiB）"
    journalctl --rotate >/dev/null 2>&1 || true
    journalctl --vacuum-time=7d >/dev/null 2>&1 || warn "journal 时间清理失败"
    journalctl --vacuum-size=200M >/dev/null 2>&1 || warn "journal 容量清理失败"
  fi
  if have_cmd systemd-tmpfiles; then
    info "按系统策略清理临时文件"
    systemd-tmpfiles --clean >/dev/null 2>&1 || warn "临时文件清理未完全成功"
  fi

  after="$(df -Pk / 2>/dev/null | awk 'NR==2{print $4}' || echo 0)"
  if [[ "$before" =~ ^[0-9]+$ && "$after" =~ ^[0-9]+$ && "$after" -ge "$before" ]]; then
    freed_kb=$((after - before))
    ok "安全清理完成，根分区约释放 $(human_bytes "$((freed_kb * 1024))")"
  else
    ok "安全清理完成"
  fi
}

cleanup_menu() {
  while true; do
    menu_header "磁盘与日志清理" "清理前预览 · 限定目标 · 不做 autoremove"
    menu_item "1" "查看清理预览" "统计包缓存、journal 与根分区"
    menu_item "2" "执行安全清理" "需要输入 CLEAN 确认"
    menu_back_item
    local c=""
    read_tty c "请输入编号 > " ""
    case "$c" in
      1) cleanup_preview || true; pause_up ;;
      2) cleanup_execute || true; pause_up ;;
      0|q|Q) return 0 ;;
      *) warn "无效选项"; pause_up ;;
    esac
  done
}

system_updates_check() {
  menu_header "检查系统更新" "刷新软件源并列出可升级软件包，不安装更新"
  local rc=0
  if have_cmd apt-get; then
    run_with_spinner "刷新 APT 软件源" apt-get -o DPkg::Lock::Timeout=30 -y update || return 1
    if have_cmd apt; then
      apt list --upgradable 2>/dev/null | sed -n '1,120p' || true
    else
      apt-get -s upgrade 2>/dev/null | awk '/^Inst /{print}' | sed -n '1,120p' || true
    fi
  elif have_cmd dnf; then
    dnf -q check-update || rc=$?
    [[ "$rc" -eq 0 || "$rc" -eq 100 ]] || { warn "DNF 检查更新失败（rc=${rc}）"; return 1; }
  elif have_cmd yum; then
    yum -q check-update || rc=$?
    [[ "$rc" -eq 0 || "$rc" -eq 100 ]] || { warn "YUM 检查更新失败（rc=${rc}）"; return 1; }
  elif have_cmd apk; then
    apk update || return 1
    apk version -l '<' 2>/dev/null | sed -n '1,120p' || true
  else
    warn "未识别包管理器"
    return 1
  fi
  ok "更新检查完成"
}

system_updates_apply() {
  warn "将安装当前发行版提供的常规更新；不会执行跨版本升级"
  confirm_word "UPDATE" "确认更新请输入 UPDATE > " || { warn "已取消"; return 0; }

  export DEBIAN_FRONTEND=noninteractive
  export NEEDRESTART_MODE=a
  if have_cmd apt-get; then
    run_with_spinner "刷新 APT 软件源" apt-get -o DPkg::Lock::Timeout=30 -y update || return 1
    run_with_spinner "安装系统更新" apt-get -o DPkg::Lock::Timeout=30 -y \
      -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold upgrade || return 1
  elif have_cmd dnf; then
    run_with_spinner "安装系统更新" dnf -y upgrade || return 1
  elif have_cmd yum; then
    run_with_spinner "安装系统更新" yum -y update || return 1
  elif have_cmd apk; then
    run_with_spinner "刷新 APK 软件源" apk update || return 1
    run_with_spinner "安装系统更新" apk upgrade || return 1
  else
    warn "未识别包管理器"
    return 1
  fi
  ok "系统更新完成"
  [[ -f /var/run/reboot-required ]] && warn "部分更新需要重启后生效"
}

time_sync_systemd_unit_exists() {
  local unit="${1%.service}.service" output=""
  is_systemd || return 1
  command_with_timeout 6 systemctl cat "$unit" >/dev/null 2>&1 && return 0
  output="$(command_with_timeout 6 systemctl list-unit-files "$unit" --no-legend 2>/dev/null | sed -n '1p' || true)"
  [[ "$output" == "$unit "* || "$output" == "$unit"$'\t'* ]]
}

time_sync_service_exists() {
  local name="${1%.service}"
  if is_systemd; then
    time_sync_systemd_unit_exists "$name"
    return $?
  fi
  [[ -x "/etc/init.d/${name}" ]] && return 0
  if have_cmd rc-service; then
    rc-service -e 2>/dev/null | grep -Fxq "$name" && return 0
  fi
  return 1
}

time_sync_service_active() {
  local name="${1%.service}"
  if is_systemd; then
    command_with_timeout 6 systemctl is-active --quiet "${name}.service" >/dev/null 2>&1 && return 0
  elif have_cmd rc-service; then
    command_with_timeout 6 rc-service "$name" status >/dev/null 2>&1 && return 0
  elif have_cmd service; then
    command_with_timeout 6 service "$name" status >/dev/null 2>&1 && return 0
  fi
  case "$name" in
    chrony|chronyd) have_cmd pgrep && pgrep -x chronyd >/dev/null 2>&1 ;;
    ntp|ntpd|ntpsec|openntpd) have_cmd pgrep && pgrep -x ntpd >/dev/null 2>&1 ;;
    systemd-timesyncd) have_cmd pgrep && pgrep -f '(^|/)systemd-timesyncd([[:space:]]|$)' >/dev/null 2>&1 ;;
    *) return 1 ;;
  esac
}

time_sync_chrony_service_name() {
  local name=""
  for name in chrony chronyd; do
    time_sync_service_exists "$name" && { printf '%s\n' "$name"; return 0; }
  done
  if have_cmd apk; then printf 'chronyd\n'; else printf 'chrony\n'; fi
}

time_sync_ntpd_service_name() {
  local name=""
  for name in ntp ntpd ntpsec openntpd; do
    time_sync_service_exists "$name" && { printf '%s\n' "$name"; return 0; }
  done
  if have_cmd ntpd; then
    if have_cmd apk || have_cmd dnf || have_cmd yum; then printf 'ntpd\n'; else printf 'ntp\n'; fi
    return 0
  fi
  return 1
}

time_sync_chrony_installed() {
  have_cmd chronyc || have_cmd chronyd || \
    time_sync_service_exists chrony || time_sync_service_exists chronyd
}

time_sync_ntpd_installed() {
  have_cmd ntpd || time_sync_service_exists ntp || time_sync_service_exists ntpd || \
    time_sync_service_exists ntpsec || time_sync_service_exists openntpd
}

time_sync_detect_backend() {
  local name=""
  for name in chrony chronyd; do
    if time_sync_service_exists "$name" && time_sync_service_active "$name"; then
      printf 'chrony|%s\n' "$name"
      return 0
    fi
  done
  if is_systemd && time_sync_service_active systemd-timesyncd; then
    printf 'timesyncd|systemd-timesyncd\n'
    return 0
  fi
  for name in ntp ntpd ntpsec openntpd; do
    if time_sync_service_exists "$name" && time_sync_service_active "$name"; then
      printf 'ntpd|%s\n' "$name"
      return 0
    fi
  done
  if have_cmd pgrep && pgrep -x chronyd >/dev/null 2>&1; then
    printf 'chrony|%s\n' "$(time_sync_chrony_service_name)"
    return 0
  fi
  if have_cmd pgrep && pgrep -x ntpd >/dev/null 2>&1; then
    printf 'ntpd|%s\n' "$(time_sync_ntpd_service_name 2>/dev/null || echo ntpd)"
    return 0
  fi
  if time_sync_chrony_installed; then
    printf 'chrony|%s\n' "$(time_sync_chrony_service_name)"
    return 0
  fi
  if is_systemd && time_sync_systemd_unit_exists systemd-timesyncd; then
    printf 'timesyncd|systemd-timesyncd\n'
    return 0
  fi
  if time_sync_ntpd_installed; then
    printf 'ntpd|%s\n' "$(time_sync_ntpd_service_name)"
    return 0
  fi
  printf 'none|none\n'
  return 1
}

time_sync_backend_label() {
  case "${1%%|*}" in
    timesyncd) printf 'systemd-timesyncd\n' ;;
    chrony) printf 'chrony\n' ;;
    ntpd) printf 'ntpd\n' ;;
    *) printf '未配置\n' ;;
  esac
}

time_sync_backend_active() {
  local backend="${1%%|*}" service_name="${1#*|}"
  [[ "$backend" != "none" && -n "$service_name" && "$service_name" != "none" ]] || return 1
  time_sync_service_active "$service_name"
}

time_sync_is_synchronized() {
  local value="" tracking=""
  if have_cmd timedatectl; then
    value="$(command_with_timeout 6 timedatectl show -p NTPSynchronized --value 2>/dev/null || true)"
    [[ "${value,,}" == "yes" ]] && return 0
  fi
  if have_cmd chronyc; then
    tracking="$(LC_ALL=C command_with_timeout 6 chronyc tracking 2>/dev/null || true)"
    grep -Eq '^Leap status[[:space:]]*:[[:space:]]*Normal([[:space:]]|$)' <<< "$tracking" && return 0
  fi
  if have_cmd ntpq; then
    LC_ALL=C command_with_timeout 6 ntpq -pn 2>/dev/null | awk '$1 ~ /^\*/ {found=1} END {exit !found}' && return 0
  fi
  return 1
}

time_sync_status_text() {
  local backend_spec="" label=""
  backend_spec="$(time_sync_detect_backend 2>/dev/null || true)"
  [[ -n "$backend_spec" ]] || backend_spec="none|none"
  label="$(time_sync_backend_label "$backend_spec")"
  if time_sync_is_synchronized; then
    [[ "$label" == "未配置" ]] && label="系统 NTP"
    printf '已同步（%s）\n' "$label"
  elif time_sync_backend_active "$backend_spec"; then
    printf '运行中，等待同步（%s）\n' "$label"
  elif [[ "${backend_spec%%|*}" != "none" ]]; then
    printf '未运行（%s）\n' "$label"
  else
    printf '未配置\n'
  fi
}

time_sync_show_status() {
  local backend_spec="${1:-}" synchronized_hint="${2:-}" active_hint="${3:-}"
  local label="" synchronized=0 active=0
  [[ -n "$backend_spec" ]] || backend_spec="$(time_sync_detect_backend 2>/dev/null || true)"
  [[ -n "$backend_spec" ]] || backend_spec="none|none"
  label="$(time_sync_backend_label "$backend_spec")"
  if [[ "$synchronized_hint" == "1" ]]; then
    synchronized=1
  elif [[ "$synchronized_hint" != "0" ]] && time_sync_is_synchronized; then
    synchronized=1
  fi
  if [[ "$active_hint" == "1" ]]; then
    active=1
  elif [[ "$active_hint" != "0" && "$synchronized" -eq 0 ]] && \
       time_sync_backend_active "$backend_spec"; then
    active=1
  fi
  print_kv "同步服务" "$label"
  if (( synchronized == 1 )); then
    ok "系统时间已经同步"
  elif (( active == 1 )); then
    warn "同步服务已运行，但尚未确认与上游完成同步"
    info "首次启动、网络刚恢复或上游暂不可达时，通常需要稍等片刻"
  else
    warn "没有运行中的时间同步服务"
  fi
  (( synchronized == 1 || active == 1 ))
}

time_sync_enable_service() {
  local name="${1%.service}"
  if is_systemd; then
    command_with_timeout 15 systemctl unmask "${name}.service" >/dev/null 2>&1 || true
    command_with_timeout 15 systemctl enable "${name}.service" >/dev/null 2>&1 || true
    if ! time_sync_service_active "$name"; then
      command_with_timeout 25 systemctl start "${name}.service" >/dev/null 2>&1 || return 1
    fi
  elif have_cmd rc-service; then
    have_cmd rc-update && command_with_timeout 15 rc-update add "$name" default >/dev/null 2>&1 || true
    if ! time_sync_service_active "$name"; then
      command_with_timeout 25 rc-service "$name" start >/dev/null 2>&1 || return 1
    fi
  elif have_cmd service; then
    have_cmd update-rc.d && command_with_timeout 15 update-rc.d "$name" defaults >/dev/null 2>&1 || true
    have_cmd chkconfig && command_with_timeout 15 chkconfig "$name" on >/dev/null 2>&1 || true
    if ! time_sync_service_active "$name"; then
      command_with_timeout 25 service "$name" start >/dev/null 2>&1 || return 1
    fi
  else
    return 1
  fi
  time_sync_service_active "$name"
}

time_sync_start_backend() {
  local backend_spec="$1" backend="${1%%|*}" service_name="${1#*|}"
  case "$backend" in
    timesyncd)
      time_sync_enable_service "$service_name" || return 1
      if have_cmd timedatectl && ! command_with_timeout 10 timedatectl set-ntp true >/dev/null 2>&1; then
        info "timedatectl 接口不可用，但 systemd-timesyncd 服务已直接启用"
      fi
      ;;
    chrony)
      time_sync_enable_service "$service_name" || return 1
      have_cmd chronyc && command_with_timeout 10 chronyc online >/dev/null 2>&1 || true
      ;;
    ntpd)
      time_sync_enable_service "$service_name" || return 1
      ;;
    *) return 1 ;;
  esac
  time_sync_backend_active "$backend_spec"
}

time_sync_install_chrony() {
  info "安装 chrony 时间同步服务"
  pkg_install chrony
  time_sync_chrony_installed || { warn "chrony 安装后仍不可用"; return 1; }
}

time_sync_install_preferred() {
  if have_cmd apt-get && is_systemd; then
    info "安装轻量的 systemd-timesyncd"
    pkg_install systemd-timesyncd
    if time_sync_systemd_unit_exists systemd-timesyncd; then
      return 0
    fi
    warn "systemd-timesyncd 不可用，将改用 chrony"
  fi
  time_sync_install_chrony
}

time_sync_finish_enable() {
  local backend_spec="$1" label="" synchronized=0
  label="$(time_sync_backend_label "$backend_spec")"
  time_sync_backend_active "$backend_spec" || { warn "${label} 未能保持运行状态"; return 1; }
  if time_sync_is_synchronized; then
    synchronized=1
    ok "自动时间同步已开启并确认同步：${label}"
  else
    ok "自动时间同步服务已开启：${label}"
    info "当前尚未确认同步完成；请等待约 1-2 分钟后再次查看状态"
  fi
  time_sync_show_status "$backend_spec" "$synchronized" 1 || true
}

time_sync_enable() {
  local backend_spec="" backend="" service_name="" fallback_spec=""
  info "正在检查时间同步服务与当前同步状态，请稍候……"
  backend_spec="$(time_sync_detect_backend 2>/dev/null || true)"
  [[ -n "$backend_spec" ]] || backend_spec="none|none"

  if time_sync_is_synchronized && time_sync_backend_active "$backend_spec"; then
    ok "自动时间同步已经正常运行，无需重复设置"
    time_sync_show_status "$backend_spec" 1 1 || true
    return 0
  fi

  if [[ "${backend_spec%%|*}" == "none" ]]; then
    time_sync_install_preferred || return 1
    backend_spec="$(time_sync_detect_backend 2>/dev/null || true)"
    [[ -n "$backend_spec" && "${backend_spec%%|*}" != "none" ]] || {
      warn "安装后仍未找到可用的时间同步服务"
      return 1
    }
  fi

  backend="${backend_spec%%|*}"
  service_name="${backend_spec#*|}"
  info "正在启用：$(time_sync_backend_label "$backend_spec")（${service_name}）"
  if time_sync_start_backend "$backend_spec"; then
    time_sync_finish_enable "$backend_spec"
    return $?
  fi
  warn "首选时间同步服务启动失败：$(time_sync_backend_label "$backend_spec")"

  if [[ "$backend" != "chrony" ]] && time_sync_install_chrony; then
    service_name="$(time_sync_chrony_service_name)"
    fallback_spec="chrony|${service_name}"
    info "正在尝试备用服务：chrony（${service_name}）"
    if time_sync_start_backend "$fallback_spec"; then
      time_sync_finish_enable "$fallback_spec"
      return $?
    fi
  fi

  if [[ "$backend" != "timesyncd" ]] && is_systemd && \
     time_sync_systemd_unit_exists systemd-timesyncd; then
    fallback_spec="timesyncd|systemd-timesyncd"
    info "正在尝试备用服务：systemd-timesyncd"
    if time_sync_start_backend "$fallback_spec"; then
      time_sync_finish_enable "$fallback_spec"
      return $?
    fi
  fi

  warn "所有可用的时间同步后端均启动失败"
  info "请查看：systemctl status systemd-timesyncd chrony chronyd --no-pager"
  info "非 systemd 系统请查看：rc-service chronyd status"
  return 1
}

system_update_menu() {
  while true; do
    menu_header "系统更新与健康" "软件更新 · 失败服务 · 重启提示 · 时间同步"
    menu_section "软件更新"
    menu_item "1" "检查可用更新" "刷新软件源，仅列出更新"
    menu_item "2" "安装常规更新" "不执行发行版跨版本升级"
    menu_section "系统健康"
    menu_item "3" "服务与重启状态" "失败服务、时间同步、重启提示"
    menu_item "4" "检查并开启时间同步" "自动选择 timesyncd、chrony 或现有 ntpd"
    menu_back_item
    local c=""
    read_tty c "请输入编号 > " ""
    case "$c" in
      1) system_updates_check || true; pause_up ;;
      2) system_updates_apply || true; pause_up ;;
      3) failed_services_status || true; pause_up ;;
      4) time_sync_enable || true; pause_up ;;
      0|q|Q) return 0 ;;
      *) warn "无效选项"; pause_up ;;
    esac
  done
}

# ======================================================================
# Fail2Ban SSH 防爆破
# ======================================================================
valid_ip_or_cidr() {
  local value="${1:-}" address="" prefix="" part="" right="" colon_chars=""
  [[ "$value" =~ ^[0-9A-Fa-f:.]+(/[0-9]{1,3})?$ ]] || return 1

  if have_cmd python3; then
    if python3 - "$value" >/dev/null 2>&1 <<'PY'
import ipaddress
import sys

value = sys.argv[1]
try:
    ipaddress.ip_network(value, strict=False) if "/" in value else ipaddress.ip_address(value)
except ValueError:
    raise SystemExit(1)
PY
    then
      return 0
    fi
    return 1
  fi

  address="${value%%/*}"
  if [[ "$value" == */* ]]; then
    prefix="${value##*/}"
  fi
  if [[ "$address" == *.* && "$address" != *:* ]]; then
    local -a octets=()
    local IFS='.'
    read -r -a octets <<< "$address"
    [[ "${#octets[@]}" -eq 4 ]] || return 1
    for part in "${octets[@]}"; do
      [[ "$part" =~ ^[0-9]{1,3}$ ]] || return 1
      (( 10#$part <= 255 )) || return 1
    done
    [[ -z "$prefix" ]] || is_uint_in_range "$prefix" 0 32
    return $?
  fi

  [[ "$address" == *:* && "$address" != *.* && "$address" =~ ^[0-9A-Fa-f:]+$ ]] || return 1
  [[ "$address" != *:::* ]] || return 1
  if [[ "$address" == *::* ]]; then
    right="${address#*::}"
    [[ "$right" != *::* ]] || return 1
  fi
  colon_chars="${address//[0-9A-Fa-f]/}"
  (( ${#colon_chars} >= 2 && ${#colon_chars} <= 8 )) || return 1
  local -a hextets=()
  local IFS=':'
  read -r -a hextets <<< "$address"
  for part in "${hextets[@]}"; do
    [[ -z "$part" || ( ${#part} -le 4 && "$part" =~ ^[0-9A-Fa-f]+$ ) ]] || return 1
  done
  if [[ "$address" == *::* ]]; then
    (( ${#hextets[@]} < 8 )) || return 1
  else
    (( ${#hextets[@]} == 8 )) || return 1
  fi
  [[ -z "$prefix" ]] || is_uint_in_range "$prefix" 0 128
}

fail2ban_service_restart() {
  if is_systemd; then
    systemctl enable fail2ban >/dev/null 2>&1 || true
    systemctl restart fail2ban >/dev/null 2>&1
  elif have_cmd rc-service; then
    rc-update add fail2ban default >/dev/null 2>&1 || true
    rc-service fail2ban restart >/dev/null 2>&1
  elif have_cmd service; then
    service fail2ban restart >/dev/null 2>&1
  else
    return 1
  fi
}

fail2ban_validate() {
  have_cmd fail2ban-client || return 1
  fail2ban-client -t >/dev/null 2>&1
}

fail2ban_status() {
  menu_header "Fail2Ban 状态" "服务、sshd jail、封禁列表与最近日志"
  if ! have_cmd fail2ban-client; then
    warn "Fail2Ban 未安装"
    return 0
  fi
  if is_systemd; then
    print_kv "服务状态" "$(systemctl is-active fail2ban 2>/dev/null || echo inactive)"
  fi
  fail2ban-client ping 2>/dev/null || warn "Fail2Ban 服务未响应"
  echo
  fail2ban-client status 2>/dev/null || true
  echo
  if fail2ban-client status sshd >/dev/null 2>&1; then
    fail2ban-client status sshd 2>/dev/null || true
  else
    warn "sshd jail 未启用"
  fi
  menu_section "最近日志"
  if have_cmd journalctl && is_systemd; then
    journalctl -u fail2ban --no-pager -n 30 2>/dev/null || true
  else
    tail -n 30 /var/log/fail2ban.log 2>/dev/null || true
  fi
}

fail2ban_restore_config_on_error() {
  local had_previous="$1" rollback_file="$2"
  if [[ "$had_previous" == "1" && -e "$rollback_file" ]]; then
    cp -a "$rollback_file" "$FAIL2BAN_JAIL_FILE" >/dev/null 2>&1 || true
  else
    rm -f "$FAIL2BAN_JAIL_FILE" >/dev/null 2>&1 || true
  fi
}

fail2ban_install_configure() {
  warn "将安装 Fail2Ban，并启用 SSH 防爆破：5 次失败、10 分钟统计、封禁 1 小时"
  confirm_word "ENABLE" "确认请输入 ENABLE > " || { warn "已取消"; return 0; }
  pkg_install fail2ban
  have_cmd fail2ban-client || { warn "Fail2Ban 安装失败或软件源中无此包"; return 1; }

  ensure_dir "$BACKUP_BASE"
  ensure_dir "$(dirname "$FAIL2BAN_JAIL_FILE")"
  local had_previous="0" rollback_file=""
  local port="22" backend="auto" current_ip="" ignore="127.0.0.1/8 ::1"
  rollback_file="$(mktemp /tmp/dmitbox-fail2ban-rollback.XXXXXX)" || {
    warn "无法创建临时回滚文件"
    return 1
  }
  if [[ -f "$FAIL2BAN_JAIL_FILE" ]]; then
    had_previous="1"
    cp -a "$FAIL2BAN_JAIL_FILE" "$rollback_file"
  fi
  if [[ ! -f "$FAIL2BAN_ORIG_MARKER" ]]; then
    if [[ -f "$FAIL2BAN_JAIL_FILE" ]]; then
      write_file "$FAIL2BAN_ORIG_MARKER" "1"
      cp -a "$FAIL2BAN_JAIL_FILE" "$FAIL2BAN_BACKUP"
    else
      write_file "$FAIL2BAN_ORIG_MARKER" "0"
    fi
  fi
  port="$(ssh_current_ports 2>/dev/null | awk '{print $1}' || echo 22)"
  is_uint_in_range "$port" 1 65535 || port="22"
  current_ip="${SSH_CONNECTION:-}"
  current_ip="${current_ip%% *}"
  if valid_ip_or_cidr "$current_ip"; then
    ignore="${ignore} ${current_ip}"
    info "已自动加入当前 SSH 来源白名单：${current_ip}"
  fi

  if is_systemd && have_cmd journalctl; then
    backend="systemd"
  elif [[ -f /var/log/auth.log ]]; then
    backend="auto"
  elif [[ -f /var/log/secure ]]; then
    backend="auto"
  else
    warn "未检测到 journald、auth.log 或 secure；配置后请确认 sshd jail 能读取日志"
  fi

  write_file "$FAIL2BAN_JAIL_FILE" "# managed by ${SCRIPT_NAME}
[DEFAULT]
ignoreip = ${ignore}
bantime = 1h
findtime = 10m
maxretry = 5

[sshd]
enabled = true
port = ${port}
backend = ${backend}"

  if ! fail2ban_validate; then
    warn "Fail2Ban 配置校验失败，正在恢复原配置"
    fail2ban-client -t 2>&1 | tail -n 30 || true
    fail2ban_restore_config_on_error "$had_previous" "$rollback_file"
    rm -f "$rollback_file" >/dev/null 2>&1 || true
    return 1
  fi
  if ! fail2ban_service_restart; then
    warn "Fail2Ban 服务启动失败，正在恢复原配置"
    fail2ban_restore_config_on_error "$had_previous" "$rollback_file"
    fail2ban_service_restart >/dev/null 2>&1 || true
    rm -f "$rollback_file" >/dev/null 2>&1 || true
    return 1
  fi
  sleep 1
  if ! fail2ban-client status sshd >/dev/null 2>&1; then
    warn "Fail2Ban 已启动，但 sshd jail 未正常运行；正在恢复原配置"
    fail2ban_restore_config_on_error "$had_previous" "$rollback_file"
    fail2ban_service_restart >/dev/null 2>&1 || true
    rm -f "$rollback_file" >/dev/null 2>&1 || true
    return 1
  fi
  rm -f "$rollback_file" >/dev/null 2>&1 || true
  ok "SSH 防爆破已启用（SSH 端口：${port}，日志后端：${backend}）"
  fail2ban-client status sshd 2>/dev/null || true
}

fail2ban_add_whitelist() {
  [[ -f "$FAIL2BAN_JAIL_FILE" ]] || { warn "请先安装并配置 Fail2Ban SSH 防护"; return 1; }
  local value="" old_ignore="" new_ignore="" tmp="/tmp/dmitbox-fail2ban.$$"
  read_tty value "输入要加入白名单的 IP 或 CIDR > " ""
  valid_ip_or_cidr "$value" || { warn "IP/CIDR 格式无效"; return 1; }
  old_ignore="$(sed -n -E 's/^ignoreip[[:space:]]*=[[:space:]]*(.*)$/\1/p' "$FAIL2BAN_JAIL_FILE" | head -n1)"
  [[ -n "$old_ignore" ]] || { warn "配置中缺少 ignoreip，请先执行【安装或修复配置】"; return 1; }
  [[ " ${old_ignore} " == *" ${value} "* ]] && { info "${value} 已在白名单中"; return 0; }
  new_ignore="${old_ignore} ${value}"
  cp -a "$FAIL2BAN_JAIL_FILE" "$tmp"
  sed -i -E "s|^ignoreip[[:space:]]*=.*$|ignoreip = ${new_ignore}|" "$FAIL2BAN_JAIL_FILE"
  if ! fail2ban_validate || ! fail2ban_service_restart; then
    cp -a "$tmp" "$FAIL2BAN_JAIL_FILE"
    fail2ban_service_restart >/dev/null 2>&1 || true
    rm -f "$tmp"
    warn "白名单配置失败，已回滚"
    return 1
  fi
  rm -f "$tmp"
  ok "已加入 Fail2Ban 白名单：${value}"
}

fail2ban_unban_ip() {
  have_cmd fail2ban-client || { warn "Fail2Ban 未安装"; return 1; }
  local value=""
  read_tty value "输入要解封的 IP > " ""
  valid_ip_or_cidr "$value" || { warn "IP 格式无效"; return 1; }
  [[ "$value" != */* ]] || { warn "解封操作请输入单个 IP，不支持 CIDR"; return 1; }
  if fail2ban-client set sshd unbanip "$value" >/dev/null 2>&1; then
    ok "已请求解封：${value}"
  else
    warn "解封失败：请确认 sshd jail 正在运行且该 IP 已被封禁"
    return 1
  fi
}

fail2ban_disable_sshd() {
  [[ -f "$FAIL2BAN_JAIL_FILE" ]] || { warn "未找到脚本创建的 Fail2Ban 配置"; return 1; }
  warn "将关闭脚本配置的 sshd jail；不会卸载 Fail2Ban"
  confirm_word "DISABLE" "确认请输入 DISABLE > " || { warn "已取消"; return 0; }
  local had_original="0" rollback_file=""
  rollback_file="$(mktemp /tmp/dmitbox-fail2ban-disable.XXXXXX)" || {
    warn "无法创建临时回滚文件"
    return 1
  }
  cp -a "$FAIL2BAN_JAIL_FILE" "$rollback_file" || {
    rm -f "$rollback_file" >/dev/null 2>&1 || true
    warn "无法备份当前 Fail2Ban 配置，已取消"
    return 1
  }
  had_original="$(cat "$FAIL2BAN_ORIG_MARKER" 2>/dev/null || echo 0)"
  if [[ "$had_original" == "1" && -s "$FAIL2BAN_BACKUP" ]]; then
    cp -a "$FAIL2BAN_BACKUP" "$FAIL2BAN_JAIL_FILE"
    info "已恢复脚本接管前的同名 Fail2Ban 配置"
  else
    rm -f "$FAIL2BAN_JAIL_FILE" >/dev/null 2>&1 || true
  fi
  if have_cmd fail2ban-client; then
    if ! fail2ban_validate || ! fail2ban_service_restart; then
      warn "恢复/移除配置后 Fail2Ban 校验或重启失败，正在回滚"
      cp -a "$rollback_file" "$FAIL2BAN_JAIL_FILE" >/dev/null 2>&1 || true
      fail2ban_service_restart >/dev/null 2>&1 || true
      rm -f "$rollback_file" >/dev/null 2>&1 || true
      return 1
    fi
  else
    warn "fail2ban-client 不存在，仅完成配置恢复，无法校验服务"
  fi
  rm -f "$rollback_file" >/dev/null 2>&1 || true
  rm -f "$FAIL2BAN_ORIG_MARKER" >/dev/null 2>&1 || true
  ok "脚本配置的 SSH 防爆破已关闭"
}

fail2ban_menu() {
  while true; do
    menu_header "Fail2Ban SSH 防爆破" "自动识别 SSH 端口 · 白名单 · 封禁状态"
    menu_section "管理"
    menu_item "1" "查看状态与日志" "sshd jail、封禁 IP 和最近日志"
    menu_item "2" "安装或修复配置" "5 次失败，封禁 1 小时"
    menu_item "3" "添加白名单" "支持单个 IP 或 CIDR"
    menu_item "4" "解封 IP" "从 sshd jail 中解除封禁"
    menu_item "5" "关闭 SSH 防爆破" "不卸载 Fail2Ban"
    menu_back_item
    local c=""
    read_tty c "请输入编号 > " ""
    case "$c" in
      1) fail2ban_status || true; pause_up ;;
      2) fail2ban_install_configure || true; pause_up ;;
      3) fail2ban_add_whitelist || true; pause_up ;;
      4) fail2ban_unban_ip || true; pause_up ;;
      5) fail2ban_disable_sshd || true; pause_up ;;
      0|q|Q) return 0 ;;
      *) warn "无效选项"; pause_up ;;
    esac
  done
}

# ======================================================================
# 安全静态网站
# 公网 HTTP 负责证书验证，配置域名通过公网 HTTPS 访问；可选 CDN 自动停站。
# 不修改或输出任何第三方程序配置。
# ======================================================================
valid_domain_name() {
  local domain="${1:-}" label=""
  [[ ${#domain} -ge 4 && ${#domain} -le 253 ]] || return 1
  [[ "$domain" == *.* && "$domain" != .* && "$domain" != *. ]] || return 1
  [[ "$domain" =~ ^[A-Za-z0-9.-]+$ ]] || return 1
  local IFS='.'
  local -a labels=()
  read -r -a labels <<< "$domain"
  (( ${#labels[@]} >= 2 )) || return 1
  for label in "${labels[@]}"; do
    [[ ${#label} -ge 1 && ${#label} -le 63 ]] || return 1
    [[ "$label" =~ ^[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?$ ]] || return 1
  done
  [[ "${labels[${#labels[@]}-1]}" =~ [A-Za-z] ]] || return 1
  valid_ip_or_cidr "$domain" && return 1
  return 0
}

valid_email_address() {
  local value="${1:-}"
  [[ -z "$value" || "$value" =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,63}$ ]]
}

random_uint_between() {
  local min="$1" max="$2" span=0
  (( min <= max )) || return 1
  span=$((max - min + 1))
  echo $((min + ((RANDOM << 15 | RANDOM) % span)))
}

secure_site_conf_value() {
  local key="$1"
  [[ -r "$SECURE_SITE_CONF" ]] || return 1
  awk -F= -v key="$key" '$1 == key {sub(/^[^=]*=/, ""); print; exit}' "$SECURE_SITE_CONF"
}

secure_site_conf_is_managed() {
  [[ -f "$SECURE_SITE_CONF" ]] && grep -Fqx '# managed by dmitbox.sh - secure static website' "$SECURE_SITE_CONF"
}

secure_site_select_nginx_paths() {
  local distro_id=""
  distro_id="$(awk -F= '$1 == "ID" {gsub(/\"/, "", $2); print tolower($2); exit}' /etc/os-release 2>/dev/null || true)"
  if [[ -d /etc/nginx/http.d ]] || [[ "$distro_id" == "alpine" ]] || \
     grep -Eq 'include[[:space:]]+/?etc/nginx/http\.d/\*\.conf' /etc/nginx/nginx.conf 2>/dev/null; then
    SECURE_SITE_NGINX_CONF="/etc/nginx/http.d/dmitbox-secure-site.conf"
    SECURE_SITE_NGINX_LIMIT_CONF="/etc/nginx/http.d/00-dmitbox-secure-site-zones.conf"
    SECURE_SITE_NGINX_ACTIVE_CONF="/etc/nginx/http.d/dmitbox-secure-site-domain.conf"
  else
    SECURE_SITE_NGINX_CONF="/etc/nginx/conf.d/dmitbox-secure-site.conf"
    SECURE_SITE_NGINX_LIMIT_CONF="/etc/nginx/conf.d/00-dmitbox-secure-site-zones.conf"
    SECURE_SITE_NGINX_ACTIVE_CONF="/etc/nginx/conf.d/dmitbox-secure-site-domain.conf"
  fi
}

secure_site_nginx_files_are_managed() {
  secure_site_select_nginx_paths
  [[ -f "$SECURE_SITE_NGINX_CONF" && -f "$SECURE_SITE_NGINX_LIMIT_CONF" ]] || return 1
  grep -Fq '# managed by dmitbox.sh - secure static website' "$SECURE_SITE_NGINX_CONF" || return 1
  grep -Fq '# managed by dmitbox.sh - secure static website' "$SECURE_SITE_NGINX_LIMIT_CONF" || return 1
  if [[ -e "$SECURE_SITE_NGINX_ACTIVE_CONF" || -e "$SECURE_SITE_NGINX_PAUSED_CONF" ]]; then
    [[ -f "$SECURE_SITE_NGINX_ACTIVE_CONF" && ! -e "$SECURE_SITE_NGINX_PAUSED_CONF" ]] || \
      [[ -f "$SECURE_SITE_NGINX_PAUSED_CONF" && ! -e "$SECURE_SITE_NGINX_ACTIVE_CONF" ]] || return 1
    if [[ -f "$SECURE_SITE_NGINX_ACTIVE_CONF" ]]; then
      grep -Fq '# managed by dmitbox.sh - secure static website' "$SECURE_SITE_NGINX_ACTIVE_CONF"
    else
      grep -Fq '# managed by dmitbox.sh - secure static website' "$SECURE_SITE_NGINX_PAUSED_CONF"
    fi
    return $?
  fi
  # r15 and earlier kept the domain server in the base file; interrupted installs may be in HTTP bootstrap mode.
  grep -Eq 'DMITBOX_(PUBLIC_TLS_SITE|HTTP_BOOTSTRAP)' "$SECURE_SITE_NGINX_CONF"
}

secure_site_aux_files_are_managed_or_absent() {
  local path=""
  for path in "$SECURE_SITE_DNS_WATCH" "$SECURE_SITE_DNS_WATCH_CRON" \
    "$SECURE_SITE_DNS_WATCH_PERIODIC" "$SECURE_SITE_DNS_WATCH_SERVICE" \
    "$SECURE_SITE_DNS_WATCH_TIMER" "$SECURE_SITE_DNS_STATUS"; do
    [[ ! -e "$path" ]] || \
      grep -Fq '# managed by dmitbox.sh - secure static website' "$path" 2>/dev/null || return 1
  done
}

secure_site_nginx_supports_ssl_reject_handshake() {
  local version="" major="0" minor="0" patch="0"
  have_cmd nginx || return 1
  version="$(nginx -v 2>&1 | sed -nE 's#.*nginx/([0-9]+(\.[0-9]+){1,2}).*#\1#p' | head -n 1)"
  [[ -n "$version" ]] || return 1
  IFS='.' read -r major minor patch <<< "$version"
  major="${major:-0}"
  minor="${minor:-0}"
  patch="${patch:-0}"
  is_uint_in_range "$major" 0 999 || return 1
  is_uint_in_range "$minor" 0 999 || return 1
  is_uint_in_range "$patch" 0 999 || return 1
  (( 10#$major > 1 || \
     (10#$major == 1 && 10#$minor > 19) || \
     (10#$major == 1 && 10#$minor == 19 && 10#$patch >= 4) ))
}

secure_site_dns_raw_records() {
  local domain="$1" rrtype="$2" output=""
  [[ "$rrtype" == "A" || "$rrtype" == "AAAA" ]] || return 1

  # Public-DNS checks must bypass /etc/hosts.  The local-origin lock deliberately
  # pins this domain to 127.0.0.1 for local programs, so getent would report the
  # lock instead of the authoritative public A/AAAA records.
  have_cmd dig || return 2
  if output="$(dig +time=4 +tries=1 +short "$domain" "$rrtype" 2>/dev/null)"; then
    printf '%s\n' "$output"
    return 0
  fi
  return 1
}

secure_site_install_dns_query_tool() {
  have_cmd dig && return 0
  if have_cmd apt-get; then
    pkg_install dnsutils
  elif have_cmd apk; then
    pkg_install bind-tools
  else
    pkg_install bind-utils
  fi
  have_cmd dig
}

secure_site_dns_records() {
  local domain="$1" rrtype="$2" value=""
  local -a candidates=()
  while IFS=$' \t' read -r value _; do
    [[ -n "$value" ]] && candidates+=("$value")
  done < <(secure_site_dns_raw_records "$domain" "$rrtype")

  if have_cmd python3; then
    python3 - "$rrtype" "${candidates[@]}" <<'PY' | sort -u
import ipaddress
import sys

record_type = sys.argv[1]
for candidate in sys.argv[2:]:
    try:
        address = ipaddress.ip_address(candidate.rstrip("."))
    except ValueError:
        continue
    if record_type == "A" and address.version == 4:
        print(address)
    elif record_type == "AAAA" and address.version == 6:
        # libc may synthesize ::ffff:a.b.c.d for an A-only hostname. It is
        # not an AAAA record and must never participate in the DNS audit.
        if address.ipv4_mapped is not None:
            continue
        if int(address) <= 0xFFFFFFFF:
            continue
        print(address.compressed)
PY
    return 0
  fi

  {
    for value in "${candidates[@]}"; do
      value="${value,,}"
      if [[ "$rrtype" == "A" ]]; then
        if [[ "$value" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
          local part="" valid="1"
          local IFS='.'
          local -a parts=()
          read -r -a parts <<< "$value"
          for part in "${parts[@]}"; do
            (( 10#$part <= 255 )) || { valid="0"; break; }
          done
          [[ "$valid" == "1" ]] && echo "$value"
        fi
      elif [[ "$value" == *:* && "$value" != ::ffff:* && ! "$value" =~ ^::[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        echo "$value"
      fi
    done
  } | sort -u
}

secure_site_filter_synthetic_aaaa() {
  local -a values=("$@")
  if ! have_cmd python3; then
    local mode="a" value=""
    for value in "${values[@]}"; do
      case "$value" in
        __AAAA__) mode="aaaa" ;;
        __DNS64__) mode="dns64" ;;
        *)
          if [[ "$mode" == "aaaa" && "$value" != 64:ff9b:* ]]; then
            echo "$value"
          fi
          ;;
      esac
    done
    return 0
  fi

  python3 - "${values[@]}" <<'PY'
import ipaddress
import sys

args = sys.argv[1:]
aaaa_at = args.index("__AAAA__")
dns64_at = args.index("__DNS64__")
ipv4 = [ipaddress.IPv4Address(value) for value in args[:aaaa_at]]
ipv6 = [ipaddress.IPv6Address(value) for value in args[aaaa_at + 1:dns64_at]]
discovery = [ipaddress.IPv6Address(value) for value in args[dns64_at + 1:]]

lengths = (32, 40, 48, 56, 64, 96)

def mask(length):
    return ((1 << length) - 1) << (128 - length)

def embed(prefix, length, address):
    v4 = int(address)
    result = prefix & mask(length)
    if length == 96:
        return result | v4
    before_u = 64 - length
    if before_u:
        result |= (v4 >> (32 - before_u)) << 64
    remaining = 32 - before_u
    if remaining:
        result |= (v4 & ((1 << remaining) - 1)) << (56 - remaining)
    return result

# Always recognize the two IANA NAT64 prefixes. Discover custom RFC 6052
# prefixes from ipv4only.arpa when the active resolver performs DNS64.
prefixes = {
    (int(ipaddress.IPv6Address("64:ff9b::")), 96),
    (int(ipaddress.IPv6Address("64:ff9b:1::")), 48),
}
well_known_v4 = (ipaddress.IPv4Address("192.0.0.170"), ipaddress.IPv4Address("192.0.0.171"))
for synthesized in discovery:
    for address in well_known_v4:
        for length in lengths:
            prefix = int(synthesized) & mask(length)
            if embed(prefix, length, address) == int(synthesized):
                prefixes.add((prefix, length))

for address6 in ipv6:
    synthesized = any(
        embed(prefix, length, address4) == int(address6)
        for prefix, length in prefixes
        for address4 in ipv4
    )
    if not synthesized:
        print(address6.compressed)
PY
}

secure_site_effective_dns_addresses() {
  local domain="$1"
  local -a a_records=() raw_aaaa_records=() aaaa_records=() dns64_discovery=()
  mapfile -t a_records < <(secure_site_dns_records "$domain" A)
  mapfile -t raw_aaaa_records < <(secure_site_dns_records "$domain" AAAA)
  if (( ${#a_records[@]} > 0 && ${#raw_aaaa_records[@]} > 0 )); then
    mapfile -t dns64_discovery < <(secure_site_dns_records ipv4only.arpa AAAA)
    mapfile -t aaaa_records < <(
      secure_site_filter_synthetic_aaaa \
        "${a_records[@]}" __AAAA__ "${raw_aaaa_records[@]}" __DNS64__ "${dns64_discovery[@]}"
    )
  else
    aaaa_records=("${raw_aaaa_records[@]}")
  fi
  printf '%s\n' "${a_records[@]}" "${aaaa_records[@]}" | awk 'NF' | sort -u
}

secure_site_dns_baseline() {
  local domain="$1"
  secure_site_effective_dns_addresses "$domain" | awk 'NF' | sort -u | paste -sd, -
}

secure_site_addresses_use_cloudflare() {
  (( $# > 0 )) || return 1
  have_cmd python3 || return 2
  python3 - "$@" <<'PY'
import ipaddress
import sys

# Official public proxy ranges: https://www.cloudflare.com/ips/
networks = tuple(ipaddress.ip_network(value) for value in (
    "173.245.48.0/20", "103.21.244.0/22", "103.22.200.0/22",
    "103.31.4.0/22", "141.101.64.0/18", "108.162.192.0/18",
    "190.93.240.0/20", "188.114.96.0/20", "197.234.240.0/22",
    "198.41.128.0/17", "162.158.0.0/15", "104.16.0.0/13",
    "104.24.0.0/14", "172.64.0.0/13", "131.0.72.0/22",
    "2400:cb00::/32", "2606:4700::/32", "2803:f800::/32",
    "2405:b500::/32", "2405:8100::/32", "2a06:98c0::/29",
    "2c0f:f248::/32",
))

for value in sys.argv[1:]:
    try:
        address = ipaddress.ip_address(value)
    except ValueError:
        continue
    if any(address in network for network in networks):
        raise SystemExit(0)
raise SystemExit(1)
PY
}

secure_site_domain_uses_cloudflare() {
  local domain="$1"
  local -a addresses=()
  mapfile -t addresses < <(secure_site_effective_dns_addresses "$domain")
  (( ${#addresses[@]} > 0 )) || return 2
  secure_site_addresses_use_cloudflare "${addresses[@]}"
}

secure_site_legacy_firewall_present() {
  local command_name=""
  if have_cmd nft && nft list table inet dmitbox_cdn_guard >/dev/null 2>&1; then
    return 0
  fi
  for command_name in iptables ip6tables; do
    have_cmd "$command_name" || continue
    "$command_name" -C INPUT -j DMITBOX_CDN_GUARD >/dev/null 2>&1 && return 0
    "$command_name" -S DMITBOX_CDN_GUARD >/dev/null 2>&1 && return 0
  done
  return 1
}

secure_site_guard_remove_firewall_rules() {
  local command_name="" rc=0 chain_exists=0
  if have_cmd nft && nft list table inet dmitbox_cdn_guard >/dev/null 2>&1; then
    nft delete table inet dmitbox_cdn_guard >/dev/null 2>&1 || rc=1
  fi
  for command_name in iptables ip6tables; do
    have_cmd "$command_name" || continue
    while "$command_name" -C INPUT -j DMITBOX_CDN_GUARD >/dev/null 2>&1; do
      "$command_name" -D INPUT -j DMITBOX_CDN_GUARD >/dev/null 2>&1 || { rc=1; break; }
    done
    chain_exists=0
    "$command_name" -S DMITBOX_CDN_GUARD >/dev/null 2>&1 && chain_exists=1
    if (( chain_exists == 1 )); then
      "$command_name" -F DMITBOX_CDN_GUARD >/dev/null 2>&1 || rc=1
      "$command_name" -X DMITBOX_CDN_GUARD >/dev/null 2>&1 || rc=1
    fi
  done
  return "$rc"
}

secure_site_cleanup_legacy_firewall_on_start() {
  secure_site_legacy_firewall_present || return 0
  if secure_site_guard_remove_firewall_rules; then
    ok "已清理旧版建站功能遗留的 nftables/iptables 拦截规则"
    info "仅删除 dmitbox_cdn_guard / DMITBOX_CDN_GUARD；其他防火墙规则未改动"
  else
    warn "发现旧版建站防火墙规则，但未能完整清理"
    warn "请进入“系统状态与端口 → 端口访问修复”再次检查"
    return 1
  fi
}

secure_site_ip_server_names() {
  local domain="$1" value="" names="localhost 127.0.0.1"
  local -a addresses=()
  mapfile -t addresses < <(secure_site_effective_dns_addresses "$domain")
  for value in "${addresses[@]}"; do
    [[ -n "$value" ]] && names+=" ${value}"
  done
  printf '%s\n' "$names"
}

secure_site_local_addresses() {
  {
    ip -o -4 address show scope global 2>/dev/null | awk '{split($4,a,"/"); print a[1]}' || true
    ip -o -6 address show scope global 2>/dev/null | awk '{split($4,a,"/"); print a[1]}' || true
    if have_cmd curl; then
      curl -4 -fsS --max-time 6 https://api.ip.sb/ip 2>/dev/null || true
      echo
      curl -6 -fsS --max-time 6 https://api.ip.sb/ip 2>/dev/null || true
      echo
    fi
  } | awk 'NF && $1 ~ /^[0-9A-Fa-f:.]+$/ {print $1}' | sort -u
}

secure_site_addresses_are_local() {
  local separator="__DMITBOX_LOCAL_ADDRESSES__" value=""
  local -a dns_addresses=("$@") local_addresses=()
  local split_at="-1" i=0
  for value in "${dns_addresses[@]}"; do
    if [[ "$value" == "$separator" ]]; then split_at="$i"; break; fi
    i=$((i + 1))
  done
  (( split_at >= 0 )) || return 1
  local_addresses=("${dns_addresses[@]:split_at+1}")
  dns_addresses=("${dns_addresses[@]:0:split_at}")

  if have_cmd python3; then
    python3 - "${dns_addresses[@]}" "$separator" "${local_addresses[@]}" >/dev/null 2>&1 <<'PY'
import ipaddress
import sys

sep = sys.argv.index("__DMITBOX_LOCAL_ADDRESSES__")
dns = {ipaddress.ip_address(value) for value in sys.argv[1:sep]}
local = {ipaddress.ip_address(value) for value in sys.argv[sep + 1:]}
raise SystemExit(0 if dns and dns.issubset(local) else 1)
PY
    return $?
  fi

  local dns_ip="" local_ip="" found="0"
  for dns_ip in "${dns_addresses[@]}"; do
    found="0"
    for local_ip in "${local_addresses[@]}"; do
      [[ "$dns_ip" == "$local_ip" ]] && { found="1"; break; }
    done
    [[ "$found" == "1" ]] || return 1
  done
  (( ${#dns_addresses[@]} > 0 ))
}

secure_site_dns_audit() {
  local domain="$1" value="" ignored_aaaa="0" mismatch="0"
  local -a a_records=() raw_aaaa_records=() aaaa_records=() dns64_discovery=()
  local -a dns_addresses=() local_addresses=()
  if ! have_cmd dig; then
    warn "缺少 dig，无法绕过本机 hosts 锁定核对公网 DNS"
    info "请安装 dnsutils（Debian/Ubuntu）、bind-utils（CentOS/RHEL）或 bind-tools（Alpine）"
    return 2
  fi
  mapfile -t a_records < <(secure_site_dns_records "$domain" A)
  mapfile -t raw_aaaa_records < <(secure_site_dns_records "$domain" AAAA)
  if (( ${#a_records[@]} > 0 && ${#raw_aaaa_records[@]} > 0 )); then
    mapfile -t dns64_discovery < <(secure_site_dns_records ipv4only.arpa AAAA)
    mapfile -t aaaa_records < <(
      secure_site_filter_synthetic_aaaa \
        "${a_records[@]}" __AAAA__ "${raw_aaaa_records[@]}" __DNS64__ "${dns64_discovery[@]}"
    )
    ignored_aaaa=$((${#raw_aaaa_records[@]} - ${#aaaa_records[@]}))
  else
    aaaa_records=("${raw_aaaa_records[@]}")
  fi
  dns_addresses=("${a_records[@]}" "${aaaa_records[@]}")
  mapfile -t local_addresses < <(secure_site_local_addresses)

  print_kv "域名" "$domain"
  if (( ${#dns_addresses[@]} == 0 )); then
    warn "域名没有可用的 A/AAAA 解析"
    return 1
  fi
  echo -e "  ${c_dim}A 记录（IPv4）：${c_reset}"
  if (( ${#a_records[@]} == 0 )); then
    echo "    - 未配置"
  else
    for value in "${a_records[@]}"; do echo "    - $value"; done
  fi
  echo -e "  ${c_dim}AAAA 记录（IPv6）：${c_reset}"
  if (( ${#aaaa_records[@]} == 0 )); then
    echo "    - 未配置"
  else
    for value in "${aaaa_records[@]}"; do echo "    - $value"; done
  fi
  if (( ignored_aaaa > 0 )); then
    info "已忽略 ${ignored_aaaa} 个由本机解析器生成的 DNS64 地址，它们不是域名的真实 AAAA 记录"
  fi
  echo -e "  ${c_dim}本机地址：${c_reset}"
  if (( ${#local_addresses[@]} == 0 )); then
    echo "    - 无法识别"
    warn "无法识别本机公网地址"
    return 1
  fi
  for value in "${local_addresses[@]}"; do echo "    - $value"; done

  if secure_site_addresses_are_local "${dns_addresses[@]}" '__DMITBOX_LOCAL_ADDRESSES__' "${local_addresses[@]}"; then
    ok "全部 DNS 地址均直接指向本机"
    return 0
  fi
  warn "以下 DNS 记录没有指向本机："
  for value in "${a_records[@]}"; do
    if ! secure_site_addresses_are_local "$value" '__DMITBOX_LOCAL_ADDRESSES__' "${local_addresses[@]}"; then
      echo "    - A     $value"
      mismatch="1"
    fi
  done
  for value in "${aaaa_records[@]}"; do
    if ! secure_site_addresses_are_local "$value" '__DMITBOX_LOCAL_ADDRESSES__' "${local_addresses[@]}"; then
      echo "    - AAAA  $value"
      mismatch="1"
    fi
  done
  [[ "$mismatch" == "1" ]] || warn "DNS 与本机地址比较失败"
  warn "可能启用了 CDN/代理，或 DNS 中仍有旧记录"
  return 1
}

secure_site_port_listener() {
  local port="$1"
  if have_cmd ss; then
    ss -H -ltnp 2>/dev/null | awk -v port="$port" '$4 ~ (":" port "$") {print}'
  elif have_cmd netstat; then
    netstat -lntp 2>/dev/null | awk -v port="$port" '$4 ~ (":" port "$") {print}'
  fi
}

secure_site_find_default_tls_server() {
  local port="${1:-443}" output="" conflict=""
  is_uint_in_range "$port" 1 65535 || return 1
  have_cmd nginx || return 1
  output="$(nginx -T 2>&1)" || return 1
  conflict="$(awk -v port="$port" '
    /^# configuration file / {
      file=$0
      sub(/^# configuration file /, "", file)
      sub(/:$/, "", file)
      next
    }
    {
      line=$0
      sub(/[[:space:]]*#.*/, "", line)
      if (line !~ /(^|[[:space:]{;])listen[[:space:]]/) next
      if (line !~ /(^|[[:space:]])default_server([[:space:];]|$)/) next
      count=split(line, fields, /[[:space:]]+/)
      endpoint=""
      for (i=1; i<=count; i++) {
        if (fields[i] == "listen" && i < count) {
          endpoint=fields[i+1]
          sub(/;$/, "", endpoint)
          break
        }
      }
      if (endpoint == port || endpoint ~ (":" port "$")) print file
    }
  ' <<< "$output" | awk 'NF' | sort -u | grep -Fvx "$SECURE_SITE_NGINX_CONF" | head -n 1 || true)"
  [[ -n "$conflict" ]] || return 1
  printf '%s\n' "$conflict"
}

secure_site_check_web_ports() {
  local listener80="" listener443="" conflict=""
  listener80="$(secure_site_port_listener 80 || true)"
  if [[ -n "$listener80" ]]; then
    if grep -qi 'nginx' <<< "$listener80"; then
      info "80/tcp 当前由 Nginx 使用，可复用"
    else
      warn "80/tcp 已被其他程序占用，无法提供证书验证与 HTTP 跳转："
      echo "$listener80"
      return 1
    fi
  fi

  listener443="$(secure_site_port_listener 443 || true)"
  if [[ -n "$listener443" ]]; then
    if grep -qi 'nginx' <<< "$listener443"; then
      info "443/tcp 当前由 Nginx 使用，可复用"
    else
      warn "443/tcp 已被其他程序占用，无法部署域名 HTTPS："
      echo "$listener443"
      return 1
    fi
  else
    info "443/tcp 当前空闲，可用于域名 HTTPS"
  fi

  conflict="$(secure_site_find_default_tls_server 443 2>/dev/null || true)"
  if [[ -n "$conflict" ]]; then
    warn "其他 Nginx 配置已占用 443 的默认 TLS 站点：$conflict"
    warn "为避免覆盖现有 HTTPS 服务，请先调整该配置后再试"
    return 1
  fi
  return 0
}

secure_site_find_conflict_domain() {
  local domain="$1" path=""
  [[ -d /etc/nginx ]] || return 1
  while IFS= read -r path; do
    [[ "$path" == "$SECURE_SITE_NGINX_CONF" || \
       "$path" == "$SECURE_SITE_NGINX_ACTIVE_CONF" || \
       "$path" == "$SECURE_SITE_NGINX_PAUSED_CONF" ]] && continue
    if grep -Ei "^[[:space:]]*server_name[[:space:]][^;]*${domain//./\\.}([[:space:];]|$)" "$path" >/dev/null 2>&1; then
      echo "$path"
      return 0
    fi
  done < <(find /etc/nginx -type f -name '*.conf' 2>/dev/null | sort)
  return 1
}

secure_site_other_nginx_server_files() {
  local output=""
  secure_site_select_nginx_paths
  have_cmd nginx || return 0
  output="$(nginx -T 2>&1)" || return 2
  awk -v base="$SECURE_SITE_NGINX_CONF" \
      -v active="$SECURE_SITE_NGINX_ACTIVE_CONF" \
      -v limit="$SECURE_SITE_NGINX_LIMIT_CONF" '
    /^# configuration file / {
      file=$0
      sub(/^# configuration file /, "", file)
      sub(/:$/, "", file)
      next
    }
    {
      line=$0
      sub(/[[:space:]]*#.*/, "", line)
      if (line !~ /^[[:space:]]*server([[:space:]]*\{|[[:space:]]*$)/) next
      if (file == base || file == active || file == limit) next
      if (file == "/etc/nginx/sites-enabled/default" ||
          file == "/etc/nginx/conf.d/default.conf" ||
          file == "/etc/nginx/http.d/default.conf") next
      if (file != "") print file
    }
  ' <<< "$output" | awk 'NF' | sort -u
}

secure_site_assert_nginx_exclusive() {
  local others="" path=""
  if ! others="$(secure_site_other_nginx_server_files)"; then
    warn "无法核对 Nginx 是否还有其他站点，拒绝启用整服务停站"
    return 1
  fi
  [[ -z "$others" ]] && return 0
  warn "检测到其他 Nginx 站点配置，不能安全停止整个 Nginx："
  while IFS= read -r path; do
    [[ -n "$path" ]] && echo "    - $path"
  done <<< "$others"
  warn "请先移除其他站点；整服务停站仅适用于本机没有其他 Nginx 网站的情况"
  return 1
}

secure_site_linked_service_normalize() {
  local name="${1:-}"
  name="${name%.service}"
  printf '%s\n' "$name"
}

secure_site_linked_service_name_valid() {
  local name=""
  name="$(secure_site_linked_service_normalize "${1:-}")"
  [[ "$name" =~ ^[A-Za-z0-9][A-Za-z0-9_.@-]{0,126}$ ]] || return 1
  case "${name,,}" in
    nginx|ssh|sshd|cron|crond|networking|network-manager|networkmanager|dbus|systemd-*|dmitbox-site-dns-watch)
      return 1
      ;;
  esac
}

secure_site_linked_service_exists() {
  local name=""
  name="$(secure_site_linked_service_normalize "${1:-}")"
  secure_site_linked_service_name_valid "$name" || return 1
  if secure_site_systemd_running; then
    local load_state=""
    load_state="$(systemctl show -p LoadState --value "${name}.service" 2>/dev/null || true)"
    [[ "$load_state" == "loaded" || "$load_state" == "masked" ]]
  elif have_cmd rc-service; then
    [[ -x "/etc/init.d/${name}" ]] || rc-service -e 2>/dev/null | grep -Fxq "$name"
  elif [[ -x "${SECURE_SITE_INIT_DIR}/${name}" ]]; then
    return 0
  else
    return 1
  fi
}

secure_site_linked_service_running() {
  local name=""
  name="$(secure_site_linked_service_normalize "${1:-}")"
  secure_site_linked_service_name_valid "$name" || return 1
  if secure_site_systemd_running; then
    systemctl is-active --quiet "${name}.service" >/dev/null 2>&1
  elif have_cmd rc-service; then
    rc-service "$name" status >/dev/null 2>&1
  elif have_cmd service; then
    service "$name" status >/dev/null 2>&1
  else
    return 1
  fi
}

secure_site_linked_service_boot_enabled() {
  local name=""
  name="$(secure_site_linked_service_normalize "${1:-}")"
  secure_site_linked_service_name_valid "$name" || return 1
  if secure_site_systemd_running; then
    systemctl is-enabled --quiet "${name}.service" >/dev/null 2>&1
  elif have_cmd rc-update; then
    rc-update show default 2>/dev/null | awk '{print $1}' | grep -Fxq "$name"
  else
    compgen -G "/etc/rc[2-5].d/S??${name}" >/dev/null 2>&1
  fi
}

secure_site_linked_service_start_now() {
  local name="" boot_enabled="${2:-0}" rc=0
  name="$(secure_site_linked_service_normalize "${1:-}")"
  secure_site_linked_service_exists "$name" || return 1
  [[ "$boot_enabled" == "0" || "$boot_enabled" == "1" ]] || return 1
  if secure_site_systemd_running; then
    systemctl unmask --runtime "${name}.service" >/dev/null 2>&1 || true
    if [[ "$boot_enabled" == "1" ]]; then
      systemctl enable "${name}.service" >/dev/null 2>&1 || rc=1
    else
      systemctl disable "${name}.service" >/dev/null 2>&1 || true
    fi
    systemctl start "${name}.service" >/dev/null 2>&1 || rc=1
  elif have_cmd rc-service; then
    if [[ "$boot_enabled" == "1" ]] && have_cmd rc-update; then
      rc-update add "$name" default >/dev/null 2>&1 || rc=1
    elif have_cmd rc-update; then
      rc-update del "$name" default >/dev/null 2>&1 || true
    fi
    rc-service "$name" start >/dev/null 2>&1 || rc=1
  elif have_cmd service; then
    if have_cmd update-rc.d; then
      if [[ "$boot_enabled" == "1" ]]; then
        update-rc.d "$name" enable >/dev/null 2>&1 || rc=1
      else
        update-rc.d "$name" disable >/dev/null 2>&1 || true
      fi
    fi
    service "$name" start >/dev/null 2>&1 || rc=1
  else
    return 1
  fi
  (( rc == 0 )) && secure_site_linked_service_running "$name"
}

secure_site_choose_linked_service() {
  local domain="$1" existing_enabled="${2:-0}" existing_name="${3:-}"
  local existing_boot="${4:-1}" input="" normalized="" boot_enabled="0"
  SECURE_SITE_SELECTED_LINKED_ENABLED="0"
  SECURE_SITE_SELECTED_LINKED_NAME=""
  SECURE_SITE_SELECTED_LINKED_BOOT="1"
  existing_name="$(secure_site_linked_service_normalize "$existing_name")"
  [[ "$existing_enabled" == "0" || "$existing_enabled" == "1" ]] || existing_enabled="0"
  [[ "$existing_boot" == "0" || "$existing_boot" == "1" ]] || existing_boot="1"

  menu_section "关联服务联动保护"
  info "可将一个独立系统服务与网站同步停复，Cloudflare 命中后其全部监听端口和现有连接都会停止"
  info "请输入 systemd/OpenRC/SysV 服务名；填写 .service 后缀也可以"
  warn "被选服务中的全部功能都会一起停止；请勿填写 SSH、网络、定时任务等系统关键服务"
  read_tty input "关联服务名（强烈建议配置；留空不联动，输入 - 取消已有联动）> " \
    "$([[ "$existing_enabled" == "1" ]] && echo "$existing_name" || true)"
  if [[ -z "$input" || "$input" == "-" ]]; then
    if [[ "$existing_enabled" == "1" ]] && secure_site_domain_uses_cloudflare "$domain"; then
      warn "当前正处于 Cloudflare 停站状态，不能直接取消已有联动"
      info "请先停用自动保护，恢复直连后再重新设置"
      return 1
    fi
    warn "未配置关联服务：只能保护网站，无法阻止其他独立监听端口继续转发流量"
    confirm_word "SKIP" "确认仅保护网站请输入 SKIP > " || { warn "已取消"; return 1; }
    return 0
  fi

  normalized="$(secure_site_linked_service_normalize "$input")"
  secure_site_linked_service_name_valid "$normalized" || {
    warn "服务名无效或属于禁止联动的系统关键服务"
    return 1
  }
  secure_site_linked_service_exists "$normalized" || {
    warn "没有找到系统服务：${normalized}.service"
    return 1
  }
  if [[ "$existing_enabled" != "1" || "$normalized" != "$existing_name" ]]; then
    secure_site_linked_service_running "$normalized" || {
      warn "新关联服务当前未运行，无法确认其正常状态，拒绝接管"
      return 1
    }
    secure_site_linked_service_boot_enabled "$normalized" && boot_enabled="1"
  else
    boot_enabled="$existing_boot"
  fi
  if [[ "$existing_enabled" == "1" && "$normalized" != "$existing_name" ]] && \
     secure_site_domain_uses_cloudflare "$domain"; then
    warn "当前正处于 Cloudflare 停站状态，不能直接更换已有联动服务"
    info "请先停用自动保护，恢复直连后再更换"
    return 1
  fi

  print_kv "关联服务" "${normalized}.service"
  print_kv "触发动作" "停止服务并禁止自动重启"
  print_kv "恢复动作" "恢复原启动属性并启动服务"
  warn "Cloudflare 命中时 ${normalized}.service 的全部连接都会立即中断"
  confirm_word "LINK" "确认关联请输入 LINK > " || { warn "已取消"; return 1; }
  SECURE_SITE_SELECTED_LINKED_ENABLED="1"
  SECURE_SITE_SELECTED_LINKED_NAME="$normalized"
  SECURE_SITE_SELECTED_LINKED_BOOT="$boot_enabled"
}

secure_site_nav_cards() {
  local data="$1" badge="" name="" description="" url="" color=""
  while IFS='|' read -r badge name description url color; do
    [[ -n "$badge" && -n "$name" && "$url" == https://* && "$color" =~ ^c[1-8]$ ]] || continue
    printf '          <a class="site" href="%s" target="_blank" rel="noopener noreferrer"><span class="site-badge %s">%s</span><span class="site-copy"><strong>%s</strong><small>%s</small></span></a>\n' \
      "$url" "$color" "$badge" "$name" "$description"
  done <<< "$data"
}

secure_site_generate_homepage() {
  local domain="$1" template="${2:-4}"
  local accent="#2563eb" accent_dark="#1d4ed8" accent_soft="#eff6ff"
  local gradient_a="#dbeafe" gradient_b="#f8fafc" theme_label="经典蓝"
  local favorites_html="" news_html="" media_html="" study_html=""
  local life_html="" cloud_html="" tools_html="" build_id="" year=""

  [[ "$template" =~ ^[1-4]$ ]] || template="4"
  [[ "$template" != "4" ]] || template="$(random_uint_between 1 3)"
  case "$template" in
    1)
      accent="#2563eb"; accent_dark="#1d4ed8"; accent_soft="#eff6ff"
      gradient_a="#dbeafe"; gradient_b="#f8fafc"; theme_label="经典蓝"
      ;;
    2)
      accent="#0f8f68"; accent_dark="#087554"; accent_soft="#ecfdf5"
      gradient_a="#d1fae5"; gradient_b="#f8fafc"; theme_label="清新绿"
      ;;
    3)
      accent="#ea580c"; accent_dark="#c2410c"; accent_soft="#fff7ed"
      gradient_a="#ffedd5"; gradient_b="#fffaf5"; theme_label="暖橙色"
      ;;
  esac

  favorites_html="$(secure_site_nav_cards "百|百度|中文搜索引擎|https://www.baidu.com/|c1
B|必应|微软搜索服务|https://www.bing.com/|c2
G|Google|全球信息检索|https://www.google.com/|c3
知|知乎|中文问答社区|https://www.zhihu.com/|c4
哔|哔哩哔哩|视频与兴趣社区|https://www.bilibili.com/|c2
GH|GitHub|代码与开源社区|https://github.com/|c7")"
  news_html="$(secure_site_nav_cards "新|新华网|权威新闻资讯|https://www.news.cn/|c6
人|人民网|综合新闻门户|https://www.people.com.cn/|c6
视|央视网|新闻与节目资讯|https://www.cctv.com/|c1
中|中国新闻网|国内国际新闻|https://www.chinanews.com.cn/|c5
早|联合早报|新加坡中文资讯|https://www.zaobao.com.sg/|c5
R|Reuters|国际新闻通讯社|https://www.reuters.com/|c7")"
  media_html="$(secure_site_nav_cards "哔|哔哩哔哩|综合视频社区|https://www.bilibili.com/|c2
YT|YouTube|全球视频平台|https://www.youtube.com/|c6
腾|腾讯视频|影视与综艺内容|https://v.qq.com/|c1
爱|爱奇艺|在线视频服务|https://www.iqiyi.com/|c3
云|网易云音乐|音乐与播客|https://music.163.com/|c6
影|豆瓣电影|电影资料与评价|https://movie.douban.com/|c3")"
  study_html="$(secure_site_nav_cards "GH|GitHub|代码托管与协作|https://github.com/|c7
MDN|MDN Web Docs|Web 开发文档|https://developer.mozilla.org/|c1
SO|Stack Overflow|开发者问答社区|https://stackoverflow.com/|c5
D|DeepL|多语言翻译工具|https://www.deepl.com/|c2
C|Canva|在线视觉设计|https://www.canva.com/|c4
N|Notion|笔记与团队协作|https://www.notion.so/|c7")"
  life_html="$(secure_site_nav_cards "淘|淘宝|综合购物平台|https://www.taobao.com/|c5
京|京东|零售与生活服务|https://www.jd.com/|c6
携|携程旅行|机票酒店与旅行|https://www.ctrip.com/|c1
铁|中国铁路 12306|铁路客票服务|https://www.12306.cn/|c2
高|高德地图|地图与路线规划|https://www.amap.com/|c3
天|中国天气|天气预报与预警|https://weather.cma.cn/|c2")"
  cloud_html="$(secure_site_nav_cards "Q|QQ 邮箱|腾讯电子邮箱|https://mail.qq.com/|c1
163|网易邮箱|电子邮件服务|https://mail.163.com/|c6
O|Outlook|微软邮件与日历|https://outlook.live.com/|c2
G|Gmail|Google 电子邮箱|https://mail.google.com/|c5
1D|OneDrive|微软云端存储|https://onedrive.live.com/|c1
GD|Google Drive|文件与协作空间|https://drive.google.com/|c3")"
  tools_html="$(secure_site_nav_cards "速|Speedtest|网络速度测试|https://www.speedtest.net/|c2
时|Time.is|精确时间与时区|https://time.is/|c7
工|在线工具|开发与文本工具箱|https://tool.lu/|c4
图|TinyPNG|图片压缩优化|https://tinypng.com/|c3
PDF|PDF24 Tools|PDF 转换与处理|https://tools.pdf24.org/zh/|c6
VT|VirusTotal|文件与网址安全检查|https://www.virustotal.com/|c8")"

  build_id="$(printf '%08x%08x' "$((RANDOM * RANDOM + RANDOM))" "$((RANDOM * RANDOM + RANDOM))")"
  year="$(date +%Y)"
  ensure_dir "$SECURE_SITE_ROOT/.well-known/acme-challenge" || return 1

  write_file "$SECURE_SITE_ROOT/index.html" "<!DOCTYPE html>
<html lang=\"zh-CN\">
<head>
  <meta charset=\"utf-8\">
  <meta name=\"viewport\" content=\"width=device-width,initial-scale=1\">
  <meta name=\"description\" content=\"实用、清爽的常用网址导航，分类整理搜索、资讯、影音、学习与生活服务。\">
  <meta name=\"theme-color\" content=\"${accent}\">
  <link rel=\"icon\" href=\"/favicon.svg\" type=\"image/svg+xml\">
  <title>网址导航 · ${domain}</title>
  <style>
    :root{color-scheme:light;--accent:${accent};--accent-dark:${accent_dark};--soft:${accent_soft};--ink:#172033;--muted:#687386;--line:#e5eaf1;--paper:#f5f7fa;--card:#fff;--shadow:0 12px 34px rgba(30,41,59,.07)}
    *{box-sizing:border-box}html{scroll-behavior:smooth}body{margin:0;background:linear-gradient(135deg,${gradient_a} 0,${gradient_b} 25rem,var(--paper) 48rem);color:var(--ink);font-family:system-ui,-apple-system,BlinkMacSystemFont,Segoe UI,sans-serif;font-size:15px}
    a{color:inherit}.wrap{width:min(1180px,calc(100% - 36px));margin:auto}.sr-only{position:absolute;width:1px;height:1px;padding:0;margin:-1px;overflow:hidden;clip:rect(0,0,0,0);white-space:nowrap;border:0}
    .topbar{height:42px;border-bottom:1px solid rgba(148,163,184,.22);color:var(--muted);font-size:12px}.topbar .wrap{height:100%;display:flex;align-items:center;justify-content:space-between}.topbar-links{display:flex;gap:18px}.topbar a{text-decoration:none}.topbar a:hover{color:var(--accent)}
    .header{padding:24px 0 20px}.header-row{display:flex;align-items:center;justify-content:space-between;gap:24px}.brand{display:flex;align-items:center;gap:12px;text-decoration:none;font-size:21px;font-weight:800;letter-spacing:-.03em}.brand-mark{display:grid;place-items:center;width:38px;height:38px;border-radius:12px;color:#fff;background:linear-gradient(145deg,var(--accent),var(--accent-dark));box-shadow:0 8px 22px color-mix(in srgb,var(--accent) 25%,transparent)}.brand small{display:block;margin-top:2px;color:var(--muted);font-size:11px;font-weight:500;letter-spacing:.03em}
    .header-note{display:flex;align-items:center;gap:8px;color:var(--muted);font-size:12px}.status-dot{width:7px;height:7px;border-radius:50%;background:#22c55e;box-shadow:0 0 0 4px #dcfce7}
    .hero{padding:34px 0 30px;text-align:center}.hero h1{margin:0;font-size:clamp(30px,5vw,48px);letter-spacing:-.045em}.hero p{margin:12px auto 24px;color:var(--muted);font-size:15px}
    .search{display:flex;width:min(720px,100%);margin:auto;padding:7px;background:#fff;border:1px solid #dce3ec;border-radius:16px;box-shadow:0 18px 50px rgba(30,41,59,.11)}.engine{display:flex;align-items:center;padding:0 13px;border-right:1px solid var(--line);color:var(--accent);font-size:13px;font-weight:750}.search input{min-width:0;flex:1;border:0;outline:0;padding:13px 15px;background:transparent;color:var(--ink);font:inherit}.search input::placeholder{color:#9aa4b2}.search button{border:0;border-radius:11px;padding:0 24px;background:var(--accent);color:#fff;font:inherit;font-weight:750;cursor:pointer}.search button:hover{background:var(--accent-dark)}
    .search-shortcuts{display:flex;justify-content:center;flex-wrap:wrap;gap:16px;margin-top:15px;color:var(--muted);font-size:12px}.search-shortcuts a{text-decoration:none}.search-shortcuts a:hover{color:var(--accent)}
    .quick-strip{display:flex;align-items:center;gap:9px;margin:0 0 24px;padding:13px 16px;border:1px solid var(--line);border-radius:14px;background:rgba(255,255,255,.78);box-shadow:0 6px 24px rgba(30,41,59,.04);overflow-x:auto;white-space:nowrap}.quick-strip strong{margin-right:4px;color:var(--accent);font-size:12px}.quick-strip a{padding:7px 11px;border-radius:8px;text-decoration:none;color:#4b5563;font-size:13px}.quick-strip a:hover{background:var(--soft);color:var(--accent)}
    .layout{display:grid;grid-template-columns:176px minmax(0,1fr);gap:22px;align-items:start}.sidebar{position:sticky;top:16px;padding:14px;border:1px solid var(--line);border-radius:16px;background:rgba(255,255,255,.9);box-shadow:var(--shadow)}.sidebar-title{padding:7px 10px 12px;color:var(--muted);font-size:11px;font-weight:750;text-transform:uppercase;letter-spacing:.12em}.sidebar a{display:flex;align-items:center;gap:10px;padding:10px;border-radius:10px;text-decoration:none;color:#4b5563;font-size:13px}.sidebar a:hover{background:var(--soft);color:var(--accent)}.side-icon{display:grid;place-items:center;width:24px;height:24px;border-radius:7px;background:#f1f5f9;font-size:12px}
    .directory{min-width:0}.category{scroll-margin-top:18px;margin:0 0 22px;padding:23px;border:1px solid var(--line);border-radius:18px;background:rgba(255,255,255,.94);box-shadow:var(--shadow)}.category-head{display:flex;align-items:end;justify-content:space-between;gap:20px;margin-bottom:18px}.category h2{margin:0;font-size:18px;letter-spacing:-.02em}.category-head span{color:var(--muted);font-size:11px}.site-grid{display:grid;grid-template-columns:repeat(3,minmax(0,1fr));gap:11px}
    .site{display:flex;align-items:center;min-width:0;gap:11px;padding:12px;border:1px solid #edf0f4;border-radius:13px;background:#fff;text-decoration:none;transition:transform .16s ease,border-color .16s ease,box-shadow .16s ease}.site:hover{transform:translateY(-2px);border-color:color-mix(in srgb,var(--accent) 35%,#e5e7eb);box-shadow:0 9px 22px rgba(30,41,59,.08)}.site-badge{flex:0 0 auto;display:grid;place-items:center;width:38px;height:38px;border-radius:11px;color:#fff;font-weight:800;font-size:13px}.site-copy{min-width:0}.site strong,.site small{display:block;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}.site strong{font-size:13px}.site small{margin-top:4px;color:var(--muted);font-size:10px}
    .c1{background:#2563eb}.c2{background:#0ea5e9}.c3{background:#16a34a}.c4{background:#7c3aed}.c5{background:#ea580c}.c6{background:#dc2626}.c7{background:#475569}.c8{background:#0891b2}
    .source-note{display:flex;justify-content:space-between;gap:20px;margin:4px 0 34px;padding:18px 20px;border:1px dashed #cbd5e1;border-radius:14px;color:var(--muted);font-size:12px;line-height:1.7}.source-note a{color:var(--accent);text-decoration:none}
    footer{display:flex;justify-content:space-between;gap:20px;padding:24px 0 34px;border-top:1px solid var(--line);color:var(--muted);font-size:12px}footer a{text-decoration:none}footer a:hover{color:var(--accent)}:focus-visible{outline:3px solid color-mix(in srgb,var(--accent) 35%,transparent);outline-offset:3px}
    @media(max-width:820px){.wrap{width:min(100% - 24px,1180px)}.topbar{display:none}.header{padding:16px 0}.header-note{display:none}.hero{padding:25px 0}.engine{display:none}.search{padding:5px;border-radius:14px}.search input{padding:12px}.search button{padding:0 18px}.quick-strip{margin-bottom:14px}.layout{display:block}.sidebar{position:sticky;z-index:2;top:0;display:flex;gap:4px;margin-bottom:14px;padding:8px;overflow-x:auto;border-radius:13px}.sidebar-title{display:none}.sidebar a{flex:0 0 auto;padding:8px 10px}.side-icon{display:none}.category{padding:17px;margin-bottom:14px}.site-grid{grid-template-columns:repeat(2,minmax(0,1fr))}.source-note,footer{flex-direction:column}}
    @media(max-width:460px){.site-grid{grid-template-columns:1fr}.category-head span{display:none}.brand{font-size:18px}}
  </style>
</head>
<body id=\"top\">
  <div class=\"topbar\"><div class=\"wrap\"><span>清爽、实用的常用网址入口</span><div class=\"topbar-links\"><a href=\"#favorites\">常用网站</a><a href=\"#tools\">在线工具</a><a href=\"/OPEN_SOURCE_NOTICE.txt\">开源说明</a></div></div></div>
  <header class=\"header\"><div class=\"wrap header-row\"><a class=\"brand\" href=\"/\"><span class=\"brand-mark\">N</span><span>网址导航<small>${domain} · ${theme_label}</small></span></a><div class=\"header-note\"><span class=\"status-dot\" aria-hidden=\"true\"></span>页面保持轻量，无广告与跟踪脚本</div></div></header>
  <main class=\"wrap\">
    <section class=\"hero\" aria-labelledby=\"page-title\"><h1 id=\"page-title\">常用网址，一页直达</h1><p>搜索、资讯、影音、学习与生活服务，分类整理，打开即用。</p>
      <form class=\"search\" action=\"https://www.bing.com/search\" method=\"get\"><span class=\"engine\">Bing</span><label class=\"sr-only\" for=\"search-query\">输入搜索内容</label><input id=\"search-query\" type=\"search\" name=\"q\" maxlength=\"120\" autocomplete=\"off\" enterkeyhint=\"search\" placeholder=\"输入关键词开始搜索\" required><button type=\"submit\">搜索</button></form>
      <nav class=\"search-shortcuts\" aria-label=\"其他搜索入口\"><span>其他搜索：</span><a href=\"https://www.baidu.com/\" target=\"_blank\" rel=\"noopener noreferrer\">百度</a><a href=\"https://www.google.com/\" target=\"_blank\" rel=\"noopener noreferrer\">Google</a><a href=\"https://www.wikipedia.org/\" target=\"_blank\" rel=\"noopener noreferrer\">Wikipedia</a></nav>
    </section>
    <nav class=\"quick-strip\" aria-label=\"快捷入口\"><strong>快捷入口</strong><a href=\"https://www.baidu.com/\" target=\"_blank\" rel=\"noopener noreferrer\">百度</a><a href=\"https://www.bilibili.com/\" target=\"_blank\" rel=\"noopener noreferrer\">哔哩哔哩</a><a href=\"https://www.zhihu.com/\" target=\"_blank\" rel=\"noopener noreferrer\">知乎</a><a href=\"https://github.com/\" target=\"_blank\" rel=\"noopener noreferrer\">GitHub</a><a href=\"https://mail.qq.com/\" target=\"_blank\" rel=\"noopener noreferrer\">QQ 邮箱</a><a href=\"https://www.taobao.com/\" target=\"_blank\" rel=\"noopener noreferrer\">淘宝</a><a href=\"https://www.jd.com/\" target=\"_blank\" rel=\"noopener noreferrer\">京东</a><a href=\"https://map.baidu.com/\" target=\"_blank\" rel=\"noopener noreferrer\">地图</a></nav>
    <div class=\"layout\">
      <aside class=\"sidebar\" aria-label=\"网址分类\"><div class=\"sidebar-title\">网址分类</div><a href=\"#favorites\"><span class=\"side-icon\">★</span>常用推荐</a><a href=\"#news\"><span class=\"side-icon\">闻</span>新闻资讯</a><a href=\"#media\"><span class=\"side-icon\">播</span>影音娱乐</a><a href=\"#study\"><span class=\"side-icon\">学</span>工作学习</a><a href=\"#life\"><span class=\"side-icon\">行</span>生活服务</a><a href=\"#cloud\"><span class=\"side-icon\">云</span>邮箱云盘</a><a href=\"#tools\"><span class=\"side-icon\">工</span>实用工具</a></aside>
      <div class=\"directory\">
        <section class=\"category\" id=\"favorites\" aria-labelledby=\"favorites-title\"><div class=\"category-head\"><h2 id=\"favorites-title\">常用推荐</h2><span>搜索、社区与知识入口</span></div><div class=\"site-grid\">
${favorites_html}
        </div></section>
        <section class=\"category\" id=\"news\" aria-labelledby=\"news-title\"><div class=\"category-head\"><h2 id=\"news-title\">新闻资讯</h2><span>国内外综合资讯网站</span></div><div class=\"site-grid\">
${news_html}
        </div></section>
        <section class=\"category\" id=\"media\" aria-labelledby=\"media-title\"><div class=\"category-head\"><h2 id=\"media-title\">影音娱乐</h2><span>视频、音乐与电影资料</span></div><div class=\"site-grid\">
${media_html}
        </div></section>
        <section class=\"category\" id=\"study\" aria-labelledby=\"study-title\"><div class=\"category-head\"><h2 id=\"study-title\">工作学习</h2><span>开发、设计与知识工具</span></div><div class=\"site-grid\">
${study_html}
        </div></section>
        <section class=\"category\" id=\"life\" aria-labelledby=\"life-title\"><div class=\"category-head\"><h2 id=\"life-title\">生活服务</h2><span>购物、出行与日常查询</span></div><div class=\"site-grid\">
${life_html}
        </div></section>
        <section class=\"category\" id=\"cloud\" aria-labelledby=\"cloud-title\"><div class=\"category-head\"><h2 id=\"cloud-title\">邮箱云盘</h2><span>邮件、文件与在线协作</span></div><div class=\"site-grid\">
${cloud_html}
        </div></section>
        <section class=\"category\" id=\"tools\" aria-labelledby=\"tools-title\"><div class=\"category-head\"><h2 id=\"tools-title\">实用工具</h2><span>测速、图片、文档与安全检查</span></div><div class=\"site-grid\">
${tools_html}
        </div></section>
        <div class=\"source-note\"><span><strong>使用提示：</strong>本站仅整理公开网址入口，不保存账号信息；外部网站的内容与服务由对应网站负责。</span><span>页面无广告、无统计、无第三方脚本。</span></div>
      </div>
    </div>
  </main>
  <footer class=\"wrap\"><span>© ${year} ${domain} · 实用网址导航</span><span><a href=\"#top\">返回顶部</a> · <a href=\"/OPEN_SOURCE_NOTICE.txt\">开源说明</a></span></footer>
  <!-- build:${build_id} -->
</body>
</html>" || return 1

  write_file "$SECURE_SITE_ROOT/404.html" "<!DOCTYPE html><html lang=\"zh-CN\"><head><meta charset=\"utf-8\"><meta name=\"viewport\" content=\"width=device-width,initial-scale=1\"><title>页面未找到 · ${domain}</title><style>body{margin:0;display:grid;place-items:center;min-height:100vh;font:16px system-ui;background:#f5f7fa;color:#172033}main{text-align:center;padding:30px}h1{font-size:64px;margin:0}p{color:#687386}a{color:${accent}}</style></head><body><main><h1>404</h1><p>没有找到你访问的页面。</p><a href=\"/\">返回网址导航</a></main></body></html>" || return 1
  write_file "$SECURE_SITE_ROOT/favicon.svg" "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 64 64\"><rect width=\"64\" height=\"64\" rx=\"17\" fill=\"${accent}\"/><path d=\"M18 18h12v12H18zm16 0h12v12H34zM18 34h12v12H18zm16 0h12v12H34z\" fill=\"white\"/></svg>" || return 1
  write_file "$SECURE_SITE_ROOT/robots.txt" "User-agent: *
Allow: /" || return 1
  write_file "$SECURE_SITE_ROOT/healthz" "ok" || return 1
  write_file "$SECURE_SITE_ROOT/OPEN_SOURCE_NOTICE.txt" "Open-source attribution

This navigation page independently reimplements the category and card layout concept of WebStackPage:
https://github.com/WebStackPage/WebStackPage.github.io

MIT License
Copyright (c) 2017 DesignStack

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the \"Software\"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED \"AS IS\", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE." || return 1
  chown -R root:root "$SECURE_SITE_ROOT" >/dev/null 2>&1 || true
  find "$SECURE_SITE_ROOT" -type d -exec chmod 755 {} + 2>/dev/null || true
  find "$SECURE_SITE_ROOT" -type f -exec chmod 644 {} + 2>/dev/null || true
  echo "$template"
}

secure_site_write_limit_conf() {
  local request_rate="$1"
  write_file "$SECURE_SITE_NGINX_LIMIT_CONF" "# managed by dmitbox.sh - secure static website
# Request and concurrent-connection limits shared by this website.
limit_req_zone \$binary_remote_addr zone=dmitbox_secure_site_req:10m rate=${request_rate}r/s;
limit_conn_zone \$binary_remote_addr zone=dmitbox_secure_site_conn:10m;"
}

secure_site_nginx_ipv6_listen() {
  local port="$1" options="${2:-}"
  if [[ -s /proc/net/if_inet6 ]] && [[ "$(sysctl -n net.ipv6.conf.all.disable_ipv6 2>/dev/null || echo 1)" != "1" ]]; then
    echo "    listen [::]:${port}${options};"
  fi
  return 0
}

secure_site_write_nginx_http_conf() {
  local domain="$1" request_rate="$2" connection_limit="$3"
  local ip_server_names="${4:-localhost 127.0.0.1}" listen_v6=""
  listen_v6="$(secure_site_nginx_ipv6_listen 80)"
  rm -f "$SECURE_SITE_NGINX_ACTIVE_CONF" "$SECURE_SITE_NGINX_PAUSED_CONF" || return 1
  write_file "$SECURE_SITE_NGINX_CONF" "# managed by dmitbox.sh - secure static website
# DMITBOX_HTTP_BOOTSTRAP: temporary HTTP-only configuration for certificate issuance.
server {
    listen 80;
${listen_v6}
    # DMITBOX_IP_LITERAL_REJECT: exact known addresses plus any IPv4/IPv6 Host literal.
    server_name ${ip_server_names} \"\"
        \"~^(?:[0-9]{1,3}\\.){3}[0-9]{1,3}\$\"
        \"~^\\[[0-9A-Fa-f:]+\\]\$\"
        \"~^[0-9A-Fa-f:]*:[0-9A-Fa-f:]+\$\";
    access_log off;
    error_log /var/log/nginx/dmitbox-secure-site-error.log crit;
    server_tokens off;
    return 444;
}

server {
    listen 80;
${listen_v6}
    server_name ${domain};
    root ${SECURE_SITE_ROOT};
    access_log off;
    error_log /var/log/nginx/dmitbox-secure-site-error.log crit;
    server_tokens off;
    if (\$host != \"${domain}\") { return 444; }
    client_header_timeout 8s;
    client_body_timeout 8s;
    keepalive_timeout 10s;
    client_max_body_size 1m;
    limit_req zone=dmitbox_secure_site_req burst=$((request_rate * 2)) nodelay;
    limit_conn dmitbox_secure_site_conn ${connection_limit};

    location ^~ /.well-known/acme-challenge/ {
        default_type text/plain;
        limit_except GET HEAD { deny all; }
        try_files \$uri =404;
    }
    location / {
        return 308 https://${domain}\$request_uri;
    }
}"
}

secure_site_write_nginx_full_conf() {
  local domain="$1" request_rate="$2" connection_limit="$3"
  local ip_server_names="${4:-localhost 127.0.0.1}"
  local sni_reject_mode="${5:-strict}" listen80_v6="" listen443_default_v6=""
  local listen443_site_v6="" tls_reject_server="" was_paused=0
  [[ "$sni_reject_mode" == "strict" || "$sni_reject_mode" == "certificate" ]] || return 1
  [[ -e "$SECURE_SITE_NGINX_ACTIVE_CONF" && -e "$SECURE_SITE_NGINX_PAUSED_CONF" ]] && return 1
  [[ -e "$SECURE_SITE_NGINX_PAUSED_CONF" ]] && was_paused=1
  listen80_v6="$(secure_site_nginx_ipv6_listen 80)"
  listen443_default_v6="$(secure_site_nginx_ipv6_listen 443 ' ssl http2 default_server')"
  listen443_site_v6="$(secure_site_nginx_ipv6_listen 443 ' ssl http2')"

  if [[ "$sni_reject_mode" == "strict" ]]; then
    tls_reject_server="server {
    listen 443 ssl http2 default_server;
${listen443_default_v6}
    server_name _;
    # DMITBOX_STRICT_SNI_REJECT: reject unknown SNI during the TLS handshake.
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_session_tickets off;
    ssl_reject_handshake on;
}"
  else
    tls_reject_server="server {
    listen 443 ssl http2 default_server;
${listen443_default_v6}
    server_name _;
    # DMITBOX_CERT_SNI_REJECT: compatibility fallback for older Nginx.
    access_log off;
    error_log /var/log/nginx/dmitbox-secure-site-error.log crit;
    server_tokens off;
    ssl_certificate /etc/letsencrypt/live/${domain}/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/${domain}/privkey.pem;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_session_tickets off;
    return 444;
}"
  fi

  write_file "$SECURE_SITE_NGINX_CONF" "# managed by dmitbox.sh - secure static website
# DMITBOX_SITE_BASE: always loaded; rejects IP literals and unknown TLS SNI.
server {
    listen 80;
${listen80_v6}
    # DMITBOX_IP_LITERAL_REJECT: exact known addresses plus any IPv4/IPv6 Host literal.
    server_name ${ip_server_names} \"\"
        \"~^(?:[0-9]{1,3}\\.){3}[0-9]{1,3}\$\"
        \"~^\\[[0-9A-Fa-f:]+\\]\$\"
        \"~^[0-9A-Fa-f:]*:[0-9A-Fa-f:]+\$\";
    access_log off;
    error_log /var/log/nginx/dmitbox-secure-site-error.log crit;
    server_tokens off;
    return 444;
}

${tls_reject_server}" || return 1

  write_file "$SECURE_SITE_NGINX_ACTIVE_CONF" "# managed by dmitbox.sh - secure static website
# DMITBOX_SITE_STATE_ACTIVE: this file is moved out of the include path when the site is paused.
server {
    listen 80;
${listen80_v6}
    server_name ${domain};
    root ${SECURE_SITE_ROOT};
    access_log off;
    error_log /var/log/nginx/dmitbox-secure-site-error.log crit;
    server_tokens off;
    if (\$host != \"${domain}\") { return 444; }
    client_header_timeout 8s;
    client_body_timeout 8s;
    keepalive_timeout 10s;
    client_max_body_size 1m;
    limit_req zone=dmitbox_secure_site_req burst=$((request_rate * 2)) nodelay;
    limit_conn dmitbox_secure_site_conn ${connection_limit};

    location ^~ /.well-known/acme-challenge/ {
        default_type text/plain;
        limit_except GET HEAD { deny all; }
        try_files \$uri =404;
    }
    location / {
        return 308 https://${domain}\$request_uri;
    }
}

server {
    # DMITBOX_PUBLIC_TLS_SITE: the configured domain is served on public TCP/443.
    listen 443 ssl http2;
${listen443_site_v6}
    # DMITBOX_LOCAL_TLS_SITE: this same website is reachable locally through 127.0.0.1:443.
    server_name ${domain};
    root ${SECURE_SITE_ROOT};
    index index.html;
    access_log off;
    error_log /var/log/nginx/dmitbox-secure-site-error.log crit;
    server_tokens off;
    if (\$ssl_server_name != \"${domain}\") { return 444; }
    if (\$host != \"${domain}\") { return 444; }

    ssl_certificate /etc/letsencrypt/live/${domain}/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/${domain}/privkey.pem;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_session_cache shared:DMITBOX_SECURE_SITE_SSL:2m;
    ssl_session_timeout 10m;
    ssl_session_tickets off;

    client_max_body_size 1m;
    client_header_timeout 8s;
    client_body_timeout 8s;
    keepalive_timeout 15s;
    send_timeout 10s;
    reset_timedout_connection on;
    limit_req_status 429;
    limit_conn_status 429;
    limit_req zone=dmitbox_secure_site_req burst=$((request_rate * 2)) nodelay;
    limit_conn dmitbox_secure_site_conn ${connection_limit};

    add_header Strict-Transport-Security \"max-age=604800\" always;
    add_header X-Content-Type-Options \"nosniff\" always;
    add_header X-Frame-Options \"DENY\" always;
    add_header Referrer-Policy \"no-referrer\" always;
    add_header Permissions-Policy \"camera=(), microphone=(), geolocation=(), payment=()\" always;
    add_header Content-Security-Policy \"default-src 'self'; img-src 'self' data:; style-src 'self' 'unsafe-inline'; script-src 'none'; object-src 'none'; base-uri 'none'; frame-ancestors 'none'; form-action https://www.bing.com\" always;
    # Prevent a later-added shared proxy from serving a cached copy after automatic pause.
    add_header Cache-Control \"private, no-store, max-age=0\" always;

    error_page 404 /404.html;
    location = /404.html { internal; }
    location = /healthz { default_type text/plain; limit_except GET HEAD { deny all; } try_files /healthz =404; }
    location ~ /\\. { deny all; }
    location ~* \\.(?:php|asp|aspx|jsp|cgi|pl|py|sh)\$ { return 404; }
    location / {
        limit_except GET HEAD { deny all; }
        try_files \$uri \$uri/ =404;
    }
}" || return 1

  if (( was_paused == 1 )); then
    mv -f "$SECURE_SITE_NGINX_ACTIVE_CONF" "$SECURE_SITE_NGINX_PAUSED_CONF" || return 1
  else
    rm -f "$SECURE_SITE_NGINX_PAUSED_CONF" || return 1
  fi
}

secure_site_nginx_reload() {
  have_cmd nginx || return 1
  nginx -t >/dev/null 2>&1 || return 1
  if secure_site_systemd_running; then
    systemctl unmask --runtime nginx >/dev/null 2>&1 || return 1
  fi
  if is_systemd && systemctl enable --now nginx >/dev/null 2>&1; then
    systemctl reload nginx >/dev/null 2>&1
    return $?
  fi
  if have_cmd rc-service; then
    rc-update add nginx default >/dev/null 2>&1 || true
    if rc-service nginx status >/dev/null 2>&1; then
      rc-service nginx reload >/dev/null 2>&1
    else
      rc-service nginx start >/dev/null 2>&1
    fi
    return $?
  fi
  if pgrep -x nginx >/dev/null 2>&1; then
    nginx -s reload >/dev/null 2>&1
  else
    nginx >/dev/null 2>&1
  fi
}

secure_site_nginx_config_loaded() {
  local output=""
  have_cmd nginx || return 1
  output="$(nginx -T 2>&1)" || return 1
  grep -Fq "# configuration file ${SECURE_SITE_NGINX_CONF}:" <<< "$output"
}

secure_site_certificate_valid() {
  local domain="$1" cert="/etc/letsencrypt/live/${domain}/fullchain.pem"
  local key="/etc/letsencrypt/live/${domain}/privkey.pem"
  [[ -s "$cert" && -s "$key" ]] || return 1
  if have_cmd openssl; then
    openssl x509 -in "$cert" -noout -checkend 604800 >/dev/null 2>&1 || return 1
    if openssl x509 -help 2>&1 | grep -q -- '-checkhost'; then
      openssl x509 -in "$cert" -noout -checkhost "$domain" >/dev/null 2>&1 || return 1
    fi
  fi
}

secure_site_issue_certificate() {
  local domain="$1" email="$2"
  local -a args=(certonly --webroot -w "$SECURE_SITE_ROOT" -d "$domain" \
    --cert-name "$domain" --non-interactive --agree-tos --preferred-challenges http \
    --keep-until-expiring)
  if [[ -n "$email" ]]; then
    args+=(--email "$email")
  else
    args+=(--register-unsafely-without-email)
  fi
  run_with_spinner "申请或检查 Let's Encrypt 证书" certbot "${args[@]}"
}

secure_site_setup_cert_renewal() {
  local certbot_path="" minute=""
  ensure_dir "$(dirname "$SECURE_SITE_CERT_HOOK")" || return 1
  write_file "$SECURE_SITE_CERT_HOOK" '#!/bin/sh
set -eu
if command -v nginx >/dev/null 2>&1 && nginx -t >/dev/null 2>&1; then
  if command -v systemctl >/dev/null 2>&1 && systemctl is-active --quiet nginx 2>/dev/null; then
    systemctl reload nginx >/dev/null 2>&1 || nginx -s reload >/dev/null 2>&1 || true
  else
    nginx -s reload >/dev/null 2>&1 || true
  fi
fi' || return 1
  chmod 755 "$SECURE_SITE_CERT_HOOK" || return 1

  if is_systemd && systemctl list-unit-files certbot.timer >/dev/null 2>&1; then
    if systemctl enable --now certbot.timer >/dev/null 2>&1; then
      rm -f "$SECURE_SITE_CERT_CRON" "$SECURE_SITE_CERT_PERIODIC" >/dev/null 2>&1 || true
      return 0
    fi
    warn "certbot.timer 启用失败，改用 cron 续期"
  fi
  certbot_path="$(command -v certbot 2>/dev/null || true)"
  [[ -n "$certbot_path" ]] || return 1
  if [[ -d /etc/periodic/daily ]]; then
    write_file "$SECURE_SITE_CERT_PERIODIC" "#!/bin/sh
${certbot_path} renew -q" || return 1
    chmod 755 "$SECURE_SITE_CERT_PERIODIC" || return 1
    rm -f "$SECURE_SITE_CERT_CRON" >/dev/null 2>&1 || true
    return 0
  fi
  minute="$(random_uint_between 3 47)"
  write_file "$SECURE_SITE_CERT_CRON" "# managed by dmitbox.sh - secure website certificate renewal
${minute} 3 * * * root ${certbot_path} renew -q" || return 1
  chmod 644 "$SECURE_SITE_CERT_CRON" || return 1
  rm -f "$SECURE_SITE_CERT_PERIODIC" >/dev/null 2>&1 || true
}

secure_site_alpine_cron_remove_tag() {
  local crontab="$SECURE_SITE_DNS_WATCH_ALPINE_CRONTAB" tmp=""
  [[ -f "$crontab" ]] || return 0
  tmp="${crontab}.tmp.$$"
  awk 'index($0, "# dmitbox-site-dns-watch") == 0' "$crontab" > "$tmp" || {
    rm -f "$tmp" >/dev/null 2>&1 || true
    return 1
  }
  chmod --reference="$crontab" "$tmp" 2>/dev/null || chmod 600 "$tmp" 2>/dev/null || true
  mv -f "$tmp" "$crontab"
}

secure_site_systemd_running() {
  is_systemd && [[ -d "$SECURE_SITE_SYSTEMD_RUNTIME_DIR" ]]
}

secure_site_cron_running() {
  pgrep -x cron >/dev/null 2>&1 || pgrep -x crond >/dev/null 2>&1
}

secure_site_start_cron_best_effort() {
  secure_site_cron_running && return 0
  if secure_site_systemd_running; then
    systemctl enable --now cron.service >/dev/null 2>&1 || \
      systemctl enable --now crond.service >/dev/null 2>&1 || true
  fi
  if have_cmd rc-update && have_cmd rc-service; then
    rc-update add crond default >/dev/null 2>&1 || true
    rc-service crond restart >/dev/null 2>&1 || true
  elif have_cmd service; then
    service cron start >/dev/null 2>&1 || service crond start >/dev/null 2>&1 || true
  fi
  secure_site_cron_running
}

secure_site_remove_dns_watch_schedule() {
  if secure_site_systemd_running; then
    systemctl disable --now dmitbox-site-dns-watch.timer >/dev/null 2>&1 || true
  fi
  rm -f "$SECURE_SITE_DNS_WATCH_CRON" "$SECURE_SITE_DNS_WATCH_PERIODIC" \
    "$SECURE_SITE_DNS_WATCH_SERVICE" "$SECURE_SITE_DNS_WATCH_TIMER" >/dev/null 2>&1 || true
  secure_site_alpine_cron_remove_tag || true
  if secure_site_systemd_running; then
    systemctl daemon-reload >/dev/null 2>&1 || true
  fi
}

secure_site_setup_dns_watch_schedule() {
  secure_site_remove_dns_watch_schedule
  if secure_site_systemd_running; then
    write_file "$SECURE_SITE_DNS_WATCH_SERVICE" "# managed by dmitbox.sh - secure static website
[Unit]
Description=DMITBox DNS and CDN guard check
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=${SECURE_SITE_DNS_WATCH}
Nice=10" || return 1
    write_file "$SECURE_SITE_DNS_WATCH_TIMER" "# managed by dmitbox.sh - secure static website
[Unit]
Description=Run DMITBox DNS and CDN guard every minute

[Timer]
OnBootSec=20s
OnUnitActiveSec=60s
AccuracySec=5s
Persistent=true
Unit=dmitbox-site-dns-watch.service

[Install]
WantedBy=timers.target" || return 1
    if systemctl daemon-reload >/dev/null 2>&1 && \
       systemctl enable --now dmitbox-site-dns-watch.timer >/dev/null 2>&1; then
      return 0
    fi
    warn "每分钟 systemd 监测启动失败，改用 cron"
    systemctl disable --now dmitbox-site-dns-watch.timer >/dev/null 2>&1 || true
    rm -f "$SECURE_SITE_DNS_WATCH_SERVICE" "$SECURE_SITE_DNS_WATCH_TIMER" >/dev/null 2>&1 || true
    systemctl daemon-reload >/dev/null 2>&1 || true
  fi

  if [[ -f /etc/alpine-release && -d "$(dirname "$SECURE_SITE_DNS_WATCH_ALPINE_CRONTAB")" ]]; then
    ensure_dir "$(dirname "$SECURE_SITE_DNS_WATCH_ALPINE_CRONTAB")" || return 1
    [[ -e "$SECURE_SITE_DNS_WATCH_ALPINE_CRONTAB" ]] || \
      write_file "$SECURE_SITE_DNS_WATCH_ALPINE_CRONTAB" ""
    printf '%s\n' "* * * * * ${SECURE_SITE_DNS_WATCH} >/dev/null 2>&1 # dmitbox-site-dns-watch" \
      >> "$SECURE_SITE_DNS_WATCH_ALPINE_CRONTAB" || return 1
    chmod 600 "$SECURE_SITE_DNS_WATCH_ALPINE_CRONTAB" 2>/dev/null || true
    secure_site_start_cron_best_effort || {
      warn "crond 未运行，无法启用每分钟 CDN 监测"
      return 1
    }
    return 0
  fi

  write_file "$SECURE_SITE_DNS_WATCH_CRON" "# managed by dmitbox.sh - secure static website
@reboot root ${SECURE_SITE_DNS_WATCH} >/dev/null 2>&1
* * * * * root ${SECURE_SITE_DNS_WATCH} >/dev/null 2>&1" || return 1
  chmod 644 "$SECURE_SITE_DNS_WATCH_CRON" || return 1
  secure_site_start_cron_best_effort || {
    warn "cron 未运行，无法启用每分钟 CDN 监测"
    return 1
  }
}

secure_site_dns_watch_schedule_active_legacy_autostop_unused() {
  if secure_site_systemd_running && \
     systemctl is-enabled --quiet dmitbox-site-dns-watch.timer >/dev/null 2>&1 && \
     systemctl is-active --quiet dmitbox-site-dns-watch.timer >/dev/null 2>&1; then
    return 0
  fi
  if [[ -f /etc/alpine-release && -r "$SECURE_SITE_DNS_WATCH_ALPINE_CRONTAB" ]] && \
     grep -Fq '# dmitbox-site-dns-watch' "$SECURE_SITE_DNS_WATCH_ALPINE_CRONTAB" && \
     secure_site_cron_running; then
    return 0
  fi
  [[ -r "$SECURE_SITE_DNS_WATCH_CRON" ]] && \
    grep -Fq "* * * * * root ${SECURE_SITE_DNS_WATCH}" "$SECURE_SITE_DNS_WATCH_CRON" && \
    secure_site_cron_running
}

secure_site_setup_dns_watch_legacy_autostop_unused() {
  local watcher_content=""
  secure_site_aux_files_are_managed_or_absent || {
    warn "发现同名但非本脚本管理的 DNS/CDN 监测文件，拒绝覆盖"
    return 1
  }
  ensure_dir "$(dirname "$SECURE_SITE_DNS_WATCH")" || return 1
  ensure_dir "$(dirname "$SECURE_SITE_DNS_STATUS")" || return 1

  IFS= read -r -d '' watcher_content <<'WATCHER' || true
#!/bin/sh
# managed by dmitbox.sh - secure static website
set -eu

conf="__DMITBOX_SITE_CONF__"
status="__DMITBOX_DNS_STATUS__"
nginx_base="__DMITBOX_NGINX_BASE__"
nginx_limit="__DMITBOX_NGINX_LIMIT__"
nginx_active="__DMITBOX_NGINX_ACTIVE__"
nginx_paused="__DMITBOX_NGINX_PAUSED__"
init_dir="__DMITBOX_INIT_DIR__"
systemd_runtime_dir="__DMITBOX_SYSTEMD_RUNTIME_DIR__"
mode=${1:-check}
[ -r "$conf" ] || exit 0
if command -v flock >/dev/null 2>&1; then
  exec 9>"${status}.lock"
  case "$mode" in
    check|--check) flock -n 9 || exit 0 ;;
    *) flock 9 || exit 5 ;;
  esac
fi

conf_value() {
  awk -F= -v key="$1" '$1 == key {sub(/^[^=]*=/, ""); print; exit}' "$conf"
}

status_value() {
  [ -r "$status" ] || return 0
  awk -F= -v key="$1" '$1 == key {sub(/^[^=]*=/, ""); print; exit}' "$status"
}

is_managed_file() {
  [ -f "$1" ] && grep -Fqx '# managed by dmitbox.sh - secure static website' "$1"
}

site_state() {
  is_managed_file "$nginx_base" || return 1
  if is_managed_file "$nginx_active" && [ ! -e "$nginx_paused" ]; then
    echo ACTIVE
    return 0
  fi
  if is_managed_file "$nginx_paused" && [ ! -e "$nginx_active" ]; then
    echo PAUSED
    return 0
  fi
  return 1
}

uses_systemd() {
  command -v systemctl >/dev/null 2>&1 && [ -d "$systemd_runtime_dir" ]
}

nginx_running() {
  if command -v pgrep >/dev/null 2>&1; then
    pgrep -x nginx >/dev/null 2>&1
    return $?
  fi
  if command -v pidof >/dev/null 2>&1; then
    pidof nginx >/dev/null 2>&1
    return $?
  fi
  nginx_pid=$(cat /run/nginx.pid 2>/dev/null || true)
  [ -n "$nginx_pid" ] && kill -0 "$nginx_pid" >/dev/null 2>&1
}

nginx_runtime_state() {
  if nginx_running; then echo RUNNING; else echo STOPPED; fi
}

nginx_wait_state() {
  wanted=$1
  attempts=0
  while [ "$attempts" -lt 10 ]; do
    if [ "$wanted" = "RUNNING" ] && nginx_running; then return 0; fi
    if [ "$wanted" = "STOPPED" ] && ! nginx_running; then return 0; fi
    attempts=$((attempts + 1))
    sleep 1
  done
  if [ "$wanted" = "RUNNING" ]; then nginx_running; else ! nginx_running; fi
}

other_nginx_server_files() {
  nginx_output=$(nginx -T 2>&1) || return 1
  printf '%s\n' "$nginx_output" | awk \
    -v base="$nginx_base" -v active="$nginx_active" -v limit="$nginx_limit" '
    /^# configuration file / {
      file=$0
      sub(/^# configuration file /, "", file)
      sub(/:$/, "", file)
      next
    }
    {
      line=$0
      sub(/[[:space:]]*#.*/, "", line)
      if (line !~ /^[[:space:]]*server([[:space:]]*\{|[[:space:]]*$)/) next
      if (file == base || file == active || file == limit) next
      if (file == "/etc/nginx/sites-enabled/default" ||
          file == "/etc/nginx/conf.d/default.conf" ||
          file == "/etc/nginx/http.d/default.conf") next
      if (file != "") print file
    }
  ' | awk 'NF' | sort -u
}

assert_nginx_exclusive() {
  other_files=$(other_nginx_server_files) || return 1
  [ -z "$other_files" ]
}

reload_nginx() {
  command -v nginx >/dev/null 2>&1 || return 1
  nginx -t >/dev/null 2>&1 || return 1
  nginx_running || return 1
  if uses_systemd; then
    systemctl reload nginx >/dev/null 2>&1
  elif command -v rc-service >/dev/null 2>&1 && rc-service nginx status >/dev/null 2>&1; then
    rc-service nginx reload >/dev/null 2>&1
  elif command -v service >/dev/null 2>&1; then
    service nginx reload >/dev/null 2>&1
  else
    nginx -s reload >/dev/null 2>&1
  fi
}

restore_nginx_start_policy() {
  policy_rc=0
  if uses_systemd; then
    systemctl unmask --runtime nginx >/dev/null 2>&1 || policy_rc=1
    systemctl enable nginx >/dev/null 2>&1 || policy_rc=1
  elif command -v rc-service >/dev/null 2>&1; then
    if command -v rc-update >/dev/null 2>&1; then
      rc-update add nginx default >/dev/null 2>&1 || policy_rc=1
    fi
  elif command -v service >/dev/null 2>&1 && command -v update-rc.d >/dev/null 2>&1; then
    update-rc.d nginx enable >/dev/null 2>&1 || policy_rc=1
  fi
  [ "$policy_rc" -eq 0 ]
}

stop_nginx() {
  stop_rc=0
  if uses_systemd; then
    systemctl disable nginx >/dev/null 2>&1 || stop_rc=1
    systemctl stop nginx >/dev/null 2>&1 || stop_rc=1
    systemctl mask --runtime nginx >/dev/null 2>&1 || stop_rc=1
  elif command -v rc-service >/dev/null 2>&1; then
    if command -v rc-update >/dev/null 2>&1; then
      rc-update del nginx default >/dev/null 2>&1 || stop_rc=1
    fi
    rc-service nginx stop >/dev/null 2>&1 || stop_rc=1
  elif command -v service >/dev/null 2>&1; then
    if command -v update-rc.d >/dev/null 2>&1; then
      update-rc.d nginx disable >/dev/null 2>&1 || stop_rc=1
    fi
    service nginx stop >/dev/null 2>&1 || stop_rc=1
  elif nginx_running; then
    nginx -s stop >/dev/null 2>&1 || stop_rc=1
  fi
  [ "$stop_rc" -eq 0 ] || return 1
  nginx_wait_state STOPPED
}

start_nginx() {
  command -v nginx >/dev/null 2>&1 || return 1
  nginx -t >/dev/null 2>&1 || return 1
  start_rc=0
  restore_nginx_start_policy || start_rc=1
  if uses_systemd; then
    systemctl start nginx >/dev/null 2>&1 || start_rc=1
  elif command -v rc-service >/dev/null 2>&1; then
    rc-service nginx start >/dev/null 2>&1 || start_rc=1
  elif command -v service >/dev/null 2>&1; then
    service nginx start >/dev/null 2>&1 || start_rc=1
  else
    nginx >/dev/null 2>&1 || start_rc=1
  fi
  [ "$start_rc" -eq 0 ] || return 1
  nginx_wait_state RUNNING
}

service_name_valid() {
  service_name=${1:-}
  [ -n "$service_name" ] || return 1
  case "$service_name" in
    *[!A-Za-z0-9_.@-]*|.*|-*) return 1 ;;
  esac
  case "$(printf '%s' "$service_name" | tr 'A-Z' 'a-z')" in
    nginx|ssh|sshd|cron|crond|networking|network-manager|networkmanager|dbus|systemd-*|dmitbox-site-dns-watch)
      return 1
      ;;
  esac
}

linked_service_exists() {
  [ "$linked_enabled" = "1" ] || return 0
  service_name_valid "$linked_service" || return 1
  if uses_systemd; then
    service_load_state=$(systemctl show -p LoadState --value "${linked_service}.service" 2>/dev/null || true)
    [ "$service_load_state" = "loaded" ] || [ "$service_load_state" = "masked" ]
  elif command -v rc-service >/dev/null 2>&1; then
    [ -x "${init_dir}/${linked_service}" ] || rc-service -e 2>/dev/null | grep -Fxq "$linked_service"
  elif [ -x "${init_dir}/${linked_service}" ]; then
    return 0
  else
    return 1
  fi
}

linked_service_running() {
  [ "$linked_enabled" = "1" ] || return 1
  if uses_systemd; then
    systemctl is-active --quiet "${linked_service}.service" >/dev/null 2>&1
  elif command -v rc-service >/dev/null 2>&1; then
    rc-service "$linked_service" status >/dev/null 2>&1
  elif command -v service >/dev/null 2>&1; then
    service "$linked_service" status >/dev/null 2>&1
  else
    return 1
  fi
}

linked_service_runtime_state() {
  if [ "$linked_enabled" != "1" ]; then echo UNMANAGED
  elif ! linked_service_exists; then echo MISSING
  elif linked_service_running; then echo RUNNING
  else echo STOPPED
  fi
}

linked_service_wait_state() {
  wanted=$1
  attempts=0
  while [ "$attempts" -lt 10 ]; do
    if [ "$wanted" = "RUNNING" ] && linked_service_running; then return 0; fi
    if [ "$wanted" = "STOPPED" ] && ! linked_service_running; then return 0; fi
    attempts=$((attempts + 1))
    sleep 1
  done
  if [ "$wanted" = "RUNNING" ]; then linked_service_running; else ! linked_service_running; fi
}

stop_linked_service() {
  [ "$linked_enabled" = "1" ] || return 0
  linked_service_exists || return 1
  stop_rc=0
  if uses_systemd; then
    systemctl disable "${linked_service}.service" >/dev/null 2>&1 || stop_rc=1
    systemctl stop "${linked_service}.service" >/dev/null 2>&1 || stop_rc=1
    systemctl mask --runtime "${linked_service}.service" >/dev/null 2>&1 || stop_rc=1
  elif command -v rc-service >/dev/null 2>&1; then
    if command -v rc-update >/dev/null 2>&1; then
      rc-update del "$linked_service" default >/dev/null 2>&1 || stop_rc=1
    fi
    rc-service "$linked_service" stop >/dev/null 2>&1 || stop_rc=1
  elif command -v service >/dev/null 2>&1; then
    if command -v update-rc.d >/dev/null 2>&1; then
      update-rc.d "$linked_service" disable >/dev/null 2>&1 || stop_rc=1
    fi
    service "$linked_service" stop >/dev/null 2>&1 || stop_rc=1
  else
    return 1
  fi
  [ "$stop_rc" -eq 0 ] || return 1
  linked_service_wait_state STOPPED
}

restore_linked_start_policy() {
  [ "$linked_enabled" = "1" ] || return 0
  linked_service_exists || return 1
  policy_rc=0
  if uses_systemd; then
    systemctl unmask --runtime "${linked_service}.service" >/dev/null 2>&1 || policy_rc=1
    if [ "$linked_boot_enabled" = "1" ]; then
      systemctl enable "${linked_service}.service" >/dev/null 2>&1 || policy_rc=1
    else
      systemctl disable "${linked_service}.service" >/dev/null 2>&1 || policy_rc=1
    fi
  elif command -v rc-service >/dev/null 2>&1 && command -v rc-update >/dev/null 2>&1; then
    if [ "$linked_boot_enabled" = "1" ]; then
      rc-update add "$linked_service" default >/dev/null 2>&1 || policy_rc=1
    else
      rc-update del "$linked_service" default >/dev/null 2>&1 || policy_rc=1
    fi
  elif command -v service >/dev/null 2>&1 && command -v update-rc.d >/dev/null 2>&1; then
    if [ "$linked_boot_enabled" = "1" ]; then
      update-rc.d "$linked_service" enable >/dev/null 2>&1 || policy_rc=1
    else
      update-rc.d "$linked_service" disable >/dev/null 2>&1 || policy_rc=1
    fi
  fi
  [ "$policy_rc" -eq 0 ]
}

start_linked_service() {
  [ "$linked_enabled" = "1" ] || return 0
  linked_service_exists || return 1
  start_rc=0
  restore_linked_start_policy || start_rc=1
  if uses_systemd; then
    systemctl start "${linked_service}.service" >/dev/null 2>&1 || start_rc=1
  elif command -v rc-service >/dev/null 2>&1; then
    rc-service "$linked_service" start >/dev/null 2>&1 || start_rc=1
  elif command -v service >/dev/null 2>&1; then
    service "$linked_service" start >/dev/null 2>&1 || start_rc=1
  else
    return 1
  fi
  [ "$start_rc" -eq 0 ] || return 1
  linked_service_wait_state RUNNING
}

apply_linked_state() {
  desired=$1
  [ "$linked_enabled" = "1" ] || return 0
  case "$desired" in
    ACTIVE)
      if linked_service_running; then restore_linked_start_policy; return $?; fi
      start_linked_service
      ;;
    PAUSED) stop_linked_service ;;
    *) return 1 ;;
  esac
}

apply_site_state() {
  desired=$1
  force_reload=${2:-0}
  current_site=$(site_state) || return 1
  if [ "$current_site" = "$desired" ]; then
    case "$desired" in
      ACTIVE)
        if nginx_running; then
          restore_nginx_start_policy || return 1
          if [ "$force_reload" = "1" ]; then
            reload_nginx
          else
            return 0
          fi
        fi
        start_nginx
        ;;
      PAUSED)
        assert_nginx_exclusive || return 1
        stop_nginx
        ;;
      *) return 1 ;;
    esac
    return $?
  fi
  case "$desired:$current_site" in
    PAUSED:ACTIVE)
      assert_nginx_exclusive || return 1
      mv "$nginx_active" "$nginx_paused" || return 1
      if ! nginx -t >/dev/null 2>&1; then
        mv "$nginx_paused" "$nginx_active" >/dev/null 2>&1 || true
        return 1
      fi
      if stop_nginx; then return 0; fi
      mv "$nginx_paused" "$nginx_active" >/dev/null 2>&1 || true
      if nginx_running; then reload_nginx >/dev/null 2>&1 || true; else start_nginx >/dev/null 2>&1 || true; fi
      return 1
      ;;
    ACTIVE:PAUSED)
      mv "$nginx_paused" "$nginx_active" || return 1
      if ! nginx -t >/dev/null 2>&1; then
        mv "$nginx_active" "$nginx_paused" >/dev/null 2>&1 || true
        return 1
      fi
      if nginx_running; then
        if restore_nginx_start_policy && reload_nginx; then return 0; fi
      elif start_nginx; then
        return 0
      fi
      mv "$nginx_active" "$nginx_paused" >/dev/null 2>&1 || true
      stop_nginx >/dev/null 2>&1 || true
      return 1
      ;;
    *) return 1 ;;
  esac
}

site_domain=$(conf_value DOMAIN)
domain=$(conf_value CDN_GUARD_DOMAIN)
baseline=$(conf_value CDN_GUARD_BASELINE)
guard_enabled=$(conf_value CDN_GUARD_ENABLED)
linked_enabled=$(conf_value LINKED_SERVICE_ENABLED)
linked_service=$(conf_value LINKED_SERVICE_NAME)
linked_boot_enabled=$(conf_value LINKED_SERVICE_BOOT_ENABLED)
[ -n "$domain" ] || domain="$site_domain"
[ -n "$baseline" ] || baseline=$(conf_value DNS_BASELINE)
[ -n "$guard_enabled" ] || guard_enabled=1
[ -n "$linked_enabled" ] || linked_enabled=0
[ -n "$linked_boot_enabled" ] || linked_boot_enabled=1
linked_service=${linked_service%.service}
[ "$linked_enabled" = "0" ] || [ "$linked_enabled" = "1" ] || exit 3
[ "$linked_boot_enabled" = "0" ] || [ "$linked_boot_enabled" = "1" ] || exit 3
[ "$linked_enabled" != "1" ] || service_name_valid "$linked_service" || exit 3
[ -n "$domain" ] && [ -n "$baseline" ] || exit 0

resolve_addresses() {
  if command -v dig >/dev/null 2>&1; then
    dig +time=4 +tries=1 +short A "$domain" 2>/dev/null || true
    if printf '%s' "$baseline" | grep -q ':'; then
      dig +time=4 +tries=1 +short AAAA "$domain" 2>/dev/null || true
    fi
  elif command -v getent >/dev/null 2>&1; then
    getent ahostsv4 "$domain" 2>/dev/null || true
    if printf '%s' "$baseline" | grep -q ':'; then
      getent ahostsv6 "$domain" 2>/dev/null || true
    fi
  fi
}

normalize_addresses() {
  if command -v python3 >/dev/null 2>&1; then
    python3 -c 'import ipaddress, sys
networks = (ipaddress.ip_network("64:ff9b::/96"), ipaddress.ip_network("64:ff9b:1::/48"))
for line in sys.stdin:
    parts = line.split()
    if not parts:
        continue
    try:
        address = ipaddress.ip_address(parts[0].rstrip("."))
    except ValueError:
        continue
    if address.version == 6:
        if address.ipv4_mapped is not None or int(address) <= 0xFFFFFFFF:
            continue
        if any(address in network for network in networks):
            continue
    print(address.compressed)'
  else
    awk '{
      value=tolower($1)
      sub(/\.$/, "", value)
      if (value ~ /^::ffff:/) next
      if (value ~ /:/ || value ~ /^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$/) print value
    }'
  fi
}

detect_cloudflare() {
  if ! command -v python3 >/dev/null 2>&1; then
    echo UNKNOWN
    return 0
  fi
  python3 -c 'import ipaddress, sys
networks = tuple(ipaddress.ip_network(value) for value in (
    "173.245.48.0/20", "103.21.244.0/22", "103.22.200.0/22",
    "103.31.4.0/22", "141.101.64.0/18", "108.162.192.0/18",
    "190.93.240.0/20", "188.114.96.0/20", "197.234.240.0/22",
    "198.41.128.0/17", "162.158.0.0/15", "104.16.0.0/13",
    "104.24.0.0/14", "172.64.0.0/13", "131.0.72.0/22",
    "2400:cb00::/32", "2606:4700::/32", "2803:f800::/32",
    "2405:b500::/32", "2405:8100::/32", "2a06:98c0::/29",
    "2c0f:f248::/32",
))
for line in sys.stdin:
    try:
        address = ipaddress.ip_address(line.strip())
    except ValueError:
        continue
    if any(address in network for network in networks):
        print("YES")
        raise SystemExit
print("NO")'
}

baseline=$(printf '%s\n' "$baseline" | tr ',' '\n' | normalize_addresses | sort -u | paste -sd, -)
current=$(resolve_addresses | normalize_addresses | sort -u | paste -sd, -)
state=OK
if [ -z "$current" ]; then
  state=UNRESOLVED
elif [ "$current" != "$baseline" ]; then
  state=CHANGED
fi
cdn_state=UNKNOWN
if [ -n "$current" ]; then
  cdn_state=$(printf '%s\n' "$current" | tr ',' '\n' | detect_cloudflare)
fi

previous_state=$(status_value STATE)
previous_guard=$(status_value GUARD_STATE)
locked_at=$(status_value LOCKED_AT)
current_site=$(site_state 2>/dev/null || echo ERROR)
desired_site="$current_site"
desired_linked="$current_site"
force_reload=0
guard_state=ERROR
action_rc=0

case "$mode" in
  --force-active)
    desired_site=ACTIVE
    desired_linked=ACTIVE
    force_reload=1
    ;;
  --sync)
    force_reload=1
    if [ "$guard_enabled" != "1" ]; then
      desired_site=ACTIVE
    elif [ "$cdn_state" = "YES" ]; then
      desired_site=PAUSED
    elif [ -n "$current" ] && [ "$cdn_state" = "NO" ] && [ "$current" = "$baseline" ]; then
      desired_site=ACTIVE
    fi
    ;;
  check|--check)
    if [ "$guard_enabled" != "1" ]; then
      desired_site=ACTIVE
    elif [ "$cdn_state" = "YES" ]; then
      desired_site=PAUSED
    elif [ -n "$current" ] && [ "$cdn_state" = "NO" ] && [ "$current" = "$baseline" ]; then
      desired_site=ACTIVE
    fi
    ;;
  *) exit 2 ;;
esac
desired_linked="$desired_site"

if [ "$desired_site" != "ACTIVE" ] && [ "$desired_site" != "PAUSED" ]; then
  action_rc=1
  desired_site=ERROR
elif [ "$desired_site" = "PAUSED" ]; then
  apply_linked_state PAUSED || action_rc=1
  apply_site_state PAUSED "$force_reload" || action_rc=1
  desired_site=$(site_state 2>/dev/null || echo ERROR)
else
  if ! apply_site_state ACTIVE "$force_reload"; then
    action_rc=1
  elif ! apply_linked_state ACTIVE; then
    stop_linked_service >/dev/null 2>&1 || true
    apply_site_state PAUSED 0 >/dev/null 2>&1 || true
    action_rc=1
  fi
  desired_site=$(site_state 2>/dev/null || echo ERROR)
fi

if [ "$action_rc" -ne 0 ] || [ "$desired_site" = "ERROR" ]; then
  guard_state=ERROR
elif [ "$guard_enabled" != "1" ] || [ "$mode" = "--force-active" ]; then
  guard_state=DISABLED
  locked_at=""
elif [ "$desired_site" = "PAUSED" ]; then
  guard_state=LOCKED
  [ -n "$locked_at" ] || locked_at=$(date -Is 2>/dev/null || date)
else
  guard_state=OPEN
  locked_at=""
fi

nginx_state=$(nginx_runtime_state)
linked_state=$(linked_service_runtime_state)
checked_at=$(date -Is 2>/dev/null || date)
tmp="${status}.tmp.$$"
{
  echo '# managed by dmitbox.sh - secure static website'
  printf 'STATE=%s\n' "$state"
  printf 'DOMAIN=%s\n' "$domain"
  printf 'BASELINE=%s\n' "$baseline"
  printf 'CURRENT=%s\n' "$current"
  printf 'CDN_STATE=%s\n' "$cdn_state"
  printf 'GUARD_STATE=%s\n' "$guard_state"
  printf 'SITE_STATE=%s\n' "$desired_site"
  printf 'NGINX_STATE=%s\n' "$nginx_state"
  printf 'LINKED_SERVICE_ENABLED=%s\n' "$linked_enabled"
  printf 'LINKED_SERVICE_NAME=%s\n' "$linked_service"
  printf 'LINKED_SERVICE_STATE=%s\n' "$linked_state"
  printf 'AUTO_RESUME=1\n'
  printf 'GUARD_BACKEND=service-interlock-v2\n'
  printf 'LOCKED_AT=%s\n' "$locked_at"
  printf 'CHECKED_AT=%s\n' "$checked_at"
} > "$tmp"
chmod 600 "$tmp" 2>/dev/null || true
mv -f "$tmp" "$status"

if command -v logger >/dev/null 2>&1; then
  if [ "$guard_state" != "$previous_guard" ] || [ "$state" != "$previous_state" ]; then
    logger -p daemon.warning -t dmitbox-site-dns-watch \
      "DNS=$state CDN=$cdn_state guard=$guard_state site=$desired_site nginx=$nginx_state linked=$linked_state domain=$domain current=${current:-none}"
  fi
fi
exit "$action_rc"
WATCHER
  watcher_content="${watcher_content//__DMITBOX_SITE_CONF__/$SECURE_SITE_CONF}"
  watcher_content="${watcher_content//__DMITBOX_DNS_STATUS__/$SECURE_SITE_DNS_STATUS}"
  watcher_content="${watcher_content//__DMITBOX_NGINX_BASE__/$SECURE_SITE_NGINX_CONF}"
  watcher_content="${watcher_content//__DMITBOX_NGINX_LIMIT__/$SECURE_SITE_NGINX_LIMIT_CONF}"
  watcher_content="${watcher_content//__DMITBOX_NGINX_ACTIVE__/$SECURE_SITE_NGINX_ACTIVE_CONF}"
  watcher_content="${watcher_content//__DMITBOX_NGINX_PAUSED__/$SECURE_SITE_NGINX_PAUSED_CONF}"
  watcher_content="${watcher_content//__DMITBOX_INIT_DIR__/$SECURE_SITE_INIT_DIR}"
  watcher_content="${watcher_content//__DMITBOX_SYSTEMD_RUNTIME_DIR__/$SECURE_SITE_SYSTEMD_RUNTIME_DIR}"
  write_file "$SECURE_SITE_DNS_WATCH" "$watcher_content" || return 1
  chmod 755 "$SECURE_SITE_DNS_WATCH" || return 1
  secure_site_setup_dns_watch_schedule || return 1
  "$SECURE_SITE_DNS_WATCH" --sync >/dev/null 2>&1
}

secure_site_dns_watch_status_legacy_autostop_unused() {
  local state="" domain="" current="" checked_at="" cdn_state="" guard_state=""
  local site_state="" nginx_state="" guard_backend="" locked_at="" rc=0
  local linked_enabled="0" linked_service="" linked_state="UNMANAGED"
  if [[ -x "$SECURE_SITE_DNS_WATCH" ]]; then
    "$SECURE_SITE_DNS_WATCH" >/dev/null 2>&1 || true
  fi
  if [[ ! -r "$SECURE_SITE_DNS_STATUS" ]]; then
    warn "DNS 变化监测尚无结果"
    return 1
  fi
  state="$(awk -F= '$1 == "STATE" {sub(/^[^=]*=/, ""); print; exit}' "$SECURE_SITE_DNS_STATUS")"
  domain="$(awk -F= '$1 == "DOMAIN" {sub(/^[^=]*=/, ""); print; exit}' "$SECURE_SITE_DNS_STATUS")"
  current="$(awk -F= '$1 == "CURRENT" {sub(/^[^=]*=/, ""); print; exit}' "$SECURE_SITE_DNS_STATUS")"
  cdn_state="$(awk -F= '$1 == "CDN_STATE" {sub(/^[^=]*=/, ""); print; exit}' "$SECURE_SITE_DNS_STATUS")"
  guard_state="$(awk -F= '$1 == "GUARD_STATE" {sub(/^[^=]*=/, ""); print; exit}' "$SECURE_SITE_DNS_STATUS")"
  site_state="$(awk -F= '$1 == "SITE_STATE" {sub(/^[^=]*=/, ""); print; exit}' "$SECURE_SITE_DNS_STATUS")"
  nginx_state="$(awk -F= '$1 == "NGINX_STATE" {sub(/^[^=]*=/, ""); print; exit}' "$SECURE_SITE_DNS_STATUS")"
  linked_enabled="$(awk -F= '$1 == "LINKED_SERVICE_ENABLED" {sub(/^[^=]*=/, ""); print; exit}' "$SECURE_SITE_DNS_STATUS")"
  linked_service="$(awk -F= '$1 == "LINKED_SERVICE_NAME" {sub(/^[^=]*=/, ""); print; exit}' "$SECURE_SITE_DNS_STATUS")"
  linked_state="$(awk -F= '$1 == "LINKED_SERVICE_STATE" {sub(/^[^=]*=/, ""); print; exit}' "$SECURE_SITE_DNS_STATUS")"
  guard_backend="$(awk -F= '$1 == "GUARD_BACKEND" {sub(/^[^=]*=/, ""); print; exit}' "$SECURE_SITE_DNS_STATUS")"
  locked_at="$(awk -F= '$1 == "LOCKED_AT" {sub(/^[^=]*=/, ""); print; exit}' "$SECURE_SITE_DNS_STATUS")"
  checked_at="$(awk -F= '$1 == "CHECKED_AT" {sub(/^[^=]*=/, ""); print; exit}' "$SECURE_SITE_DNS_STATUS")"
  linked_enabled="${linked_enabled:-0}"
  linked_state="${linked_state:-UNMANAGED}"
  if [[ -z "$site_state" || "$guard_backend" != "service-interlock-v2" ]]; then
    warn "当前仍是旧版停站方式，请选择“设置或修复自动停复站”启用关联服务联动保护"
    return 1
  fi
  case "$state" in
    OK) ok "DNS 与安装时记录一致（${checked_at:-未知时间}）" ;;
    CHANGED)
      warn "DNS 已与安装时记录不同（${checked_at:-未知时间}）"
      [[ -n "$current" ]] && echo "    - 当前：$current"
      rc=1
      ;;
    UNRESOLVED)
      warn "当前无法解析域名（${checked_at:-未知时间}）"
      rc=1
      ;;
    *)
      warn "DNS 变化监测状态无效"
      rc=1
      ;;
  esac
  [[ -n "$domain" ]] && echo "    - 监测域名：$domain"
  case "$cdn_state" in
    YES) warn "检测到域名正在使用 Cloudflare 代理"; rc=1 ;;
    NO) ok "未检测到 Cloudflare 代理地址" ;;
    UNKNOWN|"") warn "暂时无法确认 CDN 状态"; rc=1 ;;
    *) warn "CDN 检测状态无效"; rc=1 ;;
  esac
  case "$guard_state" in
    OPEN)
      if [[ "$site_state" == "ACTIVE" && "$nginx_state" == "RUNNING" && \
            ( "$linked_enabled" != "1" || "$linked_state" == "RUNNING" ) ]]; then
        ok "域名代理自动停站已启用：网站服务当前正常开放"
        if [[ "$linked_enabled" == "1" ]]; then
          ok "关联服务 ${linked_service}.service 正在运行并受联动保护"
        else
          warn "未配置关联服务联动：其他独立监听端口不受保护"
          rc=1
        fi
      else
        warn "直连状态下服务未可靠启动（网站=${site_state:-未知}，Nginx=${nginx_state:-未知}，关联=${linked_state:-未知}）"
        rc=1
      fi
      ;;
    LOCKED)
      if [[ "$site_state" == "PAUSED" && "$nginx_state" == "STOPPED" && \
            ( "$linked_enabled" != "1" || "$linked_state" == "STOPPED" ) ]]; then
        warn "检测到 Cloudflare：网站服务已自动停止并锁定"
        info "源站 TCP/80、TCP/443 已停止监听，公网和本机均无法访问该网站"
        if [[ "$linked_enabled" == "1" ]]; then
          ok "关联服务 ${linked_service}.service 已停止，其全部监听端口和现有连接均已切断"
        else
          warn "未配置关联服务联动，其他独立监听端口可能仍在转发流量"
        fi
      else
        warn "Cloudflare 已命中，但硬停状态不完整（网站=${site_state:-未知}，Nginx=${nginx_state:-未知}，关联=${linked_state:-未知}）"
      fi
      info "去掉 Cloudflare 后，待本机 DNS 恢复原始直连地址，监测器通常在 1 分钟内恢复全部关联服务"
      [[ -n "$locked_at" ]] && echo "    - 暂停时间：$locked_at"
      rc=1
      ;;
    DISABLED)
      if [[ "$site_state" == "ACTIVE" && "$nginx_state" == "RUNNING" && \
            ( "$linked_enabled" != "1" || "$linked_state" == "RUNNING" ) ]]; then
        info "域名代理自动停站未启用，网站与原关联服务保持开放"
      else
        warn "保护已停用，但服务未完全恢复（网站=${site_state:-未知}，Nginx=${nginx_state:-未知}，关联=${linked_state:-未知}）"
        rc=1
      fi
      ;;
    ERROR|"")
      warn "自动停复失败；可能存在其他站点、关联服务缺失或服务停启故障"
      info "为避免误停其他网站，监测器遇到归属不明的 Nginx 站点时会拒绝硬停"
      info "请进入管理菜单执行“设置或修复自动停复站”"
      rc=1
      ;;
    *) warn "网站自动停复状态无效（${site_state:-未知}）"; rc=1 ;;
  esac
  return "$rc"
}

secure_site_https_health() {
  local domain="$1"
  have_cmd curl || return 2
  if curl --help all 2>/dev/null | grep -q -- '--tls-max'; then
    curl --noproxy '*' -fsS --max-time 10 --tlsv1.3 --tls-max 1.3 \
      --resolve "${domain}:${SECURE_SITE_HTTPS_PORT}:127.0.0.1" \
      "https://${domain}:${SECURE_SITE_HTTPS_PORT}/healthz" | grep -Fqx 'ok'
  else
    curl --noproxy '*' -fsS --max-time 10 --tlsv1.3 \
      --resolve "${domain}:${SECURE_SITE_HTTPS_PORT}:127.0.0.1" \
      "https://${domain}:${SECURE_SITE_HTTPS_PORT}/healthz" | grep -Fqx 'ok'
  fi
}

secure_site_hosts_pin_apply() {
  local domain="$1"
  valid_domain_name "$domain" || return 1
  have_cmd python3 || { warn "缺少 Python 3，无法安全写入本机回源锁定"; return 1; }
  [[ -f "$SECURE_SITE_HOSTS_FILE" ]] || { warn "未找到 hosts 文件：${SECURE_SITE_HOSTS_FILE}"; return 1; }
  ensure_dir "$(dirname "$SECURE_SITE_HOSTS_BACKUP")" || return 1
  python3 - "$SECURE_SITE_HOSTS_FILE" "$SECURE_SITE_HOSTS_BACKUP" \
    "$SECURE_SITE_HOSTS_TAG" "$domain" <<'PY'
import errno
import json
import os
import re
import stat
import sys
import tempfile

hosts_path, backup_path, tag, domain = sys.argv[1:]
marker = "dmitbox-secure-site-hosts-v1"

def split_line(line):
    return line.rstrip("\r\n")

def has_domain(line):
    body = line.split("#", 1)[0]
    fields = body.split()
    return len(fields) > 1 and domain in fields[1:]

def remove_domain(line):
    raw = split_line(line)
    body, found, comment = raw.partition("#")
    fields = body.split()
    if len(fields) < 2 or domain not in fields[1:]:
        return raw
    kept = [fields[0]] + [value for value in fields[1:] if value != domain]
    if len(kept) == 1:
        return None
    indent = re.match(r"^\s*", raw).group(0)
    rebuilt = indent + " ".join(kept)
    if found:
        rebuilt += "  #" + comment
    return rebuilt

def replace_file(path, lines):
    directory = os.path.dirname(path) or "."
    mode = stat.S_IMODE(os.stat(path).st_mode)
    fd, temporary = tempfile.mkstemp(prefix=".dmitbox-hosts-", dir=directory, text=True)
    try:
        with os.fdopen(fd, "w", encoding="utf-8", newline="\n") as handle:
            for line in lines:
                handle.write(line.rstrip("\r\n") + "\n")
            handle.flush()
            os.fsync(handle.fileno())
        os.chmod(temporary, mode)
        try:
            os.replace(temporary, path)
            temporary = None
        except OSError as error:
            if error.errno not in (errno.EBUSY, errno.EXDEV, errno.EPERM):
                raise
            with open(temporary, "r", encoding="utf-8") as source, \
                 open(path, "w", encoding="utf-8", newline="\n") as target:
                target.write(source.read())
                target.flush()
                os.fsync(target.fileno())
    finally:
        if temporary and os.path.exists(temporary):
            os.unlink(temporary)

with open(hosts_path, "r", encoding="utf-8", errors="surrogateescape") as handle:
    original_lines = handle.readlines()

if os.path.exists(backup_path):
    with open(backup_path, "r", encoding="utf-8") as handle:
        backup = json.load(handle)
    if backup.get("marker") != marker or backup.get("domain") != domain:
        raise SystemExit("existing hosts backup belongs to another domain or is invalid")
else:
    records = []
    for line in original_lines:
        if tag not in line and has_domain(line):
            records.append({"original": split_line(line), "without_domain": remove_domain(line)})
    backup = {"marker": marker, "domain": domain, "records": records}
    backup_directory = os.path.dirname(backup_path) or "."
    fd, temporary = tempfile.mkstemp(prefix=".dmitbox-hosts-backup-", dir=backup_directory, text=True)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as handle:
            json.dump(backup, handle, ensure_ascii=True, indent=2)
            handle.write("\n")
            handle.flush()
            os.fsync(handle.fileno())
        os.chmod(temporary, 0o600)
        os.replace(temporary, backup_path)
        temporary = None
    finally:
        if temporary and os.path.exists(temporary):
            os.unlink(temporary)

new_lines = []
for line in original_lines:
    if tag in line:
        continue
    rewritten = remove_domain(line)
    if rewritten is not None:
        new_lines.append(rewritten)
new_lines.append(f"127.0.0.1 {domain} # {tag}")
replace_file(hosts_path, new_lines)
PY
}

secure_site_hosts_pin_remove() {
  local domain="$1"
  valid_domain_name "$domain" || return 1
  [[ -f "$SECURE_SITE_HOSTS_FILE" ]] || return 0
  have_cmd python3 || { warn "缺少 Python 3，无法安全恢复 hosts"; return 1; }
  python3 - "$SECURE_SITE_HOSTS_FILE" "$SECURE_SITE_HOSTS_BACKUP" \
    "$SECURE_SITE_HOSTS_TAG" "$domain" <<'PY'
import errno
import json
import os
import stat
import sys
import tempfile

hosts_path, backup_path, tag, domain = sys.argv[1:]
marker = "dmitbox-secure-site-hosts-v1"

def clean(line):
    return line.rstrip("\r\n")

def has_domain(line):
    fields = line.split("#", 1)[0].split()
    return len(fields) > 1 and domain in fields[1:]

def replace_file(path, lines):
    directory = os.path.dirname(path) or "."
    mode = stat.S_IMODE(os.stat(path).st_mode)
    fd, temporary = tempfile.mkstemp(prefix=".dmitbox-hosts-", dir=directory, text=True)
    try:
        with os.fdopen(fd, "w", encoding="utf-8", newline="\n") as handle:
            for line in lines:
                handle.write(clean(line) + "\n")
            handle.flush()
            os.fsync(handle.fileno())
        os.chmod(temporary, mode)
        try:
            os.replace(temporary, path)
            temporary = None
        except OSError as error:
            if error.errno not in (errno.EBUSY, errno.EXDEV, errno.EPERM):
                raise
            with open(temporary, "r", encoding="utf-8") as source, \
                 open(path, "w", encoding="utf-8", newline="\n") as target:
                target.write(source.read())
                target.flush()
                os.fsync(target.fileno())
    finally:
        if temporary and os.path.exists(temporary):
            os.unlink(temporary)

backup = None
if os.path.exists(backup_path):
    with open(backup_path, "r", encoding="utf-8") as handle:
        backup = json.load(handle)
    if backup.get("marker") != marker or backup.get("domain") != domain:
        raise SystemExit("hosts backup belongs to another domain or is invalid")

with open(hosts_path, "r", encoding="utf-8", errors="surrogateescape") as handle:
    lines = [clean(line) for line in handle]
lines = [line for line in lines if tag not in line]

# Preserve a mapping the administrator added after installation.  Otherwise
# merge the backed-up domain token into the still-present alias line when
# possible, and append the original record only when no derived line remains.
if backup and not any(has_domain(line) for line in lines):
    for record in backup.get("records", []):
        original = record.get("original")
        without_domain = record.get("without_domain")
        if not isinstance(original, str):
            continue
        if isinstance(without_domain, str) and without_domain in lines:
            lines[lines.index(without_domain)] = original
        elif original not in lines:
            lines.append(original)

replace_file(hosts_path, lines)
if backup and os.path.exists(backup_path):
    os.unlink(backup_path)
PY
}

secure_site_hosts_pin_status() {
  local domain="$1" resolved=""
  valid_domain_name "$domain" || return 1
  [[ -r "$SECURE_SITE_HOSTS_FILE" ]] || return 1
  awk -v domain="$domain" -v tag="$SECURE_SITE_HOSTS_TAG" '
    index($0, tag) {
      body=$0; sub(/[[:space:]]*#.*/, "", body)
      count=split(body, field, /[[:space:]]+/)
      if (field[1] == "127.0.0.1") {
        for (i=2; i<=count; i++) if (field[i] == domain) found=1
      }
    }
    END {exit !found}
  ' "$SECURE_SITE_HOSTS_FILE" || return 1
  if have_cmd getent; then
    resolved="$(getent ahostsv4 "$domain" 2>/dev/null | awk '{print $1}' | awk 'NF' | sort -u | paste -sd, -)"
    [[ "$resolved" == "127.0.0.1" ]] || return 1
  fi
}

secure_site_write_managed_conf_legacy_autostop_unused() {
  local domain="$1" template="$2" request_rate="$3" connection_limit="$4"
  local dns_baseline="${5:-}" sni_reject_mode="${6:-certificate}"
  local guard_enabled="${7:-1}" linked_enabled="${8:-0}" linked_service="${9:-}"
  local linked_boot_enabled="${10:-1}"
  local created=""
  [[ "$sni_reject_mode" == "strict" || "$sni_reject_mode" == "certificate" ]] || return 1
  [[ "$guard_enabled" == "0" || "$guard_enabled" == "1" ]] || return 1
  [[ "$linked_enabled" == "0" || "$linked_enabled" == "1" ]] || return 1
  [[ "$linked_boot_enabled" == "0" || "$linked_boot_enabled" == "1" ]] || return 1
  linked_service="$(secure_site_linked_service_normalize "$linked_service")"
  if [[ "$linked_enabled" == "1" ]]; then
    secure_site_linked_service_name_valid "$linked_service" || return 1
  else
    linked_service=""
  fi
  [[ -n "$dns_baseline" && "$dns_baseline" != *$'\n'* ]] || return 1
  created="$(secure_site_conf_value CREATED_AT 2>/dev/null || true)"
  [[ -n "$created" ]] || created="$(date -Is)"
  write_file "$SECURE_SITE_CONF" "# managed by dmitbox.sh - secure static website
DOMAIN=${domain}
TEMPLATE=${template}
REQUEST_RATE=${request_rate}
CONNECTION_LIMIT=${connection_limit}
SITE_MODE=public_tls
HTTPS_PORT=443
LOCAL_HTTPS_ENDPOINT=127.0.0.1:${SECURE_SITE_HTTPS_PORT}
SNI_REJECT_MODE=${sni_reject_mode}
DNS_BASELINE=${dns_baseline}
CDN_GUARD_ENABLED=${guard_enabled}
CDN_GUARD_DOMAIN=${domain}
CDN_GUARD_BASELINE=${dns_baseline}
CDN_GUARD_ACTION=stop_services
CDN_GUARD_AUTO_RESUME=1
LINKED_SERVICE_ENABLED=${linked_enabled}
LINKED_SERVICE_NAME=${linked_service}
LINKED_SERVICE_BOOT_ENABLED=${linked_boot_enabled}
CREATED_AT=${created}
UPDATED_AT=$(date -Is)" || return 1
  chmod 600 "$SECURE_SITE_CONF"
}

secure_site_prepare_rollback() {
  local rollback=""
  rollback="$(mktemp -d /tmp/dmitbox-secure-site-rollback.XXXXXX)" || return 1
  if [[ -e "$SECURE_SITE_NGINX_CONF" ]]; then
    if ! write_file "$rollback/had-nginx" "1" || ! cp -a "$SECURE_SITE_NGINX_CONF" "$rollback/nginx.conf"; then
      rm -rf -- "$rollback"
      return 1
    fi
  fi
  if [[ -e "$SECURE_SITE_NGINX_LIMIT_CONF" ]]; then
    if ! write_file "$rollback/had-limit" "1" || ! cp -a "$SECURE_SITE_NGINX_LIMIT_CONF" "$rollback/limit.conf"; then
      rm -rf -- "$rollback"
      return 1
    fi
  fi
  if [[ -e "$SECURE_SITE_NGINX_ACTIVE_CONF" ]]; then
    if ! write_file "$rollback/had-nginx-active" "1" || ! cp -a "$SECURE_SITE_NGINX_ACTIVE_CONF" "$rollback/nginx-active.conf"; then
      rm -rf -- "$rollback"
      return 1
    fi
  fi
  if [[ -e "$SECURE_SITE_NGINX_PAUSED_CONF" ]]; then
    if ! write_file "$rollback/had-nginx-paused" "1" || ! cp -a "$SECURE_SITE_NGINX_PAUSED_CONF" "$rollback/nginx-domain.paused"; then
      rm -rf -- "$rollback"
      return 1
    fi
  fi
  if [[ -d "$SECURE_SITE_ROOT" ]]; then
    if ! write_file "$rollback/had-root" "1" || ! cp -a "$SECURE_SITE_ROOT" "$rollback/site-root"; then
      rm -rf -- "$rollback"
      return 1
    fi
  fi
  if [[ -e "$SECURE_SITE_CONF" ]]; then
    if ! write_file "$rollback/had-site-conf" "1" || ! cp -a "$SECURE_SITE_CONF" "$rollback/site.conf"; then
      rm -rf -- "$rollback"
      return 1
    fi
  fi
  if [[ -e "$SECURE_SITE_CERT_HOOK" ]]; then
    if ! write_file "$rollback/had-hook" "1" || ! cp -a "$SECURE_SITE_CERT_HOOK" "$rollback/cert-hook"; then
      rm -rf -- "$rollback"
      return 1
    fi
  fi
  if [[ -e "$SECURE_SITE_CERT_CRON" ]]; then
    if ! write_file "$rollback/had-cron" "1" || ! cp -a "$SECURE_SITE_CERT_CRON" "$rollback/cert-cron"; then
      rm -rf -- "$rollback"
      return 1
    fi
  fi
  if [[ -e "$SECURE_SITE_CERT_PERIODIC" ]]; then
    if ! write_file "$rollback/had-periodic" "1" || ! cp -a "$SECURE_SITE_CERT_PERIODIC" "$rollback/cert-periodic"; then
      rm -rf -- "$rollback"
      return 1
    fi
  fi
  if [[ -e "$SECURE_SITE_DNS_WATCH" ]]; then
    if ! write_file "$rollback/had-dns-watch" "1" || ! cp -a "$SECURE_SITE_DNS_WATCH" "$rollback/dns-watch"; then
      rm -rf -- "$rollback"
      return 1
    fi
  fi
  if [[ -e "$SECURE_SITE_DNS_WATCH_CRON" ]]; then
    if ! write_file "$rollback/had-dns-watch-cron" "1" || ! cp -a "$SECURE_SITE_DNS_WATCH_CRON" "$rollback/dns-watch-cron"; then
      rm -rf -- "$rollback"
      return 1
    fi
  fi
  if [[ -e "$SECURE_SITE_DNS_WATCH_PERIODIC" ]]; then
    if ! write_file "$rollback/had-dns-watch-periodic" "1" || ! cp -a "$SECURE_SITE_DNS_WATCH_PERIODIC" "$rollback/dns-watch-periodic"; then
      rm -rf -- "$rollback"
      return 1
    fi
  fi
  if [[ -e "$SECURE_SITE_DNS_WATCH_SERVICE" ]]; then
    if ! write_file "$rollback/had-dns-watch-service" "1" || ! cp -a "$SECURE_SITE_DNS_WATCH_SERVICE" "$rollback/dns-watch.service"; then
      rm -rf -- "$rollback"
      return 1
    fi
  fi
  if [[ -e "$SECURE_SITE_DNS_WATCH_TIMER" ]]; then
    if ! write_file "$rollback/had-dns-watch-timer" "1" || ! cp -a "$SECURE_SITE_DNS_WATCH_TIMER" "$rollback/dns-watch.timer"; then
      rm -rf -- "$rollback"
      return 1
    fi
  fi
  if [[ -e "$SECURE_SITE_DNS_WATCH_ALPINE_CRONTAB" ]]; then
    if ! write_file "$rollback/had-alpine-crontab" "1" || ! cp -a "$SECURE_SITE_DNS_WATCH_ALPINE_CRONTAB" "$rollback/alpine-crontab"; then
      rm -rf -- "$rollback"
      return 1
    fi
  fi
  if [[ -e "$SECURE_SITE_DNS_STATUS" ]]; then
    if ! write_file "$rollback/had-dns-status" "1" || ! cp -a "$SECURE_SITE_DNS_STATUS" "$rollback/dns-status"; then
      rm -rf -- "$rollback"
      return 1
    fi
  fi
  if [[ -e "$SECURE_SITE_HOSTS_FILE" ]]; then
    if ! write_file "$rollback/had-hosts" "1" || ! cp -a "$SECURE_SITE_HOSTS_FILE" "$rollback/hosts"; then
      rm -rf -- "$rollback"
      return 1
    fi
  fi
  if [[ -e "$SECURE_SITE_HOSTS_BACKUP" ]]; then
    if ! write_file "$rollback/had-hosts-backup" "1" || ! cp -a "$SECURE_SITE_HOSTS_BACKUP" "$rollback/hosts-backup"; then
      rm -rf -- "$rollback"
      return 1
    fi
  fi
  echo "$rollback"
}

secure_site_cleanup_rollback() {
  local rollback="$1"
  [[ "$rollback" == /tmp/dmitbox-secure-site-rollback.* && -d "$rollback" ]] || return 1
  rm -rf -- "$rollback"
}

secure_site_restore_rollback() {
  local rollback="$1"
  local changed_linked_enabled="0" changed_linked_name="" changed_linked_boot="1"
  local old_linked_enabled="0" old_linked_name=""
  [[ "$rollback" == /tmp/dmitbox-secure-site-rollback.* && -d "$rollback" ]] || return 1
  if secure_site_conf_is_managed; then
    changed_linked_enabled="$(secure_site_conf_value LINKED_SERVICE_ENABLED 2>/dev/null || true)"
    changed_linked_name="$(secure_site_conf_value LINKED_SERVICE_NAME 2>/dev/null || true)"
    changed_linked_boot="$(secure_site_conf_value LINKED_SERVICE_BOOT_ENABLED 2>/dev/null || true)"
    changed_linked_enabled="${changed_linked_enabled:-0}"
    changed_linked_boot="${changed_linked_boot:-1}"
  fi
  if [[ -r "$rollback/site.conf" ]]; then
    old_linked_enabled="$(awk -F= '$1 == "LINKED_SERVICE_ENABLED" {print $2; exit}' "$rollback/site.conf")"
    old_linked_name="$(awk -F= '$1 == "LINKED_SERVICE_NAME" {print $2; exit}' "$rollback/site.conf")"
    old_linked_enabled="${old_linked_enabled:-0}"
  fi
  secure_site_remove_dns_watch_schedule
  secure_site_guard_remove_firewall_rules >/dev/null 2>&1 || true
  rm -f "$SECURE_SITE_NGINX_CONF" "$SECURE_SITE_NGINX_LIMIT_CONF" \
    "$SECURE_SITE_NGINX_ACTIVE_CONF" "$SECURE_SITE_NGINX_PAUSED_CONF" "$SECURE_SITE_CONF" \
    "$SECURE_SITE_CERT_HOOK" "$SECURE_SITE_CERT_CRON" "$SECURE_SITE_CERT_PERIODIC" \
    "$SECURE_SITE_DNS_WATCH" "$SECURE_SITE_DNS_STATUS" \
    "${SECURE_SITE_DNS_STATUS}.lock" >/dev/null 2>&1 || true
  rm -rf -- "$SECURE_SITE_ROOT"
  if [[ -f "$rollback/had-nginx" ]]; then cp -a "$rollback/nginx.conf" "$SECURE_SITE_NGINX_CONF"; fi
  if [[ -f "$rollback/had-limit" ]]; then cp -a "$rollback/limit.conf" "$SECURE_SITE_NGINX_LIMIT_CONF"; fi
  if [[ -f "$rollback/had-nginx-active" ]]; then cp -a "$rollback/nginx-active.conf" "$SECURE_SITE_NGINX_ACTIVE_CONF"; fi
  if [[ -f "$rollback/had-nginx-paused" ]]; then cp -a "$rollback/nginx-domain.paused" "$SECURE_SITE_NGINX_PAUSED_CONF"; fi
  if [[ -f "$rollback/had-root" ]]; then cp -a "$rollback/site-root" "$SECURE_SITE_ROOT"; fi
  if [[ -f "$rollback/had-site-conf" ]]; then cp -a "$rollback/site.conf" "$SECURE_SITE_CONF"; fi
  if [[ -f "$rollback/had-hook" ]]; then
    ensure_dir "$(dirname "$SECURE_SITE_CERT_HOOK")"
    cp -a "$rollback/cert-hook" "$SECURE_SITE_CERT_HOOK"
  fi
  if [[ -f "$rollback/had-cron" ]]; then
    ensure_dir "$(dirname "$SECURE_SITE_CERT_CRON")"
    cp -a "$rollback/cert-cron" "$SECURE_SITE_CERT_CRON"
  fi
  if [[ -f "$rollback/had-periodic" ]]; then
    ensure_dir "$(dirname "$SECURE_SITE_CERT_PERIODIC")"
    cp -a "$rollback/cert-periodic" "$SECURE_SITE_CERT_PERIODIC"
  fi
  if [[ -f "$rollback/had-dns-watch" ]]; then
    ensure_dir "$(dirname "$SECURE_SITE_DNS_WATCH")"
    cp -a "$rollback/dns-watch" "$SECURE_SITE_DNS_WATCH"
  fi
  if [[ -f "$rollback/had-dns-watch-cron" ]]; then
    ensure_dir "$(dirname "$SECURE_SITE_DNS_WATCH_CRON")"
    cp -a "$rollback/dns-watch-cron" "$SECURE_SITE_DNS_WATCH_CRON"
  fi
  if [[ -f "$rollback/had-dns-watch-periodic" ]]; then
    ensure_dir "$(dirname "$SECURE_SITE_DNS_WATCH_PERIODIC")"
    cp -a "$rollback/dns-watch-periodic" "$SECURE_SITE_DNS_WATCH_PERIODIC"
  fi
  if [[ -f "$rollback/had-dns-watch-service" ]]; then
    ensure_dir "$(dirname "$SECURE_SITE_DNS_WATCH_SERVICE")"
    cp -a "$rollback/dns-watch.service" "$SECURE_SITE_DNS_WATCH_SERVICE"
  fi
  if [[ -f "$rollback/had-dns-watch-timer" ]]; then
    ensure_dir "$(dirname "$SECURE_SITE_DNS_WATCH_TIMER")"
    cp -a "$rollback/dns-watch.timer" "$SECURE_SITE_DNS_WATCH_TIMER"
  fi
  if [[ -f "$rollback/had-alpine-crontab" ]]; then
    ensure_dir "$(dirname "$SECURE_SITE_DNS_WATCH_ALPINE_CRONTAB")"
    cp -a "$rollback/alpine-crontab" "$SECURE_SITE_DNS_WATCH_ALPINE_CRONTAB"
  fi
  if [[ -f "$rollback/had-dns-status" ]]; then
    ensure_dir "$(dirname "$SECURE_SITE_DNS_STATUS")"
    cp -a "$rollback/dns-status" "$SECURE_SITE_DNS_STATUS"
  fi
  if [[ -f "$rollback/had-hosts" ]]; then
    ensure_dir "$(dirname "$SECURE_SITE_HOSTS_FILE")"
    cp -f "$rollback/hosts" "$SECURE_SITE_HOSTS_FILE"
  fi
  if [[ -f "$rollback/had-hosts-backup" ]]; then
    ensure_dir "$(dirname "$SECURE_SITE_HOSTS_BACKUP")"
    cp -a "$rollback/hosts-backup" "$SECURE_SITE_HOSTS_BACKUP"
  else
    rm -f "$SECURE_SITE_HOSTS_BACKUP" >/dev/null 2>&1 || true
  fi
  if secure_site_systemd_running && [[ -f "$SECURE_SITE_DNS_WATCH_TIMER" ]]; then
    systemctl daemon-reload >/dev/null 2>&1 || true
    systemctl enable --now dmitbox-site-dns-watch.timer >/dev/null 2>&1 || true
  fi
  secure_site_nginx_reload >/dev/null 2>&1 || true
  if [[ -x "$SECURE_SITE_DNS_WATCH" ]]; then
    "$SECURE_SITE_DNS_WATCH" >/dev/null 2>&1 || true
  fi
  if [[ "$changed_linked_enabled" == "1" && \
        ( "$old_linked_enabled" != "1" || "$changed_linked_name" != "$old_linked_name" ) ]]; then
    secure_site_linked_service_start_now "$changed_linked_name" "$changed_linked_boot" >/dev/null 2>&1 || \
      warn "回滚完成，但新关联服务 ${changed_linked_name}.service 未能恢复，请手动检查"
  fi
  secure_site_cleanup_rollback "$rollback" || true
}

secure_site_conf_set() {
  local key="$1" value="$2" tmp="${SECURE_SITE_CONF}.tmp.$$"
  [[ "$key" =~ ^[A-Z0-9_]+$ && "$value" != *$'\n'* ]] || return 1
  awk -F= -v key="$key" -v value="$value" '
    BEGIN {found=0}
    $1 == key {print key "=" value; found=1; next}
    {print}
    END {if (!found) print key "=" value}
  ' "$SECURE_SITE_CONF" > "$tmp" || { rm -f "$tmp"; return 1; }
  chmod 600 "$tmp" >/dev/null 2>&1 || true
  mv -f "$tmp" "$SECURE_SITE_CONF"
}

secure_site_conf_unset() {
  local key="$1" tmp="${SECURE_SITE_CONF}.tmp.$$"
  [[ "$key" =~ ^[A-Z0-9_]+$ ]] || return 1
  awk -F= -v key="$key" '$1 != key {print}' "$SECURE_SITE_CONF" > "$tmp" || {
    rm -f "$tmp"
    return 1
  }
  chmod 600 "$tmp" >/dev/null 2>&1 || true
  mv -f "$tmp" "$SECURE_SITE_CONF"
}

secure_site_show_info_legacy_autostop_unused() {
  menu_header "建站信息" "域名、文件位置与已启用的防护"
  secure_site_select_nginx_paths
  if ! secure_site_conf_is_managed; then
    warn "尚未使用轻量建站"
    return 1
  fi
  local domain="" template="" request_rate="" connection_limit="" sni_reject_mode=""
  local guard_enabled="" guard_domain="" linked_enabled="0" linked_service=""
  domain="$(secure_site_conf_value DOMAIN)"
  template="$(secure_site_conf_value TEMPLATE)"
  request_rate="$(secure_site_conf_value REQUEST_RATE)"
  connection_limit="$(secure_site_conf_value CONNECTION_LIMIT)"
  sni_reject_mode="$(secure_site_conf_value SNI_REJECT_MODE 2>/dev/null || echo certificate)"
  guard_enabled="$(secure_site_conf_value CDN_GUARD_ENABLED 2>/dev/null || true)"
  guard_domain="$(secure_site_conf_value CDN_GUARD_DOMAIN 2>/dev/null || true)"
  linked_enabled="$(secure_site_conf_value LINKED_SERVICE_ENABLED 2>/dev/null || true)"
  linked_service="$(secure_site_conf_value LINKED_SERVICE_NAME 2>/dev/null || true)"
  guard_enabled="${guard_enabled:-1}"
  guard_domain="${guard_domain:-$domain}"
  linked_enabled="${linked_enabled:-0}"

  menu_section "网站"
  print_kv "访问地址" "https://${domain}"
  print_kv "站点目录" "$SECURE_SITE_ROOT"
  print_kv "导航配色" "$template"
  print_kv "Nginx 配置" "$SECURE_SITE_NGINX_CONF"
  print_kv "HTTPS 端口" "公网 TCP/443"
  print_kv "本机网站入口" "127.0.0.1:${SECURE_SITE_HTTPS_PORT}（与公网网站共用 443）"

  menu_section "安全措施"
  print_kv "请求速率" "${request_rate} 次/秒"
  print_kv "并发连接" "$connection_limit"
  print_kv "监测域名" "$guard_domain"
  print_kv "代理命中动作" "$([[ "$linked_enabled" == "1" ]] && echo 停止网站及关联服务 || echo 仅停止网站服务)"
  print_kv "关联服务" "$([[ "$linked_enabled" == "1" ]] && echo "${linked_service}.service" || echo 未配置)"
  print_kv "恢复方式" "DNS 恢复直连后自动恢复全部关联服务"
  print_kv "代理自动停站" "$([[ "$guard_enabled" == "1" ]] && echo 已启用 || echo 未启用)"
  info "网站通过配置域名直接监听公网 TCP/443"
  if [[ "$sni_reject_mode" == "strict" ]]; then
    info "未知 SNI 会在 TLS 握手阶段被拒绝"
  else
    info "未知 SNI 会由兼容规则立即关闭连接"
  fi
  info "仅允许 GET/HEAD，未知路径返回 404"
  info "HTTP/HTTPS 使用 IPv4 或 IPv6 地址直接访问时不会返回网站内容"
  info "HTTPS 仅接受配置域名的 SNI 与 Host"
  info "已限制请求体与超时，并关闭目录脚本执行"
  info "已启用 HSTS、CSP、防嵌入及隐私响应头"
  info "每分钟核对域名解析；检测到 Cloudflare 后停止并锁定整个 Nginx 服务"
  if [[ "$linked_enabled" == "1" ]]; then
    info "同时停止并锁定 ${linked_service}.service，切断它的全部监听端口和现有连接"
  else
    warn "尚未配置关联服务联动，其他独立监听端口仍可能继续转发流量"
  fi
  info "停站时源站 TCP/80、TCP/443 停止监听，公网和本机 127.0.0.1:${SECURE_SITE_HTTPS_PORT} 均不可访问"
  info "去掉 Cloudflare 后，待本机 DNS 解析恢复安装基线，监测器会自动启用 Nginx 并复站"
  warn "整服务停复仅适用于本机没有其他 Nginx 网站的情况"
  warn "关联后整个服务都会停复，该服务内的其他功能也会同时中断"
  info "访问日志已关闭，错误日志仅记录严重故障"
}

secure_site_site_status_legacy_autostop_unused() {
  menu_header "轻量建站" "域名、证书、监听端口与安全措施检查"
  secure_site_select_nginx_paths
  if ! secure_site_conf_is_managed; then
    warn "尚未安装"
    echo
    info "用途：一键生成独立、轻量、无脚本的 HTTPS 导航站"
    info "要求：一个所有 A/AAAA 记录均直接指向本机的独立域名"
    info "Nginx 使用公网 TCP/80 与 TCP/443，安装后可直接通过域名访问"
    info "网站本身也可通过本机 127.0.0.1:${SECURE_SITE_HTTPS_PORT} 访问，无需额外本机端口"
    info "每分钟识别 Cloudflare；命中后停止网站与可选关联服务，恢复直连后自动启动"
    warn "自动停复仅适用于本机没有其他 Nginx 网站的情况"
    info "可在域名代理保护中配置一个关联系统服务，切断其任意监听端口"
    warn "网站级限制不能替代服务器供应商的网络层防护"
    return 0
  fi

  local domain="" site_mode="" https_port="" listener80="" listener443=""
  local health_rc="0" reject_count="0" site_state="" domain_conf=""
  local linked_enabled="0" linked_service="" linked_state="UNMANAGED"
  domain="$(secure_site_conf_value DOMAIN)"
  site_mode="$(secure_site_conf_value SITE_MODE 2>/dev/null || true)"
  https_port="$(secure_site_conf_value HTTPS_PORT 2>/dev/null || true)"
  linked_enabled="$(secure_site_conf_value LINKED_SERVICE_ENABLED 2>/dev/null || true)"
  linked_service="$(secure_site_conf_value LINKED_SERVICE_NAME 2>/dev/null || true)"
  linked_enabled="${linked_enabled:-0}"
  menu_section "配置"
  print_kv "域名" "$domain"
  print_kv "访问地址" "https://${domain}"
  print_kv "站点目录" "$SECURE_SITE_ROOT"
  print_kv "本机网站入口" "127.0.0.1:${SECURE_SITE_HTTPS_PORT}"
  if [[ "$site_mode" == "public_tls" && "$https_port" == "443" ]]; then
    print_kv "HTTPS 监听" "公网 TCP/443"
  else
    warn "当前站点仍是旧版模式，请执行安装/修复迁移到公网 TCP/443"
  fi

  menu_section "DNS"
  secure_site_dns_audit "$domain" || true
  secure_site_dns_watch_status || true
  site_state="$(awk -F= '$1 == "SITE_STATE" {print $2; exit}' "$SECURE_SITE_DNS_STATUS" 2>/dev/null || true)"
  linked_state="$(awk -F= '$1 == "LINKED_SERVICE_STATE" {print $2; exit}' "$SECURE_SITE_DNS_STATUS" 2>/dev/null || true)"
  linked_state="${linked_state:-UNMANAGED}"
  print_kv "网站自动状态" "${site_state:-未知}"
  print_kv "关联服务" "$([[ "$linked_enabled" == "1" ]] && echo "${linked_service}.service" || echo 未配置)"
  print_kv "关联服务状态" "$linked_state"
  if secure_site_dns_watch_schedule_active; then
    ok "DNS/CDN 每分钟监测调度正常"
  else
    warn "DNS/CDN 每分钟监测调度异常，建议执行安装/修复"
  fi

  menu_section "Nginx"
  if have_cmd nginx && nginx -t >/dev/null 2>&1; then ok "Nginx 配置校验通过"; else warn "Nginx 配置校验失败"; fi
  listener80="$(secure_site_port_listener 80 || true)"
  listener443="$(secure_site_port_listener 443 || true)"
  if [[ "$site_state" == "PAUSED" ]]; then
    if pgrep -x nginx >/dev/null 2>&1; then
      warn "网站已暂停，但 Nginx 仍在运行，建议立即修复"
    else
      ok "Nginx 已按保护策略停止"
    fi
    if [[ -z "$listener80" && -z "$listener443" ]]; then
      ok "源站 TCP/80 与 TCP/443 均已停止监听"
    else
      warn "网站已暂停，但 TCP/80 或 TCP/443 仍被进程占用"
      [[ -n "$listener80" ]] && echo "$listener80"
      [[ -n "$listener443" ]] && echo "$listener443"
    fi
  else
    if pgrep -x nginx >/dev/null 2>&1; then ok "Nginx 正在运行"; else warn "Nginx 未运行"; fi
    if grep -qi nginx <<< "$listener80"; then
      ok "Nginx 正在监听公网 TCP/80"
    else
      warn "Nginx 未正常监听公网 TCP/80"
      [[ -n "$listener80" ]] && echo "$listener80"
    fi
    if grep -qi nginx <<< "$listener443"; then
      ok "Nginx 正在监听公网 TCP/443"
    else
      warn "Nginx 未正常监听公网 TCP/443"
      [[ -n "$listener443" ]] && echo "$listener443"
    fi
  fi
  if [[ -f "$SECURE_SITE_NGINX_ACTIVE_CONF" ]]; then
    domain_conf="$SECURE_SITE_NGINX_ACTIVE_CONF"
  else
    domain_conf="$SECURE_SITE_NGINX_PAUSED_CONF"
  fi
  reject_count="$(grep -Fhc 'return 444;' "$SECURE_SITE_NGINX_CONF" "$domain_conf" 2>/dev/null | awk '{total += $1} END {print total + 0}')"
  if secure_site_nginx_files_are_managed && grep -Fq 'access_log off;' "$SECURE_SITE_NGINX_CONF" && \
     grep -Fq 'listen 443 ssl http2 default_server;' "$SECURE_SITE_NGINX_CONF" && \
     grep -Fq 'listen 443 ssl http2;' "$domain_conf" && \
     grep -Fq 'DMITBOX_LOCAL_TLS_SITE' "$domain_conf" && \
     grep -Fq 'DMITBOX_PUBLIC_TLS_SITE' "$domain_conf" && \
     grep -Eq 'DMITBOX_(STRICT|CERT)_SNI_REJECT' "$SECURE_SITE_NGINX_CONF" && \
     grep -Fq 'DMITBOX_IP_LITERAL_REJECT' "$SECURE_SITE_NGINX_CONF" && \
     grep -Fq 'Content-Security-Policy' "$domain_conf" && \
     is_uint_in_range "$reject_count" 2 99; then
    ok "公网 HTTPS、SNI 拒绝、IP 访问拒绝、限流与安全响应头均已配置"
  else
    warn "Nginx 安全配置不完整，建议执行安装/修复"
  fi

  menu_section "关联服务联动"
  if [[ "$linked_enabled" == "1" ]]; then
    if ! secure_site_linked_service_exists "$linked_service"; then
      warn "关联服务 ${linked_service}.service 已不存在，自动停复无法保证"
    elif [[ "$site_state" == "PAUSED" ]]; then
      if secure_site_linked_service_running "$linked_service"; then
        warn "网站已暂停，但关联服务仍在运行，存在继续转发流量的风险"
      else
        ok "关联服务已停止，其全部监听端口和现有连接均已切断"
      fi
    elif secure_site_linked_service_running "$linked_service"; then
      ok "关联服务正在运行，恢复状态正常"
    else
      warn "网站已开放，但关联服务未恢复运行"
    fi
  else
    warn "未配置关联服务联动，只停止 Nginx 无法保护其他独立监听端口"
  fi

  menu_section "证书与 TLS"
  if secure_site_certificate_valid "$domain"; then
    ok "证书有效期超过 7 天且域名匹配"
  else
    warn "证书缺失、域名不匹配或将在 7 天内到期"
  fi
  if have_cmd openssl && [[ -s "/etc/letsencrypt/live/${domain}/fullchain.pem" ]]; then
    openssl x509 -in "/etc/letsencrypt/live/${domain}/fullchain.pem" -noout -subject -issuer -dates 2>/dev/null || true
  fi
  secure_site_https_health "$domain" >/dev/null 2>&1 || health_rc=$?
  if [[ "$site_state" == "PAUSED" ]]; then
    case "$health_rc" in
      0) warn "网站显示已暂停，但仍能通过本机 443 访问，建议立即修复" ;;
      2) info "当前系统没有 curl，跳过停站验证" ;;
      *) ok "整个域名站点已停止，本机 443 也无法访问该网站" ;;
    esac
  else
    case "$health_rc" in
      0) ok "本机 127.0.0.1:${SECURE_SITE_HTTPS_PORT} 的 TLS 1.3 与网站健康检查通过" ;;
      2) info "当前系统没有 curl，跳过请求级健康检查" ;;
      *) warn "HTTPS 健康检查失败" ;;
    esac
  fi

  menu_section "提醒"
  info "域名直连时网站正常开放；检测到 Cloudflare 后会停止并禁用整个 Nginx 服务"
  if [[ "$linked_enabled" == "1" ]]; then
    info "停站时也会停止 ${linked_service}.service，其所有端口和现有连接立即中断"
  else
    warn "未配置关联服务联动，其他独立监听端口不受保护"
  fi
  info "停站时源站 TCP/80、TCP/443 停止监听，本机 127.0.0.1:${SECURE_SITE_HTTPS_PORT} 也不可访问"
  info "去掉 Cloudflare 后，待本机 DNS 恢复原始直连地址，监测器通常在 1 分钟内恢复全部关联服务"
  warn "整服务停复仅适用于本机没有其他 Nginx 网站的情况"
  warn "关联服务中的其他功能也会一起停止"
  warn "应用层限流不能阻止网络层攻击，也无法避免入站线路计费"
}

secure_site_install_or_update_legacy_autostop_unused() {
  local domain="" email="" template="4" existing_domain=""
  local request_rate="" connection_limit="" conflict="" rollback="" selected_template=""
  local health_rc="0" ip_server_names="" dns_baseline=""
  local sni_reject_mode="certificate" guard_enabled="1"
  local linked_enabled="0" linked_service="" linked_boot_enabled="1"

  secure_site_select_nginx_paths

  if [[ -e "$SECURE_SITE_CONF" ]] && ! secure_site_conf_is_managed; then
    warn "${SECURE_SITE_CONF} 不是本脚本创建的文件，拒绝覆盖"
    return 1
  fi
  if [[ -e "$SECURE_SITE_NGINX_CONF" || -e "$SECURE_SITE_NGINX_LIMIT_CONF" || \
        -e "$SECURE_SITE_NGINX_ACTIVE_CONF" || -e "$SECURE_SITE_NGINX_PAUSED_CONF" ]] && \
     ! secure_site_nginx_files_are_managed; then
    warn "发现同名但非本脚本管理的 Nginx 配置，拒绝覆盖"
    return 1
  fi
  if ! secure_site_aux_files_are_managed_or_absent; then
    warn "发现同名但非本脚本管理的 DNS 监测文件，拒绝覆盖"
    return 1
  fi
  if secure_site_conf_is_managed; then
    existing_domain="$(secure_site_conf_value DOMAIN)"
    template="$(secure_site_conf_value TEMPLATE 2>/dev/null || echo 4)"
    guard_enabled="$(secure_site_conf_value CDN_GUARD_ENABLED 2>/dev/null || true)"
    guard_enabled="${guard_enabled:-1}"
    linked_enabled="$(secure_site_conf_value LINKED_SERVICE_ENABLED 2>/dev/null || true)"
    linked_service="$(secure_site_conf_value LINKED_SERVICE_NAME 2>/dev/null || true)"
    linked_boot_enabled="$(secure_site_conf_value LINKED_SERVICE_BOOT_ENABLED 2>/dev/null || true)"
    linked_enabled="${linked_enabled:-0}"
    linked_boot_enabled="${linked_boot_enabled:-1}"
  fi

  menu_header "轻量建站" "域名直连 443 · Cloudflare 自动停复站 · Let's Encrypt"
  warn "域名不能经过 CDN 或代理，全部 A/AAAA 记录必须直接指向本机"
  info "安装完成后可直接通过 https://域名 访问，使用公网 TCP/443"
  info "网站本身可通过本机 127.0.0.1:${SECURE_SITE_HTTPS_PORT} 访问，无需额外本机端口"
  info "检测到 Cloudflare 后自动停止并锁定网站与可选关联服务；恢复直连后自动启用"
  warn "自动停复仅适用于本机没有其他 Nginx 网站的情况"
  info "安装时可选择一个关联系统服务，切断其任意监听端口及现有连接"
  warn "网站级限制不能替代服务器供应商的网络层攻击防护"
  read_tty domain "输入网站域名（如 site.example.com）> " "$existing_domain"
  domain="${domain,,}"
  valid_domain_name "$domain" || { warn "域名格式无效，只支持 ASCII/Punycode 完整域名"; return 1; }
  if [[ -n "$existing_domain" && "$domain" != "$existing_domain" ]]; then
    warn "已安装域名为 ${existing_domain}；为避免误改证书，请先安全移除后再换域名"
    return 1
  fi
  read_tty email "Let's Encrypt 邮箱（可留空）> " ""
  valid_email_address "$email" || { warn "邮箱格式无效"; return 1; }
  echo "  1) 经典蓝（推荐）"
  echo "  2) 清新绿"
  echo "  3) 暖橙色"
  echo "  4) 随机配色（默认）"
  read_tty template "选择导航配色 > " "$template"
  [[ "$template" =~ ^[1-4]$ ]] || { warn "模板选项无效"; return 1; }
  menu_section "安装前检查"
  if secure_site_domain_uses_cloudflare "$domain"; then
    warn "当前域名已解析到 Cloudflare，安装前请先关闭代理并等待 DNS 恢复直连"
    return 1
  fi
  secure_site_dns_audit "$domain" || return 1
  dns_baseline="$(secure_site_dns_baseline "$domain")"
  [[ -n "$dns_baseline" ]] || { warn "无法保存 DNS 安装基线"; return 1; }
  ip_server_names="$(secure_site_ip_server_names "$domain")"
  secure_site_check_web_ports || return 1
  conflict="$(secure_site_find_conflict_domain "$domain" || true)"
  [[ -z "$conflict" ]] || { warn "域名已出现在其他 Nginx 配置中：${conflict}"; return 1; }
  print_kv "HTTPS 监听" "公网 TCP/443"
  print_kv "本机网站入口" "127.0.0.1:${SECURE_SITE_HTTPS_PORT}"
  print_kv "自动监测域名" "$domain"
  print_kv "代理命中动作" "停止并禁用网站服务"

  if [[ "$guard_enabled" == "1" ]]; then
    secure_site_choose_linked_service "$domain" "$linked_enabled" "$linked_service" "$linked_boot_enabled" || return 1
    linked_enabled="$SECURE_SITE_SELECTED_LINKED_ENABLED"
    linked_service="$SECURE_SITE_SELECTED_LINKED_NAME"
    linked_boot_enabled="$SECURE_SITE_SELECTED_LINKED_BOOT"
  fi

  request_rate="$(secure_site_conf_value REQUEST_RATE 2>/dev/null || random_uint_between 7 13)"
  connection_limit="$(secure_site_conf_value CONNECTION_LIMIT 2>/dev/null || random_uint_between 12 24)"
  is_uint_in_range "$request_rate" 1 100 || request_rate="$(random_uint_between 7 13)"
  is_uint_in_range "$connection_limit" 1 1000 || connection_limit="$(random_uint_between 12 24)"

  echo
  warn "将安装或使用 Nginx 与 Certbot，并放行公网 TCP/80、TCP/443"
  if [[ "$guard_enabled" == "1" ]]; then
    if [[ "$linked_enabled" == "1" ]]; then
      warn "域名命中 Cloudflare 后会停止网站服务及关联服务，恢复直连后自动启动"
    else
      warn "域名命中 Cloudflare 后只会停止网站服务，其他独立监听端口不受保护"
    fi
  fi
  confirm_word "SITE" "确认请输入 SITE > " || { warn "已取消"; return 0; }

  pkg_install nginx certbot curl openssl python3
  have_cmd nginx || { warn "Nginx 安装失败"; return 1; }
  have_cmd certbot || { warn "Certbot 安装失败，请确认软件源已启用"; return 1; }
  have_cmd curl || { warn "curl 安装失败"; return 1; }
  if [[ "$guard_enabled" == "1" ]]; then
    have_cmd python3 || { warn "缺少 Python 3，无法可靠识别 Cloudflare 地址"; return 1; }
  fi
  secure_site_select_nginx_paths
  secure_site_check_web_ports || return 1
  if [[ "$guard_enabled" == "1" ]]; then
    secure_site_assert_nginx_exclusive || return 1
  fi
  if secure_site_nginx_supports_ssl_reject_handshake; then
    sni_reject_mode="strict"
  else
    sni_reject_mode="certificate"
    warn "当前 Nginx 版本不支持握手阶段拒绝，将使用兼容关闭规则"
  fi

  rollback="$(secure_site_prepare_rollback)" || { warn "创建回滚备份失败"; return 1; }
  ensure_dir "$(dirname "$SECURE_SITE_NGINX_CONF")" || {
    warn "无法创建 Nginx 配置目录，正在回滚"
    secure_site_restore_rollback "$rollback"
    return 1
  }
  selected_template="$(secure_site_generate_homepage "$domain" "$template")" || {
    warn "生成静态首页失败，正在回滚"
    secure_site_restore_rollback "$rollback"
    return 1
  }
  if ! secure_site_write_limit_conf "$request_rate" || \
     ! secure_site_write_nginx_http_conf "$domain" "$request_rate" "$connection_limit" "$ip_server_names"; then
    warn "写入 Nginx HTTP 配置失败，正在回滚"
    secure_site_restore_rollback "$rollback"
    return 1
  fi
  if ! secure_site_nginx_config_loaded; then
    warn "Nginx 主配置没有加载 ${SECURE_SITE_NGINX_CONF}，正在回滚"
    secure_site_restore_rollback "$rollback"
    return 1
  fi
  if ! secure_site_nginx_reload; then
    warn "Nginx HTTP 配置失败，正在回滚"
    nginx -t 2>&1 | tail -n 30 || true
    secure_site_restore_rollback "$rollback"
    return 1
  fi
  firewall_open_port_best_effort 80 || true
  firewall_open_port_best_effort 443 || true

  if secure_site_certificate_valid "$domain"; then
    info "检测到可用证书，直接复用"
  elif ! secure_site_issue_certificate "$domain" "$email"; then
    warn "证书申请失败，正在回滚站点配置"
    secure_site_restore_rollback "$rollback"
    return 1
  fi
  secure_site_certificate_valid "$domain" || {
    warn "证书文件无效、域名不匹配或有效期不足，正在回滚"
    secure_site_restore_rollback "$rollback"
    return 1
  }

  if ! secure_site_write_nginx_full_conf "$domain" "$request_rate" "$connection_limit" \
    "$ip_server_names" "$sni_reject_mode"; then
    warn "写入 Nginx 公网 HTTPS 配置失败，正在回滚"
    secure_site_restore_rollback "$rollback"
    return 1
  fi
  if ! secure_site_nginx_config_loaded; then
    warn "Nginx 主配置没有加载公网 HTTPS 站点，正在回滚"
    secure_site_restore_rollback "$rollback"
    return 1
  fi
  if ! secure_site_nginx_reload; then
    warn "Nginx 公网 HTTPS 配置失败，正在回滚"
    nginx -t 2>&1 | tail -n 30 || true
    secure_site_restore_rollback "$rollback"
    return 1
  fi

  secure_site_https_health "$domain" >/dev/null 2>&1 || health_rc=$?
  if [[ "$health_rc" -eq 1 ]]; then
    warn "本机 443 网站健康检查失败，正在回滚"
    secure_site_restore_rollback "$rollback"
    return 1
  elif [[ "$health_rc" -eq 2 ]]; then
    warn "当前系统没有 curl，已跳过请求级健康检查"
  fi

  if ! secure_site_write_managed_conf "$domain" "$selected_template" \
    "$request_rate" "$connection_limit" "$dns_baseline" "$sni_reject_mode" "$guard_enabled" \
    "$linked_enabled" "$linked_service" "$linked_boot_enabled"; then
    warn "保存管理配置失败，正在回滚"
    secure_site_restore_rollback "$rollback"
    return 1
  fi
  if ! secure_site_setup_dns_watch; then
    warn "DNS/CDN 变化监测配置失败，正在回滚"
    secure_site_restore_rollback "$rollback"
    return 1
  fi
  if [[ "$guard_enabled" == "1" ]]; then
    if ! grep -Fxq 'GUARD_STATE=OPEN' "$SECURE_SITE_DNS_STATUS" 2>/dev/null || \
       ! grep -Fxq 'SITE_STATE=ACTIVE' "$SECURE_SITE_DNS_STATUS" 2>/dev/null || \
       ! grep -Fxq 'NGINX_STATE=RUNNING' "$SECURE_SITE_DNS_STATUS" 2>/dev/null || \
       ! grep -Fxq 'GUARD_BACKEND=service-interlock-v2' "$SECURE_SITE_DNS_STATUS" 2>/dev/null || \
       { [[ "$linked_enabled" == "1" ]] && ! grep -Fxq 'LINKED_SERVICE_STATE=RUNNING' "$SECURE_SITE_DNS_STATUS" 2>/dev/null; }; then
      warn "Cloudflare 自动停复站初始化失败，正在回滚"
      secure_site_restore_rollback "$rollback"
      return 1
    fi
  fi
  secure_site_guard_remove_firewall_rules >/dev/null 2>&1 || warn "旧版防火墙规则清理不完整，请进入代理保护菜单修复"
  secure_site_setup_cert_renewal || warn "自动续期调度设置不完整，请定期执行 certbot renew"
  ensure_dir "$SECURE_SITE_BACKUP_DIR" || warn "无法创建长期备份目录：${SECURE_SITE_BACKUP_DIR}"
  cp -a "$SECURE_SITE_CONF" "${SECURE_SITE_BACKUP_DIR}/site-conf-$(ts_now)" 2>/dev/null || true
  secure_site_cleanup_rollback "$rollback" || true

  ok "轻量网站已部署完成"
  ok "访问地址：https://${domain}"
  ok "HTTPS 已直接监听公网 TCP/443"
  ok "本机网站入口：127.0.0.1:${SECURE_SITE_HTTPS_PORT}"
  if [[ "$guard_enabled" == "1" ]]; then
    info "已启用严格 SNI、限流、安全响应头及每分钟 Cloudflare 自动停复站"
  else
    warn "域名代理自动保护当前未启用，可从管理菜单重新开启"
  fi
  echo
  secure_site_show_info
}

secure_site_regenerate_homepage() {
  secure_site_conf_is_managed || { warn "尚未使用轻量建站"; return 1; }
  local domain="" template="4" selected="" backup=""
  domain="$(secure_site_conf_value DOMAIN)"
  echo "  1) 经典蓝（推荐）"
  echo "  2) 清新绿"
  echo "  3) 暖橙色"
  echo "  4) 随机配色（默认）"
  read_tty template "选择导航配色 > " "4"
  [[ "$template" =~ ^[1-4]$ ]] || { warn "模板选项无效"; return 1; }
  ensure_dir "$SECURE_SITE_BACKUP_DIR" || { warn "无法创建首页备份目录"; return 1; }
  backup="${SECURE_SITE_BACKUP_DIR}/site-$(ts_now)"
  if [[ -d "$SECURE_SITE_ROOT" ]]; then
    cp -a "$SECURE_SITE_ROOT" "$backup" || { warn "旧站点备份失败"; return 1; }
  fi
  selected="$(secure_site_generate_homepage "$domain" "$template")" || {
    if [[ -d "$backup" ]]; then
      rm -rf -- "$SECURE_SITE_ROOT"
      cp -a "$backup" "$SECURE_SITE_ROOT" || true
    fi
    warn "首页生成失败，已恢复备份"
    return 1
  }
  secure_site_conf_set TEMPLATE "$selected" || true
  secure_site_conf_set UPDATED_AT "$(date -Is)" || true
  ok "静态首页已重新生成（模板 ${selected}）"
}

secure_site_renew_certificate_legacy_autostop_unused() {
  secure_site_conf_is_managed || { warn "尚未使用轻量建站"; return 1; }
  local domain="" site_state=""
  domain="$(secure_site_conf_value DOMAIN)"
  if [[ -x "$SECURE_SITE_DNS_WATCH" ]]; then
    "$SECURE_SITE_DNS_WATCH" >/dev/null 2>&1 || true
    site_state="$(awk -F= '$1 == "SITE_STATE" {print $2; exit}' "$SECURE_SITE_DNS_STATUS" 2>/dev/null || true)"
  fi
  if [[ "$site_state" == "PAUSED" ]]; then
    warn "当前检测到 Cloudflare，Nginx 已自动停止；恢复直连并自动复站后再检查证书续期"
    return 1
  fi
  if ! secure_site_dns_audit "$domain"; then
    warn "DNS 已发生变化，将继续尝试现有的证书验证路径"
  fi
  secure_site_check_web_ports || return 1
  have_cmd certbot || { warn "Certbot 不存在"; return 1; }
  if ! run_with_spinner "检查并续期 ${domain} 证书" certbot renew --cert-name "$domain"; then
    warn "证书续期失败"
    return 1
  fi
  secure_site_nginx_reload || { warn "证书检查完成，但 Nginx 重载失败"; return 1; }
  if have_cmd openssl && [[ -s "/etc/letsencrypt/live/${domain}/fullchain.pem" ]]; then
    openssl x509 -in "/etc/letsencrypt/live/${domain}/fullchain.pem" -noout -dates 2>/dev/null || true
  fi
  ok "证书续期检查完成（未到期时 Certbot 不会强制申请）"
}

secure_site_cdn_guard_enable() {
  secure_site_conf_is_managed || { warn "请先安装轻量网站"; return 1; }
  secure_site_select_nginx_paths
  secure_site_nginx_files_are_managed || { warn "网站配置不完整，请先执行安装/修复"; return 1; }
  local domain="" current_baseline="" new_baseline="" old_baseline="" rollback=""
  local request_rate="" connection_limit="" sni_reject_mode="" ip_server_names=""
  local linked_enabled="0" linked_service="" linked_boot_enabled="1"
  domain="$(secure_site_conf_value DOMAIN)"
  old_baseline="$(secure_site_conf_value DNS_BASELINE 2>/dev/null || true)"
  [[ -n "$old_baseline" ]] || old_baseline="$(secure_site_conf_value CDN_GUARD_BASELINE 2>/dev/null || true)"
  linked_enabled="$(secure_site_conf_value LINKED_SERVICE_ENABLED 2>/dev/null || true)"
  linked_service="$(secure_site_conf_value LINKED_SERVICE_NAME 2>/dev/null || true)"
  linked_boot_enabled="$(secure_site_conf_value LINKED_SERVICE_BOOT_ENABLED 2>/dev/null || true)"
  linked_enabled="${linked_enabled:-0}"
  linked_boot_enabled="${linked_boot_enabled:-1}"

  pkg_install python3
  have_cmd python3 || { warn "缺少 Python 3，无法可靠识别 Cloudflare 地址"; return 1; }
  secure_site_assert_nginx_exclusive || return 1
  current_baseline="$(secure_site_dns_baseline "$domain")"
  [[ -n "$current_baseline" ]] || { warn "当前无法解析网站域名"; return 1; }
  if secure_site_domain_uses_cloudflare "$domain"; then
    new_baseline="$old_baseline"
    [[ -n "$new_baseline" ]] || {
      warn "当前已使用 Cloudflare，但没有安装时的原始直连基线，无法安全配置自动恢复"
      return 1
    }
    warn "当前已检测到 Cloudflare；启用后会立即停止并禁用网站及关联服务"
  else
    secure_site_dns_audit "$domain" || return 1
    new_baseline="$current_baseline"
    info "当前域名直连本机，将此解析结果保存为自动恢复基线"
  fi

  secure_site_choose_linked_service "$domain" "$linked_enabled" "$linked_service" "$linked_boot_enabled" || return 1
  linked_enabled="$SECURE_SITE_SELECTED_LINKED_ENABLED"
  linked_service="$SECURE_SITE_SELECTED_LINKED_NAME"
  linked_boot_enabled="$SECURE_SITE_SELECTED_LINKED_BOOT"

  info "命中 Cloudflare：停止并禁用整个 Nginx，源站 80/443 不再监听"
  if [[ "$linked_enabled" == "1" ]]; then
    info "同时停止并锁定 ${linked_service}.service，切断其所有端口和现有连接"
  else
    warn "未关联独立服务，其监听端口仍可能继续转发流量"
  fi
  info "恢复原始直连：本机 DNS 看到安装基线后，通常 1 分钟内自动恢复全部关联服务"
  warn "此方式会影响整个 Nginx，仅适用于本机没有其他 Nginx 网站的情况"
  warn "关联后整个服务都会停复；同一服务内的其他功能也会受影响"
  confirm_word "GUARD" "确认启用请输入 GUARD > " || { warn "已取消"; return 0; }

  rollback="$(secure_site_prepare_rollback)" || { warn "创建回滚备份失败"; return 1; }
  request_rate="$(secure_site_conf_value REQUEST_RATE 2>/dev/null || echo 10)"
  connection_limit="$(secure_site_conf_value CONNECTION_LIMIT 2>/dev/null || echo 20)"
  sni_reject_mode="$(secure_site_conf_value SNI_REJECT_MODE 2>/dev/null || echo strict)"
  is_uint_in_range "$request_rate" 1 100 || request_rate=10
  is_uint_in_range "$connection_limit" 1 1000 || connection_limit=20
  [[ "$sni_reject_mode" == "strict" || "$sni_reject_mode" == "certificate" ]] || sni_reject_mode=strict
  ip_server_names="$(secure_site_ip_server_names "$domain")"

  if ! secure_site_guard_remove_firewall_rules || \
     ! secure_site_write_nginx_full_conf "$domain" "$request_rate" "$connection_limit" \
       "$ip_server_names" "$sni_reject_mode" || \
     ! secure_site_conf_set DNS_BASELINE "$new_baseline" || \
     ! secure_site_conf_set CDN_GUARD_DOMAIN "$domain" || \
     ! secure_site_conf_set CDN_GUARD_BASELINE "$new_baseline" || \
     ! secure_site_conf_set CDN_GUARD_ACTION stop_services || \
     ! secure_site_conf_set CDN_GUARD_AUTO_RESUME 1 || \
     ! secure_site_conf_set LOCAL_HTTPS_ENDPOINT "127.0.0.1:${SECURE_SITE_HTTPS_PORT}" || \
     ! secure_site_conf_set LINKED_SERVICE_ENABLED "$linked_enabled" || \
     ! secure_site_conf_set LINKED_SERVICE_NAME "$linked_service" || \
     ! secure_site_conf_set LINKED_SERVICE_BOOT_ENABLED "$linked_boot_enabled" || \
     ! secure_site_conf_set CDN_GUARD_ENABLED 1 || \
     ! secure_site_conf_unset CDN_GUARD_PORT || \
     ! secure_site_conf_unset CDN_GUARD_PORTS || \
     ! secure_site_setup_dns_watch; then
    warn "自动停复站配置失败，正在恢复原设置"
    secure_site_restore_rollback "$rollback"
    return 1
  fi

  if secure_site_domain_uses_cloudflare "$domain"; then
    if ! grep -Fxq 'GUARD_STATE=LOCKED' "$SECURE_SITE_DNS_STATUS" || \
       ! grep -Fxq 'SITE_STATE=PAUSED' "$SECURE_SITE_DNS_STATUS" || \
       ! grep -Fxq 'NGINX_STATE=STOPPED' "$SECURE_SITE_DNS_STATUS" || \
       ! grep -Fxq 'GUARD_BACKEND=service-interlock-v2' "$SECURE_SITE_DNS_STATUS" || \
       { [[ "$linked_enabled" == "1" ]] && ! grep -Fxq 'LINKED_SERVICE_STATE=STOPPED' "$SECURE_SITE_DNS_STATUS"; }; then
      warn "检测到 Cloudflare，但网站或关联服务未能可靠停止，正在恢复原设置"
      secure_site_restore_rollback "$rollback"
      return 1
    fi
  elif ! grep -Fxq 'GUARD_STATE=OPEN' "$SECURE_SITE_DNS_STATUS" || \
       ! grep -Fxq 'SITE_STATE=ACTIVE' "$SECURE_SITE_DNS_STATUS" || \
       ! grep -Fxq 'NGINX_STATE=RUNNING' "$SECURE_SITE_DNS_STATUS" || \
       ! grep -Fxq 'GUARD_BACKEND=service-interlock-v2' "$SECURE_SITE_DNS_STATUS" || \
       { [[ "$linked_enabled" == "1" ]] && ! grep -Fxq 'LINKED_SERVICE_STATE=RUNNING' "$SECURE_SITE_DNS_STATUS"; }; then
    warn "网站或关联服务自动恢复状态校验失败，正在恢复原设置"
    secure_site_restore_rollback "$rollback"
    return 1
  fi

  secure_site_cleanup_rollback "$rollback" || true
  ok "Cloudflare 触发网站与关联服务自动停复已启用"
  secure_site_dns_watch_status || true
}

secure_site_cdn_guard_recheck() {
  secure_site_conf_is_managed || { warn "请先安装轻量网站"; return 1; }
  if [[ ! -x "$SECURE_SITE_DNS_WATCH" ]]; then
    secure_site_setup_dns_watch || { warn "监测程序修复失败"; return 1; }
  else
    "$SECURE_SITE_DNS_WATCH" --sync >/dev/null 2>&1 || { warn "立即检测失败"; return 1; }
  fi
  secure_site_dns_watch_status || true
}

secure_site_cdn_guard_disable() {
  secure_site_conf_is_managed || { warn "请先安装轻量网站"; return 1; }
  local old_enabled="" old_linked_enabled="0" linked_service="" cleanup_rc=0
  old_enabled="$(secure_site_conf_value CDN_GUARD_ENABLED 2>/dev/null || true)"
  old_enabled="${old_enabled:-0}"
  old_linked_enabled="$(secure_site_conf_value LINKED_SERVICE_ENABLED 2>/dev/null || true)"
  linked_service="$(secure_site_conf_value LINKED_SERVICE_NAME 2>/dev/null || true)"
  old_linked_enabled="${old_linked_enabled:-0}"
  warn "停用后会立即恢复网站及已关联服务，域名接入 Cloudflare 时不再自动停站"
  confirm_word "DISABLE" "确认停用请输入 DISABLE > " || { warn "已取消"; return 0; }
  if [[ "$old_linked_enabled" == "1" ]] && ! secure_site_linked_service_exists "$linked_service"; then
    warn "原关联服务 ${linked_service:-（空）} 已不存在，将解除失效联动后继续恢复网站"
    secure_site_conf_set LINKED_SERVICE_ENABLED 0 || return 1
  fi
  secure_site_conf_set CDN_GUARD_ENABLED 0 || return 1
  if [[ -x "$SECURE_SITE_DNS_WATCH" ]]; then
    "$SECURE_SITE_DNS_WATCH" --force-active >/dev/null 2>&1 || cleanup_rc=1
  else
    secure_site_setup_dns_watch >/dev/null 2>&1 || cleanup_rc=1
  fi
  secure_site_guard_remove_firewall_rules || cleanup_rc=1
  if (( cleanup_rc != 0 )); then
    secure_site_conf_set CDN_GUARD_ENABLED "$old_enabled" || true
    secure_site_conf_set LINKED_SERVICE_ENABLED "$old_linked_enabled" || true
    "$SECURE_SITE_DNS_WATCH" >/dev/null 2>&1 || true
    warn "恢复网站或清理旧规则失败，已恢复原设置"
    return 1
  fi
  ok "Cloudflare 自动停复站已停用，网站及原关联服务已恢复开放"
}

secure_site_cdn_guard_menu_legacy_autostop_unused() {
  while true; do
    menu_header "域名代理保护" "Cloudflare 服务熔断 · 直连自动恢复 · 无需手动"
    if secure_site_conf_is_managed; then
      secure_site_dns_watch_status || true
    else
      warn "请先安装轻量网站"
    fi
    menu_section "管理"
    menu_item "1" "设置或修复自动停复站" "联动网站与一个独立服务，切断全部监听端口"
    menu_item "2" "立即重新检测" "不等待定时任务，立刻同步当前网站状态"
    menu_item "3" "停用自动停复站" "立即恢复网站及已关联服务"
    menu_back_item
    local c=""
    read_tty c "请输入编号 > " ""
    case "$c" in
      1) secure_site_cdn_guard_enable || true; pause_up ;;
      2) secure_site_cdn_guard_recheck || true; pause_up ;;
      3) secure_site_cdn_guard_disable || true; pause_up ;;
      0|q|Q) return 0 ;;
      *) warn "无效选项"; pause_up ;;
    esac
  done
}

secure_site_remove_site_legacy_autostop_unused() {
  secure_site_conf_is_managed || { warn "尚未使用脚本的轻量建站"; return 1; }
  secure_site_nginx_files_are_managed || { warn "Nginx 文件已被人工修改或归属不明，拒绝自动删除"; return 1; }
  secure_site_aux_files_are_managed_or_absent || { warn "DNS 监测文件已被人工修改或归属不明，拒绝自动删除"; return 1; }
  local domain="" rollback="" backup_dir="" backup_tmp="" guard_cleanup_rc=0
  local linked_enabled="0" linked_service=""
  domain="$(secure_site_conf_value DOMAIN)"
  linked_enabled="$(secure_site_conf_value LINKED_SERVICE_ENABLED 2>/dev/null || true)"
  linked_service="$(secure_site_conf_value LINKED_SERVICE_NAME 2>/dev/null || true)"
  linked_enabled="${linked_enabled:-0}"
  warn "移除后 https://${domain} 将停止访问，请先确认没有其他服务依赖该站点"
  warn "不会卸载 Nginx/Certbot，也不会删除 Let's Encrypt 证书"
  confirm_word "REMOVE" "确认移除网站请输入 REMOVE > " || { warn "已取消"; return 0; }

  rollback="$(secure_site_prepare_rollback)" || { warn "创建回滚备份失败"; return 1; }
  if ! ensure_dir "$SECURE_SITE_BACKUP_DIR" || \
     ! backup_tmp="$(mktemp -d "${SECURE_SITE_BACKUP_DIR}/.remove.XXXXXX")"; then
    warn "创建长期卸载备份失败，已取消"
    secure_site_cleanup_rollback "$rollback" || true
    return 1
  fi
  backup_dir="${SECURE_SITE_BACKUP_DIR}/removed-$(ts_now)-${backup_tmp##*.}"
  if ! cp -a "$SECURE_SITE_CONF" "$backup_tmp/management.conf" || \
     ! cp -a "$SECURE_SITE_NGINX_CONF" "$backup_tmp/nginx-site.conf" || \
     ! cp -a "$SECURE_SITE_NGINX_LIMIT_CONF" "$backup_tmp/nginx-limits.conf"; then
    warn "创建长期卸载备份失败，已取消"
    [[ "$backup_tmp" == "${SECURE_SITE_BACKUP_DIR}/.remove."* ]] && rm -rf -- "$backup_tmp"
    secure_site_cleanup_rollback "$rollback" || true
    return 1
  fi
  if [[ -e "$SECURE_SITE_NGINX_ACTIVE_CONF" ]]; then
    cp -a "$SECURE_SITE_NGINX_ACTIVE_CONF" "$backup_tmp/nginx-domain-active.conf" || {
      warn "备份活动站点配置失败，已取消"
      [[ "$backup_tmp" == "${SECURE_SITE_BACKUP_DIR}/.remove."* ]] && rm -rf -- "$backup_tmp"
      secure_site_cleanup_rollback "$rollback" || true
      return 1
    }
  elif [[ -e "$SECURE_SITE_NGINX_PAUSED_CONF" ]]; then
    cp -a "$SECURE_SITE_NGINX_PAUSED_CONF" "$backup_tmp/nginx-domain-paused.conf" || {
      warn "备份暂停站点配置失败，已取消"
      [[ "$backup_tmp" == "${SECURE_SITE_BACKUP_DIR}/.remove."* ]] && rm -rf -- "$backup_tmp"
      secure_site_cleanup_rollback "$rollback" || true
      return 1
    }
  fi
  if [[ -d "$SECURE_SITE_ROOT" ]]; then
    if ! cp -a "$SECURE_SITE_ROOT" "$backup_tmp/site-root"; then
      warn "备份静态站点失败，已取消"
      [[ "$backup_tmp" == "${SECURE_SITE_BACKUP_DIR}/.remove."* ]] && rm -rf -- "$backup_tmp"
      secure_site_cleanup_rollback "$rollback" || true
      return 1
    fi
  fi
  if [[ -e "$SECURE_SITE_DNS_STATUS" ]] && \
     ! cp -a "$SECURE_SITE_DNS_STATUS" "$backup_tmp/dns-status.conf"; then
    warn "备份 DNS 监测状态失败，已取消"
    [[ "$backup_tmp" == "${SECURE_SITE_BACKUP_DIR}/.remove."* ]] && rm -rf -- "$backup_tmp"
    secure_site_cleanup_rollback "$rollback" || true
    return 1
  fi
  if ! mv -- "$backup_tmp" "$backup_dir"; then
    warn "完成长期卸载备份失败，已取消"
    [[ "$backup_tmp" == "${SECURE_SITE_BACKUP_DIR}/.remove."* ]] && rm -rf -- "$backup_tmp"
    secure_site_cleanup_rollback "$rollback" || true
    return 1
  fi

  if [[ "$linked_enabled" == "1" ]] && ! secure_site_linked_service_exists "$linked_service"; then
    warn "原关联服务 ${linked_service:-（空）} 已不存在，将解除失效联动后继续移除网站"
    secure_site_conf_set LINKED_SERVICE_ENABLED 0 || guard_cleanup_rc=1
  fi
  if (( guard_cleanup_rc == 0 )) && [[ -x "$SECURE_SITE_DNS_WATCH" ]]; then
    "$SECURE_SITE_DNS_WATCH" --force-active >/dev/null 2>&1 || guard_cleanup_rc=1
  fi
  secure_site_guard_remove_firewall_rules || guard_cleanup_rc=1
  if (( guard_cleanup_rc != 0 )); then
    warn "恢复网站或清理旧版规则失败，正在回滚"
    secure_site_restore_rollback "$rollback"
    return 1
  fi
  secure_site_remove_dns_watch_schedule

  rm -f "$SECURE_SITE_NGINX_CONF" "$SECURE_SITE_NGINX_LIMIT_CONF" \
    "$SECURE_SITE_NGINX_ACTIVE_CONF" "$SECURE_SITE_NGINX_PAUSED_CONF" >/dev/null 2>&1 || true
  if have_cmd nginx; then
    if ! nginx -t >/dev/null 2>&1; then
      warn "移除后 Nginx 校验失败，正在回滚"
      nginx -t 2>&1 | tail -n 30 || true
      secure_site_restore_rollback "$rollback"
      return 1
    fi
    if ! secure_site_nginx_reload; then
      warn "Nginx 重载失败，正在回滚"
      secure_site_restore_rollback "$rollback"
      return 1
    fi
  else
    info "当前未安装 Nginx，无需重载服务"
  fi
  if ! rm -rf -- "$SECURE_SITE_ROOT" || \
     ! rm -f "$SECURE_SITE_CONF" "$SECURE_SITE_CERT_HOOK" "$SECURE_SITE_CERT_CRON" \
       "$SECURE_SITE_CERT_PERIODIC" "$SECURE_SITE_DNS_WATCH" \
       "$SECURE_SITE_DNS_WATCH_CRON" "$SECURE_SITE_DNS_WATCH_PERIODIC" \
       "$SECURE_SITE_DNS_WATCH_SERVICE" "$SECURE_SITE_DNS_WATCH_TIMER" \
       "$SECURE_SITE_DNS_STATUS" "${SECURE_SITE_DNS_STATUS}.lock"; then
    warn "删除脚本管理文件失败，正在回滚"
    secure_site_restore_rollback "$rollback"
    return 1
  fi
  secure_site_cleanup_rollback "$rollback" || true
  ok "轻量网站已移除"
  info "证书仍保留在 /etc/letsencrypt/live/${domain}，备份位于 ${backup_dir}"
  info "自动停复站与旧版防火墙规则已清理；TCP/80 与 TCP/443 原有放行规则予以保留"
}

# ======================================================================
# Secure-site v20: persistent local-origin lock
#
# Public DNS may later point at a CDN, but local programs continue to
# resolve the managed domain to this Nginx instance through /etc/hosts.
# The previous DNS watcher, whole-Nginx shutdown and linked-service
# interlock are retained above only so an installed r19 site can be
# recovered and migrated safely; none of them is enabled by v20.
# ======================================================================

secure_site_write_managed_conf() {
  local domain="$1" template="$2" request_rate="$3" connection_limit="$4"
  local dns_baseline="${5:-}" sni_reject_mode="${6:-certificate}" created=""
  [[ "$sni_reject_mode" == "strict" || "$sni_reject_mode" == "certificate" ]] || return 1
  [[ "$dns_baseline" != *$'\n'* ]] || return 1
  created="$(secure_site_conf_value CREATED_AT 2>/dev/null || true)"
  [[ -n "$created" ]] || created="$(date -Is)"
  write_file "$SECURE_SITE_CONF" "# managed by dmitbox.sh - secure static website
DOMAIN=${domain}
TEMPLATE=${template}
REQUEST_RATE=${request_rate}
CONNECTION_LIMIT=${connection_limit}
SITE_MODE=public_tls
HTTPS_PORT=443
LOCAL_HTTPS_ENDPOINT=127.0.0.1:${SECURE_SITE_HTTPS_PORT}
LOCAL_ORIGIN_LOCK=1
LOCAL_ORIGIN_ADDRESS=127.0.0.1
LOCAL_ORIGIN_HOSTS_TAG=${SECURE_SITE_HOSTS_TAG}
SNI_REJECT_MODE=${sni_reject_mode}
DNS_BASELINE=${dns_baseline}
PUBLIC_DNS_BASELINE=${dns_baseline}
FIREWALL_MODE=none
CREATED_AT=${created}
UPDATED_AT=$(date -Is)" || return 1
  chmod 600 "$SECURE_SITE_CONF"
}

secure_site_setup_dns_watch() {
  # v20 intentionally has no periodic stop/start task.  Keep this function as
  # a cleanup shim for upgrades and scripts that called the old repair entry.
  secure_site_remove_dns_watch_schedule
  rm -f "$SECURE_SITE_DNS_WATCH" "$SECURE_SITE_DNS_STATUS" \
    "${SECURE_SITE_DNS_STATUS}.lock" >/dev/null 2>&1 || true
}

secure_site_dns_watch_schedule_active() { return 1; }

secure_site_ip_server_names_from_baseline() {
  local baseline="${1:-}" value="" names="localhost 127.0.0.1"
  local IFS=','
  local -a addresses=()
  read -r -a addresses <<< "$baseline"
  for value in "${addresses[@]}"; do
    [[ "$value" =~ ^[0-9A-Fa-f:.]+$ ]] || continue
    names+=" ${value}"
  done
  printf '%s\n' "$names"
}

secure_site_public_dns_status() {
  local domain="$1" baseline="${2:-}" current="" cf_rc=1
  local -a addresses=()
  if ! have_cmd dig; then
    warn "缺少 dig，暂时无法核对公网 A/AAAA 记录"
    return 2
  fi
  mapfile -t addresses < <(secure_site_effective_dns_addresses "$domain")
  current="$(printf '%s\n' "${addresses[@]}" | awk 'NF' | sort -u | paste -sd, -)"
  print_kv "公网解析" "${current:-未解析}"
  [[ -n "$current" ]] || { warn "公网 DNS 当前没有可用的 A/AAAA 记录"; return 1; }
  secure_site_addresses_use_cloudflare "${addresses[@]}" && cf_rc=0 || cf_rc=$?
  if (( cf_rc == 0 )); then
    warn "公网 DNS 正在使用 Cloudflare 代理"
    ok "本机回源仍固定到 127.0.0.1，不会跟随 Cloudflare 地址变化"
  elif (( cf_rc == 2 )); then
    warn "缺少 Python 3，无法判断公网地址是否属于 Cloudflare"
  else
    ok "公网 DNS 未检测到 Cloudflare 地址"
  fi
  if [[ -n "$baseline" ]]; then
    if [[ "$current" == "$baseline" ]]; then
      ok "公网 DNS 与安装基线一致"
    else
      info "公网 DNS 与安装基线不同；这不会改变本机回源锁定"
      print_kv "安装基线" "$baseline"
    fi
  fi
  return "$cf_rc"
}

secure_site_legacy_guard_restore() {
  local linked_enabled="0" linked_service="" linked_boot="1" rc=0 legacy=0
  if secure_site_conf_is_managed; then
    linked_enabled="$(secure_site_conf_value LINKED_SERVICE_ENABLED 2>/dev/null || true)"
    linked_service="$(secure_site_conf_value LINKED_SERVICE_NAME 2>/dev/null || true)"
    linked_boot="$(secure_site_conf_value LINKED_SERVICE_BOOT_ENABLED 2>/dev/null || true)"
    [[ -n "$(secure_site_conf_value CDN_GUARD_ENABLED 2>/dev/null || true)" ]] && legacy=1
  fi
  [[ -e "$SECURE_SITE_NGINX_PAUSED_CONF" || -e "$SECURE_SITE_DNS_WATCH" ]] && legacy=1
  secure_site_legacy_firewall_present && legacy=1
  linked_enabled="${linked_enabled:-0}"
  linked_boot="${linked_boot:-1}"

  secure_site_remove_dns_watch_schedule
  if [[ -x "$SECURE_SITE_DNS_WATCH" && "$legacy" == "1" ]]; then
    if [[ "$linked_enabled" == "1" ]] && ! secure_site_linked_service_exists "$linked_service"; then
      secure_site_conf_set LINKED_SERVICE_ENABLED 0 >/dev/null 2>&1 || true
    fi
    secure_site_conf_set CDN_GUARD_ENABLED 0 >/dev/null 2>&1 || true
    "$SECURE_SITE_DNS_WATCH" --force-active >/dev/null 2>&1 || true
  fi

  if [[ -e "$SECURE_SITE_NGINX_ACTIVE_CONF" && -e "$SECURE_SITE_NGINX_PAUSED_CONF" ]]; then
    warn "活动与暂停的 Nginx 站点文件同时存在，拒绝猜测"
    rc=1
  elif [[ -f "$SECURE_SITE_NGINX_PAUSED_CONF" ]]; then
    mv -f "$SECURE_SITE_NGINX_PAUSED_CONF" "$SECURE_SITE_NGINX_ACTIVE_CONF" || rc=1
  fi

  if (( rc == 0 )) && secure_site_nginx_files_are_managed; then
    secure_site_nginx_reload >/dev/null 2>&1 || rc=1
  fi
  if [[ "$linked_enabled" == "1" ]] && secure_site_linked_service_exists "$linked_service"; then
    secure_site_linked_service_start_now "$linked_service" "$linked_boot" >/dev/null 2>&1 || \
      warn "原关联服务 ${linked_service}.service 未能自动恢复，请手动检查"
  fi

  rm -f "$SECURE_SITE_DNS_WATCH" "$SECURE_SITE_DNS_STATUS" \
    "${SECURE_SITE_DNS_STATUS}.lock" >/dev/null 2>&1 || rc=1
  secure_site_guard_remove_firewall_rules || rc=1
  return "$rc"
}

secure_site_migrate_legacy_site() {
  secure_site_conf_is_managed || return 0
  local lock="" domain="" template="4" request_rate="10" connection_limit="20"
  local sni_reject_mode="certificate" baseline="" rollback="" needs_migration=0
  lock="$(secure_site_conf_value LOCAL_ORIGIN_LOCK 2>/dev/null || true)"
  [[ "$lock" == "1" ]] || needs_migration=1
  [[ -e "$SECURE_SITE_DNS_WATCH" || -e "$SECURE_SITE_NGINX_PAUSED_CONF" ]] && needs_migration=1
  [[ -n "$(secure_site_conf_value CDN_GUARD_ENABLED 2>/dev/null || true)" ]] && needs_migration=1
  secure_site_legacy_firewall_present && needs_migration=1
  (( needs_migration == 1 )) || {
    secure_site_remove_dns_watch_schedule
    return 0
  }

  secure_site_aux_files_are_managed_or_absent || {
    warn "旧版监测文件存在但不属于本脚本，拒绝自动删除"
    return 1
  }
  have_cmd python3 || { warn "缺少 Python 3，无法迁移本机回源锁定"; return 1; }

  domain="$(secure_site_conf_value DOMAIN 2>/dev/null || true)"
  valid_domain_name "$domain" || { warn "旧站点域名无效，无法自动迁移"; return 1; }
  template="$(secure_site_conf_value TEMPLATE 2>/dev/null || echo 4)"
  request_rate="$(secure_site_conf_value REQUEST_RATE 2>/dev/null || echo 10)"
  connection_limit="$(secure_site_conf_value CONNECTION_LIMIT 2>/dev/null || echo 20)"
  sni_reject_mode="$(secure_site_conf_value SNI_REJECT_MODE 2>/dev/null || echo certificate)"
  baseline="$(secure_site_conf_value PUBLIC_DNS_BASELINE 2>/dev/null || true)"
  [[ -n "$baseline" ]] || baseline="$(secure_site_conf_value DNS_BASELINE 2>/dev/null || true)"
  [[ -n "$baseline" ]] || baseline="$(secure_site_conf_value CDN_GUARD_BASELINE 2>/dev/null || true)"
  [[ "$template" =~ ^[1-4]$ ]] || template=4
  is_uint_in_range "$request_rate" 1 100 || request_rate=10
  is_uint_in_range "$connection_limit" 1 1000 || connection_limit=20
  [[ "$sni_reject_mode" == "strict" || "$sni_reject_mode" == "certificate" ]] || sni_reject_mode=certificate

  rollback="$(secure_site_prepare_rollback)" || { warn "无法创建旧站点迁移回滚点"; return 1; }
  if ! secure_site_legacy_guard_restore || \
     ! secure_site_hosts_pin_apply "$domain" || \
     ! secure_site_write_managed_conf "$domain" "$template" "$request_rate" \
       "$connection_limit" "$baseline" "$sni_reject_mode"; then
    warn "旧版网站保护迁移失败，正在恢复原状态"
    secure_site_restore_rollback "$rollback"
    return 1
  fi
  secure_site_setup_dns_watch
  secure_site_cleanup_rollback "$rollback" || true
  ok "已将旧版自动停站迁移为本机回源锁定"
  info "Nginx 与原关联服务已恢复；旧版定时任务和专用防火墙规则已移除"
}

secure_site_dns_watch_status() {
  secure_site_conf_is_managed || return 1
  local domain="" baseline=""
  domain="$(secure_site_conf_value DOMAIN)"
  baseline="$(secure_site_conf_value PUBLIC_DNS_BASELINE 2>/dev/null || true)"
  [[ -n "$baseline" ]] || baseline="$(secure_site_conf_value DNS_BASELINE 2>/dev/null || true)"
  secure_site_public_dns_status "$domain" "$baseline"
}

secure_site_show_info() {
  menu_header "建站信息" "公网网站 · 本机回源 · 安全配置"
  secure_site_select_nginx_paths
  secure_site_conf_is_managed || { warn "尚未使用轻量建站"; return 1; }
  secure_site_migrate_legacy_site || return 1
  local domain="" template="" request_rate="" connection_limit="" sni_reject_mode="" baseline=""
  domain="$(secure_site_conf_value DOMAIN)"
  template="$(secure_site_conf_value TEMPLATE)"
  request_rate="$(secure_site_conf_value REQUEST_RATE)"
  connection_limit="$(secure_site_conf_value CONNECTION_LIMIT)"
  sni_reject_mode="$(secure_site_conf_value SNI_REJECT_MODE 2>/dev/null || echo certificate)"
  baseline="$(secure_site_conf_value PUBLIC_DNS_BASELINE 2>/dev/null || true)"

  menu_section "网站"
  print_kv "访问地址" "https://${domain}"
  print_kv "站点目录" "$SECURE_SITE_ROOT"
  print_kv "导航配色" "$template"
  print_kv "Nginx 配置" "$SECURE_SITE_NGINX_CONF"
  print_kv "HTTPS 端口" "公网 TCP/443"
  print_kv "本机回源" "${domain} → 127.0.0.1:443"
  print_kv "公网 DNS 基线" "${baseline:-未记录}"

  menu_section "安全措施"
  print_kv "请求速率" "${request_rate} 次/秒"
  print_kv "并发连接" "$connection_limit"
  print_kv "本机回源锁定" "已启用"
  print_kv "网站停站任务" "未启用"
  print_kv "脚本防火墙规则" "无"
  if [[ "$sni_reject_mode" == "strict" ]]; then
    info "未知 SNI 会在 TLS 握手阶段被拒绝"
  else
    info "未知 SNI 会由兼容规则立即关闭连接"
  fi
  info "HTTP/HTTPS 使用 IP 地址直接访问时不会返回网站内容"
  info "仅允许 GET/HEAD，未知路径返回 404；访问日志已关闭"
  info "已启用限流、连接上限、TLS 安全参数和浏览器安全响应头"
  info "公网 DNS 即使日后接入 Cloudflare，本机进程仍只会回源到 127.0.0.1"
  warn "本机回源锁定只影响使用系统域名解析的本机程序；已缓存旧 DNS 的程序应重启一次"
}

secure_site_site_status() {
  menu_header "轻量建站" "网站、回源锁定、DNS、端口与防火墙检查"
  secure_site_select_nginx_paths
  if ! secure_site_conf_is_managed; then
    warn "尚未安装"
    info "用途：生成无脚本 HTTPS 导航站，并将该域名的本机回源固定到 127.0.0.1:443"
    info "初次申请证书时，公网 A/AAAA 记录必须直接指向本机"
    info "安装后公网 DNS 可以变化，不会触发停站，也不会修改其他服务端口"
    return 0
  fi
  secure_site_migrate_legacy_site || return 1

  local domain="" baseline="" listener80="" listener443="" health_rc=0
  domain="$(secure_site_conf_value DOMAIN)"
  baseline="$(secure_site_conf_value PUBLIC_DNS_BASELINE 2>/dev/null || true)"
  [[ -n "$baseline" ]] || baseline="$(secure_site_conf_value DNS_BASELINE 2>/dev/null || true)"

  menu_section "配置"
  print_kv "域名" "$domain"
  print_kv "访问地址" "https://${domain}"
  print_kv "本机回源" "127.0.0.1:${SECURE_SITE_HTTPS_PORT}"
  if secure_site_hosts_pin_status "$domain"; then
    ok "本机解析已固定：${domain} → 127.0.0.1"
  else
    warn "本机回源锁定缺失或解析结果异常，请执行“本机回源与端口 → 修复回源锁定”"
  fi
  if [[ -e "$SECURE_SITE_DNS_WATCH" || -e "$SECURE_SITE_DNS_WATCH_CRON" || \
        -e "$SECURE_SITE_DNS_WATCH_SERVICE" || -e "$SECURE_SITE_DNS_WATCH_TIMER" ]]; then
    warn "仍有旧版自动停站任务残留，建议立即修复回源锁定"
  else
    ok "未启用 DNS 自动停站任务"
  fi

  menu_section "公网 DNS"
  secure_site_public_dns_status "$domain" "$baseline" || true

  menu_section "Nginx 与端口"
  if have_cmd nginx && nginx -t >/dev/null 2>&1; then ok "Nginx 配置校验通过"; else warn "Nginx 配置校验失败"; fi
  if pgrep -x nginx >/dev/null 2>&1; then ok "Nginx 正在运行"; else warn "Nginx 未运行"; fi
  listener80="$(secure_site_port_listener 80 || true)"
  listener443="$(secure_site_port_listener 443 || true)"
  if grep -qi nginx <<< "$listener80"; then ok "Nginx 正在监听 TCP/80"; else warn "Nginx 未正常监听 TCP/80"; fi
  if grep -qi nginx <<< "$listener443"; then ok "Nginx 正在监听 TCP/443"; else warn "Nginx 未正常监听 TCP/443"; fi
  if secure_site_nginx_files_are_managed && [[ -f "$SECURE_SITE_NGINX_ACTIVE_CONF" ]] && \
     [[ ! -e "$SECURE_SITE_NGINX_PAUSED_CONF" ]] && \
     grep -Fq 'DMITBOX_PUBLIC_TLS_SITE' "$SECURE_SITE_NGINX_ACTIVE_CONF" && \
     grep -Fq 'DMITBOX_IP_LITERAL_REJECT' "$SECURE_SITE_NGINX_CONF" && \
     grep -Fq 'Content-Security-Policy' "$SECURE_SITE_NGINX_ACTIVE_CONF"; then
    ok "域名 HTTPS、IP 拒绝、SNI 限制、限流与安全响应头均已配置"
  else
    warn "Nginx 安全配置不完整，建议执行安装/修复"
  fi

  menu_section "本机防火墙"
  if secure_site_legacy_firewall_present; then
    warn "发现旧版 DMITBox 建站拦截规则，可能影响其他端口"
  else
    ok "没有旧版 dmitbox_cdn_guard / DMITBOX_CDN_GUARD 规则"
  fi
  info "脚本不会为网站创建 nftables 封锁表，也不会接管其他服务端口"

  menu_section "证书与本机健康"
  if secure_site_certificate_valid "$domain"; then
    ok "证书有效期超过 7 天且域名匹配"
  else
    warn "证书缺失、域名不匹配或将在 7 天内到期"
  fi
  secure_site_https_health "$domain" >/dev/null 2>&1 || health_rc=$?
  case "$health_rc" in
    0) ok "本机 127.0.0.1:443 的 TLS 1.3 与网站健康检查通过" ;;
    2) info "当前系统没有 curl，跳过请求级健康检查" ;;
    *) warn "本机 HTTPS 健康检查失败" ;;
  esac

  menu_section "端口访问提示"
  info "其他端口无法访问时，请使用“系统状态与端口 → 端口访问修复”"
  info "它会区分未监听、只监听回环、本机防火墙和云安全组，不会清空整套规则"
}

secure_site_origin_lock_repair() {
  secure_site_conf_is_managed || { warn "请先安装轻量网站"; return 1; }
  secure_site_select_nginx_paths
  secure_site_migrate_legacy_site || return 1
  local domain=""
  domain="$(secure_site_conf_value DOMAIN)"
  if ! secure_site_legacy_guard_restore || \
     ! secure_site_hosts_pin_apply "$domain" || \
     ! secure_site_setup_dns_watch || \
     ! secure_site_guard_remove_firewall_rules; then
    warn "本机回源修复不完整"
    return 1
  fi
  secure_site_nginx_reload || { warn "Nginx 恢复失败"; return 1; }
  secure_site_conf_set LOCAL_ORIGIN_LOCK 1 || return 1
  secure_site_conf_set LOCAL_ORIGIN_ADDRESS 127.0.0.1 || return 1
  secure_site_conf_set FIREWALL_MODE none || return 1
  ok "本机回源锁定已修复：${domain} → 127.0.0.1:443"
  ok "旧版自动停站任务及专用防火墙规则已移除"
  info "若某个本机服务在修复前缓存过公网 DNS，请将该服务重启一次"
}

secure_site_legacy_firewall_repair() {
  local had=0
  secure_site_legacy_firewall_present && had=1
  if secure_site_guard_remove_firewall_rules; then
    if (( had == 1 )); then
      ok "旧版 DMITBox 防火墙规则已清理"
    else
      ok "未发现旧版 DMITBox 防火墙规则"
    fi
    info "UFW、firewalld、其他 nftables/iptables 规则均未清空"
  else
    warn "旧版规则未能完整清理"
    return 1
  fi
}

secure_site_cdn_guard_menu() {
  while true; do
    menu_header "本机回源与端口" "固定本机回源 · 公网 DNS 检查 · 端口修复"
    if secure_site_conf_is_managed; then
      local menu_domain=""
      menu_domain="$(secure_site_conf_value DOMAIN 2>/dev/null || true)"
      if secure_site_hosts_pin_status "$menu_domain"; then
        ok "${menu_domain} 的本机回源锁定正常"
      else
        warn "本机回源锁定需要修复"
      fi
    else
      warn "尚未安装轻量网站；端口修复仍可独立使用"
    fi
    menu_section "管理"
    menu_item "1" "检查并修复回源锁定" "固定域名到本机 127.0.0.1:443"
    menu_item "2" "查看公网 DNS 状态" "只查询真实 A/AAAA 与 Cloudflare 状态"
    menu_item "3" "清理旧版防火墙规则" "仅删除 DMITBox 旧建站规则"
    menu_item "4" "端口访问修复" "检查监听地址并安全放行指定端口"
    menu_back_item
    local c="" domain="" baseline=""
    read_tty c "请输入编号 > " ""
    case "$c" in
      1) secure_site_origin_lock_repair || true; pause_up ;;
      2)
        if secure_site_conf_is_managed; then
          domain="$(secure_site_conf_value DOMAIN)"
          baseline="$(secure_site_conf_value PUBLIC_DNS_BASELINE 2>/dev/null || true)"
          secure_site_public_dns_status "$domain" "$baseline" || true
        else
          warn "请先安装轻量网站"
        fi
        pause_up
        ;;
      3) secure_site_legacy_firewall_repair || true; pause_up ;;
      4) port_access_repair || true; pause_up ;;
      0|q|Q) return 0 ;;
      *) warn "无效选项"; pause_up ;;
    esac
  done
}

secure_site_renew_certificate() {
  secure_site_conf_is_managed || { warn "尚未使用轻量建站"; return 1; }
  secure_site_migrate_legacy_site || return 1
  local domain="" baseline=""
  domain="$(secure_site_conf_value DOMAIN)"
  baseline="$(secure_site_conf_value PUBLIC_DNS_BASELINE 2>/dev/null || true)"
  secure_site_public_dns_status "$domain" "$baseline" || \
    warn "公网 DNS 已变化；仍将尝试现有 HTTP 验证路径"
  secure_site_check_web_ports || return 1
  have_cmd certbot || { warn "Certbot 不存在"; return 1; }
  if ! run_with_spinner "检查并续期 ${domain} 证书" certbot renew --cert-name "$domain"; then
    warn "证书续期失败"
    return 1
  fi
  secure_site_nginx_reload || { warn "证书检查完成，但 Nginx 重载失败"; return 1; }
  if have_cmd openssl && [[ -s "/etc/letsencrypt/live/${domain}/fullchain.pem" ]]; then
    openssl x509 -in "/etc/letsencrypt/live/${domain}/fullchain.pem" -noout -dates 2>/dev/null || true
  fi
  ok "证书续期检查完成（未到期时 Certbot 不会强制申请）"
}

secure_site_install_or_update() {
  local domain="" email="" template="4" existing_domain="" is_existing=0
  local request_rate="" connection_limit="" conflict="" rollback="" selected_template=""
  local health_rc=0 ip_server_names="" dns_baseline="" current_baseline="" old_baseline=""
  local sni_reject_mode="certificate" dns_direct=0

  secure_site_select_nginx_paths
  if [[ -e "$SECURE_SITE_CONF" ]] && ! secure_site_conf_is_managed; then
    warn "${SECURE_SITE_CONF} 不是本脚本创建的文件，拒绝覆盖"
    return 1
  fi
  secure_site_aux_files_are_managed_or_absent || {
    warn "发现同名但非本脚本管理的监测文件，拒绝覆盖或删除"
    return 1
  }
  if secure_site_conf_is_managed; then
    secure_site_migrate_legacy_site || return 1
    is_existing=1
    existing_domain="$(secure_site_conf_value DOMAIN)"
    template="$(secure_site_conf_value TEMPLATE 2>/dev/null || echo 4)"
    old_baseline="$(secure_site_conf_value PUBLIC_DNS_BASELINE 2>/dev/null || true)"
    [[ -n "$old_baseline" ]] || old_baseline="$(secure_site_conf_value DNS_BASELINE 2>/dev/null || true)"
  fi
  if [[ -e "$SECURE_SITE_NGINX_CONF" || -e "$SECURE_SITE_NGINX_LIMIT_CONF" || \
        -e "$SECURE_SITE_NGINX_ACTIVE_CONF" || -e "$SECURE_SITE_NGINX_PAUSED_CONF" ]] && \
     ! secure_site_nginx_files_are_managed; then
    warn "发现同名但非本脚本管理的 Nginx 配置，拒绝覆盖"
    return 1
  fi

  menu_header "轻量建站" "公网 443 · 本机回源锁定 · Let's Encrypt"
  info "网站安装后始终运行，不再根据公网 DNS 停止 Nginx 或其他服务"
  info "本机将固定解析 网站域名 → 127.0.0.1，公网 DNS 日后变化也不改变回源"
  info "仅初次申请证书要求全部公网 A/AAAA 记录直接指向本机"
  info "脚本不会创建网站封锁用的 nftables 表，也不会接管其他服务端口"
  read_tty domain "输入网站域名（如 site.example.com）> " "$existing_domain"
  domain="${domain,,}"
  valid_domain_name "$domain" || { warn "域名格式无效，只支持 ASCII/Punycode 完整域名"; return 1; }
  if [[ -n "$existing_domain" && "$domain" != "$existing_domain" ]]; then
    warn "已安装域名为 ${existing_domain}；为避免误改证书，请先安全移除后再换域名"
    return 1
  fi
  read_tty email "Let's Encrypt 邮箱（可留空）> " ""
  valid_email_address "$email" || { warn "邮箱格式无效"; return 1; }
  echo "  1) 经典蓝（推荐）"
  echo "  2) 清新绿"
  echo "  3) 暖橙色"
  echo "  4) 随机配色（默认）"
  read_tty template "选择导航配色 > " "$template"
  [[ "$template" =~ ^[1-4]$ ]] || { warn "模板选项无效"; return 1; }

  menu_section "DNS 检查"
  if ! secure_site_install_dns_query_tool; then
    warn "dig 安装失败，无法区分公网 DNS 与本机 hosts 锁定"
    return 1
  fi
  current_baseline="$(secure_site_dns_baseline "$domain")"
  if secure_site_dns_audit "$domain"; then
    dns_direct=1
    dns_baseline="$current_baseline"
  elif (( is_existing == 1 )) && [[ -n "$old_baseline" ]]; then
    dns_baseline="$old_baseline"
    warn "公网 DNS 当前未全部直连本机，将保留原始安装基线"
    info "这不会阻止修复：本机回源锁定独立于公网 DNS"
  else
    warn "初次安装必须先关闭 CDN/代理，并让全部公网 A/AAAA 记录直接指向本机"
    return 1
  fi
  [[ -n "$dns_baseline" ]] || { warn "无法取得或恢复公网 DNS 基线"; return 1; }
  ip_server_names="$(secure_site_ip_server_names_from_baseline "$dns_baseline")"

  secure_site_check_web_ports || return 1
  conflict="$(secure_site_find_conflict_domain "$domain" || true)"
  [[ -z "$conflict" ]] || { warn "域名已出现在其他 Nginx 配置中：${conflict}"; return 1; }
  print_kv "访问地址" "https://${domain}"
  print_kv "HTTPS 监听" "公网 TCP/443"
  print_kv "本机回源" "${domain} → 127.0.0.1:443"
  print_kv "公网 DNS" "$([[ "$dns_direct" == "1" ]] && echo 当前直连本机 || echo 当前已变化，保留安装基线)"

  request_rate="$(secure_site_conf_value REQUEST_RATE 2>/dev/null || random_uint_between 7 13)"
  connection_limit="$(secure_site_conf_value CONNECTION_LIMIT 2>/dev/null || random_uint_between 12 24)"
  is_uint_in_range "$request_rate" 1 100 || request_rate="$(random_uint_between 7 13)"
  is_uint_in_range "$connection_limit" 1 1000 || connection_limit="$(random_uint_between 12 24)"

  echo
  warn "将安装或使用 Nginx、Certbot、dig，并放行公网 TCP/80、TCP/443"
  warn "会清理旧版 DMITBox 建站专用规则，但不会清空其他 nftables/iptables/UFW 规则"
  confirm_word "SITE" "确认请输入 SITE > " || { warn "已取消"; return 0; }

  pkg_install nginx certbot curl openssl python3
  have_cmd nginx || { warn "Nginx 安装失败"; return 1; }
  have_cmd certbot || { warn "Certbot 安装失败，请确认软件源已启用"; return 1; }
  have_cmd curl || { warn "curl 安装失败"; return 1; }
  have_cmd python3 || { warn "Python 3 安装失败"; return 1; }
  secure_site_select_nginx_paths
  secure_site_check_web_ports || return 1
  if secure_site_nginx_supports_ssl_reject_handshake; then
    sni_reject_mode="strict"
  else
    sni_reject_mode="certificate"
    warn "当前 Nginx 版本不支持握手阶段拒绝，将使用兼容关闭规则"
  fi

  rollback="$(secure_site_prepare_rollback)" || { warn "创建回滚备份失败"; return 1; }
  if ! secure_site_legacy_guard_restore; then
    warn "旧版自动停站状态恢复失败，正在回滚"
    secure_site_restore_rollback "$rollback"
    return 1
  fi
  ensure_dir "$(dirname "$SECURE_SITE_NGINX_CONF")" || {
    warn "无法创建 Nginx 配置目录，正在回滚"
    secure_site_restore_rollback "$rollback"
    return 1
  }
  selected_template="$(secure_site_generate_homepage "$domain" "$template")" || {
    warn "生成静态首页失败，正在回滚"
    secure_site_restore_rollback "$rollback"
    return 1
  }
  if ! secure_site_write_limit_conf "$request_rate" || \
     ! secure_site_write_nginx_http_conf "$domain" "$request_rate" "$connection_limit" "$ip_server_names"; then
    warn "写入 Nginx HTTP 配置失败，正在回滚"
    secure_site_restore_rollback "$rollback"
    return 1
  fi
  if ! secure_site_nginx_config_loaded || ! secure_site_nginx_reload; then
    warn "Nginx HTTP 配置加载失败，正在回滚"
    nginx -t 2>&1 | tail -n 30 || true
    secure_site_restore_rollback "$rollback"
    return 1
  fi
  firewall_open_port_best_effort 80 || true
  firewall_open_port_best_effort 443 || true

  if secure_site_certificate_valid "$domain"; then
    info "检测到可用证书，直接复用"
  elif ! secure_site_issue_certificate "$domain" "$email"; then
    warn "证书申请失败，正在回滚站点配置"
    secure_site_restore_rollback "$rollback"
    return 1
  fi
  secure_site_certificate_valid "$domain" || {
    warn "证书文件无效、域名不匹配或有效期不足，正在回滚"
    secure_site_restore_rollback "$rollback"
    return 1
  }

  if ! secure_site_write_nginx_full_conf "$domain" "$request_rate" "$connection_limit" \
       "$ip_server_names" "$sni_reject_mode" || \
     ! secure_site_nginx_config_loaded || ! secure_site_nginx_reload; then
    warn "Nginx 公网 HTTPS 配置失败，正在回滚"
    nginx -t 2>&1 | tail -n 30 || true
    secure_site_restore_rollback "$rollback"
    return 1
  fi

  secure_site_https_health "$domain" >/dev/null 2>&1 || health_rc=$?
  if [[ "$health_rc" -eq 1 ]]; then
    warn "本机 443 网站健康检查失败，正在回滚"
    secure_site_restore_rollback "$rollback"
    return 1
  elif [[ "$health_rc" -eq 2 ]]; then
    warn "当前系统没有 curl，已跳过请求级健康检查"
  fi

  if ! secure_site_hosts_pin_apply "$domain" || \
     ! secure_site_write_managed_conf "$domain" "$selected_template" "$request_rate" \
       "$connection_limit" "$dns_baseline" "$sni_reject_mode" || \
     ! secure_site_setup_dns_watch || \
     ! secure_site_guard_remove_firewall_rules; then
    warn "保存本机回源锁定失败，正在回滚"
    secure_site_restore_rollback "$rollback"
    return 1
  fi
  if ! secure_site_hosts_pin_status "$domain"; then
    warn "本机解析没有稳定返回 127.0.0.1，正在回滚"
    secure_site_restore_rollback "$rollback"
    return 1
  fi
  secure_site_setup_cert_renewal || warn "自动续期调度设置不完整，请定期执行 certbot renew"
  ensure_dir "$SECURE_SITE_BACKUP_DIR" || warn "无法创建长期备份目录：${SECURE_SITE_BACKUP_DIR}"
  cp -a "$SECURE_SITE_CONF" "${SECURE_SITE_BACKUP_DIR}/site-conf-$(ts_now)-$$" 2>/dev/null || true
  secure_site_cleanup_rollback "$rollback" || true

  ok "轻量网站已部署完成"
  ok "访问地址：https://${domain}"
  ok "本机回源已固定：${domain} → 127.0.0.1:443"
  ok "旧版自动停站、服务联动和专用防火墙规则均已移除"
  info "公网 DNS 日后接入 Cloudflare 时，网站继续运行，但本机回源不会跟随其地址"
  warn "若使用该域名回源的本机程序已运行并缓存旧 DNS，请在本次升级后重启它一次"
  echo
  secure_site_show_info
}

secure_site_stop_nginx_when_unused() {
  if secure_site_systemd_running; then
    systemctl unmask --runtime nginx >/dev/null 2>&1 || true
    systemctl disable --now nginx >/dev/null 2>&1
    return $?
  fi
  if have_cmd rc-service; then
    have_cmd rc-update && rc-update del nginx default >/dev/null 2>&1 || true
    rc-service nginx stop >/dev/null 2>&1
    return $?
  fi
  if have_cmd service; then
    have_cmd update-rc.d && update-rc.d nginx disable >/dev/null 2>&1 || true
    service nginx stop >/dev/null 2>&1
    return $?
  fi
  if pgrep -x nginx >/dev/null 2>&1; then
    nginx -s stop >/dev/null 2>&1
  fi
}

secure_site_remove_site() {
  secure_site_conf_is_managed || { warn "尚未使用脚本的轻量建站"; return 1; }
  secure_site_select_nginx_paths
  secure_site_aux_files_are_managed_or_absent || {
    warn "旧监测文件已被人工修改或归属不明，拒绝自动删除"
    return 1
  }
  secure_site_migrate_legacy_site || return 1
  secure_site_nginx_files_are_managed || {
    warn "Nginx 文件已被人工修改或归属不明，拒绝自动删除"
    return 1
  }

  local domain="" rollback="" backup_dir="" backup_tmp="" other_sites=""
  domain="$(secure_site_conf_value DOMAIN)"
  warn "移除后 https://${domain} 将停止访问"
  warn "不会卸载 Nginx/Certbot，也不会删除 Let's Encrypt 证书"
  info "若没有其他 Nginx 网站，将同时停止并禁用 Nginx，避免 IP 地址显示默认欢迎页"
  confirm_word "REMOVE" "确认移除网站请输入 REMOVE > " || { warn "已取消"; return 0; }

  rollback="$(secure_site_prepare_rollback)" || { warn "创建回滚备份失败"; return 1; }
  if ! ensure_dir "$SECURE_SITE_BACKUP_DIR" || \
     ! backup_tmp="$(mktemp -d "${SECURE_SITE_BACKUP_DIR}/.remove.XXXXXX")"; then
    warn "创建长期卸载备份失败，已取消"
    secure_site_cleanup_rollback "$rollback" || true
    return 1
  fi
  backup_dir="${SECURE_SITE_BACKUP_DIR}/removed-$(ts_now)-${backup_tmp##*.}"
  if ! cp -a "$SECURE_SITE_CONF" "$backup_tmp/management.conf" || \
     ! cp -a "$SECURE_SITE_NGINX_CONF" "$backup_tmp/nginx-base.conf" || \
     ! cp -a "$SECURE_SITE_NGINX_LIMIT_CONF" "$backup_tmp/nginx-limits.conf" || \
     ! cp -a "$SECURE_SITE_NGINX_ACTIVE_CONF" "$backup_tmp/nginx-domain.conf"; then
    warn "创建长期卸载备份失败，已取消"
    rm -rf -- "$backup_tmp"
    secure_site_cleanup_rollback "$rollback" || true
    return 1
  fi
  if [[ -d "$SECURE_SITE_ROOT" ]] && ! cp -a "$SECURE_SITE_ROOT" "$backup_tmp/site-root"; then
    warn "备份静态站点失败，已取消"
    rm -rf -- "$backup_tmp"
    secure_site_cleanup_rollback "$rollback" || true
    return 1
  fi
  if [[ -e "$SECURE_SITE_HOSTS_BACKUP" ]] && \
     ! cp -a "$SECURE_SITE_HOSTS_BACKUP" "$backup_tmp/hosts-origin-backup.json"; then
    warn "备份本机回源记录失败，已取消"
    rm -rf -- "$backup_tmp"
    secure_site_cleanup_rollback "$rollback" || true
    return 1
  fi
  if ! mv -- "$backup_tmp" "$backup_dir"; then
    warn "完成长期卸载备份失败，已取消"
    rm -rf -- "$backup_tmp"
    secure_site_cleanup_rollback "$rollback" || true
    return 1
  fi

  if ! other_sites="$(secure_site_other_nginx_server_files)"; then
    warn "无法确认是否还有其他 Nginx 网站，已取消移除"
    secure_site_cleanup_rollback "$rollback" || true
    return 1
  fi
  if ! secure_site_legacy_guard_restore || \
     ! secure_site_hosts_pin_remove "$domain" || \
     ! secure_site_guard_remove_firewall_rules; then
    warn "恢复本机解析或清理旧规则失败，正在回滚"
    secure_site_restore_rollback "$rollback"
    return 1
  fi
  secure_site_remove_dns_watch_schedule

  rm -f "$SECURE_SITE_NGINX_CONF" "$SECURE_SITE_NGINX_LIMIT_CONF" \
    "$SECURE_SITE_NGINX_ACTIVE_CONF" "$SECURE_SITE_NGINX_PAUSED_CONF" >/dev/null 2>&1 || true
  if have_cmd nginx && ! nginx -t >/dev/null 2>&1; then
    warn "移除后 Nginx 校验失败，正在回滚"
    nginx -t 2>&1 | tail -n 30 || true
    secure_site_restore_rollback "$rollback"
    return 1
  fi
  if [[ -z "$other_sites" ]]; then
    if ! secure_site_stop_nginx_when_unused; then
      warn "Nginx 停止失败，正在回滚"
      secure_site_restore_rollback "$rollback"
      return 1
    fi
  elif ! secure_site_nginx_reload; then
    warn "Nginx 重载失败，正在回滚"
    secure_site_restore_rollback "$rollback"
    return 1
  fi

  if ! rm -rf -- "$SECURE_SITE_ROOT" || \
     ! rm -f "$SECURE_SITE_CONF" "$SECURE_SITE_CERT_HOOK" "$SECURE_SITE_CERT_CRON" \
       "$SECURE_SITE_CERT_PERIODIC" "$SECURE_SITE_DNS_WATCH" \
       "$SECURE_SITE_DNS_WATCH_CRON" "$SECURE_SITE_DNS_WATCH_PERIODIC" \
       "$SECURE_SITE_DNS_WATCH_SERVICE" "$SECURE_SITE_DNS_WATCH_TIMER" \
       "$SECURE_SITE_DNS_STATUS" "${SECURE_SITE_DNS_STATUS}.lock"; then
    warn "删除脚本管理文件失败，正在回滚"
    secure_site_restore_rollback "$rollback"
    return 1
  fi
  secure_site_cleanup_rollback "$rollback" || true
  ok "轻量网站已移除"
  ok "本机回源锁定和旧版 DMITBox 防火墙规则已清理"
  if [[ -z "$other_sites" ]]; then
    ok "未发现其他网站，Nginx 已停止；HTTP/HTTPS 通过 IP 不会显示默认页面"
  else
    info "检测到其他 Nginx 网站，已保留并重载 Nginx"
  fi
  info "证书仍保留在 /etc/letsencrypt/live/${domain}，备份位于 ${backup_dir}"
}

secure_site_menu() {
  while true; do
    menu_header "轻量建站" "公网 443 · 本机回源锁定 · 证书自动续期"
    menu_section "管理"
    menu_item "1" "状态与安全检查" "回源锁定、真实 DNS、证书、端口与防火墙"
    menu_item "2" "一键安装或修复" "生成导航站并固定本机域名回源"
    menu_item "3" "查看网站与安全信息" "访问地址、本机回源与安全措施"
    menu_item "4" "重新生成导航首页" "三套无脚本配色，旧首页自动备份"
    menu_item "5" "检查证书续期" "调用 Certbot；未到期不会强制申请"
    menu_item "6" "本机回源与端口" "回源锁定、真实 DNS、旧规则与端口修复"
    menu_item "7" "安全移除网站" "保留软件包、证书和完整备份"
    menu_back_item
    local c=""
    read_tty c "请输入编号 > " ""
    case "$c" in
      1) secure_site_site_status || true; pause_up ;;
      2) secure_site_install_or_update || true; pause_up ;;
      3) secure_site_show_info || true; pause_up ;;
      4) secure_site_regenerate_homepage || true; pause_up ;;
      5) secure_site_renew_certificate || true; pause_up ;;
      6) secure_site_cdn_guard_menu ;;
      7) secure_site_remove_site || true; pause_up ;;
      0|q|Q) return 0 ;;
      *) warn "无效选项"; pause_up ;;
    esac
  done
}

# ======================================================================
# HTTPS reverse proxy (domain -> loopback TCP port)
# ======================================================================
reverse_proxy_select_paths() {
  secure_site_select_nginx_paths
  REVERSE_PROXY_NGINX_DIR="$(dirname "$SECURE_SITE_NGINX_CONF")"
  REVERSE_PROXY_MAP_CONF="${REVERSE_PROXY_NGINX_DIR}/00-dmitbox-reverse-proxy-map.conf"
}

reverse_proxy_meta_path() {
  local domain="$1"
  valid_domain_name "$domain" || return 1
  printf '%s/%s.conf\n' "$REVERSE_PROXY_CONF_DIR" "${domain,,}"
}

reverse_proxy_nginx_path() {
  local domain="$1"
  valid_domain_name "$domain" || return 1
  reverse_proxy_select_paths
  printf '%s/dmitbox-proxy-%s.conf\n' "$REVERSE_PROXY_NGINX_DIR" "${domain,,}"
}

reverse_proxy_conf_value() {
  local file="$1" key="$2"
  [[ -r "$file" && "$key" =~ ^[A-Z0-9_]+$ ]] || return 1
  awk -F= -v key="$key" '$1 == key {sub(/^[^=]*=/, ""); print; exit}' "$file"
}

reverse_proxy_meta_is_managed() {
  local file="$1"
  [[ -f "$file" ]] && grep -Fqx '# managed by dmitbox.sh - reverse proxy' "$file"
}

reverse_proxy_nginx_is_managed() {
  local file="$1"
  [[ -f "$file" ]] && grep -Fqx '# managed by dmitbox.sh - reverse proxy' "$file"
}

reverse_proxy_map_is_managed_or_absent() {
  [[ ! -e "$REVERSE_PROXY_MAP_CONF" ]] || \
    grep -Fqx '# managed by dmitbox.sh - reverse proxy map' "$REVERSE_PROXY_MAP_CONF"
}

reverse_proxy_write_map_conf() {
  reverse_proxy_select_paths
  reverse_proxy_map_is_managed_or_absent || {
    warn "${REVERSE_PROXY_MAP_CONF} 已存在且不属于本脚本，拒绝覆盖"
    return 1
  }
  write_file "$REVERSE_PROXY_MAP_CONF" '# managed by dmitbox.sh - reverse proxy map
map $http_upgrade $dmitbox_connection_upgrade {
    default upgrade;
    ""      close;
}'
}

reverse_proxy_managed_files() {
  local file=""
  [[ -d "$REVERSE_PROXY_CONF_DIR" ]] || return 0
  for file in "$REVERSE_PROXY_CONF_DIR"/*.conf; do
    [[ -e "$file" ]] || continue
    reverse_proxy_meta_is_managed "$file" && printf '%s\n' "$file"
  done | sort
}

reverse_proxy_any_managed() {
  [[ -n "$(reverse_proxy_managed_files)" ]]
}

reverse_proxy_web_ports_available() {
  local listener=""
  listener="$(secure_site_port_listener 80 || true)"
  if [[ -n "$listener" ]] && ! grep -qi nginx <<< "$listener"; then
    warn "TCP/80 已被非 Nginx 程序占用："
    echo "$listener"
    return 1
  fi
  listener="$(secure_site_port_listener 443 || true)"
  if [[ -n "$listener" ]] && ! grep -qi nginx <<< "$listener"; then
    warn "TCP/443 已被非 Nginx 程序占用："
    echo "$listener"
    return 1
  fi
}

reverse_proxy_domain_conflict() {
  local domain="$1" own_nginx="${2:-}" path=""
  if secure_site_conf_is_managed && \
     [[ "$(secure_site_conf_value DOMAIN 2>/dev/null || true)" == "$domain" ]]; then
    printf '%s\n' "$SECURE_SITE_CONF"
    return 0
  fi
  while IFS= read -r path; do
    [[ -n "$path" && "$path" != "$own_nginx" ]] || continue
    if grep -Ei "^[[:space:]]*server_name[[:space:]][^;]*${domain//./\\.}([[:space:];]|$)" "$path" >/dev/null 2>&1; then
      printf '%s\n' "$path"
      return 0
    fi
  done < <(find /etc/nginx -type f -name '*.conf' 2>/dev/null | sort)
  return 1
}

REVERSE_PROXY_PARSED_SCHEME=""
REVERSE_PROXY_PARSED_HOST=""
REVERSE_PROXY_PARSED_PORT=""
REVERSE_PROXY_PARSED_PATH=""
REVERSE_PROXY_PARSED_AUTHORITY=""
REVERSE_PROXY_PARSED_URL=""

reverse_proxy_valid_upstream_host() {
  local host="${1:-}"
  valid_domain_name "$host" && return 0
  [[ "$host" != */* ]] && valid_ip_or_cidr "$host"
}

reverse_proxy_parse_remote_url() {
  local url="${1:-}" scheme="" authority="" host="" port="" path="/" host_authority=""
  REVERSE_PROXY_PARSED_SCHEME=""
  REVERSE_PROXY_PARSED_HOST=""
  REVERSE_PROXY_PARSED_PORT=""
  REVERSE_PROXY_PARSED_PATH=""
  REVERSE_PROXY_PARSED_AUTHORITY=""
  REVERSE_PROXY_PARSED_URL=""

  [[ "$url" =~ ^(https?)://([^/?#]+)(/[^?#]*)?$ ]] || return 1
  scheme="${BASH_REMATCH[1],,}"
  authority="${BASH_REMATCH[2]}"
  path="${BASH_REMATCH[3]:-/}"
  [[ "$authority" != *@* ]] || return 1
  [[ "$path" =~ ^/[A-Za-z0-9._~!%\&\(\)+,=:@/-]*$ ]] || return 1

  if [[ "$authority" =~ ^\[([0-9A-Fa-f:]+)\](:([0-9]+))?$ ]]; then
    host="${BASH_REMATCH[1],,}"
    port="${BASH_REMATCH[3]:-}"
    host_authority="[${host}]"
  else
    [[ "$authority" != *:*:* ]] || return 1
    if [[ "$authority" == *:* ]]; then
      host="${authority%:*}"
      port="${authority##*:}"
    else
      host="$authority"
    fi
    host="${host,,}"
    host_authority="$host"
  fi
  reverse_proxy_valid_upstream_host "$host" || return 1
  [[ -z "$port" ]] && { [[ "$scheme" == "https" ]] && port=443 || port=80; }
  is_uint_in_range "$port" 1 65535 || return 1
  port=$((10#$port))
  [[ "$path" == */ ]] || path+="/"

  authority="$host_authority"
  if ! { [[ "$scheme" == "http" && "$port" == "80" ]] || \
         [[ "$scheme" == "https" && "$port" == "443" ]]; }; then
    authority+=":${port}"
  fi
  REVERSE_PROXY_PARSED_SCHEME="$scheme"
  REVERSE_PROXY_PARSED_HOST="$host"
  REVERSE_PROXY_PARSED_PORT="$port"
  REVERSE_PROXY_PARSED_PATH="$path"
  REVERSE_PROXY_PARSED_AUTHORITY="$authority"
  REVERSE_PROXY_PARSED_URL="${scheme}://${authority}${path}"
}

reverse_proxy_upstream_url() {
  local backend_type="$1" scheme="$2" host="$3" port="$4" path="${5:-/}" authority=""
  [[ "$backend_type" == "local" || "$backend_type" == "remote" ]] || return 1
  [[ "$scheme" == "http" || "$scheme" == "https" ]] || return 1
  is_uint_in_range "$port" 1 65535 || return 1
  port=$((10#$port))
  if [[ "$backend_type" == "local" ]]; then
    [[ "$host" == "127.0.0.1" && "$path" == "/" ]] || return 1
    (( port != 80 && port != 443 )) || return 1
    printf '%s://127.0.0.1:%s/\n' "$scheme" "$port"
    return 0
  fi
  reverse_proxy_valid_upstream_host "$host" || return 1
  [[ "$path" =~ ^/[A-Za-z0-9._~!%\&\(\)+,=:@/-]*$ && "$path" == */ ]] || return 1
  if [[ "$host" == *:* ]]; then authority="[${host}]"; else authority="$host"; fi
  if ! { [[ "$scheme" == "http" && "$port" == "80" ]] || \
         [[ "$scheme" == "https" && "$port" == "443" ]]; }; then
    authority+=":${port}"
  fi
  printf '%s://%s%s\n' "$scheme" "$authority" "$path"
}

reverse_proxy_upstream_authority() {
  local scheme="$1" host="$2" port="$3" authority=""
  [[ "$scheme" == "http" || "$scheme" == "https" ]] || return 1
  reverse_proxy_valid_upstream_host "$host" || return 1
  is_uint_in_range "$port" 1 65535 || return 1
  port=$((10#$port))
  if [[ "$host" == *:* ]]; then authority="[${host}]"; else authority="$host"; fi
  if ! { [[ "$scheme" == "http" && "$port" == "80" ]] || \
         [[ "$scheme" == "https" && "$port" == "443" ]]; }; then
    authority+=":${port}"
  fi
  printf '%s\n' "$authority"
}

reverse_proxy_ca_bundle() {
  local path=""
  for path in \
    /etc/ssl/certs/ca-certificates.crt \
    /etc/pki/tls/certs/ca-bundle.crt \
    /etc/ssl/cert.pem \
    /etc/pki/ca-trust/extracted/pem/tls-ca-bundle.pem; do
    [[ -s "$path" ]] && { printf '%s\n' "$path"; return 0; }
  done
  return 1
}

reverse_proxy_addresses_overlap() {
  local separator="__DMITBOX_LOCAL_ADDRESSES__"
  have_cmd python3 || return 2
  python3 - "$@" <<'PY'
import ipaddress
import sys

separator = "__DMITBOX_LOCAL_ADDRESSES__"
try:
    split = sys.argv.index(separator)
except ValueError:
    raise SystemExit(2)

def parse(values):
    result = set()
    for value in values:
        try:
            result.add(ipaddress.ip_address(value))
        except ValueError:
            pass
    return result

upstream = parse(sys.argv[1:split])
local = parse(sys.argv[split + 1:])
raise SystemExit(0 if upstream & local else 1)
PY
}

reverse_proxy_remote_addresses_safe() {
  (( $# > 0 )) || return 1
  have_cmd python3 || return 2
  python3 - "$@" <<'PY'
import ipaddress
import sys

addresses = []
for value in sys.argv[1:]:
    try:
        addresses.append(ipaddress.ip_address(value))
    except ValueError:
        raise SystemExit(1)

# A public-facing remote-site proxy must not become a route into loopback,
# link-local, private, multicast, documentation or other special networks.
raise SystemExit(0 if addresses and all(address.is_global for address in addresses) else 1)
PY
}

reverse_proxy_remote_addresses() {
  local host="$1"
  if [[ "$host" != */* ]] && valid_ip_or_cidr "$host"; then
    printf '%s\n' "$host"
  else
    secure_site_effective_dns_addresses "$host"
  fi
}

reverse_proxy_target_points_to_local() {
  local host="$1"
  local -a upstream_addresses=() local_addresses=()
  mapfile -t upstream_addresses < <(reverse_proxy_remote_addresses "$host")
  mapfile -t local_addresses < <(secure_site_local_addresses)
  (( ${#upstream_addresses[@]} > 0 && ${#local_addresses[@]} > 0 )) || return 1
  reverse_proxy_addresses_overlap "${upstream_addresses[@]}" \
    '__DMITBOX_LOCAL_ADDRESSES__' "${local_addresses[@]}"
}

reverse_proxy_backend_listener() {
  local port="$1"
  port_listener_for_protocol "$port" tcp
}

reverse_proxy_backend_health() {
  local backend_type="$1" scheme="$2" host="$3" port="$4" path="${5:-/}"
  local code="" output="" target=""
  have_cmd curl || return 2
  target="$(reverse_proxy_upstream_url "$backend_type" "$scheme" "$host" "$port" "$path")" || return 1
  local -a args=(--noproxy '*' -sS -o /dev/null --connect-timeout 3 --max-time 8 \
    -A 'DMITBox-Reverse-Proxy-Check/1.0' -w '%{http_code}' "$target")
  [[ "$backend_type" != "local" || "$scheme" != "https" ]] || args=(-k "${args[@]}")
  output="$(curl "${args[@]}" 2>/dev/null)" || return 1
  code="${output//$'\n'/}"
  [[ "$code" =~ ^[1-5][0-9]{2}$ ]] || return 1
  printf '%s\n' "$code"
}

reverse_proxy_nginx_loaded() {
  local path="$1" output=""
  have_cmd nginx || return 1
  output="$(nginx -T 2>&1)" || return 1
  grep -Fq "# configuration file ${path}:" <<< "$output"
}

reverse_proxy_write_http_conf() {
  local domain="$1" nginx_file="$2" listen_v6=""
  valid_domain_name "$domain" || return 1
  listen_v6="$(secure_site_nginx_ipv6_listen 80)"
  write_file "$nginx_file" "# managed by dmitbox.sh - reverse proxy
# DMITBOX_REVERSE_PROXY_HTTP_BOOTSTRAP
server {
    listen 80;
${listen_v6}
    server_name ${domain};
    root ${REVERSE_PROXY_ACME_ROOT};
    access_log off;
    error_log /var/log/nginx/dmitbox-reverse-proxy-error.log warn;
    server_tokens off;
    if (\$host != \"${domain}\") { return 444; }

    location ^~ /.well-known/acme-challenge/ {
        default_type text/plain;
        limit_except GET HEAD { deny all; }
        try_files \$uri =404;
    }
    location / { return 308 https://${domain}\$request_uri; }
}"
}

reverse_proxy_write_full_conf() {
  local domain="$1" backend_type="$2" scheme="$3" upstream_host="$4" port="$5"
  local upstream_path="$6" max_body_mb="$7" timeout_seconds="$8" nginx_file="$9"
  local ca_bundle="${10:-}" listen80_v6="" listen443_v6="" upstream_url=""
  local authority="" referer_base="" upstream_headers="" upstream_tls="" upstream_cookie=""
  valid_domain_name "$domain" || return 1
  [[ "$backend_type" == "local" || "$backend_type" == "remote" ]] || return 1
  [[ "$scheme" == "http" || "$scheme" == "https" ]] || return 1
  is_uint_in_range "$port" 1 65535 || return 1
  port=$((10#$port))
  is_uint_in_range "$max_body_mb" 1 10240 || return 1
  is_uint_in_range "$timeout_seconds" 10 86400 || return 1
  upstream_url="$(reverse_proxy_upstream_url "$backend_type" "$scheme" "$upstream_host" \
    "$port" "$upstream_path")" || return 1

  if [[ "$backend_type" == "local" ]]; then
    upstream_headers="        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header X-Forwarded-Host \$host;
        proxy_set_header X-Forwarded-Port \$server_port;"
  else
    authority="$(reverse_proxy_upstream_authority "$scheme" "$upstream_host" "$port")" || return 1
    referer_base="${scheme}://${authority}${upstream_path%/}"
    upstream_headers="        # Remote-site mode uses the target Host/Origin and does not disclose visitor IP headers.
        proxy_set_header Host ${authority};
        proxy_set_header Origin ${scheme}://${authority};
        proxy_set_header Referer ${referer_base}\$request_uri;
        proxy_set_header X-Real-IP \"\";
        proxy_set_header X-Forwarded-For \"\";
        proxy_set_header Forwarded \"\";
        proxy_set_header CF-Connecting-IP \"\";
        proxy_set_header True-Client-IP \"\";
        proxy_set_header X-Forwarded-Proto ${scheme};
        proxy_set_header X-Forwarded-Host ${authority};
        proxy_set_header X-Forwarded-Port ${port};
        proxy_redirect default;"
    if valid_domain_name "$upstream_host"; then
      upstream_cookie="        proxy_cookie_domain ${upstream_host} ${domain};
        proxy_cookie_domain ~.* ${domain};"
    fi
    if [[ "$upstream_path" != "/" ]]; then
      upstream_cookie+="${upstream_cookie:+$'\n'}        proxy_cookie_path ${upstream_path} /;"
    fi
    if [[ "$scheme" == "https" ]]; then
      [[ "$ca_bundle" == /* && "$ca_bundle" != *[[:space:]\;\{\}]* && -s "$ca_bundle" ]] || return 1
      upstream_tls="        proxy_ssl_server_name on;
        proxy_ssl_name ${upstream_host};
        proxy_ssl_verify on;
        proxy_ssl_verify_depth 5;
        proxy_ssl_trusted_certificate ${ca_bundle};
        proxy_ssl_protocols TLSv1.2 TLSv1.3;
        proxy_ssl_session_reuse on;"
    fi
  fi
  listen80_v6="$(secure_site_nginx_ipv6_listen 80)"
  listen443_v6="$(secure_site_nginx_ipv6_listen 443 ' ssl http2')"
  write_file "$nginx_file" "# managed by dmitbox.sh - reverse proxy
# DMITBOX_REVERSE_PROXY_HTTPS
server {
    listen 80;
${listen80_v6}
    server_name ${domain};
    root ${REVERSE_PROXY_ACME_ROOT};
    access_log off;
    error_log /var/log/nginx/dmitbox-reverse-proxy-error.log warn;
    server_tokens off;
    if (\$host != \"${domain}\") { return 444; }

    location ^~ /.well-known/acme-challenge/ {
        default_type text/plain;
        limit_except GET HEAD { deny all; }
        try_files \$uri =404;
    }
    location / { return 308 https://${domain}\$request_uri; }
}

server {
    listen 443 ssl http2;
${listen443_v6}
    server_name ${domain};
    access_log off;
    error_log /var/log/nginx/dmitbox-reverse-proxy-error.log warn;
    server_tokens off;
    if (\$ssl_server_name != \"${domain}\") { return 444; }
    if (\$host != \"${domain}\") { return 444; }

    ssl_certificate /etc/letsencrypt/live/${domain}/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/${domain}/privkey.pem;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_session_cache shared:DMITBOX_PROXY_SSL:10m;
    ssl_session_timeout 10m;
    ssl_session_tickets off;

    client_max_body_size ${max_body_mb}m;
    client_header_timeout 15s;
    client_body_timeout ${timeout_seconds}s;
    keepalive_timeout 65s;
    send_timeout ${timeout_seconds}s;

    add_header Strict-Transport-Security \"max-age=604800\" always;
    add_header X-Content-Type-Options \"nosniff\" always;
    add_header Referrer-Policy \"strict-origin-when-cross-origin\" always;

    location / {
        proxy_pass ${upstream_url};
        proxy_http_version 1.1;
${upstream_headers}
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection \$dmitbox_connection_upgrade;
${upstream_tls}
${upstream_cookie}
        proxy_connect_timeout 8s;
        proxy_send_timeout ${timeout_seconds}s;
        proxy_read_timeout ${timeout_seconds}s;
        proxy_buffering off;
        proxy_request_buffering off;
        proxy_socket_keepalive on;
        proxy_hide_header X-Powered-By;
    }
}"
}

reverse_proxy_write_meta() {
  local file="$1" domain="$2" backend_type="$3" scheme="$4" upstream_host="$5"
  local port="$6" upstream_path="$7" max_body_mb="$8" timeout_seconds="$9"
  local created="" upstream_url="" tls_verify=0
  valid_domain_name "$domain" || return 1
  [[ "$backend_type" == "local" || "$backend_type" == "remote" ]] || return 1
  [[ "$scheme" == "http" || "$scheme" == "https" ]] || return 1
  is_uint_in_range "$port" 1 65535 || return 1
  port=$((10#$port))
  is_uint_in_range "$max_body_mb" 1 10240 || return 1
  is_uint_in_range "$timeout_seconds" 10 86400 || return 1
  upstream_url="$(reverse_proxy_upstream_url "$backend_type" "$scheme" "$upstream_host" \
    "$port" "$upstream_path")" || return 1
  [[ "$backend_type" != "remote" || "$scheme" != "https" ]] || tls_verify=1
  created="$(reverse_proxy_conf_value "$file" CREATED_AT 2>/dev/null || true)"
  [[ -n "$created" ]] || created="$(date -Is)"
  write_file "$file" "# managed by dmitbox.sh - reverse proxy
DOMAIN=${domain}
BACKEND_TYPE=${backend_type}
UPSTREAM_SCHEME=${scheme}
UPSTREAM_HOST=${upstream_host}
UPSTREAM_PORT=${port}
UPSTREAM_PATH=${upstream_path}
UPSTREAM_URL=${upstream_url}
UPSTREAM_TLS_VERIFY=${tls_verify}
MAX_BODY_MB=${max_body_mb}
TIMEOUT_SECONDS=${timeout_seconds}
WEBSOCKET=1
CREATED_AT=${created}
UPDATED_AT=$(date -Is)" || return 1
  chmod 600 "$file"
}

reverse_proxy_prepare_rollback() {
  local domain="$1" meta="$2" nginx_file="$3" rollback=""
  rollback="$(mktemp -d /tmp/dmitbox-reverse-proxy-rollback.XXXXXX)" || return 1
  if [[ -e "$meta" ]]; then
    write_file "$rollback/had-meta" 1
    cp -a "$meta" "$rollback/meta" || { rm -rf -- "$rollback"; return 1; }
  fi
  if [[ -e "$nginx_file" ]]; then
    write_file "$rollback/had-nginx" 1
    cp -a "$nginx_file" "$rollback/nginx" || { rm -rf -- "$rollback"; return 1; }
  fi
  if [[ -e "$REVERSE_PROXY_MAP_CONF" ]]; then
    write_file "$rollback/had-map" 1
    cp -a "$REVERSE_PROXY_MAP_CONF" "$rollback/map" || { rm -rf -- "$rollback"; return 1; }
  fi
  printf '%s\n' "$rollback"
}

reverse_proxy_restore_rollback() {
  local rollback="$1" meta="$2" nginx_file="$3"
  [[ "$rollback" == /tmp/dmitbox-reverse-proxy-rollback.* && -d "$rollback" ]] || return 1
  rm -f "$meta" "$nginx_file" "$REVERSE_PROXY_MAP_CONF" >/dev/null 2>&1 || true
  [[ ! -f "$rollback/had-meta" ]] || cp -a "$rollback/meta" "$meta"
  [[ ! -f "$rollback/had-nginx" ]] || cp -a "$rollback/nginx" "$nginx_file"
  [[ ! -f "$rollback/had-map" ]] || cp -a "$rollback/map" "$REVERSE_PROXY_MAP_CONF"
  have_cmd nginx && secure_site_nginx_reload >/dev/null 2>&1 || true
  rm -rf -- "$rollback"
}

reverse_proxy_cleanup_rollback() {
  local rollback="$1"
  [[ "$rollback" == /tmp/dmitbox-reverse-proxy-rollback.* && -d "$rollback" ]] || return 1
  rm -rf -- "$rollback"
}

reverse_proxy_issue_certificate() {
  local domain="$1" email="$2"
  local -a args=(certonly --webroot -w "$REVERSE_PROXY_ACME_ROOT" -d "$domain" \
    --cert-name "$domain" --non-interactive --agree-tos --preferred-challenges http \
    --keep-until-expiring)
  if [[ -n "$email" ]]; then args+=(--email "$email"); else args+=(--register-unsafely-without-email); fi
  run_with_spinner "申请或检查 ${domain} 的 Let's Encrypt 证书" certbot "${args[@]}"
}

reverse_proxy_install_or_update() {
  local domain="" email="" backend_type="local" backend_choice="1" scheme="http"
  local upstream_host="127.0.0.1" port="" upstream_path="/" target_url=""
  local max_body_mb="100" timeout_seconds="300" meta="" nginx_file="" conflict=""
  local rollback="" listener="" health_code="" health_rc=0 existing=0 ca_bundle=""
  local -a remote_addresses=()

  menu_header "HTTPS 反向代理" "本机服务或远程网站 · 自动证书 · WebSocket"
  info "可转发到本机 127.0.0.1 端口，也可转发到其他服务器的网站 URL"
  info "支持普通网页、API、WebSocket、SSE 与较大文件上传"
  read_tty domain "输入反代域名（如 app.example.com）> " ""
  domain="${domain,,}"
  valid_domain_name "$domain" || { warn "域名格式无效"; return 1; }
  meta="$(reverse_proxy_meta_path "$domain")"
  nginx_file="$(reverse_proxy_nginx_path "$domain")"
  if [[ -e "$meta" ]] && ! reverse_proxy_meta_is_managed "$meta"; then
    warn "${meta} 不属于本脚本，拒绝覆盖"
    return 1
  fi
  if [[ -e "$nginx_file" ]] && ! reverse_proxy_nginx_is_managed "$nginx_file"; then
    warn "${nginx_file} 不属于本脚本，拒绝覆盖"
    return 1
  fi
  if reverse_proxy_meta_is_managed "$meta"; then
    existing=1
    backend_type="$(reverse_proxy_conf_value "$meta" BACKEND_TYPE 2>/dev/null || true)"
    [[ "$backend_type" == "local" || "$backend_type" == "remote" ]] || backend_type="local"
    scheme="$(reverse_proxy_conf_value "$meta" UPSTREAM_SCHEME 2>/dev/null || echo http)"
    upstream_host="$(reverse_proxy_conf_value "$meta" UPSTREAM_HOST 2>/dev/null || echo 127.0.0.1)"
    port="$(reverse_proxy_conf_value "$meta" UPSTREAM_PORT 2>/dev/null || true)"
    upstream_path="$(reverse_proxy_conf_value "$meta" UPSTREAM_PATH 2>/dev/null || echo /)"
    [[ -n "$upstream_path" ]] || upstream_path="/"
    max_body_mb="$(reverse_proxy_conf_value "$meta" MAX_BODY_MB 2>/dev/null || echo 100)"
    timeout_seconds="$(reverse_proxy_conf_value "$meta" TIMEOUT_SECONDS 2>/dev/null || echo 300)"
  fi

  conflict="$(reverse_proxy_domain_conflict "$domain" "$nginx_file" || true)"
  [[ -z "$conflict" ]] || { warn "域名已被其他 Nginx 配置使用：${conflict}"; return 1; }
  [[ "$backend_type" == "remote" ]] && backend_choice=2 || backend_choice=1
  echo "  1) 本机服务（127.0.0.1 指定端口）"
  echo "  2) 远程网站（完整 http/https URL）"
  read_tty backend_choice "选择后端类型（默认 ${backend_choice}）> " "$backend_choice"
  case "$backend_choice" in
    1)
      backend_type="local"
      upstream_host="127.0.0.1"
      upstream_path="/"
      read_tty scheme "本机服务协议 http/https（默认 ${scheme}）> " "$scheme"
      scheme="${scheme,,}"
      [[ "$scheme" == "http" || "$scheme" == "https" ]] || { warn "协议只能是 http 或 https"; return 1; }
      read_tty port "本机服务端口（1-65535）> " "$port"
      is_uint_in_range "$port" 1 65535 || { warn "后端端口无效"; return 1; }
      port=$((10#$port))
      (( port != 80 && port != 443 )) || { warn "为防止反代循环，本机后端不能使用 80/443"; return 1; }
      ;;
    2)
      backend_type="remote"
      if [[ "$existing" == "1" && "$(reverse_proxy_conf_value "$meta" BACKEND_TYPE 2>/dev/null || true)" == "remote" ]]; then
        target_url="$(reverse_proxy_upstream_url remote "$scheme" "$upstream_host" "$port" "$upstream_path" 2>/dev/null || true)"
      fi
      read_tty target_url "远程目标 URL（如 https://www.example.com/）> " "$target_url"
      reverse_proxy_parse_remote_url "$target_url" || {
        warn "目标 URL 无效；只支持 http/https、域名或 IP、可选端口及路径，不支持账号、查询参数或片段"
        return 1
      }
      scheme="$REVERSE_PROXY_PARSED_SCHEME"
      upstream_host="$REVERSE_PROXY_PARSED_HOST"
      port="$REVERSE_PROXY_PARSED_PORT"
      upstream_path="$REVERSE_PROXY_PARSED_PATH"
      target_url="$REVERSE_PROXY_PARSED_URL"
      [[ "$upstream_host" != "$domain" ]] || { warn "目标不能与当前反代域名相同，否则会形成循环"; return 1; }
      ;;
    *) warn "后端类型无效"; return 1 ;;
  esac
  read_tty max_body_mb "最大请求/上传大小 MiB（默认 100）> " "$max_body_mb"
  is_uint_in_range "$max_body_mb" 1 10240 || { warn "大小必须在 1-10240 MiB"; return 1; }
  max_body_mb=$((10#$max_body_mb))
  read_tty timeout_seconds "后端超时秒数（默认 300）> " "$timeout_seconds"
  is_uint_in_range "$timeout_seconds" 10 86400 || { warn "超时必须在 10-86400 秒"; return 1; }
  timeout_seconds=$((10#$timeout_seconds))
  read_tty email "Let's Encrypt 邮箱（可留空）> " ""
  valid_email_address "$email" || { warn "邮箱格式无效"; return 1; }

  pkg_install nginx certbot curl openssl python3 ca-certificates
  have_cmd nginx && have_cmd certbot && have_cmd curl || { warn "Nginx、Certbot 或 curl 安装失败"; return 1; }
  secure_site_install_dns_query_tool || { warn "dig 安装失败"; return 1; }
  if [[ "$backend_type" == "local" ]]; then
    listener="$(reverse_proxy_backend_listener "$port")"
    if [[ -z "$listener" ]]; then
      warn "127.0.0.1:${port} 当前没有 TCP 服务监听"
      warn "请先启动后端服务；反代配置不会替你启动应用"
      return 1
    fi
    echo "$listener"
  else
    mapfile -t remote_addresses < <(reverse_proxy_remote_addresses "$upstream_host")
    if (( ${#remote_addresses[@]} == 0 )); then
      warn "远程目标没有可用的公网 DNS 地址"
      return 1
    fi
    if ! reverse_proxy_remote_addresses_safe "${remote_addresses[@]}"; then
      warn "远程目标包含私有、回环、链路本地或其他非公网地址，已拒绝创建公网反代"
      info "本机应用请使用“本机服务”模式；远程网站必须解析到公网单播地址"
      return 1
    fi
    if reverse_proxy_target_points_to_local "$upstream_host"; then
      warn "远程目标解析到了本机地址，可能形成反代循环"
      info "如果目标确实在本机，请改用“本机服务”并填写实际监听端口"
      return 1
    fi
    if [[ "$scheme" == "https" ]]; then
      ca_bundle="$(reverse_proxy_ca_bundle || true)"
      [[ -n "$ca_bundle" ]] || { warn "系统缺少可用 CA 证书库，无法安全验证远程 HTTPS"; return 1; }
    fi
  fi

  health_rc=0
  health_code="$(reverse_proxy_backend_health "$backend_type" "$scheme" "$upstream_host" \
    "$port" "$upstream_path")" || health_rc=$?
  case "$health_rc" in
    0)
      if [[ "$health_code" =~ ^[45] ]]; then
        warn "目标可以连接，但当前返回 HTTP ${health_code}；目标站可能存在权限、反爬或来源限制"
      else
        ok "后端响应正常（HTTP ${health_code}）"
      fi
      ;;
    *) warn "无法通过 ${scheme} 访问目标，请核对地址、协议、证书和网络"; return 1 ;;
  esac

  reverse_proxy_select_paths
  reverse_proxy_web_ports_available || return 1
  if ! secure_site_certificate_valid "$domain"; then
    secure_site_dns_audit "$domain" || {
      warn "首次申请证书要求公网 A/AAAA 记录全部直接指向本机"
      return 1
    }
  fi

  print_kv "访问地址" "https://${domain}"
  target_url="$(reverse_proxy_upstream_url "$backend_type" "$scheme" "$upstream_host" "$port" "$upstream_path")"
  print_kv "后端类型" "$([[ "$backend_type" == "local" ]] && echo 本机服务 || echo 远程网站)"
  print_kv "目标" "$target_url"
  print_kv "WebSocket" "自动支持"
  print_kv "最大上传" "${max_body_mb} MiB"
  print_kv "后端超时" "${timeout_seconds} 秒"
  if [[ "$backend_type" == "local" ]]; then
    warn "将写入独立 Nginx 站点；不会修改本机后端或开放 ${port}/tcp"
  else
    warn "请确认你有权代理该目标；部分站点会因登录、CSP、反爬或绝对资源地址而无法完整镜像"
    info "远程 HTTPS 会校验证书和 SNI，并改写目标跳转与 Cookie 域；不会转发访客真实 IP 头"
  fi
  if secure_site_conf_is_managed; then
    warn "本机已有“轻量建站”：增加反代后，整套 Nginx 自动停站将不再满足“无其他网站”条件"
    info "这是为了避免 Cloudflare 状态变化时误停这个反代；轻量网站状态页会给出相应提示"
  fi
  confirm_word "PROXY" "确认安装反代请输入 PROXY > " || { warn "已取消"; return 0; }

  ensure_dir "$REVERSE_PROXY_CONF_DIR" || return 1
  ensure_dir "$REVERSE_PROXY_NGINX_DIR" || return 1
  ensure_dir "$REVERSE_PROXY_ACME_ROOT/.well-known/acme-challenge" || return 1
  rollback="$(reverse_proxy_prepare_rollback "$domain" "$meta" "$nginx_file")" || {
    warn "创建反代回滚点失败"
    return 1
  }
  if ! reverse_proxy_write_map_conf; then
    reverse_proxy_restore_rollback "$rollback" "$meta" "$nginx_file"
    return 1
  fi

  if ! secure_site_certificate_valid "$domain"; then
    if ! reverse_proxy_write_http_conf "$domain" "$nginx_file" || \
       ! reverse_proxy_nginx_loaded "$nginx_file" || ! secure_site_nginx_reload; then
      warn "Nginx 证书验证配置失败，正在回滚"
      nginx -t 2>&1 | tail -n 30 || true
      reverse_proxy_restore_rollback "$rollback" "$meta" "$nginx_file"
      return 1
    fi
    firewall_open_port_best_effort 80 || true
    firewall_open_port_best_effort 443 || true
    if ! reverse_proxy_issue_certificate "$domain" "$email" || ! secure_site_certificate_valid "$domain"; then
      warn "证书申请失败，正在回滚"
      reverse_proxy_restore_rollback "$rollback" "$meta" "$nginx_file"
      return 1
    fi
  fi

  if ! reverse_proxy_write_full_conf "$domain" "$backend_type" "$scheme" "$upstream_host" \
       "$port" "$upstream_path" "$max_body_mb" "$timeout_seconds" "$nginx_file" "$ca_bundle" || \
     ! reverse_proxy_write_meta "$meta" "$domain" "$backend_type" "$scheme" "$upstream_host" \
       "$port" "$upstream_path" "$max_body_mb" "$timeout_seconds" || \
     ! reverse_proxy_nginx_loaded "$nginx_file" || ! secure_site_nginx_reload; then
    warn "反代 HTTPS 配置失败，正在回滚"
    nginx -t 2>&1 | tail -n 30 || true
    reverse_proxy_restore_rollback "$rollback" "$meta" "$nginx_file"
    return 1
  fi
  secure_site_setup_cert_renewal || warn "证书自动续期调度设置不完整"
  reverse_proxy_cleanup_rollback "$rollback" || true
  ok "$([[ "$existing" == "1" ]] && echo 反向代理已更新 || echo 反向代理已创建)"
  ok "https://${domain} → ${target_url}"
  if [[ "$backend_type" == "local" ]]; then
    info "本机后端端口无需在防火墙或云安全组中放行"
  else
    info "远程目标固定在该站点配置中，本功能不会成为可由访客指定目标的开放代理"
  fi
}

reverse_proxy_status() {
  menu_header "反向代理状态" "域名、后端、证书与配置检查"
  reverse_proxy_select_paths
  local file="" domain="" backend_type="" scheme="" upstream_host="" port=""
  local upstream_path="" target_url="" nginx_file="" count=0 health_rc=0 health_code=""
  while IFS= read -r file; do
    [[ -n "$file" ]] || continue
    count=$((count + 1))
    domain="$(reverse_proxy_conf_value "$file" DOMAIN 2>/dev/null || true)"
    backend_type="$(reverse_proxy_conf_value "$file" BACKEND_TYPE 2>/dev/null || true)"
    [[ "$backend_type" == "local" || "$backend_type" == "remote" ]] || backend_type="local"
    scheme="$(reverse_proxy_conf_value "$file" UPSTREAM_SCHEME 2>/dev/null || true)"
    upstream_host="$(reverse_proxy_conf_value "$file" UPSTREAM_HOST 2>/dev/null || true)"
    [[ -n "$upstream_host" ]] || upstream_host="127.0.0.1"
    port="$(reverse_proxy_conf_value "$file" UPSTREAM_PORT 2>/dev/null || true)"
    upstream_path="$(reverse_proxy_conf_value "$file" UPSTREAM_PATH 2>/dev/null || true)"
    [[ -n "$upstream_path" ]] || upstream_path="/"
    target_url="$(reverse_proxy_upstream_url "$backend_type" "$scheme" "$upstream_host" \
      "$port" "$upstream_path" 2>/dev/null || true)"
    nginx_file="$(reverse_proxy_nginx_path "$domain" 2>/dev/null || true)"
    menu_section "$domain"
    print_kv "访问地址" "https://${domain}"
    print_kv "后端类型" "$([[ "$backend_type" == "local" ]] && echo 本机服务 || echo 远程网站)"
    print_kv "目标" "${target_url:-配置无效}"
    if reverse_proxy_nginx_is_managed "$nginx_file" && reverse_proxy_nginx_loaded "$nginx_file"; then
      ok "Nginx 站点配置已加载"
    else
      warn "Nginx 站点配置缺失、被修改或未加载"
    fi
    if secure_site_certificate_valid "$domain"; then ok "HTTPS 证书有效"; else warn "HTTPS 证书缺失或将在 7 天内到期"; fi
    health_rc=0
    health_code=""
    if [[ -n "$target_url" ]]; then
      health_code="$(reverse_proxy_backend_health "$backend_type" "$scheme" "$upstream_host" \
        "$port" "$upstream_path")" || health_rc=$?
    else
      health_rc=1
    fi
    case "$health_rc" in
      0)
        if [[ "$health_code" =~ ^[45] ]]; then
          warn "后端可连接，但返回 HTTP ${health_code}"
        else
          ok "后端响应正常（HTTP ${health_code}）"
        fi
        ;;
      2) info "缺少 curl，跳过后端请求检查" ;;
      *) warn "后端当前无法正常响应" ;;
    esac
  done < <(reverse_proxy_managed_files)
  if (( count == 0 )); then
    info "尚未配置反向代理"
  else
    menu_section "Nginx"
    if nginx -t >/dev/null 2>&1; then ok "Nginx 全局配置校验通过"; else warn "Nginx 全局配置校验失败"; fi
  fi
}

reverse_proxy_renew_certificate() {
  local domain="" meta=""
  read_tty domain "输入要续期检查的反代域名 > " ""
  domain="${domain,,}"
  valid_domain_name "$domain" || { warn "域名格式无效"; return 1; }
  meta="$(reverse_proxy_meta_path "$domain")"
  reverse_proxy_meta_is_managed "$meta" || { warn "该域名不是脚本管理的反代"; return 1; }
  have_cmd certbot || { warn "Certbot 不存在"; return 1; }
  if ! run_with_spinner "检查并续期 ${domain} 证书" certbot renew --cert-name "$domain"; then
    warn "证书续期失败"
    return 1
  fi
  secure_site_nginx_reload || { warn "证书检查完成，但 Nginx 重载失败"; return 1; }
  ok "证书续期检查完成"
}

reverse_proxy_remove() {
  local domain="" meta="" nginx_file="" rollback="" backup_dir=""
  read_tty domain "输入要移除的反代域名 > " ""
  domain="${domain,,}"
  valid_domain_name "$domain" || { warn "域名格式无效"; return 1; }
  meta="$(reverse_proxy_meta_path "$domain")"
  nginx_file="$(reverse_proxy_nginx_path "$domain")"
  reverse_proxy_meta_is_managed "$meta" || { warn "该域名不是脚本管理的反代"; return 1; }
  reverse_proxy_nginx_is_managed "$nginx_file" || { warn "Nginx 配置已被人工修改，拒绝自动删除"; return 1; }
  warn "将移除 https://${domain} 的反代；不会删除后端服务或 Let's Encrypt 证书"
  confirm_word "REMOVE" "确认移除请输入 REMOVE > " || { warn "已取消"; return 0; }
  reverse_proxy_select_paths
  rollback="$(reverse_proxy_prepare_rollback "$domain" "$meta" "$nginx_file")" || return 1
  ensure_dir "$REVERSE_PROXY_BACKUP_DIR" || {
    reverse_proxy_cleanup_rollback "$rollback" || true
    return 1
  }
  backup_dir="${REVERSE_PROXY_BACKUP_DIR}/removed-${domain}-$(ts_now)-$$"
  ensure_dir "$backup_dir" || { reverse_proxy_cleanup_rollback "$rollback" || true; return 1; }
  cp -a "$meta" "$backup_dir/management.conf" || { reverse_proxy_cleanup_rollback "$rollback" || true; return 1; }
  cp -a "$nginx_file" "$backup_dir/nginx.conf" || { reverse_proxy_cleanup_rollback "$rollback" || true; return 1; }

  rm -f "$meta" "$nginx_file" >/dev/null 2>&1 || true
  if ! reverse_proxy_any_managed; then
    reverse_proxy_map_is_managed_or_absent && rm -f "$REVERSE_PROXY_MAP_CONF" >/dev/null 2>&1 || true
  fi
  if ! nginx -t >/dev/null 2>&1 || ! secure_site_nginx_reload; then
    warn "移除后 Nginx 校验或重载失败，正在回滚"
    reverse_proxy_restore_rollback "$rollback" "$meta" "$nginx_file"
    return 1
  fi
  reverse_proxy_cleanup_rollback "$rollback" || true
  ok "反向代理已移除：https://${domain}"
  info "后端服务未改动；证书仍保留；配置备份位于 ${backup_dir}"
}

reverse_proxy_menu() {
  while true; do
    menu_header "HTTPS 反向代理" "本机服务或远程网站 · 自动证书 · WebSocket"
    menu_section "管理"
    menu_item "1" "查看反代状态" "域名、后端、证书与健康检查"
    menu_item "2" "添加或更新反代" "转发到本机端口或远程网站 URL"
    menu_item "3" "检查证书续期" "调用 Certbot；未到期不会强制申请"
    menu_item "4" "安全移除反代" "保留后端、证书和配置备份"
    menu_back_item
    local c=""
    read_tty c "请输入编号 > " ""
    case "$c" in
      1) reverse_proxy_status || true; pause_up ;;
      2) reverse_proxy_install_or_update || true; pause_up ;;
      3) reverse_proxy_renew_certificate || true; pause_up ;;
      4) reverse_proxy_remove || true; pause_up ;;
      0|q|Q) return 0 ;;
      *) warn "无效选项"; pause_up ;;
    esac
  done
}

# ======================================================================
# Common firewall management
# ======================================================================
common_firewall_normalize_port_spec() {
  local value="${1:-}" start="" end=""
  value="${value//:/-}"
  if [[ "$value" =~ ^[0-9]{1,5}$ ]]; then
    is_uint_in_range "$value" 1 65535 || return 1
    printf '%s\n' "$((10#$value))"
    return 0
  fi
  [[ "$value" =~ ^([0-9]{1,5})-([0-9]{1,5})$ ]] || return 1
  start="${BASH_REMATCH[1]}"
  end="${BASH_REMATCH[2]}"
  is_uint_in_range "$start" 1 65535 || return 1
  is_uint_in_range "$end" 1 65535 || return 1
  start=$((10#$start))
  end=$((10#$end))
  (( start <= end )) || return 1
  printf '%s-%s\n' "$start" "$end"
}

common_firewall_ufw_port_spec() {
  local value=""
  value="$(common_firewall_normalize_port_spec "${1:-}")" || return 1
  printf '%s\n' "${value//-/:}"
}

common_firewall_valid_protocol() {
  [[ "${1:-}" == "tcp" || "${1:-}" == "udp" ]]
}

common_firewall_source_family() {
  local source="${1:-}"
  valid_ip_or_cidr "$source" || return 1
  if [[ "$source" == *:* ]]; then printf 'ipv6\n'; else printf 'ipv4\n'; fi
}

common_firewall_source_contains_ip() {
  local source="${1:-}" address="${2:-}"
  valid_ip_or_cidr "$source" || return 1
  valid_ip_or_cidr "$address" || return 1
  [[ "$address" != */* ]] || return 1
  if have_cmd python3; then
    if python3 - "$source" "$address" >/dev/null 2>&1 <<'PY'
import ipaddress
import sys

network = ipaddress.ip_network(sys.argv[1], strict=False)
address = ipaddress.ip_address(sys.argv[2])
raise SystemExit(0 if address.version == network.version and address in network else 1)
PY
    then
      return 0
    fi
    return 1
  fi
  [[ "$source" == "$address" ]]
}

common_firewall_ufw_active() {
  have_cmd ufw || return 1
  LC_ALL=C ufw status 2>/dev/null | grep -qi '^Status:[[:space:]]*active'
}

common_firewall_firewalld_active() {
  have_cmd firewall-cmd || return 1
  firewall-cmd --state 2>/dev/null | grep -qx 'running'
}

common_firewall_active_backend() {
  local ufw_active=0 firewalld_active=0
  common_firewall_ufw_active && ufw_active=1
  common_firewall_firewalld_active && firewalld_active=1
  if (( ufw_active == 1 && firewalld_active == 1 )); then
    printf 'conflict\n'
    return 2
  fi
  if (( ufw_active == 1 )); then printf 'ufw\n'; return 0; fi
  if (( firewalld_active == 1 )); then printf 'firewalld\n'; return 0; fi
  printf 'none\n'
  return 1
}

common_firewall_installed_managers() {
  local managers=""
  have_cmd ufw && managers="UFW"
  if have_cmd firewall-cmd; then
    if [[ -n "$managers" ]]; then
      managers="${managers} + firewalld"
    else
      managers="firewalld"
    fi
  fi
  [[ -n "$managers" ]] || return 1
  printf '%s\n' "$managers"
}

common_firewall_state_summary() {
  local backend="" rc=0 installed=""
  backend="$(common_firewall_active_backend)" || rc=$?
  case "$rc:$backend" in
    0:ufw) printf 'UFW 已启用\n' ;;
    0:firewalld) printf 'firewalld 已启用\n' ;;
    2:conflict) printf '双管理器冲突\n' ;;
    *)
      installed="$(common_firewall_installed_managers 2>/dev/null || true)"
      if [[ -n "$installed" ]]; then
        printf '%s 已安装未启用\n' "$installed"
      else
        printf '尚未安装\n'
      fi
      ;;
  esac
}

common_firewall_menu_notice() {
  local backend="" rc=0 installed="" netfilter_risk="none"
  backend="$(common_firewall_active_backend)" || rc=$?
  case "$rc:$backend" in
    0:ufw) ok "UFW 正在运行" ;;
    0:firewalld) ok "firewalld 正在运行" ;;
    2:conflict)
      warn "UFW 与 firewalld 同时运行；脚本已暂停规则修改"
      ;;
    *)
      installed="$(common_firewall_installed_managers 2>/dev/null || true)"
      if [[ -n "$installed" ]]; then
        warn "${installed} 已安装但尚未启用；选择 [2] 可安全启用"
      else
        warn "尚未安装 UFW/firewalld；选择 [2] 可自动安装并安全启用"
      fi
      netfilter_risk="$(common_firewall_netfilter_risk)"
      case "$netfilter_risk" in
        forwarding) info "已有转发/NAT/输出规则：安装时会自动备份并原样保留" ;;
        input) warn "已有规则影响本机 INPUT：安装时会显示明细并要求确认共存" ;;
        unknown) warn "存在无法完整解析的规则：安装时会显示明细并要求确认" ;;
      esac
      ;;
  esac
}

common_firewall_choose_install_backend() {
  local ufw_installed=0 firewalld_installed=0
  have_cmd ufw && ufw_installed=1
  have_cmd firewall-cmd && firewalld_installed=1

  if (( ufw_installed == 1 && firewalld_installed == 0 )); then printf 'ufw\n'; return 0; fi
  if (( firewalld_installed == 1 && ufw_installed == 0 )); then printf 'firewalld\n'; return 0; fi
  if have_cmd apt-get || have_cmd apk; then printf 'ufw\n'; return 0; fi
  if have_cmd dnf || have_cmd yum; then printf 'firewalld\n'; return 0; fi
  return 1
}

common_firewall_firewalld_zone() {
  local zone="" ifc="" connection=""
  ifc="$(default_iface)"
  if common_firewall_firewalld_active; then
    zone="$(firewall-cmd --get-zone-of-interface="$ifc" 2>/dev/null || true)"
    [[ "$zone" == "no zone" ]] && zone=""
    [[ -n "$zone" ]] || zone="$(firewall-cmd --get-default-zone 2>/dev/null || true)"
  elif have_cmd firewall-offline-cmd; then
    if have_cmd nmcli; then
      connection="$(nmcli -g GENERAL.CONNECTION device show "$ifc" 2>/dev/null | sed -n '1p' || true)"
      if [[ -n "$connection" && "$connection" != "--" ]]; then
        zone="$(nmcli -g connection.zone connection show "$connection" 2>/dev/null | sed -n '1p' || true)"
      fi
    fi
    [[ -n "$zone" && "$zone" != "--" ]] || zone=""
    [[ -n "$zone" ]] || zone="$(firewall-offline-cmd --get-default-zone 2>/dev/null || true)"
  fi
  zone="${zone:-public}"
  [[ "$zone" =~ ^[A-Za-z0-9_.-]{1,32}$ ]] || return 1
  printf '%s\n' "$zone"
}

common_firewall_netfilter_inventory() {
  local output="" result="" command_name="" line="" ipt_risk="none"
  local nft_parsed=0
  if have_cmd nft; then
    if have_cmd python3; then
      output="$(nft -j list ruleset 2>/dev/null || true)"
      if [[ -n "$output" ]]; then
        if result="$(python3 -c '
import json
import sys

try:
    objects = json.load(sys.stdin).get("nftables", [])
except (ValueError, AttributeError):
    raise SystemExit(2)

owned_tables = {("inet", "dmitbox_rand6")}
chains = {}
rules = []
table_keys = set()

for item in objects:
    if not isinstance(item, dict) or not item:
        continue
    kind, data = next(iter(item.items()))
    if kind == "metainfo" or not isinstance(data, dict):
        continue
    family = str(data.get("family", ""))
    table = str(data.get("table", ""))
    if kind == "table":
        table = str(data.get("name", ""))
    key = (family, table)
    if not family or not table or key in owned_tables:
        continue
    table_keys.add(key)
    if kind == "chain":
        name = str(data.get("name", ""))
        if name:
            chains[(family, table, name)] = data
    elif kind == "rule":
        rules.append(data)

for family, table in sorted(table_keys):
    table_chains = {
        name: data for (fam, tab, name), data in chains.items()
        if fam == family and tab == table
    }
    table_rules = [
        rule for rule in rules
        if str(rule.get("family", "")) == family and str(rule.get("table", "")) == table
    ]
    input_chains = {
        name for name, data in table_chains.items()
        if str(data.get("hook", "")).lower() == "input"
    }
    input_policy = any(
        str(table_chains[name].get("policy") or "accept").lower() != "accept"
        for name in input_chains
    )
    input_rules = any(str(rule.get("chain", "")) in input_chains for rule in table_rules)
    hooked_policy = any(
        data.get("hook") and str(data.get("policy") or "accept").lower() != "accept"
        for data in table_chains.values()
    )
    if input_policy or input_rules:
        risk = "input"
        detail = "包含 INPUT 钩子规则或非 ACCEPT 策略"
    elif table_rules or hooked_policy:
        risk = "forwarding"
        hooks = sorted({str(data.get("hook")) for data in table_chains.values() if data.get("hook")})
        detail = "仅发现转发/NAT/输出路径"
        if hooks:
            detail += "（" + ",".join(hooks) + "）"
    else:
        continue
    label = (family + " " + table).replace("|", "/")
    print("|".join((risk, "nft", label, detail)))
' <<< "$output")"; then
          nft_parsed=1
          [[ -n "$result" ]] && printf '%s\n' "$result"
        fi
      fi
    fi
    if (( nft_parsed == 0 )); then
      output="$(nft list tables 2>/dev/null || true)"
      while IFS= read -r line; do
        [[ -n "$line" ]] || continue
        [[ "$line" =~ ^[[:space:]]*table[[:space:]]+inet[[:space:]]+dmitbox_rand6[[:space:]]*$ ]] && continue
        printf 'unknown|nft|%s|无法解析该表对入站流量的影响\n' "${line//|//}"
      done <<< "$output"
    fi
  fi
  for command_name in iptables ip6tables; do
    have_cmd "$command_name" || continue
    output="$("$command_name" -S 2>/dev/null || true)"
    ipt_risk="none"
    while IFS= read -r line; do
      [[ -n "$line" ]] || continue
      case "$line" in
        "-P INPUT ACCEPT"|"-P FORWARD ACCEPT"|"-P OUTPUT ACCEPT"|-N\ *) ;;
        "-P INPUT "*|-A\ INPUT\ *) ipt_risk="input"; break ;;
        -P\ FORWARD\ *|-P\ OUTPUT\ *|-A\ *) [[ "$ipt_risk" == "none" ]] && ipt_risk="forwarding" ;;
      esac
    done <<< "$output"
    case "$ipt_risk" in
      input) printf 'input|%s|filter 规则集|包含 INPUT 规则或非 ACCEPT 策略\n' "$command_name" ;;
      forwarding) printf 'forwarding|%s|规则集|仅发现转发、输出或自定义链\n' "$command_name" ;;
    esac
  done
}

common_firewall_netfilter_risk() {
  local inventory=""
  inventory="$(common_firewall_netfilter_inventory | sort -u)"
  if grep -q '^input|' <<< "$inventory"; then printf 'input\n'; return 0; fi
  if grep -q '^unknown|' <<< "$inventory"; then printf 'unknown\n'; return 0; fi
  if grep -q '^forwarding|' <<< "$inventory"; then printf 'forwarding\n'; return 0; fi
  printf 'none\n'
}

common_firewall_netfilter_show_inventory() {
  local inventory="" risk="" source="" object="" detail="" count=0
  inventory="$(common_firewall_netfilter_inventory | sort -u)"
  [[ -n "$inventory" ]] || { info "未发现额外的 netfilter 规则"; return 0; }
  while IFS='|' read -r risk source object detail; do
    [[ -n "$risk" ]] || continue
    count=$((count + 1))
    if (( count > 16 )); then
      info "其余规则已省略，可在防火墙状态页查看"
      break
    fi
    case "$risk" in
      input) warn "影响本机入站：${source} · ${object} · ${detail}" ;;
      forwarding) info "保留共存规则：${source} · ${object} · ${detail}" ;;
      unknown) warn "影响范围未知：${source} · ${object} · ${detail}" ;;
    esac
  done <<< "$inventory"
}

common_firewall_custom_netfilter_present() {
  [[ "$(common_firewall_netfilter_risk)" != "none" ]]
}

common_firewall_backup_netfilter() {
  local backup_dir="" saved=0 command_name="" output_file=""
  COMMON_FIREWALL_LAST_BACKUP=""
  ensure_dir "$COMMON_FIREWALL_BACKUP_DIR" || { warn "无法创建防火墙备份目录"; return 1; }
  backup_dir="${COMMON_FIREWALL_BACKUP_DIR}/pre-enable-$(ts_now)-$$"
  ensure_dir "$backup_dir" || { warn "无法创建本次防火墙备份"; return 1; }
  chmod 700 "$COMMON_FIREWALL_BACKUP_DIR" "$backup_dir" 2>/dev/null || true

  if have_cmd nft; then
    output_file="${backup_dir}/nftables.rules"
    if (umask 077; nft list ruleset > "$output_file" 2>/dev/null) && [[ -s "$output_file" ]]; then
      saved=$((saved + 1))
    else
      rm -f "$output_file"
    fi
  fi
  for command_name in iptables-save ip6tables-save; do
    have_cmd "$command_name" || continue
    output_file="${backup_dir}/${command_name}.rules"
    if (umask 077; "$command_name" > "$output_file" 2>/dev/null) && [[ -s "$output_file" ]]; then
      saved=$((saved + 1))
    else
      rm -f "$output_file"
    fi
  done
  if (( saved == 0 )); then
    rmdir "$backup_dir" 2>/dev/null || true
    warn "已有规则无法完整读取和备份，已取消启用"
    return 1
  fi
  (umask 077; printf '%s\n' \
    "DMITBox 防火墙启用前只读备份" \
    "时间：$(date -Is 2>/dev/null || date)" \
    "说明：脚本不会自动恢复此备份；需要恢复时请从 VPS 控制台人工确认。" \
    > "${backup_dir}/README.txt") || return 1
  COMMON_FIREWALL_LAST_BACKUP="$backup_dir"
  ok "原有 netfilter 规则已备份：${backup_dir}"
}

common_firewall_listener_lines() {
  local protocol="$1"
  common_firewall_valid_protocol "$protocol" || return 1
  if have_cmd ss; then
    if [[ "$protocol" == "tcp" ]]; then
      ss -H -ltn 2>/dev/null || true
    else
      ss -H -lun 2>/dev/null || true
    fi
  elif have_cmd netstat; then
    if [[ "$protocol" == "tcp" ]]; then
      netstat -lnt 2>/dev/null | sed -n '3,$p' || true
    else
      netstat -lnu 2>/dev/null | sed -n '3,$p' || true
    fi
  fi
}

common_firewall_public_listeners() {
  local protocol="" line="" address="" host="" port=""
  for protocol in tcp udp; do
    while IFS= read -r line; do
      [[ -n "$line" ]] || continue
      address="$(awk '{print $4}' <<< "$line")"
      [[ "$address" == *:* ]] || continue
      port="${address##*:}"
      is_uint_in_range "$port" 1 65535 || continue
      port=$((10#$port))
      host="${address%:*}"
      host="${host%%%*}"
      case "$host" in
        127.*|localhost|"[::1]"|::1|::ffff:127.*) continue ;;
      esac
      printf '%s|%s\n' "$protocol" "$port"
    done < <(common_firewall_listener_lines "$protocol")
  done | sort -t '|' -k1,1 -k2,2n -u
}

common_firewall_preserved_ports() {
  local preset="${1:-listeners}" port=""
  {
    while IFS= read -r port; do
      is_uint_in_range "$port" 1 65535 || continue
      printf 'tcp|%s\n' "$((10#$port))"
    done < <(ssh_current_ports 2>/dev/null | tr '[:space:]' '\n')
    case "$preset" in
      ssh) ;;
      web)
        printf 'tcp|80\ntcp|443\n'
        ;;
      listeners)
        common_firewall_public_listeners
        ;;
      *) return 1 ;;
    esac
  } | sort -t '|' -k1,1 -k2,2n -u
}

common_firewall_registry_init() {
  local first=""
  if [[ -L "$COMMON_FIREWALL_REGISTRY" ]]; then
    warn "防火墙规则记录路径不能是符号链接"
    return 1
  fi
  if [[ -e "$COMMON_FIREWALL_REGISTRY" && ! -f "$COMMON_FIREWALL_REGISTRY" ]]; then
    warn "防火墙规则记录路径不是普通文件：${COMMON_FIREWALL_REGISTRY}"
    return 1
  fi
  if [[ -s "$COMMON_FIREWALL_REGISTRY" ]]; then
    first="$(sed -n '1p' "$COMMON_FIREWALL_REGISTRY" 2>/dev/null || true)"
    if [[ "$first" != "$COMMON_FIREWALL_MARKER" ]]; then
      warn "防火墙规则记录文件不属于本脚本，拒绝覆盖"
      return 1
    fi
  else
    ensure_dir "$(dirname "$COMMON_FIREWALL_REGISTRY")" || return 1
    (umask 077; printf '%s\n' "$COMMON_FIREWALL_MARKER" > "$COMMON_FIREWALL_REGISTRY") || return 1
  fi
  chmod 600 "$COMMON_FIREWALL_REGISTRY" 2>/dev/null || true
}

common_firewall_registry_add() {
  local backend="$1" action="$2" protocol="$3" port="$4" source="$5" zone="$6"
  local id="" created=""
  [[ "$backend" == "ufw" || "$backend" == "firewalld" ]] || return 1
  [[ "$action" == "allow-port" || "$action" == "allow-source-port" || "$action" == "deny-source" ]] || return 1
  if [[ "$protocol" != "-" ]]; then common_firewall_valid_protocol "$protocol" || return 1; fi
  if [[ "$port" != "-" ]]; then port="$(common_firewall_normalize_port_spec "$port")" || return 1; fi
  if [[ "$source" != "-" ]]; then valid_ip_or_cidr "$source" || return 1; fi
  [[ "$zone" == "-" || "$zone" =~ ^[A-Za-z0-9_.-]{1,32}$ ]] || return 1
  common_firewall_registry_init || return 1
  if awk -F '|' -v b="$backend" -v a="$action" -v p="$protocol" -v n="$port" -v s="$source" -v z="$zone" '
    NR > 1 && $2 == b && $3 == a && $4 == p && $5 == n && $6 == s && $7 == z {found=1}
    END {exit !found}
  ' "$COMMON_FIREWALL_REGISTRY"; then
    return 0
  fi
  created="$(date '+%Y-%m-%dT%H:%M:%S%z')"
  id="$(date +%s)-$$-${RANDOM}"
  printf '%s|%s|%s|%s|%s|%s|%s|%s\n' \
    "$id" "$backend" "$action" "$protocol" "$port" "$source" "$zone" "$created" \
    >> "$COMMON_FIREWALL_REGISTRY" || return 1
  chmod 600 "$COMMON_FIREWALL_REGISTRY" 2>/dev/null || true
}

common_firewall_registry_count() {
  if [[ -f "$COMMON_FIREWALL_REGISTRY" ]] && \
     [[ "$(sed -n '1p' "$COMMON_FIREWALL_REGISTRY" 2>/dev/null || true)" == "$COMMON_FIREWALL_MARKER" ]]; then
    awk 'NR > 1 && NF {count++} END {print count + 0}' "$COMMON_FIREWALL_REGISTRY"
  else
    printf '0\n'
  fi
}

common_firewall_action_text() {
  case "${1:-}" in
    allow-port) printf '放行端口\n' ;;
    allow-source-port) printf '来源放行\n' ;;
    deny-source) printf '封禁来源\n' ;;
    *) printf '未知\n' ;;
  esac
}

common_firewall_registry_list() {
  local id="" backend="" action="" protocol="" port="" source="" zone="" created=""
  if [[ ! -f "$COMMON_FIREWALL_REGISTRY" ]] || \
     [[ "$(sed -n '1p' "$COMMON_FIREWALL_REGISTRY" 2>/dev/null || true)" != "$COMMON_FIREWALL_MARKER" ]]; then
    info "本脚本尚未创建防火墙规则"
    return 0
  fi
  printf '%-24s %-10s %-10s %-5s %-11s %-25s %s\n' "ID" "管理器" "动作" "协议" "端口" "来源" "区域"
  while IFS='|' read -r id backend action protocol port source zone created; do
    [[ -n "$id" && "$id" != \#* ]] || continue
    printf '%-24s %-10s %-10s %-5s %-11s %-25s %s\n' \
      "$id" "$backend" "$(common_firewall_action_text "$action")" "$protocol" "$port" "$source" "$zone"
  done < "$COMMON_FIREWALL_REGISTRY"
}

common_firewall_ufw_apply_rule() {
  local action="$1" protocol="$2" port="$3" source="$4"
  local ufw_port="" output="" rc=0
  COMMON_FIREWALL_CREATED=0
  case "$action" in
    allow-port)
      common_firewall_valid_protocol "$protocol" || return 1
      ufw_port="$(common_firewall_ufw_port_spec "$port")" || return 1
      output="$(LC_ALL=C ufw allow "${ufw_port}/${protocol}" 2>&1)" || rc=$?
      ;;
    allow-source-port)
      common_firewall_valid_protocol "$protocol" || return 1
      valid_ip_or_cidr "$source" || return 1
      ufw_port="$(common_firewall_ufw_port_spec "$port")" || return 1
      output="$(LC_ALL=C ufw allow proto "$protocol" from "$source" to any port "$ufw_port" 2>&1)" || rc=$?
      ;;
    deny-source)
      valid_ip_or_cidr "$source" || return 1
      output="$(LC_ALL=C ufw prepend deny from "$source" 2>&1)" || rc=$?
      ;;
    *) return 1 ;;
  esac
  if (( rc != 0 )); then
    [[ -n "$output" ]] && warn "$output"
    return "$rc"
  fi
  if grep -qi 'Skipping adding existing rule' <<< "$output"; then
    COMMON_FIREWALL_CREATED=0
  else
    COMMON_FIREWALL_CREATED=1
  fi
}

common_firewall_ufw_remove_rule() {
  local action="$1" protocol="$2" port="$3" source="$4"
  local ufw_port="" output="" rc=0
  case "$action" in
    allow-port)
      common_firewall_valid_protocol "$protocol" || return 1
      ufw_port="$(common_firewall_ufw_port_spec "$port")" || return 1
      output="$(LC_ALL=C ufw --force delete allow "${ufw_port}/${protocol}" 2>&1)" || rc=$?
      ;;
    allow-source-port)
      common_firewall_valid_protocol "$protocol" || return 1
      valid_ip_or_cidr "$source" || return 1
      ufw_port="$(common_firewall_ufw_port_spec "$port")" || return 1
      output="$(LC_ALL=C ufw --force delete allow proto "$protocol" from "$source" to any port "$ufw_port" 2>&1)" || rc=$?
      ;;
    deny-source)
      valid_ip_or_cidr "$source" || return 1
      output="$(LC_ALL=C ufw --force delete deny from "$source" 2>&1)" || rc=$?
      ;;
    *) return 1 ;;
  esac
  if (( rc != 0 )) && ! grep -Eqi 'non-existent|could not find|not found' <<< "$output"; then
    [[ -n "$output" ]] && warn "$output"
    return "$rc"
  fi
}

common_firewall_firewalld_rich_rule() {
  local action="$1" protocol="$2" port="$3" source="$4" family=""
  family="$(common_firewall_source_family "$source")" || return 1
  case "$action" in
    allow-source-port)
      common_firewall_valid_protocol "$protocol" || return 1
      port="$(common_firewall_normalize_port_spec "$port")" || return 1
      printf 'rule family="%s" source address="%s" port port="%s" protocol="%s" accept\n' \
        "$family" "$source" "$port" "$protocol"
      ;;
    deny-source)
      printf 'rule family="%s" source address="%s" drop\n' "$family" "$source"
      ;;
    *) return 1 ;;
  esac
}

common_firewall_firewalld_apply_rule() {
  local action="$1" protocol="$2" port="$3" source="$4" zone="$5"
  local kind="" value="" rich_rule="" permanent_created=0
  COMMON_FIREWALL_CREATED=0
  [[ "$zone" =~ ^[A-Za-z0-9_.-]{1,32}$ ]] || return 1
  case "$action" in
    allow-port)
      common_firewall_valid_protocol "$protocol" || return 1
      port="$(common_firewall_normalize_port_spec "$port")" || return 1
      kind="port"
      value="${port}/${protocol}"
      ;;
    allow-source-port|deny-source)
      rich_rule="$(common_firewall_firewalld_rich_rule "$action" "$protocol" "$port" "$source")" || return 1
      kind="rich-rule"
      value="$rich_rule"
      ;;
    *) return 1 ;;
  esac

  if common_firewall_firewalld_active; then
    if ! firewall-cmd --permanent --zone="$zone" "--query-${kind}=${value}" >/dev/null 2>&1; then
      firewall-cmd --permanent --zone="$zone" "--add-${kind}=${value}" >/dev/null 2>&1 || return 1
      permanent_created=1
      COMMON_FIREWALL_CREATED=1
    fi
    if ! firewall-cmd --zone="$zone" "--query-${kind}=${value}" >/dev/null 2>&1; then
      if ! firewall-cmd --zone="$zone" "--add-${kind}=${value}" >/dev/null 2>&1; then
        if (( permanent_created == 1 )); then
          firewall-cmd --permanent --zone="$zone" "--remove-${kind}=${value}" >/dev/null 2>&1 || true
        fi
        return 1
      fi
    fi
    return 0
  fi

  have_cmd firewall-offline-cmd || return 1
  if firewall-offline-cmd --zone="$zone" "--query-${kind}=${value}" >/dev/null 2>&1; then
    COMMON_FIREWALL_CREATED=0
    return 0
  fi
  firewall-offline-cmd --zone="$zone" "--add-${kind}=${value}" >/dev/null 2>&1 || return 1
  COMMON_FIREWALL_CREATED=1
}

common_firewall_firewalld_remove_rule() {
  local action="$1" protocol="$2" port="$3" source="$4" zone="$5"
  local kind="" value="" rich_rule="" rc=0
  [[ "$zone" =~ ^[A-Za-z0-9_.-]{1,32}$ ]] || return 1
  case "$action" in
    allow-port)
      common_firewall_valid_protocol "$protocol" || return 1
      port="$(common_firewall_normalize_port_spec "$port")" || return 1
      kind="port"
      value="${port}/${protocol}"
      ;;
    allow-source-port|deny-source)
      rich_rule="$(common_firewall_firewalld_rich_rule "$action" "$protocol" "$port" "$source")" || return 1
      kind="rich-rule"
      value="$rich_rule"
      ;;
    *) return 1 ;;
  esac
  if common_firewall_firewalld_active; then
    if firewall-cmd --zone="$zone" "--query-${kind}=${value}" >/dev/null 2>&1; then
      firewall-cmd --zone="$zone" "--remove-${kind}=${value}" >/dev/null 2>&1 || rc=1
    fi
    if firewall-cmd --permanent --zone="$zone" "--query-${kind}=${value}" >/dev/null 2>&1; then
      firewall-cmd --permanent --zone="$zone" "--remove-${kind}=${value}" >/dev/null 2>&1 || rc=1
    fi
  elif have_cmd firewall-offline-cmd; then
    if firewall-offline-cmd --zone="$zone" "--query-${kind}=${value}" >/dev/null 2>&1; then
      firewall-offline-cmd --zone="$zone" "--remove-${kind}=${value}" >/dev/null 2>&1 || rc=1
    fi
  else
    return 1
  fi
  return "$rc"
}

common_firewall_apply_rule() {
  local backend="$1" action="$2" protocol="$3" port="$4" source="$5" zone="$6"
  COMMON_FIREWALL_CREATED=0
  case "$backend" in
    ufw)
      have_cmd ufw || return 1
      common_firewall_ufw_apply_rule "$action" "$protocol" "$port" "$source" || return 1
      ;;
    firewalld)
      common_firewall_firewalld_apply_rule "$action" "$protocol" "$port" "$source" "$zone" || return 1
      ;;
    *) return 1 ;;
  esac
  if (( COMMON_FIREWALL_CREATED == 1 )); then
    if ! common_firewall_registry_add "$backend" "$action" "$protocol" "$port" "$source" "$zone"; then
      warn "规则已添加，但写入脚本记录失败；正在回滚该规则"
      if [[ "$backend" == "ufw" ]]; then
        common_firewall_ufw_remove_rule "$action" "$protocol" "$port" "$source" || true
      else
        common_firewall_firewalld_remove_rule "$action" "$protocol" "$port" "$source" "$zone" || true
      fi
      return 1
    fi
  fi
}

common_firewall_remove_rule_by_id() {
  local id="${1:-}" line="" backend="" action="" protocol="" port="" source="" zone="" created=""
  local tmp=""
  [[ "$id" =~ ^[0-9]+-[0-9]+-[0-9]+$ ]] || { warn "规则 ID 格式无效"; return 1; }
  [[ ! -L "$COMMON_FIREWALL_REGISTRY" ]] || { warn "规则记录路径是符号链接，拒绝操作"; return 1; }
  [[ -f "$COMMON_FIREWALL_REGISTRY" ]] || { warn "没有脚本规则记录"; return 1; }
  [[ "$(sed -n '1p' "$COMMON_FIREWALL_REGISTRY" 2>/dev/null || true)" == "$COMMON_FIREWALL_MARKER" ]] || {
    warn "规则记录文件校验失败"
    return 1
  }
  line="$(awk -F '|' -v id="$id" '$1 == id {print; exit}' "$COMMON_FIREWALL_REGISTRY")"
  [[ -n "$line" ]] || { warn "没有找到规则 ID：${id}"; return 1; }
  IFS='|' read -r id backend action protocol port source zone created <<< "$line"
  case "$backend" in
    ufw)
      have_cmd ufw || { warn "UFW 不存在，无法精确删除规则"; return 1; }
      common_firewall_ufw_remove_rule "$action" "$protocol" "$port" "$source" || return 1
      ;;
    firewalld)
      common_firewall_firewalld_remove_rule "$action" "$protocol" "$port" "$source" "$zone" || return 1
      ;;
    *) warn "记录中的防火墙类型无效"; return 1 ;;
  esac
  tmp="$(mktemp "${COMMON_FIREWALL_REGISTRY}.tmp.XXXXXX")" || return 1
  if ! awk -F '|' -v id="$id" '$1 != id' "$COMMON_FIREWALL_REGISTRY" > "$tmp"; then
    rm -f "$tmp"
    return 1
  fi
  chmod 600 "$tmp" 2>/dev/null || true
  if ! mv -f "$tmp" "$COMMON_FIREWALL_REGISTRY"; then
    rm -f "$tmp"
    return 1
  fi
  ok "已删除脚本规则：${id}"
}

common_firewall_require_active_backend() {
  local backend="" rc=0 installed="" setup_choice=""
  COMMON_FIREWALL_BACKEND=""
  backend="$(common_firewall_active_backend)" || rc=$?
  case "$rc:$backend" in
    0:ufw|0:firewalld)
      COMMON_FIREWALL_BACKEND="$backend"
      return 0
      ;;
    2:conflict)
      warn "UFW 与 firewalld 同时处于启用状态，已拒绝修改"
      info "请先人工确认实际规则来源，再停用其中一个管理器"
      return 2
      ;;
    *)
      installed="$(common_firewall_installed_managers 2>/dev/null || true)"
      if [[ -n "$installed" ]]; then
        warn "${installed} 已安装，但当前尚未启用"
      else
        warn "本机尚未安装 UFW/firewalld"
      fi
      info "安全流程会先放行 SSH 与所选服务，再安装或启用防火墙"
      if [[ "${RUN_MODE:-menu}" != "menu" ]]; then
        info "请进入“常用防火墙”，选择 [2] 安装并安全启用"
        return 1
      fi
      read_tty setup_choice "是否立即进入安全安装/启用流程？[Y/n] > " "y"
      case "${setup_choice,,}" in
        y|yes|是)
          common_firewall_safe_enable || return $?
          rc=0
          backend="$(common_firewall_active_backend)" || rc=$?
          if (( rc == 0 )) && [[ "$backend" == "ufw" || "$backend" == "firewalld" ]]; then
            COMMON_FIREWALL_BACKEND="$backend"
            ok "防火墙已就绪，继续执行刚才选择的功能"
            return 0
          fi
          info "防火墙仍未启用，已取消当前操作"
          return 1
          ;;
        n|no|否)
          info "已取消；需要时可选择 [2] 安装并安全启用"
          return 1
          ;;
        *)
          warn "请输入 y 或 n"
          return 1
          ;;
      esac
      ;;
  esac
}

common_firewall_protocols_from_choice() {
  case "${1,,}" in
    1|tcp) printf 'tcp\n' ;;
    2|udp) printf 'udp\n' ;;
    3|both|all|tcp+udp) printf 'tcp\nudp\n' ;;
    *) return 1 ;;
  esac
}

common_firewall_add_port_ui() {
  local backend="" port="" choice="" protocol="" zone="-" added=0 existing=0
  common_firewall_require_active_backend || return $?
  backend="$COMMON_FIREWALL_BACKEND"
  read_tty port "端口或范围（如 443、8000-8100）> " ""
  port="$(common_firewall_normalize_port_spec "$port")" || { warn "端口必须是 1-65535，范围起点不能大于终点"; return 1; }
  echo "  1) TCP"
  echo "  2) UDP"
  echo "  3) TCP + UDP"
  read_tty choice "协议（默认 TCP）> " "1"
  common_firewall_protocols_from_choice "$choice" >/dev/null || { warn "协议选项无效"; return 1; }
  if [[ "$backend" == "firewalld" ]]; then
    zone="$(common_firewall_firewalld_zone)" || { warn "无法确定 firewalld 入站区域"; return 1; }
  fi
  while IFS= read -r protocol; do
    common_firewall_apply_rule "$backend" allow-port "$protocol" "$port" - "$zone" || return 1
    if (( COMMON_FIREWALL_CREATED == 1 )); then
      ok "已放行 ${port}/${protocol}"
      added=$((added + 1))
    else
      info "${port}/${protocol} 已存在，未接管原规则"
      existing=$((existing + 1))
    fi
  done < <(common_firewall_protocols_from_choice "$choice")
  (( added + existing > 0 ))
}

common_firewall_add_source_port_ui() {
  local backend="" source="" port="" choice="" protocol="" zone="-" added=0 existing=0
  common_firewall_require_active_backend || return $?
  backend="$COMMON_FIREWALL_BACKEND"
  read_tty source "允许的来源 IP/CIDR > " ""
  valid_ip_or_cidr "$source" || { warn "来源必须是有效 IPv4、IPv6 或 CIDR"; return 1; }
  read_tty port "端口或范围（如 22、8000-8100）> " ""
  port="$(common_firewall_normalize_port_spec "$port")" || { warn "端口格式无效"; return 1; }
  echo "  1) TCP"
  echo "  2) UDP"
  echo "  3) TCP + UDP"
  read_tty choice "协议（默认 TCP）> " "1"
  common_firewall_protocols_from_choice "$choice" >/dev/null || { warn "协议选项无效"; return 1; }
  if [[ "$backend" == "firewalld" ]]; then
    zone="$(common_firewall_firewalld_zone)" || { warn "无法确定 firewalld 入站区域"; return 1; }
  fi
  while IFS= read -r protocol; do
    common_firewall_apply_rule "$backend" allow-source-port "$protocol" "$port" "$source" "$zone" || return 1
    if (( COMMON_FIREWALL_CREATED == 1 )); then
      ok "已允许 ${source} 访问 ${port}/${protocol}"
      added=$((added + 1))
    else
      info "相同规则已存在，未接管原规则"
      existing=$((existing + 1))
    fi
  done < <(common_firewall_protocols_from_choice "$choice")
  (( added + existing > 0 ))
}

common_firewall_block_source_ui() {
  local backend="" source="" zone="-" ssh_client="" confirm="BLOCK"
  common_firewall_require_active_backend || return $?
  backend="$COMMON_FIREWALL_BACKEND"
  read_tty source "要封禁的来源 IP/CIDR > " ""
  valid_ip_or_cidr "$source" || { warn "来源必须是有效 IPv4、IPv6 或 CIDR"; return 1; }
  ssh_client="${SSH_CONNECTION:-}"
  ssh_client="${ssh_client%% *}"
  if [[ -n "$ssh_client" ]] && common_firewall_source_contains_ip "$source" "$ssh_client"; then
    warn "该范围包含当前 SSH 客户端 ${ssh_client}，为避免立即失联已拒绝"
    info "如确需封禁，请从 VPS 控制台操作"
    return 2
  fi
  if [[ "$source" == "0.0.0.0/0" || "$source" == "::/0" ]]; then
    warn "该网段代表整个地址族，将封禁几乎所有入站来源"
    confirm="BLOCK-ALL"
  fi
  warn "该规则将丢弃此来源访问本机的流量"
  confirm_word "$confirm" "确认封禁请输入 ${confirm} > " || { info "已取消"; return 0; }
  if [[ "$backend" == "firewalld" ]]; then
    zone="$(common_firewall_firewalld_zone)" || { warn "无法确定 firewalld 入站区域"; return 1; }
  fi
  common_firewall_apply_rule "$backend" deny-source - - "$source" "$zone" || return 1
  if (( COMMON_FIREWALL_CREATED == 1 )); then
    ok "已封禁：${source}"
  else
    info "相同规则已存在，未接管原规则"
  fi
}

common_firewall_delete_rules_ui() {
  local choice="" id="" rc=0 count=0
  local -a ids=()
  menu_header "脚本防火墙规则" "只删除本脚本确实创建并记录的规则"
  common_firewall_registry_list
  count="$(common_firewall_registry_count)"
  (( count > 0 )) || return 0
  echo
  echo "  1) 按 ID 删除一条"
  echo "  2) 删除全部脚本规则"
  read_tty choice "请选择 > " ""
  case "$choice" in
    1)
      read_tty id "输入规则 ID > " ""
      confirm_word "DELETE" "确认删除请输入 DELETE > " || { info "已取消"; return 0; }
      common_firewall_remove_rule_by_id "$id"
      ;;
    2)
      confirm_word "CLEAR" "确认删除全部脚本规则请输入 CLEAR > " || { info "已取消"; return 0; }
      mapfile -t ids < <(awk -F '|' 'NR > 1 && NF {print $1}' "$COMMON_FIREWALL_REGISTRY")
      for id in "${ids[@]}"; do
        [[ -n "$id" ]] || continue
        common_firewall_remove_rule_by_id "$id" || rc=1
      done
      (( rc == 0 )) && ok "全部脚本规则已删除"
      return "$rc"
      ;;
    *) warn "无效选项"; return 1 ;;
  esac
}

common_firewall_show_preserved_ports() {
  local entries="$1" protocol="" port=""
  printf '%-8s %s\n' "协议" "端口"
  while IFS='|' read -r protocol port; do
    [[ -n "$protocol" && -n "$port" ]] || continue
    printf '%-8s %s\n' "$protocol" "$port"
  done <<< "$entries"
}

common_firewall_install_backend() {
  local backend="$1"
  case "$backend" in
    ufw)
      have_cmd ufw || pkg_install ufw
      have_cmd ufw || { warn "UFW 安装失败"; return 1; }
      ;;
    firewalld)
      have_cmd firewall-cmd || pkg_install firewalld
      have_cmd firewall-cmd || { warn "firewalld 安装失败"; return 1; }
      have_cmd firewall-offline-cmd || { warn "缺少 firewall-offline-cmd，无法在启动前安全预置 SSH 规则"; return 1; }
      ;;
    *) return 1 ;;
  esac
}

common_firewall_safe_enable() {
  local active="" active_rc=0 backend="" preset_choice="" preset="listeners"
  local entries="" protocol="" port="" zone="-" existing_config="" existing_zone=""
  local netfilter_risk="none" confirm_token="ENABLE" needs_netfilter_backup=0
  active="$(common_firewall_active_backend)" || active_rc=$?
  if (( active_rc == 0 )); then
    info "防火墙已经启用：${active}"
    return 0
  fi
  if (( active_rc == 2 )); then
    warn "UFW 与 firewalld 同时启用，拒绝继续"
    return 2
  fi
  netfilter_risk="$(common_firewall_netfilter_risk)"
  case "$netfilter_risk" in
    forwarding)
      warn "检测到已有转发/NAT/输出规则（常见于 Docker、Podman 或代理服务）"
      common_firewall_netfilter_show_inventory
      info "这些规则不会被清空或接管；确认启用后将先备份，再以共存方式继续"
      needs_netfilter_backup=1
      ;;
    input)
      warn "检测到会直接影响本机 INPUT 的既有规则"
      common_firewall_netfilter_show_inventory
      info "脚本不会清空或改写这些规则；新防火墙将与它们同时生效"
      warn "多套入站规则的最终效果取决于链优先级，请保持 SSH 会话并准备 VPS 控制台"
      confirm_token="COEXIST"
      needs_netfilter_backup=1
      ;;
    unknown)
      warn "发现无法完整解析的 netfilter 表，无法自动判断是否影响 INPUT"
      common_firewall_netfilter_show_inventory
      info "脚本不会清空或接管这些规则"
      confirm_token="COEXIST"
      needs_netfilter_backup=1
      ;;
  esac
  backend="$(common_firewall_choose_install_backend)" || {
    warn "当前发行版无法自动选择受支持的防火墙管理器"
    return 1
  }

  menu_header "安装并安全启用防火墙" "先放行 SSH 与所选服务，再启用默认入站保护"
  menu_section "启用时保留"
  menu_item "1" "SSH 端口" "最小开放范围"
  menu_item "2" "SSH + 网站端口" "额外保留 TCP/80、TCP/443"
  menu_item "3" "SSH + 当前非回环监听" "推荐，避免影响已安装服务"
  read_tty preset_choice "请选择（默认 3）> " "3"
  case "$preset_choice" in
    1) preset="ssh" ;;
    2) preset="web" ;;
    3) preset="listeners" ;;
    *) warn "无效选项"; return 1 ;;
  esac
  entries="$(common_firewall_preserved_ports "$preset")"
  [[ -n "$entries" ]] || { warn "没有识别到 SSH 端口，拒绝启用以避免失联"; return 1; }
  menu_section "将预先放行"
  common_firewall_show_preserved_ports "$entries"
  echo
  print_kv "管理器" "$backend"
  if [[ "$backend" == "ufw" ]] && have_cmd ufw; then
    existing_config="$(LC_ALL=C ufw show added 2>/dev/null || true)"
    if grep -q '^ufw ' <<< "$existing_config"; then
      warn "UFW 中已有永久规则；启用后这些规则也会生效"
      printf '%s\n' "$existing_config" | sed -n '1,60p'
    fi
  elif [[ "$backend" == "firewalld" ]] && have_cmd firewall-offline-cmd; then
    existing_zone="$(common_firewall_firewalld_zone 2>/dev/null || true)"
    if [[ -n "$existing_zone" ]]; then
      existing_config="$(firewall-offline-cmd --zone="$existing_zone" --list-all 2>/dev/null || true)"
      if [[ -n "$existing_config" ]]; then
        info "firewalld 区域 ${existing_zone} 的现有永久配置也会保留"
        printf '%s\n' "$existing_config" | sed -n '1,40p'
      fi
    fi
  fi
  warn "启用防火墙可能影响未显示的服务；请保持当前 SSH 会话并准备 VPS 控制台"
  if [[ "$confirm_token" == "COEXIST" ]]; then
    warn "输入 COEXIST 表示保留现有规则，并确认同时启用新的防火墙管理器"
    confirm_word "COEXIST" "确认共存并启用请输入 COEXIST > " || { info "已取消，原规则未改动"; return 0; }
  else
    confirm_word "ENABLE" "确认启用请输入 ENABLE > " || { info "已取消"; return 0; }
  fi
  if (( needs_netfilter_backup == 1 )); then
    common_firewall_backup_netfilter || return 1
  fi

  common_firewall_install_backend "$backend" || return 1
  if [[ "$backend" == "ufw" ]]; then
    if common_firewall_ufw_active; then
      warn "确认期间 UFW 状态已变为启用，已取消以避免覆盖并发修改"
      return 2
    fi
    LC_ALL=C ufw default deny incoming >/dev/null 2>&1 || { warn "设置 UFW 入站策略失败"; return 1; }
    LC_ALL=C ufw default allow outgoing >/dev/null 2>&1 || { warn "设置 UFW 出站策略失败"; return 1; }
  else
    zone="$(common_firewall_firewalld_zone)" || { warn "无法确定 firewalld 入站区域"; return 1; }
    local zone_target=""
    if common_firewall_firewalld_active; then
      zone_target="$(firewall-cmd --zone="$zone" --get-target 2>/dev/null || true)"
    else
      zone_target="$(firewall-offline-cmd --zone="$zone" --get-target 2>/dev/null || true)"
    fi
    if [[ "$zone" == "trusted" || "${zone_target^^}" == "ACCEPT" ]]; then
      warn "firewalld 区域 ${zone} 当前允许全部入站，拒绝以“一键安全”方式启用"
      info "请先人工调整区域目标，再重新执行"
      return 2
    fi
  fi

  while IFS='|' read -r protocol port; do
    [[ -n "$protocol" && -n "$port" ]] || continue
    if ! common_firewall_apply_rule "$backend" allow-port "$protocol" "$port" - "$zone"; then
      warn "预置 ${port}/${protocol} 失败，防火墙尚未启用"
      return 1
    fi
  done <<< "$entries"

  if [[ "$backend" == "ufw" ]]; then
    if ! LC_ALL=C ufw --force enable >/dev/null 2>&1; then
      warn "UFW 启用失败；已写入的放行规则仍保留但防火墙未启用"
      return 1
    fi
    common_firewall_ufw_active || { warn "UFW 命令完成但状态仍不是 active"; return 1; }
  else
    if is_systemd; then
      systemctl enable --now firewalld >/dev/null 2>&1 || { warn "firewalld 启动失败"; return 1; }
    elif have_cmd service; then
      service firewalld start >/dev/null 2>&1 || { warn "firewalld 启动失败"; return 1; }
    else
      warn "没有可用的服务管理器，firewalld 未启动"
      return 1
    fi
    common_firewall_firewalld_active || { warn "firewalld 启动后未进入 running 状态"; return 1; }
  fi
  ok "防火墙已安全启用：${backend}"
  info "请立即新开一个 SSH 会话验证登录；当前会话先不要退出"
}

common_firewall_container_warning() {
  if have_cmd docker || have_cmd podman || \
     ip link show docker0 >/dev/null 2>&1 || ip link show podman0 >/dev/null 2>&1; then
    warn "检测到容器环境：Docker/Podman 发布端口可能使用独立转发规则"
    info "请同时检查容器端口映射；不要仅凭 UFW/firewalld 状态判断容器端口已被拦截"
    return 0
  fi
  return 1
}

common_firewall_status() {
  local backend="" rc=0 zone="" listeners="" rule_count="" installed="" netfilter_risk="none"
  menu_header "防火墙状态" "管理器 · 入站规则 · 非回环监听 · 冲突诊断"
  backend="$(common_firewall_active_backend)" || rc=$?
  menu_section "管理状态"
  case "$rc:$backend" in
    0:ufw)
      print_kv "当前管理器" "UFW（已启用）"
      LC_ALL=C ufw status verbose 2>/dev/null || true
      echo
      LC_ALL=C ufw status numbered 2>/dev/null | sed -n '1,100p' || true
      ;;
    0:firewalld)
      zone="$(common_firewall_firewalld_zone 2>/dev/null || echo public)"
      print_kv "当前管理器" "firewalld（已启用）"
      print_kv "当前入站区域" "$zone"
      firewall-cmd --zone="$zone" --list-all 2>/dev/null || true
      ;;
    2:conflict)
      warn "UFW 与 firewalld 同时启用：规则可能互相覆盖"
      info "在明确规则来源前，脚本不会修改任何一方"
      ;;
    *)
      installed="$(common_firewall_installed_managers 2>/dev/null || true)"
      if [[ -n "$installed" ]]; then
        print_kv "当前管理器" "${installed}（已安装但未启用）"
        info "选择 [2] 可在保留 SSH 与现有服务后安全启用"
      else
        print_kv "当前管理器" "未安装"
        warn "尚未安装 UFW/firewalld"
        info "返回后选择 [2]，脚本会自动选择、安装并安全启用"
      fi
      netfilter_risk="$(common_firewall_netfilter_risk)"
      case "$netfilter_risk" in
        input)
          warn "现有规则会影响本机 INPUT；启用新管理器前需要确认共存"
          common_firewall_netfilter_show_inventory
          ;;
        forwarding)
          info "现有规则仅涉及转发/NAT/输出，可在备份后与新防火墙共存"
          common_firewall_netfilter_show_inventory
          ;;
        unknown)
          warn "存在无法完整解析的 netfilter 规则"
          common_firewall_netfilter_show_inventory
          ;;
        *) info "未发现明显的自定义 netfilter 规则" ;;
      esac
      if have_cmd nft; then
        echo -e "${c_dim}nftables 表：${c_reset}"
        nft list tables 2>/dev/null | sed -n '1,30p' || true
      fi
      ;;
  esac

  menu_section "本脚本创建的规则"
  rule_count="$(common_firewall_registry_count)"
  print_kv "记录数量" "$rule_count"
  common_firewall_registry_list

  menu_section "非回环监听端口"
  listeners="$(common_firewall_public_listeners)"
  if [[ -n "$listeners" ]]; then
    common_firewall_show_preserved_ports "$listeners"
  else
    info "未发现非回环 TCP/UDP 监听端口，或缺少 ss/netstat"
  fi

  menu_section "边界提醒"
  common_firewall_container_warning || true
  info "VPS 服务商安全组/云防火墙是另一层策略，需要单独检查"
  info "本模块不修改转发/NAT，不清空 nftables/iptables，也不删除非脚本规则"
}

common_firewall_logging_ui() {
  local backend="" choice=""
  common_firewall_require_active_backend || return $?
  backend="$COMMON_FIREWALL_BACKEND"
  echo "  1) 开启丢弃日志（UFW low / firewalld 单播）"
  echo "  2) 关闭防火墙日志"
  read_tty choice "请选择 > " ""
  case "$backend:$choice" in
    ufw:1) LC_ALL=C ufw logging low >/dev/null 2>&1 || return 1 ;;
    ufw:2) LC_ALL=C ufw logging off >/dev/null 2>&1 || return 1 ;;
    firewalld:1) firewall-cmd --set-log-denied=unicast >/dev/null 2>&1 || return 1 ;;
    firewalld:2) firewall-cmd --set-log-denied=off >/dev/null 2>&1 || return 1 ;;
    *) warn "无效选项"; return 1 ;;
  esac
  ok "防火墙日志设置已更新"
  info "日志可能写入 journal、kern.log 或系统防火墙日志，取决于发行版配置"
  if [[ "$choice" == "1" ]]; then
    warn "遭遇扫描或攻击时日志会增长，请同时关注磁盘空间"
  fi
}

common_firewall_disable_ui() {
  local backend="" rc=0 installed=""
  backend="$(common_firewall_active_backend)" || rc=$?
  if (( rc == 2 )); then
    warn "UFW 与 firewalld 同时启用，拒绝自动停用其中一方"
    return 2
  fi
  if (( rc != 0 )); then
    installed="$(common_firewall_installed_managers 2>/dev/null || true)"
    if [[ -n "$installed" ]]; then
      info "${installed} 已安装但当前未启用，无需停用"
    else
      info "本机尚未安装 UFW/firewalld，无需停用"
    fi
    return 0
  fi
  warn "停用 ${backend} 后，本机入站保护将不再生效"
  warn "永久规则和脚本记录会保留，重新启用后可继续使用"
  confirm_word "DISABLE" "确认停用请输入 DISABLE > " || { info "已取消"; return 0; }
  case "$backend" in
    ufw)
      LC_ALL=C ufw --force disable >/dev/null 2>&1 || { warn "UFW 停用失败"; return 1; }
      ;;
    firewalld)
      if is_systemd; then
        systemctl disable --now firewalld >/dev/null 2>&1 || { warn "firewalld 停用失败"; return 1; }
      elif have_cmd service; then
        service firewalld stop >/dev/null 2>&1 || { warn "firewalld 停用失败"; return 1; }
      else
        warn "没有可用的服务管理器"
        return 1
      fi
      ;;
  esac
  ok "防火墙已停用：${backend}"
}

common_firewall_menu() {
  while true; do
    local state=""
    state="$(common_firewall_state_summary)"
    menu_header "常用防火墙" "当前：${state} · 规则共存保护 · 精确规则管理"
    common_firewall_menu_notice
    menu_section "状态与启用"
    menu_item "1" "状态与安全诊断" "规则、监听端口、冲突与容器提示"
    menu_item "2" "安装并安全启用" "保留 SSH/现有服务，识别并备份原规则"
    menu_section "常用规则"
    menu_item "3" "放行端口" "TCP、UDP、单端口或端口范围"
    menu_item "4" "仅指定来源放行" "IPv4/IPv6/CIDR + 端口"
    menu_item "5" "封禁 IP 或网段" "丢弃该来源访问本机的流量"
    menu_item "6" "关闭端口 / 解封来源" "查看并只删除本脚本创建的精确规则"
    menu_section "运行设置"
    menu_item "7" "防火墙日志" "开启基础丢弃日志或关闭日志"
    menu_item "8" "停用防火墙" "保留永久规则，需要 DISABLE 确认"
    menu_back_item
    local c=""
    read_tty c "请输入编号 > " ""
    case "$c" in
      1) common_firewall_status || true; pause_up ;;
      2) common_firewall_safe_enable || true; pause_up ;;
      3) common_firewall_add_port_ui || true; pause_up ;;
      4) common_firewall_add_source_port_ui || true; pause_up ;;
      5) common_firewall_block_source_ui || true; pause_up ;;
      6) common_firewall_delete_rules_ui || true; pause_up ;;
      7) common_firewall_logging_ui || true; pause_up ;;
      8) common_firewall_disable_ui || true; pause_up ;;
      0|q|Q) return 0 ;;
      *) warn "无效选项"; pause_up ;;
    esac
  done
}

security_overview() {
  menu_header "安全防护状态" "SSH · Fail2Ban · 常用防火墙"
  menu_section "SSH"
  print_kv "当前端口" "$(ssh_current_ports 2>/dev/null || echo 22)"
  if have_cmd sshd; then
    sshd -T 2>/dev/null | grep -Ei '^(passwordauthentication|permitrootlogin|pubkeyauthentication|maxauthtries|logingracetime) ' || true
  else
    warn "未找到 sshd"
  fi
  menu_section "Fail2Ban"
  if have_cmd fail2ban-client; then
    fail2ban-client ping 2>/dev/null || warn "Fail2Ban 服务未响应"
    fail2ban-client status sshd 2>/dev/null || warn "sshd jail 未运行"
  else
    info "Fail2Ban 未安装"
  fi
  menu_section "防火墙"
  local firewall_backend="" firewall_rc=0 firewall_installed=""
  firewall_backend="$(common_firewall_active_backend)" || firewall_rc=$?
  case "$firewall_rc:$firewall_backend" in
    0:ufw) ok "UFW 已启用" ;;
    0:firewalld) ok "firewalld 已启用" ;;
    2:conflict) warn "UFW 与 firewalld 同时启用" ;;
    *)
      firewall_installed="$(common_firewall_installed_managers 2>/dev/null || true)"
      if [[ -n "$firewall_installed" ]]; then
        info "${firewall_installed} 已安装但未启用"
      else
        warn "尚未安装 UFW/firewalld"
      fi
      ;;
  esac
  print_kv "脚本规则" "$(common_firewall_registry_count) 条"
}

security_menu() {
  while true; do
    menu_header "安全防护" "SSH 登录 · 防爆破 · 常用防火墙"
    menu_item "1" "安全状态总览" "SSH、Fail2Ban 与防火墙状态"
    menu_item "2" "SSH 安全工具" "用户、认证方式、端口与恢复"
    menu_item "3" "Fail2Ban SSH 防爆破" "安装、白名单、封禁与解封"
    menu_item "4" "常用防火墙" "安全启用、端口、来源、封禁与日志"
    menu_back_item
    local c=""
    read_tty c "请输入编号 > " ""
    case "$c" in
      1) security_overview || true; pause_up ;;
      2) ssh_menu ;;
      3) fail2ban_menu ;;
      4) common_firewall_menu ;;
      0|q|Q) return 0 ;;
      *) warn "无效选项"; pause_up ;;
    esac
  done
}

# ---------------- 一键还原 ----------------
restore_all() {
  local ifc; ifc="$(default_iface)"
  if tcpfit_tuning_active; then
    warn "检测到 tcpfit 动态调优正在生效，本次综合还原已取消"
    info "动态参数有独立原始快照；请先进入【TCP / BBR → 动态实测调优】完整回滚"
    info "回滚完成后再运行本功能，避免两套恢复逻辑互相覆盖"
    return 1
  fi
  info "配置还原：恢复网络/TCP/SSH（不影响 Swap、Fail2Ban、轻量建站、用户、时区和 cloud-init）"

  # 必须先读取地址池配置并删除已挂载的 /128，再移除配置文件。
  ipv6_rand_disable || true
  ipv6_pool_disable || true

  rm -f "$TUNE_SYSCTL_FILE" "$DMIT_TCP_DEFAULT_FILE" >/dev/null 2>&1 || true
  rm -f "$IPV6_SYSCTL_FILE" "$IPV6_FIX_SYSCTL_FILE" >/dev/null 2>&1 || true

  if [[ -f "${BACKUP_BASE}/gai.conf.orig" ]]; then
    cp -a "${BACKUP_BASE}/gai.conf.orig" "$GAI_CONF" 2>/dev/null || true
  else
    if [[ -f "$GAI_CONF" ]]; then
      sed -i -E '/^[[:space:]]*precedence[[:space:]]+::ffff:0:0\/96[[:space:]]+[0-9]+[[:space:]]*$/d' "$GAI_CONF" || true
    fi
  fi

  if is_resolved_active && have_cmd resolvectl; then
    resolvectl revert "$ifc" >/dev/null 2>&1 || true
    resolvectl flush-caches >/dev/null 2>&1 || true
  fi
  if [[ -f "$RESOLV_BACKUP" ]]; then
    cp -a "$RESOLV_BACKUP" /etc/resolv.conf 2>/dev/null 2>&1 || true
  fi

  if is_systemd; then
    systemctl disable dmit-mtu.service >/dev/null 2>&1 || true
    systemctl stop dmit-mtu.service >/dev/null 2>&1 || true
    rm -f "$MTU_SERVICE" "$MTU_VALUE_FILE" || true

    systemctl daemon-reload >/dev/null 2>&1 || true
  fi

  if ! mtu_restore_original; then
    warn "未找到可用的原始 MTU 备份，运行时 MTU 保持不变"
  fi

  if [[ -s "$SSH_ORIG_TGZ" ]]; then
    ssh_restore_key_login || warn "SSH 原始配置恢复失败，请人工检查"
  fi

  sysctl_apply_all
  if [[ -s "$TCP_SYSCTL_BACKUP" ]]; then
    tcp_restore_runtime_backup || warn "部分 TCP/sysctl 原始参数恢复失败"
  fi
  if [[ -s "$IPV6_SYSCTL_BACKUP" ]]; then
    ipv6_restore_runtime_backup || warn "部分 IPv6 原始参数恢复失败"
  fi
  restart_network_services_best_effort
  sleep 1

  ok "已还原（建议再跑一次【网络体检】确认状态）"
}

# ---------------- 分组菜单 ----------------
network_menu() {
  while true; do
    menu_header "网络诊断与修复" "连通性检查 · 自动修复 · 协议优先级"
    menu_section "诊断"
    menu_item "1" "网络体检" "只检查状态，不修改配置"
    menu_item "2" "体检并自动修复" "重拉 IPv6 并刷新 DNS"
    menu_section "协议优先级"
    menu_item "3" "优先 IPv4" "调整 glibc 地址选择顺序"
    menu_item "4" "优先 IPv6" "恢复系统默认倾向"
    menu_item "5" "恢复原始优先级" "从首次修改前的备份还原"
    menu_back_item

    local c=""
    read_tty c "请输入编号 > " ""
    case "$c" in
      1) health_check_only || true; pause_up ;;
      2) health_check_autofix || true; pause_up ;;
      3) prefer_ipv4 || true; pause_up ;;
      4) prefer_ipv6 || true; pause_up ;;
      5) restore_gai_default || true; pause_up ;;
      0|q|Q) return 0 ;;
      *) warn "无效选项"; pause_up ;;
    esac
  done
}

ipv6_menu() {
  while true; do
    menu_header "IPv6 管理" "基础开关 · 故障修复 · /64 地址池与随机出网"
    menu_section "基础管理"
    menu_item "1" "查看 IPv6 状态" "地址、路由、/64 前缀与 /128 列表"
    menu_item "2" "开启 IPv6" "开启 sysctl 并重新获取地址和路由"
    menu_item "3" "关闭 IPv6" "系统级禁用"
    menu_section "高级工具"
    menu_item "4" "/64 地址池与随机出网" "管理 /128 地址和 nft NAT66"
    menu_item "5" "强力修复 IPv6" "修复 GRUB、模块黑名单、RA 与 SLAAC"
    menu_back_item

    local c=""
    read_tty c "请输入编号 > " ""
    case "$c" in
      1) ipv6_pool_status || true; pause_up ;;
      2) ipv6_enable || true; pause_up ;;
      3) ipv6_disable || true; pause_up ;;
      4) ipv6_tools_menu ;;
      5) ipv6_hard_repair || true; pause_up ;;
      0|q|Q) return 0 ;;
      *) warn "无效选项"; pause_up ;;
    esac
  done
}

tcp_menu() {
  while true; do
    menu_header "TCP / BBR" "固定预设 · 动态实测 · BDP 推导与安全恢复"
    menu_section "当前状态"
    print_kv "固定调优" "$(tcp_fixed_status_text)"
    print_kv "动态调优" "$(tcpfit_status_summary)"
    menu_section "检测与调优"
    menu_item "1" "检测 BBR 支持" "查看当前、可用拥塞控制算法"
    menu_item "2" "固定通用调优" "BBR + FQ + 64 MiB 缓冲，无需测速"
    menu_item "3" "动态实测调优" "按带宽、RTT、内存推导 BDP 并实测限速器拐点"
    menu_section "兼容与恢复"
    menu_item "4" "应用 DMIT 默认参数" "兼容 DMIT 镜像参数，不作为动态优化"
    menu_item "5" "恢复修改前参数" "优先使用首次修改时的原值备份"
    menu_back_item

    local c=""
    read_tty c "请输入编号 > " ""
    case "$c" in
      1) bbr_check || true; pause_up ;;
      2) tcp_fixed_apply || true; pause_up ;;
      3) tcpfit_menu ;;
      4) tcp_restore_dmit_default || true; pause_up ;;
      5) tcp_restore_default || true; pause_up ;;
      0|q|Q) return 0 ;;
      *) warn "无效选项"; pause_up ;;
    esac
  done
}

dns_mtu_menu() {
  while true; do
    menu_header "DNS / MTU" "解析服务器 · 路径 MTU 探测与持久化"
    menu_section "DNS"
    menu_item "1" "切换 DNS" "Cloudflare、Google、Quad9"
    menu_item "2" "恢复原始 DNS" "回到脚本首次修改前的配置"
    menu_section "MTU"
    menu_item "3" "MTU 管理" "探测、设置、持久化与移除"
    menu_back_item

    local c=""
    read_tty c "请输入编号 > " ""
    case "$c" in
      1) dns_switch_menu ;;
      2) dns_restore || true; pause_up ;;
      3) mtu_menu ;;
      0|q|Q) return 0 ;;
      *) warn "无效选项"; pause_up ;;
    esac
  done
}

system_tools_menu() {
  while true; do
    menu_header "系统维护与恢复" "Swap · 清理 · 更新 · 快照 · 系统重装"
    menu_section "维护"
    menu_item "1" "Swap 管理" "创建、调整、删除 Swap 与设置 swappiness"
    menu_item "2" "磁盘与日志清理" "预览后清理缓存、journal 和临时文件"
    menu_item "3" "系统更新与健康" "更新、失败服务、重启提示与时间同步"
    menu_item "4" "设置中国时区" "Asia/Shanghai"
    menu_item "5" "保存环境快照" "收集网络与配置状态，便于发工单"
    menu_section "恢复"
    menu_item "6" "还原网络配置" "网络、TCP、SSH；不影响 Swap 与安全防护"
    menu_section "危险操作"
    menu_item "7" "DD 重装系统" "清空系统盘，开始前需再次确认"
    menu_back_item

    local c=""
    read_tty c "请输入编号 > " ""
    case "$c" in
      1) swap_menu ;;
      2) cleanup_menu ;;
      3) system_update_menu ;;
      4) set_timezone_china || true; pause_up ;;
      5) env_snapshot || true; pause_up ;;
      6) restore_all || true; pause_up ;;
      7) dd_reinstall || true; pause_up ;;
      0|q|Q) return 0 ;;
      *) warn "无效选项"; pause_up ;;
    esac
  done
}

# ---------------- 主菜单 ----------------
menu() {
  RUN_MODE="menu"
  while true; do
    banner
    menu_section "网络与协议"
    menu_item "1" "网络诊断与修复" "体检、自动修复、协议优先级"
    menu_item "2" "IPv6 管理" "开关、强力修复、地址池、随机出网"
    menu_item "3" "TCP / BBR" "固定预设、动态实测、BBR 与安全恢复"
    menu_item "4" "DNS / MTU" "解析服务器与路径 MTU"
    menu_section "系统与安全"
    menu_item "5" "系统状态与端口" "资源、进程、监听端口与服务健康"
    menu_item "6" "安全防护" "SSH、Fail2Ban 与常用防火墙"
    menu_item "7" "轻量建站" "网址导航、本机回源锁定与端口安全"
    menu_item "8" "HTTPS 反向代理" "本机服务、远程网站、证书与 WebSocket"
    menu_item "9" "换 IP 防失联" "cloud-init、QGA、自动回滚保护"
    menu_section "测试与维护"
    menu_item "10" "性能与网络测试" "GB5、回程、TcpQuality、解锁"
    menu_item "11" "系统维护与恢复" "Swap、清理、更新、快照、还原、DD"
    echo
    menu_item "0" "退出工具箱"
    menu_rule

    local choice=""
    read_tty choice "请输入编号 > " ""
    case "$choice" in
      1) network_menu ;;
      2) ipv6_menu ;;
      3) tcp_menu ;;
      4) dns_mtu_menu ;;
      5) system_status_menu ;;
      6) security_menu ;;
      7) secure_site_menu ;;
      8) reverse_proxy_menu ;;
      9) cloudinit_qga_menu ;;
      10) tests_menu ;;
      11) system_tools_menu ;;
      0|q|Q) return 0 ;;
      *) warn "无效选项"; pause_main ;;
    esac
  done
}

main() {
  need_root
  # Self-heal only artifacts owned by older DMITBox site guards.  This runs
  # before the menu so an obsolete named firewall chain cannot keep blocking
  # an unrelated service port merely because the user has not opened the site menu.
  secure_site_cleanup_legacy_firewall_on_start || true
  secure_site_select_nginx_paths
  secure_site_migrate_legacy_site || warn "旧版轻量网站尚未完成迁移，请进入轻量建站执行安装/修复"
  secure_site_cleanup_legacy_firewall_on_start || true
  if ! has_tty && [[ ! -t 0 ]]; then
    warn "当前没有可交互终端，无法显示菜单。请在 SSH/控制台中直接运行：bash ${SCRIPT_NAME}"
    return 1
  fi
  menu
}
if [[ "${DMITBOX_SOURCE_ONLY:-0}" != "1" ]]; then
  main "$@"
fi
