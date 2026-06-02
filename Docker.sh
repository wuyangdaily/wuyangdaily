#!/bin/bash
# 🐳 Docker 工具箱 v1.3.6  by：万物皆可盘

set -e

# -------------------------
# 基础变量
# -------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="/var/log/docker-toolkit.log"
CONF_DIR="/etc/docker-toolkit"

mkdir -p "$CONF_DIR" 2>/dev/null || true

# -------------------------
# 权限检查
# -------------------------
[ "${EUID:-0}" -ne 0 ] && echo "错误：请以 root 权限运行" && exit 1

# -------------------------
# 操作系统检测
# -------------------------
detect_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS="$ID"
        case "$OS" in
            archlinux) OS="arch" ;;
            opensuse-leap|opensuse-tumbleweed) OS="suse" ;;
            alpine) OS="alpine" ;;
            centos|rocky|rhel|fedora|ubuntu|debian|armbian) ;;
            *) OS=$(uname -s | tr '[:upper:]' '[:lower:]') ;;
        esac
    else
        OS=$(uname -s | tr '[:upper:]' '[:lower:]')
    fi
    export OS
}
detect_os

log() {
    local msg="$*"
    mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null || true

    if [ -f "$LOG_FILE" ]; then
        file_size=$(stat -c%s "$LOG_FILE" 2>/dev/null || true)
        if [ -n "$file_size" ] && [ "$file_size" -gt 5242880 ]; then
            > "$LOG_FILE"
        fi
    fi
    
    echo "$(date '+%F %T') $msg" | tee -a "$LOG_FILE" >/dev/null
}

pause_return() {
    echo
    read -r -p "↩ 按回车返回菜单..."
}

ensure_root_dir() {
    if [ ! -d "/root" ]; then
        echo "📁 /root 目录不存在，正在创建..."
        mkdir -p /root
        echo "✅ /root 目录已创建"
    fi
}

safe_name() {
    echo "$1" | sed 's#[/[:space:]:]#_#g'
}

get_beijing_time() {
    TZ='Asia/Shanghai' date +"%Y%m%d_%H%M%S"
}

# -------------------------
# 确保 nano 编辑器已安装
# -------------------------
ensure_nano_installed() {
    if command -v nano &>/dev/null; then
        return 0
    fi
    echo "📦 未检测到 nano 编辑器，正在自动安装..."
    case "$OS" in
        ubuntu|debian|armbian)
            apt update || true
            apt install -y nano || true
            ;;
        centos|rocky|fedora|rhel)
            dnf -y install nano || true
            ;;
        arch)
            pacman -Sy --noconfirm nano || true
            ;;
        suse)
            zypper install -y nano || true
            ;;
        alpine)
            apk add nano || true
            ;;
        *)
            echo "⚠️ 无法自动安装 nano，请手动安装后重试"
            return 1
            ;;
    esac
    echo "✅ nano 安装完成"
}

# -------------------------
# 格式化容器状态
# -------------------------
format_container_status() {
    local status="$1"
    if [[ "$status" == Up* ]]; then
        echo "🟢 运行中"
    elif [[ "$status" == Exited* ]]; then
        echo "🔴 已停止"
    elif [[ "$status" == Created* ]]; then
        status="${status/Created/已创建}"
        status="${status//seconds ago/秒前}"
        status="${status//minutes ago/分钟前}"
        status="${status//hours ago/小时前}"
        status="${status//days ago/天前}"
        status="${status//weeks ago/周前}"
        status="${status//months ago/月前}"
        status="${status//years ago/年前}"
        echo "🟡 $status"
    elif [[ "$status" == Restarting* ]]; then
        status="${status/Restarting/重启中}"
        status="${status//seconds ago/秒前}"
        status="${status//minutes ago/分钟前}"
        status="${status//hours ago/小时前}"
        status="${status//days ago/天前}"
        status="${status//weeks ago/周前}"
        status="${status//months ago/月前}"
        status="${status//years ago/年前}"
        echo "🟡 $status"
    elif [[ "$status" == Paused* ]]; then
        echo "🟡 已暂停"
    elif [[ "$status" == Dead* ]]; then
        echo "🟡 已死亡"
    else
        echo "🟡 $status"
    fi
}

get_compose_cmd() {
    if docker compose version >/dev/null 2>&1; then
        echo "docker compose"
    elif command -v docker-compose >/dev/null 2>&1; then
        echo "docker-compose"
    else
        return 1
    fi
}

require_cmds() {
    local missing=()
    local c
    for c in "$@"; do
        command -v "$c" >/dev/null 2>&1 || missing+=("$c")
    done
    if [ "${#missing[@]}" -gt 0 ]; then
        echo "⚠️ 缺少依赖: ${missing[*]}"
        return 1
    fi
}

ensure_base_deps() {
    require_cmds docker jq curl zip unzip tar || return 1
}

TOOLBOX_LOCK_FILE="/tmp/docker-toolbox.runtime.lock"

enter_toolbox_runtime() {
    : > "$TOOLBOX_LOCK_FILE"
}

leave_toolbox_runtime() {
    rm -f "$TOOLBOX_LOCK_FILE"
}

container_exists() {
    local name=$1
    docker ps -a --format "{{.Names}}" | grep -qx "$name"
}

get_container_image() {
    local name=$1
    docker inspect -f '{{.Config.Image}}' "$name" 2>/dev/null
}

get_container_bind_source_by_dest() {
    local inspect_file=$1
    local dest=$2
    jq -r --arg dest "$dest" '
        .[0].Mounts[]?
        | select(.Type=="bind" and .Destination==$dest)
        | .Source
    ' "$inspect_file" | head -n1
}

infer_data_dir_from_container() {
    local service=$1
    local container=$2
    local inspect_file
    inspect_file=$(mktemp)
    trap 'rm -f "$inspect_file"' EXIT

    docker inspect "$container" > "$inspect_file"

    local result="/root"
    case "$service" in
        npm)
            local data_src
            data_src=$(get_container_bind_source_by_dest "$inspect_file" "/data")
            if [ -n "$data_src" ] && [ "$data_src" != "null" ]; then
                result=$(dirname "$data_src")
            fi
            ;;
        portainer)
            local data_src
            data_src=$(get_container_bind_source_by_dest "$inspect_file" "/data")
            if [ -n "$data_src" ] && [ "$data_src" != "null" ]; then
                result="$data_src"
            fi
            ;;
        lucky)
            local conf_src
            conf_src=$(get_container_bind_source_by_dest "$inspect_file" "/app/conf")
            if [ -n "$conf_src" ] && [ "$conf_src" != "null" ]; then
                result="$conf_src"
            fi
            ;;
        *)
            local first_bind
            first_bind=$(jq -r '.[0].Mounts[]? | select(.Type=="bind") | .Source' "$inspect_file" | head -n1 || true)
            if [ -n "$first_bind" ] && [ "$first_bind" != "null" ]; then
                result="$first_bind"
            fi
            ;;
    esac

    echo "$result"
}

save_service_config() {
    local service=$1
    local image=$2
    local data_dir=$3
    local extra_params=${4:-}
    cat > "$CONF_DIR/${service}.conf" <<EOF
IMAGE=$(printf '%q' "$image")
DATA_DIR=$(printf '%q' "$data_dir")
EXTRA_PARAMS=$(printf '%q' "$extra_params")
EOF
}

load_service_config() {
    local service=$1
    if [ -f "$CONF_DIR/${service}.conf" ]; then
        # shellcheck disable=SC1090
        source "$CONF_DIR/${service}.conf"
        return 0
    fi
    return 1
}

remove_service_config() {
    local service=$1
    rm -f "$CONF_DIR/${service}.conf"
}

build_service_run_cmd() {
    local service=$1
    local image=$2
    local container_name=$3
    local data_dir=$4

    case "$service" in
        npm)
            printf 'docker run -d --name %q --restart=always -p 80:80 -p 81:81 -p 443:443 -v %q:/data -v %q:/etc/letsencrypt %q' \
                "$container_name" \
                "${data_dir}/data" \
                "${data_dir}/letsencrypt" \
                "$image"
            ;;
        portainer)
            printf 'docker run -d --name %q --privileged=true --restart=always -p 9000:9000 -v %q:/data -v /var/run/docker.sock:/var/run/docker.sock %q' \
                "$container_name" \
                "$data_dir" \
                "$image"
            ;;
        lucky)
            printf 'docker run -d --name %q --network host --privileged=true --restart=always -v %q:/app/conf -v /var/run/docker.sock:/var/run/docker.sock %q' \
                "$container_name" \
                "$data_dir" \
                "$image"
            ;;
        *)
            return 1
            ;;
    esac
}

# -------------------------
# 通用服务更新函数
# -------------------------
update_docker_service() {
    local service=$1
    local display_name=$2
    local default_name=$3

    echo "🔄 正在更新 $display_name ..."

    local image_keyword=""
    case "$service" in
        npm)       image_keyword="nginx-proxy-manager" ;;
        portainer) image_keyword="portainer" ;;
        lucky)     image_keyword="lucky" ;;
        *)         image_keyword="" ;;
    esac

    local actual_container=""
    if [ -n "$image_keyword" ]; then
        actual_container=$(docker ps -a --format "{{.Names}} {{.Image}}" | grep -i "$image_keyword" | head -n1 | awk '{print $1}' || true)
    fi

    if [ -z "$actual_container" ]; then
        if load_service_config "$service" && container_exists "$default_name"; then
            actual_container="$default_name"
        fi
    fi

    if [ -z "$actual_container" ]; then
        echo "⚠️ 未找到 $display_name 的安装配置，且没有检测到运行中的容器。请先安装。"
        return
    fi

    echo "📦 检测到容器: $actual_container"

    local IMAGE DATA_DIR
    IMAGE=$(get_container_image "$actual_container")
    DATA_DIR=$(infer_data_dir_from_container "$service" "$actual_container")

    if [ "$service" = "npm" ] && [ "$DATA_DIR" = "/root" ]; then
        local inspect_file
        inspect_file=$(mktemp)
        docker inspect "$actual_container" > "$inspect_file"
        local lets_src
        lets_src=$(get_container_bind_source_by_dest "$inspect_file" "/etc/letsencrypt")
        rm -f "$inspect_file"
        if [ -n "$lets_src" ] && [ "$lets_src" != "null" ]; then
            DATA_DIR=$(dirname "$lets_src")
        fi
    fi

    if [ -z "$IMAGE" ] || [ -z "$DATA_DIR" ]; then
        echo "⚠️ 无法获取镜像或数据目录，更新失败"
        return 1
    fi

    save_service_config "$service" "$IMAGE" "$DATA_DIR" "" || true

    if container_exists "$actual_container"; then
        echo "📌 停止并删除旧容器: $actual_container"
        docker stop "$actual_container" >/dev/null 2>&1 || true
        docker rm "$actual_container" >/dev/null 2>&1 || true
    fi

    echo "📥 拉取最新镜像: $IMAGE"
    docker pull "$IMAGE" || {
        echo "⚠️ 镜像拉取失败"
        return 1
    }

    echo "🚀 重新创建容器（名称: $default_name）..."
    local run_cmd
    run_cmd=$(build_service_run_cmd "$service" "$IMAGE" "$default_name" "$DATA_DIR")
    eval "$run_cmd" || {
    echo "⚠️ 重建容器失败"
    return 1
    }

    echo "✅ $display_name 更新完成"
}

# -------------------------
# 通用服务卸载函数
# -------------------------
uninstall_docker_service() {
    local service=$1
    local display_name=$2
    local default_name=$3
    local default_image=$4

    local image_keyword=""
    case "$service" in
        npm)       image_keyword="nginx-proxy-manager" ;;
        portainer) image_keyword="portainer" ;;
        lucky)     image_keyword="lucky" ;;
        *)         image_keyword="" ;;
    esac

    local actual_container=""
    if [ -n "$image_keyword" ]; then
        actual_container=$(docker ps -a --format "{{.Names}} {{.Image}}" | grep -i "$image_keyword" | head -n1 | awk '{print $1}' || true)
    fi
    if [ -z "$actual_container" ] && container_exists "$default_name"; then
        actual_container="$default_name"
    fi

    local config_exists_flag=false
    if [ -f "$CONF_DIR/${service}.conf" ]; then
        config_exists_flag=true
        load_service_config "$service" || true
    fi

    local image_to_remove="$default_image"
    local data_dir_to_remove=""
    if [ "$config_exists_flag" = true ]; then
        [ -n "${IMAGE:-}" ] && image_to_remove="$IMAGE"
        [ -n "${DATA_DIR:-}" ] && data_dir_to_remove="$DATA_DIR"
    fi

    if [ -z "$actual_container" ] && [ "$config_exists_flag" = false ]; then
        echo "⚠️ $display_name 未安装，无需卸载。"
        return
    fi

    echo "⚠️ 即将卸载 $display_name (容器: ${actual_container:-未找到}, 镜像: $image_to_remove)"
    read -r -p "确认卸载？该操作会删除容器、镜像、数据目录及配置文件 (Y/N): " confirm
    [[ ! "$confirm" =~ ^[Yy]$ ]] && echo "已取消" && return 0

    if [ -n "$actual_container" ]; then
        echo "🗑 删除容器: $actual_container"
        docker stop "$actual_container" >/dev/null 2>&1 || true
        docker rm "$actual_container" >/dev/null 2>&1 || true
    fi

    if docker image inspect "$image_to_remove" &>/dev/null; then
        echo "🗑 删除镜像: $image_to_remove"
        docker rmi "$image_to_remove" 2>/dev/null || echo "⚠️ 镜像被其他容器引用，跳过删除"
    fi

    if [ "$config_exists_flag" = true ]; then
        if [ -n "$data_dir_to_remove" ] && [ -d "$data_dir_to_remove" ]; then
            read -r -p "是否删除数据目录 $data_dir_to_remove ? (Y/N): " del_data
            if [[ "$del_data" =~ ^[Yy]$ ]]; then
                rm -rf "$data_dir_to_remove"
                echo "✅ 已删除数据目录"
            fi
        fi
        remove_service_config "$service"
    fi

    echo "✅ $display_name 卸载完成"
}

# -------------------------
# 智能 Docker 源
# -------------------------
get_docker_sources() {
    case "$OS" in
        ubuntu|debian)
            SOURCES=(
                "https://download.docker.com/linux/$OS"
                "https://mirrors.aliyun.com/docker-ce/linux/$OS"
                "https://mirrors.ustc.edu.cn/docker-ce/linux/$OS"
                "https://mirrors.tuna.tsinghua.edu.cn/docker-ce/linux/$OS"
                "https://repo.huaweicloud.com/docker-ce/linux/$OS"
                "https://download.daocloud.io/docker-ce/linux/$OS"
                "https://mirrors.163.com/docker-ce/linux/$OS"
                "https://mirrors.cloud.tencent.com/docker-ce/linux/$OS"
                "https://mirror.sjtu.edu.cn/docker-ce/linux/$OS"
                "https://mirrors.zju.edu.cn/docker-ce/linux/$OS"
            )
            ;;
        armbian)
            SOURCES=(
                "https://download.docker.com/linux/debian"
                "https://mirrors.aliyun.com/docker-ce/linux/debian"
                "https://mirrors.ustc.edu.cn/docker-ce/linux/debian"
                "https://mirrors.tuna.tsinghua.edu.cn/docker-ce/linux/debian"
                "https://repo.huaweicloud.com/docker-ce/linux/debian"
                "https://download.daocloud.io/docker-ce/linux/debian"
                "https://mirrors.163.com/docker-ce/linux/debian"
                "https://mirrors.cloud.tencent.com/docker-ce/linux/debian"
                "https://mirror.sjtu.edu.cn/docker-ce/linux/debian"
                "https://mirrors.zju.edu.cn/docker-ce/linux/debian"
            )
            ;;
        centos|rocky|rhel)
            SOURCES=(
                "https://download.docker.com/linux/centos"
                "https://mirrors.aliyun.com/docker-ce/linux/centos"
                "https://mirrors.ustc.edu.cn/docker-ce/linux/centos"
                "https://mirrors.tuna.tsinghua.edu.cn/docker-ce/linux/centos"
                "https://repo.huaweicloud.com/docker-ce/linux/centos"
                "https://download.daocloud.io/docker-ce/linux/centos"
                "https://mirrors.163.com/docker-ce/linux/centos"
                "https://mirrors.cloud.tencent.com/docker-ce/linux/centos"
                "https://mirror.sjtu.edu.cn/docker-ce/linux/centos"
                "https://mirrors.zju.edu.cn/docker-ce/linux/centos"
            )
            ;;
        fedora)
            SOURCES=(
                "https://download.docker.com/linux/fedora"
                "https://mirrors.aliyun.com/docker-ce/linux/fedora"
                "https://mirrors.ustc.edu.cn/docker-ce/linux/fedora"
                "https://mirrors.tuna.tsinghua.edu.cn/docker-ce/linux/fedora"
                "https://repo.huaweicloud.com/docker-ce/linux/fedora"
                "https://download.daocloud.io/docker-ce/linux/fedora"
                "https://mirrors.163.com/docker-ce/linux/fedora"
                "https://mirrors.cloud.tencent.com/docker-ce/linux/fedora"
                "https://mirror.sjtu.edu.cn/docker-ce/linux/fedora"
                "https://mirrors.zju.edu.cn/docker-ce/linux/fedora"
            )
            ;;
        arch)
            SOURCES=("https://archlinux.org/packages/community/x86_64/docker")
            ;;
        suse)
            SOURCES=("https://download.opensuse.org/repositories/Virtualization:containers/openSUSE_Leap_15.5/")
            ;;
        alpine)
            SOURCES=("official")
            ;;
        *)
            SOURCES=("official")
            ;;
    esac
}

try_docker_source() {
    if [ "$OS" = "arch" ] || [ "$OS" = "suse" ] || [ "$OS" = "alpine" ]; then
        DOCKER_SRC="official"
        return 0
    fi

    for SRC in "${SOURCES[@]}"; do
        echo "尝试 Docker 源: $SRC"
        if [[ "$OS" =~ ^(centos|rocky|rhel|fedora)$ ]]; then
            if curl -fsSL "$SRC/docker-ce.repo" >/dev/null 2>&1; then
                DOCKER_SRC="$SRC"
                return 0
            fi
        else
            if [[ "$SRC" == "official" ]] || curl -fsSL "$SRC/gpg" >/dev/null 2>&1; then
                DOCKER_SRC="$SRC"
                return 0
            fi
        fi
    done
    echo "⚠️ 所有 Docker 源不可用"
    return 1
}

# -------------------------
# Docker 安装 / 更新 / 卸载
# -------------------------
install_docker() {
    echo "🚀 安装 Docker & Compose..."

# -------------------------
# 自动优化 inotify 上限
# -------------------------
if command -v sysctl >/dev/null 2>&1; then
    CURRENT_WATCHES=$(sysctl -n fs.inotify.max_user_watches 2>/dev/null || echo 0)
    if [ "$CURRENT_WATCHES" -lt 524288 ]; then
        echo "⚠️ inotify 上限较低（当前 $CURRENT_WATCHES），自动调整到 524288"
        [ -f /etc/sysctl.d/99-docker.conf ] && echo "ℹ️ 将覆盖已有 sysctl 优化配置"
        cat > /etc/sysctl.d/99-docker.conf <<EOF
fs.inotify.max_user_watches=524288
fs.inotify.max_user_instances=512
EOF
        sysctl --system >/dev/null 2>&1 || true
        echo "✅ inotify 已优化"
    else
        echo "ℹ️ inotify 已达推荐值（$CURRENT_WATCHES）"
    fi
fi

# -------------------------
# 自动优化文件描述符
# -------------------------
CURRENT_NOFILE=$(ulimit -n)
if [ "$CURRENT_NOFILE" -lt 524288 ]; then
    echo "⚠️ 文件描述符过低（当前 $CURRENT_NOFILE），自动调整到 524288"
    sed -i '/^\*\s\+soft\s\+nofile/d' /etc/security/limits.conf || true
    sed -i '/^\*\s\+hard\s\+nofile/d' /etc/security/limits.conf || true
    echo "* soft nofile 524288" >> /etc/security/limits.conf || true
    echo "* hard nofile 524288" >> /etc/security/limits.conf || true
    sed -i '/DefaultLimitNOFILE/d' /etc/systemd/system.conf || true
    sed -i '/DefaultLimitNOFILE/d' /etc/systemd/user.conf || true
    echo "DefaultLimitNOFILE=524288" >> /etc/systemd/system.conf || true
    echo "DefaultLimitNOFILE=524288" >> /etc/systemd/user.conf || true
    systemctl daemon-reexec 2>/dev/null || true
    ulimit -n 524288 2>/dev/null || true
    echo "✅ 文件描述符已优化"
    echo "ℹ️ 当前会话已生效，永久生效需重新登录"
else
    echo "ℹ️ 文件描述符已达推荐值（$CURRENT_WATCHES）"
fi

echo "=============================="
echo "ℹ️ inotify 当前值: $(sysctl -n fs.inotify.max_user_watches)"
echo "ℹ️ 文件描述符当前值: $(ulimit -n)"
echo "=============================="

    get_docker_sources

    # ---------- arch / suse / alpine ----------
    case "$OS" in
        arch)
            pacman -Sy --noconfirm docker docker-compose
            systemctl enable --now docker >/dev/null 2>&1 || true
            REAL_USER=$(logname 2>/dev/null || echo "${SUDO_USER:-}")
            if [ -n "$REAL_USER" ] && [ "$REAL_USER" != "root" ] && id "$REAL_USER" &>/dev/null; then
                usermod -aG docker "$REAL_USER" || true
                echo "✅ 已将用户 $REAL_USER 加入 docker 组"
            fi
            echo "✅ 安装完成"
            return 0
            ;;
        suse)
            zypper refresh
            zypper install -y docker docker-compose
            systemctl enable --now docker >/dev/null 2>&1 || true
            REAL_USER=$(logname 2>/dev/null || echo "${SUDO_USER:-}")
            if [ -n "$REAL_USER" ] && [ "$REAL_USER" != "root" ] && id "$REAL_USER" &>/dev/null; then
                usermod -aG docker "$REAL_USER" || true
                echo "✅ 已将用户 $REAL_USER 加入 docker 组"
            fi
            echo "✅ 安装完成"
            return 0
            ;;
        alpine)
            apk add --no-cache docker docker-compose
            REAL_USER=$(logname 2>/dev/null || echo "${SUDO_USER:-}")
            if [ -n "$REAL_USER" ] && [ "$REAL_USER" != "root" ] && id "$REAL_USER" &>/dev/null; then
                addgroup "$REAL_USER" docker 2>/dev/null || true
                echo "✅ 已将用户 $REAL_USER 加入 docker 组"
            fi
            echo "✅ 安装完成"
            return 0
            ;;
    esac

    # ---------- Ubuntu / Debian / Armbian ----------
    if [[ "$OS" =~ ^(ubuntu|debian|armbian)$ ]]; then
        apt update || true
        echo "📦 正在升级系统软件包..."
        apt upgrade -y -qq 2>/dev/null || apt upgrade -y || true
        apt install -y ca-certificates curl gnupg lsb-release || true
        mkdir -p /etc/apt/keyrings

        echo -e "\n🧹 自动清理不再需要的依赖包..."
        apt autoremove -y || true

        local success=0
        for src in "${SOURCES[@]}"; do
            echo "🔍 尝试使用源: $src"
            rm -f /etc/apt/keyrings/docker.gpg /etc/apt/keyrings/docker.asc
            rm -f /etc/apt/sources.list.d/docker.list

            local KEYRING
            local codename
            codename=$(lsb_release -cs)

            if [[ "$src" == "https://download.docker.com/linux/ubuntu" ]] || [[ "$src" == "https://download.docker.com/linux/debian" ]]; then
                KEYRING="/etc/apt/keyrings/docker.asc"
                if curl -fsSL "$src/gpg" -o "$KEYRING" 2>/dev/null; then
                    chmod a+r "$KEYRING" || true
                    echo "deb [arch=$(dpkg --print-architecture) signed-by=$KEYRING] $src $codename stable" > /etc/apt/sources.list.d/docker.list
                else
                    echo "⚠️ 官方源 GPG 密钥下载失败，尝试下一个源"
                    continue
                fi
            else
                KEYRING="/etc/apt/keyrings/docker.gpg"
                if curl -fsSL "$src/gpg" -o /tmp/docker.gpg 2>/dev/null; then
                    gpg --dearmor -o "$KEYRING" < /tmp/docker.gpg 2>/dev/null || true
                    rm -f /tmp/docker.gpg
                    chmod a+r "$KEYRING" || true
                    echo "deb [arch=$(dpkg --print-architecture) signed-by=$KEYRING] $src $codename stable" > /etc/apt/sources.list.d/docker.list
                else
                    echo "⚠️ 镜像源 GPG 密钥下载失败，尝试下一个"
                    continue
                fi
            fi

            if apt update 2>&1 | tee /tmp/apt_update.log; then
                echo "📦 正在安装 Docker 组件..."
                if DEBIAN_FRONTEND=noninteractive apt install -y -qq docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin >/dev/null 2>&1; then
                    echo "✅ 成功从源 $src 安装 Docker"
                    success=1
                    break
                else
                    echo "⚠️ 源 $src 安装失败，尝试下一个"
                fi
            else
                if grep -q "NO_PUBKEY" /tmp/apt_update.log; then
                    missing_key=$(grep -oP 'NO_PUBKEY\s+\K[0-9A-F]+' /tmp/apt_update.log | head -1)
                    echo "🔑 缺少公钥 $missing_key，尝试自动导入..."
                    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor > /etc/apt/keyrings/docker.gpg 2>/dev/null
                    if [ -s /etc/apt/keyrings/docker.gpg ]; then
                        echo "✅ 重新导入公钥成功"
                        if apt update && DEBIAN_FRONTEND=noninteractive apt install -y -qq docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin >/dev/null 2>&1; then
                            echo "✅ 成功从源 $src 安装 Docker"
                            success=1
                            break
                        else
                            echo "⚠️ 公钥修复后安装仍然失败"
                        fi
                    else
                        echo "⚠️ 公钥修复失败"
                    fi
                else
                    echo "⚠️ apt update 失败，错误非 NO_PUBKEY"
                fi
            fi
        done

        if [ $success -eq 0 ]; then
            echo "⚠️ 所有 Docker 源均不可用，请检查网络"
            return 1
        fi
        rm -f /tmp/apt_update.log
    fi

    # ---------- CentOS / Rocky / RHEL / Fedora ----------
    if [[ "$OS" =~ ^(centos|rocky|rhel|fedora)$ ]]; then
        echo "📦 正在升级系统软件包..."
        if command -v dnf >/dev/null 2>&1; then
            dnf upgrade -y || true
            dnf -y install dnf-plugins-core || true
        else
            yum update -y || true
            yum -y install yum-utils || true
        fi

        echo -e "\n🧹 自动清理不再需要的依赖包..."
        if command -v dnf >/dev/null 2>&1; then
            dnf autoremove -y || true
        else
            yum autoremove -y || true
        fi

        local success=0
        for src in "${SOURCES[@]}"; do
            echo "🔍 尝试使用源: $src"
            rm -f /etc/yum.repos.d/docker-ce.repo
            if curl -fsSL "$src/docker-ce.repo" -o /etc/yum.repos.d/docker-ce.repo 2>/dev/null; then
                if command -v dnf >/dev/null 2>&1; then
                    if dnf -y install docker-ce docker-ce-cli containerd.io docker-compose-plugin >/dev/null 2>&1; then
                        echo "✅ 成功从源 $src 安装 Docker"
                        success=1
                        break
                    else
                        echo "⚠️ 源 $src 安装失败，尝试下一个"
                    fi
                else
                    if yum -y install docker-ce docker-ce-cli containerd.io docker-compose-plugin >/dev/null 2>&1; then
                        echo "✅ 成功从源 $src 安装 Docker"
                        success=1
                        break
                    else
                        echo "⚠️ 源 $src 安装失败，尝试下一个"
                    fi
                fi
            else
                echo "⚠️ 源 $src repo 文件下载失败，尝试下一个"
            fi
        done

        if [ $success -eq 0 ]; then
            echo "⚠️ 所有 Docker 源均不可用，请检查网络"
            return 1
        fi
    fi

    systemctl enable --now docker >/dev/null 2>&1 || true

    REAL_USER=$(logname 2>/dev/null || echo "${SUDO_USER:-}")
    if [ -n "$REAL_USER" ] && [ "$REAL_USER" != "root" ]; then
        if id "$REAL_USER" &>/dev/null; then
            usermod -aG docker "$REAL_USER" || true
            echo "✅ 已将用户 $REAL_USER 加入 docker 组"
        else
            echo "⚠️ 用户 $REAL_USER 不存在，跳过添加 docker 组"
        fi
    fi

    echo "✅ 安装完成"
}

update_docker() {
    if ! command -v docker &>/dev/null; then
        echo "⚠️ Docker 未安装，请先安装。"
        return 1
    fi

    echo "🔄 更新 Docker & Compose..."

    get_docker_sources

    case "$OS" in
        arch)
            echo "📦 使用 pacman 更新系统及 Docker..."
            pacman -Syu --noconfirm
            systemctl restart docker 2>/dev/null || true
            echo "🧹 自动清理不再需要的依赖包..."
            pacman -Rns $(pacman -Qdtq 2>/dev/null) --noconfirm 2>/dev/null || true
            echo "✅ 系统及 Docker 更新完成"
            show_versions
            return 0
            ;;
        suse)
            echo "📦 使用 zypper 更新系统及 Docker..."
            zypper refresh
            zypper update -y
            systemctl restart docker 2>/dev/null || true
            echo "🧹 自动清理不再需要的依赖包..."
            zypper -n rm -u 2>/dev/null || true
            echo "✅ 系统及 Docker 更新完成"
            show_versions
            return 0
            ;;
        alpine)
            echo "📦 使用 apk 更新系统及 Docker..."
            apk update || true
            apk upgrade || true
            echo "🧹 自动清理不再需要的依赖包..."
            apk autoremove 2>/dev/null || true
            echo "✅ 系统及 Docker 更新完成"
            show_versions
            return 0
            ;;
    esac

    # ---------- Ubuntu/Debian/Armbian ----------
    if [[ "$OS" =~ ^(ubuntu|debian|armbian)$ ]]; then
        local success=0
        for src in "${SOURCES[@]}"; do
            echo "🔍 尝试使用源: $src"
            rm -f /etc/apt/sources.list.d/docker.list
            local codename
            codename=$(lsb_release -cs)

            local KEYRING
            if [[ "$src" == "https://download.docker.com/linux/ubuntu" ]] || [[ "$src" == "https://download.docker.com/linux/debian" ]]; then
                KEYRING="/etc/apt/keyrings/docker.asc"
                if [ ! -f "$KEYRING" ]; then
                    curl -fsSL "$src/gpg" -o "$KEYRING" 2>/dev/null || continue
                    chmod a+r "$KEYRING"
                fi
                echo "deb [arch=$(dpkg --print-architecture) signed-by=$KEYRING] $src $codename stable" > /etc/apt/sources.list.d/docker.list
            else
                KEYRING="/etc/apt/keyrings/docker.gpg"
                if [ ! -f "$KEYRING" ]; then
                    curl -fsSL "$src/gpg" -o /tmp/docker.gpg 2>/dev/null || continue
                    gpg --dearmor -o "$KEYRING" < /tmp/docker.gpg 2>/dev/null || true
                    rm -f /tmp/docker.gpg
                    chmod a+r "$KEYRING"
                fi
                echo "deb [arch=$(dpkg --print-architecture) signed-by=$KEYRING] $src $codename stable" > /etc/apt/sources.list.d/docker.list
            fi

            if apt update 2>&1 | tee /tmp/apt_update.log; then
                echo "📦 正在升级所有系统软件包（包括 Docker）..."
                if DEBIAN_FRONTEND=noninteractive apt upgrade -y -qq 2>/dev/null; then
                    echo -e "\n🧹 自动清理不再需要的依赖包..."
                    apt autoremove -y 2>/dev/null || true
                    echo -e "\n✅ 成功从源 $src 更新系统及 Docker"
                    success=1
                    break
                else
                    echo "⚠️ 源 $src 升级失败，尝试下一个"
                fi
            else
                if grep -q "NO_PUBKEY" /tmp/apt_update.log; then
                    missing_key=$(grep -oP 'NO_PUBKEY\s+\K[0-9A-F]+' /tmp/apt_update.log | head -1)
                    echo "🔑 缺少公钥 $missing_key，尝试自动导入..."
                    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor > /etc/apt/keyrings/docker.gpg 2>/dev/null
                    if [ -s /etc/apt/keyrings/docker.gpg ]; then
                        echo "✅ 公钥导入成功，重试更新..."
                        apt update && DEBIAN_FRONTEND=noninteractive apt upgrade -y -qq 2>/dev/null || true
                        if [ $? -eq 0 ]; then
                            echo -e "\n🧹 自动清理不再需要的依赖包..."
                            apt autoremove -y 2>/dev/null || true
                            echo -e "\n✅ 成功从源 $src 更新系统及 Docker"
                            success=1
                            break
                        fi
                    else
                        echo "⚠️ 公钥修复失败"
                    fi
                fi
            fi
        done
        rm -f /tmp/apt_update.log

        if [ $success -eq 0 ]; then
            echo "⚠️ 所有源均无法更新系统，请检查网络"
            return 1
        fi
    fi

    # ---------- CentOS/Rocky/RHEL/Fedora ----------
    if [[ "$OS" =~ ^(centos|rocky|rhel|fedora)$ ]]; then
        local success=0
        for src in "${SOURCES[@]}"; do
            echo "🔍 尝试使用源: $src"
            rm -f /etc/yum.repos.d/docker-ce.repo
            if curl -fsSL "$src/docker-ce.repo" -o /etc/yum.repos.d/docker-ce.repo 2>/dev/null; then
                echo "📦 正在升级所有系统软件包（包括 Docker）..."
                if command -v dnf >/dev/null 2>&1; then
                    if dnf upgrade -y; then
                        echo -e "\n🧹 自动清理不再需要的依赖包..."
                        dnf autoremove -y 2>/dev/null || true
                        echo -e "\n✅ 成功从源 $src 更新系统及 Docker"
                        success=1
                        break
                    else
                        echo "⚠️ 源 $src dnf 升级失败，尝试下一个"
                    fi
                else
                    if yum update -y; then
                        echo -e "\n🧹 自动清理不再需要的依赖包..."
                        yum autoremove -y 2>/dev/null || true
                        echo -e "\n✅ 成功从源 $src 更新系统及 Docker"
                        success=1
                        break
                    else
                        echo "⚠️ 源 $src yum 升级失败，尝试下一个"
                    fi
                fi
            else
                echo "⚠️ 源 $src repo 文件下载失败，尝试下一个"
            fi
        done

        if [ $success -eq 0 ]; then
            echo "⚠️ 所有源均无法更新系统，请检查网络"
            return 1
        fi
    fi

    systemctl restart docker 2>/dev/null || true
    echo "✅ 系统及 Docker 更新完成"
    show_versions
}

uninstall_docker() {
    echo "⚠️ 警告：卸载 Docker & Compose 将删除所有容器、镜像、数据卷及配置文件！此操作不可逆！"
    read -r -p "确认要卸载 Docker & Compose 吗？(Y/N): " confirm
    [[ ! "$confirm" =~ ^[Yy]$ ]] && echo "已取消" && return

    echo "⚠️ 卸载 Docker & Compose..."
    systemctl stop docker 2>/dev/null || true

    case "$OS" in
        ubuntu|debian|armbian)
            apt purge -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin || true
            rm -f /etc/apt/sources.list.d/docker.list
            rm -f /etc/apt/keyrings/docker.gpg
            rm -f /etc/apt/keyrings/docker.asc
            rm -rf /var/lib/docker /var/lib/containerd
            apt autoremove -y || true
            ;;
        centos|rocky|fedora|rhel)
            if command -v dnf >/dev/null 2>&1; then
                dnf remove -y docker-ce docker-ce-cli containerd.io docker-compose-plugin || true
            else
                yum remove -y docker-ce docker-ce-cli containerd.io docker-compose-plugin || true
            fi
            rm -f /etc/yum.repos.d/docker-ce.repo
            rm -f /etc/pki/rpm-gpg/RPM-GPG-KEY-docker-ce-*
            rm -rf /var/lib/docker /var/lib/containerd
            ;;
        arch)
            pacman -Rns --noconfirm docker docker-compose || true
            sed -i '/docker/d' /etc/pacman.conf 2>/dev/null || true
            rm -rf /var/lib/docker /var/lib/containerd
            ;;
        suse)
            zypper remove -y docker docker-compose || true
            zypper removerepo docker 2>/dev/null || true
            rm -f /etc/zypp/repos.d/docker-ce.repo
            rm -rf /var/lib/docker /var/lib/containerd
            ;;
        alpine)
            apk del docker docker-compose || true
            sed -i '/docker/d' /etc/apk/repositories 2>/dev/null || true
            rm -rf /var/lib/docker /var/lib/containerd
            ;;
        *)
            echo "⚠️ 不支持的系统，无法自动清理全部残留"
            return 1
            ;;
    esac

    echo "🗑️ Docker & Compose 已卸载"
}

show_versions() {
    if command -v docker >/dev/null 2>&1; then
        DOCKER_VER=$(docker --version | awk '{print $3}' | sed 's/,//')
        if docker compose version >/dev/null 2>&1; then
            COMPOSE_VER=$(docker compose version --short)
        elif command -v docker-compose >/dev/null 2>&1; then
            COMPOSE_VER=$(docker-compose version --short 2>/dev/null)
        else
            COMPOSE_VER="未安装"
        fi
        echo "🐳 Docker 版本: $DOCKER_VER"
        echo "🔧 Compose 版本: $COMPOSE_VER"
    else
        echo "⚠️ Docker 未安装"
    fi
}

# -------------------------
# 服务部署
# -------------------------
install_npm() {
    echo "📂 配置 Nginx Proxy Manager 数据目录"
    echo "提示：将创建两个子目录 data 和 letsencrypt 用于持久化数据"
    read -r -p "请输入宿主机数据目录（回车退出安装）: " npm_base
    [ -z "$npm_base" ] && echo "⚠️ 退出安装" && return

    local npm_data="${npm_base}/data"
    local npm_letsencrypt="${npm_base}/letsencrypt"
    mkdir -p "$npm_data" "$npm_letsencrypt" || true

    local image="chishin/nginx-proxy-manager-zh:release"
    local container_name="npm"
    
    if container_exists "$container_name"; then
        echo "⚠️ 检测到已存在容器: $container_name"
        read -r -p "是否删除旧容器并重新安装？(Y/N): " confirm
        [[ ! "$confirm" =~ ^[Yy]$ ]] && echo "已取消安装" && return
        docker stop "$container_name" >/dev/null 2>&1 || true
        docker rm "$container_name" >/dev/null 2>&1 || true
        echo "✅ 已删除旧容器"
    fi
    
    local run_cmd
    run_cmd=$(build_service_run_cmd "npm" "$image" "$container_name" "$npm_base")

    eval "$run_cmd" || echo "⚠️ NPM 启动失败，请检查端口或镜像"
    save_service_config "npm" "$image" "$npm_base" "-p 80:80 -p 81:81 -p 443:443 -v ${npm_base}/data:/data -v ${npm_base}/letsencrypt:/etc/letsencrypt" || true
    echo "✅ Nginx Proxy Manager 安装完成，访问 http://IP:81"
    echo "🔑 默认登录信息"
    echo "Email: admin@example.com"
    echo "Password: changeme"
    echo "⚠️ 首次登录后请立即修改账号密码！"
}

install_portainer() {
    echo "📂 配置 Portainer 数据目录"
    read -r -p "请输入宿主机数据目录（回车退出安装）: " portainer_dir
    [ -z "$portainer_dir" ] && echo "⚠️ 退出安装" && return
    mkdir -p "$portainer_dir" || true

    local image="6053537/portainer-ce:latest"
    local container_name="portainer"

    if container_exists "$container_name"; then
        echo "⚠️ 检测到已存在容器: $container_name"
        read -r -p "是否删除旧容器并重新安装？(Y/N): " confirm
        [[ ! "$confirm" =~ ^[Yy]$ ]] && echo "已取消安装" && return
        docker stop "$container_name" >/dev/null 2>&1 || true
        docker rm "$container_name" >/dev/null 2>&1 || true
        echo "✅ 已删除旧容器"
    fi
    
    local run_cmd
    run_cmd=$(build_service_run_cmd "portainer" "$image" "$container_name" "$portainer_dir")

    eval "$run_cmd" || echo "⚠️ Portainer 启动失败，请检查端口或镜像"
    save_service_config "portainer" "$image" "$portainer_dir" "-p 9000:9000 -v ${portainer_dir}:/data -v /var/run/docker.sock:/var/run/docker.sock" || true
    echo "✅ Portainer 安装完成，访问 http://IP:9000"
}

install_lucky() {
    echo "📂 配置 Lucky 数据目录"
    read -r -p "请输入宿主机数据目录（回车退出安装）: " lucky_dir
    [ -z "$lucky_dir" ] && echo "⚠️ 退出安装" && return
    mkdir -p "$lucky_dir" || true

    local image="gdy666/lucky:v3"
    local container_name="lucky"

    if container_exists "$container_name"; then
        echo "⚠️ 检测到已存在容器: $container_name"
        read -r -p "是否删除旧容器并重新安装？(Y/N): " confirm
        [[ ! "$confirm" =~ ^[Yy]$ ]] && echo "已取消安装" && return
        docker stop "$container_name" >/dev/null 2>&1 || true
        docker rm "$container_name" >/dev/null 2>&1 || true
        echo "✅ 已删除旧容器"
    fi

    local run_cmd
    run_cmd=$(build_service_run_cmd "lucky" "$image" "$container_name" "$lucky_dir")

    eval "$run_cmd" || echo "⚠️ Lucky 启动失败，请检查端口或镜像"
    save_service_config "lucky" "$image" "$lucky_dir" "--network host -v ${lucky_dir}:/app/conf -v /var/run/docker.sock:/var/run/docker.sock" || true
    echo "✅ Lucky 安装完成，访问 http://IP:16601"
    echo "🔑 默认登录信息"
    echo "默认账号：666"
    echo "默认密码：666"
    echo "⚠️ 首次登录后请立即修改账号密码！"
}

# -------------------------
# 1Panel 部署
# -------------------------
install_1panel() {
    echo "🚀 开始部署 1Panel..."
    echo "📌 将使用官方一键安装脚本"
    echo "⚠️ 请确保系统已联网，且未安装过 1Panel（如有数据请提前备份）"
    read -r -p "是否继续安装？(Y/N): " confirm
    [[ ! "$confirm" =~ ^[Yy]$ ]] && echo "已取消" && return
    curl -fsSL https://resource.fit2cloud.com/1panel/package/quick_start.sh -o /tmp/quick_start.sh
    bash /tmp/quick_start.sh
    if [ $? -eq 0 ]; then
        echo "✅ 1Panel 安装完成"
        touch "$CONF_DIR/1panel.installed"
    else
        echo "⚠️ 安装失败"
    fi
}

update_1panel() {
    if command -v 1panel &>/dev/null; then
        echo "🔄 更新 1Panel ..."
        1panel update
        echo "✅ 1Panel 更新完成"
    else
        echo "⚠️ 1Panel 未安装，请先安装"
    fi
}

uninstall_1panel() {
    if ! command -v 1panel &>/dev/null && ! [ -f "$CONF_DIR/1panel.installed" ]; then
        echo "⚠️ 1Panel 未安装，请先安装"
        return
    fi

    echo "⚠️ 卸载 1Panel 将删除所有数据！"
    read -r -p "确认卸载？(Y/N): " confirm
    [[ ! "$confirm" =~ ^[Yy]$ ]] && echo "已取消" && return

    if [ -f "/usr/local/bin/1panel-uninstall" ]; then
        /usr/local/bin/1panel-uninstall
    elif command -v 1panel &>/dev/null; then
        echo "尝试使用内置卸载命令..."
        1panel uninstall || true
    else
        echo "⚠️ 未找到 1Panel 卸载程序，请手动删除"
        return
    fi
    rm -f "$CONF_DIR/1panel.installed"
    echo "✅ 1Panel 已卸载"
}

# -------------------------
# 依赖自动安装
# -------------------------
check_backup_deps() {
    local missing=()
    command -v jq >/dev/null 2>&1 || missing+=("jq")
    command -v tar >/dev/null 2>&1 || missing+=("tar")
    command -v gzip >/dev/null 2>&1 || missing+=("gzip")
    command -v docker >/dev/null 2>&1 || missing+=("docker")
    command -v unzip >/dev/null 2>&1 || missing+=("unzip")
    command -v zip >/dev/null 2>&1 || missing+=("zip")

    if [ ${#missing[@]} -eq 0 ]; then
        return 0
    fi

    echo "📦 检测到缺少依赖工具: ${missing[*]}，正在自动安装..."
    case "$OS" in
        ubuntu|debian|armbian)
            apt update || true
            apt install -y "${missing[@]}" || true
            ;;
        centos|rocky|fedora|rhel)
            if command -v dnf >/dev/null 2>&1; then
                dnf install -y epel-release 2>/dev/null || true
                dnf install -y "${missing[@]}" || true
            else
                yum install -y epel-release 2>/dev/null || true
                yum install -y "${missing[@]}" || true
            fi
            ;;
        arch)
            pacman -Sy --noconfirm "${missing[@]}" || true
            ;;
        suse)
            zypper refresh || true
            zypper install -y "${missing[@]}" || true
            ;;
        alpine)
            apk add --no-cache "${missing[@]}" || true
            ;;
        *)
            echo "⚠️ 无法自动安装依赖，请手动安装: ${missing[*]}"
            return 1
            ;;
    esac
    echo "✅ 依赖安装完成"
}

check_runlike() {
    if ! docker image inspect wuyangdaily/runlike:latest &>/dev/null; then
        echo "📥 正在拉取 runlike 镜像（用于生成容器启动命令）..."
        docker pull wuyangdaily/runlike:latest || { echo "⚠️ 拉取 runlike 镜像失败"; return 1; }
    fi
    return 0
}

# -------------------------
# 容器选择（单选 / 多选）
# -------------------------
select_containers_for_backup() {
    local mode="${1:-single}"
    local prompt="${2:-📦 请选择要备份的容器：}"
    local containers
    containers=$(docker ps -a --format "{{.Names}}\t{{.Status}}\t{{.Image}}" | sort)

    if [ -z "$containers" ]; then
        echo "⚠️ 没有找到任何容器" >&2
        return 1
    fi

    local names=()
    local i=1

    echo "$prompt" >&2
    echo "--------------------------------------------------------------------------------------------" >&2
    printf "%-4s %-25s %-20s %s\n" "序号" "容器名" "状态" "镜像" >&2
    echo "--------------------------------------------------------------------------------------------" >&2

    while IFS=$'\t' read -r name status image; do
        [ -z "$name" ] && continue
        status=$(format_container_status "$status")
        names+=("$name")
        printf "%-4s %-25s %-20s %s\n" "$i" "$name" "$status" "$image" >&2
        ((i++))
    done <<< "$containers"

    echo "--------------------------------------------------------------------------------------------" >&2

    if [ "$mode" = "multi" ]; then
        echo "📦 支持单选或多选（用空格分隔，如: 1 或 1 3 5）" >&2
    fi
    echo "0) 取消" >&2

    read -r -p "请输入序号: " sel

    if [ "$mode" = "multi" ]; then
        if [[ "$sel" == "0" ]]; then
            echo "已取消" >&2
            return 1
        fi

        if [[ -z "$sel" ]] || ! [[ "$sel" =~ ^[0-9\ ]+$ ]]; then
            echo "⚠️ 无效选择" >&2
            return 1
        fi

        local selected=()
        local n
        for n in $sel; do
            if [[ "$n" =~ ^[0-9]+$ ]] && [ "$n" -ge 1 ] && [ "$n" -le ${#names[@]} ]; then
                selected+=("${names[$((n-1))]}")
            fi
        done

        if [ ${#selected[@]} -eq 0 ]; then
            echo "⚠️ 无效选择" >&2
            return 1
        fi

        echo "${selected[@]}"
        return 0
    fi

    if [[ -z "$sel" ]]; then
        echo "⚠️ 无效选择" >&2
        return 1
    fi
    if [[ ! "$sel" =~ ^[0-9]+$ ]] || [ "$sel" -eq 0 ] || [ "$sel" -gt ${#names[@]} ]; then
        echo "已取消" >&2
        return 1
    fi

    echo "${names[$((sel-1))]}"
    return 0
}

# -------------------------
# 备份核心函数：打包数据卷 + 生成启动脚本
# 参数：容器名称数组，输出zip文件名（不含路径），返回zip文件完整路径
# -------------------------
backup_containers_core() {
    local -n containers_ref=$1
    local zip_filename="$2"
    local temp_dir
    temp_dir=$(mktemp -d)
    trap 'rm -rf "$temp_dir"' EXIT
    local success=0

    check_runlike || return 1

    local data_tar="docker_data.tar.gz"
    local start_script="docker_run.sh"

    local volume_paths_file="${temp_dir}/volume_paths.txt"
    > "$volume_paths_file"

    cat > "${temp_dir}/${start_script}" << 'EOF'
#!/bin/bash
set -e
# Auto-generated by Docker Toolkit Backup

EOF

    for container in "${containers_ref[@]}"; do
        if ! docker ps -a --format "{{.Names}}" | grep -qx "$container"; then
            echo "⚠️ 容器 $container 不存在，跳过" >&2
            continue
        fi

        echo "📦 处理容器: $container"

        docker inspect "$container" --format '{{range .Mounts}}{{.Source}}{{"\n"}}{{end}}' >> "$volume_paths_file"

        local run_cmd
        run_cmd=$(docker run --rm -v /var/run/docker.sock:/var/run/docker.sock wuyangdaily/runlike "$container" 2>/dev/null || true)
        if [ -z "$run_cmd" ]; then
            echo "⚠️ 无法为容器 $container 生成启动命令，跳过" >&2
            continue
        fi
        local clean_cmd
        clean_cmd=$(echo "$run_cmd" | sed -E 's/--hostname=[^ ]+ //g; s/--mac-address=[^ ]+ //g')

        echo "" >> "${temp_dir}/${start_script}"
        echo "echo \"🚀 正在启动容器: $container\"" >> "${temp_dir}/${start_script}"
        echo "$clean_cmd" >> "${temp_dir}/${start_script}"
    done

    sort -u "$volume_paths_file" -o "$volume_paths_file"

    if [ -s "$volume_paths_file" ]; then
        echo "📦 打包数据卷（绝对路径）..."
        if ! tar -czpf "${temp_dir}/${data_tar}" -P -C / -T "$volume_paths_file" 2>/dev/null; then
            echo "⚠️ 打包数据卷失败" >&2
            success=1
        fi
    else
        echo "⚠️ 没有发现任何数据卷，将创建空数据包" >&2
        touch "${temp_dir}/${data_tar}"
    fi

    if [ $success -eq 0 ]; then
        cd "$temp_dir" || { success=1; cd - >/dev/null || true; }
        if [ $success -eq 0 ]; then
            if ! zip -r -9 "/root/${zip_filename}" . >/dev/null; then
                echo "⚠️ 创建 zip 文件失败" >&2
                success=1
            fi
            if [ $? -eq 0 ]; then
                echo "✅ 备份文件已创建: /root/${zip_filename}"
            else
                echo "⚠️ 创建 zip 文件失败" >&2
                success=1
            fi
        fi
        cd - >/dev/null || true
    fi

    rm -rf "$temp_dir"
    return $success
}

# -------------------------
# 备份所有容器
# -------------------------
backup_all_containers() {
    ensure_root_dir
    check_backup_deps || return 1

    local all_containers=()
    while IFS= read -r name; do
        all_containers+=("$name")
    done < <(docker ps -a --format "{{.Names}}" | sort)

    if [ ${#all_containers[@]} -eq 0 ]; then
        echo "⚠️ 没有找到任何容器"
        return
    fi

echo "📦 即将备份以下所有容器："
echo "--------------------------------------------------------------------------------------------"
printf "%-4s %-25s %-20s %s\n" "序号" "容器名" "状态" "镜像"
echo "--------------------------------------------------------------------------------------------"

containers=$(docker ps -a --format "{{.Names}}\t{{.Status}}\t{{.Image}}")

i=1
while IFS=$'\t' read -r name status image; do
    [ -z "$name" ] && continue

    status=$(format_container_status "$status")

    printf "%-4s %-25s %-20s %s\n" "$i" "$name" "$status" "$image"
    ((i++))
done <<< "$containers"

echo "--------------------------------------------------------------------------------------------"
read -r -p "确认备份全部容器？(Y/N): " confirm
if [[ -z "$confirm" ]]; then
    echo "⚠️ 无效选择"
    return
fi
[[ ! "$confirm" =~ ^[Yy]$ ]] && echo "已取消" && return

    local time_str
    time_str=$(get_beijing_time)
    local zip_name="Docker-${time_str}.zip"

    echo "📦 开始备份所有容器..."
    if backup_containers_core all_containers "$zip_name"; then
        echo "💡 恢复方法：将文件传输到目标服务器，在本工具中选择「恢复 Docker 容器」即可"
    else
        echo "⚠️ 备份过程中出现错误"
    fi
}

# -------------------------
# 备份选中的容器（支持单选/多选）
# -------------------------
backup_selected_containers() {
    ensure_root_dir
    check_backup_deps || return 1

    local selected
    selected=$(select_containers_for_backup multi) || return 0

    local selected_array=($selected)
    if [ ${#selected_array[@]} -eq 0 ]; then
        return 0
    fi

    local time_str
    time_str=$(get_beijing_time)
    local zip_name
    if [ ${#selected_array[@]} -eq 1 ]; then
        zip_name="${selected_array[0]}-${time_str}.zip"
    else
        local names_joined
        names_joined=$(printf "%s_" "${selected_array[@]}")
        names_joined=${names_joined%_}
        zip_name="${names_joined}-${time_str}.zip"
    fi

    echo "📦 开始备份选中的容器: ${selected_array[*]}"
    if backup_containers_core selected_array "$zip_name"; then
        echo "💡 恢复方法：将文件传输到目标服务器，在本工具中选择「恢复 Docker 容器」即可"
    else
        echo "⚠️ 备份过程中出现错误"
    fi
}

# -------------------------
# 恢复备份
# -------------------------
restore_backup() {
    ensure_root_dir
    check_backup_deps || return 1

    shopt -s nullglob
    local backups=(/root/*.zip)
    shopt -u nullglob

    if [ ${#backups[@]} -eq 0 ]; then
        echo "⚠️ 没有找到任何备份文件，请先备份。"
        pause_return
        return
    fi

    echo "请选择要恢复的备份文件："
    local i=1
    local f
    for f in "${backups[@]}"; do
        echo "$i) $(basename "$f") ($(du -h "$f" | cut -f1))"
        ((i++))
    done
    echo "0) 取消"

    read -r -p "请输入序号: " sel
    if [[ -z "$sel" ]]; then
        echo "⚠️ 无效选择"
        pause_return
        return
    fi
    if [[ ! "$sel" =~ ^[0-9]+$ ]] || [ "$sel" -eq 0 ] || [ "$sel" -gt ${#backups[@]} ]; then
        echo "已取消"
        pause_return
        return
    fi

    local backup_path="${backups[$((sel-1))]}"
    echo "已选择: $(basename "$backup_path")"

    local restore_root="/root/restore_temp_$(date +%s)"
    mkdir -p "$restore_root"
    trap 'cd / >/dev/null; rm -rf "$restore_root" 2>/dev/null' EXIT
    cd "$restore_root" || return

    echo "📂 解压备份文件..."
    unzip -q "$backup_path" || { echo "⚠️ 解压失败"; cd - >/dev/null; rm -rf "$restore_root"; return 1; }

    local data_tar="docker_data.tar.gz"
    local start_script="docker_run.sh"

    if [ ! -f "$data_tar" ] || [ ! -f "$start_script" ]; then
        echo "⚠️ 备份文件缺少必要组件 (data.tar.gz 或 run.sh)"
        cd - >/dev/null
        rm -rf "$restore_root"
        return 1
    fi

    local all_containers=()
    while IFS= read -r line; do
        if [[ "$line" =~ ^echo\ \"?🚀\ 正在启动容器:\ ([^\"]+)\"?$ ]]; then
            all_containers+=("${BASH_REMATCH[1]}")
        fi
    done < "$start_script"

    if [ ${#all_containers[@]} -eq 0 ]; then
        echo "⚠️ 备份脚本中未找到任何容器定义"
        cd - >/dev/null
        rm -rf "$restore_root"
        return 1
    fi

    local existing_containers=()
    local non_existing_containers=()
    for cn in "${all_containers[@]}"; do
        if docker ps -a --format "{{.Names}}" | grep -qx "$cn"; then
            existing_containers+=("$cn")
        else
            non_existing_containers+=("$cn")
        fi
    done

    local delete_existing=false
    local containers_to_restore=()
    if [ ${#existing_containers[@]} -gt 0 ]; then
        echo "⚠️ 备份中包含以下容器已存在于当前系统中："
        for cn in "${existing_containers[@]}"; do
            echo "   - $cn"
        done
        echo ""
        echo "请选择操作："
        echo "  Y) 删除这些容器，完整恢复所有容器"
        echo "  N) 保留这些容器，仅恢复不存在容器"
        echo "回车) 取消恢复"
        read -r -p "请选择 [Y/N] :" confirm
        if [[ -z "$confirm" ]]; then
            echo "已取消恢复"
            cd - >/dev/null
            rm -rf "$restore_root"
            pause_return
            return
        fi
        case "$confirm" in
            [Yy])
                delete_existing=true
                for cn in "${existing_containers[@]}"; do
                    docker rm -f "$cn" >/dev/null 2>&1 && echo "✅ 已删除容器 $cn"
                done
                containers_to_restore=("${all_containers[@]}")
                ;;
            [Nn])
                delete_existing=false
                if [ ${#non_existing_containers[@]} -eq 0 ]; then
                    echo "⚠️ 没有需要恢复的新容器，操作结束。"
                    cd - >/dev/null
                    rm -rf "$restore_root"
                    pause_return
                    return
                fi
                containers_to_restore=("${non_existing_containers[@]}")
                echo "ℹ️ 将恢复以下容器：${containers_to_restore[*]}"
                echo "⚠️ 警告：数据卷恢复会覆盖所有备份中的目录（包括可能被保留容器使用的目录），请确认数据无冲突或已提前备份。"
                read -r -p "是否继续恢复数据卷和新增容器？(Y/N):" continue_restore
                if [[ -z "$continue_restore" ]] || [[ ! "$continue_restore" =~ ^[Yy]$ ]]; then
                    echo "已取消"
                    cd - >/dev/null
                    rm -rf "$restore_root"
                    pause_return
                    return
                fi
                ;;
            *)
                echo "⚠️ 无效选择"
                cd - >/dev/null
                rm -rf "$restore_root"
                pause_return
                return
                ;;
        esac
    else
        containers_to_restore=("${all_containers[@]}")
    fi

    echo "📦 恢复数据卷（解压到原始目录）..."
    if ! tar -xzpf "$data_tar" -P -C /; then
        echo "⚠️ 恢复数据卷失败"
        cd - >/dev/null
        rm -rf "$restore_root"
        return 1
    fi

    local final_script="docker_run_filtered.sh"
    if [ "$delete_existing" = true ] || [ ${#existing_containers[@]} -eq 0 ]; then
        cp "$start_script" "$final_script"
    else
        cp "$start_script" "$final_script"
        local temp_script="${final_script}.tmp"
        > "$temp_script"
        local in_block=false
        local current_container=""
        local should_keep=false
        while IFS= read -r line; do
            if [[ "$line" =~ ^echo\ \"?🚀\ 正在启动容器:\ ([^\"]+)\"?$ ]]; then
                current_container="${BASH_REMATCH[1]}"
                if printf '%s\n' "${containers_to_restore[@]}" | grep -qx "$current_container"; then
                    should_keep=true
                    in_block=true
                    echo "$line" >> "$temp_script"
                else
                    should_keep=false
                    in_block=false
                fi
            elif [ "$in_block" = true ] && [ "$should_keep" = true ]; then
                echo "$line" >> "$temp_script"
            fi
        done < "$start_script"
        mv "$temp_script" "$final_script"
    fi

    if grep -q '^set -e' "$final_script"; then
        sed -i 's/^set -e/#set -e/g' "$final_script"
    fi

    chmod +x "$final_script"

    if [ ! -s "$final_script" ]; then
        echo "⚠️ 生成的启动脚本为空，没有容器需要启动？"
        cd - >/dev/null
        rm -rf "$restore_root"
        pause_return
        return
    fi

    echo "🚀 执行启动脚本..."
    bash "$final_script" || echo "⚠️ 部分容器启动失败，请手动检查"

    cd - >/dev/null
    rm -rf "$restore_root"
    echo "✅ 恢复操作完成"
    pause_return
}

# -------------------------
# 列出备份文件并允许删除
# -------------------------
list_backups() {
    ensure_root_dir
    echo "📁 位于 /root 目录下的备份文件："
    shopt -s nullglob
    local backups=(/root/*.zip)
    shopt -u nullglob

    if [ ${#backups[@]} -eq 0 ]; then
        echo "没有找到任何备份文件"
        pause_return
        return
    fi

    local i=1
    local f
    for f in "${backups[@]}"; do
        echo "$i) $(basename "$f") ($(du -h "$f" | cut -f1))"
        ((i++))
    done
    echo "0) 取消"

    read -r -p "请选择要删除的备份文件序号: " sel

    if [[ "$sel" == "0" ]]; then
        echo "已取消"
    elif [[ "$sel" =~ ^[0-9]+$ ]] && [ "$sel" -gt 0 ] && [ "$sel" -le ${#backups[@]} ]; then
        local to_delete="${backups[$((sel-1))]}"
        read -r -p "确认删除 $(basename "$to_delete") ？(Y/N): " confirm
        if [[ "$confirm" =~ ^[Yy]$ ]]; then
            rm -f "$to_delete"
            echo "✅ 已删除"
        else
            echo "已取消"
        fi
    else
        echo "⚠️ 无效选择"
    fi
    pause_return
}

generate_compose() {
    local container="$1"
    local out="$2"

    docker inspect "$container" | jq '
.[0] |
{
  version: "3",
  services: {
    (.Name|ltrimstr("/")): {
      image: .Config.Image,
      container_name: (.Name|ltrimstr("/")),
      restart: .HostConfig.RestartPolicy.Name,
      environment: .Config.Env,
      working_dir: .Config.WorkingDir,
      user: .Config.User,
      labels: .Config.Labels,
      ports: (
        .HostConfig.PortBindings // {} |
        to_entries |
        map("\(.value[0].HostPort):\(.key|split("/")[0])")
      ),
      volumes: (
        .Mounts |
        map("\(.Source):\(.Destination)")
      )
    }
  }
}
' > "$out"
}

new_compose() {
    local compose_cmd
    compose_cmd=$(get_compose_cmd) || { echo "⚠️ 未找到 docker compose / docker-compose"; return; }

    echo "请输入 Compose 项目路径，将在此目录下创建 docker-compose.yml 文件"
    read -r -p "项目路径: " project_dir
    if [ -z "$project_dir" ]; then
        echo "⚠️ 未输入路径"
        return
    fi

    local dir_created_by_us=false
    if [ ! -d "$project_dir" ]; then
        mkdir -p "$project_dir" || { echo "⚠️ 无法创建路径 $project_dir"; return; }
        dir_created_by_us=true
        echo "📁 已创建目录: $project_dir"
    else
        echo "📁 使用已有目录: $project_dir"
    fi

    cd "$project_dir" || return

    local compose_file="$project_dir/docker-compose.yml"

    echo "📝 正在编辑配置文件: $compose_file"
    ensure_nano_installed || return

    nano "$compose_file" || true

    if [ ! -f "$compose_file" ] || [ ! -s "$compose_file" ]; then
        echo "⚠️ 配置文件不存在或为空，未保存有效内容"
        if [ "$dir_created_by_us" = true ]; then
            cd / >/dev/null
            rm -rf "$project_dir"
            echo "🗑 已删除新建的目录: $project_dir"
        else
            echo "ℹ️ 目录 '$project_dir' 已保留（未创建有效 compose 文件）"
        fi
        return
    fi

    echo "🔍 正在验证配置文件语法..."
    if ! $compose_cmd -f "$compose_file" config >/dev/null 2>&1; then
        echo "⚠️ 配置文件语法错误："
        $compose_cmd -f "$compose_file" config 2>&1 | head -10
        echo "💡 请修正上述错误后重新运行本选项"
        return
    fi

    echo "🚀 正在启动 Compose 服务..."
    if $compose_cmd -f "$compose_file" up -d --remove-orphans; then
        echo "✅ Compose 服务已启动"
    else
        echo "⚠️ 启动 Compose 服务失败，请检查配置文件语法"
    fi
}

update_compose_all() {
    local compose_cmd
    compose_cmd=$(get_compose_cmd) || { echo "⚠️ 未找到 docker compose / docker-compose"; pause_return; return; }

    local files=()
    local dirs=()
    while IFS= read -r file; do
        if [[ "$file" != *"/root/restore_temp"* ]] && [[ "$file" != *"/root/backup_temp"* ]] && [[ "$file" != *"/root/backup_temp_all"* ]] && [[ "$file" != *"/root/backup_temp_multi"* ]]; then
            files+=("$file")
            dirs+=("$(dirname "$file")")
        fi
    done < <(find /root -type f \( -name "docker-compose.yml" -o -name "docker-compose.yaml" \) 2>/dev/null | sort)

    if [ ${#files[@]} -eq 0 ]; then
        echo "⚠️ 未在 /root 下找到任何 docker-compose 文件"
        pause_return
        return
    fi

    echo "📦 找到以下 Compose 项目："
    echo "------------------------------------------------"
    local i=1
    for d in "${dirs[@]}"; do
        printf "%-4s %s\n" "$i" "$d"
        ((i++))
    done
    echo "------------------------------------------------"
    echo "📦 支持单选或多选（用空格分隔，如: 1 或 1 3 5）"
    echo "0) 取消"
    read -r -p "请输入序号: " sel

    if [ -z "$sel" ]; then
        echo "⚠️ 无效选择"
        pause_return
        return
    fi
    if [[ "$sel" == "0" ]]; then
        echo "已取消"
        pause_return
        return
    fi

    local selected_indices=()
    local n
    for n in $sel; do
        if [[ "$n" =~ ^[0-9]+$ ]] && [ "$n" -ge 1 ] && [ "$n" -le ${#files[@]} ]; then
            selected_indices+=("$n")
        fi
    done
    if [ ${#selected_indices[@]} -eq 0 ]; then
        if echo "$sel" | grep -qw '0'; then
            echo "已取消"
        else
            echo "⚠️ 无效选择"
        fi
        pause_return
        return
    fi

    echo "准备更新以下项目:"
    for idx in "${selected_indices[@]}"; do
        echo "  - ${dirs[$((idx-1))]}"
    done
    read -r -p "确认继续？(Y/N): " confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        echo "已取消"
        pause_return
        return
    fi

    local original_dir
    original_dir=$(pwd)
    for idx in "${selected_indices[@]}"; do
        local file="${files[$((idx-1))]}"
        local dir="${dirs[$((idx-1))]}"
        echo "🔄 正在更新: $dir"
        cd "$dir" || { echo "⚠️ 无法进入目录 $dir，跳过"; continue; }
        $compose_cmd -f "$file" pull || { echo "⚠️ 拉取镜像失败: $dir"; cd "$original_dir"; continue; }
        $compose_cmd -f "$file" up -d || { echo "⚠️ 启动服务失败: $dir"; cd "$original_dir"; continue; }
        echo "✅ 已更新: $dir"
        cd "$original_dir"
    done
    echo "✅ 选中的 Compose 项目更新完成"
    pause_return
}

uninstall_compose_all() {
    local compose_cmd
    compose_cmd=$(get_compose_cmd) || { echo "⚠️ 未找到 docker compose / docker-compose"; pause_return; return; }
    require_cmds jq || { echo "⚠️ jq 未安装，无法解析资源列表，请先安装 jq"; pause_return; return; }

    local files=()
    local dirs=()
    while IFS= read -r file; do
        if [[ "$file" != *"/root/restore_temp"* ]] && [[ "$file" != *"/root/backup_temp"* ]] && [[ "$file" != *"/root/backup_temp_all"* ]] && [[ "$file" != *"/root/backup_temp_multi"* ]]; then
            files+=("$file")
            dirs+=("$(dirname "$file")")
        fi
    done < <(find /root -type f \( -name "docker-compose.yml" -o -name "docker-compose.yaml" \) 2>/dev/null | sort)

    if [ ${#files[@]} -eq 0 ]; then
        echo "⚠️ 未在 /root 下找到任何 docker-compose 文件"
        pause_return
        return
    fi

    echo "📦 找到以下 Compose 项目："
    echo "------------------------------------------------"
    local i=1
    for d in "${dirs[@]}"; do
        printf "%-4s %s\n" "$i" "$d"
        ((i++))
    done
    echo "------------------------------------------------"
    echo "📦 支持单选或多选（用空格分隔，如: 1 或 1 3 5）"
    echo "0) 取消"
    read -r -p "请输入序号: " sel

    if [ -z "$sel" ]; then
        echo "⚠️ 无效选择"
        pause_return
        return
    fi
    if [[ "$sel" == "0" ]]; then
        echo "已取消"
        pause_return
        return
    fi

    local selected_indices=()
    local n
    for n in $sel; do
        if [[ "$n" =~ ^[0-9]+$ ]] && [ "$n" -ge 1 ] && [ "$n" -le ${#files[@]} ]; then
            selected_indices+=("$n")
        fi
    done
    if [ ${#selected_indices[@]} -eq 0 ]; then
        if echo "$sel" | grep -qw '0'; then
            echo "已取消"
        else
            echo "⚠️ 无效选择"
        fi
        pause_return
        return
    fi

    echo "准备卸载以下 Compose 项目:"
    for idx in "${selected_indices[@]}"; do
        echo "  - ${dirs[$((idx-1))]}"
    done
    read -r -p "⚠️ 确认彻底卸载（容器/网络/镜像/卷/目录）？(Y/N): " confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        echo "已取消"
        pause_return
        return
    fi

    local original_dir
    original_dir=$(pwd)
    for idx in "${selected_indices[@]}"; do
        local file="${files[$((idx-1))]}"
        local dir="${dirs[$((idx-1))]}"
        echo "🗑 正在卸载: $dir"
        cd "$dir" || { echo "⚠️ 无法进入目录 $dir，跳过"; continue; }

        local containers=() networks=() volumes=() images=()
        local compose_json
        if compose_json=$($compose_cmd -f "$file" config --format json 2>/dev/null); then
            mapfile -t containers < <(echo "$compose_json" | jq -r '.services | keys[]' | sort -u)
            mapfile -t networks < <(echo "$compose_json" | jq -r '.networks // {} | keys[]' | sort -u)
            mapfile -t volumes < <(echo "$compose_json" | jq -r '.volumes // {} | keys[]' | sort -u)
            mapfile -t images < <(echo "$compose_json" | jq -r '.services[]?.image // empty' | sort -u)
        else
            echo "⚠️ 无法解析 compose 配置，将继续执行 down -v"
        fi

        if [ ${#containers[@]} -gt 0 ]; then
            echo "📦 将删除以下容器:"
            for c in "${containers[@]}"; do
                echo "    - $c"
            done
        fi
        if [ ${#networks[@]} -gt 0 ]; then
            echo "🌐 将删除以下网络:"
            for n in "${networks[@]}"; do
                echo "    - $n"
            done
        fi
        if [ ${#volumes[@]} -gt 0 ]; then
            echo "💾 将删除以下卷:"
            for v in "${volumes[@]}"; do
                echo "    - $v"
            done
        fi
        if [ ${#images[@]} -gt 0 ]; then
            echo "🐳 将删除以下镜像:"
            for img in "${images[@]}"; do
                echo "    - $img"
            done
        fi
        echo ""

        $compose_cmd -f "$file" down -v --remove-orphans >/dev/null 2>&1
        if [ $? -ne 0 ]; then
            $compose_cmd -f "$file" down >/dev/null 2>&1
        fi

        if [ ${#images[@]} -gt 0 ]; then
            for img in "${images[@]}"; do
                docker rmi "$img" &>/dev/null || true
            done
        fi

        rm -f "$file"
        echo "✅ 已删除 docker-compose.yml"
        cd "$original_dir"
        rm -rf "$dir"
        echo "✅ 已删除目录 $dir"
    done
    echo "✅ 选中的 Compose 项目已完全卸载"
    pause_return
}

manage_compose() {
    while true; do
        clear
        echo "===== Docker Compose 服务管理 ====="
        echo "1) 创建 Docker Compose"
        echo "2) 备份 Docker 容器"
        echo "3) 恢复 Docker 容器"
        echo "4) 查看 Docker 备份"
        echo "5) 停止 Docker 容器"
        echo "6) 重启 Docker 容器"
        echo "7) 更新 Compose 服务"
        echo "8) 卸载 Compose 服务"
        echo "0) 返回主菜单"
        read -r -p "请选择: " opt

        case $opt in
            1)
                ensure_nano_installed || { pause_return; continue; }
                new_compose || true
                pause_return
                ;;
            2)
                echo "备份 Docker 容器"
                echo "1) 备份所有容器（运行中/已停止）"
                echo "2) 选择容器备份（支持单选/多选）"
                read -r -p "请选择: " sub

                if [ "$sub" = "1" ]; then
                    backup_all_containers || true
                    pause_return
                elif [ "$sub" = "2" ]; then
                    backup_selected_containers || true
                    pause_return
                else
                    echo "⚠️ 无效选择"
                    pause_return
                fi
                ;;
            3)
                restore_backup || true
                ;;
            4)
                list_backups || true
                ;;
            5)
                selected=$(select_containers_for_backup multi "📦 请选择要停止的容器：") || { pause_return; continue; }
                for container in $selected; do
                    echo -n "停止容器 $container ... "
                    if docker stop "$container" >/dev/null 2>&1; then
                        echo "✅ 成功"
                    else
                        echo "⚠️ 失败"
                    fi
                done
                pause_return
                ;;
            6)
                selected=$(select_containers_for_backup multi "📦 请选择要重启的容器：") || { pause_return; continue; }
                for container in $selected; do
                    echo -n "重启容器 $container ... "
                    if docker restart "$container" >/dev/null 2>&1; then
                        echo "✅ 成功"
                    else
                        echo "⚠️ 失败"
                    fi
                done
                pause_return
                ;;
            7)
                update_compose_all || true
                ;;
            8)
                uninstall_compose_all || true
                ;;
            0)
                break
                ;;
            *)
                echo "⚠️ 无效选择"
                pause_return
                ;;
        esac
    done
}

# -------------------------
# 容器操作函数
# -------------------------
restart_all_containers() {
    if ! command -v docker &>/dev/null; then
        echo "⚠️ Docker 未安装，请先安装。"
        pause_return
        return
    fi

    echo "⚠️ 即将重启所有容器（包括已停止的容器）"
    read -r -p "确认继续？(Y/N): " confirm
    [[ ! "$confirm" =~ ^[Yy]$ ]] && echo "已取消" && pause_return && return

    local containers
    containers=$(docker ps -aq)
    if [ -z "$containers" ]; then
        echo "⚠️ 没有找到任何容器"
    else
        for container_id in $containers; do
            local container_name=$(docker inspect --format '{{.Name}}' "$container_id" 2>/dev/null | sed 's/^\///' || true)
            if docker restart "$container_id" >/dev/null 2>&1; then
                echo "✅ 容器 $container_name 已重启"
            elif docker start "$container_id" >/dev/null 2>&1; then
                echo "✅ 容器 $container_name 已启动"
            else
                echo "⚠️ 容器 $container_name 操作失败"
            fi
        done
        echo "✅ 所有容器操作完成"
    fi
    pause_return
}

stop_all_containers() {
    if ! command -v docker &>/dev/null; then
        echo "⚠️ Docker 未安装，请先安装。"
        pause_return
        return
    fi

    echo "⚠️ 即将停止所有正在运行的容器"
    read -r -p "确认继续？(Y/N): " confirm
    [[ ! "$confirm" =~ ^[Yy]$ ]] && echo "已取消" && pause_return && return

    local containers
    containers=$(docker ps --format "{{.Names}}")
    if [ -n "$containers" ]; then
        for container_name in $containers; do
            if docker stop "$container_name" >/dev/null 2>&1; then
                echo "✅ 容器 $container_name 已停止"
            else
                echo "⚠️ 容器 $container_name 停止失败"
            fi
        done
        echo "✅ 所有容器已停止"
    else
        echo "⚠️ 没有正在运行的容器"
    fi
    pause_return
}

cleanup_system() {
    if ! command -v docker &>/dev/null; then
        echo "⚠️ Docker 未安装，请先安装。"
        pause_return
        return
    fi

    echo "⚠️ 即将清理所有未使用的 Docker 资源（镜像、容器、网络、缓存）"
    read -r -p "确认继续？(Y/N): " confirm
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        docker system prune -af || true
        echo "✅ 清理完成"
    else
        echo "已取消"
    fi
    pause_return
}

fix_network() {
    if ! command -v docker &>/dev/null; then
        echo "⚠️ Docker 未安装，请先安装。"
        pause_return
        return
    fi

    echo "🔧 即将修复 Docker 网络，包括："
    echo "   • 重启 Docker 服务"
    echo "   • 清理未使用的网络"
    echo "   • 重置防火墙规则"
    echo "   • 重启运行中的容器"
    read -r -p "确认继续？(Y/N): " confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        echo "已取消"
        pause_return
        return
    fi

    echo "→ 重启 Docker 服务..."
    systemctl restart docker || true
    sleep 2

    if ! ip link show docker0 &>/dev/null; then
        echo "→ docker0 网桥缺失，尝试重新创建..."
        docker network prune -f || true
        systemctl restart docker || true
    fi

    echo "→ 清理未使用的 Docker 网络..."
    docker network prune -f || true

    if systemctl is-active --quiet NetworkManager; then
        echo "→ 重启 NetworkManager..."
        systemctl restart NetworkManager || true
    elif systemctl is-active --quiet networking; then
        echo "→ 重启 networking..."
        systemctl restart networking || true
    fi

    echo "→ 重置 Docker 防火墙规则..."
    if command -v iptables &>/dev/null; then
        iptables -t nat -F POSTROUTING 2>/dev/null || true
    fi

    echo "→ 重启容器..."
    running_containers=$(docker ps --format "{{.Names}}")
    if [ -n "$running_containers" ]; then
        while IFS= read -r name; do
            if docker restart "$name" >/dev/null 2>&1; then
                echo "✅ 容器 $name 已重启"
            else
                echo "⚠️ 容器 $name 重启失败"
            fi
        done <<< "$running_containers"
    else
        echo "⚠️ 没有运行中的容器"
    fi

    echo "✅ Docker 网络修复完成（已重启服务、清理网络、重置防火墙）"
    pause_return
}

self_heal() {
    if ! command -v docker &>/dev/null; then
        echo "⚠️ Docker 未安装，请先安装。"
        pause_return
        return
    fi

    echo "🔍 即将执行 Docker 自愈程序，包括："
    echo "   • 检查并启动策略允许的异常退出容器"
    echo "   • 清理无用的容器、镜像和构建缓存"
    echo "   • 显示当前容器状态摘要"
    read -r -p "确认继续？(Y/N): " confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        echo "已取消"
        pause_return
        return
    fi

    if ! systemctl is-active --quiet docker; then
        echo "⚠️ Docker 服务未运行，正在启动..."
        systemctl start docker || true
        sleep 2
        if ! systemctl is-active --quiet docker; then
            echo "⚠️ Docker 服务启动失败，请检查日志: journalctl -u docker"
            pause_return
            return
        fi
    fi

    echo "→ 检查异常退出的容器..."
    exited_containers=$(docker ps -a --filter "status=exited" --filter "status=created" --format "{{.Names}}")
    if [ -n "$exited_containers" ]; then
        for name in $exited_containers; do
            restart_policy=$(docker inspect -f '{{.HostConfig.RestartPolicy.Name}}' "$name" 2>/dev/null || true)
            case "$restart_policy" in
                always|unless-stopped|on-failure)
                    echo "→ 自动重启容器: $name (策略: $restart_policy)"
                    docker start "$name" 2>/dev/null && echo "✅ 已重启 $name" || echo "⚠️ 重启 $name 失败"
                    ;;
                *)
                    echo "ℹ️ 容器 $name 已退出但重启策略为 $restart_policy，跳过自动重启"
                    ;;
            esac
        done
    else
        echo "✅ 无异常退出的容器"
    fi

    echo "→ 清理无用的容器、镜像和构建缓存..."
    docker system prune -f || true

    echo -e "\n📋 当前容器状态摘要："
	echo "---------------------------------------------------------------------------"
    docker ps -a --format "table {{.Names}}\t{{.Status}}\t{{.Image}}"
	echo "---------------------------------------------------------------------------"

    echo "✅ Docker 自愈完成"
    pause_return
}

open_ports() {
    echo "🐳 端口管理工具"
    echo "1) 查看防火墙已开放端口 (ufw)"
    echo "2) 查看 Docker 容器映射端口"
    echo "3) 检测/释放端口"
    echo "4) 开放端口"
    echo "0) 返回主菜单"
    read -r -p "请选择: " action

    case $action in
1)
    if ! command -v ufw >/dev/null 2>&1; then
        echo "⚠️ 系统未安装 ufw"
        read -r -p "是否自动安装 ufw？(Y/N): " install_ufw
        if [[ ! "$install_ufw" =~ ^[Yy]$ ]]; then
            echo "↩️ 已跳过安装，请手动安装 ufw 后重试"
            pause_return
            return
        fi

        echo "🔧 正在自动安装 ufw..."
        
        if command -v apt-get >/dev/null 2>&1; then
            apt-get update || true
            apt-get install ufw -y || true
        elif command -v dnf >/dev/null 2>&1; then
            dnf install ufw -y || true
        elif command -v yum >/dev/null 2>&1; then
            yum install epel-release -y || true
            yum install ufw -y || true
        elif command -v pacman >/dev/null 2>&1; then
            pacman -S ufw --noconfirm || true
        elif command -v apk >/dev/null 2>&1; then
            apk add ufw ip6tables || true
        elif command -v zypper >/dev/null 2>&1; then
            zypper install -y ufw || true
        else
            echo "⚠️ 无法自动安装 ufw，请手动安装后重试"
            pause_return
            return
        fi
        
        if ! command -v ufw >/dev/null 2>&1; then
            echo "⚠️ ufw 安装失败，请手动检查"
            pause_return
            return
        fi
        echo "✅ ufw 安装完成"
    fi

    UFW_STATUS=$(ufw status 2>/dev/null || true)
    if echo "$UFW_STATUS" | grep -qiE 'inactive|不活动'; then
        echo "⚠️ 防火墙未启用"
        echo "💡 当前所有端口默认开放"
        read -r -p "是否启用防火墙? (Y/N): " yn
        if [[ "$yn" =~ ^[Yy]$ ]]; then
            if ufw allow OpenSSH >/dev/null 2>&1; then
                echo "✅ 已放行 SSH（通过 OpenSSH 应用）"
            else
                ufw allow 22/tcp >/dev/null 2>&1
                echo "✅ 已放行 SSH（端口 22/tcp）"
            fi
            ufw --force enable >/dev/null 2>&1 || true
            if ! ufw status | grep -qE '22/tcp.*ALLOW|OpenSSH.*ALLOW'; then
                echo "⚠️ 自动放行 SSH 失败，请手动执行: ufw allow 22/tcp"
            fi
        else
            echo "已取消"
        fi
        pause_return
        return
    fi

    echo "✅ 防火墙状态：已启用"
    echo "📌 当前已放行端口规则:"
    RULES=$(ufw status 2>/dev/null | sed -e '/^Status:/d' -e '/^状态：/d' -e '/^$/d' \
        -e 's#ALLOW IN#允许进入#g' \
        -e 's#ALLOW OUT#允许流出#g' \
        -e 's#DENY IN#拒绝进入#g' \
        -e 's#DENY OUT#拒绝流出#g' \
        -e 's#LIMIT IN#限制进入#g' \
        -e 's#ALLOW#允许进入#g' \
        -e 's#Anywhere (v6)#任意位置 (v6)#g' \
        -e 's#Anywhere#任意位置#g') || true
    
    if [ -z "$RULES" ]; then
        echo "⚠️ 当前无任何放行规则"
    else
        echo "$RULES"
    fi

    read -r -p "🔹 是否关闭防火墙并清空规则? (Y/N): " close_fw
    if [[ "$close_fw" =~ ^[Yy]$ ]]; then
        echo "⚠️ 正在清空所有规则并关闭防火墙..."
        ufw --force reset >/dev/null 2>&1
        systemctl stop ufw >/dev/null 2>&1 || true
        systemctl disable ufw >/dev/null 2>&1 || true
        echo "⚠️ 防火墙已关闭，所有端口默认开放"
    fi
    pause_return
;;
2)
    echo "🐳 Docker 容器端口:"
    if command -v docker >/dev/null 2>&1; then
        echo "--------------------------------------------------------------------------------------------------------------------------------"
        printf "%-20s %-20s %s\n" "容器名称" "状态" "PORTS"
        echo "--------------------------------------------------------------------------------------------------------------------------------"
        docker ps --format "{{.Names}}\t{{.Status}}\t{{.Ports}}" 2>/dev/null | while IFS=$'\t' read -r name status ports; do
            status_clean=$(echo "$status" | sed -E 's/\s*\([^)]*\)//g')
            
            status_cn="$status_clean"
            status_cn=$(echo "$status_cn" | sed -E 's/Up ([0-9]+) seconds?/已运行 \1 秒/')
            status_cn=$(echo "$status_cn" | sed -E 's/Up ([0-9]+) minutes?/已运行 \1 分钟/')
            status_cn=$(echo "$status_cn" | sed -E 's/Up ([0-9]+) hours?/已运行 \1 小时/')
            status_cn=$(echo "$status_cn" | sed -E 's/Up ([0-9]+) days?/已运行 \1 天/')
            status_cn=$(echo "$status_cn" | sed -E 's/Up ([0-9]+) weeks?/已运行 \1 周/')
            status_cn=$(echo "$status_cn" | sed -E 's/Up ([0-9]+) months?/已运行 \1 月/')
            status_cn=$(echo "$status_cn" | sed -E 's/Up ([0-9]+) years?/已运行 \1 年/')
            status_cn=$(echo "$status_cn" | sed -E 's/Exited \(0\)/已停止/')
            
            if [[ "$status_cn" =~ ^Restarting ]]; then
                status_cn=$(echo "$status_cn" | sed -E 's/Restarting/重启中/')
                status_cn=$(echo "$status_cn" | sed -E 's/ seconds? ago/秒前/')
                status_cn=$(echo "$status_cn" | sed -E 's/ minutes? ago/分钟前/')
                status_cn=$(echo "$status_cn" | sed -E 's/ hours? ago/小时前/')
                status_cn=$(echo "$status_cn" | sed -E 's/ days? ago/天前/')
                status_cn=$(echo "$status_cn" | sed -E 's/ weeks? ago/周前/')
                status_cn=$(echo "$status_cn" | sed -E 's/ months? ago/月前/')
                status_cn=$(echo "$status_cn" | sed -E 's/ years? ago/年前/')
            fi
            
            printf "%-20s %-20s %s\n" "$name" "$status_cn" "$ports"
        done
        echo "--------------------------------------------------------------------------------------------------------------------------------"
    else
        echo "⚠️ Docker 未安装，请先安装。"
    fi
    pause_return
;;
3)
    set +e

    if ! command -v lsof &>/dev/null; then
        echo "📦 lsof 未安装，正在自动安装..."
        case "$OS" in
            ubuntu|debian|armbian)
                apt update && apt install -y lsof
                ;;
            centos|rocky|rhel|fedora)
                if command -v dnf &>/dev/null; then
                    dnf install -y lsof
                else
                    yum install -y lsof
                fi
                ;;
            arch)
                pacman -S --noconfirm lsof
                ;;
            suse)
                zypper install -y lsof
                ;;
            alpine)
                apk add lsof
                ;;
            *)
                echo "⚠️ 无法自动安装 lsof，请手动安装后重试"
                pause_return
                set -e
                return
                ;;
        esac
        if ! command -v lsof &>/dev/null; then
            echo "⚠️ lsof 安装失败，无法检测端口"
            pause_return
            set -e
            return
        fi
        echo "✅ lsof 安装完成"
    fi

    echo "🔍 检测/释放端口"
    read -r -p "输入要检测的端口(多个用空格分隔, 0取消, A一键释放所有占用): " ports
    if [ -z "$ports" ] || [ "$ports" = "0" ]; then
        echo "已取消"
        pause_return
        set -e
        return
    fi

    if [[ "$ports" =~ ^[aA]$ ]]; then
        echo "⚠️ 警告：一键释放会结束所有占用端口的容器和系统进程"
        read -r -p "确认执行? (Y/N): " yn
        if [[ ! "$yn" =~ ^[Yy]$ ]]; then
            echo "↩️ 已取消操作"
            pause_return
            set -e
            return
        fi

        if command -v docker >/dev/null 2>&1; then
            docker ps --format "{{.Names}}\t{{.Ports}}" 2>/dev/null | while IFS=$'\t' read -r name ports; do
                [[ -z "$ports" ]] && continue
                echo "🐳 停止容器 $name 释放端口..."
                docker stop "$name" >/dev/null 2>&1 && echo "✅ 容器 $name 已停止（端口释放）"
            done
        fi

        for pid in $(lsof -t -iTCP -sTCP:LISTEN 2>/dev/null); do
            [ -z "$pid" ] && continue
            PROC_NAME=$(ps -p $pid -o comm= 2>/dev/null)
            PORTS=$(lsof -Pan -p $pid -iTCP -sTCP:LISTEN 2>/dev/null | awk -F'[:()]' '{print $2}' | xargs)
            echo "🖥️ 进程: $PROC_NAME | PID: $pid | 端口: $PORTS | 状态: 监听中"
            kill -9 $pid >/dev/null 2>&1 && echo "✅ 已结束 $PROC_NAME (PID=$pid)" || echo "⚠️ 结束失败 PID=$pid"
        done

        echo "🔥 已一键释放所有占用端口"
        pause_return
        set -e
        return
    fi

    for port in $ports; do
        echo "📌 端口: $port"

        if command -v docker >/dev/null 2>&1; then
            DOCKER=$(docker ps --format "{{.Names}}\t{{.Ports}}" 2>/dev/null | grep -F ":$port->")
            if [ -n "$DOCKER" ]; then
                CONTAINER=$(echo "$DOCKER" | awk '{print $1}')
                read -r -p "🐳 Docker 占用, 是否停止容器 $CONTAINER ? (Y/N): " yn
                if [[ "$yn" =~ ^[Yy]$ ]]; then
                    if docker stop "$CONTAINER" >/dev/null 2>&1; then
                        echo "✅ 已停止容器 $CONTAINER（端口释放）"
                    else
                        echo "⚠️ 停止容器 $CONTAINER 失败"
                    fi
                else
                    echo "↩️ 已取消释放（容器 $CONTAINER 继续运行）"
                fi
                continue
            fi
        fi

        PID=$(lsof -t -i ":$port" 2>/dev/null)
        if [ -n "$PID" ]; then
            PROC_NAME=$(ps -p "$PID" -o comm= 2>/dev/null)
            read -r -p "🖥️ 系统进程 $PROC_NAME 占用端口 $port, 是否释放? (Y/N): " yn
            if [[ "$yn" =~ ^[Yy]$ ]]; then
                kill "$PID" 2>/dev/null || true
                sleep 1
                if ! lsof -i ":$port" >/dev/null 2>&1; then
                    echo "✅ 已释放端口 $port"
                else
                    kill -9 "$PID" 2>/dev/null || true
                    if ! lsof -i ":$port" >/dev/null 2>&1; then
                        echo "🔥 已强制释放端口 $port"
                    else
                        echo "⚠️ 释放失败"
                    fi
                fi
            else
                echo "↩️ 已取消释放（进程 $PROC_NAME 继续占用端口 $port）"
            fi
        else
            echo "✅ 端口 $port 未被占用"
        fi
    done

    pause_return
    set -e
;;
4)
    echo "🔓 开放端口"
    if ! command -v ufw >/dev/null 2>&1; then
        echo "⚠️ 系统未安装 ufw"
        pause_return
        return
    fi

    read -r -p "输入要开放的端口(多个用空格分隔，0取消): " ports
    if [ -z "$ports" ] || [ "$ports" = "0" ]; then
        echo "已取消"
    else
        for port in $ports; do
            if ! [[ "$port" =~ ^[0-9]+$ ]] || [ "$port" -le 0 ] || [ "$port" -gt 65535 ]; then
                echo "⚠️ 非法端口: $port"
                continue
            fi
            ufw allow "$port" >/dev/null 2>&1 && echo "✅ 端口 $port 已开放" || echo "⚠️ 端口 $port 开放失败"
        done
    fi
    pause_return
;;
0)
            break
            ;;
*)
            echo "⚠️ 无效选择"
            pause_return
            ;;
    esac
}

# -------------------------
# 容器工具子菜单
# -------------------------
container_tools_menu() {
    echo "===== 容器管理工具 ====="
    echo "1) 容器实时监控"
    echo "2) 查看容器日志"
    echo "3) 进入容器 Shell"
    echo "4) 批量更新容器镜像"
    echo "5) Docker 磁盘分析"
	echo "6) Docker 健康报告"
	echo "7) Docker 安全审计"
	echo "8) Docker 日志轮转"
    echo "9) 深度清理（容器/镜像）"
    echo "10) 命令导出"
    echo "11) 文件浏览"
    echo "12) 网络管理"
    echo "13) 导出镜像"
    echo "14) 导入镜像"
    echo "0) 返回主菜单"
    read -r -p "请选择: " tool_opt

    case $tool_opt in
        1) show_container_stats ;;
        2) view_container_logs ;;
        3) enter_container_shell ;;
        4) update_selected_containers ;;
        5) show_disk_usage ;;
		6) docker_health_report ;;
		7) docker_security_audit ;;
        8) config_log_rotation ;;
        9) clean_stopped_and_unused ;;
        10) export_container_start_cmd ;;
        11) browse_container_files ;;
        12) container_network_menu ;;
        13) export_image ;;
        14) import_image ;;
        0) return ;;
        *) echo "⚠️ 无效选择"; pause_return ;;
    esac
    return
}

# 1. 容器实时监控
show_container_stats() {
    if ! command -v docker &>/dev/null; then
        echo "⚠️ Docker 未安装，请先安装。"
        pause_return
        return
    fi
    if [ -z "$(docker ps -q)" ]; then
        echo "⚠️ 没有正在运行的容器。"
        pause_return
        return
    fi

    if ! command -v watch &>/dev/null; then
        echo "📦 未检测到 watch 命令，正在自动安装..."
        case "$OS" in
            ubuntu|debian|armbian)
                apt update && apt install -y procps || true
                ;;
            centos|rocky|rhel|fedora)
                if command -v dnf &>/dev/null; then
                    dnf install -y procps || true
                else
                    yum install -y procps || true
                fi
                ;;
            arch)
                pacman -S --noconfirm procps-ng || true
                ;;
            suse)
                zypper install -y procps || true
                ;;
            alpine)
                apk add procps || true
                ;;
            *)
                echo "⚠️ 无法自动安装 watch，请手动安装 procps 包"
                ;;
        esac
        if ! command -v watch &>/dev/null; then
            echo "⚠️ watch 安装失败，将使用原生 docker stats（表头可能仅首次显示）"
            docker stats --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.MemPerc}}\t{{.NetIO}}\t{{.BlockIO}}"
            echo "✅ 监控已结束"
            pause_return
            return
        fi
        echo "✅ watch 安装完成"
    fi
    
    watch -t -n 1 'clear; echo "📊 容器实时资源监控（按 Ctrl+C 退出监控）";
    echo "============================================================================================";
    docker stats --no-stream --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.MemPerc}}\t{{.NetIO}}\t{{.BlockIO}}"' || true
    
    echo "✅ 监控已结束"
    pause_return
}

# 2. 查看容器日志
view_container_logs() {
    if ! docker ps -a --format "{{.Names}}" | grep -q .; then
        echo "⚠️ 没有找到任何容器，请先安装或运行容器。"
        pause_return
        return
    fi

    local container
    container=$(select_containers_for_backup single "📦 请选择要查看日志的容器") || return
    [ -z "$container" ] && return
    echo "请选择日志查看方式："
    echo "1) 最后 50 行"
    echo "2) 最后 100 行"
    echo "3) 最后 200 行"
    echo "4) 实时跟踪（Ctrl+C 退出）"
    echo "5) 实时跟踪 + 关键字过滤"
    read -r -p "请选择: " opt

    case $opt in
        1) 
            clear
            lines=50 ;;
        2) 
            clear
            lines=100 ;;
        3) 
            clear
            lines=200 ;;
        4)
            clear
            echo "📡 实时跟踪容器 $container 的日志（按 Ctrl+C 退出）..."
            docker logs -f "$container" || true
            echo ""
            pause_return
            return
            ;;
        5)
            clear
            read -r -p "请输入过滤关键字: " keyword
            if [ -z "$keyword" ]; then
                echo "关键字不能为空"
                return
            fi
            echo "📡 实时跟踪并过滤关键字: $keyword （按 Ctrl+C 退出）..."
            docker logs -f "$container" | grep --color=always "$keyword" || true
            echo ""
            pause_return
            return
            ;;
        *)
            echo "⚠️ 无效选择"
            pause_return
            return
            ;;
    esac

    echo "📜 容器 $container 最后 ${lines} 行日志："
    echo "------------------------------------------------------------"
    docker logs --tail "$lines" "$container"
    echo "------------------------------------------------------------"
    pause_return
}

# 3. 进入容器 Shell
enter_container_shell() {
    local running_containers=$(docker ps --format "{{.Names}}")
    if [ -z "$running_containers" ]; then
        echo "⚠️ 没有正在运行的容器"
        pause_return
        return
    fi

    echo "📦 请选择要进入的容器："
    local i=1
    local name_array=()
    while IFS= read -r name; do
        echo "$i) $name"
        name_array+=("$name")
        ((i++))
    done <<< "$running_containers"
    echo "0) 取消"
    read -r -p "请输入序号: " sel

    if [[ -z "$sel" ]]; then
        echo "⚠️ 无效选择"
        pause_return
        return
    fi

    if [[ "$sel" == "0" ]] || [ "$sel" -lt 1 ] || [ "$sel" -gt ${#name_array[@]} ]; then
        echo "已取消"
        pause_return
        return
    fi

    local container="${name_array[$((sel-1))]}"
    local shell_cmd="sh"
    if docker exec "$container" which bash >/dev/null 2>&1; then
        shell_cmd="bash"
    fi
    echo "🚀 进入容器 $container （使用 $shell_cmd，输入 exit 退出）"
    docker exec -it "$container" "$shell_cmd" || true
    echo "✅ 已退出容器"
    pause_return
}

# 4. 批量更新容器镜像
update_selected_containers() {
    if ! command -v docker &>/dev/null; then
        echo "⚠️ Docker 未安装，请先安装。"
        pause_return
        return
    fi

    local selected
    selected=$(select_containers_for_backup multi "📦 选择要更新镜像的容器") || return
    [ -z "$selected" ] && return

    check_runlike || { echo "⚠️ runlike 镜像拉取失败，无法重建容器"; pause_return; return; }

    for name in $selected; do
        echo "🔄 处理容器: $name"
        local image=$(docker inspect -f '{{.Config.Image}}' "$name" 2>/dev/null)
        if [ -z "$image" ]; then
            echo "   ⚠️ 无法获取容器镜像，跳过"
            continue
        fi
        echo "   拉取最新镜像: $image"
        if ! pull_output=$(docker pull "$image" 2>&1); then
            echo "   ⚠️ 拉取失败: $pull_output"
            continue
        fi

        local old_id=$(docker inspect -f '{{.Image}}' "$name" 2>/dev/null)
        local new_id=$(docker inspect -f '{{.Image}}' "$image" 2>/dev/null)
        if [ "$old_id" != "$new_id" ]; then
            echo "   镜像已更新，准备重建容器..."

            local run_cmd
            if ! run_cmd=$(docker run --rm -v /var/run/docker.sock:/var/run/docker.sock wuyangdaily/runlike "$name" 2>/dev/null); then
                echo "   ⚠️ 无法获取启动命令，跳过重建"
                continue
            fi

            docker rm -f "$name" >/dev/null 2>&1
            if eval "$run_cmd" >/dev/null 2>&1; then
                echo "   ✅ 已重建 $name"

                if [ -n "$old_id" ]; then
                    local ref_count=$(docker ps -a --filter "ancestor=$old_id" -q | wc -l)
                    if [ "$ref_count" -eq 0 ]; then
                        if docker rmi "$old_id" >/dev/null 2>&1; then
                            echo "   🗑 已删除旧镜像 $old_id"
                        else
                            echo "   ℹ️ 旧镜像 $old_id 无法删除（可能仍有依赖）"
                        fi
                    else
                        local using_names=$(docker ps -a --filter "ancestor=$old_id" --format "{{.Names}}" | tr '\n' ' ')
                        echo "   ℹ️ 旧镜像 $old_id 被容器: $using_names使用，跳过删除"
                    fi
                fi
            else
                echo "   ⚠️ 重建失败，请手动检查"
            fi
        else
            echo "   ✅ 镜像已是最新"
        fi
    done
    echo "✅ 批量更新完成"
    pause_return
}

# 5. Docker 磁盘分析
show_disk_usage() {
    if ! command -v docker &>/dev/null; then
        echo "⚠️ Docker 未安装，请先安装。"
        pause_return
        return
    fi
    clear
    echo "📊 Docker 磁盘使用详情"
    echo "========================================================================"
    docker system df -v
    echo "========================================================================"
    echo "💡 提示：可使用 'docker system prune -a' 清理未使用的资源"
    pause_return
}

# 6. Docker 健康报告
docker_health_report() {
    if ! command -v docker >/dev/null 2>&1; then
        echo "⚠️ Docker 未安装，请先安装。"
        pause_return
        return 1
    fi

    clear
    echo "📊 Docker 健康报告"
    echo "=================="

    local running stopped total
    running=$(docker ps -q | wc -l | awk '{print $1}')
    stopped=$(docker ps -aq --filter status=exited --filter status=created | wc -l | awk '{print $1}')
    total=$(docker ps -aq | wc -l | awk '{print $1}')
    echo "容器总数: $total"
    echo "运行中: $running"
    echo "已停止: $stopped"
    echo "------------------"

    if [ "$total" -eq 0 ]; then
        echo "没有检测到任何容器。"
        pause_return
        return 0
    fi

    echo "容器状态概览："
    declare -a table_lines=()
    table_lines+=("$(printf "%-20s %-22s %-30s %-12s %-12s %-10s" "NAME" "STATUS" "IMAGE" "UPTIME" "RESTARTS" "HEALTH")")
    table_lines+=("--------------------------------------------------------------------------------------------------------------")

    while IFS= read -r name; do
        status_raw=$(docker ps -a --filter "name=$name" --format "{{.Status}}" 2>/dev/null)
        status_display=$(format_container_status "$status_raw")

        state=$(docker inspect -f '{{.State.Status}}' "$name" 2>/dev/null)
        if [ "$state" = "running" ]; then
            started=$(docker inspect -f '{{.State.StartedAt}}' "$name" | xargs -I{} date -d {} +%s 2>/dev/null)
            now=$(date +%s)
            uptime_seconds=$((now - started))
            if [ $uptime_seconds -lt 60 ]; then
                uptime="${uptime_seconds}s"
            elif [ $uptime_seconds -lt 3600 ]; then
                uptime="$((uptime_seconds / 60))m"
            elif [ $uptime_seconds -lt 86400 ]; then
                uptime="$((uptime_seconds / 3600))h"
            else
                uptime="$((uptime_seconds / 86400))d"
            fi
        else
            uptime="stopped"
        fi

        restart_count=$(docker inspect -f '{{.RestartCount}}' "$name" 2>/dev/null)
        image=$(docker inspect -f '{{.Config.Image}}' "$name" 2>/dev/null)
        health=$(docker inspect -f '{{.State.Health.Status}}' "$name" 2>/dev/null)
        [ -z "$health" ] && health="none"

        line=$(printf "%-20s %-22s %-30s %-12s %-12s %-10s" "$name" "$status_display" "$image" "$uptime" "$restart_count" "$health")
        table_lines+=("$line")
    done < <(docker ps -a --format "{{.Names}}")

    printf '%s\n' "${table_lines[@]}"
    echo "--------------------------------------------------------------------------------------------------------------"

    echo "资源占用（按 CPU 从高到低）："
    echo "--------------------------------------------------------------------------------------------------------------"
    if [ -n "$(docker ps -q)" ]; then
        docker stats --no-stream --format "{{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.MemPerc}}\t{{.NetIO}}\t{{.BlockIO}}" \
            | sort -k2 -hr \
            | awk 'BEGIN {
                printf "%-20s %-8s %-20s %-6s %-16s %-16s\n", "NAME", "CPU", "MEMORY", "MEM%", "NET I/O", "BLOCK I/O"
            }
            {
                split($3, mem_arr, "/")
                mem_used = mem_arr[1]
                gsub(/^[ \t]+|[ \t]+$/, "", mem_used)
                printf "%-20s %-8s %-20s %-6s %-16s %-16s\n", $1, $2, mem_used, $4, $5, $6
            }'
    else
        echo "当前没有运行中的容器。"
    fi
    echo "=============================================================================================================="
    pause_return
}

# 7. Docker 安全审计
docker_security_audit() {
    if ! command -v docker >/dev/null 2>&1; then
        echo "⚠️ Docker 未安装，请先安装。"
        pause_return
        return 1
    fi
    if ! command -v jq >/dev/null 2>&1; then
        echo "📦 jq 未安装，正在自动安装..."
        case "$OS" in
            ubuntu|debian|armbian)
                apt update && apt install -y jq || true
                ;;
            centos|rocky|rhel|fedora)
                if command -v dnf &>/dev/null; then
                    dnf install -y jq || true
                else
                    yum install -y jq || true
                fi
                ;;
            arch)
                pacman -Sy --noconfirm jq || true
                ;;
            suse)
                zypper install -y jq || true
                ;;
            alpine)
                apk add jq || true
                ;;
            *)
                echo "⚠️ 无法自动安装 jq，请手动安装后重试"
                pause_return
                return 1
                ;;
        esac
        if ! command -v jq >/dev/null 2>&1; then
            echo "⚠️ jq 安装失败，请手动安装后重试"
            pause_return
            return 1
        fi
        echo "✅ jq 安装完成"
    fi

    clear
    echo "🛡️ Docker 安全审计"
    echo "=================="

    echo ""
    echo "📌 宿主机 TCP 端口监听"
    echo "--------------------------------------------------------------------------------------------------------------------------------------------------------------------------"
    if command -v ss &>/dev/null; then
        ss -tlnp 2>/dev/null || echo "⚠️ ss 命令执行失败"
    elif command -v netstat &>/dev/null; then
        netstat -tlnp 2>/dev/null || echo "⚠️ netstat 命令执行失败"
    else
        echo "⚠️ 无法检测端口占用（缺少 ss 或 netstat）"
    fi

    echo ""
    echo "📌 宿主机 UDP 端口监听"
    echo "--------------------------------------------------------------------------------------------------------------------------------------------------------------------------"
    if command -v ss &>/dev/null; then
        ss -ulnp 2>/dev/null || echo "⚠️ 未发现 UDP 监听"
    elif command -v netstat &>/dev/null; then
        netstat -ulnp 2>/dev/null || echo "⚠️ 未发现 UDP 监听"
    else
        echo "⚠️ 无法检测 UDP 端口（缺少 ss 或 netstat）"
    fi

    echo "--------------------------------------------------------------------------------------------------------------------------------------------------------------------------"

    echo "📌 高风险容器概览"
    echo ""
    local found=0

    while IFS= read -r container_name; do
        [ -z "$container_name" ] && continue
        inspect_json=$(docker inspect "$container_name" 2>/dev/null || true)
        [ -z "$inspect_json" ] && continue

        privileged=$(printf '%s' "$inspect_json" | jq -r '.[0].HostConfig.Privileged // false')
        sock_mount=$(printf '%s' "$inspect_json" | jq -r '.[0].Mounts[]? | select(.Source=="/var/run/docker.sock" or .Source=="/run/docker.sock") | .Source' | head -n1)
        port_bindings=$(printf '%s' "$inspect_json" | jq -r '.[0].NetworkSettings.Ports // {} | to_entries[]? | "\(.key) => \(.value[0].HostIp // "0.0.0.0"):\(.value[0].HostPort // "")"' )

        if [ "$privileged" = "true" ] || [ -n "$sock_mount" ] || [ -n "$port_bindings" ]; then
            found=1
            echo "容器: $container_name"
            [ "$privileged" = "true" ] && echo "  ⚠️ privileged=true"
            [ -n "$sock_mount" ] && echo "  ⚠️ 挂载 docker.sock"
            if [ -n "$port_bindings" ]; then
                echo "  端口映射:"
                printf '%s\n' "$port_bindings" | sed 's/^/    - /'
            fi
            echo
        fi
    done < <(docker ps -a --format "{{.Names}}")

    if [ "$found" -eq 0 ]; then
        echo "未发现明显高风险容器配置。"
    else
        echo "💡 建议：对暴露端口、docker.sock、privileged 容器进行最小化收敛。"
    fi
    pause_return
}

# 8. Docker 日志轮转
config_log_rotation() {
    if ! command -v docker &>/dev/null; then
        echo "⚠️ Docker 未安装，请先安装。"
        pause_return
        return
    fi

    echo "📑 配置 Docker 日志轮转（防止磁盘爆满）"
    echo "当前配置将限制单个容器日志文件最大 5MB，最多保留 3 个文件。"
    read -r -p "是否应用此配置？(Y/N): " confirm
    [[ ! "$confirm" =~ ^[Yy]$ ]] && echo "已取消" && return

    mkdir -p /etc/docker

    tmp_json=$(mktemp)
    if command -v jq &>/dev/null; then
        if [ -f /etc/docker/daemon.json ]; then
            jq '. + {"log-driver": "json-file", "log-opts": {"max-size": "5m", "max-file": "3"}}' /etc/docker/daemon.json > "$tmp_json"
        else
            jq -n '{"log-driver": "json-file", "log-opts": {"max-size": "5m", "max-file": "3"}}' > "$tmp_json"
        fi
        mv "$tmp_json" /etc/docker/daemon.json
    else
        cat >> /etc/docker/daemon.json <<EOF
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "5m",
    "max-file": "3"
  }
}
EOF
        echo "⚠️ 未安装 jq，配置可能覆盖原有内容，请手动检查 /etc/docker/daemon.json"
    fi

    echo "🔄 重启 Docker 服务..."
    systemctl restart docker || true
    echo "✅ 日志轮转配置已生效"
    echo "💡 现有容器需要重启才会应用新日志配置"
    pause_return
}

# 9. 批量清理（停止容器/悬空镜像/深度清理）
clean_stopped_and_unused() {
    if ! command -v docker &>/dev/null; then
        echo "⚠️ Docker 未安装，请先安装。"
        pause_return
        return
    fi

    stopped_ids=$(docker ps -aq --filter "status=exited" --filter "status=created")
    stop_names=()
    for cid in $stopped_ids; do
        name=$(docker inspect -f '{{.Name}}' "$cid" | sed 's/^\///')
        stop_names+=("$name")
    done

    dangling_images=$(docker images --filter "dangling=true" --format "{{.Repository}}:{{.Tag}}" 2>/dev/null)

    if [ ${#stop_names[@]} -gt 0 ] || [ -n "$dangling_images" ]; then
        echo "📋 以下资源将被清理"
        if [ ${#stop_names[@]} -gt 0 ]; then
            echo ""
            echo "停止的容器："
            for name in "${stop_names[@]}"; do
                echo "  - $name"
            done
        fi
        if [ -n "$dangling_images" ]; then
            echo ""
            echo "悬空镜像（dangling）："
            echo "$dangling_images" | while read -r img; do
                echo "  - $img"
            done
        fi
        echo ""
        read -r -p "确认删除上述停止的容器和悬空镜像？(Y/N): " confirm
        if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
            echo "已取消"
            pause_return
            return
        fi

        if [ ${#stop_names[@]} -gt 0 ]; then
            echo ""
            echo "🧹 清理停止的容器..."
            for cid in $stopped_ids; do
                docker rm "$cid" >/dev/null 2>&1 || true
            done
            echo "✅ 已删除 ${#stop_names[@]} 个停止的容器"
        fi

        echo ""
        echo "🧹 清理悬空镜像..."
        docker image prune -f || true
        echo "✅ 悬空镜像清理完成"
    else
        echo "✅ 没有停止的容器或悬空镜像需要清理。"
    fi

    protect_container="tmp-runlike-protector"
    docker rm -f "$protect_container" 2>/dev/null || true
    need_protect=false
    if docker image inspect wuyangdaily/runlike:latest &>/dev/null; then
        need_protect=true
        echo "🛡️ 正在创建保护容器，防止 runlike 镜像被误删..."
        docker run -d --restart=always --name "$protect_container" wuyangdaily/runlike:latest tail -f /dev/null >/dev/null 2>&1 || true
        sleep 1
        if ! docker ps --format "{{.Names}}" | grep -q "^$protect_container$"; then
            docker rm -f "$protect_container" 2>/dev/null
            docker run -d --restart=always --name "$protect_container" wuyangdaily/runlike:latest /bin/sh -c "while true; do sleep 1000; done" >/dev/null 2>&1 || true
        fi
        echo "✅ 保护容器已运行"
    fi

    all_images=$(docker images --format "{{.Repository}}:{{.Tag}}" | grep -v "<none>")
    used_images=$(docker ps --format "{{.Image}}" | sort -u)
    to_delete_images=()
    while read -r img; do
        if ! echo "$used_images" | grep -qx "$img"; then
            to_delete_images+=("$img")
        fi
    done <<< "$all_images"

    deep_networks=()
    while IFS= read -r net; do
        deep_networks+=("$net")
    done < <(docker network ls --format "{{.Name}}" --filter "dangling=true" 2>/dev/null)

    build_cache_items=()
    has_build_cache=false
    if command -v docker &>/dev/null && docker builder prune --dry-run &>/dev/null; then
        cache_dry_run=$(docker builder prune --dry-run 2>/dev/null)
        if [[ "$cache_dry_run" =~ "would be removed" ]] && ! [[ "$cache_dry_run" =~ "0 would be removed" ]]; then
            while IFS= read -r line; do
                if [[ "$line" =~ ^([0-9a-f]{12})\s+([0-9.]+[KMGT]?B) ]]; then
                    id="${BASH_REMATCH[1]}"; size="${BASH_REMATCH[2]}"
                    build_cache_items+=("$id ($size)")
                elif [[ "$line" =~ ^([0-9a-f]{12}) ]]; then
                    build_cache_items+=("$line")
                fi
            done <<< "$cache_dry_run"
            if [ ${#build_cache_items[@]} -gt 0 ]; then
                has_build_cache=true
            else
                cache_count=$(echo "$cache_dry_run" | grep -oP 'Would remove \K[0-9]+' | head -1)
                cache_size=$(echo "$cache_dry_run" | grep -oP 'reclaimable space: \K[0-9.]+[KMGT]?B' | head -1)
                if [ -n "$cache_count" ] && [ "$cache_count" -gt 0 ]; then
                    has_build_cache=true
                    if [ -n "$cache_size" ]; then
                        build_cache_items=("共 $cache_count 个缓存条目，将释放 $cache_size")
                    else
                        build_cache_items=("共 $cache_count 个缓存条目")
                    fi
                fi
            fi
        fi
    fi

    volume_names=()
    for vol in $(docker volume ls -qf dangling=true 2>/dev/null); do
        volume_names+=("$vol")
    done

    if [ ${#to_delete_images[@]} -eq 0 ] && [ ${#deep_networks[@]} -eq 0 ] && [ "$has_build_cache" = false ] && [ ${#volume_names[@]} -eq 0 ]; then
        echo ""
        echo "✅ 没有需要深度清理的资源（无未使用镜像、网络、缓存、卷）。"
    else
        echo ""
        echo "⚡ 是否需要深度清理以下资源？"
        if [ ${#to_delete_images[@]} -gt 0 ]; then
            echo "  - 未被任何容器引用的镜像（带标签）："
            for img in "${to_delete_images[@]}"; do
                echo "      $img"
            done
        fi
        if [ ${#deep_networks[@]} -gt 0 ]; then
            echo "  - 未使用的 Docker 网络："
            for net in "${deep_networks[@]}"; do
                echo "      $net"
            done
        fi
        if [ "$has_build_cache" = true ]; then
            if [ ${#build_cache_items[@]} -gt 0 ] && [[ ! "${build_cache_items[0]}" =~ ^共 ]]; then
                echo "  - Docker 构建缓存条目："
                for item in "${build_cache_items[@]}"; do
                    echo "      $item"
                done
            else
                echo "  - Docker 构建缓存：${build_cache_items[0]}"
            fi
        fi
        if [ ${#volume_names[@]} -gt 0 ]; then
            echo "  - 未使用的卷（删除后将永久丢失数据）："
            for vol in "${volume_names[@]}"; do
                echo "      $vol"
            done
        fi
        echo ""
        read -r -p "确认执行深度清理？(Y/N): " confirm_deep
        if [[ "$confirm_deep" =~ ^[Yy]$ ]]; then
            echo "正在执行 docker system prune -a ..."
            docker system prune -a -f || true
            echo "正在清理未使用的卷..."
            docker volume prune -f || true
            echo "✅ 深度清理完成"
        else
            echo "跳过深度清理"
        fi
    fi

    [ "$need_protect" = true ] && docker rm -f "$protect_container" >/dev/null 2>&1 && echo "🛡️ 已移除保护容器"

    echo ""
    echo "💡 提示：所有清理操作已完成。"
    pause_return
}

# 10. 命令导出
export_container_start_cmd() {
    if ! command -v docker &>/dev/null; then
        echo "⚠️ Docker 未安装，请先安装。"
        pause_return
        return
    fi

    local container=$(select_containers_for_backup single "📦 选择要导出启动命令的容器") || return
    [ -z "$container" ] && return

    check_runlike || return

    local filename="/root/${container}_run_cmd.sh"
    echo "# 容器 $container 的启动命令" > "$filename"
    echo "# 生成时间: $(date)" >> "$filename"
    echo "" >> "$filename"
    if docker run --rm -v /var/run/docker.sock:/var/run/docker.sock wuyangdaily/runlike "$container" > "$filename" 2>/dev/null; then
        echo "✅ 启动命令已保存到: $filename"
		echo "💡 使用方法: bash $filename"
    else
        echo "⚠️ 导出失败"
        rm -f "$filename"
    fi
    pause_return
}

# 11. 文件浏览
browse_container_files() {
    if ! command -v docker &>/dev/null; then
        echo "⚠️ Docker 未安装，请先安装。"
        pause_return
        return
    fi

    local container
    container=$(select_containers_for_backup single "📦 选择要浏览文件的容器") || return
    [ -z "$container" ] && return

    echo "当前容器: $container"
    printf "请输入要浏览的容器内绝对路径（回车则默认为 /）: "
    read -r path < /dev/tty
    if [ -z "$path" ]; then
        path="/"
    fi

    if ! docker exec "$container" test -e "$path" 2>/dev/null; then
        echo "⚠️ 路径 $path 在容器内不存在"
        pause_return
        return
    fi

    if docker exec "$container" test -f "$path" 2>/dev/null; then
        echo "📄 文件内容（前20行）:"
        echo "---------------------------------------------------"
        docker exec "$container" head -n 20 "$path" 2>/dev/null || echo "无法读取文件"
        echo "---------------------------------------------------"
        read -r -p "是否查看完整内容？(Y/N): " full
        if [[ "$full" =~ ^[Yy]$ ]]; then
            docker exec "$container" cat "$path" 2>/dev/null || echo "读取失败"
        fi
    elif docker exec "$container" test -d "$path" 2>/dev/null; then
        echo "📁 目录内容:"
        echo "---------------------------------------------------"
        docker exec "$container" ls -lah --color=never "$path" 2>/dev/null || echo "无法列出目录"
        echo "---------------------------------------------------"
    else
        echo "⚠️ 路径存在但不是普通文件或目录"
    fi
    pause_return
}

# 12. 网络管理
container_network_menu() {
    while true; do
        clear
        echo "===== 容器网络管理 ====="
        echo "1) 查看容器 IP 地址"
        echo "2) 查看 Docker 网络"
        echo "3) 创建自定义网络"
        echo "4) 删除自定义网络"
        echo "5) 将容器连接到网络"
        echo "6) 将容器从网络断开"
        echo "7) 修改容器重启策略"
        echo "0) 返回主菜单"
        read -r -p "请选择: " net_opt

        case $net_opt in
            1)
                echo "📋 容器 IP 地址列表:"
                echo "---------------------------------------------------"
                docker ps -q | while read cid; do
                    name=$(docker inspect -f '{{.Name}}' "$cid" | sed 's/^\///')
                    ip=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "$cid")
                    echo "$name : ${ip:-未连接}"
                done
                echo "---------------------------------------------------"
                pause_return
                ;;
            2)
                docker network ls
                pause_return
                ;;
            3)
                read -r -p "请输入网络名称: " net_name
                if [ -z "$net_name" ]; then
                    echo "⚠️ 错误：网络名称不能为空！"
                    pause_return
                    continue
                fi
                read -r -p "请输入子网（如 172.20.0.0/24，回车则为默认）: " subnet
                if [ -n "$subnet" ]; then
                    if docker network create --subnet="$subnet" "$net_name" 2>/dev/null; then
                        echo "✅ 网络 $net_name 已创建"
                    else
                        echo "⚠️ 创建失败：名称可能已存在或子网格式无效"
                    fi
                else
                    if docker network create "$net_name" 2>/dev/null; then
                        echo "✅ 网络 $net_name 已创建"
                    else
                        echo "⚠️ 创建失败：名称可能已存在"
                    fi
                fi
                pause_return
                ;;
            4)
                echo "可删除的网络列表："
                local networks=()
                local i=1
                while IFS= read -r net; do
                    echo "$i) $net"
                    networks+=("$net")
                    ((i++))
                done < <(docker network ls --format "{{.Name}}")
                if [ ${#networks[@]} -eq 0 ]; then
                    echo "⚠️ 没有找到任何网络"
                    pause_return
                    continue
                fi
                echo "0) 取消"
                read -r -p "请选择要删除的网络序号: " sel
                if [ -z "$sel" ]; then
                    echo "⚠️ 无效选择"
                    pause_return
                    continue
                fi
                if [[ "$sel" == "0" ]] || [ -z "${networks[$((sel-1))]}" ]; then
                    echo "已取消"
                    pause_return
                    continue
                fi
                local net_name="${networks[$((sel-1))]}"
                docker network rm "$net_name" 2>/dev/null
                if [ $? -eq 0 ]; then
                    echo "✅ 网络 $net_name 已删除"
                else
                    echo "⚠️ 删除失败（网络可能正在被使用或是系统默认网络）"
                fi
                pause_return
                ;;
            5)
                local container
                container=$(select_containers_for_backup single "📦 选择要连接到网络的容器") || continue
                [ -z "$container" ] && continue

                echo "可用的网络："
                local networks=()
                local i=1
                while IFS= read -r net; do
                    echo "$i) $net"
                    networks+=("$net")
                    ((i++))
                done < <(docker network ls --format "{{.Name}}")
                if [ ${#networks[@]} -eq 0 ]; then
                    echo "⚠️ 没有可用的网络"
                    pause_return
                    continue
                fi
                echo "0) 取消"
                read -r -p "请选择网络序号: " sel
                if [ -z "$sel" ]; then
                    echo "⚠️ 无效选择"
                    pause_return
                    continue
                fi
                if [[ "$sel" == "0" ]] || [ -z "${networks[$((sel-1))]}" ]; then
                    echo "已取消"
                    pause_return
                    continue
                fi
                local net_name="${networks[$((sel-1))]}"
                docker network connect "$net_name" "$container" 2>/dev/null
                if [ $? -eq 0 ]; then
                    echo "✅ 容器 $container 已连接到网络 $net_name"
                else
                    echo "⚠️ 连接失败（可能已连接或不支持的操作）"
                fi
                pause_return
                ;;
            6)
                local container
                container=$(select_containers_for_backup single "📦 选择要断开网络的容器") || continue
                [ -z "$container" ] && continue

                echo "容器 $container 已连接的网络："
                local networks=()
                local i=1
                while IFS= read -r net; do
                    [ -z "$net" ] && continue
                    echo "$i) $net"
                    networks+=("$net")
                    ((i++))
                done < <(docker inspect -f '{{range $net, $conf := .NetworkSettings.Networks}}{{$net}}{{"\n"}}{{end}}' "$container" 2>/dev/null)
                if [ ${#networks[@]} -eq 0 ]; then
                    echo "⚠️ 容器 $container 没有连接任何网络"
                    pause_return
                    continue
                fi
                echo "0) 取消"
                read -r -p "请选择要断开的网络序号: " sel
                if [ -z "$sel" ]; then
                    echo "⚠️ 无效选择"
                    pause_return
                    continue
                fi
                if [[ "$sel" == "0" ]] || [ -z "${networks[$((sel-1))]}" ]; then
                    echo "已取消"
                    pause_return
                    continue
                fi
                local net_name="${networks[$((sel-1))]}"
                docker network disconnect "$net_name" "$container" 2>/dev/null
                if [ $? -eq 0 ]; then
                    echo "✅ 容器 $container 已从网络 $net_name 断开"
                else
                    echo "⚠️ 断开失败（可能为默认网络或当前唯一网络）"
                fi
                pause_return
                ;;
            7)
                local selected_names
                selected_names=$(select_containers_for_backup multi "📦 请选择要修改重启策略的容器")
                if [ -z "$selected_names" ]; then
                    pause_return
                    continue
                fi

                local containers=($selected_names)
                echo ""
                echo "📋 将修改以下 ${#containers[@]} 个容器的重启策略："
                for cn in "${containers[@]}"; do
                    local cur_policy=$(docker inspect "$cn" -f '{{.HostConfig.RestartPolicy.Name}}' 2>/dev/null)
                    echo "   • $cn (当前: ${cur_policy:-未设置})"
                done

                echo ""
                echo "💡 可选重启策略:"
                echo "1) no             - 容器退出时不自动重启"
                echo "2) on-failure     - 仅在非正常退出时重启"
                echo "3) always         - 总是重启"
                echo "4) unless-stopped - 除非手动停止，否则总是重启"
                echo "0) 取消"
                read -r -p "请选择新的策略 (1-4): " policy_choice

                local new_policy=""
                case $policy_choice in
                    1) new_policy="no" ;;
                    2)
                        new_policy="on-failure"
						read -r -p "设置最大重试次数（回车默认无限）: " max_retries
                        if [[ -n "$max_retries" ]]; then
                            if [[ "$max_retries" =~ ^[0-9]+$ ]]; then
                                new_policy="on-failure:$max_retries"
                            else
                                echo "⚠️ 无效输入，将使用无限次重试"
                            fi
                        fi
                        ;;
                    3) new_policy="always" ;;
                    4) new_policy="unless-stopped" ;;
                    0) echo "已取消"; pause_return; continue ;;
                    *) echo "⚠️ 无效选择"; pause_return; continue ;;
                esac

                echo ""
                echo "即将对以下 ${#containers[@]} 个容器应用新策略: $new_policy"
                for cn in "${containers[@]}"; do
                    echo "   • $cn"
                done

                read -r -p "确认继续？(Y/N): " confirm
                if [[ -z "$confirm" ]]; then
                    echo "⚠️ 无效选择"
                    pause_return
                    continue
                fi
                if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
                    echo "已取消"
                    pause_return
                    continue
                fi

                local success_count=0
                local fail_count=0
                for cn in "${containers[@]}"; do
                    if docker update --restart="$new_policy" "$cn" >/dev/null 2>&1; then
                        echo "✅ $cn 重启策略已更新为 $new_policy"
                        ((success_count++))
                    else
                        echo "⚠️ $cn 更新失败"
                        ((fail_count++))
                    fi
                done
                echo ""
                echo "✅ 操作完成：成功 $success_count 个，失败 $fail_count 个"
                pause_return
                ;;
            0)
                break
                ;;
            *)
                echo "⚠️ 无效选择"
                pause_return
                ;;
        esac
    done
    return
}

# 13. 导出镜像
export_image() {
    local images_list=$(docker images --format "{{.Repository}}:{{.Tag}}" | grep -v "<none>" | sort)
    if [ -z "$images_list" ]; then
        echo "⚠️ 没有可导出的镜像"
        pause_return
        return
    fi

    clear
    echo "📦 请选择要导出的镜像："
    echo "---------------------------------------------------"
    local i=1
    local img_array=()
    while IFS= read -r img; do
        echo "$i) $img"
        img_array+=("$img")
        ((i++))
    done <<< "$images_list"
    echo "---------------------------------------------------"
    echo "📦 支持单选或多选（用空格分隔，如: 1 或 1 3 5）"
    echo "0) 取消"
    read -r -p "请输入序号: " sel

    if [[ " $sel " == *" 0 "* ]] || [[ "$sel" == "0" ]]; then
        echo "已取消"
        pause_return
        return
    fi

    local selected_indices=()
    for token in $sel; do
        if [[ "$token" =~ ^[0-9]+$ ]] && [ "$token" -ge 1 ] && [ "$token" -le ${#img_array[@]} ]; then
            selected_indices+=("$token")
        fi
    done

    if [ ${#selected_indices[@]} -eq 0 ]; then
        echo "⚠️ 无效选择"
        pause_return
        return
    fi

    local success_count=0
    local fail_count=0
    for idx in "${selected_indices[@]}"; do
        local selected_img="${img_array[$((idx-1))]}"
        local safe_name=$(echo "$selected_img" | tr '/' '_' | tr ':' '_')
        local output_file="/root/${safe_name}.tar"
        echo "📦 正在导出镜像 $selected_img 到 $output_file"
        if docker save -o "$output_file" "$selected_img" 2>/dev/null; then
            echo "✅ 导出完成，文件大小: $(du -h "$output_file" | cut -f1)"
            ((success_count++))
        else
            echo "⚠️ 导出失败: $selected_img"
            ((fail_count++))
        fi
    done
    pause_return
}

# 14. 导入镜像
import_image() {
    shopt -s nullglob
    local tar_files=(/root/*.tar)
    shopt -u nullglob
    if [ ${#tar_files[@]} -eq 0 ]; then
        echo "⚠️ 在 /root 下没有找到 .tar 镜像文件"
        pause_return
        return
    fi

    clear
    echo "📦 请选择要导入的镜像文件："
    echo "---------------------------------------------------"
    local i=1
    for f in "${tar_files[@]}"; do
        echo "$i) $(basename "$f") ($(du -h "$f" | cut -f1))"
        ((i++))
    done
    echo "---------------------------------------------------"
    echo "📦 支持单选或多选（用空格分隔，如: 1 或 1 3 5）"
    echo "0) 取消"
    read -r -p "请输入序号: " sel

    if [[ -z "$sel" ]]; then
        echo "⚠️ 无效选择"
        pause_return
        return
    fi

    if [[ " $sel " == *" 0 "* ]] || [[ "$sel" == "0" ]]; then
        echo "已取消"
        pause_return
        return
    fi

    local selected_indices=()
    for token in $sel; do
        if [[ "$token" =~ ^[0-9]+$ ]] && [ "$token" -ge 1 ] && [ "$token" -le ${#tar_files[@]} ]; then
            selected_indices+=("$token")
        fi
    done

    if [ ${#selected_indices[@]} -eq 0 ]; then
        echo "⚠️ 无效选择"
        pause_return
        return
    fi

    for idx in "${selected_indices[@]}"; do
        local file="${tar_files[$((idx-1))]}"
        echo "📥 正在导入镜像: $(basename "$file")"
        if docker load -i "$file"; then
            echo "✅ 导入完成"
        else
            echo "⚠️ 导入失败: $(basename "$file")"
        fi
    done
    pause_return
}

# -------------------------
# 配置 Docker 镜像加速器
# -------------------------
set_docker_mirror() {
    if ! command -v docker &>/dev/null; then
        echo "⚠️ Docker 未安装，请先安装。"
        pause_return
        return
    fi

    echo "🐳 配置 Docker 镜像加速器(支持单选/多选，用空格分隔)"
    echo "---------------------------------------------------"
    echo "📌 当前配置:"

    if [ -f /etc/docker/daemon.json ]; then
        if command -v jq &>/dev/null; then
            mirrors=$(jq -r '.["registry-mirrors"]? // [] | .[]' /etc/docker/daemon.json 2>/dev/null)

            if [ -n "$mirrors" ]; then
                echo "$mirrors" | sed 's/^/  - /'
            else
                echo "  无"
            fi
        else
            mirrors=$(grep -oP '"registry-mirrors":\s*\[\s*"\K[^"]+' /etc/docker/daemon.json 2>/dev/null)

            if [ -n "$mirrors" ]; then
                echo "$mirrors" | sed 's/^/  - /'
            else
                echo "  无"
            fi
        fi
    else
        echo "  未配置"
    fi

    echo "---------------------------------------------------"
    echo "1) 阿里云（需手动输入专属加速器地址）"
    echo "2) 毫秒 (https://docker.1ms.run)"
    echo "3) 1Panel (https://docker.1panel.live)"
    echo "4) 轩辕 (https://docker.xuanyuan.me)"
    echo "5) 耗子 (https://hub.rat.dev)"
    echo "6) DockerProxy (https://dockerproxy.net)"
    echo "7) DaoCloud (https://docker.m.daocloud.io)"
    echo "8) 科技lion (https://docker.kejilion.pro)"
    echo "9) CNIX (https://docker.m.ixdev.cn)"
    echo "10) 自定义地址"
    echo "0) 取消"

    read -r -p "请选择: " sel

    if [[ -z "$sel" ]]; then
        echo "⚠️ 无效选择"
        pause_return
        return
    fi

    if [[ " $sel " == *" 0 "* ]] || [[ "$sel" == "0" ]]; then
        echo "已取消"
        pause_return
        return
    fi

    local mirror_urls=()
    local tokens=($sel)

    local has_aliyun=false
    local has_custom=false

    for token in "${tokens[@]}"; do
        case $token in

            1)
                if [ "$has_aliyun" = false ]; then

                    echo "🔑 获取阿里云加速器地址：登录 https://cr.console.aliyun.com -> 镜像工具 -> 镜像加速器"
                    read -r -p "请输入加速器地址（如 https://xxxx.mirror.aliyuncs.com）: " aliyun_url

                    if [[ -n "$aliyun_url" ]]; then
                        mirror_urls+=("$aliyun_url")
                        has_aliyun=true
                    else
                        echo "⚠️ 阿里云地址为空，跳过"
                    fi
                else
                    echo "ℹ️ 阿里云已添加，跳过重复"
                fi
                ;;
            2)
                mirror_urls+=("https://docker.1ms.run")
                ;;
            3)
                mirror_urls+=("https://docker.1panel.live")
                ;;
            4)
                mirror_urls+=("https://docker.xuanyuan.me")
                ;;
            5)
                mirror_urls+=("https://hub.rat.dev")
                ;;
            6)
                mirror_urls+=("https://dockerproxy.net")
                ;;
            7)
                mirror_urls+=("https://docker.m.daocloud.io")
                ;;
            8)
                mirror_urls+=("https://docker.kejilion.pro")
                ;;
            9)
                mirror_urls+=("https://docker.m.ixdev.cn")
                ;;
            10)
                if [ "$has_custom" = false ]; then

                    read -r -p "📝 请输入自定义加速器地址（多个用空格分隔）: " custom_input

                    if [[ -n "$custom_input" ]]; then

                        for url in $custom_input; do

                            if [[ "$url" =~ ^https?:// ]]; then
                                mirror_urls+=("$url")
                            else
                                echo "⚠️ 无效地址格式: $url"
                            fi

                        done

                        has_custom=true

                    else
                        echo "⚠️ 未输入自定义地址，跳过"
                    fi

                else
                    echo "ℹ️ 自定义地址已添加过，跳过重复"
                fi
                ;;

            *)
                echo "⚠️ 无效选择"
                ;;

        esac
    done

    if [ ${#mirror_urls[@]} -eq 0 ]; then
        pause_return
        return
    fi

    echo "📦 将配置以下镜像源（共 ${#mirror_urls[@]} 个）："

    for url in "${mirror_urls[@]}"; do
        echo "  - $url"
    done

    mkdir -p /etc/docker

    if command -v jq &>/dev/null; then

        tmp_file=$(mktemp)

        json_array=$(printf '%s\n' "${mirror_urls[@]}" | jq -R . | jq -s .)

        if [ -f /etc/docker/daemon.json ]; then

            jq --argjson new_mirrors "$json_array" \
               '.["registry-mirrors"] = $new_mirrors' \
               /etc/docker/daemon.json > "$tmp_file"

        else

            jq -n --argjson new_mirrors "$json_array" \
               '{ "registry-mirrors": $new_mirrors }' > "$tmp_file"

        fi

        mv "$tmp_file" /etc/docker/daemon.json

    else

        echo "⚠️ 未安装 jq，将直接覆盖 daemon.json"

        json="["
        first=true

        for url in "${mirror_urls[@]}"; do

            if [ "$first" = true ]; then
                first=false
            else
                json+=","
            fi

            json+="\"$url\""

        done

        json+="]"

        cat > /etc/docker/daemon.json <<EOF
{
  "registry-mirrors": $json
}
EOF

    fi

    echo "📝 写入配置完成"
    echo "🔄 重启 Docker 服务..."

    if systemctl restart docker; then
        echo "✅ Docker 重启成功"
    else
        echo "⚠️ Docker 重启失败"
        echo "👉 请检查:"
        echo "   systemctl status docker"
        pause_return
        return
    fi

    echo "💡 当前镜像加速器配置："

    if command -v jq &>/dev/null && [ -f /etc/docker/daemon.json ]; then

        jq -r '.["registry-mirrors"]? // [] | .[]' \
            /etc/docker/daemon.json 2>/dev/null | while read -r line; do
            echo "  - $line"
        done

    else

        grep -oP '"registry-mirrors":\s*\[\s*"\K[^"]+' \
            /etc/docker/daemon.json 2>/dev/null | while read -r line; do
            echo "  - $line"
        done

    fi
    pause_return
}

switch_lang() {
    [ "$EUID" -ne 0 ] && echo "错误：请以 root 权限运行" && return 1
    [ -f /etc/os-release ] && . /etc/os-release || ID="unknown"

    echo "正在快速切换系统语言为 zh_CN.UTF-8..."

    if [[ "$ID" == "debian" || "$ID" == "ubuntu" || "$ID" == "armbian" ]]; then
        
        NEED_INSTALL=false
        ! command -v locale-gen &> /dev/null && NEED_INSTALL=true
        [[ "$ID" == "ubuntu" ]] && ! dpkg -l | grep -q "language-pack-zh-hans" && NEED_INSTALL=true

        if [ "$NEED_INSTALL" = true ]; then
            echo "正在补全语言环境 (仅首次运行需等待)..."
            apt-get update -qq > /dev/null 2>&1 || true
            if [[ "$ID" == "ubuntu" ]]; then
                apt-get install -y locales language-pack-zh-hans -qq > /dev/null 2>&1 || true
            else
                apt-get install -y locales -qq > /dev/null 2>&1 || true
            fi
        fi

        echo "zh_CN.UTF-8 UTF-8" > /etc/locale.gen

        if [[ "$(locale -a 2>/dev/null || true)" != *"zh_CN.utf8"* ]]; then
            echo "正在编译语言环境..."
            /usr/sbin/locale-gen zh_CN.UTF-8 > /dev/null 2>&1 || true
        fi

        cat << 'EOF' > /etc/default/locale
LANG=zh_CN.UTF-8
LANGUAGE=zh_CN:zh
LC_ALL=zh_CN.UTF-8
EOF

        [ -f /etc/dpkg/dpkg.cfg.d/excludes ] && rm -f /etc/dpkg/dpkg.cfg.d/excludes > /dev/null 2>&1

    elif [[ "$ID" == "alpine" ]]; then
        apk add --no-cache musl-locales musl-locales-lang > /dev/null 2>&1
        echo "export LANG=zh_CN.UTF-8" > /etc/profile.d/lang.sh
    fi

    export LANG=zh_CN.UTF-8 > /dev/null 2>&1
    export LC_ALL=zh_CN.UTF-8 > /dev/null 2>&1
    echo "✅ 系统语言切换完成，请重新连接 SSH 生效"
    pause_return
}

install_motd() {
if [ "$EUID" -ne 0 ]; then 
  echo "错误：请以 root 权限运行此脚本"
  return 1
fi

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
        if ! command -v bash >/dev/null 2>&1; then apk add bash 2>/dev/null || true; fi
        ;;
    *)
        true > /etc/motd
        ;;
esac

SSHD_CONFIG="/etc/ssh/sshd_config"
if [ -f "$SSHD_CONFIG" ]; then
    if grep -q '^[#]*\s*PrintMotd' "$SSHD_CONFIG"; then
        sed -i 's/^[#]*\s*PrintMotd.*/PrintMotd no/' "$SSHD_CONFIG" || true
    else
        echo 'PrintMotd no' >> "$SSHD_CONFIG"
    fi
    if grep -q '^[#]*\s*PrintLastLog' "$SSHD_CONFIG"; then
        sed -i 's/^[#]*\s*PrintLastLog.*/PrintLastLog no/' "$SSHD_CONFIG" || true
    else
        echo 'PrintLastLog no' >> "$SSHD_CONFIG"
    fi
    sed -i '/^Banner /d' "$SSHD_CONFIG" || true
fi

for pamfile in /etc/pam.d/sshd /etc/pam.d/login; do
    if [ -f "$pamfile" ]; then
        sed -i 's/^\([^#]*pam_motd\.so\)/#\1/' "$pamfile" || true
    fi
done

for dynamic_motd in /run/motd.dynamic /etc/motd.dynamic /var/run/motd.dynamic; do
    [ -f "$dynamic_motd" ] && true > "$dynamic_motd"
done

[ -d /etc/update-motd.d ] && chmod -x /etc/update-motd.d/* 2>/dev/null

if command -v systemctl >/dev/null 2>&1; then
    systemctl restart ssh 2>/dev/null || systemctl restart sshd 2>/dev/null || true
elif [ -f /etc/init.d/ssh ]; then
    /etc/init.d/ssh restart || true
else
    echo "⚠️ 警告：无法自动重启 SSH 服务，请手动重启"
fi

TARGET_PATH="/etc/profile.d/custom-motd.sh"

cat << 'EOF' > $TARGET_PATH
#!/bin/bash

# 颜色定义
GREEN='\033[1;32m'; CYAN='\033[1;96m'; YELLOW='\033[1;33m'; RED='\033[1;31m'; RESET='\033[0m'

# 容器状态
fmt_docker_status() {
    local status="$1"
    status=$(echo "$status" | sed -E 's/\s*\([^)]*\)//g')
    status=$(echo "$status" | sed -E 's/Up ([0-9]+) seconds?/已运行 \1 秒/')
    status=$(echo "$status" | sed -E 's/Up About a minute/已运行 1 分钟/')
    status=$(echo "$status" | sed -E 's/Up ([0-9]+) minutes?/已运行 \1 分钟/')
    status=$(echo "$status" | sed -E 's/Up About an hour/已运行 1 小时/')
    status=$(echo "$status" | sed -E 's/Up ([0-9]+) hours?/已运行 \1 小时/')
    status=$(echo "$status" | sed -E 's/Up ([0-9]+) days?/已运行 \1 天/')
    status=$(echo "$status" | sed -E 's/Up ([0-9]+) weeks?/已运行 \1 周/')
    status=$(echo "$status" | sed -E 's/Up ([0-9]+) months?/已运行 \1 月/')
    status=$(echo "$status" | sed -E 's/Up ([0-9]+) years?/已运行 \1 年/')
    status=$(echo "$status" | sed -E 's/Exited \(0\)/已停止/')
    status=$(echo "$status" | sed -E 's/Exited \(([0-9]+)\)/已退出(代码 \1)/')
    status=$(echo "$status" | sed -E 's/Exited ([0-9]+) seconds? ago/已停止 \1 秒/')
    status=$(echo "$status" | sed -E 's/Exited About a minute ago/已停止 1 分钟/')
    status=$(echo "$status" | sed -E 's/Exited ([0-9]+) minutes? ago/已停止 \1 分钟/')
    status=$(echo "$status" | sed -E 's/Exited About an hour ago/已停止 1 小时/')
    status=$(echo "$status" | sed -E 's/Exited ([0-9]+) hours? ago/已停止 \1 小时/')
    status=$(echo "$status" | sed -E 's/Exited ([0-9]+) days? ago/已停止 \1 天/')
    status=$(echo "$status" | sed -E 's/Exited ([0-9]+) weeks? ago/已停止 \1 周/')
    status=$(echo "$status" | sed -E 's/Exited ([0-9]+) months? ago/已停止 \1 月/')
    status=$(echo "$status" | sed -E 's/Exited ([0-9]+) years? ago/已停止 \1 年/')
    status=$(echo "$status" | sed -E 's/Created/已创建/')
    if [[ "$status" =~ ^Restarting ]]; then
        status=$(echo "$status" | sed -E 's/Restarting/重启中/')
        status=$(echo "$status" | sed -E 's/ seconds? ago/秒前/')
        status=$(echo "$status" | sed -E 's/ minutes? ago/分钟前/')
        status=$(echo "$status" | sed -E 's/ hours? ago/小时前/')
        status=$(echo "$status" | sed -E 's/ days? ago/天前/')
        status=$(echo "$status" | sed -E 's/ weeks? ago/周前/')
        status=$(echo "$status" | sed -E 's/ months? ago/月前/')
        status=$(echo "$status" | sed -E 's/ years? ago/年前/')
    fi
    echo "$status"
}

# 基础信息采集
USER_NAME=$(whoami)
HOSTNAME=$(hostname)
OS_VER=$(grep "PRETTY_NAME" /etc/os-release | cut -d '"' -f2)
KERNEL_VER=$(uname -r)
ISP_INFO=$(curl -s ipinfo.io/org)
TCP_TOTAL=$(ss -ant --no-header | wc -l)
UDP_SOCKETS=$(ss -uan | tail -n +2 | wc -l)
TOTAL_PROCESSES=$(ps -e --no-headers | wc -l)
USER_PROCESSES=$(ps -u "$USER" --no-headers | wc -l)
LOAD_AVG=$(awk '{printf "1m:%s 5m:%s 15m:%s", $1, $2, $3}' /proc/loadavg)

# 获取公网 IPv4 和 IPv6
IPV4_ADDRESS=$(curl -s -m 2 ipv4.ip.sb)
IPV6_ADDRESS=$(curl -s -m 2 ipv6.ip.sb)

# 获取默认路由对应的网卡
iface=$(ip route show default 2>/dev/null | awk '{print $5}' | head -n1)
if [ -z "$iface" ]; then
    iface=$(ip -br link 2>/dev/null | grep -v LOOPBACK | awk '{print $1}' | head -n1)
fi

if [ -n "$iface" ]; then
    output=$(awk -v iface="$iface" '$1 == iface":" {rx=$2; tx=$10} END {
        units[0]="B"; units[1]="KB"; units[2]="MB"; units[3]="GB";
        rxi=0; rxv=rx; while(rxv>=1024 && rxi<3){rxv/=1024; rxi++}
        txi=0; txv=tx; while(txv>=1024 && txi<3){txv/=1024; txi++}
        printf("⬇ 总接收: %.2f %s\n⬆ 总发送: %.2f %s\n", rxv, units[rxi], txv, units[txi])
    }' /proc/net/dev)
else
    output="⚠️ 未检测到网络接口"
fi

# 时间与星期
CURRENT_DATE=$(date '+%Y-%m-%d %H:%M:%S')
WEEKDAY_NUM=$(date '+%u')
case "$WEEKDAY_NUM" in
  1) WEEKDAY="星期一" ;; 2) WEEKDAY="星期二" ;; 3) WEEKDAY="星期三" ;;
  4) WEEKDAY="星期四" ;; 5) WEEKDAY="星期五" ;; 6) WEEKDAY="星期六" ;;
  7) WEEKDAY="星期日" ;; *) WEEKDAY="未知" ;;
esac

# CPU 内存与磁盘
MEM_INFO=$(free -m | awk '/^Mem:|^内存：/{total=$2; used=$2-$4-$6; printf "%dM / %.2fG (%.2f%%)", used, total/1024, used*100/total}')
DISK_INFO=$(df -h / | awk 'NR==2 {gsub(/G/,"",$3); gsub(/G/,"",$2); gsub(/%/,"",$5); printf "%.2fG / %.2fG (%.1f%%)", $3, $2, $5}')
DISK_PERCENT=$(df / | awk 'NR==2 {print $5}' | sed 's/%//')
UPTIME=$(cat /proc/uptime | awk -F. '{run_days=int($1 / 86400);run_hours=int(($1 % 86400) / 3600);run_minutes=int(($1 % 3600) / 60); if (run_days > 0) printf("%d天 ", run_days); if (run_hours > 0) printf("%d时 ", run_hours); printf("%d分\n", run_minutes)}')
LAST_UPDATE=$(stat -c %y /var/log/apt/history.log 2>/dev/null | cut -d '.' -f1 || echo "Unknown")
CPU_USAGE=$(LANG=C top -bn1 | awk -F',' '/Cpu\(s\)/ {for(i=1;i<=NF;i++){if($i ~ /id/){gsub(/[^0-9.]/,"",$i); idle=$i}} printf "%.2f%%", 100 - idle}')

# Docker 详细状态与容器分类
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
    D_STATUS="⚠️ Docker 未安装"
    DOCKER_VER="未安装"
    COMPOSE_VER="未安装"
fi

# 输出界面
echo -e "${GREEN}👋 欢迎回来, ${USER_NAME}!${RESET}"
echo -e "${CYAN}------------------------------------------------------------${RESET}"
echo -e "⏰ 当前时间:${RESET}    ${CYAN}${CURRENT_DATE} (${WEEKDAY})${RESET}"
echo -e "⌛ 运行时间:${RESET}    ${CYAN}${UPTIME}${RESET}"
echo -e "🧠 CPU 使用:${RESET}    ${CYAN}${CPU_USAGE} ($(nproc)核)${RESET}"
echo -e "📊 系统负载:${RESET}    ${CYAN}${LOAD_AVG}${RESET}"
echo -e "💾 内存使用:${RESET}    ${CYAN}${MEM_INFO}${RESET}"
echo -e "🗂 磁盘使用:${RESET}    ${CYAN}${DISK_INFO}${RESET}"
echo -e "🔄 系统更新:${RESET}    ${CYAN}${LAST_UPDATE}${RESET}"
echo -e "🖥 系统版本:${RESET}    ${CYAN}${OS_VER}${RESET}"
echo -e "🖥 Linux版本:${RESET}   ${CYAN}${KERNEL_VER}${RESET}"
echo -e "🐳 Docker 版本:${RESET}    ${CYAN}${DOCKER_VER}${RESET}"
echo -e "🔧 Compose 版本:${RESET}   ${CYAN}${COMPOSE_VER}${RESET}"
echo -e "🌍 IPv4地址:${RESET}   ${CYAN}${IPV4_ADDRESS:-无}${RESET}"
echo -e "🌐 IPv6地址:${RESET}   ${CYAN}${IPV6_ADDRESS:-无}${RESET}"
echo -e "🏷️ 主机名:${RESET}   ${CYAN}${HOSTNAME}${RESET}"
echo -e "📡 运营商:${RESET}   ${CYAN}${ISP_INFO}${RESET}"
echo -e "🔌 TCP连接数:${RESET}   ${CYAN}${TCP_TOTAL}${RESET}"
echo -e "📬 UDP套接字:${RESET}   ${CYAN}${UDP_SOCKETS}${RESET}"
echo -e "⚙️ 总进程数:${RESET}    ${CYAN}${TOTAL_PROCESSES}${RESET}"
echo -e "👤 用户进程:${RESET}    ${CYAN}${USER_PROCESSES}${RESET}"
echo -e "$output${RESET}"
echo -e "${CYAN}------------------------------------------------------------${RESET}"

# Docker 统计
echo -e "\n${YELLOW}🐳 Docker 状态:${RESET}   ${D_STATUS}"
if [ -n "$RUNNING_APPS" ]; then
    docker ps --format "{{.Names}}\t{{.Status}}" | while IFS=$'\t' read -r name uptime; do
        chinese_status=$(fmt_docker_status "$uptime")
        echo -e "${GREEN}✅ $name 运行中 (${chinese_status})${RESET}"
    done
fi
if [ -n "$EXITED_APPS" ]; then
    for app in $EXITED_APPS; do
        exited_info=$(docker ps -a --filter "name=^/${app}$" --format "{{.Status}}")
        chinese_exited=$(fmt_docker_status "$exited_info")
        echo -e "${RED}⚠️ $app 未运行 (${chinese_exited})${RESET}"
    done
fi

# 最近登录记录
echo -e "\n${YELLOW}🛡 最近登录记录:${RESET}"
if command -v journalctl >/dev/null 2>&1; then
    logs=$(journalctl -u ssh --no-pager -n 50 2>/dev/null | grep "Accepted" | tail -n 3 | tac)
    if [ -n "$logs" ]; then
        echo "$logs" | while read line; do
            month_raw=$(echo "$line" | awk '{print $1}')
            day=$(echo "$line" | awk '{print $2}')
            time=$(echo "$line" | awk '{print $3}')
            user=$(echo "$line" | sed -n 's/.*for \([^ ]*\) from .*/\1/p')
            ip=$(echo "$line" | sed -n 's/.*from \([0-9.]*\).*/\1/p')
            [ -z "$ip" ] && ip=$(echo "$line" | sed -n 's/.*from \([a-f0-9:]*\).*/\1/p')

            case $month_raw in
                1月|Jan) month_num=1 ;; 2月|Feb) month_num=2 ;; 3月|Mar) month_num=3 ;;
                4月|Apr) month_num=4 ;; 5月|May) month_num=5 ;; 6月|Jun) month_num=6 ;;
                7月|Jul) month_num=7 ;; 8月|Aug) month_num=8 ;; 9月|Sep) month_num=9 ;;
                10月|Oct) month_num=10 ;; 11月|Nov) month_num=11 ;; 12月|Dec) month_num=12 ;;
                *) month_num=1 ;;
            esac

            year=$(date +%Y)
            wd=$(date -d "$year-$month_num-$day" +%A 2>/dev/null)
            if [ -n "$wd" ]; then
                printf "  %-8s %-15s  %s %s %s %s\n" "$user" "$ip" "$wd" "$month_raw" "$day" "$time"
            fi
        done
    else
        echo "  未找到 SSH 登录记录"
    fi
else
    echo "  journalctl 不可用"
fi

# 磁盘告警
if [ "$DISK_PERCENT" -ge 70 ]; then
    echo -e "\n${RED}💔 警告：磁盘使用率已达到 ${DISK_PERCENT}% ，请及时清理！${RESET}"
fi
echo ""
EOF

# 设置权限
chmod +x $TARGET_PATH
echo "✅ 安装成功！请重新连接 SSH 终端查看效果。"
    pause_return
}

# -------------------------
# 服务子菜单
# -------------------------
service_menu() {
    local service=$1
    local name=$2

    while true; do
        clear
        echo "===== $name 管理 ====="
        echo "1) 安装 $name"
        echo "2) 更新 $name"
        echo "3) 卸载 $name"
        echo "0) 返回主菜单"
        read -r -p "请选择: " opt

        case $opt in
            1)
                case $service in
                    npm) install_npm || true ;;
                    portainer) install_portainer || true ;;
                    lucky) install_lucky || true ;;
                    panel) install_1panel || true ;;
                esac
                pause_return
                ;;
            2)
                case $service in
                    npm) update_docker_service "npm" "Nginx Proxy Manager" "npm" || true ;;
                    portainer) update_docker_service "portainer" "Portainer" "portainer" || true ;;
                    lucky) update_docker_service "lucky" "Lucky" "lucky" || true ;;
                    panel) update_1panel || true ;;
                esac
                pause_return
                ;;
            3)
                case $service in
                    npm) uninstall_docker_service "npm" "Nginx Proxy Manager" "npm" "chishin/nginx-proxy-manager-zh:release" || true ;;
                    portainer) uninstall_docker_service "portainer" "Portainer" "portainer" "6053537/portainer-ce:latest" || true ;;
                    lucky) uninstall_docker_service "lucky" "Lucky" "lucky" "gdy666/lucky:v3" || true ;;
                    panel) uninstall_1panel || true ;;
                esac
                pause_return
                ;;
            0)
                break
                ;;
            *)
                echo "⚠️ 无效选择"
                pause_return
                ;;
        esac
    done
}

# ===================== Caddy 管理功能 =====================
install_caddy() {
    echo "🚀 正在安装 Caddy Web 服务器..."
    
    ARCH=$(uname -m)
    case "$ARCH" in
        x86_64)  ARCH="amd64" ;;
        aarch64) ARCH="arm64" ;;
        armv7l)  ARCH="armv7" ;;
        *)       echo "⚠️ 不支持的架构: $ARCH"; return ;;
    esac

    LATEST_VERSION=$(curl -s https://api.github.com/repos/caddyserver/caddy/releases/latest | jq -r .tag_name || true)
    if [ -z "$LATEST_VERSION" ] || [ "$LATEST_VERSION" = "null" ]; then
        echo "⚠️ 获取最新版本失败，使用默认版本 v2.11.2"
        LATEST_VERSION="v2.11.2"
    fi
    VERSION=${LATEST_VERSION#v}
    DOWNLOAD_URL="https://github.com/caddyserver/caddy/releases/download/${LATEST_VERSION}/caddy_${VERSION}_linux_${ARCH}.tar.gz"

    echo "📥 下载 Caddy ${LATEST_VERSION} for ${ARCH} ..."
    TMP_DIR=$(mktemp -d)
    cd "$TMP_DIR" || return 1
    curl -fsSL "$DOWNLOAD_URL" -o caddy.tar.gz || { echo "⚠️ 下载失败"; cd - >/dev/null || true; rm -rf "$TMP_DIR"; return; }
    tar -xzf caddy.tar.gz
    chmod +x caddy
    mv caddy /usr/local/bin/caddy
    cd - >/dev/null || true
    rm -rf "$TMP_DIR"

    mkdir -p /etc/caddy /var/lib/caddy /var/log/caddy
    if ! id "caddy" &>/dev/null; then
        useradd -r -d /var/lib/caddy -s /usr/sbin/nologin caddy || true
    fi
    chown -R caddy:caddy /etc/caddy /var/lib/caddy /var/log/caddy || true

    cat > /etc/systemd/system/caddy.service << 'EOF'
[Unit]
Description=Caddy Web Server
Documentation=https://caddyserver.com/docs/
After=network.target

[Service]
User=caddy
Group=caddy
ExecStart=/usr/local/bin/caddy run --config /etc/caddy/Caddyfile
ExecReload=/usr/local/bin/caddy reload --config /etc/caddy/Caddyfile
TimeoutStopSec=5s
LimitNOFILE=1048576
LimitNPROC=512
PrivateTmp=true
ProtectSystem=full
AmbientCapabilities=CAP_NET_BIND_SERVICE

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable caddy

    if [ ! -f /etc/caddy/Caddyfile ]; then
        cat > /etc/caddy/Caddyfile << 'EOF'
# 默认 Caddyfile 示例
# 请将 example.com 替换为你的域名或 IP
:80 {
    respond "Caddy 已正常运行！"
}
EOF
    fi

    echo "✅ Caddy 安装完成"
    echo "📁 配置文件位置: /etc/caddy/Caddyfile"
    echo "📂 数据目录: /var/lib/caddy"
    echo "📄 日志目录: /var/log/caddy"
    echo "🔧 如需启动服务，请执行: systemctl start caddy"
}

update_caddy() {
    echo "🔄 正在更新 Caddy..."
    if ! command -v caddy &>/dev/null; then
        echo "⚠️ Caddy 未安装，请先安装"
        return
    fi
    systemctl stop caddy 2>/dev/null || true
    install_caddy
    systemctl start caddy 2>/dev/null || true
    echo "✅ Caddy 更新完成"
}

uninstall_caddy() {
    if ! command -v caddy &>/dev/null; then
        echo "⚠️ Caddy 未安装，请先安装"
        return
    fi

    echo "⚠️ 即将卸载 Caddy"
    read -r -p "确认卸载？(Y/N): " confirm
    [[ ! "$confirm" =~ ^[Yy]$ ]] && echo "已取消" && return

    systemctl stop caddy 2>/dev/null || true
    systemctl disable caddy 2>/dev/null || true
    rm -f /etc/systemd/system/caddy.service
    systemctl daemon-reload || true

    rm -f /usr/local/bin/caddy

    read -r -p "是否删除配置、数据及日志文件？(Y/N): " del_data
    if [[ "$del_data" =~ ^[Yy]$ ]]; then
        rm -rf /etc/caddy /var/lib/caddy /var/log/caddy
        echo "✅ 已删除数据目录"
    else
        echo "保留数据目录: /etc/caddy, /var/lib/caddy, /var/log/caddy"
    fi

    if id "caddy" &>/dev/null; then
        userdel caddy 2>/dev/null || true
    fi

    echo "✅ Caddy 已卸载"
}

configure_caddy() {
    if ! command -v caddy &>/dev/null; then
        echo "⚠️ Caddy 未安装，请先安装"
        return
    fi
    echo "📝 编辑 Caddy 配置文件..."
    if ! ensure_nano_installed; then
        echo "nano 编辑器安装失败，将使用 vi"
        EDITOR=vi
    else
        EDITOR=nano
    fi
    $EDITOR /etc/caddy/Caddyfile || true
    echo "✅ 配置已保存"
    echo "💡 重新加载配置: systemctl reload caddy 或 caddy reload --config /etc/caddy/Caddyfile"
}

start_caddy() {
    if ! command -v caddy &>/dev/null; then
        echo "⚠️ Caddy 未安装，请先安装"
        return
    fi
    if systemctl start caddy 2>/dev/null; then
        echo "✅ Caddy 已启动"
    else
        echo "⚠️ 启动失败，请检查配置和日志"
    fi
}

stop_caddy() {
    if ! command -v caddy &>/dev/null; then
        echo "⚠️ Caddy 未安装，请先安装"
        return
    fi
    if systemctl stop caddy 2>/dev/null; then
        echo "✅ Caddy 已停止"
    else
        echo "⚠️ 停止失败（服务可能未运行）"
    fi
}

restart_caddy() {
    if ! command -v caddy &>/dev/null; then
        echo "⚠️ Caddy 未安装，请先安装"
        return
    fi
    if systemctl restart caddy 2>/dev/null; then
        echo "✅ Caddy 已重启"
    else
        echo "⚠️ 重启失败，请检查配置和日志"
    fi
}

status_caddy() {
    if ! command -v caddy &>/dev/null; then
        echo "⚠️ Caddy 未安装，请先安装"
        return
    fi
    if systemctl status caddy --no-pager 2>/dev/null; then
        systemctl status caddy --no-pager
    else
        echo "⚠️ Caddy 服务未安装或未运行"
    fi
}

caddy_menu() {
    while true; do
        clear
        echo "===== Caddy Web 服务器管理 ====="
        echo "1) 安装 Caddy"
        echo "2) 更新 Caddy"
        echo "3) 卸载 Caddy"
        echo "4) 配置 Caddy"
        echo "5) 启动 Caddy"
        echo "6) 停止 Caddy"
        echo "7) 重启 Caddy"
        echo "8) 查看 Caddy 状态"
        echo "0) 返回主菜单"
        read -r -p "请选择: " opt

        case $opt in
            1) install_caddy || true ;;
            2) update_caddy || true ;;
            3) uninstall_caddy || true ;;
            4) configure_caddy || true ;;
            5) start_caddy || true ;;
            6) stop_caddy || true ;;
            7) restart_caddy || true ;;
            8) status_caddy || true ;;
            0) break ;;
            *) echo "⚠️ 无效选择" ;;
        esac
        pause_return
    done
}

# -------------------------
# 主菜单
# -------------------------
enter_toolbox_runtime
trap 'leave_toolbox_runtime' EXIT INT TERM

while true; do
    clear
    echo "---------------------------------------------------" >&2
    echo "🐳 Docker 工具箱 v1.3.6  by：万物皆可盘"
    echo "bash <(curl -sL https://url.wuyang.skin/Docker)"
    echo "---------------------------------------------------" >&2
    echo "1) 安装 Docker & Compose"
    echo "2) 更新 Docker & Compose"
    echo "3) 管理 Docker & Compose"
    echo "4) 卸载 Docker & Compose"
    echo "5) 管理 Nginx Proxy Manager"
    echo "6) 管理 Portainer"
    echo "7) 管理 Lucky"
    echo "8) 管理 1Panel"
    echo "9) 管理 Caddy"
    echo "10) 停止所有 Docker 容器"
    echo "11) 重启所有 Docker 容器"
    echo "12) 清理 Docker 系统垃圾"
    echo "13) 修复 Docker 网络"
    echo "14) 自愈 Docker"
    echo "15) 端口管理"
    echo "16) 容器管理"
    echo "17) 镜像加速"
    echo "18) 切换系统语言 (zh_CN.UTF-8)"
    echo "19) 安装 SSH 登录面板 (MOTD)"
    echo "0) 退出"
    read -r -p "请选择: " choice
    case $choice in
        1) install_docker || true; show_versions; pause_return ;;
        2) update_docker || true; pause_return ;;
        3) manage_compose || true ;;
        4) uninstall_docker || true; pause_return ;;
        5) service_menu npm "Nginx Proxy Manager" || true ;;
        6) service_menu portainer "Portainer" || true ;;
        7) service_menu lucky "Lucky" || true ;;
        8) service_menu panel "1Panel" || true ;;
        9) caddy_menu || true ;;
        10) stop_all_containers || true ;;
        11) restart_all_containers || true ;;
        12) cleanup_system || true ;;
        13) fix_network || true ;;
        14) self_heal || true ;;
        15) open_ports || true ;;
        16) container_tools_menu || true ;;
        17) set_docker_mirror || true ;;
        18) switch_lang || true ;;
        19) install_motd || true ;;
        0) exit 0 ;;
        *) echo "⚠️ 无效选择"; pause_return ;;
    esac
done
