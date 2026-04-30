#!/bin/bash
# 🐳 Docker 工具箱 v1.3.5  by：万物皆可盘

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

    # 根据服务类型确定用于查找的镜像关键字
    local image_keyword=""
    case "$service" in
        npm)       image_keyword="nginx-proxy-manager" ;;
        portainer) image_keyword="portainer" ;;
        lucky)     image_keyword="lucky" ;;
        *)         image_keyword="" ;;
    esac

    # 1. 查找现有容器（不限名称，通过镜像名关键字匹配）
    local actual_container=""
    if [ -n "$image_keyword" ]; then
        # 遍历所有容器，找到镜像名包含关键字的第一个容器
        actual_container=$(docker ps -a --format "{{.Names}} {{.Image}}" | grep -i "$image_keyword" | head -n1 | awk '{print $1}' || true)
    fi

    # 如果没找到，尝试通过配置文件或默认名称
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

    # 2. 获取镜像和数据目录
    local IMAGE DATA_DIR
    IMAGE=$(get_container_image "$actual_container")
    DATA_DIR=$(infer_data_dir_from_container "$service" "$actual_container")

    # 二次修正（避免 /root 误判）
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

    # 保存配置（使用标准名称）
    save_service_config "$service" "$IMAGE" "$DATA_DIR" ""

    # 3. 停止并删除旧容器
    if container_exists "$actual_container"; then
        echo "📌 停止并删除旧容器: $actual_container"
        docker stop "$actual_container" >/dev/null 2>&1 || true
        docker rm "$actual_container" >/dev/null 2>&1 || true
    fi

    # 4. 拉取新镜像
    echo "📥 拉取最新镜像: $IMAGE"
    docker pull "$IMAGE" || {
        echo "⚠️ 镜像拉取失败"
        return 1
    }

    # 5. 使用标准名称重新创建容器
    echo "🚀 重新创建容器（名称: $default_name）..."
    local run_cmd
    run_cmd=$(build_service_run_cmd "$service" "$IMAGE" "$default_name" "$DATA_DIR")
    eval "$run_cmd"

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

    # 查找实际容器
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
                "https://download.daocloud.io/docker-ce/linux/$OS"
                "https://mirrors.163.com/docker-ce/linux/$OS"
                "https://mirrors.cloud.tencent.com/docker-ce/linux/$OS"
            )
            ;;
        armbian)
            SOURCES=(
                "https://download.docker.com/linux/debian"
                "https://mirrors.aliyun.com/docker-ce/linux/debian"
                "https://download.daocloud.io/docker-ce/linux/debian"
                "https://mirrors.163.com/docker-ce/linux/debian"
                "https://mirrors.cloud.tencent.com/docker-ce/linux/debian"
            )
            ;;
        centos|rocky|rhel)
            SOURCES=(
                "https://download.docker.com/linux/centos"
                "https://mirrors.aliyun.com/docker-ce/linux/centos"
                "https://download.daocloud.io/docker-ce/linux/centos"
                "https://mirrors.163.com/docker-ce/linux/centos"
                "https://mirrors.cloud.tencent.com/docker-ce/linux/centos"
            )
            ;;
        fedora)
            SOURCES=(
                "https://download.docker.com/linux/fedora"
                "https://mirrors.aliyun.com/docker-ce/linux/fedora"
                "https://download.daocloud.io/docker-ce/linux/fedora"
                "https://mirrors.163.com/docker-ce/linux/fedora"
                "https://mirrors.cloud.tencent.com/docker-ce/linux/fedora"
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
        sysctl --system >/dev/null 2>&1
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
    sed -i '/^\*\s\+soft\s\+nofile/d' /etc/security/limits.conf
    sed -i '/^\*\s\+hard\s\+nofile/d' /etc/security/limits.conf
    echo "* soft nofile 524288" >> /etc/security/limits.conf
    echo "* hard nofile 524288" >> /etc/security/limits.conf
    sed -i '/DefaultLimitNOFILE/d' /etc/systemd/system.conf
    sed -i '/DefaultLimitNOFILE/d' /etc/systemd/user.conf
    echo "DefaultLimitNOFILE=524288" >> /etc/systemd/system.conf
    echo "DefaultLimitNOFILE=524288" >> /etc/systemd/user.conf
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
        apt update
        echo "📦 正在升级系统软件包..."
        apt upgrade -y -qq 2>/dev/null || apt upgrade -y
        apt install -y ca-certificates curl gnupg lsb-release
        mkdir -p /etc/apt/keyrings

        local success=0
        for src in "${SOURCES[@]}"; do
            echo "🔍 尝试使用源: $src"
            # 清理可能残留的旧配置
            rm -f /etc/apt/keyrings/docker.gpg
            rm -f /etc/apt/sources.list.d/docker.list

            # 下载 GPG 密钥
            if curl -fsSL "$src/gpg" -o /tmp/docker.gpg 2>/dev/null; then
                gpg --dearmor -o /etc/apt/keyrings/docker.gpg < /tmp/docker.gpg 2>/dev/null
                rm -f /tmp/docker.gpg
                # 添加 apt 源
                local codename
                codename=$(lsb_release -cs)
                echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] $src $codename stable" > /etc/apt/sources.list.d/docker.list
                # 更新并尝试安装
                if apt update 2>/dev/null && DEBIAN_FRONTEND=noninteractive apt install -y -qq docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin >/dev/null 2>&1; then
                    echo "✅ 成功从源 $src 安装 Docker"
                    success=1
                    break
                else
                    echo "⚠️ 源 $src 安装失败，尝试下一个"
                fi
            else
                echo "⚠️ 源 $src GPG 密钥下载失败，尝试下一个"
            fi
        done

        if [ $success -eq 0 ]; then
            echo "⚠️ 所有 Docker 源均不可用，请检查网络"
            return 1
        fi
    fi

    # ---------- CentOS / Rocky / RHEL / Fedora ----------
    if [[ "$OS" =~ ^(centos|rocky|rhel|fedora)$ ]]; then
        echo "📦 正在升级系统软件包..."
        if command -v dnf >/dev/null 2>&1; then
            dnf upgrade -y
            dnf -y install dnf-plugins-core
        else
            yum update -y
            yum -y install yum-utils
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

    # 启动 Docker 服务
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
            echo "✅ 系统及 Docker 更新完成"
            show_versions
            return 0
            ;;
        suse)
            echo "📦 使用 zypper 更新系统及 Docker..."
            zypper refresh
            zypper update -y
            systemctl restart docker 2>/dev/null || true
            echo "✅ 系统及 Docker 更新完成"
            show_versions
            return 0
            ;;
        alpine)
            echo "📦 使用 apk 更新系统及 Docker..."
            apk update && apk upgrade
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
            echo "deb [arch=$(dpkg --print-architecture)] $src $codename stable" > /etc/apt/sources.list.d/docker.list

            if apt update 2>/dev/null; then
                echo "📦 正在升级所有系统软件包（包括 Docker）..."
                if DEBIAN_FRONTEND=noninteractive apt upgrade -y -qq 2>/dev/null; then
                    echo "✅ 成功从源 $src 更新系统及 Docker"
                    success=1
                    break
                else
                    echo "⚠️ 源 $src 升级失败，尝试下一个"
                fi
            else
                echo "⚠️ 源 $src apt update 失败，尝试下一个"
            fi
        done

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
                        echo "✅ 成功从源 $src 更新系统及 Docker"
                        success=1
                        break
                    else
                        echo "⚠️ 源 $src dnf 升级失败，尝试下一个"
                    fi
                else
                    if yum update -y; then
                        echo "✅ 成功从源 $src 更新系统及 Docker"
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
            rm -rf /var/lib/docker /var/lib/containerd /etc/apt/sources.list.d/docker.list /etc/apt/keyrings/docker.gpg
            apt autoremove -y || true
            ;;
        centos|rocky|fedora|rhel)
            if command -v dnf >/dev/null 2>&1; then
                dnf remove -y docker-ce docker-ce-cli containerd.io docker-compose-plugin || true
            else
                yum remove -y docker-ce docker-ce-cli containerd.io docker-compose-plugin || true
            fi
            rm -rf /var/lib/docker /var/lib/containerd
            ;;
        arch)
            pacman -Rns --noconfirm docker docker-compose || true
            rm -rf /var/lib/docker /var/lib/containerd
            ;;
        suse)
            zypper remove -y docker docker-compose || true
            rm -rf /var/lib/docker /var/lib/containerd
            ;;
        alpine)
            apk del docker docker-compose || true
            rm -rf /var/lib/docker /var/lib/containerd
            ;;
        *)
            echo "⚠️ 不支持的系统"
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
    mkdir -p "$npm_data" "$npm_letsencrypt"

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

    eval "$run_cmd"
    save_service_config "npm" "$image" "$npm_base" "-p 80:80 -p 81:81 -p 443:443 -v ${npm_base}/data:/data -v ${npm_base}/letsencrypt:/etc/letsencrypt"
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
    mkdir -p "$portainer_dir"

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

    eval "$run_cmd"
    save_service_config "portainer" "$image" "$portainer_dir" "-p 9000:9000 -v ${portainer_dir}:/data -v /var/run/docker.sock:/var/run/docker.sock"
    echo "✅ Portainer 安装完成，访问 http://IP:9000"
}

install_lucky() {
    echo "📂 配置 Lucky 数据目录"
    read -r -p "请输入宿主机数据目录（回车退出安装）: " lucky_dir
    [ -z "$lucky_dir" ] && echo "⚠️ 退出安装" && return
    mkdir -p "$lucky_dir"

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

    eval "$run_cmd"
    save_service_config "lucky" "$image" "$lucky_dir" "--network host -v ${lucky_dir}:/app/conf -v /var/run/docker.sock:/var/run/docker.sock"
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
            apt update
            apt install -y "${missing[@]}"
            ;;
        centos|rocky|fedora|rhel)
            if command -v dnf >/dev/null 2>&1; then
                dnf install -y epel-release 2>/dev/null || true
                dnf install -y "${missing[@]}"
            else
                yum install -y epel-release 2>/dev/null || true
                yum install -y "${missing[@]}"
            fi
            ;;
        arch)
            pacman -Sy --noconfirm "${missing[@]}"
            ;;
        suse)
            zypper refresh
            zypper install -y "${missing[@]}"
            ;;
        alpine)
            apk add --no-cache "${missing[@]}"
            ;;
        *)
            echo "⚠️ 无法自动安装依赖，请手动安装: ${missing[*]}"
            return 1
            ;;
    esac
    echo "✅ 依赖安装完成"
}

# 检查并拉取 runlike 镜像
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
        
        if [[ "$status" == Up* ]]; then
        status="🟢 运行中"
    elif [[ "$status" == Exited* ]]; then
        status="🔴 已停止"
    elif [[ "$status" == Created* ]]; then
        status="${status/Created/已创建}"
        status="${status//seconds ago/秒前}"
        status="${status//minutes ago/分钟前}"
        status="${status//hours ago/小时前}"
        status="${status//days ago/天前}"
        status="${status//weeks ago/周前}"
        status="${status//months ago/月前}"
        status="${status//years ago/年前}"
        status="🟡 $status"
    elif [[ "$status" == Restarting* ]]; then
        status="${status/Restarting/重启中}"
        status="${status//seconds ago/秒前}"
        status="${status//minutes ago/分钟前}"
        status="${status//hours ago/小时前}"
        status="${status//days ago/天前}"
        status="${status//weeks ago/周前}"
        status="${status//months ago/月前}"
        status="${status//years ago/年前}"
        status="🟡 $status"
    elif [[ "$status" == Paused* ]]; then
        status="🟡 已暂停"
    elif [[ "$status" == Dead* ]]; then
        status="🟡 已死亡"
    else
        status="🟡 $status"
    fi

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
        [[ "$sel" == "0" ]] && return 1

        local selected=()
        local n
        for n in $sel; do
            if [[ "$n" =~ ^[0-9]+$ ]] && [ "$n" -ge 1 ] && [ "$n" -le ${#names[@]} ]; then
                selected+=("${names[$((n-1))]}")
            fi
        done

        if [ ${#selected[@]} -eq 0 ]; then
            echo "⚠️ 未选择有效容器" >&2
            return 1
        fi

        echo "${selected[@]}"
        return 0
    else
        if [[ ! "$sel" =~ ^[0-9]+$ ]] || [ "$sel" -eq 0 ] || [ "$sel" -gt ${#names[@]} ]; then
            echo "已取消" >&2
            return 1
        fi

        echo "${names[$((sel-1))]}"
        return 0
    fi
}

# -------------------------
# 新备份核心函数：打包数据卷 + 生成启动脚本
# 参数：容器名称数组，输出zip文件名（不含路径），返回zip文件完整路径
# -------------------------
backup_containers_core() {
    local -n containers_ref=$1
    local zip_filename="$2"
    local temp_dir
    temp_dir=$(mktemp -d)
    local success=0

    # 确保 runlike 可用
    check_runlike || return 1

    local data_tar="docker_data.tar.gz"
    local start_script="docker_run.sh"

    # 收集所有数据卷绝对路径（去重）
    local volume_paths_file="${temp_dir}/volume_paths.txt"
    > "$volume_paths_file"

    # 生成启动脚本头
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

        # 记录数据卷路径
        docker inspect "$container" --format '{{range .Mounts}}{{.Source}}{{"\n"}}{{end}}' >> "$volume_paths_file"

        # 生成 runlike 命令，并清理 hostname/mac-address
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

    # 去重数据卷路径
    sort -u "$volume_paths_file" -o "$volume_paths_file"

    # 打包数据卷
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
        # 将启动脚本和数据包打包成 zip
        cd "$temp_dir" || { success=1; cd - >/dev/null; }
        if [ $success -eq 0 ]; then
            zip -r -9 "/root/${zip_filename}" . >/dev/null
            if [ $? -eq 0 ]; then
                echo "✅ 备份文件已创建: /root/${zip_filename}"
            else
                echo "⚠️ 创建 zip 文件失败" >&2
                success=1
            fi
        fi
        cd - >/dev/null
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

    # 获取所有容器（包括停止的）
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

        if [[ "$status" == Up* ]]; then
        status="🟢 运行中"
    elif [[ "$status" == Exited* ]]; then
        status="🔴 已停止"
    elif [[ "$status" == Created* ]]; then
        status="${status/Created/已创建}"
        status="${status//seconds ago/秒前}"
        status="${status//minutes ago/分钟前}"
        status="${status//hours ago/小时前}"
        status="${status//days ago/天前}"
        status="${status//weeks ago/周前}"
        status="${status//months ago/月前}"
        status="${status//years ago/年前}"
        status="🟡 $status"
    elif [[ "$status" == Restarting* ]]; then
        status="${status/Restarting/重启中}"
        status="${status//seconds ago/秒前}"
        status="${status//minutes ago/分钟前}"
        status="${status//hours ago/小时前}"
        status="${status//days ago/天前}"
        status="${status//weeks ago/周前}"
        status="${status//months ago/月前}"
        status="${status//years ago/年前}"
        status="🟡 $status"
    elif [[ "$status" == Paused* ]]; then
        status="🟡 已暂停"
    elif [[ "$status" == Dead* ]]; then
        status="🟡 已死亡"
    else
        status="🟡 $status"
    fi

    printf "%-4s %-25s %-20s %s\n" "$i" "$name" "$status" "$image"
    ((i++))
done <<< "$containers"

echo "--------------------------------------------------------------------------------------------"
read -r -p "确认备份全部容器？(Y/N): " confirm
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
    selected=$(select_containers_for_backup multi) || { echo "已取消"; return 0; }
    local selected_array=($selected)

    if [ ${#selected_array[@]} -eq 0 ]; then
        echo "⚠️ 未选择任何容器"
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
    if [[ ! "$sel" =~ ^[0-9]+$ ]] || [ "$sel" -eq 0 ] || [ "$sel" -gt ${#backups[@]} ]; then
        echo "已取消"
        return
    fi

    local backup_path="${backups[$((sel-1))]}"
    echo "已选择: $(basename "$backup_path")"

    local restore_root="/root/restore_temp_$(date +%s)"
    mkdir -p "$restore_root"
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

    CONTAINER_NAMES=()
    while IFS= read -r line; do
        if [[ "$line" =~ --name[=[:space:]]+([^[:space:]]+) ]]; then
            CONTAINER_NAMES+=("${BASH_REMATCH[1]}")
        fi
    done < "$start_script"

    if [ ${#CONTAINER_NAMES[@]} -gt 0 ]; then
        echo "🔍 检测到备份中包含以下容器：${CONTAINER_NAMES[*]}"
        local to_delete=()
        for cn in "${CONTAINER_NAMES[@]}"; do
            if docker ps -a --format "{{.Names}}" | grep -qx "$cn"; then
                echo "⚠️ 容器 $cn 已存在于当前系统中"
                read -r -p "是否删除该容器并继续恢复？(Y/N): " confirm
                if [[ "$confirm" =~ ^[Yy]$ ]]; then
                    to_delete+=("$cn")
                else
                    echo "⚠️ 用户取消，恢复中止"
                    pause_return
                    cd - >/dev/null
                    rm -rf "$restore_root"
                    return
                fi
            fi
        done
        for cn in "${to_delete[@]}"; do
            docker rm -f "$cn" >/dev/null 2>&1 && echo "✅ 已删除容器 $cn"
        done
    fi

    echo "📦 恢复数据卷（解压到原始目录）..."
    if ! tar -xzpf "$data_tar" -P -C /; then
        echo "⚠️ 恢复数据卷失败"
        cd - >/dev/null
        rm -rf "$restore_root"
        return 1
    fi

    echo "🚀 执行启动脚本..."
    chmod +x "$start_script"
    if ! bash "$start_script"; then
        echo "⚠️ 容器启动失败，请手动检查"
    else
        echo "✅ 容器已尝试启动"
    fi

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
    echo "0) 返回"

    read -r -p "请选择要删除的备份文件序号（0返回）: " sel
    if [[ "$sel" =~ ^[0-9]+$ ]] && [ "$sel" -gt 0 ] && [ "$sel" -le ${#backups[@]} ]; then
        local to_delete="${backups[$((sel-1))]}"
        read -r -p "确认删除 $(basename "$to_delete") ？(Y/N): " confirm
        if [[ "$confirm" =~ ^[Yy]$ ]]; then
            rm -f "$to_delete"
            echo "✅ 已删除"
        else
            echo "已取消"
        fi
    elif [ "$sel" != "0" ]; then
        echo "⚠️ 无效选择"
    fi
    pause_return
}

# 生成 compose 等
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

    mkdir -p "$project_dir" || { echo "⚠️ 无法创建路径 $project_dir"; return; }
    cd "$project_dir" || return

    local compose_file="$project_dir/docker-compose.yml"

    echo "📝 正在编辑配置文件: $compose_file"
    if ! command -v nano &>/dev/null; then
        echo "📦 未检测到 nano 编辑器，正在自动安装..."
        case "$OS" in
            ubuntu|debian|armbian) apt update && apt install -y nano ;;
            centos|rocky|fedora|rhel) dnf -y install nano ;;
            arch) pacman -Sy --noconfirm nano ;;
            suse) zypper install -y nano ;;
            alpine) apk add nano ;;
            *) echo "⚠️ 无法自动安装 nano，请手动安装后重试"; return ;;
        esac
        echo "✅ nano 安装完成"
    fi

    nano "$compose_file"

    echo "🚀 正在启动 Compose 服务..."
    $compose_cmd -f "$compose_file" up -d --remove-orphans
    echo "✅ Compose 服务已启动"
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

    echo "找到以下 Compose 项目："
    echo "------------------------------------------------"
    local i=1
    for d in "${dirs[@]}"; do
        printf "%-4s %s\n" "$i" "$d"
        ((i++))
    done
    echo "------------------------------------------------"
    echo "📦 支持单选或多选（用空格分隔，如: 1 或 1 3 5）"
    echo "0) 返回"
    read -r -p "请输入序号: " sel

    if [[ "$sel" == "0" ]] || [ -z "$sel" ]; then
        echo "已取消"
        pause_return
        return
    fi

    local selected_indices=()
    local n
    for n in $sel; do
        if [[ "$n" =~ ^[0-9]+$ ]] && [ "$n" -ge 1 ] && [ "$n" -le ${#files[@]} ]; then
            selected_indices+=("$n")
        else
            echo "⚠️ 忽略无效序号: $n"
        fi
    done
    if [ ${#selected_indices[@]} -eq 0 ]; then
        echo "⚠️ 未选择有效项目"
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
        cd "$dir" || continue
        $compose_cmd -f "$file" pull || { echo "⚠️ 拉取镜像失败: $dir"; cd "$original_dir"; continue; }
        $compose_cmd -f "$file" up -d || { echo "⚠️ 启动服务失败: $dir"; cd "$original_dir"; continue; }
        echo "✅ 已更新: $dir"
        cd "$original_dir"
    done
    echo "✅ 所有选中的 Compose 项目更新完成"
    pause_return
}

uninstall_compose_all() {
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

    echo "找到以下 Compose 项目："
    echo "------------------------------------------------"
    local i=1
    for d in "${dirs[@]}"; do
        printf "%-4s %s\n" "$i" "$d"
        ((i++))
    done
    echo "------------------------------------------------"
    echo "📦 支持单选或多选（用空格分隔，如: 1 或 1 3 5）"
    echo "0) 返回"
    read -r -p "请输入序号: " sel

    if [[ "$sel" == "0" ]] || [ -z "$sel" ]; then
        echo "已取消"
        pause_return
        return
    fi

    local selected_indices=()
    local n
    for n in $sel; do
        if [[ "$n" =~ ^[0-9]+$ ]] && [ "$n" -ge 1 ] && [ "$n" -le ${#files[@]} ]; then
            selected_indices+=("$n")
        else
            echo "⚠️ 忽略无效序号: $n"
        fi
    done
    if [ ${#selected_indices[@]} -eq 0 ]; then
        echo "⚠️ 未选择有效项目"
        pause_return
        return
    fi

    echo "准备卸载以下 Compose 项目:"
    for idx in "${selected_indices[@]}"; do
        echo "  - ${dirs[$((idx-1))]}"
    done
    read -r -p "确认卸载？此操作将停止并删除容器、网络、卷（如果存在），并删除 docker-compose.yml 文件 (Y/N): " confirm
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
        cd "$dir" || continue

        $compose_cmd -f "$file" down -v 2>/dev/null || echo "⚠️ 执行 down -v 失败，尝试普通 down"
        $compose_cmd -f "$file" down 2>/dev/null

        rm -f "$file"
        echo "✅ 已删除 docker-compose.yml"

        read -r -p "是否删除项目目录 $dir ? (Y/N): " del_dir
        if [[ "$del_dir" =~ ^[Yy]$ ]]; then
            rm -rf "$dir"
            echo "✅ 已删除目录 $dir"
        else
            echo "保留目录: $dir"
        fi
        cd "$original_dir"
    done
    echo "✅ 选中的 Compose 项目已卸载"
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
                if ! command -v nano &>/dev/null; then
                    echo "📦 未检测到 nano 编辑器，正在自动安装..."
                    case "$OS" in
                        ubuntu|debian|armbian) apt update && apt install -y nano ;;
                        centos|rocky|fedora|rhel) dnf -y install nano ;;
                        arch) pacman -Sy --noconfirm nano ;;
                        suse) zypper install -y nano ;;
                        alpine) apk add nano ;;
                        *) echo "⚠️ 无法自动安装 nano，请手动安装后重试"; pause_return; continue ;;
                    esac
                    echo "✅ nano 安装完成"
                fi
                new_compose
                pause_return
                ;;
            2)
                echo "备份 Docker 容器"
                echo "1) 备份所有容器（运行中/已停止）"
                echo "2) 选择容器备份（支持单选/多选）"
                read -r -p "请选择: " sub

                if [ "$sub" = "1" ]; then
                    backup_all_containers
                    pause_return
                elif [ "$sub" = "2" ]; then
                    backup_selected_containers
                    pause_return
                else
                    echo "⚠️ 无效选择"
                    pause_return
                fi
                ;;
            3)
                restore_backup
                ;;
            4)
                list_backups
                ;;
            5)
                selected=$(select_containers_for_backup multi "📦 请选择要停止的容器：") || { echo "已取消"; pause_return; continue; }
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
                selected=$(select_containers_for_backup multi "📦 请选择要重启的容器：") || { echo "已取消"; pause_return; continue; }
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
                update_compose_all
                ;;
            8)
                uninstall_compose_all
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
        echo "⚠️ Docker 未安装"
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
        echo "⚠️ Docker 未安装"
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
        echo "⚠️ Docker 未安装"
        pause_return
        return
    fi

    echo "⚠️ 即将清理所有未使用的 Docker 资源（镜像、容器、网络、缓存）"
    read -r -p "确认继续？(Y/N): " confirm
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        docker system prune -af
        echo "✅ 清理完成"
    else
        echo "已取消"
    fi
    pause_return
}

fix_network() {
    if ! command -v docker &>/dev/null || ! systemctl is-active --quiet docker 2>/dev/null; then
        echo "⚠️ Docker 未安装"
        pause_return
        return
    fi
    systemctl restart docker
    echo "✅ Docker 网络已重置"
    pause_return
}

self_heal() {
    if ! command -v docker &>/dev/null; then
        echo "⚠️ Docker 未安装"
        pause_return
        return
    fi
    systemctl restart docker 2>/dev/null || true
    docker ps -a
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
            apt-get update && apt-get install ufw -y
        elif command -v dnf >/dev/null 2>&1; then
            dnf install ufw -y
        elif command -v yum >/dev/null 2>&1; then
            yum install epel-release -y && yum install ufw -y
        elif command -v pacman >/dev/null 2>&1; then
            pacman -S ufw --noconfirm
        elif command -v apk >/dev/null 2>&1; then
            apk add ufw ip6tables
        elif command -v zypper >/dev/null 2>&1; then
            zypper install -y ufw
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

    UFW_STATUS=$(ufw status)
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
            ufw --force enable >/dev/null 2>&1
            if ! ufw status | grep -qE '22/tcp.*ALLOW|OpenSSH.*ALLOW'; then
                echo "⚠️ 自动放行 SSH 失败，请手动执行: ufw allow 22/tcp"
            fi
        else
            echo "↩️ 未启用防火墙"
        fi
        pause_return
        return
    fi

    # 获取防火墙状态（支持中英文）
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
        -e 's#Anywhere#任意位置#g')
    
    if [ -z "$RULES" ]; then
        echo "⚠️ 当前无任何放行规则"
    else
        echo "$RULES"
    fi

    read -r -p "🔹 是否关闭防火墙并清空规则? (Y/N): " close_fw
    if [[ "$close_fw" =~ ^[Yy]$ ]]; then
        echo "⚠️ 正在清空所有规则并关闭防火墙..."
        ufw --force reset >/dev/null 2>&1
        systemctl stop ufw >/dev/null 2>&1
        systemctl disable ufw >/dev/null 2>&1
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
        docker ps --format "{{.Names}}\t{{.Status}}\t{{.Ports}}" | while IFS=$'\t' read -r name status ports; do
            status_cn="$status"
            status_cn=$(echo "$status_cn" | sed -E 's/Up ([0-9]+) seconds/已运行 \1 秒/')
            status_cn=$(echo "$status_cn" | sed -E 's/Up About a minute/已运行 1 分钟/')
            status_cn=$(echo "$status_cn" | sed -E 's/Up ([0-9]+) minutes/已运行 \1 分钟/')
            status_cn=$(echo "$status_cn" | sed -E 's/Up About an hour/已运行 1 小时/')
            status_cn=$(echo "$status_cn" | sed -E 's/Up ([0-9]+) hours/已运行 \1 小时/')
            status_cn=$(echo "$status_cn" | sed -E 's/Up ([0-9]+) days/已运行 \1 天/')
            status_cn=$(echo "$status_cn" | sed -E 's/Up ([0-9]+) weeks?/已运行 \1 周/')
            status_cn=$(echo "$status_cn" | sed -E 's/Up ([0-9]+) months?/已运行 \1 月/')
            status_cn=$(echo "$status_cn" | sed -E 's/Up ([0-9]+) years?/已运行 \1 年/')
            status_cn=$(echo "$status_cn" | sed -E 's/Exited \(0\)/已停止/')
            if [[ "$status_cn" =~ ^Restarting ]]; then
                status_cn=$(echo "$status_cn" | sed -E 's/Restarting/重启中/')
                status_cn=$(echo "$status_cn" | sed -E 's/seconds ago/秒前/')
                status_cn=$(echo "$status_cn" | sed -E 's/minutes ago/分钟前/')
                status_cn=$(echo "$status_cn" | sed -E 's/hours ago/小时前/')
                status_cn=$(echo "$status_cn" | sed -E 's/days ago/天前/')
                status_cn=$(echo "$status_cn" | sed -E 's/weeks ago/周前/')
                status_cn=$(echo "$status_cn" | sed -E 's/months ago/月前/')
                status_cn=$(echo "$status_cn" | sed -E 's/years ago/年前/')
            fi
            printf "%-20s %-20s %s\n" "$name" "$status_cn" "$ports"
        done
        echo "--------------------------------------------------------------------------------------------------------------------------------"
    else
        echo "⚠️ Docker 未安装"
    fi
    pause_return
;;
3)
    # 临时关闭错误退出，避免任何命令失败导致中断
    set +e

    # ----- 检测/释放端口 -----
    # 确保 lsof 已安装
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
    read -r -p "输入要检测的端口(多个用空格分隔, 0返回, A一键释放所有占用): " ports
    if [ -z "$ports" ] || [ "$ports" = "0" ]; then
        echo "↩️ 已取消操作"
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

        # 释放 Docker 容器占用的端口
        if command -v docker >/dev/null 2>&1; then
            docker ps --format "{{.Names}}\t{{.Ports}}" 2>/dev/null | while IFS=$'\t' read -r name ports; do
                [[ -z "$ports" ]] && continue
                echo "🐳 停止容器 $name 释放端口..."
                docker stop "$name" >/dev/null 2>&1 && echo "✅ 容器 $name 已停止（端口释放）"
            done
        fi

        # 释放系统进程占用的端口
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

        # 检查 Docker 容器占用
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
                fi
                continue
            fi
        fi

        # 检查系统进程占用
        PID=$(lsof -t -i :$port 2>/dev/null)
        if [ -n "$PID" ]; then
            PROC_NAME=$(ps -p $PID -o comm= 2>/dev/null)
            read -r -p "🖥️ 系统进程 $PROC_NAME 占用端口 $port, 是否释放? (Y/N): " yn
            if [[ "$yn" =~ ^[Yy]$ ]]; then
                kill $PID 2>/dev/null
                sleep 1
                if ! lsof -i :$port >/dev/null 2>&1; then
                    echo "✅ 已释放端口 $port"
                else
                    kill -9 $PID 2>/dev/null && echo "🔥 已强制释放端口 $port" || echo "⚠️ 释放失败"
                fi
            fi
        else
            echo "未被占用"
        fi
    done

    pause_return
    # 恢复错误退出模式
    set -e
;;
4)
    echo "🔓 开放端口"
    if ! command -v ufw >/dev/null 2>&1; then
        echo "⚠️ 系统未安装 ufw"
        pause_return
        return
    fi

    read -r -p "输入要开放的端口(多个用空格分隔，0返回): " ports
    if [ -z "$ports" ] || [ "$ports" = "0" ]; then
        echo "↩️ 已取消操作"
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

switch_lang() {
    # 1. 权限与系统识别
    [ "$EUID" -ne 0 ] && echo "错误：请以 root 权限运行" && return 1
    [ -f /etc/os-release ] && . /etc/os-release || ID="unknown"

    echo "正在快速切换系统语言为 zh_CN.UTF-8..."

    # 2. 核心逻辑 (针对 Debian/Ubuntu/Armbian)
    if [[ "$ID" == "debian" || "$ID" == "ubuntu" || "$ID" == "armbian" ]]; then
        
        # 精准检查
        NEED_INSTALL=false
        ! command -v locale-gen &> /dev/null && NEED_INSTALL=true
        [[ "$ID" == "ubuntu" ]] && ! dpkg -l | grep -q "language-pack-zh-hans" && NEED_INSTALL=true

        if [ "$NEED_INSTALL" = true ]; then
            echo "正在补全语言环境 (仅首次运行需等待)..."
            # 使用 > /dev/null 2>&1 屏蔽所有安装日志
            apt-get update -qq > /dev/null 2>&1
            if [[ "$ID" == "ubuntu" ]]; then
                apt-get install -y locales language-pack-zh-hans -qq > /dev/null 2>&1
            else
                apt-get install -y locales -qq > /dev/null 2>&1
            fi
        fi

        # 写入生成配置 (静默)
        echo "zh_CN.UTF-8 UTF-8" > /etc/locale.gen

        # 只有缺失时才编译
        if [[ "$(locale -a 2>/dev/null || true)" != *"zh_CN.utf8"* ]]; then
            echo "正在编译语言环境..."
            /usr/sbin/locale-gen zh_CN.UTF-8 > /dev/null 2>&1
        fi

        # 永久写入配置
        cat << 'EOF' > /etc/default/locale
LANG=zh_CN.UTF-8
LANGUAGE=zh_CN:zh
LC_ALL=zh_CN.UTF-8
EOF

        # 清除精简系统限制 (静默)
        [ -f /etc/dpkg/dpkg.cfg.d/excludes ] && rm -f /etc/dpkg/dpkg.cfg.d/excludes > /dev/null 2>&1

    elif [[ "$ID" == "alpine" ]]; then
        apk add --no-cache musl-locales musl-locales-lang > /dev/null 2>&1
        echo "export LANG=zh_CN.UTF-8" > /etc/profile.d/lang.sh
    fi

    # 3. 强制刷新当前会话
    export LANG=zh_CN.UTF-8 > /dev/null 2>&1
    export LC_ALL=zh_CN.UTF-8 > /dev/null 2>&1
    echo "✅ 系统语言切换完成，请重新连接 SSH 生效"
    pause_return
}

install_motd() {
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
        if ! command -v bash >/dev/null 2>&1; then apk add bash 2>/dev/null || true; fi
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
    echo "⚠️ 警告：无法自动重启 SSH 服务，请手动重启"
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

output=$(awk '$1 == "eth0:" {rx=$2; tx=$10} END {
    units[0]="B"; units[1]="KB"; units[2]="MB"; units[3]="GB";
    rxi=0; rxv=rx; while(rxv>=1024 && rxi<3){rxv/=1024; rxi++}
    txi=0; txv=tx; while(txv>=1024 && txi<3){txv/=1024; txi++}
    printf("⬇ 总接收: %.2f %s\n⬆ 总发送: %.2f %s\n", rxv, units[rxi], txv, units[txi])
}' /proc/net/dev)

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
    D_STATUS="⚠️ Docker 未安装"
    DOCKER_VER="未安装"
    COMPOSE_VER="未安装"
fi

# 3. 输出界面
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
echo -e "${purple}$output${re}"
echo -e "${CYAN}------------------------------------------------------------${RESET}"

# 4. Docker 统计
echo -e "\n${YELLOW}🐳 Docker 状态:${RESET}   ${D_STATUS}"
if [ -n "$RUNNING_APPS" ]; then
    docker ps --format "{{.Names}}\t{{.Status}}" | while IFS=$'\t' read -r name uptime; do
        echo -e "${GREEN}✅ $name 运行中 (${uptime})${RESET}"
    done
fi
if [ -n "$EXITED_APPS" ]; then
    for app in $EXITED_APPS; do
        exited_info=$(docker ps -a --filter "name=^/${app}$" --format "{{.Status}}")
        echo -e "${RED}⚠️ $app 未运行 (${exited_info})${RESET}"
    done
fi

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
                    npm) install_npm ;;
                    portainer) install_portainer ;;
                    lucky) install_lucky ;;
                    panel) install_1panel ;;
                esac
                pause_return
                ;;
            2)
                case $service in
                    npm) update_docker_service "npm" "Nginx Proxy Manager" "npm" ;;
                    portainer) update_docker_service "portainer" "Portainer" "portainer" ;;
                    lucky) update_docker_service "lucky" "Lucky" "lucky" ;;
                    panel) update_1panel ;;
                esac
                pause_return
                ;;
            3)
                case $service in
                    npm) uninstall_docker_service "npm" "Nginx Proxy Manager" "npm" "chishin/nginx-proxy-manager-zh:release" ;;
                    portainer) uninstall_docker_service "portainer" "Portainer" "portainer" "6053537/portainer-ce:latest" ;;
                    lucky) uninstall_docker_service "lucky" "Lucky" "lucky" "gdy666/lucky:v3" ;;
                    panel) uninstall_1panel ;;
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
    curl -fsSL "$DOWNLOAD_URL" -o caddy.tar.gz || { echo "⚠️ 下载失败"; cd -; rm -rf "$TMP_DIR"; return; }
    tar -xzf caddy.tar.gz
    chmod +x caddy
    mv caddy /usr/local/bin/caddy
    cd - >/dev/null
    rm -rf "$TMP_DIR"

    mkdir -p /etc/caddy /var/lib/caddy /var/log/caddy
    if ! id "caddy" &>/dev/null; then
        useradd -r -d /var/lib/caddy -s /usr/sbin/nologin caddy
    fi
    chown -R caddy:caddy /etc/caddy /var/lib/caddy /var/log/caddy

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
    if ! command -v nano &>/dev/null; then
        echo "nano 编辑器未安装，将使用 vi"
        EDITOR=vi
    else
        EDITOR=nano
    fi
    $EDITOR /etc/caddy/Caddyfile
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
            1) install_caddy ;;
            2) update_caddy ;;
            3) uninstall_caddy ;;
            4) configure_caddy ;;
            5) start_caddy ;;
            6) stop_caddy ;;
            7) restart_caddy ;;
            8) status_caddy ;;
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
    echo "🐳 Docker 工具箱 v1.3.5  by：万物皆可盘"
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
    echo "16) 切换系统语言 (zh_CN.UTF-8)"
    echo "17) 安装 SSH 登录面板 (MOTD)"
    echo "0) 退出"
    read -r -p "请选择: " choice
    case $choice in
        1) install_docker; show_versions; pause_return ;;
        2) update_docker; pause_return ;;
        3) manage_compose ;;
        4) uninstall_docker; pause_return ;;
        5) service_menu npm "Nginx Proxy Manager" ;;
        6) service_menu portainer "Portainer" ;;
        7) service_menu lucky "Lucky" ;;
        8) service_menu panel "1Panel" ;;
        9) caddy_menu ;;
        10) stop_all_containers ;;
        11) restart_all_containers ;;
        12) cleanup_system ;;
        13) fix_network ;;
        14) self_heal ;;
        15) open_ports ;;
        16) switch_lang ;;
        17) install_motd ;;
        0) exit 0 ;;
        *) echo "⚠️ 无效选择"; pause_return ;;
    esac
done
