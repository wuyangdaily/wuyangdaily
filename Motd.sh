#!/bin/bash

# 1. 权限检查
if [ "$EUID" -ne 0 ]; then 
  echo "错误：请以 root 权限运行此脚本"
  exit 1
fi

# 2. 自动识别系统并清理默认信息
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS=$ID
else
    OS="unknown"
fi

case "$OS" in
    ubuntu|debian)
        true > /etc/motd
        true > /etc/issue
        true > /etc/issue.net
        [ -d /etc/update-motd.d ] && chmod -x /etc/update-motd.d/* 2>/dev/null || true
        ;;
    armbian)
        chmod -x /etc/update-motd.d/* 2>/dev/null || true
        [ -f /etc/default/armbian-motd ] && sed -i 's/ENABLED=true/ENABLED=false/' /etc/default/armbian-motd 2>/dev/null
        ;;
    alpine)
        true > /etc/motd
        true > /etc/issue
        if ! command -v bash >/dev/null 2>&1; then apk add bash 2>/dev/null; fi
        ;;
    *)
        true > /etc/motd
        ;;
esac

# 3. 彻底禁止 SSH 和 PAM 产生的任何登录提示（实现“全部禁止”）
# --------------------------------------------
# 3.1 SSH 配置：PrintMotd, PrintLastLog, Banner
SSHD_CONFIG="/etc/ssh/sshd_config"
if [ -f "$SSHD_CONFIG" ]; then
    # 强制关闭 PrintMotd
    if grep -q '^[#]*\s*PrintMotd' "$SSHD_CONFIG"; then
        sed -i 's/^[#]*\s*PrintMotd.*/PrintMotd no/' "$SSHD_CONFIG"
    else
        echo 'PrintMotd no' >> "$SSHD_CONFIG"
    fi
    # 强制关闭 PrintLastLog
    if grep -q '^[#]*\s*PrintLastLog' "$SSHD_CONFIG"; then
        sed -i 's/^[#]*\s*PrintLastLog.*/PrintLastLog no/' "$SSHD_CONFIG"
    else
        echo 'PrintLastLog no' >> "$SSHD_CONFIG"
    fi
    # 删除任何 Banner 行
    sed -i '/^Banner /d' "$SSHD_CONFIG"
fi

# 3.2 PAM 禁用 pam_motd.so（避免 PAM 层再次输出）
for pamfile in /etc/pam.d/sshd /etc/pam.d/login; do
    if [ -f "$pamfile" ]; then
        # 注释掉所有包含 pam_motd.so 且未被注释的行
        sed -i 's/^\([^#]*pam_motd\.so\)/#\1/' "$pamfile"
    fi
done

# 3.3 清空可能残留的动态 MOTD 文件
for dynamic_motd in /run/motd.dynamic /etc/motd.dynamic /var/run/motd.dynamic; do
    [ -f "$dynamic_motd" ] && true > "$dynamic_motd"
done

# 3.4 确保 /etc/update-motd.d 内所有脚本不可执行（再次确认）
[ -d /etc/update-motd.d ] && chmod -x /etc/update-motd.d/* 2>/dev/null

# 3.5 重启 SSH 服务（使上述修改生效）
if command -v systemctl >/dev/null 2>&1; then
    systemctl restart ssh 2>/dev/null || systemctl restart sshd 2>/dev/null
elif [ -f /etc/init.d/ssh ]; then
    /etc/init.d/ssh restart
else
    echo "警告：无法自动重启 SSH 服务，请手动重启"
fi

# 4. 写入你的自定义 MOTD 脚本（完全保留原始内容）
TARGET_PATH="/etc/profile.d/custom-motd.sh"

cat << 'EOF' > $TARGET_PATH
#!/bin/bash

# 颜色定义
GREEN='\033[1;32m'; CYAN='\033[1;96m'; YELLOW='\033[1;33m'; RED='\033[1;31m'; RESET='\033[0m'

# 1. 基础信息采集
USER_NAME=$(whoami)
HOSTNAME=$(hostname)
OS_VER=$(grep "PRETTY_NAME" /etc/os-release | cut -d '"' -f2)

# 时间与星期
CURRENT_DATE=$(date '+%Y-%m-%d %H:%M:%S')
WEEKDAY_NUM=$(date '+%u')
case "$WEEKDAY_NUM" in
  1) WEEKDAY="星期一" ;; 2) WEEKDAY="星期二" ;; 3) WEEKDAY="星期三" ;;
  4) WEEKDAY="星期四" ;; 5) WEEKDAY="星期五" ;; 6) WEEKDAY="星期六" ;;
  7) WEEKDAY="星期日" ;; *) WEEKDAY="未知" ;;
esac

# CPU 内存与磁盘
MEM_INFO=$(free -h | grep -Ei "mem|内存" | awk '{print $3 " / " $2}')
DISK_INFO=$(df -h / | awk 'NR==2 {print $3 " / " $2 " ("$5")"}')
DISK_PERCENT=$(df / | awk 'NR==2 {print $5}' | sed 's/%//')
UPTIME=$(uptime -p | sed 's/up //')
LAST_UPDATE=$(stat -c %y /var/log/apt/history.log 2>/dev/null | cut -d '.' -f1 || echo "Unknown")
CPU_USAGE=$(top -bn1 | grep "Cpu(s)" | awk '{printf "%.1f%%", 100 - $8}')

# 2. Docker 详细状态与容器分类
if command -v docker &> /dev/null; then
    RUNNING_APPS=$(docker ps --format "{{.Names}}" | sort)
    EXITED_APPS=$(docker ps -a --filter "status=exited" --filter "status=created" --format "{{.Names}}" | sort)
    D_TOTAL_COUNT=$(docker ps -a -q | wc -l)
    D_IMAGES=$(docker images -q | wc -l)
    D_STATUS="✅ Docker 运行中：容器 $D_TOTAL_COUNT 个，镜像 $D_IMAGES 个"
    DOCKER_VER=$(docker --version | awk '{print $3}' | sed 's/,//')
    if docker compose version >/dev/null 2>&1; then
        COMPOSE_VER=$(docker compose version --short)
    elif command -v docker-compose &> /dev/null; then
        COMPOSE_VER=$(docker-compose version --short)
    else
        COMPOSE_VER="未安装"
    fi
else
    D_STATUS="❌ 未安装 Docker"
    DOCKER_VER="未安装"
    COMPOSE_VER="未安装"
fi

# 3. 输出界面
echo -e "${GREEN}👋 欢迎回来, ${USER_NAME}!${RESET}"
echo -e "${CYAN}------------------------------------------------------------${RESET}"
echo -e "⏰ 当前时间:${RESET}    ${CYAN}${CURRENT_DATE} (${WEEKDAY})${RESET}"
echo -e "🆙 运行时间:${RESET}    ${CYAN}${UPTIME}${RESET}"
echo -e "🖥 CPU 使用:${RESET}    ${CYAN}${CPU_USAGE}${RESET}"
echo -e "💾 内存使用:${RESET}    ${CYAN}${MEM_INFO}${RESET}"
echo -e "🗂 磁盘使用:${RESET}    ${CYAN}${DISK_INFO}${RESET}"
echo -e "📦 系统更新:${RESET}    ${CYAN}${LAST_UPDATE}${RESET}"
echo -e "🖥 系统版本:${RESET}    ${CYAN}${OS_VER}${RESET}"
echo -e "📦 Docker 版本:${RESET}    ${CYAN}${DOCKER_VER}${RESET}"
echo -e "📦 Compose 版本:${RESET}   ${CYAN}${COMPOSE_VER}${RESET}"
echo -e "${CYAN}------------------------------------------------------------${RESET}"

# 4. Docker 统计
echo -e "\n${YELLOW}🐳 Docker 状态:${RESET}   ${D_STATUS}"
[ -n "$RUNNING_APPS" ] && for app in $RUNNING_APPS; do echo -e "${GREEN}✅ $app 运行中${RESET}"; done
[ -n "$EXITED_APPS" ] && for app in $EXITED_APPS; do echo -e "${RED}❌ $app 未运行${RESET}"; done

# 5. 最近登录记录
if command -v last &> /dev/null; then
    echo -e "\n${YELLOW}🛡 最近登录记录:${RESET}"
    last -i -n 3 | grep -vE "reboot|wtmp" | awk '{printf "%s   %s   %s   %s %s %s %s\n", $1, $2, $3, $4, $5, $6, $7}'
fi

# 6. 磁盘告警
if [ "$DISK_PERCENT" -ge 70 ]; then
    echo -e "\n${RED}💔 警告：磁盘使用率已达到 ${DISK_PERCENT}% ，请及时清理！${RESET}"
fi
echo ""
EOF

# 5. 设置权限
chmod +x $TARGET_PATH
echo "✅ 安装成功！请重新连接 SSH 终端查看效果。"
