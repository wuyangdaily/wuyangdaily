## 📚 目录

| [Docker install](#ubuntu-server-docker-compose-install) | [Docker update](#ubuntu-server-docker-compose-update) | [SSH](#ssh登陆页面) | [MoviePilot](#moviepilot) | [Emby](#emby) | [Qbittorrent](#qbittorrent) | [Neko-master](#neko-master) | [AssppWeb](#assppweb) |
|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|
| [Harvest](#harvest) | [Sun-panel](#sun-panel) | [NginxProxyManager](#nginxproxymanager) | [Portainer](#portainer) | [Lucky](#lucky) | [Cloudreve](#cloudreve) | [Wxchat](#wxchat) | [Wechat](#wechat) |
| [Certimate](#certimate) | [Komari](#komari-主题) | [Agent](#agentuninstall) | [NodeCtl](#nodectl) | [Moments-blog](#moments-blog) | [Mihomo](#mihomo-配置) | [Sub-Store](#sub-store订阅转换) | [Miaospeed](#miaospeed测速后端) |
| [Koipy](#koipy机器人后端配置) | [配置文件](#配置文件) |  |  |  |  |  |

## Ubuntu Server Docker Compose install
```bash
bash <(curl -sL https://url.wuyang.skin/Docker)
```
```bash
bash <(curl -sL https://url.wuyang.skin/GitDel)
```
```bash
sudo apt update && sudo apt install -y ca-certificates curl gnupg && \
sudo install -m 0755 -d /etc/apt/keyrings && \
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg && \
sudo chmod a+r /etc/apt/keyrings/docker.gpg && \
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null && \
sudo apt update && \
sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin && \
sudo systemctl enable --now docker && \
docker version && docker compose version
```

## Ubuntu Server Docker Compose update
```bash
sudo apt update && \
sudo apt full-upgrade -y && \
sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin && \
sudo systemctl restart docker && \
docker version && docker compose version
```

## SSH登陆页面
```bash
bash <(curl -sL https://url.wuyang.skin/CN)
```
```bash
bash <(curl -sL https://url.wuyang.skin/MOTD)
```
**Debian,Ubuntu,Armbian** 系统禁用自带登录信息
```bash
grep -q '^[#]*\s*PrintLastLog' /etc/ssh/sshd_config && sed -i 's/^[#]*\s*PrintLastLog.*/PrintLastLog no/' /etc/ssh/sshd_config || echo 'PrintLastLog no' >> /etc/ssh/sshd_config && chmod -x /etc/update-motd.d/* && systemctl restart ssh
```

新建脚本
```bash
sudo touch /etc/profile.d/custom-motd.sh
```

编辑脚本
```bash
nano /etc/profile.d/custom-motd.sh
```

赋予权限
```bash
chmod +x /etc/profile.d/custom-motd.sh
```

刷新当前环境查看脚本效果
```bash
source /etc/profile.d/custom-motd.sh
```

脚本内容
```bash
#!/bin/bash

# 1. 核心逻辑：防止 sudo 切换时重复显示
# 如果是从 mac 用户通过 sudo -i 进来的，直接退出，不显示第二次
[ -n "$SUDO_USER" ] && return

# 颜色定义
GREEN='\033[1;32m'; CYAN='\033[1;96m'
YELLOW='\033[1;33m'; RED='\033[1;31m'; RESET='\033[0m'

# 2. 基础信息采集
USER_NAME=$(whoami)
HOSTNAME=$(hostname)
OS_VER=$(grep "PRETTY_NAME" /etc/os-release | cut -d '"' -f 2)

# 时间与星期
CURRENT_DATE=$(date '+%Y-%m-%d %H:%M:%S')
WEEKDAY_NUM=$(date '+%u')
case "$WEEKDAY_NUM" in
    1) WEEKDAY="星期一" ;; 2) WEEKDAY="星期二" ;; 3) WEEKDAY="星期三" ;;
    4) WEEKDAY="星期四" ;; 5) WEEKDAY="星期五" ;; 6) WEEKDAY="星期六" ;;
    7) WEEKDAY="星期日" ;; *) WEEKDAY="未知" ;;
esac

# 内存与磁盘
MEM_INFO=$(free -h | grep -Ei "mem|内存" | awk '{print $3 " / " $2}')
DISK_INFO=$(df -h / | awk 'NR==2 {print $3 " / " $2 " (" $5 ")"}')
DISK_PERCENT=$(df / | awk 'NR==2 {print $5}' | sed 's/%//')
UPTIME=$(uptime -p | sed 's/up //')
LAST_UPDATE=$(stat -c %y /var/log/apt/history.log 2>/dev/null | cut -d '.' -f1 || echo "Unknown")

# 3. Docker 详细状态与容器分类
if command -v docker &> /dev/null; then
    RUNNING_APPS=$(docker ps --format "{{.Names}}" | sort)
    EXITED_APPS=$(docker ps -a --filter "status=exited" --filter "status=created" --format "{{.Names}}" | sort)
    D_TOTAL_COUNT=$(docker ps -a -q | wc -l)
    D_IMAGES=$(docker images -q | wc -l)
    D_STATUS="✅ Docker 运行中：容器 $D_TOTAL_COUNT 个，镜像 $D_IMAGES 个"
else
    D_STATUS="❌ 未安装 Docker"
fi

# 4. 输出界面
echo -e "${GREEN}👋 欢迎回来, ${USER_NAME}!${RESET}"
echo -e "${CYAN}------------------------------------------------------------${RESET}"
echo -e "⏰ 当前时间:${RESET}    ${CYAN}${CURRENT_DATE} (${WEEKDAY})${RESET}"
echo -e "🆙 运行时间:${RESET}    ${CYAN}${UPTIME}${RESET}"
echo -e "💾 内存使用:${RESET}    ${CYAN}${MEM_INFO}${RESET}"
echo -e "🗂 磁盘使用:${RESET}    ${CYAN}${DISK_INFO}${RESET}"
echo -e "📦 系统更新:${RESET}    ${CYAN}${LAST_UPDATE}${RESET}"
echo -e "🖥 系统版本:${RESET}    ${CYAN}${OS_VER}${RESET}"
echo -e "${CYAN}------------------------------------------------------------${RESET}"

# 5. Docker 统计
echo -e "\n${YELLOW}🐳 Docker 状态:${RESET}   ${D_STATUS}"

if [ -n "$RUNNING_APPS" ]; then
    for app in $RUNNING_APPS; do
        echo -e "${GREEN}✅ $app 运行中${RESET}"
    done
fi
if [ -n "$EXITED_APPS" ]; then
    for app in $EXITED_APPS; do
        echo -e "${RED}❌ $app 未运行${RESET}"
    done
fi

# 6. 最近登录记录
if command -v last &> /dev/null; then
    echo -e "\n${YELLOW}🛡 最近登录记录:${RESET}"
    last -i -n 3 | grep -vE "reboot|wtmp" | awk '{printf "%s   %s   %s   %s %s %s %s\n", $1, $2, $3, $4, $5, $6, $7}'
fi

# 7. 磁盘告警
if [ "$DISK_PERCENT" -ge 70 ]; then
    echo -e "\n${RED}💔 警告：磁盘使用率已达到 ${DISK_PERCENT}%，请及时清理！${RESET}"
fi
echo ""
```

## [MoviePilot](https://github.com/jxxghp/MoviePilot)
[![GitHub release](https://img.shields.io/github/v/release/jxxghp/MoviePilot)](https://github.com/jxxghp/MoviePilot/releases) [![Docker Pulls](https://img.shields.io/badge/dynamic/json?url=https://hub.docker.com/v2/repositories/jxxghp/moviepilot-v2&query=$.pull_count&label=下载次数&logo=docker)](https://hub.docker.com/r/jxxghp/moviepilot-v2)
```bash
docker run -d \
  --name moviepilot \
  -p 3000:3000 \
  -p 3001:3001 \
  -v /Media:/media \
  -v $(pwd)/config:/config \
  -v $(pwd)/core:/moviepilot/.cache/ms-playwright \
  -v /var/run/docker.sock:/var/run/docker.sock:ro \
  -e 'NGINX_PORT=3000' \
  -e 'PORT=3001' \
  -e 'PUID=0' \
  -e 'PGID=0' \
  -e 'UMASK=000' \
  -e 'TZ=Asia/Shanghai' \
  -e 'SUPERUSER=admin' \
  -e 'SUPERUSER_PASSWORD=password' \
  -e 'AUTH_SITE=iyuu' \
  -e 'IYUU_SIGN=123' \
  --restart=always \
  jxxghp/moviepilot-v2:latest
```

## [Emby](https://hub.docker.com/r/amilys/embyserver)
[![Docker Pulls](https://img.shields.io/docker/v/amilys/embyserver?sort=semver)](https://hub.docker.com/r/amilys/embyserver) [![Docker Pulls](https://img.shields.io/badge/dynamic/json?url=https://hub.docker.com/v2/repositories/amilys/embyserver&query=$.pull_count&label=下载次数&logo=docker)](https://hub.docker.com/r/amilys/embyserver)
```bash
docker run -d \
  --name emby \
  -p 8096:8096 \
  -p 8920:8920 \
  -v /Media:/media \
  -v $(pwd)/config:/config \
  --restart=always \
  --privileged=true \
  amilys/embyserver:latest
```

## [Qbittorrent](https://github.com/qbittorrent/qBittorrent)
[![GitHub tag](https://img.shields.io/github/tag/qbittorrent/qBittorrent.svg?label=latest%20tag)](https://github.com/qbittorrent/qBittorrent/tags) [![Docker Pulls](https://img.shields.io/badge/dynamic/json?url=https://hub.docker.com/v2/repositories/linuxserver/qbittorrent&query=$.pull_count&label=下载次数&logo=docker)](https://hub.docker.com/r/linuxserver/qbittorrent)
```bash
docker run -d \
  --name qbittorrent \
  -v $(pwd)/config:/config \
  -v /Media/downloads:/downloads \
  -e PUID=1000 \
  -e PGID=1000 \
  -e TZ=Asia/Shanghai \
  -e WEBUI_PORT=8080 \
  -e WEBUI_USERNAME=admin \
  -e WEBUI_PASSWORD=password \
  --restart=always \
  --network=macvlan \
  --ip=192.168.100.6 \
  linuxserver/qbittorrent:latest
```

## [Neko-master](https://github.com/foru17/neko-master)
[![GitHub release](https://img.shields.io/github/v/release/foru17/neko-master)](https://github.com/foru17/neko-master/releases) [![Docker Pulls](https://img.shields.io/badge/dynamic/json?url=https://hub.docker.com/v2/repositories/foru17/neko-master&query=$.pull_count&label=下载次数&logo=docker)](https://hub.docker.com/r/foru17/neko-master)
```bash
docker run -d \
  --name neko-master \
  -p 3000:3000 \
  -p 3002:3002 \
  -v $(pwd)/data:/app/data \
  -e COOKIE_SECRET="$(openssl rand -hex 32)" \
  --restart=always \
  foru17/neko-master:latest
```

## [AssppWeb](https://github.com/Lakr233/AssppWeb)
```bash
docker run -d \
  --name assppweb \
  -p 8080:8080 \
  -v $(pwd)/data:/data \
  -e DATA_DIR=/data \
  -e AUTO_CLEANUP_DAYS=1 \
  -e AUTO_CLEANUP_MAX_MB=10240 \
  --restart=always \
  ghcr.io/lakr233/assppweb:latest
```

## [Harvest](http://ptools.fun)
[![Docker Pulls](https://img.shields.io/docker/v/newptools/harvest?sort=semver)](https://hub.docker.com/r/newptools/harvest) [![Docker Pulls](https://img.shields.io/badge/dynamic/json?url=https://hub.docker.com/v2/repositories/newptools/harvest&query=$.pull_count&label=下载次数&logo=docker)](https://hub.docker.com/r/newptools/harvest)
```bash
docker run -d \
  --name harvest \
  -p 8000:8000 \
  -p 5566:5566 \
  -p 9001:9001 \
  -p 5173:5173 \
  -v $(pwd)/db:/app/db \
  -v $(pwd)/sites:/app/sites \
  -v $(pwd)/icons:/icons \
  -e TOKEN=YOUR-TOKEN \
  -e DJANGO_SUPERUSER_EMAIL=YOUR-EMAIL \
  -e DJANGO_SUPERUSER_USERNAME=admin \
  -e DJANGO_SUPERUSER_PASSWORD=password \
  -e WEBUI_PORT=5173 \
  -e DJANGO_WEB_PORT=8000 \
  -e REDIS_SERVER_PORT=6379 \
  -e FLOWER_UI_PORT=5566 \
  -e SUPERVISOR_UI_PORT=9001 \
  -e CloudFlareSpeedTest=false \
  --restart=always \
  newptools/harvest:latest
```

## [Sun-panel](https://github.com/hslr-s/sun-panel)
[![GitHub release](https://img.shields.io/github/v/release/hslr-s/sun-panel)](https://github.com/hslr-s/sun-panel/releases) [![Docker Pulls](https://img.shields.io/badge/dynamic/json?url=https://hub.docker.com/v2/repositories/hslr/sun-panel&query=$.pull_count&label=下载次数&logo=docker)](https://hub.docker.com/r/hslr/sun-panel)
```bash
docker run -d \
  --name sun-panel \
  -p 3002:3002 \
  -v $(pwd)/conf:/app/conf \
  -v /var/run/docker.sock:/var/run/docker.sock \
  --restart=always \
  hslr/sun-panel:latest
```

## [NginxProxyManager](https://github.com/xiaoxinpro/nginx-proxy-manager-zh)
[![GitHub release](https://img.shields.io/github/v/release/xiaoxinpro/nginx-proxy-manager-zh)](https://github.com/xiaoxinpro/nginx-proxy-manager-zh/releases) [![Docker Pulls](https://img.shields.io/badge/dynamic/json?url=https://hub.docker.com/v2/repositories/chishin/nginx-proxy-manager-zh&query=$.pull_count&label=下载次数&logo=docker)](https://hub.docker.com/r/chishin/nginx-proxy-manager-zh)
- Email：`admin@example.com`
- Password：`changeme`
```bash
docker run -d \
  --name NPM \
  -p 80:80 \
  -p 81:81 \
  -p 443:443 \
  -v $(pwd)/data:/data \
  -v $(pwd)/letsencrypt:/etc/letsencrypt \
  --restart=always \
  chishin/nginx-proxy-manager-zh:release
```

## [Portainer](https://github.com/eysp/portainer-ce)
[![GitHub release](https://img.shields.io/github/v/release/eysp/portainer-ce)](https://github.com/eysp/portainer-ce/releases) [![Docker Pulls](https://img.shields.io/badge/dynamic/json?url=https://hub.docker.com/v2/repositories/6053537/portainer-ce&query=$.pull_count&label=下载次数&logo=docker)](https://hub.docker.com/r/6053537/portainer-ce)
```bash
docker run -d \
  --name portainer \
  -p 9000:9000 \
  -v $(pwd):/data \
  -v /var/run/docker.sock:/var/run/docker.sock \
  --restart=always \
  --privileged=true \
  6053537/portainer-ce:latest
```

## [Lucky](https://github.com/gdy666/lucky)
[![GitHub release](https://img.shields.io/github/v/release/gdy666/lucky)](https://github.com/gdy666/lucky/releases) [![Docker Pulls](https://img.shields.io/badge/dynamic/json?url=https://hub.docker.com/v2/repositories/gdy666/lucky&query=$.pull_count&label=下载次数&logo=docker)](https://hub.docker.com/r/gdy666/lucky)
```bash
docker run -d \
  --name lucky \
  -v $(pwd):/app/conf \
  -v /var/run/docker.sock:/var/run/docker.sock \
  --restart=always \
  --network=host \
  --privileged=true \
  gdy666/lucky:v2
```

## [Cloudreve](https://github.com/cloudreve/Cloudreve)
[![GitHub release](https://img.shields.io/github/v/release/cloudreve/Cloudreve)](https://github.com/cloudreve/Cloudreve/releases) [![Docker Pulls](https://img.shields.io/badge/dynamic/json?url=https://hub.docker.com/v2/repositories/cloudreve/cloudreve&query=$.pull_count&label=下载次数&logo=docker)](https://hub.docker.com/r/cloudreve/cloudreve)
```bash
docker run -d \
  --name cloudreve \
  -p 5212:5212 \
  -p 6888:6888 \
  -p 6888:6888/udp \
  -v $(pwd)/data:/cloudreve/data \
  --restart=always \
  cloudreve/cloudreve:latest
```

## [Wxchat](https://github.com/wuyangdaily/wxchat)
[![GitHub release](https://img.shields.io/github/v/release/wuyangdaily/wxchat)](https://github.com/wuyangdaily/wxchat/releases) [![Docker Pulls](https://img.shields.io/badge/dynamic/json?url=https://hub.docker.com/v2/repositories/wuyangdaily/wxchat&query=$.pull_count&label=下载次数&logo=docker)](https://hub.docker.com/r/wuyangdaily/wxchat)
```bash
docker run -d \
  --name wxchat \
  -p 7080:80 \
  --restart=always \
  wuyangdaily/wxchat:latest
```

## [Wechat](https://github.com/wuyangdaily/wechat)
[![GitHub release](https://img.shields.io/github/v/release/wuyangdaily/wechat)](https://github.com/wuyangdaily/wechat/releases) [![Docker Pulls](https://img.shields.io/badge/dynamic/json?url=https://hub.docker.com/v2/repositories/wuyangdaily/wechat&query=$.pull_count&label=下载次数&logo=docker)](https://hub.docker.com/r/wuyangdaily/wechat)
```bash
docker run -d \
  --name wechat \
  -p 7080:80 \
  --restart=always \
  wuyangdaily/wechat:latest
```

## [Certimate](https://github.com/certimate-go/certimate)
[![GitHub release](https://img.shields.io/github/v/release/certimate-go/certimate)](https://github.com/certimate-go/certimate/releases) [![Docker Pulls](https://img.shields.io/badge/dynamic/json?url=https://hub.docker.com/v2/repositories/certimate/certimate&query=$.pull_count&label=下载次数&logo=docker)](https://hub.docker.com/r/certimate/certimate)
- 账号：`admin@certimate.fun`
- 密码：`1234567890`
```bash
docker run -d \
  --name certimate \
  -p 8090:8090 \
  -v $(pwd)/data:/app/pb_data \
  -v /etc/localtime:/etc/localtime:ro \
  -v /etc/timezone:/etc/timezone:ro \
  --restart=always \
  certimate/certimate:latest
```

## [Komari](https://github.com/komari-monitor/komari) [主题](https://github.com/Montia37/Komari-theme-purcarte)
[![GitHub release](https://img.shields.io/github/v/release/komari-monitor/komari)](https://github.com/wuyangdaily/komari-monitor/komari) [![GitHub release](https://img.shields.io/github/v/release/Montia37/Komari-theme-purcarte)](https://github.comMontia37/Komari-theme-purcarte)
```bash
docker run -d \
  --name komari \
  -p 25774:25774 \
  -v $(pwd):/app/data \
  --restart=always \
  ghcr.io/komari-monitor/komari:latest
```
## Agent（Uninstall）
```bash
sudo systemctl stop komari-agent 2>/dev/null; \
sudo systemctl disable komari-agent 2>/dev/null; \
sudo rm -f /etc/systemd/system/komari-agent.service; \
sudo systemctl daemon-reload; \
sudo pkill -f /opt/komari/agent 2>/dev/null; \
sudo rm -rf /opt/komari; \
systemctl status komari-agent
```

## [NodeCtl](https://github.com/hobin66/nodectl)
[![GitHub release](https://img.shields.io/github/v/release/hobin66/nodectl)](https://github.com/hobin66/nodectl/releases) 
```bash
docker run -d \
  --name nodectl \
  -p 8080:8080 \
  -v $(pwd)/data:/app/data \
  --restart=always \
  ghcr.io/hobin66/nodectl:latest
```

## [Moments-blog](https://github.com/zhoujun0601/moments-blog)
- 用户名：`admin`
- 密码：`Strong1passwd!`
- 创建网络：`docker network create moments-network`
```bash
docker run -d \
  --name moments-blog \
  -p 5201:80 \
  -v $(pwd)/data/uploads:/data/uploads \
  -v $(pwd)/data/logs:/data/logs \
  -e JWT_SECRET=$(openssl rand -hex 64) \
  -e DATABASE_URL=postgresql://moments:Moments@123456@moments-db:5432/moments \
  -e NODE_ENV=production \
  -e PORT=3001 \
  -e UPLOAD_DIR=/data/uploads \
  -e INTERNAL_API_URL=http://localhost:3001 \
  --restart=always \
  --network=moments-network \
  koalalove/moments-blog:latest
```
```bash
docker run -d \
  --name moments-db \
  -v $(pwd)/data/postgres:/var/lib/postgresql/data \
  -e POSTGRES_DB=moments \
  -e POSTGRES_USER=moments \
  -e POSTGRES_PASSWORD=Moments@123456 \
  -e PGDATA=/var/lib/postgresql/data/pgdata \
  --restart=always \
  --network=moments-network \
  postgres:15-alpine
```

## [Mihomo](https://github.com/MetaCubeX/mihomo) [配置](https://lanzoux.com/iqrN63nccthc)
[![GitHub release](https://img.shields.io/github/v/release/MetaCubeX/mihomo)](https://github.com/MetaCubeX/mihomo/releases) [![Docker Pulls](https://img.shields.io/badge/dynamic/json?url=https://hub.docker.com/v2/repositories/metacubex/mihomo&query=$.pull_count&label=下载次数&logo=docker)](https://hub.docker.com/r/metacubex/mihomo)
```bash
docker run -d \
  --name mihomo \
  -v $(pwd):/root/.config/mihomo \
  --restart=always \
  --network=host \
  metacubex/mihomo:latest
```

## [Sub-Store](https://github.com/sub-store-org/Sub-Store)（订阅转换）
[![Docker Pulls](https://img.shields.io/docker/v/xream/sub-store?sort=semver)](https://hub.docker.com/r/xream/sub-store) [![Docker Pulls](https://img.shields.io/badge/dynamic/json?url=https://hub.docker.com/v2/repositories/xream/sub-store&query=$.pull_count&label=下载次数&logo=docker)](https://hub.docker.com/r/xream/sub-store)
```bash
docker run -d \
  --name sub-store \
  -v $(pwd):/opt/app/data \
  -e SUB_STORE_FRONTEND_BACKEND_PATH=/CKg2abstVnOeRpm1aB4G \
  --network=host \
  --restart=always \
  xream/sub-store:latest
```

## [Miaospeed](https://github.com/AirportR/miaospeed)（测速后端）
[![GitHub release](https://img.shields.io/github/v/release/AirportR/miaospeed)](https://github.com/AirportR/miaospeed/releases) [![Docker Pulls](https://img.shields.io/badge/dynamic/json?url=https://hub.docker.com/v2/repositories/airportr/miaospeed&query=$.pull_count&label=下载次数&logo=docker)](https://hub.docker.com/r/airportr/miaospeed)
```bash
docker run -d \
  --name miaospeed \
  --network=host \
  --restart=always \
  airportr/miaospeed:latest \
  server -bind 0.0.0.0:8765 -path miaospeed -token 'Xwqg^flYQN' -mtls -ipv6 true
```

## [Koipy](https://github.com/koipy-org/koipy)（机器人后端)[配置](https://lanzoux.com/imh7l3m57eyb)
[![Docker Pulls](https://img.shields.io/docker/v/koipy/koipy?sort=semver)](https://hub.docker.com/r/koipy/koipy) [![Docker Pulls](https://img.shields.io/badge/dynamic/json?url=https://hub.docker.com/v2/repositories/koipy/koipy&query=$.pull_count&label=下载次数&logo=docker)](https://hub.docker.com/r/koipy/koipy)
```bash
docker run -d \
  --name koipy \
  -v $(pwd)/config.yaml:/app/config.yaml \
  -v $(pwd)/builtin:/app/resources/scripts/builtin \
  --network=host \
  --restart=always \
  koipy/koipy:dev
```

## 配置文件
```bash
# 文档地址，有疑问先看文档：https://koipy.gitbook.io/koipy
license: "激活码" # 激活码，必填，否则无法使用。
admin: # 管理员，可以不填，不填删掉。首次启动自动设置管理员。
- 12345678
network: # 网络配置
  httpProxy: "http://127.0.0.1:7890" # http代理，如果设置的话，bot会用这个拉取订阅
  socks5Proxy: "socks5://127.0.0.1:7890" # socks5代理， bot的代理在下面bot那一栏填
  userAgent："ClashMetaForAndroid/2.8.9.Meta Mihomo/0.16" # UA设置，影响订阅获取
bot:
  bot-token: 12345678 # bot的token, 首次启动必填
  api-id:  # telegram的 api_id 可选，想用自己的api可以填，默认内置
  api-hash:  # telegram的 api_hash 可选，想用自己的api可以填，默认内置
  proxy: socks5://127.0.0.1:7890 # bot的代理设置，推荐socks5代理，http代理也可以，目前仅支持这两种代理
  ipv6: false #是否使用ipv6连接
  antiGroup: true # 是否开启防拉群模式，默认false
  strictMode: true # 严格模式，在此模式下，bot的所有按钮只能触发消息对话的那个人点，否则是全体用户权限均可点击。默认false
  bypassMode: false # 是否将bot设置为旁路模式，设置为旁路模式后，bot原本内置的所有指令都将失效。取而代之仅生效下面bot.commands配置的指令。关于旁路模式有什么用，请查阅在线文档。
  parseMode: MARKDOWN # bot的文本解析模式，可选值如下： [DEFAULT, MARKDOWN, HTML, DISABLED]
  inviteGroup: [-12345678] # invite指令权限覆写群组白名单，写上对应群组id，那个群所有人都将可以使用/invite指令，默认只能用户权限使用。 群组id以-100开头
  cacheTime: 60 # 订阅缓存的最大时长，默认60秒。一个订阅不会重复拉取，在60秒内使用缓存值，超过60秒重新获取。
  echoLimit: 0.8 # 限制响应速度，单位秒，默认0.8秒，即bot每0.8秒最多响应一条消息。每0.8/2秒内按钮最多响应一次
  inviteBlacklistURL: [] # 邀请测试里禁止测试的URL链接远程更新地址，多个用逗号隔开。样例： https://raw.githubusercontent.com/koipy-org/koihub/master/proxypool_url.txt
  inviteBlacklistDomain: [] # 邀请测试里禁止测试包含的域名远程更新地址，多个用逗号隔开。样例：https://raw.githubusercontent.com/koipy-org/koihub/master/proxypool_domain.txt
  autoResetCommands: false # 是否自动重置bot指令，默认false。开启后，每次启动时会清除原来固定在TG前端的指令
  commands: # bot的指令设置
    # 特殊情况说明：1. 当name=invite的内置规则 enable=false attachToInvite=ture rule=任意，会禁用内置的invite按钮
    # 2. 当name=invite的内置规则 enable=true attachToInvite=true rule=任意，text=任意，即可更改内置invite按钮的文本
    # 3. 当name=invite的内置规则 enable=true attachToInvite=true rule=invite内置规则 ，会复写内置invite的规则，后台会有DEBUG日志提示
    # 内置invite规则名称：['test', 'analyze', 'speed', 'full', 'ping', 'udptype', 'uspeed']
    - name: "ping" # 指令名称
      title: "PING测试" # 绘图时任务标题
      enable: true # 是否启用该指令， 默认true。未启用时，无法使用该指令。
      rule: "ping" # 将该指令升级为测试指令，写对应的规则名，会读取你配置好的规则，读取不到则判定该指令为普通指令，而非测试指令。普通指令相当于 /help /version 这些，等于仅修改描述文本，而无实际测试功能
      pin: true # 是否固定指令，固定指令后会始终显示在TG客户端的指令列表中，默认false
      text: "" # 指令的提示文本，默认空时自动使用name的值
      attachToInvite: true # 是否附加到invite指令中选择的按钮，让invite也能享受到此规则背后的script选择，默认true
    - name: "nf"
      rule: "nf"
      enable: true
      pin: false # 不固定指令时，相当于隐藏指令，只有你自己知道
image:
  speedFormat: "byte/decimal" # 速度结果绘图格式，共有以下可用值： ["byte/binary", "byte/decimal", "bit/binary", "bit/decimal"] 具体解释请查看文档
  color: # 颜色配置
    background: # 背景颜色
      inbound: # 入口背景
        alpha: 255 # 透明度
        end-color: '#ffffff' # 透明度
        label: 0 # 值
        name: '' # 名称随意
        value: '#ffffff'
      outbound: #出口背景
        alpha: 255
        end-color: '#ffffff'
        label: 0
        name: ''
        value: '#ffffff'
      script: # 连通性测试图
        alpha: 255
        end-color: '#ffffff'
        label: 0
        name: ''
        value: '#ffffff'
      scriptTitle: # 连通性图标题栏颜色
        alpha: 255
        end-color: '#ffffff'
        label: 0
        name: ''
        value: '#EAEAEA'
      speed: # 速度图内容颜色
        alpha: 255
        end-color: '#ffffff'
        label: 0
        name: ''
        value: '#ffffff'
      speedTitle: # 速度图标题栏颜色
        alpha: 255
        end-color: '#ffffff'
        label: 0
        name: ''
        value: '#EAEAEA'
      topoTitle: # 拓扑图标题栏颜色
        alpha: 255
        end-color: '#ffffff'
        label: 0
        name: ''
        value: '#EAEAEA'
    delay: # 延迟配色
    - label: 1 # 延迟的值， >1 就采用这个颜色 单位ms
      name: '1'
      value: '#e4f8f9'
    - label: 50 # 延迟的值， >50 就采用这个颜色 单位ms
      name: '2'
      value: '#e4f8f9'
    - label: 100 # 以此类推
      name: '2'
      value: '#bdedf1'
    - label: 200
      name: '3'
      value: '#96e2e8'
    - label: 300
      name: '4'
      value: '#78d5de'
    - label: 500
      name: '5'
      value: '#67c2cf'
    - label: 1000
      name: '6'
      value: '#61b2bd'
    - label: 2000
      name: '7'
      value: '#466463'
    - label: 0
      name: '8'
      value: '#8d8b8e'
    ipriskHigh: # ip风险非常高的颜色
      alpha: 255
      end-color: '#ffffff'
      label: 0
      name: ''
      value: '#ffffff'
    ipriskLow: # ip风险最低的颜色
      alpha: 255
      end-color: '#ffffff'
      label: 0
      name: ''
      value: '#ffffff'
    ipriskMedium: # ip风险其他颜色同理
      alpha: 255
      end-color: '#ffffff'
      label: 0
      name: ''
      value: '#ffffff'
    ipriskVeryHigh:
      alpha: 255
      end-color: '#ffffff'
      label: 0
      name: ''
      value: '#ffffff'
    na: # na的颜色
      alpha: 255
      end-color: '#8d8b8e'
      label: 0
      name: ''
      value: '#8d8b8e'
    'no': # 解锁失败的颜色
      alpha: 255
      end-color: '#ee6b73'
      label: 0
      name: ''
      value: '#ee6b73'
    outColor: []
    speed: # 速度值颜色
    - label: 0.0
      name: '1'
      value: '#fae0e4'
      alpha: 255
      end_color: '#ffffff'
    - label: 0.0
      name: '2'
      value: '#f7cad0'
      alpha: 255
      end_color: '#ffffff'
    - label: 25.0
      name: '3'
      value: '#f9bec7'
      alpha: 255
      end_color: '#ffffff'
    - label: 50.0
      name: '4'
      value: '#ff85a1'
      alpha: 255
      end_color: '#ffffff'
    - label: 100.0
      name: '5'
      value: '#ff7096'
      alpha: 255
      end_color: '#ffffff'
    - label: 150.0
      name: '6'
      value: '#ff5c8a'
      alpha: 255
      end_color: '#ffffff'
    - label: 200.0
      name: '7'
      value: '#ff477e'
      alpha: 255
      end_color: '#ffffff'
    wait:
      alpha: 255
      end-color: '#dcc7e1'
      label: 0
      name: ''
      value: '#dcc7e1'
    warn:
      alpha: 255
      end-color: '#fcc43c'
      label: 0
      name: ''
      value: '#fcc43c'
    'yes':
      alpha: 255
      end-color: '#bee47e'
      label: 0
      name: ''
      value: '#bee47e'
    'xline': # x轴线条颜色
      value: '#E1E1E1'
    'yline': # y轴线条颜色
      value: '#EAEAEA'
    'font': # 字体颜色
      value: '#000000'
  compress: false # 是否压缩
  emoji: # emoji是否开启，建议开启，就这样设置
    enable: true
    source: TwemojiLocalSource
  endColorsSwitch: false
  font: ./resources/alibaba-Regular.otf #字体路径
  speedEndColorSwitch: false # 是否开启渐变色
  invert: false # 是否将图片取反色，与透明度模式不兼容，开启此项透明度将失效
  save: true # 是否保存图片到本地，设置为false时，图片将不会保存到本地，默认保存到本地备份(true)
  pixelThreshold: 2500x3500 # 图片像素阈值，超过阈值则发送原图，否则发送压缩图片，发送压缩图有助于让TG客户端自动下载图片以提升视觉体验。格式：宽的像素x高的像素，例如：2500x3500
  title: 节点测速机器人 # 绘图标题
  logo: true # 是否在绘图的类型中显示协议相关的logo
  watermark: # 水印
    alpha: 32 # 透明度
    angle: -16.0 # 旋转角度
    color: # 颜色
      alpha: 16
      end-color: '#ffffff'
      label: 0
      name: ''
      value: '#000000'
    enable: false #是否启用
    row-spacing: 0 # 行间距
    shadow: false # 暂时未实现
    size: 64 # 水印大小
    start-y: 0 # 开始坐标
    text: koipy # 水印内容
    trace: false # UID追踪开启，测试图结果显示任务发起人的UID，同时会在TG客户端发送图片时打上关联UID的tag
runtime: # 测速任务可以动态调整的配置
  entrance: true # 是否显示入口IP段
  duration: 10 # 测速时长，优先级高于后端单独设置的测速时长
  ipstack: true # 是否启用双栈检测
  localip: false # 暂时无用
  nospeed: false # 暂时无用
  pingURL: https://www.gstatic.com/generate_204 # 延迟测试地址
  speedFiles: # 速度测试的大文件下载地址，写多个地址后，在后端设置里 option.DownloadURL="DYNAMIC:ALL" 表示用runtime.speedFiles里随机一个地址
  - https://dl.google.com/dl/android/studio/install/3.4.1.0/android-studio-ide-183.5522156-windows.exe
  speedNodes: 300 # 最大测速节点数量
  speedThreads: 4 # 后端测速线程数量，优先级高于后端单独设置的
  output: image # 输出类型，目前支持 image 和 json 和 video 三种，其中video如果你用的不是docker镜像启动的，需要自己单独安装 ffmepg，然后设置好 ffmepg 的环境变量
  realtime: true # 是否实时渲染测试结果
  disableSubCvt: false # 是否针对单次测试禁用订阅转换，默认false。开启后，假如全局订阅转换开启，则单次测试不会进行订阅转换。配合rule或者指令参数使用
  protectContent: false # bot输出的所有图片设置为保护内容，默认false。设置为 true后，bot输出的图片不允许进行转发，复制。
  enableDNSInject: false # 是否启用 mihomo DNS 注入。开启后会读取订阅中的 dns 字段并编码成 mihomo://base64... 插入到后端 dnsServer 第一项。
scriptConfig:
  scripts: # 脚本载入
    - type: gojajs
      name: "Netflix"
      rank: 1
      content: resources/scripts/builtin/netflix.js
    - type: gojajs
      name: "Youtube"
      rank: 2
      content: "resources/scripts/builtin/youtube.js"
    - type: gojajs
      name: "Disney+"
      rank: 3
      content: "resources/scripts/builtin/disney+.js"
    - type: gojajs
      name: "OpenAI"
      rank: 4
      content: "resources/scripts/builtin/openai.js"
    - type: gojajs
      name: "Tiktok"
      rank: 5
      content: "resources/scripts/builtin/tiktok.js"
    - type: gojajs
      name: "Spotify"
      rank: 6
      content: "resources/scripts/builtin/spotify.js"
    - type: gojajs
      name: "维基百科"
      rank: 7
      content: "resources/scripts/builtin/wikipedia.js"
    - type: gojajs
      name: "Copilot"
      rank: 8
      content: "resources/scripts/builtin/copilot.js"
    - type: gojajs
      name: "Bilibili"
      rank: 9
      content: "resources/scripts/builtin/bilibili.js"
    - type: gojajs
      name: "Viu"
      rank: 10
      content: "resources/scripts/builtin/viu.js"
    - type: gojajs
      name: "Gemini"
      rank: 11
      content: "resources/scripts/builtin/gemini.js"
    - type: gojajs
      name: "Claude"
      rank: 12
      content: "resources/scripts/builtin/Claude.js"
    - type: gojajs
      name: "iQIYI"
      rank: 13
      content: "resources/scripts/builtin/iqiyi.js"
    - type: gojajs
      name: "Steam"
      rank: 14
      content: "resources/scripts/builtin/steam.js"
    - type: gojajs
      name: "Primevideo"
      rank: 15
      content: "resources/scripts/builtin/primevideo.js"
    - type: gojajs
      name: "SSH"
      rank: 16
      content: "resources/scripts/builtin/ssh22.js"
    - type: gojajs
      name: "IP风险"
      rank: 17
      content: "resources/scripts/builtin/iprisk.js"
    - type: gojajs
      name: "DNS区域"
      rank: 18
      content: "resources/scripts/builtin/dns.js"
    - type: gofunc
      name: "TEST_PING_PACKET_LOSS"
      rank: 19
      content: ""
    - type: gojajs
      name: "IP质量"
      rank: 20
      content: "resources/scripts/builtin/ipquality.js"
    - type: gojajs
      name: "IP评分"
      rank: 21
      content: "resources/scripts/builtin/ipscore.js"
# 以下为固定脚本名称，用于覆写内置的GEOIP脚本，脚本名称不可更改：
#    - type: gojajs
#      name: "GEOIP_INBOUND"
#      rank: 0
#      content: "YOUR_GEOIP_SCRIPT" # 默认的GEOIP脚本参见 https://github.com/AirportR/miaospeed/blob/master/engine/embeded/default_geoip.js
slaveConfig: # 后端配置
  healthCheck: # checkslave 后端健康检查配置
    numSamples: 10 # 健康检查样本数量，单位整数次数，默认采样10次PING测试数据
    showStatusStyle: "default" # 在后端选择页面展示状态的样式，共有以下可用值： ["emoji", "number", "default"]，分别代表：展示emoji、展示延迟、不展示，默认default不展示
    autoHideOnFailure: false # 健康检查失败时是否自动隐藏后端，默认false。
  showID: true # 是否在选择后端页面展示slaveid
  # 后端测速任务的调度模式，共有以下可用值：["concurrent", "pipeline", "sequential"]，默认pipeline，分别代表：
  # 1. 并发模式（所有后端同时开始测速）
  # 2. 流水线模式（当第一个测速后端测完第一个节点，第二个后端才开始发送测速任务，以此类推）
  # 3. 串行模式（前一个后端全部测完后下一个才开始）
  speedScheduling: pipeline 
  geoClustering: true # 是否开启拓扑结果的聚类排序，默认为true。开启后会将结果相同或相近的后端排列在一起，提高绘图时的单元格合并率，使图片更整洁。
  slaves: # 后端列表，注意是数组类型
    - type: miaospeed # 固定值，目前只这个支持
      id: "local" # 后端id
      token: "Xwqg^flYQN" # 连接密码
      address: "127.0.0.1:8765" # 后端地址
      path: "/miaospeed" # websocket的连接路径，只有路径正确才能正确连接，请填写复杂的路径，防止路径被爆破。可以有效避免miaospeed服务被网络爬虫扫描到.
      skipCertVerify: true # 跳过证书验证，如果你不知道在做什么，请写此默认值
      tls: true # 启用加密连接，如果你不知道在做什么，请写此默认值
      invoker: "1114514" # bot调用者，请删掉此行或者随便填一个字符串
      buildtoken: "MIAOKO4|580JxAo049R|GEnERAl|1X571R930|T0kEN" # 默认编译token  如果你不知道在做什么，请写此默认值
      comment: "本地MS后端" # 后端备注，显示在bot页面的
      hidden: false # 是否隐藏此后端
      # proxy: http://127.0.0.1:7890 # 为此后端设置专门的http代理（暂时仅支持http代理）
      option: # 可选配置，请注意部分值设置得太大会不生效，比如taskTimeout设置成10000以上，就不会生效。
        downloadDuration: 8 # 测试时长
        downloadThreading: 4 # 测速线程
        downloadURL: https://dl.google.com/dl/android/studio/install/3.4.1.0/android-studio-ide-183.5522156-windows.exe # 测速大文件，有一个特殊值：DYNAMIC:ALL，表示随机选择一个下载地址，随机选择列表需要在runtime.speedFiles里或rule.runtime.speedFiles里设置。
        pingAddress: https://cp.cloudflare.com/generate_204 # 延迟测试地址
        pingAverageOver: 3 # ping多少次取平均
        stunURL: udp://stunserver2025.stunprotocol.org:3478 # STUN地址，测udp连通性的，格式: udp://host:port
        taskRetry: 3 # 后端任务重试，单位秒(s)
        taskTimeout: 2500 # 后端任务超时判定时长，单位毫秒(ms)
        dnsServer: [] # 后端指定dns服务器，解析节点域名时会用到。例子: ["119.29.29.29:53", "223.5.5.5:53"]，也支持DoH格式的域名，例如：["https://dns.google/dns-query"]
        # dnsServer 也支持 mihomo的dns配置（后端版本至少为 4.6.5），经过base64编码后会发送给后端，后端支持解析： mihomo://ZG5zOgogIGVuYWJsZTogdHJ1ZQogIGRlZmF1bHQtbmFtZXNlcnZlcjoKICAgIC0gMjIzLjUuNS41
        apiVersion: 1 # 后端Api版本，设置为 0或者1可以适配旧版后端兼容性，默认为1，如无必要请勿修改。如果要对接其他分支miaospeed请设置为0或者1
        uploadURL: https://speed.cloudflare.com/__up # 旧版/其他分支不兼容，apiVersion=3 独有配置，上行速度测试的自定义URL
        uploadDuration: 8 # 旧版/其他分支不兼容，apiVersion=3 独有配置。上行速度测试的测速时长
        uploadThreading: 4 # 旧版/其他分支不兼容，apiVersion=3 独有配置。上行速度测试的测速线程
rules:
  - name: 订阅名1 # 规则名称
    url: https://www.google.com  # 订阅链接
    owner: 1111111111 # 规则创建者
    slaveid: [local] # 写你在后端配置里设置的后端id，如果用数组形式写多个后端id，就代表为多后端联测。
    runtime: null # 支持主配置runtime的所有值
    script: [] # 写你在后端配置里设置的脚本配置名称，也支持预保留的名称TEST_PING_RTT等
  - name: 订阅名2 # 规则名称2
    url: https://www.google2.com  # 订阅链接
    owner: 2222222222 # 规则创建者
subconverter: # 订阅转换，功能详情：https://github.com/tindy2013/subconverter
  address: 127.0.0.1:25500 # 地址
  enable: false # 是否启用
  tls: false # 是否启用安全加密HTTPS协议，如果不知道的话， https 开头就设为true，否则默认false
substore: # 订阅转换2，功能详情：https://github.com/sub-store-org/Sub-Store
  enable: true # 是否启用，默认false
  backend: "http://127.0.0.1:3000/download/sub?target=ClashMeta" # 后端地址，bot会自动解析成 http://127.0.0.1:3000/download/sub
  ua: "" # bot传递给订阅转换自定义的请求UA，留空则使用默认UA
  autoDeploy: false # 是否自动部署sub-store，默认false，如果为true，bot启动时会自动下载sub-store后端和对应的javascript运行时(bun)，如果你自己手动部署sub-store，请设置为false
  path: "sub-store.bundle.js" # sub-store后端主程序文件路径，自动部署时会自动生成，请勿修改
  jsRuntime: "/usr/bin/node" # js运行时的可执行文件路径，默认留空。自动部署时会自动生成，请勿修改
#callbacks: # http回调功能支持
#  onMessage: http://127.0.0.1:8080/onMessage # 回调地址，bot收到消息时,会向此地址发送POST请求，使用方法请看文档
#  onPreSend: http://127.0.0.1:8080/onPreSend # 回调地址，bot处理所有任务的前置动作后（比如选定后端、选定规则等），会向此地址发送POST请求，来完成一些操作，使用方法请看文档
#  onResult: http://127.0.0.1:8080/onResult # 回调地址，bot接受完测试结果后，会向此地址发送POST请求，可以用来添加/修改结果数据，使用方法请看文档
translation: # 翻译语言包
  lang: zh-CN # 启用哪个语言包，填的值为下面resources配置的键，默认zh-CN
  resources: # 翻译包在哪加载
    zh-CN: ./resources/i18n/zh-CN.yml # 键随便填，值填文件路径，文件内容格式为yaml，具体请看文档
log-level: INFO # 日志文件日志等级，共有以下日志等级： [DEBUG, INFO, WARNING, ERROR, CRITICAL, DISABLE]，越后的等级日志越严重，DISABLE会禁用日志文件，日志存放在logs目录下。控制台日志等级不受此配置影响，始终为DEBUG等级
user: [] # 用户权限名单，不用自己设，推荐使用 /grant 指令添加用户权限
```
