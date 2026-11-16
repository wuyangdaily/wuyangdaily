#!/bin/bash

red='\033[0;31m'
green='\033[0;32m'
blue='\033[0;34m'
yellow='\033[0;33m'
plain='\033[0m'

xui_folder="${XUI_MAIN_FOLDER:=/usr/local/x-ui}"
xui_service="${XUI_SERVICE:=/etc/systemd/system}"

# 检查 root 权限
[[ $EUID -ne 0 ]] && echo -e "${red}致命错误：${plain} 请使用 root 权限运行此脚本 \n " && exit 1

# 检查操作系统并设置 release 变量
if [[ -f /etc/os-release ]]; then
    source /etc/os-release
    release=$ID
elif [[ -f /usr/lib/os-release ]]; then
    source /usr/lib/os-release
    release=$ID
else
    echo "无法检测系统操作系统，请联系作者！" >&2
    exit 1
fi
echo "操作系统版本为：$release"

arch() {
    case "$(uname -m)" in
        x86_64 | x64 | amd64) echo 'amd64' ;;
        i*86 | x86) echo '386' ;;
        armv8* | armv8 | arm64 | aarch64) echo 'arm64' ;;
        armv7* | armv7 | arm) echo 'armv7' ;;
        armv6* | armv6) echo 'armv6' ;;
        armv5* | armv5) echo 'armv5' ;;
        s390x) echo 's390x' ;;
        *) echo -e "${green}不支持的 CPU 架构！${plain}" && rm -f "$(realpath "$0")" && exit 1 ;;
    esac
}

echo "架构：$(arch)"

# 非交互模式：通过 XUI_NONINTERACTIVE=1 显式触发，或在 stdin 不是 TTY 时
# （例如 `curl ... | bash`、cloud-init）隐式触发。
# 在此模式下，下面的每个交互提示都会被环境变量或合理的默认值替代。
if [[ "${XUI_NONINTERACTIVE:-0}" == "1" ]] || [[ ! -t 0 ]]; then
    NONINTERACTIVE=1
else
    NONINTERACTIVE=0
fi
export NONINTERACTIVE

# 简单辅助函数
is_ipv4() {
    [[ "$1" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] && return 0 || return 1
}
is_ipv6() {
    [[ "$1" =~ : ]] && return 0 || return 1
}
is_ip() {
    is_ipv4 "$1" || is_ipv6 "$1"
}
is_domain() {
    [[ "$1" =~ ^([A-Za-z0-9](-*[A-Za-z0-9])*\.)+(xn--[a-z0-9]{2,}|[A-Za-z]{2,})$ ]] && return 0 || return 1
}

# acme.sh 的 standalone 服务默认绑定 IPv4；--listen-v6 会使其仅绑定 IPv6，
# 当域名的 A 记录指向本机的 IPv4 地址时，会破坏 HTTP-01 验证（#4994）。
# 只有当主机完全没有公网 IPv4 地址时，才强制使用 IPv6。
acme_listen_flag() {
    if ip -4 addr show scope global 2> /dev/null | grep -q "inet "; then
        echo ""
    else
        echo "--listen-v6"
    fi
}

# 端口辅助函数
is_port_in_use() {
    local port="$1"
    if command -v ss > /dev/null 2>&1; then
        ss -ltn 2> /dev/null | awk -v p=":${port}$" '$4 ~ p {exit 0} END {exit 1}'
        return
    fi
    if command -v netstat > /dev/null 2>&1; then
        netstat -lnt 2> /dev/null | awk -v p=":${port} " '$4 ~ p {exit 0} END {exit 1}'
        return
    fi
    if command -v lsof > /dev/null 2>&1; then
        lsof -nP -iTCP:${port} -sTCP:LISTEN > /dev/null 2>&1 && return 0
    fi
    return 1
}

install_base() {
    case "${release}" in
        ubuntu | debian | armbian)
            apt-get update && apt-get install -y -q cron curl tar tzdata socat ca-certificates openssl
            ;;
        fedora | amzn | virtuozzo | rhel | almalinux | rocky | ol)
            dnf makecache -y && dnf install -y -q cronie curl tar tzdata socat ca-certificates openssl
            ;;
        centos)
            if [[ "${VERSION_ID}" =~ ^7 ]]; then
                yum makecache -y && yum install -y cronie curl tar tzdata socat ca-certificates openssl
            else
                dnf makecache -y && dnf install -y -q cronie curl tar tzdata socat ca-certificates openssl
            fi
            ;;
        arch | manjaro | parch)
            pacman -Sy --noconfirm cronie curl tar tzdata socat ca-certificates openssl
            ;;
        opensuse-tumbleweed | opensuse-leap)
            zypper refresh && zypper -q install -y cron curl tar timezone socat ca-certificates openssl
            ;;
        alpine)
            apk update && apk add dcron curl tar tzdata socat ca-certificates openssl
            ;;
        *)
            apt-get update && apt-get install -y -q cron curl tar tzdata socat ca-certificates openssl
            ;;
    esac
}

gen_random_string() {
    local length="$1"
    openssl rand -base64 $((length * 2)) \
        | tr -dc 'a-zA-Z0-9' \
        | head -c "$length"
}

# prompt_or_default VARNAME "提示文本" "默认值" [ENV_NAME]
# 交互模式：读入 VARNAME。非交互模式：VARNAME = ${ENV_NAME:-默认值}。
# 省略时 ENV_NAME 默认为 VARNAME。保持每个交互提示字符串与原始的
# `read -rp` 逐字节一致。
prompt_or_default() {
    local __var="$1" __prompt="$2" __default="$3" __env="${4:-$1}"
    if [[ "$NONINTERACTIVE" == "1" ]]; then
        printf -v "$__var" '%s' "${!__env:-$__default}"
    else
        # shellcheck disable=SC2229
        read -rp "$__prompt" "$__var"
    fi
}

# write_install_result <用户> <密码> <端口> <web路径> <协议> <主机> <token> <数据库类型>
# 持久化一个可解析的、仅 root 可读的凭据文件，供 cloud-init/MOTD 使用。
# 值使用 printf '%q' 写入，因此包含空格、引号、$(...) 或反引号的固定密码/用户名
# 会被 shell 转义，文件保持可安全 source（消费者执行 '. install-result.env'）。
# 对于 gen_random_string 生成的字母数字随机值，%q 等同于原值。此文件与
# PostgreSQL 环境文件（/etc/default/x-ui）不同。
write_install_result() {
    local u="$1" p="$2" port="$3" wbp="$4" scheme="$5" host="$6" token="$7" dbtype="$8"
    local result_file="/etc/x-ui/install-result.env"
    local url_host="${host:-SERVER_IP_UNKNOWN}"
    install -d -m 700 /etc/x-ui 2> /dev/null
    local prev_umask
    prev_umask=$(umask)
    umask 077
    if ! {
        printf 'XUI_USERNAME=%q\n' "$u"
        printf 'XUI_PASSWORD=%q\n' "$p"
        printf 'XUI_PANEL_PORT=%q\n' "$port"
        printf 'XUI_WEB_BASE_PATH=%q\n' "$wbp"
        printf 'XUI_ACCESS_URL=%q\n' "${scheme}://${url_host}:${port}/${wbp}"
        printf 'XUI_API_TOKEN=%q\n' "$token"
        printf 'XUI_DB_TYPE=%q\n' "$dbtype"
    } > "$result_file"; then
        umask "$prev_umask"
        echo -e "${yellow}警告：写入 ${result_file} 失败。${plain}" >&2
        return 1
    fi
    umask "$prev_umask"
    chmod 600 "$result_file" 2> /dev/null
    chown root:root "$result_file" 2> /dev/null || true
    echo -e "${green}安装结果已写入 ${result_file}（权限 600）。${plain}"
}

# RHEL 系列的 initdb 会向 pg_hba.conf 写入使用 ident 认证的 host 规则，
# 该规则会将 OS 用户名与 PostgreSQL 角色进行比较，导致通过 TCP 连接的随机生成的
# 面板角色始终被拒绝（#5806）。为面板数据库预先添加密码认证规则；
# 首先匹配的规则生效，且 md5 也接受以 scram-sha-256 存储的验证器，
# 因此在所有支持的发行版上都适用。
pg_ensure_hba_password_auth() {
    local pg_db="$1"
    local hba_file
    hba_file=$(sudo -u postgres psql -tAc 'SHOW hba_file' 2> /dev/null | tr -d '[:space:]')
    [[ -n "${hba_file}" && -f "${hba_file}" ]] || return 0
    grep -Eq "^host[[:space:]]+${pg_db}[[:space:]]" "${hba_file}" && return 0
    local tmp
    tmp=$(mktemp) || return 1
    {
        echo "# 由 3x-ui 添加：允许面板数据库使用密码登录。"
        echo "host    ${pg_db}    all    127.0.0.1/32    md5"
        echo "host    ${pg_db}    all    ::1/128         md5"
        cat "${hba_file}"
    } > "${tmp}" || {
        rm -f "${tmp}"
        return 1
    }
    cat "${tmp}" > "${hba_file}" || {
        rm -f "${tmp}"
        return 1
    }
    rm -f "${tmp}"
    sudo -u postgres psql -tAc 'SELECT pg_reload_conf()' > /dev/null 2>&1 || true
}

install_postgres_local() {
    local pg_user pg_pass
    pg_pass=$(gen_random_string 24)
    local pg_db="xui"
    local pg_host="127.0.0.1"
    local pg_port="5432"

    case "${release}" in
        ubuntu | debian | armbian)
            apt-get update >&2 && apt-get install -y -q postgresql >&2 || return 1
            ;;
        fedora | amzn | virtuozzo | rhel | almalinux | rocky | ol)
            dnf install -y -q postgresql-server postgresql-contrib >&2 || return 1
            [[ -d /var/lib/pgsql/data && -f /var/lib/pgsql/data/PG_VERSION ]] || postgresql-setup --initdb >&2 || return 1
            ;;
        centos)
            if [[ "${VERSION_ID}" =~ ^7 ]]; then
                yum install -y postgresql-server postgresql-contrib >&2 || return 1
            else
                dnf install -y -q postgresql-server postgresql-contrib >&2 || return 1
            fi
            [[ -d /var/lib/pgsql/data && -f /var/lib/pgsql/data/PG_VERSION ]] || postgresql-setup --initdb >&2 || return 1
            ;;
        arch | manjaro | parch)
            pacman -Sy --noconfirm postgresql >&2 || return 1
            if [[ ! -f /var/lib/postgres/data/PG_VERSION ]]; then
                sudo -u postgres initdb -D /var/lib/postgres/data >&2 || return 1
            fi
            ;;
        opensuse-tumbleweed | opensuse-leap)
            zypper -q install -y postgresql-server postgresql-contrib >&2 || return 1
            if [[ ! -f /var/lib/pgsql/data/PG_VERSION ]]; then
                install -d -o postgres -g postgres -m 700 /var/lib/pgsql/data >&2 || return 1
                su - postgres -c "initdb -D /var/lib/pgsql/data" >&2 || return 1
            fi
            ;;
        alpine)
            apk add --no-cache postgresql postgresql-contrib >&2 || return 1
            if [[ ! -f /var/lib/postgresql/data/PG_VERSION ]]; then
                /etc/init.d/postgresql setup >&2 || return 1
            fi
            rc-update add postgresql default >&2 2> /dev/null || true
            rc-service postgresql start >&2 || return 1
            ;;
        *)
            echo -e "${red}不支持自动安装 PostgreSQL 的发行版：${release}${plain}" >&2
            return 1
            ;;
    esac

    if [[ "${release}" != "alpine" ]]; then
        systemctl enable --now postgresql >&2 || return 1
    fi

    # 短暂等待服务器接受连接。
    local i
    for i in 1 2 3 4 5; do
        sudo -u postgres psql -tAc 'SELECT 1' > /dev/null 2>&1 && break
        sleep 1
    done

    local existing_owner=""
    existing_owner=$(sudo -u postgres psql -tAc \
        "SELECT pg_catalog.pg_get_userbyid(datdba) FROM pg_database WHERE datname='${pg_db}'" 2> /dev/null \
        | tr -d '[:space:]')
    if [[ -n "${existing_owner}" && "${existing_owner}" != "postgres" ]]; then
        pg_user="${existing_owner}"
    else
        pg_user=$(gen_random_string 8)
    fi

    # 幂等的角色/数据库创建。标识符使用双引号，因为随机用户名可能以数字开头，
    # PostgreSQL 拒绝不加引号的此类标识符。
    sudo -u postgres psql -tAc "SELECT 1 FROM pg_roles WHERE rolname='${pg_user}'" 2> /dev/null \
        | grep -q 1 \
        || sudo -u postgres psql -c "CREATE USER \"${pg_user}\" WITH PASSWORD '${pg_pass}';" >&2 || return 1

    sudo -u postgres psql -tAc "SELECT 1 FROM pg_database WHERE datname='${pg_db}'" 2> /dev/null \
        | grep -q 1 \
        || sudo -u postgres psql -c "CREATE DATABASE \"${pg_db}\" OWNER \"${pg_user}\";" >&2 || return 1

    sudo -u postgres psql -c "ALTER USER \"${pg_user}\" WITH PASSWORD '${pg_pass}';" >&2 || return 1

    pg_ensure_hba_password_auth "${pg_db}" \
        || echo -e "${yellow}警告：无法更新 pg_hba.conf；PostgreSQL 可能拒绝面板的 TCP 登录（ident 认证）。${plain}" >&2

    local pg_pass_enc
    pg_pass_enc=$(printf '%s' "${pg_pass}" | sed -e 's/%/%25/g' -e 's/:/%3A/g' -e 's/@/%40/g' -e 's|/|%2F|g' -e 's/?/%3F/g' -e 's/#/%23/g')

    if [[ -n "${PG_CRED_FILE:-}" ]]; then
        local prev_umask
        prev_umask=$(umask)
        umask 077
        if ! cat > "${PG_CRED_FILE}" << EOF; then
PG_USER=${pg_user}
PG_PASS=${pg_pass}
PG_HOST=${pg_host}
PG_PORT=${pg_port}
PG_DB=${pg_db}
EOF
            umask "${prev_umask}"
            echo -e "${red}将 PostgreSQL 凭据写入 ${PG_CRED_FILE} 失败${plain}" >&2
            return 1
        fi
        umask "${prev_umask}"
    fi

    echo "postgres://${pg_user}:${pg_pass_enc}@${pg_host}:${pg_port}/${pg_db}?sslmode=disable"
    return 0
}

ensure_pg_client() {
    if command -v pg_dump > /dev/null 2>&1 && command -v pg_restore > /dev/null 2>&1; then
        return 0
    fi
    echo -e "${yellow}正在安装 PostgreSQL 客户端工具（pg_dump/pg_restore）以供面板内备份使用...${plain}" >&2
    case "${release}" in
        ubuntu | debian | armbian)
            apt-get update >&2 && apt-get install -y -q postgresql-client >&2 || return 1
            ;;
        fedora | amzn | virtuozzo | rhel | almalinux | rocky | ol)
            dnf install -y -q postgresql >&2 || return 1
            ;;
        centos)
            if [[ "${VERSION_ID}" =~ ^7 ]]; then
                yum install -y postgresql >&2 || return 1
            else
                dnf install -y -q postgresql >&2 || return 1
            fi
            ;;
        arch | manjaro | parch)
            pacman -Sy --noconfirm postgresql >&2 || return 1
            ;;
        opensuse-tumbleweed | opensuse-leap)
            zypper -q install -y postgresql >&2 || return 1
            ;;
        alpine)
            apk add --no-cache postgresql-client >&2 || return 1
            ;;
        *)
            return 1
            ;;
    esac
    command -v pg_dump > /dev/null 2>&1 && command -v pg_restore > /dev/null 2>&1
}

install_acme() {
    echo -e "${green}正在安装 acme.sh 用于 SSL 证书管理...${plain}"
    cd ~ || return 1
    curl -s https://get.acme.sh | sh > /dev/null 2>&1
    if [ $? -ne 0 ]; then
        echo -e "${red}安装 acme.sh 失败${plain}"
        return 1
    else
        echo -e "${green}acme.sh 安装成功${plain}"
    fi
    return 0
}

setup_ssl_certificate() {
    local domain="$1"
    local server_ip="$2"
    local existing_port="$3"
    local existing_webBasePath="$4"

    echo -e "${green}正在设置 SSL 证书...${plain}"

    # 检查 acme.sh 是否已安装
    if ! command -v ~/.acme.sh/acme.sh &> /dev/null; then
        install_acme
        if [ $? -ne 0 ]; then
            echo -e "${yellow}安装 acme.sh 失败，跳过 SSL 设置${plain}"
            return 1
        fi
    fi

    # 创建证书目录
    local certPath="/root/cert/${domain}"
    mkdir -p "$certPath"

    # 签发证书
    echo -e "${green}正在为 ${domain} 签发 SSL 证书...${plain}"
    echo -e "${yellow}注意：80 端口必须对外开放并且可从互联网访问${plain}"

    ~/.acme.sh/acme.sh --set-default-ca --server letsencrypt --force > /dev/null 2>&1
    ~/.acme.sh/acme.sh --issue -d ${domain} $(acme_listen_flag) --standalone --httpport 80 --force

    if [ $? -ne 0 ]; then
        echo -e "${yellow}为 ${domain} 签发证书失败${plain}"
        echo -e "${yellow}请确保 80 端口已开放，稍后可使用以下命令重试：x-ui${plain}"
        rm -rf ~/.acme.sh/${domain} ~/.acme.sh/${domain}_ecc 2> /dev/null
        rm -rf "$certPath" 2> /dev/null
        return 1
    fi

    # 安装证书
    ~/.acme.sh/acme.sh --installcert --force -d ${domain} \
        --key-file /root/cert/${domain}/privkey.pem \
        --fullchain-file /root/cert/${domain}/fullchain.pem \
        --reloadcmd "systemctl restart x-ui" > /dev/null 2>&1

    if [ $? -ne 0 ]; then
        echo -e "${yellow}安装证书失败${plain}"
        return 1
    fi

    # 启用自动续期
    ~/.acme.sh/acme.sh --upgrade --auto-upgrade > /dev/null 2>&1
    # 安全权限：私钥仅所有者可读
    chmod 600 $certPath/privkey.pem 2> /dev/null
    chmod 644 $certPath/fullchain.pem 2> /dev/null

    # 为面板设置证书
    local webCertFile="/root/cert/${domain}/fullchain.pem"
    local webKeyFile="/root/cert/${domain}/privkey.pem"

    if [[ -f "$webCertFile" && -f "$webKeyFile" ]]; then
        ${xui_folder}/x-ui cert -webCert "$webCertFile" -webCertKey "$webKeyFile" > /dev/null 2>&1
        echo -e "${green}SSL 证书已成功安装并配置！${plain}"
        return 0
    else
        echo -e "${yellow}未找到证书文件${plain}"
        return 1
    fi
}

# 使用 shortlived profile 签发 Let's Encrypt IP 证书（有效期约 6 天）
# 需要 acme.sh 以及 80 端口开放以进行 HTTP-01 验证
setup_ip_certificate() {
    local ipv4="$1"
    local ipv6="$2" # 可选

    echo -e "${green}正在设置 Let's Encrypt IP 证书（shortlived profile）...${plain}"
    echo -e "${yellow}注意：IP 证书有效期约为 6 天，将自动续期。${plain}"
    echo -e "${yellow}默认监听端口为 80。如果选择其他端口，请确保外部 80 端口转发到该端口。${plain}"

    # 检查 acme.sh
    if ! command -v ~/.acme.sh/acme.sh &> /dev/null; then
        install_acme
        if [ $? -ne 0 ]; then
            echo -e "${red}安装 acme.sh 失败${plain}"
            return 1
        fi
    fi

    # 验证 IP 地址
    if [[ -z "$ipv4" ]]; then
        echo -e "${red}必须提供 IPv4 地址${plain}"
        return 1
    fi

    if ! is_ipv4 "$ipv4"; then
        echo -e "${red}无效的 IPv4 地址：$ipv4${plain}"
        return 1
    fi

    # 创建证书目录
    local certDir="/root/cert/ip"
    mkdir -p "$certDir"

    # 构建域名参数
    local domain_args="-d ${ipv4}"
    if [[ -n "$ipv6" ]] && is_ipv6 "$ipv6"; then
        domain_args="${domain_args} -d ${ipv6}"
        echo -e "${green}包含 IPv6 地址：${ipv6}${plain}"
    fi

    # 设置自动续期的 reload 命令（添加 || true 使其在首次安装期间不失败）
    local reloadCmd="systemctl restart x-ui 2>/dev/null || rc-service x-ui restart 2>/dev/null || true"

    # 选择 HTTP-01 监听端口（默认 80，可提示覆盖）
    local WebPort=""
    prompt_or_default WebPort "用于 ACME HTTP-01 监听的端口（默认 80）：" "80" XUI_ACME_HTTP_PORT
    WebPort="${WebPort:-80}"
    if ! [[ "${WebPort}" =~ ^[0-9]+$ ]] || ((WebPort < 1 || WebPort > 65535)); then
        echo -e "${red}提供的端口无效。回退到 80。${plain}"
        WebPort=80
    fi
    echo -e "${green}使用端口 ${WebPort} 进行 standalone 验证。${plain}"
    if [[ "${WebPort}" -ne 80 ]]; then
        echo -e "${yellow}提醒：Let's Encrypt 仍会连接 80 端口；请将外部 80 端口转发到 ${WebPort}。${plain}"
    fi

    # 确保所选端口可用
    while true; do
        if is_port_in_use "${WebPort}"; then
            echo -e "${yellow}端口 ${WebPort} 已被占用。${plain}"

            local alt_port=""
            if [[ "$NONINTERACTIVE" == "1" ]]; then
                echo -e "${red}端口 ${WebPort} 被占用；非交互模式下无法继续。${plain}"
                return 1
            fi
            read -rp "输入另一个用于 acme.sh standalone 监听的端口（留空则中止）：" alt_port
            alt_port="${alt_port// /}"
            if [[ -z "${alt_port}" ]]; then
                echo -e "${red}端口 ${WebPort} 被占用；无法继续。${plain}"
                return 1
            fi
            if ! [[ "${alt_port}" =~ ^[0-9]+$ ]] || ((alt_port < 1 || alt_port > 65535)); then
                echo -e "${red}提供的端口无效。${plain}"
                return 1
            fi
            WebPort="${alt_port}"
            continue
        else
            echo -e "${green}端口 ${WebPort} 空闲，可用于 standalone 验证。${plain}"
            break
        fi
    done

    # 使用 shortlived profile 签发证书
    echo -e "${green}正在为 ${ipv4} 签发 IP 证书...${plain}"
    ~/.acme.sh/acme.sh --set-default-ca --server letsencrypt --force > /dev/null 2>&1
    [[ -n "${XUI_ACME_EMAIL:-}" ]] && ~/.acme.sh/acme.sh --register-account -m "${XUI_ACME_EMAIL}" > /dev/null 2>&1

    ~/.acme.sh/acme.sh --issue \
        ${domain_args} \
        --standalone \
        --server letsencrypt \
        --certificate-profile shortlived \
        --days 6 \
        --httpport ${WebPort} \
        --force

    if [ $? -ne 0 ]; then
        echo -e "${red}签发 IP 证书失败${plain}"
        echo -e "${yellow}请确保端口 ${WebPort} 可达（或从外部 80 端口转发过来）${plain}"
        # 清理 acme.sh 数据，包含 IPv4 和 IPv6（如果指定）
        rm -rf ~/.acme.sh/${ipv4} ~/.acme.sh/${ipv4}_ecc 2> /dev/null
        [[ -n "$ipv6" ]] && rm -rf ~/.acme.sh/${ipv6} ~/.acme.sh/${ipv6}_ecc 2> /dev/null
        rm -rf ${certDir} 2> /dev/null
        return 1
    fi

    echo -e "${green}证书签发成功，正在安装...${plain}"

    # 安装证书
    # 注意：如果 reloadcmd 失败，acme.sh 可能报告 "Reload error" 并返回非零值，
    # 但证书文件仍然已安装。我们检查文件是否存在，而不是退出码。
    ~/.acme.sh/acme.sh --installcert --force -d ${ipv4} \
        --key-file "${certDir}/privkey.pem" \
        --fullchain-file "${certDir}/fullchain.pem" \
        --reloadcmd "${reloadCmd}" 2>&1 || true

    # 验证证书文件存在（不要依赖退出码——reloadcmd 失败会导致非零值）
    if [[ ! -f "${certDir}/fullchain.pem" || ! -f "${certDir}/privkey.pem" ]]; then
        echo -e "${red}安装后未找到证书文件${plain}"
        # 清理 acme.sh 数据，包含 IPv4 和 IPv6（如果指定）
        rm -rf ~/.acme.sh/${ipv4} ~/.acme.sh/${ipv4}_ecc 2> /dev/null
        [[ -n "$ipv6" ]] && rm -rf ~/.acme.sh/${ipv6} ~/.acme.sh/${ipv6}_ecc 2> /dev/null
        rm -rf ${certDir} 2> /dev/null
        return 1
    fi

    echo -e "${green}证书文件安装成功${plain}"

    # 启用 acme.sh 自动升级（确保 cron 任务运行）
    ~/.acme.sh/acme.sh --upgrade --auto-upgrade > /dev/null 2>&1

    # 安全权限：私钥仅所有者可读
    chmod 600 ${certDir}/privkey.pem 2> /dev/null
    chmod 644 ${certDir}/fullchain.pem 2> /dev/null

    # 为面板配置证书
    echo -e "${green}正在为面板设置证书路径...${plain}"
    ${xui_folder}/x-ui cert -webCert "${certDir}/fullchain.pem" -webCertKey "${certDir}/privkey.pem"

    if [ $? -ne 0 ]; then
        echo -e "${yellow}警告：无法自动设置证书路径${plain}"
        echo -e "${yellow}证书文件位置：${plain}"
        echo -e "  证书：${certDir}/fullchain.pem"
        echo -e "  密钥：${certDir}/privkey.pem"
    else
        echo -e "${green}证书路径配置成功${plain}"
    fi

    echo -e "${green}IP 证书已成功安装并配置！${plain}"
    echo -e "${green}证书有效期约 6 天，通过 acme.sh cron 任务自动续期。${plain}"
    echo -e "${yellow}acme.sh 将在到期前自动续期并重载 x-ui。${plain}"
    return 0
}

# 通过 acme.sh 进行全面的手动 SSL 证书签发
ssl_cert_issue() {
    local existing_webBasePath=$(${xui_folder}/x-ui setting -show true | grep 'webBasePath:' | awk -F': ' '{print $2}' | tr -d '[:space:]' | sed 's#^/##')
    local existing_port=$(${xui_folder}/x-ui setting -show true | grep 'port:' | awk -F': ' '{print $2}' | tr -d '[:space:]')

    # 首先检查 acme.sh
    if ! command -v ~/.acme.sh/acme.sh &> /dev/null; then
        echo "未找到 acme.sh。现在安装..."
        cd ~ || return 1
        curl -s https://get.acme.sh | sh
        if [ $? -ne 0 ]; then
            echo -e "${red}安装 acme.sh 失败${plain}"
            return 1
        else
            echo -e "${green}acme.sh 安装成功${plain}"
        fi
    fi

    # 在此处获取域名，并验证
    local domain=""
    if [[ "$NONINTERACTIVE" == "1" ]]; then
        domain="${XUI_DOMAIN// /}"
        if [[ -z "$domain" ]] || ! is_domain "$domain"; then
            echo -e "${red}XUI_SSL_MODE=domain 需要有效的 XUI_DOMAIN（当前值：'${XUI_DOMAIN:-}'）。${plain}"
            return 1
        fi
    else
        while true; do
            read -rp "请输入您的域名：" domain
            domain="${domain// /}" # 去除空白

            if [[ -z "$domain" ]]; then
                echo -e "${red}域名不能为空。请重试。${plain}"
                continue
            fi

            if ! is_domain "$domain"; then
                echo -e "${red}域名格式无效：${domain}。请输入有效的域名。${plain}"
                continue
            fi

            break
        done
    fi
    echo -e "${green}您的域名是：${domain}，正在检查...${plain}"
    SSL_ISSUED_DOMAIN="${domain}"

    # 检测现有证书，仅当证书文件实际存在且非空时才复用。
    # acme.sh 将 ECC 证书存储在 ${domain}_ecc，RSA 证书存储在 ${domain}；
    # 签发失败可能在 --list 中留下域名条目但没有可用证书文件，
    # 此时不能复用（会产生 0 字节的 fullchain.pem）。损坏的部分状态会被清理，
    # 以便继续签发。
    local cert_exists=0
    if ~/.acme.sh/acme.sh --list 2> /dev/null | awk '{print $1}' | grep -Fxq "${domain}"; then
        local acmeCertDir=""
        if [[ -s ~/.acme.sh/${domain}_ecc/fullchain.cer && -s ~/.acme.sh/${domain}_ecc/${domain}.key ]]; then
            acmeCertDir=~/.acme.sh/${domain}_ecc
        elif [[ -s ~/.acme.sh/${domain}/fullchain.cer && -s ~/.acme.sh/${domain}/${domain}.key ]]; then
            acmeCertDir=~/.acme.sh/${domain}
        fi
        if [[ -n "${acmeCertDir}" ]]; then
            cert_exists=1
            local certInfo=$(~/.acme.sh/acme.sh --list 2> /dev/null | grep -F "${domain}")
            echo -e "${yellow}发现 ${domain} 的现有证书，将复用。${plain}"
            [[ -n "${certInfo}" ]] && echo "$certInfo"
        else
            echo -e "${yellow}发现 ${domain} 存在不完整的 acme.sh 状态（无有效证书文件）；正在清理并重新签发。${plain}"
            rm -rf ~/.acme.sh/${domain} ~/.acme.sh/${domain}_ecc
        fi
    fi
    if [[ ${cert_exists} -eq 0 ]]; then
        echo -e "${green}您的域名已准备好签发证书...${plain}"
    fi

    # 创建证书目录
    certPath="/root/cert/${domain}"
    if [ ! -d "$certPath" ]; then
        mkdir -p "$certPath"
    else
        rm -rf "$certPath"
        mkdir -p "$certPath"
    fi

    # 获取 standalone 服务器的端口号
    local WebPort=80
    prompt_or_default WebPort "请选择要使用的端口（默认 80）：" "80" XUI_ACME_HTTP_PORT
    if [[ -z ${WebPort} ]]; then
        WebPort=80
    elif [[ ! ${WebPort} =~ ^[1-9][0-9]*$ || ${WebPort} -gt 65535 ]]; then
        echo -e "${yellow}您输入的 ${WebPort} 无效，将使用默认端口 80。${plain}"
        WebPort=80
    fi
    echo -e "${green}将使用端口：${WebPort} 签发证书。请确保该端口已开放。${plain}"

    # 临时停止面板
    echo -e "${yellow}正在临时停止面板...${plain}"
    systemctl stop x-ui 2> /dev/null || rc-service x-ui stop 2> /dev/null

    if [[ ${cert_exists} -eq 0 ]]; then
        # 签发证书
        ~/.acme.sh/acme.sh --set-default-ca --server letsencrypt --force
        [[ -n "${XUI_ACME_EMAIL:-}" ]] && ~/.acme.sh/acme.sh --register-account -m "${XUI_ACME_EMAIL}" > /dev/null 2>&1
        ~/.acme.sh/acme.sh --issue -d ${domain} $(acme_listen_flag) --standalone --httpport ${WebPort} --force
        if [ $? -ne 0 ]; then
            echo -e "${red}签发证书失败，请查看日志。${plain}"
            rm -rf ~/.acme.sh/${domain} ~/.acme.sh/${domain}_ecc
            systemctl start x-ui 2> /dev/null || rc-service x-ui start 2> /dev/null
            return 1
        else
            echo -e "${green}签发证书成功，正在安装证书...${plain}"
        fi
    else
        echo -e "${green}使用现有证书，正在安装证书...${plain}"
    fi

    # 设置 reload 命令
    reloadCmd="systemctl restart x-ui || rc-service x-ui restart"
    echo -e "${green}ACME 默认 --reloadcmd 为：${yellow}systemctl restart x-ui || rc-service x-ui restart${plain}"
    echo -e "${green}此命令将在每次证书签发和续期时运行。${plain}"
    if [[ "$NONINTERACTIVE" == "1" ]]; then
        setReloadcmd="n"
    else
        read -rp "您是否要修改 ACME 的 --reloadcmd？(y/n)：" setReloadcmd
    fi
    if [[ "$setReloadcmd" == "y" || "$setReloadcmd" == "Y" ]]; then
        echo -e "\n${green}\t1.${plain} 预设：systemctl reload nginx ; systemctl restart x-ui"
        echo -e "${green}\t2.${plain} 输入自定义命令"
        echo -e "${green}\t0.${plain} 保留默认 reloadcmd"
        read -rp "请选择一个选项：" choice
        case "$choice" in
            1)
                echo -e "${green}Reloadcmd 为：systemctl reload nginx ; systemctl restart x-ui${plain}"
                reloadCmd="systemctl reload nginx ; systemctl restart x-ui"
                ;;
            2)
                echo -e "${yellow}建议将 x-ui restart 放在末尾${plain}"
                read -rp "请输入您的自定义 reloadcmd：" reloadCmd
                echo -e "${green}Reloadcmd 为：${reloadCmd}${plain}"
                ;;
            *)
                echo -e "${green}保留默认 reloadcmd${plain}"
                ;;
        esac
    fi

    # 安装证书
    local installOutput=""
    installOutput=$(~/.acme.sh/acme.sh --installcert --force -d ${domain} \
        --key-file /root/cert/${domain}/privkey.pem \
        --fullchain-file /root/cert/${domain}/fullchain.pem --reloadcmd "${reloadCmd}" 2>&1)
    local installRc=$?
    echo "${installOutput}"

    local installWroteFiles=0
    if echo "${installOutput}" | grep -q "Installing key to:" && echo "${installOutput}" | grep -q "Installing full chain to:"; then
        installWroteFiles=1
    fi

    if [[ -f "/root/cert/${domain}/privkey.pem" && -f "/root/cert/${domain}/fullchain.pem" && (${installRc} -eq 0 || ${installWroteFiles} -eq 1) ]]; then
        echo -e "${green}安装证书成功，正在启用自动续期...${plain}"
    else
        echo -e "${red}安装证书失败，退出。${plain}"
        if [[ ${cert_exists} -eq 0 ]]; then
            rm -rf ~/.acme.sh/${domain} ~/.acme.sh/${domain}_ecc
        fi
        systemctl start x-ui 2> /dev/null || rc-service x-ui start 2> /dev/null
        return 1
    fi

    # 启用自动续期
    ~/.acme.sh/acme.sh --upgrade --auto-upgrade
    if [ $? -ne 0 ]; then
        echo -e "${yellow}自动续期设置有疑问，证书详情：${plain}"
        ls -lah /root/cert/${domain}/
        # 安全权限：私钥仅所有者可读
        chmod 600 $certPath/privkey.pem 2> /dev/null
        chmod 644 $certPath/fullchain.pem 2> /dev/null
    else
        echo -e "${green}自动续期设置成功，证书详情：${plain}"
        ls -lah /root/cert/${domain}/
        # 安全权限：私钥仅所有者可读
        chmod 600 $certPath/privkey.pem 2> /dev/null
        chmod 644 $certPath/fullchain.pem 2> /dev/null
    fi

    # 启动面板
    systemctl start x-ui 2> /dev/null || rc-service x-ui start 2> /dev/null

    # 证书安装成功后提示用户设置面板路径
    if [[ "$NONINTERACTIVE" == "1" ]]; then
        setPanel="y"
    else
        read -rp "您是否要将此证书设置给面板使用？(y/n)：" setPanel
    fi
    if [[ "$setPanel" == "y" || "$setPanel" == "Y" ]]; then
        local webCertFile="/root/cert/${domain}/fullchain.pem"
        local webKeyFile="/root/cert/${domain}/privkey.pem"

        if [[ -f "$webCertFile" && -f "$webKeyFile" ]]; then
            ${xui_folder}/x-ui cert -webCert "$webCertFile" -webCertKey "$webKeyFile"
            echo -e "${green}已为面板设置证书路径${plain}"
            echo -e "${green}证书文件：$webCertFile${plain}"
            echo -e "${green}私钥文件：$webKeyFile${plain}"
            echo ""
            echo -e "${green}访问地址：https://${domain}:${existing_port}/${existing_webBasePath}${plain}"
            echo -e "${yellow}面板将重启以应用 SSL 证书...${plain}"
            systemctl restart x-ui 2> /dev/null || rc-service x-ui restart 2> /dev/null
        else
            echo -e "${red}错误：未找到域名为 $domain 的证书或私钥文件。${plain}"
        fi
    else
        echo -e "${yellow}跳过面板路径设置。${plain}"
    fi

    return 0
}

# 可复用的交互式 SSL 设置（域名或 IP）
# 将全局变量 `SSL_HOST` 设置为所选的域名/IP 以供访问 URL 使用
prompt_and_setup_ssl() {
    local panel_port="$1"
    local web_base_path="$2"
    local server_ip="$3"

    local ssl_choice=""
    SSL_SCHEME="https"

    echo -e "${yellow}选择 SSL 证书设置方式：${plain}"
    echo -e "${green}1.${plain} Let's Encrypt 域名证书（有效期 90 天，自动续期）"
    echo -e "${green}2.${plain} Let's Encrypt IP 地址证书（有效期 6 天，自动续期）"
    echo -e "${green}3.${plain} 自定义 SSL 证书（使用现有文件的路径）"
    echo -e "${green}4.${plain} 跳过 SSL（高级——仅用于反向代理 / SSH 隧道）"
    echo -e "${blue}注意：${plain} 选项 1 和 2 需要 80 端口开放。选项 3 需要手动指定路径。"
    echo -e "${blue}注意：${plain} 选项 4 会以明文 HTTP 提供面板——仅在 nginx/Caddy 或 SSH 隧道之后安全。"
    if [[ "$NONINTERACTIVE" == "1" ]]; then
        case "${XUI_SSL_MODE:-none}" in
            domain) ssl_choice="1" ;;
            ip) ssl_choice="2" ;;
            none | "") ssl_choice="4" ;;
            *)
                echo -e "${yellow}未知的 XUI_SSL_MODE='${XUI_SSL_MODE}'，默认为 none（HTTP）。${plain}"
                ssl_choice="4"
                ;;
        esac
    else
        read -rp "选择一个选项（默认 2 为 IP 证书）：" ssl_choice
        ssl_choice="${ssl_choice// /}" # 去除空白

        # 如果输入为空或无效（不是 1、3、4），则默认使用 2（IP 证书）
        if [[ "$ssl_choice" != "1" && "$ssl_choice" != "3" && "$ssl_choice" != "4" ]]; then
            ssl_choice="2"
        fi
    fi

    case "$ssl_choice" in
        1)
            # 用户选择了 Let's Encrypt 域名选项
            echo -e "${green}正在使用 Let's Encrypt 获取域名证书...${plain}"
            if ssl_cert_issue; then
                local cert_domain="${SSL_ISSUED_DOMAIN}"
                if [[ -z "${cert_domain}" ]]; then
                    cert_domain=$(~/.acme.sh/acme.sh --list 2> /dev/null | tail -1 | awk '{print $1}')
                fi

                if [[ -n "${cert_domain}" ]]; then
                    SSL_HOST="${cert_domain}"
                    echo -e "${green}✓ SSL 证书已成功配置，域名：${cert_domain}${plain}"
                else
                    echo -e "${yellow}SSL 设置可能已完成，但域名提取失败${plain}"
                    SSL_HOST="${server_ip}"
                fi
            else
                echo -e "${red}域名模式的 SSL 证书设置失败。${plain}"
                SSL_HOST="${server_ip}"
            fi
            ;;
        2)
            # 用户选择了 Let's Encrypt IP 证书选项
            echo -e "${green}正在使用 Let's Encrypt 获取 IP 证书（shortlived profile）...${plain}"

            # 在为自动检测的 IP 签发证书前确认：在非对称路由 / 多 WAN 情况下，
            # echo 服务可能返回中转地址。
            if [[ "$NONINTERACTIVE" != "1" ]]; then
                local ip_confirm=""
                read -rp "${server_ip} 是本服务器正确的公网 IPv4 入站地址吗？[默认 y]：" ip_confirm
                if [[ -n "$ip_confirm" && "$ip_confirm" != "y" && "$ip_confirm" != "Y" ]]; then
                    server_ip=""
                    while [[ -z "$server_ip" ]]; do
                        read -rp "请输入您服务器的公网 IPv4 地址：" server_ip
                        server_ip="${server_ip// /}"
                        if [[ ! "$server_ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
                            echo -e "${red}无效的 IPv4 地址。请重试。${plain}"
                            server_ip=""
                        fi
                    done
                fi
            fi

            # 询问可选的 IPv6
            local ipv6_addr=""
            prompt_or_default ipv6_addr "是否有要包含的 IPv6 地址？（留空跳过）：" "" XUI_SSL_IPV6
            ipv6_addr="${ipv6_addr// /}" # 去除空白

            # 如果面板正在运行则停止（需要 80 端口）
            if [[ $release == "alpine" ]]; then
                rc-service x-ui stop > /dev/null 2>&1
            else
                systemctl stop x-ui > /dev/null 2>&1
            fi

            setup_ip_certificate "${server_ip}" "${ipv6_addr}"
            if [ $? -eq 0 ]; then
                SSL_HOST="${server_ip}"
                echo -e "${green}✓ Let's Encrypt IP 证书配置成功${plain}"
            else
                echo -e "${red}✗ IP 证书设置失败。请检查 80 端口是否开放。${plain}"
                SSL_HOST="${server_ip}"
            fi
            ;;
        3)
            # 用户选择了自定义路径（用户提供）选项
            echo -e "${green}正在使用自定义现有证书...${plain}"
            local custom_cert=""
            local custom_key=""
            local custom_domain=""

            # 3.1 请求域名以便稍后组装面板 URL
            read -rp "请输入证书签发的域名：" custom_domain
            custom_domain="${custom_domain// /}" # 移除空格

            # 3.2 循环获取证书路径
            while true; do
                read -rp "输入证书路径（关键字：.crt / fullchain）：" custom_cert
                # 去除引号
                custom_cert=$(echo "$custom_cert" | tr -d '"' | tr -d "'")

                if [[ -f "$custom_cert" && -r "$custom_cert" && -s "$custom_cert" ]]; then
                    break
                elif [[ ! -f "$custom_cert" ]]; then
                    echo -e "${red}错误：文件不存在！请重试。${plain}"
                elif [[ ! -r "$custom_cert" ]]; then
                    echo -e "${red}错误：文件存在但不可读（请检查权限）！${plain}"
                else
                    echo -e "${red}错误：文件为空！${plain}"
                fi
            done

            # 3.3 循环获取私钥路径
            while true; do
                read -rp "输入私钥路径（关键字：.key / privatekey）：" custom_key
                # 去除引号
                custom_key=$(echo "$custom_key" | tr -d '"' | tr -d "'")

                if [[ -f "$custom_key" && -r "$custom_key" && -s "$custom_key" ]]; then
                    break
                elif [[ ! -f "$custom_key" ]]; then
                    echo -e "${red}错误：文件不存在！请重试。${plain}"
                elif [[ ! -r "$custom_key" ]]; then
                    echo -e "${red}错误：文件存在但不可读（请检查权限）！${plain}"
                else
                    echo -e "${red}错误：文件为空！${plain}"
                fi
            done

            # 3.4 通过 x-ui 二进制应用设置
            ${xui_folder}/x-ui cert -webCert "$custom_cert" -webCertKey "$custom_key" > /dev/null 2>&1

            # 设置 SSL_HOST 以组装面板 URL
            if [[ -n "$custom_domain" ]]; then
                SSL_HOST="$custom_domain"
            else
                SSL_HOST="${server_ip}"
            fi

            echo -e "${green}✓ 自定义证书路径已应用。${plain}"
            echo -e "${yellow}注意：您需要自行负责在外部续期这些文件。${plain}"

            systemctl restart x-ui > /dev/null 2>&1 || rc-service x-ui restart > /dev/null 2>&1
            ;;
        4)
            echo ""
            echo -e "${red}⚠ 面板将在没有 SSL/TLS 的情况下安装。${plain}"
            echo -e "${yellow}登录凭据和 Cookie 将以明文 HTTP 传输。${plain}"
            echo -e "${yellow}仅在以下情况安全：${plain}"
            echo -e "${yellow}  • 反向代理（nginx、Caddy、Traefik）为您终止 TLS，或${plain}"
            echo -e "${yellow}  • 您仅通过 SSH 隧道访问面板${plain}"
            echo ""

            SSL_SCHEME="http"
            SSL_HOST="${server_ip}"

            local bind_local=""
            if [[ "$NONINTERACTIVE" == "1" ]]; then
                # 云镜像必须保持在其公共接口上可访问。
                bind_local="n"
            else
                read -rp "是否将面板仅绑定到 127.0.0.1？（推荐——强制使用 SSH 隧道 / 反向代理访问）[y/N]：" bind_local
            fi
            if [[ "$bind_local" == "y" || "$bind_local" == "Y" ]]; then
                ${xui_folder}/x-ui setting -listenIP "127.0.0.1" > /dev/null 2>&1
                SSL_HOST="127.0.0.1"
                echo -e "${green}✓ 面板已仅绑定到 127.0.0.1。现在无法从公网访问。${plain}"
                echo ""
                echo -e "${green}SSH 端口转发——通过以下命令在本地机器打开面板：${plain}"
                echo -e "  标准 SSH 命令："
                echo -e "  ${yellow}ssh -L 2222:127.0.0.1:${panel_port} root@${server_ip}${plain}"
                echo -e "  如果使用 SSH 密钥："
                echo -e "  ${yellow}ssh -i <sshkeypath> -L 2222:127.0.0.1:${panel_port} root@${server_ip}${plain}"
                echo -e "  然后在浏览器中打开："
                echo -e "  ${yellow}http://localhost:2222/${web_base_path}${plain}"
                echo ""
                echo -e "${yellow}替代方案：将反向代理（nginx/Caddy）指向 127.0.0.1:${panel_port} 并让它终止 TLS。${plain}"
            else
                echo -e "${yellow}面板将在所有接口上以明文 HTTP 监听。请确保前面有其他东西在终止 TLS。${plain}"
            fi

            systemctl restart x-ui > /dev/null 2>&1 || rc-service x-ui restart > /dev/null 2>&1
            echo -e "${green}✓ 已跳过 SSL 设置。${plain}"
            ;;
        *)
            echo -e "${red}无效选项。跳过 SSL 设置。${plain}"
            SSL_HOST="${server_ip}"
            ;;
    esac
}

config_after_install() {
    local existing_hasDefaultCredential=$(${xui_folder}/x-ui setting -show true | grep -Eo 'hasDefaultCredential: .+' | awk '{print $2}')
    local existing_webBasePath=$(${xui_folder}/x-ui setting -show true | grep -Eo 'webBasePath: .+' | awk '{print $2}' | sed 's#^/##')
    local existing_port=$(${xui_folder}/x-ui setting -show true | grep -Eo 'port: .+' | awk '{print $2}')
    # 通过检查 cert: 行是否存在且其后面有内容来正确检测空证书
    local existing_cert=$(${xui_folder}/x-ui setting -getCert true | grep 'cert:' | awk -F': ' '{print $2}' | tr -d '[:space:]')
    local URL_lists=(
        "https://api4.ipify.org"
        "https://ipv4.icanhazip.com"
        "https://v4.api.ipinfo.io/ip"
        "https://ipv4.myexternalip.com/raw"
        "https://4.ident.me"
        "https://check-host.net/ip"
    )
    local server_ip=""
    for ip_address in "${URL_lists[@]}"; do
        local response=$(curl -s -w "\n%{http_code}" --max-time 3 "${ip_address}" 2> /dev/null)
        local http_code=$(echo "$response" | tail -n1)
        local ip_result=$(echo "$response" | head -n-1 | tr -d '[:space:]"')
        if [[ "${http_code}" == "200" && "${ip_result}" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
            server_ip="${ip_result}"
            break
        fi
    done

    if [[ -z "$server_ip" ]]; then
        if [[ "$NONINTERACTIVE" == "1" ]]; then
            # 面板无论如何都绑定到 0.0.0.0；IP 仅用于组装显示的访问 URL。
            # 回退到 XUI_SERVER_IP 或留空。
            server_ip="${XUI_SERVER_IP:-}"
        else
            echo -e "${yellow}无法从任何提供商自动检测服务器 IP。${plain}"
            while [[ -z "$server_ip" ]]; do
                read -rp "请输入您服务器的公网 IPv4 地址：" server_ip
                server_ip="${server_ip// /}"
                if [[ ! "$server_ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
                    echo -e "${red}无效的 IPv4 地址。请重试。${plain}"
                    server_ip=""
                fi
            done
        fi
    fi

    if [[ ${#existing_webBasePath} -lt 4 ]]; then
        if [[ "$existing_hasDefaultCredential" == "true" ]]; then
            local config_webBasePath="${XUI_WEB_BASE_PATH:-$(gen_random_string 18)}"
            local config_username="${XUI_USERNAME:-$(gen_random_string 10)}"
            local config_password="${XUI_PASSWORD:-$(gen_random_string 10)}"
            local config_port=""

            local db_label="SQLite (/etc/x-ui/x-ui.db)"
            echo ""
            echo -e "${green}═══════════════════════════════════════════${plain}"
            echo -e "${green}     数据库选择                          ${plain}"
            echo -e "${green}═══════════════════════════════════════════${plain}"
            echo -e "  1) SQLite     （默认——推荐用于客户端数 < 500）"
            echo -e "  2) PostgreSQL （推荐用于大量客户端 / 众多节点）"
            if [[ "$NONINTERACTIVE" == "1" ]]; then
                if [[ "${XUI_DB_TYPE:-sqlite}" == "postgres" ]]; then
                    db_choice="2"
                else
                    db_choice="1"
                fi
            else
                read -rp "请选择 [1]：" db_choice
                db_choice="${db_choice:-1}"
            fi
            if [[ "$db_choice" == "2" ]]; then
                local xui_env_file
                case "${release}" in
                    ubuntu | debian | armbian)
                        xui_env_file="/etc/default/x-ui"
                        ;;
                    arch | manjaro | parch | alpine)
                        xui_env_file="/etc/conf.d/x-ui"
                        ;;
                    *)
                        xui_env_file="/etc/sysconfig/x-ui"
                        ;;
                esac

                local xui_dsn=""
                local pg_mode=""
                local pg_local_installed=0
                while [[ -z "$xui_dsn" ]]; do
                    if [[ "$NONINTERACTIVE" == "1" ]]; then
                        if [[ -n "${XUI_DB_DSN:-}" ]]; then
                            xui_dsn="${XUI_DB_DSN}"
                            db_label="PostgreSQL（外部）"
                            break
                        fi
                        echo -e "${yellow}正在本地安装 PostgreSQL（非交互模式）...${plain}"
                        local pg_cred_file
                        pg_cred_file=$(mktemp 2> /dev/null) || pg_cred_file=$(mktemp -t x-ui-pg-creds.XXXXXXXX)
                        if [[ -n "${pg_cred_file}" ]] && xui_dsn=$(PG_CRED_FILE="${pg_cred_file}" install_postgres_local); then
                            pg_local_installed=1
                            if [[ -r "${pg_cred_file}" ]]; then
                                # shellcheck disable=SC1090
                                source "${pg_cred_file}"
                            fi
                            rm -f "${pg_cred_file}"
                            db_label="PostgreSQL（${PG_USER}@${PG_HOST}:${PG_PORT}/${PG_DB}）"
                            break
                        fi
                        rm -f "${pg_cred_file}"
                        echo -e "${red}非交互模式下 PostgreSQL 安装失败；中止。${plain}"
                        echo -e "${yellow}设置 XUI_DB_DSN 使用现有服务器，或设置 XUI_DB_TYPE=sqlite。${plain}"
                        exit 1
                    fi
                    echo ""
                    echo -e "  1) 本地安装 PostgreSQL 并创建专用用户/数据库（推荐）"
                    echo -e "  2) 使用现有 PostgreSQL 服务器（输入 DSN）"
                    read -rp "请选择 [1]：" pg_mode
                    pg_mode="${pg_mode:-1}"
                    if [[ "$pg_mode" == "2" ]]; then
                        while [[ -z "$xui_dsn" ]]; do
                            read -rp "输入 PostgreSQL DSN（postgres://user:pass@host:port/dbname?sslmode=disable）：" xui_dsn
                            xui_dsn="${xui_dsn// /}"
                        done
                        db_label="PostgreSQL（外部）"
                    else
                        echo -e "${yellow}正在安装 PostgreSQL——这可能需要一点时间...${plain}"
                        local pg_cred_file
                        pg_cred_file=$(mktemp 2> /dev/null) || pg_cred_file=$(mktemp -t x-ui-pg-creds.XXXXXXXX)
                        if [[ -z "${pg_cred_file}" ]]; then
                            echo -e "${red}创建临时凭据文件失败。${plain}"
                            xui_dsn=""
                            continue
                        fi
                        if xui_dsn=$(PG_CRED_FILE="${pg_cred_file}" install_postgres_local); then
                            pg_local_installed=1
                            if [[ -r "${pg_cred_file}" ]]; then
                                # shellcheck disable=SC1090
                                source "${pg_cred_file}"
                            fi
                            rm -f "${pg_cred_file}"
                            db_label="PostgreSQL（${PG_USER}@${PG_HOST}:${PG_PORT}/${PG_DB}）"
                        else
                            rm -f "${pg_cred_file}"
                            echo ""
                            echo -e "${red}PostgreSQL 安装失败。${plain}"
                            echo -e "  1) 重试本地安装"
                            echo -e "  2) 改为输入外部 DSN"
                            echo -e "  3) 中止安装"
                            echo -e "  4) 回退到 SQLite"
                            read -rp "请选择 [1]：" pg_fail
                            pg_fail="${pg_fail:-1}"
                            case "$pg_fail" in
                                2) pg_mode="2" ;;
                                3)
                                    echo -e "${red}安装已中止。${plain}"
                                    exit 1
                                    ;;
                                4)
                                    db_choice="1"
                                    xui_dsn=""
                                    break
                                    ;;
                                *) xui_dsn="" ;;
                            esac
                        fi
                    fi
                done
                if [[ -n "$xui_dsn" ]]; then
                    install -d -m 755 "$(dirname "$xui_env_file")"
                    umask 077
                    cat > "$xui_env_file" << EOF
XUI_DB_TYPE=postgres
XUI_DB_DSN=${xui_dsn}
EOF
                    chmod 600 "$xui_env_file"
                    umask 022
                    export XUI_DB_TYPE=postgres
                    export XUI_DB_DSN="${xui_dsn}"
                    ensure_pg_client || echo -e "${yellow}⚠ 无法安装 pg_dump/pg_restore。面板内数据库备份/恢复将不可用，直到您安装 postgresql-client 包。${plain}"
                fi
            fi

            if [[ "$NONINTERACTIVE" == "1" ]]; then
                if [[ -n "${XUI_PANEL_PORT:-}" ]]; then
                    config_port="${XUI_PANEL_PORT}"
                    echo -e "${yellow}您的面板端口为：${config_port}${plain}"
                else
                    config_port=$(shuf -i 1024-62000 -n 1)
                    echo -e "${yellow}已生成随机端口：${config_port}${plain}"
                fi
            else
                read -rp "您是否要自定义面板端口设置？（如果不，将应用随机端口）[y/n]：" config_confirm
                if [[ "${config_confirm}" == "y" || "${config_confirm}" == "Y" ]]; then
                    read -rp "请设置面板端口：" config_port
                    echo -e "${yellow}您的面板端口为：${config_port}${plain}"
                else
                    config_port=$(shuf -i 1024-62000 -n 1)
                    echo -e "${yellow}已生成随机端口：${config_port}${plain}"
                fi
            fi

            ${xui_folder}/x-ui setting -username "${config_username}" -password "${config_password}" -port "${config_port}" -webBasePath "${config_webBasePath}"

            echo ""
            echo -e "${green}═══════════════════════════════════════════${plain}"
            echo -e "${green}     SSL 证书设置（推荐）                   ${plain}"
            echo -e "${green}═══════════════════════════════════════════${plain}"
            echo -e "${yellow}强烈推荐启用 SSL。仅当反向代理或 SSH 隧道为您处理 TLS 时才可跳过。${plain}"
            echo -e "${yellow}Let's Encrypt 现在同时支持域名和 IP 地址！${plain}"
            echo ""

            prompt_and_setup_ssl "${config_port}" "${config_webBasePath}" "${server_ip}"

            # 获取 API Token 以供显示
            local config_apiToken=$(${xui_folder}/x-ui setting -getApiToken | grep -Eo 'apiToken: .+' | awk '{print $2}')

            # 显示最终凭据和访问信息
            echo ""
            echo -e "${green}═══════════════════════════════════════════${plain}"
            echo -e "${green}     面板安装完成！                        ${plain}"
            echo -e "${green}═══════════════════════════════════════════${plain}"
            echo -e "${green}用户名：    ${config_username}${plain}"
            echo -e "${green}密码：      ${config_password}${plain}"
            echo -e "${green}端口：      ${config_port}${plain}"
            echo -e "${green}Web基础路径：${config_webBasePath}${plain}"
            echo -e "${green}数据库：    ${db_label}${plain}"
            echo -e "${green}访问地址：  ${SSL_SCHEME}://${SSL_HOST}:${config_port}/${config_webBasePath}${plain}"
            echo -e "${green}API Token： ${config_apiToken}${plain}"
            echo -e "${green}═══════════════════════════════════════════${plain}"
            echo -e "${yellow}⚠ 重要：请妥善保存这些凭据！${plain}"
            if [[ "$SSL_SCHEME" == "https" ]]; then
                echo -e "${yellow}⚠ SSL 证书：已启用并配置${plain}"
            else
                echo -e "${yellow}⚠ SSL 证书：已跳过——面板仅 HTTP。请使用反向代理或 SSH 隧道。${plain}"
            fi

            if [[ "$db_choice" == "2" ]]; then
                echo ""
                echo -e "${green}面板内置了 PostgreSQL 备份与恢复：${plain}"
                echo -e "  ${blue}${SSL_SCHEME}://${SSL_HOST}:${config_port}/${config_webBasePath}${plain} → 备份与恢复"
                echo -e "${yellow}  备份会下载 pg_dump .dump 文件；恢复通过 pg_restore 重新加载。${plain}"
            fi

            if [[ "$db_choice" == "2" && "$pg_local_installed" == "1" ]]; then
                echo ""
                echo -e "${green}═══════════════════════════════════════════${plain}"
                echo -e "${green}     PostgreSQL 凭据                       ${plain}"
                echo -e "${green}═══════════════════════════════════════════${plain}"
                echo -e "${green}数据库名：  ${PG_DB}${plain}"
                echo -e "${green}用户名：    ${PG_USER}${plain}"
                echo -e "${green}密码：      ${PG_PASS}${plain}"
                echo -e "${green}主机：      ${PG_HOST}${plain}"
                echo -e "${green}端口：      ${PG_PORT}${plain}"
                echo -e "${green}DSN：       ${xui_dsn}${plain}"
                echo -e "${green}环境文件：  ${xui_env_file}${plain}"
                echo -e "${green}-------------------------------------------${plain}"
                echo -e "${green}从本服务器连接：${plain}"
                echo -e "  ${blue}sudo -u postgres psql -d ${PG_DB}${plain}      （作为 postgres 超级用户）"
                echo -e "  ${blue}PGPASSWORD='${PG_PASS}' psql -h ${PG_HOST} -p ${PG_PORT} -U ${PG_USER} -d ${PG_DB}${plain}"
                echo -e "${green}═══════════════════════════════════════════${plain}"
                echo -e "${yellow}⚠ 面板从 ${xui_env_file} 读取这些凭据。${plain}"
                echo -e "${yellow}⚠ 请保存密码——它不会以明文形式存储在其他任何地方。${plain}"
                unset PG_USER PG_PASS PG_HOST PG_PORT PG_DB
            fi

            # 为 cloud-init / MOTD 持久化一个机器可解析的凭据文件。
            : "${SSL_SCHEME:=https}"
            : "${SSL_HOST:=${server_ip}}"
            local db_type_out="sqlite"
            [[ "$db_choice" == "2" ]] && db_type_out="postgres"
            write_install_result "${config_username}" "${config_password}" "${config_port}" \
                "${config_webBasePath}" "${SSL_SCHEME}" "${SSL_HOST}" "${config_apiToken}" "${db_type_out}"
        else
            local config_webBasePath=$(gen_random_string 18)
            echo -e "${yellow}WebBasePath 缺失或过短。正在生成新的...${plain}"
            ${xui_folder}/x-ui setting -webBasePath "${config_webBasePath}"
            echo -e "${green}新的 WebBasePath：${config_webBasePath}${plain}"

            # 如果面板已安装但未配置证书，则现在提示设置 SSL
            if [[ -z "${existing_cert}" ]]; then
                echo ""
                echo -e "${green}═══════════════════════════════════════════${plain}"
                echo -e "${green}     SSL 证书设置（推荐）                   ${plain}"
                echo -e "${green}═══════════════════════════════════════════${plain}"
                echo -e "${yellow}Let's Encrypt 现在同时支持域名和 IP 地址！${plain}"
                echo ""
                prompt_and_setup_ssl "${existing_port}" "${config_webBasePath}" "${server_ip}"
                echo -e "${green}访问地址：  ${SSL_SCHEME}://${SSL_HOST}:${existing_port}/${config_webBasePath}${plain}"
            else
                # 如果证书已存在，仅显示访问 URL
                echo -e "${green}访问地址：https://${server_ip}:${existing_port}/${config_webBasePath}${plain}"
            fi
        fi
    else
        if [[ "$existing_hasDefaultCredential" == "true" ]]; then
            local config_username="${XUI_USERNAME:-$(gen_random_string 10)}"
            local config_password="${XUI_PASSWORD:-$(gen_random_string 10)}"

            echo -e "${yellow}检测到默认凭据。需要进行安全更新...${plain}"
            ${xui_folder}/x-ui setting -username "${config_username}" -password "${config_password}"
            echo -e "已生成新的随机登录凭据："
            echo -e "###############################################"
            echo -e "${green}用户名：${config_username}${plain}"
            echo -e "${green}密码：  ${config_password}${plain}"
            echo -e "###############################################"

            # 为 cloud-init / MOTD 持久化一个机器可解析的凭据文件。
            local config_apiToken
            config_apiToken=$(${xui_folder}/x-ui setting -getApiToken | grep -Eo 'apiToken: .+' | awk '{print $2}')
            : "${SSL_SCHEME:=https}"
            : "${SSL_HOST:=${server_ip}}"
            write_install_result "${config_username}" "${config_password}" "${existing_port}" \
                "${existing_webBasePath}" "${SSL_SCHEME}" "${SSL_HOST}" "${config_apiToken}" "${XUI_DB_TYPE:-sqlite}"
        else
            echo -e "${green}用户名、密码和 WebBasePath 已正确设置。${plain}"
        fi

        # 现有安装：如果未配置证书，则提示用户进行 SSL 设置
        # 通过检查 cert: 行是否存在且其后面有内容来正确检测空证书
        existing_cert=$(${xui_folder}/x-ui setting -getCert true | grep 'cert:' | awk -F': ' '{print $2}' | tr -d '[:space:]')
        if [[ -z "$existing_cert" ]]; then
            echo ""
            echo -e "${green}═══════════════════════════════════════════${plain}"
            echo -e "${green}     SSL 证书设置（推荐）                   ${plain}"
            echo -e "${green}═══════════════════════════════════════════${plain}"
            echo -e "${yellow}Let's Encrypt 现在同时支持域名和 IP 地址！${plain}"
            echo ""
            prompt_and_setup_ssl "${existing_port}" "${existing_webBasePath}" "${server_ip}"
            echo -e "${green}访问地址：  ${SSL_SCHEME}://${SSL_HOST}:${existing_port}/${existing_webBasePath}${plain}"
        else
            echo -e "${green}SSL 证书已配置。无需操作。${plain}"
        fi
    fi

    ${xui_folder}/x-ui migrate
}

# setup_fail2ban 通过调用刚安装的 x-ui CLI 自动安装并配置 fail2ban 以支持
# IP 限制功能。IP 限制依赖 fail2ban（没有它，面板会禁用 limitIp 字段并将现有
# 限制归零），因此全新安装应开箱即用，就像 Docker 镜像已经做的那样。
# 设计上为非致命：fail2ban 失败绝不能中止面板安装。
setup_fail2ban() {
    if [[ -n "${XUI_ENABLE_FAIL2BAN+x}" && "${XUI_ENABLE_FAIL2BAN}" != "true" ]]; then
        echo -e "${yellow}XUI_ENABLE_FAIL2BAN=${XUI_ENABLE_FAIL2BAN}，跳过 Fail2ban 自动设置。${plain}"
        return 0
    fi

    if [[ ! -x /usr/bin/x-ui ]]; then
        echo -e "${yellow}未找到 x-ui CLI；跳过 Fail2ban 自动设置。${plain}"
        return 0
    fi

    # 早于 v3.4.0 的脚本没有 setup-fail2ban 并从用法横幅中以 0 退出，
    # 这在此处会被误读为成功。
    if ! grep -q '"setup-fail2ban")' /usr/bin/x-ui; then
        echo -e "${yellow}此 x-ui.sh 早于 'x-ui setup-fail2ban'；跳过 Fail2ban 自动设置。${plain}"
        return 0
    fi

    echo -e "${green}正在为 IP 限制功能设置 Fail2ban...${plain}"
    if /usr/bin/x-ui setup-fail2ban; then
        echo -e "${green}Fail2ban 设置完成。${plain}"
    else
        echo -e "${yellow}Fail2ban 设置未完成；IP 限制将保持禁用，直到您运行 'x-ui' 并打开 IP 限制菜单。继续。${plain}"
    fi
    return 0
}

# 通过临时文件 + 原子 mv 将 systemd 单元文件放置到 ${xui_service}/x-ui.service，
# 这样 cp/curl 失败或 mv 被中断都不会在实时路径留下截断的单元文件——
# systemd 在下一次 daemon-reload/start 时将无法解析它。与脚本中其他地方对
# /usr/bin/x-ui 使用的模式相同。source_is_url 选择 cp（从已从发布 tarball
# 解压的文件）还是 curl（GitHub 回退）。
_install_xui_service_unit() {
    local source="$1"
    local source_is_url="$2"
    local dest="${xui_service}/x-ui.service"
    local temp_file="${dest}.tmp.$$"

    rm -f "$temp_file"
    if [[ "$source_is_url" == "true" ]]; then
        curl -fLRo "$temp_file" "$source" > /dev/null 2>&1
    else
        cp -f "$source" "$temp_file" > /dev/null 2>&1
    fi
    if [[ $? -ne 0 ]]; then
        rm -f "$temp_file"
        return 1
    fi
    if [[ ! -s "$temp_file" ]]; then
        rm -f "$temp_file"
        return 1
    fi
    mv -f "$temp_file" "$dest"
    if [[ $? -ne 0 ]]; then
        rm -f "$temp_file"
        return 1
    fi
    return 0
}

# resolve_latest_tag 打印最新稳定发布标签。它优先使用 web
# releases/latest 重定向，因为该方式不受未认证 API 每 IP 每小时 60 次请求的
# 限制影响（共享 CI/CGNAT 地址会触发该限制，导致安装失败并提示
# "Failed to fetch x-ui version"），并以 API 作为回退。
resolve_latest_tag() {
    local url tag
    url=$(curl -sSLI -o /dev/null -w '%{url_effective}' --retry 5 --retry-delay 3 --connect-timeout 15 --max-time 60 "https://github.com/MHSanaei/3x-ui/releases/latest" 2>/dev/null)
    tag=${url##*/tag/}
    if [[ "$tag" != "$url" && -n "$tag" && "$tag" != "latest" ]]; then
        echo "$tag"
        return 0
    fi
    curl -Ls --retry 5 --retry-delay 3 --connect-timeout 15 --max-time 60 "https://api.github.com/repos/MHSanaei/3x-ui/releases/latest" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/'
}

# 发布会在每个归档旁发布 <asset>.sha256。校验和不匹配或 sidecar 下载失败
# 会中止安装；只有 404（早于 sidecar 的旧版本发布）会以警告方式容忍。
verify_release_checksum() {
    local url="$1" file="$2" sums="$2.sha256" code expected actual
    rm -f "${sums}"
    code=$(curl -sL --retry 3 --retry-delay 3 --connect-timeout 15 --max-time 60 -o "${sums}" -w '%{http_code}' "${url}.sha256")
    if [[ "${code}" == "404" ]]; then
        rm -f "${sums}"
        echo -e "${yellow}此版本未发布校验和，跳过验证${plain}"
        return 0
    fi
    if [[ "${code}" != "200" ]]; then
        rm -f "${sums}" "${file}"
        echo -e "${red}下载 $(basename "${file}") 的校验和失败（HTTP ${code}）${plain}"
        exit 1
    fi
    expected=$(awk 'NR == 1 {print $1}' "${sums}")
    actual=$(sha256sum "${file}" | awk '{print $1}')
    rm -f "${sums}"
    if [[ ! "${expected}" =~ ^[0-9a-f]{64}$ || "${expected}" != "${actual}" ]]; then
        rm -f "${file}"
        echo -e "${red}$(basename "${file}") 校验和不匹配：期望 ${expected:-<无>}，实际 ${actual}${plain}"
        exit 1
    fi
    echo -e "${green}校验和已验证：${actual}${plain}"
}

# 较早的标签早于其中一些文件（x-ui.rc 在 v2.8.4 才加入）。将 main 的副本
# 用于旧二进制正是此固定所要防止的不匹配，因此在停止或删除任何内容之前
# 先探测并拒绝该标签。
require_repo_files() {
    local ref="$1" name status
    shift
    [[ "${ref}" == "main" ]] && return 0
    for name in "$@"; do
        status=$(curl -sIL --retry 3 --connect-timeout 15 -o /dev/null -w '%{http_code}' "https://raw.githubusercontent.com/MHSanaei/3x-ui/${ref}/${name}")
        if [[ "${status}" != "200" ]]; then
            echo -e "${red}${name} 不适用于 ${ref}（HTTP ${status}）${plain}"
            echo -e "${red}请安装包含它的版本，或使用 'dev' 获取滚动构建。您现有的安装未被修改。${plain}"
            exit 1
        fi
    done
}

install_x-ui() {
    cd ${xui_folder%/x-ui}/

    # 下载资源
    if [ $# == 0 ]; then
        tag_version=$(resolve_latest_tag)
        if [[ ! -n "$tag_version" ]]; then
            echo -e "${red}获取 x-ui 版本失败，可能是 GitHub API 限制导致，请稍后重试${plain}"
            exit 1
        fi
        echo -e "已获取 x-ui 最新版本：${tag_version}，开始安装..."
        curl -fLR --retry 5 --retry-delay 3 --connect-timeout 15 --speed-limit 1 --speed-time 300 -o ${xui_folder}-linux-$(arch).tar.gz https://github.com/MHSanaei/3x-ui/releases/download/${tag_version}/x-ui-linux-$(arch).tar.gz
        if [[ $? -ne 0 ]]; then
            echo -e "${red}下载 x-ui 失败，请确保您的服务器可以访问 GitHub ${plain}"
            exit 1
        fi
        if [[ ! -s ${xui_folder}-linux-$(arch).tar.gz ]]; then
            rm ${xui_folder}-linux-$(arch).tar.gz -f
            echo -e "${red}下载的 x-ui 发布归档为空${plain}"
            exit 1
        fi
        verify_release_checksum "https://github.com/MHSanaei/3x-ui/releases/download/${tag_version}/x-ui-linux-$(arch).tar.gz" "${xui_folder}-linux-$(arch).tar.gz"
    else
        tag_version=$1
        # 滚动 dev 通道以固定的、非语义化标签发布，该标签在每次推送时
        # 被强制移动到最新的 main 提交。接受 `dev` 作为便捷别名，
        # 并对其跳过数字下限检查。
        if [[ "$tag_version" == "dev" || "$tag_version" == "dev-latest" ]]; then
            tag_version="dev-latest"
            echo -e "${yellow}正在安装滚动 dev 构建（标签：dev-latest）。这是每次提交的预发布版本，不是稳定版本。${plain}"
        else
            tag_version_numeric=${tag_version#v}
            min_version="2.3.5"

            if [[ "$(printf '%s\n' "$min_version" "$tag_version_numeric" | sort -V | head -n1)" != "$min_version" ]]; then
                echo -e "${red}请使用更新的版本（至少 v2.3.5）。退出安装。${plain}"
                exit 1
            fi
        fi

        url="https://github.com/MHSanaei/3x-ui/releases/download/${tag_version}/x-ui-linux-$(arch).tar.gz"
        echo -e "开始安装 x-ui ${tag_version}"
        curl -fLR --retry 5 --retry-delay 3 --connect-timeout 15 --speed-limit 1 --speed-time 300 -o ${xui_folder}-linux-$(arch).tar.gz ${url}
        if [[ $? -ne 0 ]]; then
            echo -e "${red}下载 x-ui ${tag_version} 失败，请检查该版本是否存在 ${plain}"
            exit 1
        fi
        if [[ ! -s ${xui_folder}-linux-$(arch).tar.gz ]]; then
            rm ${xui_folder}-linux-$(arch).tar.gz -f
            echo -e "${red}下载的 x-ui 发布归档为空${plain}"
            exit 1
        fi
        verify_release_checksum "${url}" "${xui_folder}-linux-$(arch).tar.gz"
    fi
    # x-ui.sh、x-ui.rc 和单元文件必须与二进制来自同一版本；
    # 只有滚动 dev 构建跟踪 main。
    local script_ref="${tag_version}"
    if [[ "${tag_version}" == "dev-latest" ]]; then
        script_ref="main"
    fi
    # 仅当发布 tarball 缺少单元文件时才获取它们，因此它们在那时才检查，
    # 而不是在此处。
    local required_files=("x-ui.sh")
    [[ $release == "alpine" ]] && required_files+=("x-ui.rc")
    require_repo_files "${script_ref}" "${required_files[@]}"
    local xui_script_temp="/usr/bin/x-ui-temp.$$"
    rm -f "${xui_script_temp}"
    curl -fLRo "${xui_script_temp}" "https://raw.githubusercontent.com/MHSanaei/3x-ui/${script_ref}/x-ui.sh"
    if [[ $? -ne 0 ]]; then
        rm -f "${xui_script_temp}"
        echo -e "${red}下载 x-ui.sh 失败${plain}"
        exit 1
    fi
    if [[ ! -s "${xui_script_temp}" ]]; then
        rm -f "${xui_script_temp}"
        echo -e "${red}下载的 x-ui.sh 为空${plain}"
        exit 1
    fi

    # 停止 x-ui 服务并删除旧资源
    local custom_bin_backup=""
    if [[ -e ${xui_folder}/ ]]; then
        if [[ $release == "alpine" ]]; then
            rc-service x-ui stop
        else
            systemctl stop x-ui
        fi
        # 终止所有残留的 mtg（MTProto）sidecar。x-ui 在其自身生命周期之外运行它们，
        # 因此在 Linux 上，陈旧的实例可能在 stop 后存活并继续以过期的 secret
        # 占用入站端口，从而静默地破坏新客户端。新安装的面板在启动时会为每个
        # 入站重新生成干净的 mtg。
        pkill -f 'mtg-linux-[^ ]* run ' > /dev/null 2>&1 || true
        pkill -f 'tuic-server.*-c .*bin/tuic/tuic_[0-9]+\.json' > /dev/null 2>&1 || true

        # 下面的 tar 解压将整体清除 bin/。发布只附带已知资源（xray/mtg 二进制、
        # 捆绑的 geoip*/geosite*.dat 集合）——bin/ 中其他任何东西都是管理员放置的
        # （例如通过路由规则中的 "ext:<file>:<code>" 引用的手动添加的自定义
        # geoip/geosite 文件），否则会在每次更新时被静默删除，导致下次启动时
        # Xray 因任何引用它的路由规则而失败并报 "failed to open <file>: no such
        # file or directory"。这里采用移动而非复制：同一文件系统上的重命名是
        # 原子的（如果磁盘空间在中途耗尽，不像 `cp` 会产生截断文件），并将快照
        # 保存在 /usr/local 下，而不是可能很小或位于 tmpfs 的 $TMPDIR 中。
        if [[ -d "${xui_folder}/bin" ]]; then
            custom_bin_backup="${xui_folder%/x-ui}/x-ui-bin-backup.$$"
            rm -rf "${custom_bin_backup}"
            if ! mv "${xui_folder}/bin" "${custom_bin_backup}"; then
                custom_bin_backup=""
                echo -e "${yellow}无法备份 bin/——其中的自定义文件在本次更新中不会被保留${plain}"
            fi
        fi
        # 从这里开始这是备份的唯一清理路径——同时覆盖下面两个 `exit 1`
        # （解压/二进制缺失失败）以及在恢复运行之前被中断的更新
        # （Ctrl-C、信号）。在下面的恢复正常完成后清除。
        trap '[[ -n "${custom_bin_backup}" ]] && rm -rf "${custom_bin_backup}"' EXIT INT TERM
        rm ${xui_folder}/ -rf
    fi

    # 解压资源并设置权限
    tar zxvf x-ui-linux-$(arch).tar.gz
    if [[ $? -ne 0 ]]; then
        rm x-ui-linux-$(arch).tar.gz -f
        rm -f "${xui_script_temp}"
        echo -e "${red}解压 x-ui 发布归档失败——之前的安装已被删除，因此在修复前面板不会启动；请尝试再次运行安装程序${plain}"
        exit 1
    fi
    rm x-ui-linux-$(arch).tar.gz -f

    cd x-ui
    if [[ $? -ne 0 || ! -s x-ui ]]; then
        rm -f "${xui_script_temp}"
        echo -e "${red}解压后的 x-ui 归档缺少 x-ui 二进制——之前的安装已被删除，因此在修复前面板不会启动；请尝试再次运行安装程序${plain}"
        exit 1
    fi
    chmod +x x-ui
    chmod +x x-ui.sh

    # 检查系统架构并相应重命名文件。
    # 面板二进制将 GOARCH=arm 映射为 "arm32"（internal/xray/process.go），
    # 因此 Xray 二进制必须命名为 xray-linux-arm32；mtg 保持纯 "arm"。
    if [[ $(arch) == "armv5" || $(arch) == "armv6" || $(arch) == "armv7" ]]; then
        mv bin/xray-linux-$(arch) bin/xray-linux-arm32
        chmod +x bin/xray-linux-arm32
        if [[ -f bin/mtg-linux-$(arch) ]]; then
            mv bin/mtg-linux-$(arch) bin/mtg-linux-arm
            chmod +x bin/mtg-linux-arm
        fi
    fi
    chmod +x x-ui bin/xray-linux-$(arch)
    if [[ -f bin/mtg-linux-arm ]]; then
        chmod +x bin/mtg-linux-arm
    elif [[ -f bin/mtg-linux-$(arch) ]]; then
        chmod +x bin/mtg-linux-$(arch)
    fi

    # 从旧 bin/ 恢复新发布未附带的任何内容（自定义 geoip/geosite 文件，
    # 或管理员手动放置的其他任何东西）——绝不覆盖新发布提供的同名文件，
    # 因此捆绑的资源（geoip.dat、geoip_RU.dat 等）仍然获得每个版本的全新副本。
    # 在上面的架构重命名之后运行，因此 xray-linux-arm32/mtg-linux-arm 已经
    # 以最终名称存在，不会被误认为是需要恢复的自定义文件。跳过面板自身在
    # 运行时重新生成的路径（config.json、mtproto/*.toml——见
    # internal/xray/process.go、internal/mtproto/manager.go）：那些不是管理员
    # 放置的，恢复陈旧的只会复活无效状态（已删除入站的孤立 mtg 配置）或
    # 错误的目录权限。
    if [[ -n "${custom_bin_backup}" ]]; then
        local restored_custom_bin=()
        while IFS= read -r -d '' f; do
            local rel="${f#"${custom_bin_backup}"/}"
            case "${rel}" in
                config.json | mtproto | mtproto/* | tuic | tuic/* | tuic-server | tuic-server-*) continue ;;
            esac
            if [[ ! -e "bin/${rel}" ]]; then
                mkdir -p "bin/$(dirname "${rel}")"
                cp -a "${f}" "bin/${rel}"
                restored_custom_bin+=("${rel}")
            fi
        done < <(find "${custom_bin_backup}" \( -type f -o -type l \) -print0)
        rm -rf "${custom_bin_backup}"
        custom_bin_backup=""
        if [[ ${#restored_custom_bin[@]} -gt 0 ]]; then
            echo -e "${green}已恢复此版本未附带的 bin/ 中的自定义文件：${restored_custom_bin[*]}${plain}"
        fi
    fi
    trap - EXIT INT TERM

    rm -f bin/tuic-server bin/tuic-server-* > /dev/null 2>&1 || true
    rm -rf bin/tuic > /dev/null 2>&1 || true

    # 更新 x-ui CLI 并设置权限
    mv -f "${xui_script_temp}" /usr/bin/x-ui
    if [[ $? -ne 0 ]]; then
        rm -f "${xui_script_temp}"
        echo -e "${red}安装 x-ui.sh 失败${plain}"
        exit 1
    fi
    chmod +x /usr/bin/x-ui
    mkdir -p /var/log/x-ui
    config_after_install

    # Etckeeper 兼容性
    if [ -d "/etc/.git" ]; then
        if [ -f "/etc/.gitignore" ]; then
            if ! grep -q "x-ui/x-ui.db" "/etc/.gitignore"; then
                echo "" >> "/etc/.gitignore"
                echo "x-ui/x-ui.db" >> "/etc/.gitignore"
                echo -e "${green}已为 etckeeper 将 x-ui.db 添加到 /etc/.gitignore${plain}"
            fi
        else
            echo "x-ui/x-ui.db" > "/etc/.gitignore"
            echo -e "${green}已创建 /etc/.gitignore 并为 etckeeper 添加 x-ui.db${plain}"
        fi
    fi

    if [[ $release == "alpine" ]]; then
        xui_rc_temp="/etc/init.d/x-ui.tmp.$$"
        rm -f "${xui_rc_temp}"
        curl -fLRo "${xui_rc_temp}" "https://raw.githubusercontent.com/MHSanaei/3x-ui/${script_ref}/x-ui.rc"
        if [[ $? -ne 0 ]]; then
            rm -f "${xui_rc_temp}"
            echo -e "${red}下载 x-ui.rc 失败${plain}"
            exit 1
        fi
        if [[ ! -s "${xui_rc_temp}" ]]; then
            rm -f "${xui_rc_temp}"
            echo -e "${red}下载的 x-ui.rc 为空${plain}"
            exit 1
        fi
        mv -f "${xui_rc_temp}" /etc/init.d/x-ui
        if [[ $? -ne 0 ]]; then
            rm -f "${xui_rc_temp}"
            echo -e "${red}安装 x-ui.rc 失败${plain}"
            exit 1
        fi
        chmod +x /etc/init.d/x-ui
        rc-update add x-ui
        rc-service x-ui start
    else
        # 安装 systemd 服务文件
        service_installed=false

        if [ -f "x-ui.service" ]; then
            echo -e "${green}在解压文件中找到 x-ui.service，正在安装...${plain}"
            if _install_xui_service_unit "x-ui.service" "false"; then
                service_installed=true
            fi
        fi

        if [ "$service_installed" = false ]; then
            case "${release}" in
                ubuntu | debian | armbian)
                    if [ -f "x-ui.service.debian" ]; then
                        echo -e "${green}在解压文件中找到 x-ui.service.debian，正在安装...${plain}"
                        if _install_xui_service_unit "x-ui.service.debian" "false"; then
                            service_installed=true
                        fi
                    fi
                    ;;
                arch | manjaro | parch)
                    if [ -f "x-ui.service.arch" ]; then
                        echo -e "${green}在解压文件中找到 x-ui.service.arch，正在安装...${plain}"
                        if _install_xui_service_unit "x-ui.service.arch" "false"; then
                            service_installed=true
                        fi
                    fi
                    ;;
                *)
                    if [ -f "x-ui.service.rhel" ]; then
                        echo -e "${green}在解压文件中找到 x-ui.service.rhel，正在安装...${plain}"
                        if _install_xui_service_unit "x-ui.service.rhel" "false"; then
                            service_installed=true
                        fi
                    fi
                    ;;
            esac
        fi

        # 如果 tar.gz 中未找到服务文件，则从 GitHub 下载
        if [ "$service_installed" = false ]; then
            echo -e "${yellow}tar.gz 中未找到服务文件，正在从 GitHub 下载...${plain}"
            case "${release}" in
                ubuntu | debian | armbian)
                    service_unit_url="https://raw.githubusercontent.com/MHSanaei/3x-ui/${script_ref}/x-ui.service.debian"
                    ;;
                arch | manjaro | parch)
                    service_unit_url="https://raw.githubusercontent.com/MHSanaei/3x-ui/${script_ref}/x-ui.service.arch"
                    ;;
                *)
                    service_unit_url="https://raw.githubusercontent.com/MHSanaei/3x-ui/${script_ref}/x-ui.service.rhel"
                    ;;
            esac

            if ! _install_xui_service_unit "$service_unit_url" "true"; then
                echo -e "${red}从 GitHub 安装 x-ui.service 失败（${script_ref}）——发布 tarball 也未附带该文件${plain}"
                exit 1
            fi
            service_installed=true
        fi

        if [ "$service_installed" = true ]; then
            echo -e "${green}正在设置 systemd 单元...${plain}"
            chown root:root ${xui_service}/x-ui.service > /dev/null 2>&1
            chmod 644 ${xui_service}/x-ui.service > /dev/null 2>&1
            systemctl daemon-reload
            systemctl enable x-ui
            systemctl start x-ui
        else
            echo -e "${red}安装 x-ui.service 文件失败${plain}"
            exit 1
        fi
    fi

    # IP 限制依赖 fail2ban；现在安装并配置它，使该功能开箱即用
    # （XUI_ENABLE_FAIL2BAN=false 时为空操作）。绝不为致命错误。
    setup_fail2ban

    echo -e "${green}x-ui ${tag_version}${plain} 安装完成，正在运行中..."
    echo -e ""
    echo -e "┌───────────────────────────────────────────────────────┐
│  ${blue}x-ui 控制菜单用法（子命令）：${plain}                    │
│                                                       │
│  ${blue}x-ui${plain}              - 管理脚本                          │
│  ${blue}x-ui start${plain}        - 启动                              │
│  ${blue}x-ui stop${plain}         - 停止                              │
│  ${blue}x-ui restart${plain}      - 重启                              │
│  ${blue}x-ui status${plain}       - 当前状态                          │
│  ${blue}x-ui settings${plain}     - 当前设置                          │
│  ${blue}x-ui enable${plain}       - 启用开机自启                      │
│  ${blue}x-ui disable${plain}      - 禁用开机自启                      │
│  ${blue}x-ui log${plain}          - 查看日志                          │
│  ${blue}x-ui banlog${plain}       - 查看 Fail2ban 封禁日志             │
│  ${blue}x-ui update${plain}       - 更新                              │
│  ${blue}x-ui legacy${plain}       - 旧版                              │
│  ${blue}x-ui install${plain}      - 安装                              │
│  ${blue}x-ui uninstall${plain}    - 卸载                              │
└───────────────────────────────────────────────────────┘"
}

echo -e "${green}正在运行...${plain}"
install_base
install_x-ui $1
