#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

SCRIPT_NAME="dmitbox.sh"
AD_TEXT="欢迎加入DMIT交流群 https://t.me/DmitChat"

# managed files
TUNE_SYSCTL_FILE="/etc/sysctl.d/99-dmit-tcp-tune.conf"
DMIT_TCP_DEFAULT_FILE="/etc/sysctl.d/99-dmit-tcp-dmitdefault.conf"
IPV6_SYSCTL_FILE="/etc/sysctl.d/99-dmit-ipv6.conf"
IPV6_FIX_SYSCTL_FILE="/etc/sysctl.d/99-dmit-ipv6-fix.conf"
GAI_CONF="/etc/gai.conf"
BACKUP_BASE="/root/dmit-backup"

# MTU persistent via systemd
MTU_SERVICE="/etc/systemd/system/dmit-mtu.service"
MTU_VALUE_FILE="/etc/dmit-mtu.conf"

# DNS backup
RESOLV_BACKUP="${BACKUP_BASE}/resolv.conf.orig"

# SSH backup & drop-in
SSH_ORIG_TGZ="${BACKUP_BASE}/ssh-orig.tgz"
SSH_DROPIN_DIR="/etc/ssh/sshd_config.d"
SSH_DROPIN_FILE="${SSH_DROPIN_DIR}/99-dmitbox.conf"

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

RUN_MODE="${RUN_MODE:-menu}" # menu | cli

# colors (no red)
c_reset="\033[0m"
c_dim="\033[2m"
c_bold="\033[1m"
c_green="\033[32m"
c_yellow="\033[33m"
c_cyan="\033[36m"
c_white="\033[37m"

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

has_tty() { [[ -r /dev/tty ]]; }

read_tty() {
  local __var="$1" __prompt="$2" __default="${3:-}"
  local __val=""
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

pause_up() {
  [[ "$RUN_MODE" == "menu" ]] || return 0
  echo
  local msg="↩ 回车返回上级菜单..."
  printf "%s" "$msg"
  if [[ -t 0 ]]; then
    read -r _ || true
  elif [[ -r /dev/tty ]]; then
    read -r _ </dev/tty || true
  else
    sleep 2
  fi
  echo
}



pause_main() {
  [[ "$RUN_MODE" == "menu" ]] || return 0
  echo
  local msg="↩ 回车返回主菜单..."
  printf "%s" "$msg"
  if [[ -t 0 ]]; then
    read -r _ || true
  elif [[ -r /dev/tty ]]; then
    read -r _ </dev/tty || true
  else
    sleep 2
  fi
  echo
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
  local log="/tmp/dmitbox-$(ts_now).log"

  info "$title"
  warn "若长时间无输出：这通常是 dpkg 在处理 triggers（如 libc-bin/ldconfig），不一定卡死。可随时按 Ctrl+C 中断。"

  ("$@") >"$log" 2>&1 &
  local pid=$!
  local spin='|/-\\'
  local i=0
  while kill -0 "$pid" >/dev/null 2>&1; do
    local j=$(( i % 4 ))
    # shellcheck disable=SC2059
    printf "\r${c_dim}…安装/配置进行中 %c  (log: %s)${c_reset}" "${spin:j:1}" "$log"
    sleep 0.2
    i=$((i+1))
  done
  wait "$pid"; local rc=$?
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

is_systemd() { have_cmd systemctl; }
is_resolved_active() { is_systemd && systemctl is-active --quiet systemd-resolved 2>/dev/null; }

curl4_ok() { have_cmd curl && curl -4 -sS --max-time 5 ip.sb >/dev/null 2>&1; }
curl6_ok() { have_cmd curl && curl -6 -sS --max-time 5 ip.sb >/dev/null 2>&1; }

dns_resolve_ok() {
  if have_cmd getent; then getent hosts ip.sb >/dev/null 2>&1 && return 0; fi
  have_cmd curl && curl -sS --max-time 5 ip.sb >/dev/null 2>&1
}

# ---------------- banner ----------------
banner() {
  soft_clear
  echo -e "${c_bold}${c_white}DMIT 工具箱${c_reset}  ${c_dim}(${SCRIPT_NAME})${c_reset}"
  echo -e "${c_green}${AD_TEXT}${c_reset}"
  echo "bash <(curl -sL https://url.wuyang.skin/DMIT)"
  echo -e "${c_dim}----------------------------------------------${c_reset}"
}

sub_banner() {
  echo -e "${c_dim}----------------------------------------------${c_reset}"
  echo -e "${c_green}${AD_TEXT}${c_reset}"
  echo -e "${c_dim}----------------------------------------------${c_reset}"
}

# ---------------- 环境快照 ----------------
env_snapshot() {
  ensure_dir "$BACKUP_BASE"
  local bdir="${BACKUP_BASE}/snapshot-$(ts_now)"
  ensure_dir "$bdir"
  info "环境快照 → ${bdir}"

  for p in /etc/sysctl.conf /etc/sysctl.d /etc/gai.conf /etc/modprobe.d /etc/default/grub /etc/network /etc/netplan /etc/systemd/network /etc/resolv.conf /etc/ssh/sshd_config /etc/ssh/sshd_config.d; do
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
  have_cmd nft && nft delete table inet dmitbox_rand6 >/dev/null 2>&1 || true
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
ipv6_disable() {
  info "IPv6：关闭（系统级禁用）"
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

  ensure_dir "$BACKUP_BASE"
  local bdir="${BACKUP_BASE}/ipv6-hardfix-$(ts_now)"
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
bbr_check() {
  echo "================ BBR 检测 ================"
  echo "kernel=$(uname -r)"
  local avail cur
  avail="$(cat /proc/sys/net/ipv4/tcp_available_congestion_control 2>/dev/null || echo "")"
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

tcp_tune_apply() {
  info "TCP：通用调优（BBR + FQ + 常用参数）"
  have_cmd modprobe && modprobe tcp_bbr >/dev/null 2>&1 || true

  rm -f "$DMIT_TCP_DEFAULT_FILE" >/dev/null 2>&1 || true

  write_file "$TUNE_SYSCTL_FILE" \
"net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr

net.core.netdev_max_backlog=16384
net.core.somaxconn=8192
net.ipv4.tcp_max_syn_backlog=8192

net.core.rmem_max=67108864
net.core.wmem_max=67108864
net.ipv4.tcp_rmem=4096 87380 67108864
net.ipv4.tcp_wmem=4096 65536 67108864

net.ipv4.tcp_mtu_probing=1
net.ipv4.tcp_fastopen=3
net.ipv4.tcp_syncookies=1"
  sysctl_apply_all
  ok "已应用 TCP 通用调优"
  bbr_check
}

tcp_restore_default() {
  info "TCP：恢复 Linux 默认（CUBIC + pfifo_fast）"
  rm -f "$TUNE_SYSCTL_FILE" "$DMIT_TCP_DEFAULT_FILE" >/dev/null 2>&1 || true
  sysctl -w net.core.default_qdisc=pfifo_fast >/dev/null 2>&1 || true
  sysctl -w net.ipv4.tcp_congestion_control=cubic >/dev/null 2>&1 || true
  sysctl_apply_all
  ok "已恢复 TCP 默认"
}

tcp_restore_dmit_default() {
  info "TCP：恢复 DMIT 默认 TCP"
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

os_id_like() {
  if [[ -r /etc/os-release ]]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    echo "${ID:-unknown}|${ID_LIKE:-}"
  else
    echo "unknown|"
  fi
}

bbrv3_install_xanmod() {
  local arch; arch="$(uname -m)"
  if [[ "$arch" != "x86_64" ]]; then
    warn "BBRv3（XanMod）仅建议 x86_64 使用。当前：$arch"
    return 1
  fi

  local ids; ids="$(os_id_like)"
  if ! echo "$ids" | grep -Eqi 'debian|ubuntu|kali'; then
    warn "当前系统不像 Debian/Ubuntu/Kali：此安装方式不适用"
    return 1
  fi

  warn "将安装 XanMod 内核（包含 BBRv3），需要重启生效"
  warn "有 DKMS/驱动的机器请谨慎"

  local ans=""
  read_tty ans "确认继续请输入 YES > " ""
  if [[ "$ans" != "YES" ]]; then
    warn "已取消"
    return 0
  fi

  pkg_install wget gpg ca-certificates lsb-release apt-transport-https

  local psabi="x86-64-v3"
  local out=""
  out="$(wget -qO- https://dl.xanmod.org/check_x86-64_psabi.sh | bash 2>/dev/null || true)"
  if echo "$out" | grep -q "x86-64-v1"; then psabi="x86-64-v1"; fi
  if echo "$out" | grep -q "x86-64-v2"; then psabi="x86-64-v2"; fi
  if echo "$out" | grep -q "x86-64-v3"; then psabi="x86-64-v3"; fi
  info "CPU 指令集等级：${psabi}"

  wget -qO /tmp/xanmod.gpg https://dl.xanmod.org/gpg.key
  gpg --dearmor -o /usr/share/keyrings/xanmod-archive-keyring.gpg /tmp/xanmod.gpg >/dev/null 2>&1 || true

  local codename=""
  codename="$(lsb_release -sc 2>/dev/null || true)"
  if [[ -z "$codename" && -r /etc/os-release ]]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    codename="${VERSION_CODENAME:-}"
  fi
  [[ -z "$codename" ]] && codename="stable"

  write_file /etc/apt/sources.list.d/xanmod-release.list \
"deb [signed-by=/usr/share/keyrings/xanmod-archive-keyring.gpg] http://deb.xanmod.org ${codename} main"

  apt-get -qq update >/dev/null 2>&1 || true

  local pkg="linux-xanmod-x64v3"
  case "$psabi" in
    x86-64-v1) pkg="linux-xanmod-x64v1" ;;
    x86-64-v2) pkg="linux-xanmod-x64v2" ;;
    x86-64-v3) pkg="linux-xanmod-x64v3" ;;
  esac

  info "安装内核包：${pkg}"
  apt-get -y install "${pkg}" >/dev/null 2>&1 || true

  ok "XanMod 内核已安装（需重启生效）"
  local rb=""
  read_tty rb "现在重启？(y/N) > " "N"
  if [[ "$rb" == "y" || "$rb" == "Y" ]]; then
    warn "即将重启..."
    reboot || true
  else
    info "稍后手动重启：reboot"
  fi
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
    echo
    echo -e "${c_bold}${c_white}DNS 切换（更换解析服务器）${c_reset}  ${c_dim}(接口: $ifc)${c_reset}"
    sub_banner
    echo "  1) Cloudflare  (1.1.1.1 / 1.0.0.1)"
    echo "  2) Google      (8.8.8.8 / 8.8.4.4)"
    echo "  3) Quad9       (9.9.9.9 / 149.112.112.112)"
    echo "  0) 返回"
    local c=""
    read_tty c "选择> " ""
    case "$c" in
      1) dns_set "cloudflare" "$ifc"; pause_up ;;
      2) dns_set "google" "$ifc"; pause_up ;;
      3) dns_set "quad9" "$ifc"; pause_up ;;
      0) return 0 ;;
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

ping_payload_ok_v4() {
  local host="$1" payload="$2"
  ping -4 -c 1 -W 1 -M do -s "$payload" "$host" >/dev/null 2>&1
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
    echo
    echo -e "${c_bold}${c_white}MTU 工具（探测/设置/持久化）${c_reset}  ${c_dim}(接口: $(default_iface)，当前: ${cur:-N/A})${c_reset}"
    sub_banner
    echo "  1) 自动探测 MTU（只显示推荐值）"
    echo "  2) 手动设置 MTU（临时生效）"
    echo "  3) 探测并设置 MTU（临时生效）"
    echo "  4) 探测并设置 MTU（开机自动生效）"
    echo "  5) 移除 MTU 开机自动设置"
    echo "  0) 返回"
    local c=""
    read_tty c "选择> " ""

    case "$c" in
      1)
        local mtu=""
        mtu="$(mtu_probe_v4_value || true)"
        [[ -n "${mtu:-}" ]] && ok "推荐 MTU：$mtu" || true
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
      0) return 0 ;;
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
    info "IPv6 不完整：执行“开启 IPv6（重拉地址/路由）”"
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
  [[ "$fixed" -eq 1 ]] && ok "已执行自动修复动作" || ok "无需修复"
}

# ---------------- IPv6 /64 地址池 + 随机出网 ----------------
ipv6_prefix64_guess() {
  local ifc="${1:-$(default_iface)}"
  local a=""
  a="$(ip -6 addr show dev "$ifc" scope global 2>/dev/null | awk '/inet6/{print $2}' | grep -E '/64$' | head -n1 || true)"
  if [[ -n "$a" ]]; then
    a="${a%/64}"
    echo "$a" | awk -F: '{print $1 ":" $2 ":" $3 ":" $4}'
    return 0
  fi
  a="$(ip -6 route show 2>/dev/null | awk -v i="$ifc" '$1 ~ /\/64$/ && $0 ~ ("dev " i) {print $1; exit}' || true)"
  if [[ -n "$a" ]]; then
    a="${a%::/64}"
    echo "$a"
    return 0
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
  have_cmd nft && nft delete table inet dmitbox_rand6 >/dev/null 2>&1 || true

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
  total="$(grep -v '^$' "$tmp" | wc -l | tr -d ' ')"
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
  ipv6_rand_load_conf || true
  ipv6_rand_apply_nft_runtime || true
  ipv6_rand_persist_systemd || true

  ok "完成：已生成 /128 池并启用随机出网"
}

ipv6_tools_menu() {
  local ifc; ifc="$(default_iface)"
  while true; do
    echo
    echo -e "${c_bold}${c_white}IPv6 /64 工具（地址池 / 随机出网）${c_reset}  ${c_dim}(接口: ${ifc})${c_reset}"
    sub_banner
    echo "  1) 查看当前 IPv6 状态（/64 与 /128）"
    echo "  2) 新增 /128（持久：forever）"
    echo "  3) 新增 /128（临时：1小时有效）"
    echo "  4) 删除一个 /128（手动输入）"
    echo "  5) 启用：出网随机 IPv6（从现有 /128 里选前 N 个）"
    echo "  6) 关闭：出网随机 IPv6"
    echo "  7) 查看：随机出网 IPv6 状态"
    echo "  8) 一键：生成 N 个 /128 + 立刻启用随机出网（推荐）"
    echo "  9) 关闭：IPv6 地址池（删除池内 /128 + 取消持久化）"
    echo "  10) 自检：随机出网是否真的在变（连续测试）"
    echo "  11) 强力修复 IPv6（DD 后无 IPv6：修 GRUB/黑名单/RA）"
    echo "  0) 返回"
    local c=""
    read_tty c "选择> " ""

    case "$c" in
      1) ipv6_pool_status; pause_up ;;
      2)
        local n=""
        read_tty n "生成多少个 /128（默认 3）> " "3"
        [[ "$n" =~ ^[0-9]+$ ]] || { warn "必须是数字"; pause_up; continue; }
        ipv6_gen_n_128 "$n" "persist" || true
        pause_up
        ;;
      3)
        local n=""
        read_tty n "生成多少个 /128（默认 1）> " "1"
        [[ "$n" =~ ^[0-9]+$ ]] || { warn "必须是数字"; pause_up; continue; }
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
      5)
        local n=""
        read_tty n "随机池大小 N（建议 3~10，默认 5）> " "5"
        [[ "$n" =~ ^[0-9]+$ ]] || { warn "N 必须是数字"; pause_up; continue; }
        (( n >= 2 )) || { warn "N 至少 2"; pause_up; continue; }
        ipv6_rand_enable_from_pool "$n" || true
        pause_up
        ;;
      6) ipv6_rand_disable || true; pause_up ;;
      7) ipv6_rand_status; pause_up ;;
      8)
        local n=""
        read_tty n "生成并随机出网：N（建议 3~10，默认 5）> " "5"
        [[ "$n" =~ ^[0-9]+$ ]] || { warn "N 必须是数字"; pause_up; continue; }
        (( n >= 2 )) || { warn "N 至少 2"; pause_up; continue; }
        ipv6_pool_generate_and_enable_rand "$n" || true
        pause_up
        ;;
      9) ipv6_pool_disable || true; pause_up ;;
      10)
        local n=""
        read_tty n "自检次数（默认 10）> " "10"
        [[ "$n" =~ ^[0-9]+$ ]] || n="10"
        ipv6_rand_selftest "$n" || true
        pause_up
        ;;
      11) ipv6_hard_repair || true; pause_up ;;
      0) return 0 ;;
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
    warn "如果你要使用面板“换 IP”功能：请在本菜单选择【开启 cloud-init 网络接管】后，再执行 cloud-init clean 并重启。"
  fi
}

cloudinit_qga_enable_network_management() {
  # Remove our disable file and also neutralize other 'network: {config: disabled}' lines if any.
  local changed="0"
  ensure_dir "$BACKUP_BASE"
  local bdir="${BACKUP_BASE}/cloudinit-enable-$(ts_now)"
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
    echo -e "${c_dim}可选修复：运行 apt-get update 查看真实原因；若不想每次开机触发，可在本脚本里选择“禁用 cloud-init 自动 apt 更新”。${c_reset}"
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
  echo -e "${c_dim}说明：DMIT 面板的“换 IP”通常依赖 cloud-init 重新下发网络配置；缺少 cloud-init/QGA 或网络被禁用，可能导致换 IP 后 SSH 直接失联。${c_reset}"
}

cloudinit_qga_install() {
  info "安装/启用：cloud-init + qemu-guest-agent（换 IP 防失联）"
  warn "若安装过程看起来卡住：请先耐心等待下载/安装；也可以按 Ctrl+C 中断并返回菜单。"

  local interrupted="0"
  trap 'interrupted="1"' INT

  pkg_install cloud-init qemu-guest-agent

  trap - INT
  [[ "$interrupted" == "1" ]] && { warn "已中断安装，返回菜单"; return 0; }

  if is_systemd; then
    systemctl enable --now qemu-guest-agent >/dev/null 2>&1 || true
    # cloud-init/cloud-final 多为 oneshot：首次运行可能很久（且我们把输出吞掉了），
    # 会让菜单看起来“卡在完成”。因此改成：启用 + 后台启动（不阻塞菜单）。
    systemctl enable cloud-init cloud-config cloud-final >/dev/null 2>&1 || true
    [[ "${RUN_MODE:-menu}" == "menu" ]] && info "启动 cloud-init（后台，不阻塞菜单）"
    systemctl start --no-block cloud-init cloud-config cloud-final >/dev/null 2>&1 || true
  fi

  ok "已执行安装/启用（若源里无包会跳过）"
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
  local bdir="${BACKUP_BASE}/ipchange-dmitdefault-$(ts_now)"
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
  echo "提示：如果你原来就是“仅密钥登录”，上述配置不会影响；如果你用密码登录，这能显著降低重启后无法登录的概率。"
}


# 让 cloud-init 只做“网络相关”的事，避免 DD 后因 user-data/模块默认行为导致：
# - SSH host key 被删除/重建（指纹变化）
# - sshd 被改成禁用密码/禁用 root（端口通但登不上）
# - set-passwords/users-groups 触发账号/密码/锁定变化
# - package-update-upgrade-install 在首启自动跑 apt（改动太大 + 可能报错导致 cloud-init status:error）
cloudinit_qga_dd_lockdown_network_only() {
  _need_root
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
  warn "已内置“自动回滚保护”：若重启后无网，会自动恢复原网络配置（见 /var/log/dmitbox-net-rollback.log）。"

  cloudinit_qga_install
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
    echo
    echo -e "${c_bold}${c_white}换 IP 防失联（cloud-init / QEMU Guest Agent）${c_reset}"
    sub_banner
    echo "  1) 检测状态（是否装了 cloud-init / QGA，是否禁用网络）"
    echo "  2) 安装/启用 cloud-init + QEMU Guest Agent"
    echo "  3) 开启 cloud-init 网络接管（解除 network: {config: disabled}）"
    echo "  4) cloud-init clean（建议换 IP 前/后执行，之后重启）"
    echo "  5) DD 后适配 DMIT 默认换IP（NoCloud/ConfigDrive + 接管网络）"
    echo "  6) 禁用 cloud-init 自动 apt 更新（避免 status:error）"
    echo "  0) 返回"
    local c=""
    read_tty c "选择> " ""
    case "$c" in
      1) cloudinit_qga_status; pause_up ;;
      2) cloudinit_qga_install || true; pause_up ;;
      3) cloudinit_qga_fix_network_disabled || true; pause_up ;;
      4) cloudinit_clean_and_hint_reboot || true; pause_up ;;
      5) cloudinit_qga_apply_dmit_default_ipchange_mode || true; pause_up ;;
      
      6) cloudinit_disable_pkg_updates || true; pause_up ;;
      0) return 0 ;;
      *) warn "无效选项"; pause_up ;;
    esac
  done
}

# ======================================================================
# SSH（关键修复：强制清理冲突项 + 99 drop-in 覆盖 + 禁用 ssh.socket）
# ======================================================================

ssh_pkg_install() {
  if have_cmd apk; then
    pkg_install openssh
  else
    pkg_install openssh-server openssh-client
  fi
  if ! have_cmd sshd && [[ -x /usr/sbin/sshd ]]; then
    export PATH="$PATH:/usr/sbin:/sbin"
  fi
}

ssh_backup_once() {
  ensure_dir "$BACKUP_BASE"
  if [[ ! -f "$SSH_ORIG_TGZ" ]]; then
    info "SSH：备份原始配置 → $SSH_ORIG_TGZ"
    tar -czf "$SSH_ORIG_TGZ" /etc/ssh/sshd_config /etc/ssh/sshd_config.d 2>/dev/null || \
      tar -czf "$SSH_ORIG_TGZ" /etc/ssh/sshd_config 2>/dev/null || true
    ok "SSH 原始配置已备份"
  fi
}

sshd_restart() {
  if is_systemd; then
    systemctl restart ssh  >/dev/null 2>&1 || true
    systemctl restart sshd >/dev/null 2>&1 || true
    systemctl try-restart ssh  >/dev/null 2>&1 || true
    systemctl try-restart sshd >/dev/null 2>&1 || true
  else
    service ssh restart  >/dev/null 2>&1 || true
    service sshd restart >/dev/null 2>&1 || true
  fi
}

sshd_status_hint() {
  echo -e "${c_dim}--- SSH 当前生效配置（节选）---${c_reset}"
  if have_cmd sshd; then
    sshd -T 2>/dev/null | egrep -i 'port|passwordauthentication|permitrootlogin|pubkeyauthentication|authenticationmethods|kbdinteractiveauthentication|challengeresponseauthentication|usepam|maxauthtries|logingracetime|clientaliveinterval|clientalivecountmax' || true
  else
    warn "未找到 sshd 命令，改为简单 grep："
    egrep -Rin -i 'Port|PasswordAuthentication|PubkeyAuthentication|KbdInteractiveAuthentication|ChallengeResponseAuthentication|UsePAM|PermitRootLogin|AuthenticationMethods' /etc/ssh/sshd_config /etc/ssh/sshd_config.d 2>/dev/null || true
  fi
  echo -e "${c_dim}--------------------------------${c_reset}"
}

# 便携删除配置行（避免 sed -i /I 在某些系统不兼容）
conf_strip_keys_in_file() {
  local f="$1"; shift
  [[ -f "$f" ]] || return 0
  local tmp="/tmp/.dmitbox.$$.$(basename "$f").tmp"
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
  ' "$f" > "$tmp" 2>/dev/null || { rm -f "$tmp" >/dev/null 2>&1 || true; return 0; }
  cat "$tmp" > "$f" 2>/dev/null || true
  rm -f "$tmp" >/dev/null 2>&1 || true
}

ssh_dropin_ensure() {
  ensure_dir "$SSH_DROPIN_DIR"
  if [[ ! -f "$SSH_DROPIN_FILE" ]]; then
    write_file "$SSH_DROPIN_FILE" "# managed by ${SCRIPT_NAME}"
  fi
  chown root:root "$SSH_DROPIN_FILE" >/dev/null 2>&1 || true
  chmod 600 "$SSH_DROPIN_FILE" >/dev/null 2>&1 || true
}

# 核心修复：清掉所有冲突项（主配置 + 其它 drop-in），确保我们的 99 生效
ssh_remove_conflicts_everywhere() {
  local keys=(
    Port PasswordAuthentication PermitRootLogin PubkeyAuthentication
    KbdInteractiveAuthentication ChallengeResponseAuthentication
    AuthenticationMethods UsePAM MaxAuthTries LoginGraceTime
    ClientAliveInterval ClientAliveCountMax PermitEmptyPasswords
  )

  # 主配置清理
  conf_strip_keys_in_file /etc/ssh/sshd_config "${keys[@]}" || true

  # drop-in 清理（除了我们自己的 99）
  if [[ -d "$SSH_DROPIN_DIR" ]]; then
    local f
    for f in "$SSH_DROPIN_DIR"/*.conf; do
      [[ -e "$f" ]] || continue
      [[ "$f" == "$SSH_DROPIN_FILE" ]] && continue
      conf_strip_keys_in_file "$f" "${keys[@]}" || true
    done
  fi
}

ssh_dropin_set_kv() {
  local key="$1" val="$2"
  ssh_dropin_ensure
  # 清理旧行（在我们的 99 内）
  conf_strip_keys_in_file "$SSH_DROPIN_FILE" "$key" || true
  printf "%s %s\n" "$key" "$val" >> "$SSH_DROPIN_FILE"
  chmod 600 "$SSH_DROPIN_FILE" >/dev/null 2>&1 || true
}

# 防止 ssh.socket 抢占 22（即便现在 inactive，也避免后续被 enable）
ssh_socket_disable_if_any() {
  is_systemd || return 0
  if systemctl list-unit-files 2>/dev/null | awk '{print $1}' | grep -qx "ssh.socket"; then
    if systemctl is-enabled --quiet ssh.socket 2>/dev/null; then
      warn "检测到 ssh.socket 已启用：将 disable（否则端口可能被固定在 22）"
      systemctl disable --now ssh.socket >/dev/null 2>&1 || true
    else
      systemctl stop ssh.socket >/dev/null 2>&1 || true
    fi
  fi
}

ssh_random_pass() { tr -dc 'A-Za-z0-9' < /dev/urandom | head -c 18 || true; }

ssh_create_user_with_password() {
  local user="$1"
  local passwd="$2"

  if ! id "$user" >/dev/null 2>&1; then
    info "创建用户：$user"
    if have_cmd useradd; then
      useradd -m -s /bin/bash "$user" >/dev/null 2>&1 || true
    elif have_cmd adduser; then
      adduser -D "$user" >/dev/null 2>&1 || adduser --disabled-password --gecos "" "$user" >/dev/null 2>&1 || true
    else
      warn "没有 useradd/adduser，无法创建用户"
      return 1
    fi
  fi

  if have_cmd chpasswd; then
    echo "${user}:${passwd}" | chpasswd
  else
    if have_cmd passwd; then
      printf "%s\n%s\n" "$passwd" "$passwd" | passwd "$user" >/dev/null 2>&1 || {
        warn "设置密码失败（缺 chpasswd 且 passwd 不可用）"
        return 1
      }
    else
      warn "系统缺少 chpasswd/passwd，无法设置密码"
      return 1
    fi
  fi

  ok "已设置 ${user} 密码"
  echo -e "${c_green}${user} 密码：${passwd}${c_reset}"

  if getent group sudo >/dev/null 2>&1; then
    usermod -aG sudo "$user" >/dev/null 2>&1 || true
  elif getent group wheel >/dev/null 2>&1; then
    usermod -aG wheel "$user" >/dev/null 2>&1 || true
  fi
}

ssh_apply_base_hardening() {
  # 先清冲突、再写我们的 99，保证最终生效
  ssh_remove_conflicts_everywhere || true
  ssh_socket_disable_if_any || true
  ssh_dropin_set_kv "KbdInteractiveAuthentication" "no"
  ssh_dropin_set_kv "ChallengeResponseAuthentication" "no"
  ssh_dropin_set_kv "PermitEmptyPasswords" "no"
  ssh_dropin_set_kv "UsePAM" "yes"
  ssh_dropin_set_kv "MaxAuthTries" "3"
  ssh_dropin_set_kv "LoginGraceTime" "20"
  ssh_dropin_set_kv "ClientAliveInterval" "60"
  ssh_dropin_set_kv "ClientAliveCountMax" "2"
  ssh_dropin_set_kv "AuthenticationMethods" "any"
}

ssh_safe_enable_password_for_user_keep_root_key() {
  local user="${1:-dmit}"
  ssh_pkg_install
  ssh_backup_once

  warn "推荐模式：普通用户密码登录；root 禁止密码（仅密钥）"
  warn "建议保持当前 SSH 会话不要断开，确认新用户可登录后再退出"

  ssh_apply_base_hardening

  ssh_dropin_set_kv "PasswordAuthentication" "yes"
  ssh_dropin_set_kv "PubkeyAuthentication" "yes"
  ssh_dropin_set_kv "PermitRootLogin" "prohibit-password"

  local p; p="$(ssh_random_pass)"
  [[ -z "${p:-}" ]] && { warn "生成随机密码失败"; return 1; }
  ssh_create_user_with_password "$user" "$p" || true

  if have_cmd sshd && ! sshd -t >/dev/null 2>&1; then
    warn "sshd 配置校验失败：自动回滚"
    ssh_restore_key_login || true
    return 1
  fi

  sshd_restart
  ok "已重启 SSH（推荐模式已生效）"
  sshd_status_hint
}

ssh_enable_password_keep_key_for_user() {
  local user="${1:-root}"
  local mode="${2:-random}" # random|custom
  local passwd="${3:-}"

  ssh_pkg_install
  ssh_backup_once

  warn "中等模式：开启密码登录（保留密钥登录）"
  warn "建议保持当前 SSH 会话不要断开，确认密码可登录后再退出"

  ssh_apply_base_hardening
  ssh_dropin_set_kv "PasswordAuthentication" "yes"
  ssh_dropin_set_kv "PubkeyAuthentication" "yes"
  ssh_dropin_set_kv "PermitRootLogin" "yes"

  if [[ "$mode" == "random" ]]; then passwd="$(ssh_random_pass)"; fi
  [[ -z "${passwd:-}" ]] && { warn "密码为空：取消"; return 1; }

  if id "$user" >/dev/null 2>&1; then
    if have_cmd chpasswd; then
      echo "${user}:${passwd}" | chpasswd
    else
      printf "%s\n%s\n" "$passwd" "$passwd" | passwd "$user" >/dev/null 2>&1 || true
    fi
    ok "已设置用户密码：${user}"
    echo -e "${c_green}新密码：${passwd}${c_reset}"
  else
    warn "用户不存在：$user（未设置密码）"
  fi

  if have_cmd sshd && ! sshd -t >/dev/null 2>&1; then
    warn "sshd 配置校验失败：自动回滚"
    ssh_restore_key_login || true
    return 1
  fi

  sshd_restart
  ok "已重启 SSH（密码+密钥均可）"
  sshd_status_hint
}

ssh_password_only_disable_key_risky() {
  local user="${1:-root}"
  local mode="${2:-random}" # random|custom
  local passwd="${3:-}"

  ssh_pkg_install
  ssh_backup_once

  warn "高风险模式：仅密码登录（禁用密钥）"
  warn "有锁门风险：务必保持当前 SSH 会话不断开"
  local ans=""
  read_tty ans "确认继续请输入 YES > " ""
  if [[ "${ans}" != "YES" ]]; then
    warn "已取消"
    return 0
  fi

  ssh_apply_base_hardening
  ssh_dropin_set_kv "PasswordAuthentication" "yes"
  ssh_dropin_set_kv "PubkeyAuthentication" "no"
  ssh_dropin_set_kv "PermitRootLogin" "yes"

  if [[ "$mode" == "random" ]]; then passwd="$(ssh_random_pass)"; fi
  [[ -z "${passwd:-}" ]] && { warn "密码为空：取消"; return 1; }

  if id "$user" >/dev/null 2>&1; then
    if have_cmd chpasswd; then
      echo "${user}:${passwd}" | chpasswd
    else
      printf "%s\n%s\n" "$passwd" "$passwd" | passwd "$user" >/dev/null 2>&1 || true
    fi
    ok "已设置用户密码：${user}"
    echo -e "${c_green}新密码：${passwd}${c_reset}"
  else
    warn "用户不存在：$user（未设置密码）"
  fi

  if have_cmd sshd && ! sshd -t >/dev/null 2>&1; then
    warn "sshd 配置校验失败：自动回滚"
    ssh_restore_key_login || true
    return 1
  fi

  sshd_restart
  ok "已重启 SSH（仅密码登录）"
  sshd_status_hint
}

ssh_restore_key_login() {
  ssh_backup_once
  info "SSH：恢复原来的配置（从备份还原）"
  if [[ -f "$SSH_ORIG_TGZ" ]]; then
    tar -xzf "$SSH_ORIG_TGZ" -C / 2>/dev/null || true
    rm -f "$SSH_DROPIN_FILE" 2>/dev/null || true
    sshd_restart
    ok "已恢复 SSH 原始配置并重启"
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
  local p="$1"

  if have_cmd ufw; then
    if ufw status 2>/dev/null | grep -qi "Status: active"; then
      ufw allow "${p}/tcp" >/dev/null 2>&1 || true
      ok "已尝试放行 ufw：${p}/tcp"
      return 0
    fi
  fi

  if have_cmd firewall-cmd; then
    if firewall-cmd --state >/dev/null 2>&1; then
      firewall-cmd --permanent --add-port="${p}/tcp" >/dev/null 2>&1 || true
      firewall-cmd --reload >/dev/null 2>&1 || true
      ok "已尝试放行 firewalld：${p}/tcp"
      return 0
    fi
  fi

  if have_cmd iptables; then
    iptables -C INPUT -p tcp --dport "$p" -j ACCEPT >/dev/null 2>&1 || \
      iptables -I INPUT -p tcp --dport "$p" -j ACCEPT >/dev/null 2>&1 || true
    ok "已尝试放行 iptables：${p}/tcp（可能不持久）"
    return 0
  fi

  warn "未检测到可用防火墙工具：请自行放行 ${p}/tcp"
  return 0
}

ssh_set_port() {
  local newp="$1"

  [[ "$newp" =~ ^[0-9]+$ ]] || { warn "端口必须是数字"; return 1; }
  if (( newp < 1 || newp > 65535 )); then warn "端口范围 1-65535"; return 1; fi
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

  ssh_pkg_install
  ssh_backup_once

  warn "更换 SSH 端口会影响新连接"
  warn "强烈建议保持当前 SSH 会话不要断开"
  warn "请先测试：ssh -p ${newp} user@你的IP"

  ssh_apply_base_hardening
  ssh_dropin_set_kv "Port" "$newp"
  firewall_open_port_best_effort "$newp"

  if have_cmd sshd && ! sshd -t >/dev/null 2>&1; then
    warn "sshd 配置校验失败：将恢复备份"
    ssh_restore_key_login || true
    return 1
  fi

  sshd_restart
  ok "已尝试切换 SSH 端口 → ${newp}"

  echo -e "${c_dim}--- 立即验证 ---${c_reset}"
  sshd -T 2>/dev/null | egrep -i 'port|passwordauthentication|permitrootlogin|pubkeyauthentication|authenticationmethods' || true
  ss -lntp 2>/dev/null | grep -E "sshd|:${newp}\b|:22\b" || true

  echo -e "${c_green}提示：请用新端口测试登录成功后，再退出当前会话${c_reset}"
  echo -e "${c_dim}当前端口：$(ssh_current_ports)${c_reset}"
}

ssh_menu() {
  while true; do
    echo
    echo -e "${c_bold}${c_white}SSH 工具（安全优先）${c_reset}"
    sub_banner
    echo "  1) 创建新用户 + 密码登录（root 仅密钥，更安全）"
    echo "  2) 开启密码登录（保留密钥）"
    echo "  3) 仅密码登录（禁用密钥，高风险）"
    echo "  4) 更换 SSH 端口（并尝试放行防火墙）"
    echo "  5) 恢复 SSH 原始配置（用备份还原）"
    echo "  6) 查看 SSH 当前生效状态（含端口）"
    echo "  0) 返回"
    local c=""
    read_tty c "选择> " ""
    case "$c" in
      1)
        local u=""
        read_tty u "新用户名（默认 dmit）> " "dmit"
        ssh_safe_enable_password_for_user_keep_root_key "$u" || true
        pause_up
        ;;
      2)
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
      3)
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
      4)
        echo -e "${c_dim}当前 SSH 端口：$(ssh_current_ports)${c_reset}"
        local p=""
        read_tty p "输入新端口（建议 20000-59999）> " ""
        ssh_set_port "$p" || true
        pause_up
        ;;
      5) ssh_restore_key_login || true; pause_up ;;
      6)
        sshd_status_hint
        echo -e "${c_dim}当前端口：$(ssh_current_ports)${c_reset}"
        pause_up
        ;;
      0) return 0 ;;
      *) warn "无效选项"; pause_up ;;
    esac
  done
}

# ---------------- 测试：运行外部脚本 ----------------
run_remote_script() {
  local title="$1"
  local cmd="$2"
  local note="${3:-}"

  echo
  echo -e "${c_bold}${c_white}${title}${c_reset}"
  [[ -n "$note" ]] && echo -e "${c_yellow}${note}${c_reset}"
  echo -e "${c_dim}将执行：${cmd}${c_reset}"
  warn "注意：这会从网络拉取并运行脚本（请自行确认来源可信）"

  if ! has_tty; then
    warn "当前无可交互 TTY（可能是 curl|bash 场景 / 无 -t 终端），为安全起见：已取消执行"
    return 0
  fi
  read_tty _ "回车执行（Ctrl+C 取消）..." ""

  if echo "$cmd" | grep -q "curl"; then pkg_install curl; fi
  if echo "$cmd" | grep -q "wget"; then pkg_install wget; fi
  pkg_install bash

  bash -lc "$cmd" </dev/tty || true
}

tests_menu() {
  while true; do
    echo
    echo -e "${c_bold}${c_white}一键测试脚本${c_reset}"
    sub_banner
    echo "  1) GB5 性能测试（Geekbench 5）"
    echo "  2) Bench 综合测试（bench.sh）"
    echo "  3) 三网回程测试（仅参考）"
    echo "  4) IP 质量检测（IP.Check.Place）"
    echo "  5) NodeQuality 测试"
    echo "  6) Telegram 延迟测试"
    echo "  7) 流媒体解锁检测（check.unlock.media）"
    echo "  0) 返回"
    local c=""
    read_tty c "选择> " ""
    case "$c" in
      1) run_remote_script "GB5 性能测试"  "bash <(wget -qO- https://raw.githubusercontent.com/i-abc/GB5/main/gb5-test.sh)"; pause_up ;;
      2) run_remote_script "Bench 综合测试" "bash <(curl -fsSL https://bench.sh)"; pause_up ;;
      3) run_remote_script "三网回程测试" "bash <(curl -fsSL https://raw.githubusercontent.com/ludashi2020/backtrace/main/install.sh)" "备注：仅参考"; pause_up ;;
      4) run_remote_script "IP 质量检测" "bash <(curl -sL IP.Check.Place)"; pause_up ;;
      5) run_remote_script "NodeQuality 测试" "bash <(curl -sL https://run.NodeQuality.com)"; pause_up ;;
      6) run_remote_script "Telegram 延迟测试" "bash <(curl -fsSL https://sub.777337.xyz/tgdc.sh)"; pause_up ;;
      7) run_remote_script "流媒体解锁检测" "bash <(curl -L -s check.unlock.media)"; pause_up ;;
      0) return 0 ;;
      *) warn "无效选项"; pause_up ;;
    esac
  done
}

# ---------------- 一键DD重装系统 ----------------
dd_reinstall() {
  warn "一键 DD 重装系统：会清空系统盘数据，风险极高！"
  warn "建议先准备好：VNC/救援模式/面板控制台"
  warn "开始后 SSH 可能中断，请勿慌"

  if ! has_tty; then
    warn "当前无可交互 TTY（可能是 curl|bash 场景），为安全起见：已取消"
    return 0
  fi

  local c="" flag="" ver="" port="" mode="" pwd=""
  echo
  echo -e "${c_bold}${c_white}DD 重装系统（InstallNET.sh）${c_reset}"
  sub_banner
  echo "  1) Debian 11"
  echo "  2) Debian 12"
  echo "  3) Debian 13"
  echo "  4) Ubuntu 22.04"
  echo "  5) Ubuntu 24.04"
  echo "  6) CentOS 7"
  echo "  7) CentOS 8"
  echo "  8) RockyLinux 9"
  echo "  9) AlmaLinux 9"
  echo "  10) Alpine edge"
  echo "  0) 返回"
  read_tty c "选择> " ""
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
    0) return 0 ;;
    *) warn "无效选项"; return 0 ;;
  esac

  local cur_port
  cur_port="$(ssh_current_ports | awk '{print $1}' || true)"
  cur_port="${cur_port:-22}"
  read_tty port "SSH 端口（默认 ${cur_port}）> " "$cur_port"
  [[ "$port" =~ ^[0-9]+$ ]] || { warn "端口必须是数字"; return 0; }

  echo
  echo "  1) 随机密码"
  echo "  2) 自定义密码"
  read_tty mode "选择> " "1"
  if [[ "$mode" == "1" ]]; then
    pwd="K$(ssh_random_pass)"
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
  wget --no-check-certificate -qO /tmp/InstallNET.sh 'https://raw.githubusercontent.com/leitbogioro/Tools/master/Linux_reinstall/InstallNET.sh'
  chmod a+x /tmp/InstallNET.sh

  warn "开始执行重装脚本（可能会进入安装流程/重启）"
  bash /tmp/InstallNET.sh "${flag}" "${ver}" -port "${port}" -pwd "${pwd}" || true
}

# ---------------- 一键还原 ----------------
restore_all() {
  local ifc; ifc="$(default_iface)"
  info "一键还原：撤销本脚本改动（DNS/MTU/IPv6/TCP/优先级/SSH/IPv6池/随机出网）"

  rm -f "$TUNE_SYSCTL_FILE" "$DMIT_TCP_DEFAULT_FILE" >/dev/null 2>&1 || true
  rm -f "$IPV6_SYSCTL_FILE" "$IPV6_FIX_SYSCTL_FILE" >/dev/null 2>&1 || true

  if [[ -f "${BACKUP_BASE}/gai.conf.orig" ]]; then
    cp -a "${BACKUP_BASE}/gai.conf.orig" "$GAI_CONF" 2>/dev/null || true
  else
    [[ -f "$GAI_CONF" ]] && sed -i -E '/^[[:space:]]*precedence[[:space:]]+::ffff:0:0\/96[[:space:]]+[0-9]+[[:space:]]*$/d' "$GAI_CONF" || true
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

    systemctl disable dmit-ipv6-pool.service >/dev/null 2>&1 || true
    systemctl stop dmit-ipv6-pool.service >/dev/null 2>&1 || true
    rm -f "$IPV6_POOL_SERVICE" || true

    systemctl disable dmit-ipv6-rand.service >/dev/null 2>&1 || true
    systemctl stop dmit-ipv6-rand.service >/dev/null 2>&1 || true
    rm -f "$IPV6_RAND_SERVICE" >/dev/null 2>&1 || true

    systemctl daemon-reload >/dev/null 2>&1 || true
  fi

  have_cmd nft && nft delete table inet dmitbox_rand6 >/dev/null 2>&1 || true
  rm -f "$IPV6_RAND_NFT" "$IPV6_RAND_CONF" "$IPV6_POOL_CONF" >/dev/null 2>&1 || true

  ip link set dev "$ifc" mtu 1500 >/dev/null 2>&1 || true

  if [[ -f "$SSH_ORIG_TGZ" ]]; then
    tar -xzf "$SSH_ORIG_TGZ" -C / 2>/dev/null || true
    rm -f "$SSH_DROPIN_FILE" 2>/dev/null || true
    sshd_restart || true
  fi

  sysctl_apply_all
  restart_network_services_best_effort
  sleep 1

  ok "已还原（建议再跑一次“网络体检”确认状态）"
}

# ---------------- 主菜单 ----------------
menu() {
  RUN_MODE="menu"
  while true; do
    banner

    echo -e "${c_bold}${c_white}【网络】${c_reset}"
    echo -e "  ${c_cyan}1${c_reset}) 网络体检（只看状态）"
    echo -e "  ${c_cyan}2${c_reset}) 体检 + 自动修复（重拉IPv6/刷新DNS）"
    echo -e "  ${c_cyan}3${c_reset}) 开启 IPv6（重拉地址/路由）"
    echo -e "  ${c_cyan}4${c_reset}) 关闭 IPv6（系统级禁用）"
    echo -e "  ${c_cyan}5${c_reset}) DNS 切换（CF/Google/Quad9）"
    echo -e "  ${c_cyan}6${c_reset}) DNS 恢复（回到备份）"
    echo -e "  ${c_cyan}7${c_reset}) MTU 工具（探测/设置/持久化）"
    echo -e "  ${c_cyan}8${c_reset}) IPv4 优先（解析优先）"
    echo -e "  ${c_cyan}9${c_reset}) IPv6 优先（恢复默认）"
    echo -e "  ${c_cyan}10${c_reset}) 恢复 IPv4/IPv6 优先级（用备份还原）"
    echo -e "  ${c_cyan}11${c_reset}) IPv6 /64 工具（地址池 / 随机出网）"

    echo
    echo -e "${c_bold}${c_white}【TCP/BBR】${c_reset}"
    echo -e "  ${c_cyan}12${c_reset}) TCP 通用调优（BBR+FQ）"
    echo -e "  ${c_cyan}13${c_reset}) 恢复 Linux 默认 TCP（CUBIC）"
    echo -e "  ${c_cyan}14${c_reset}) 恢复 DMIT 默认 TCP"
    echo -e "  ${c_cyan}15${c_reset}) BBR 支持性检测"
    echo -e "  ${c_cyan}16${c_reset}) 安装 BBRv3（XanMod 内核，需要重启）"

    echo
    echo -e "${c_bold}${c_white}【系统/安全】${c_reset}"
    echo -e "  ${c_cyan}17${c_reset}) 设置时区为中国（Asia/Shanghai）"
    echo -e "  ${c_cyan}18${c_reset}) SSH 安全工具（密码/密钥/换端口）"
    echo -e "  ${c_cyan}19${c_reset}) 一键 DD 重装系统（高风险）"

    echo
    echo -e "${c_bold}${c_white}【测试】${c_reset}"
    echo -e "  ${c_cyan}20${c_reset}) 一键测试脚本（GB5/Bench/回程/IP质量/解锁）"

    echo
    echo -e "${c_bold}${c_white}【工具】${c_reset}"
    echo -e "  ${c_cyan}21${c_reset}) 一键还原（撤销本脚本改动）"
    echo -e "  ${c_cyan}22${c_reset}) 保存环境快照（发工单用）"
    echo -e "  ${c_cyan}23${c_reset}) 换IP防失联（cloud-init/QGA 工具）"

    echo
    echo -e "  ${c_cyan}0${c_reset}) 退出"
    echo -e "${c_dim}----------------------------------------------${c_reset}"

    local choice=""
    read_tty choice "选择> " ""

    case "$choice" in
      1) health_check_only; pause_main ;;
      2) health_check_autofix; pause_main ;;
      3) ipv6_enable; pause_main ;;
      4) ipv6_disable; pause_main ;;
      5) dns_switch_menu ;;
      6) dns_restore; pause_main ;;
      7) mtu_menu ;;
      8) prefer_ipv4; pause_main ;;
      9) prefer_ipv6; pause_main ;;
      10) restore_gai_default; pause_main ;;
      11) ipv6_tools_menu ;;
      12) tcp_tune_apply; pause_main ;;
      13) tcp_restore_default; pause_main ;;
      14) tcp_restore_dmit_default; pause_main ;;
      15) bbr_check; pause_main ;;
      16) bbrv3_install_xanmod; pause_main ;;
      17) set_timezone_china; pause_main ;;
      18) ssh_menu ;;
      19) dd_reinstall; pause_main ;;
      20) tests_menu ;;
      21) restore_all; pause_main ;;
      22) env_snapshot; pause_main ;;
      23) cloudinit_qga_menu ;;
      0) exit 0 ;;
      *) warn "无效选项"; pause_main ;;
    esac
  done
}

main() {
  need_root
  menu
}
main "$@"
