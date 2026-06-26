## 📚 目录

| [Docker install](#ubuntu-server-docker-compose-install) | [Docker update](#ubuntu-server-docker-compose-update) | [MoviePilot](#moviepilot) | [Emby](#emby) | [Qbittorrent](#qbittorrent) | [Neko-master](#neko-master) | [AssppWeb](#assppweb) | [Harvest](#harvest-配置) |
|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|
| [Sun-panel](#sun-panel) | [NginxProxyManager](#nginxproxymanager) | [Portainer](#portainer) | [Lucky](#lucky) | [Cloudreve](#cloudreve) | [Wxchat](#wxchat) | [Wechat](#wechat) | [Certimate](#certimate) |
| [Komari](#komari-主题) | [Agent](#agentuninstall) | [NodeCtl](#nodectl) | [Moments-blog](#moments-blog) | [Mihomo](#mihomo-配置) | [Sub-Store](#sub-store订阅转换) | [Miaospeed](#miaospeed测速后端) | [Koipy](#koipy机器人后端配置) |
| [RustDesk](#rustdesk) | [DockUP](#dockup) | [配置文件](#配置文件) |  |  |

## Ubuntu Server Docker Compose install
![Docker](https://img.shields.io/github/v/tag/docker/cli?label=Docker&logo=docker) ![Compose](https://img.shields.io/github/v/release/docker/compose?label=Compose&logo=docker)

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
sudo usermod -aG docker $USER && \
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

## [MoviePilot](https://github.com/jxxghp/MoviePilot)
[![GitHub release](https://img.shields.io/github/v/release/jxxghp/MoviePilot)](https://github.com/jxxghp/MoviePilot/releases) [![Docker Pulls](https://img.shields.io/badge/dynamic/json?url=https://hub.docker.com/v2/repositories/jxxghp/moviepilot-v2&query=$.pull_count&label=下载次数&logo=docker)](https://hub.docker.com/r/jxxghp/moviepilot-v2)
```bash
docker run -d \
  --name moviepilot \
  -p 3000:3000 \
  -p 3001:3001 \
  -v /Media:/media \
  -v ~/moviepilot/config:/config \
  -v ~/moviepilot/core:/moviepilot/.cloakbrowser \
  -v /var/run/docker.sock:/var/run/docker.sock:ro \
  -e NGINX_PORT=3000 \
  -e PORT=3001 \
  -e PUID=0 \
  -e PGID=0 \
  -e UMASK=000 \
  -e TZ=Asia/Shanghai \
  -e SUPERUSER=admin \
  -e SUPERUSER_PASSWORD=password \
  -e AUTH_SITE=iyuu \
  -e IYUU_SIGN=123 \
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
  -v ~/emby/config:/config \
  --restart=always \
  --privileged=true \
  amilys/embyserver:latest
```

## [Qbittorrent](https://github.com/qbittorrent/qBittorrent)
[![GitHub tag](https://img.shields.io/github/tag/qbittorrent/qBittorrent.svg?label=latest%20tag)](https://github.com/qbittorrent/qBittorrent/tags) [![Docker Pulls](https://img.shields.io/badge/dynamic/json?url=https://hub.docker.com/v2/repositories/linuxserver/qbittorrent&query=$.pull_count&label=下载次数&logo=docker)](https://hub.docker.com/r/linuxserver/qbittorrent)
```bash
docker run -d \
  --name qbittorrent \
  -v ~/qbittorrent/config:/config \
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
[![Docker Pulls](https://img.shields.io/docker/v/foru17/neko-master?sort=semver)](https://hub.docker.com/r/foru17/neko-master) [![Docker Pulls](https://img.shields.io/badge/dynamic/json?url=https://hub.docker.com/v2/repositories/foru17/neko-master&query=$.pull_count&label=下载次数&logo=docker)](https://hub.docker.com/r/foru17/neko-master)
```bash
docker run -d \
  --name neko-master \
  -p 3000:3000 \
  -p 3002:3002 \
  -v ~/neko-master/data:/app/data \
  -e COOKIE_SECRET="$(openssl rand -hex 32)" \
  --restart=always \
  foru17/neko-master:latest
```

## [AssppWeb](https://github.com/Lakr233/AssppWeb)
```bash
docker run -d \
  --name assppweb \
  -p 8080:8080 \
  -v ~/assppweb/data:/data \
  -e DATA_DIR=/data \
  -e AUTO_CLEANUP_DAYS=1 \
  -e AUTO_CLEANUP_MAX_MB=10240 \
  --restart=always \
  ghcr.io/lakr233/assppweb:latest
```

## [Harvest](http://ptools.fun) [配置](https://lanzoux.com/iNTSF3q7tjrc)
[![Docker Pulls](https://img.shields.io/docker/v/newptools/go-harvest/latest)](https://hub.docker.com/r/newptools/go-harvest) [![Docker Pulls](https://img.shields.io/badge/dynamic/json?url=https://hub.docker.com/v2/repositories/newptools/go-harvest&query=$.pull_count&label=下载次数&logo=docker)](https://hub.docker.com/r/newptools/go-harvest)
```bash
docker run -d \
  --name harvest \
  -p 5173:5173 \
  -v ~/harvest/db:/app/db \
  -v ~/harvest/sites:/app/sites \
  -v ~/harvest/downloads:/downloads \
  -v ~/harvest/downloaders:/downloaders \
  -e AUTO_UPDATE=true \
  -e EMAIL=YOUR-EMAIL \
  -e TOKEN=YOUR-TOKEN \
  --health-cmd='curl -fsS http://127.0.0.1:5173/api.json >/dev/null || exit 1' \
  --health-interval=20s \
  --health-timeout=5s \
  --health-retries=10 \
  --health-start-period=30s \
  --restart=always \
  newptools/go-harvest:latest
```

## [Sun-panel](https://github.com/hslr-s/sun-panel)
[![Docker Pulls](https://img.shields.io/docker/v/hslr/sun-panel)](https://hub.docker.com/r/hslr/sun-panel) [![Docker Pulls](https://img.shields.io/badge/dynamic/json?url=https://hub.docker.com/v2/repositories/hslr/sun-panel&query=$.pull_count&label=下载次数&logo=docker)](https://hub.docker.com/r/hslr/sun-panel)
```bash
docker run -d \
  --name sun-panel \
  -p 3002:3002 \
  -v ~/sun-panel/conf:/app/conf \
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
  -v ~/npm/data:/data \
  -v ~/npm/letsencrypt:/etc/letsencrypt \
  -e TZ=Asia/Shanghai \
  --restart=always \
  chishin/nginx-proxy-manager-zh:release
```

## [Portainer](https://github.com/eysp/portainer-ce)
[![Docker Pulls](https://img.shields.io/docker/v/6053537/portainer-ce?sort=semver)](https://hub.docker.com/r/6053537/portainer-ce) [![Docker Pulls](https://img.shields.io/badge/dynamic/json?url=https://hub.docker.com/v2/repositories/6053537/portainer-ce&query=$.pull_count&label=下载次数&logo=docker)](https://hub.docker.com/r/6053537/portainer-ce)
```bash
docker run -d \
  --name portainer \
  -p 9000:9000 \
  -v ~/portainer:/data \
  -v /var/run/docker.sock:/var/run/docker.sock \
  --restart=always \
  --privileged=true \
  6053537/portainer-ce:latest
```

## [Lucky](https://github.com/gdy666/lucky)
[![Docker Pulls](https://img.shields.io/docker/v/gdy666/lucky?sort=semver)](https://hub.docker.com/r/gdy666/lucky) [![Docker Pulls](https://img.shields.io/badge/dynamic/json?url=https://hub.docker.com/v2/repositories/gdy666/lucky&query=$.pull_count&label=下载次数&logo=docker)](https://hub.docker.com/r/gdy666/lucky)
```bash
docker run -d \
  --name lucky \
  -v ~/lucky:/app/conf \
  -v /var/run/docker.sock:/var/run/docker.sock \
  --restart=always \
  --network=host \
  --privileged=true \
  gdy666/lucky:v3
```

## [Cloudreve](https://github.com/cloudreve/Cloudreve)
[![GitHub release](https://img.shields.io/github/v/release/cloudreve/Cloudreve)](https://github.com/cloudreve/Cloudreve/releases) [![Docker Pulls](https://img.shields.io/badge/dynamic/json?url=https://hub.docker.com/v2/repositories/cloudreve/cloudreve&query=$.pull_count&label=下载次数&logo=docker)](https://hub.docker.com/r/cloudreve/cloudreve)
```bash
docker run -d \
  --name cloudreve \
  -p 5212:5212 \
  -p 6888:6888 \
  -p 6888:6888/udp \
  -v ~/cloudreve/data:/cloudreve/data \
  --restart=always \
  cloudreve/cloudreve:latest
```

## [Wxchat](https://github.com/wuyangdaily/wxchat)
[![GitHub release](https://img.shields.io/github/v/release/wuyangdaily/wxchat)](https://github.com/wuyangdaily/wxchat/releases) [![Docker Pulls](https://img.shields.io/badge/dynamic/json?url=https://hub.docker.com/v2/repositories/wuyangdaily/wxchat&query=$.pull_count&label=下载次数&logo=docker)](https://hub.docker.com/r/wuyangdaily/wxchat)
```bash
docker run -d \
  --name wxchat \
  -p 7080:80 \
  -e TZ=Asia/Shanghai \
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
  -v ~/certimate/data:/app/pb_data \
  -v /etc/localtime:/etc/localtime:ro \
  -v /etc/timezone:/etc/timezone:ro \
  --restart=always \
  certimate/certimate:latest
```

## [Komari](https://github.com/komari-monitor/komari) [主题](https://github.com/shanyang242/Komari-Theme-LuminaPlus)
[![GitHub release](https://img.shields.io/github/v/release/komari-monitor/komari)](https://github.com/komari-monitor/komari/releases) [![GitHub release](https://img.shields.io/github/v/release/shanyang242/Komari-Theme-LuminaPlus)](https://github.com/shanyang242/Komari-Theme-LuminaPlus/releases)
```bash
docker run -d \
  --name komari \
  -p 25774:25774 \
  -v ~/komari:/app/data \
  -e TZ=Asia/Shanghai \
  --restart=always \
  ghcr.io/komari-monitor/komari:latest
```
## Agent（Uninstall）
```bash
sudo systemctl stop komari-agent 2>/dev/null; \
sudo systemctl disable komari-agent 2>/dev/null; \
sudo systemctl reset-failed komari-agent 2>/dev/null; \
sudo rm -f /etc/systemd/system/komari-agent.service; \
sudo rm -rf /etc/systemd/system/komari-agent.service.d; \
sudo systemctl daemon-reload; \
sudo pkill -f /opt/komari/agent 2>/dev/null; \
sudo rm -rf /opt/komari; \
sudo rm -rf /etc/komari; \
sudo rm -f /var/log/komari-agent.log; \
sudo rm -rf /var/log/komari; \
systemctl status komari-agent --no-pager
```

## [NodeCtl](https://github.com/hobin66/nodectl)
[![GitHub release](https://img.shields.io/github/v/release/hobin66/nodectl)](https://github.com/hobin66/nodectl/releases) 
```bash
docker run -d \
  --name nodectl \
  -p 8080:8080 \
  -v ~/nodectl/data:/app/data \
  --restart=always \
  ghcr.io/hobin66/nodectl:latest
```

## [Moments-blog](https://github.com/zhoujun0601/moments-blog)
[![Docker Pulls](https://img.shields.io/docker/v/koalalove/moments-blog?sort=semver)](https://hub.docker.com/r/koalalove/moments-blog) [![Docker Pulls](https://img.shields.io/badge/dynamic/json?url=https://hub.docker.com/v2/repositories/koalalove/moments-blog&query=$.pull_count&label=下载次数&logo=docker)](https://hub.docker.com/r/koalalove/moments-blog)
- 用户名：`admin`
- 密码：`Strong1passwd!`
```bash
docker run -d \
  --name moments-blog \
  -p 5201:80 \
  -v ~/moments/data/postgres:/var/lib/postgresql/data \
  -v ~/moments/data/uploads:/data/uploads \
  -v ~/moments/data/logs:/data/logs \
  -e JWT_SECRET=$(openssl rand -hex 64) \
  -e DATABASE_URL=postgresql://moments:moments_password@127.0.0.1:5432/moments \
  -e NODE_ENV=production \
  -e PORT=3001 \
  -e UPLOAD_DIR=/data/uploads \
  -e INTERNAL_API_URL=http://localhost:3001 \
  -e PGDATA=/var/lib/postgresql/data \
  -e TRUST_PROXY=2 \
  --restart=always \
  koalalove/moments-blog:latest
```

## [Mihomo](https://github.com/MetaCubeX/mihomo) [配置](https://lanzoux.com/iaxEF3ocyref)
[![GitHub release](https://img.shields.io/github/v/release/MetaCubeX/mihomo)](https://github.com/MetaCubeX/mihomo/releases) [![Docker Pulls](https://img.shields.io/badge/dynamic/json?url=https://hub.docker.com/v2/repositories/metacubex/mihomo&query=$.pull_count&label=下载次数&logo=docker)](https://hub.docker.com/r/metacubex/mihomo)
```bash
docker run -d \
  --name mihomo \
  -v ~/mihomo:/root/.config/mihomo \
  -e TZ=Asia/Shanghai \
  --restart=always \
  --network=host \
  metacubex/mihomo:latest
```

## [Sub-Store](https://github.com/sub-store-org/Sub-Store)（订阅转换）
[![GitHub release](https://img.shields.io/github/v/release/sub-store-org/Sub-Store)](https://github.com/sub-store-org/Sub-Store/releases) [![Docker Pulls](https://img.shields.io/badge/dynamic/json?url=https://hub.docker.com/v2/repositories/xream/sub-store&query=$.pull_count&label=下载次数&logo=docker)](https://hub.docker.com/r/xream/sub-store)
```bash
docker run -d \
  --name sub-store \
  -v ~/sub-store:/opt/app/data \
  -e SUB_STORE_FRONTEND_BACKEND_PATH=/12345678 \
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
  -v ~/koipy/config.yaml:/app/config.yaml \
  -v ~/koipy/builtin:/app/resources/scripts/builtin \
  --network=host \
  --restart=always \
  koipy/koipy:dev
```

## [RustDesk](https://github.com/rustdesk/rustdesk)
[![GitHub release](https://img.shields.io/github/v/release/rustdesk/rustdesk)](https://github.com/rustdesk/rustdesk/releases)  [![Docker Pulls](https://img.shields.io/badge/dynamic/json?url=https://hub.docker.com/v2/repositories/lejianwen/rustdesk-server-s6&query=$.pull_count&label=下载次数&logo=docker)](https://hub.docker.com/r/lejianwen/rustdesk-server-s6)
- 签名：`codesign -s - --deep --force --timestamp=none /Applications/RustDesk.app`
```bash
docker run -d \
  --name rustdesk \
  -p 21114:21114 \
  -p 21115:21115 \
  -p 21116:21116 \
  -p 21116:21116/udp \
  -p 21117:21117 \
  -p 21118:21118 \
  -p 21119:21119 \
  -v ~/rustdesk/server:/data \
  -v ~/rustdesk/api:/app/data \
  -e RELAY=relay_server:21117 \
  -e ENCRYPTED_ONLY=1 \
  -e MUST_LOGIN=N \
  -e TZ=Asia/Shanghai \
  -e RUSTDESK_API_RUSTDESK_ID_SERVER=id_server:21116 \
  -e RUSTDESK_API_RUSTDESK_RELAY_SERVER=relay_server:21117 \
  -e RUSTDESK_API_RUSTDESK_API_SERVER=http://api_server:21114 \
  -e RUSTDESK_API_RUSTDESK_WS_HOST=api_server:21114 \
  -e RUSTDESK_API_KEY_FILE=/data/id_ed25519.pub \
  --restart=always \
  lejianwen/rustdesk-server-s6:latest
```

## [DockUP](https://github.com/shuijiao1/DockUP)
[![GitHub release](https://img.shields.io/github/v/release/shuijiao1/DockUP)](https://github.com/shuijiao1/DockUP/releases)
```bash
docker run -d \
  --name dockup \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -e TZ=Asia/Shanghai \
  -e TG_BOT_TOKEN=BOT_TOKEN \
  -e TG_CHAT_ID=CHAT_ID \
  -e CHECK_INTERVAL=12h \
  -e CLEANUP=true \
  -e SETUP_TEST_MESSAGE=true \
  -e HTTP_PROXY=http://127.0.0.1:7890 \
  -e HTTPS_PROXY=http://127.0.0.1:7890 \
  --network=host \
  --restart=always \
  ghcr.io/shuijiao1/dockup:latest
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
  userAgent: "ClashMetaForAndroid/2.8.9.Meta Mihomo/0.16" # UA设置，影响订阅获取
subscription: # 订阅获取相关配置
  age: # age 加密订阅解密配置，仅支持 age X25519 ASCII armor 格式；不依赖额外二进制
    enable: false # 是否启用 age 解密。开启后，Koipy 会在订阅下载成功后、解析/订阅转换前尝试解密 age armor 内容
    secretKey: "" # age X25519 私钥，格式 AGE-SECRET-KEY-...；启用 age 解密时必填
    publicKey: "" # age 公钥，格式 age1...；填写后请求订阅时会通过下面的 publicKeyHeader 发给订阅服务端
    publicKeyHeader: X-Age-Public-Key # 发送公钥使用的 HTTP 请求头名；服务端可用该公钥临时加密返回内容
webapi: # Web 配置 API（可选；前端面板已独立部署/维护）
  enable: false # 是否启用内置 Web 配置 API 服务，默认 false
  address: 127.0.0.1:8899 # 监听地址（host:port）
  password: "" # 访问密码；启用 webapi 时必填，留空会拒绝启动
  tls: false # 是否启用 HTTPS（TLS）
  tlsCertFile: "" # TLS 证书文件（PEM）。当 tls=true 时必填
  tlsKeyFile: "" # TLS 私钥文件（PEM）。可选，若证书文件已包含私钥可留空
  allowOrigins: # 允许跨域的来源列表
  - http://127.0.0.1:8899
  - http://localhost:8899
  - https://127.0.0.1:8899
  - https://localhost:8899
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
  showUnsafeTips: true # 是否在绘图的页脚里显示不安全的后端提示，不安全的后端是指：tls=true 并且 skipCertVerify=true 或者 tls=false
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
  enableDNSInject: false # 此配置无法设置为全局runtime配置。是否启用 mihomo DNS 注入。开启后会读取订阅中的 dns 字段并编码成 mihomo://base64... 插入到后端 dnsServer 第一项。
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
subconverter: # 订阅转换对接配置，可以把base64格式转换bot测试需要的Clash格式
  enable: true # 是否启用
  mode: substore # 可选 subconverter / substore / builtin，用于选择转换后端时自动推断端口，使用builtin代表用的内部自带的转换（实验性）
  template:
    backend: "http://$Host:$Port/download/sub?target=$Target&url=$EncodedURL"
  defaults:
    host: 127.0.0.1
    port: 3000
    target: ClashMeta
#callbacks: # http回调功能支持
#  onMessage: http://127.0.0.1:8080/onMessage # 回调地址，bot收到消息时,会向此地址发送POST请求，使用方法请看文档
#  onPreSend: http://127.0.0.1:8080/onPreSend # 回调地址，bot处理所有任务的前置动作后（比如选定后端、选定规则等），会向此地址发送POST请求，来完成一些操作，使用方法请看文档
#  onResult: http://127.0.0.1:8080/onResult # 回调地址，bot接受完测试结果后，会向此地址发送POST请求，可以用来添加/修改结果数据，使用方法请看文档
translation: # 翻译语言包
  lang: zh-CN # 启用哪个语言包，填的值为下面resources配置的键，默认zh-CN
  resources: # 翻译包在哪加载
    zh-CN: ./resources/localization/zh-CN.yml # 键随便填，值填文件路径，文件内容格式为yaml，具体请看文档
log-level: INFO # 日志文件日志等级，共有以下日志等级： [DEBUG, INFO, WARNING, ERROR, CRITICAL, DISABLE]，越后的等级日志越严重，DISABLE会禁用日志文件，日志存放在logs目录下。控制台日志等级不受此配置影响，始终为DEBUG等级
user: [] # 用户权限名单，不用自己设，推荐使用 /grant 指令添加用户权限
```
