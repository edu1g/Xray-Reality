#!/bin/bash

# ─────────────────────────────────────────────
#  4_config.sh — 修复版：保留原节点信息 + 解决冲突
# ─────────────────────────────────────────────

core_config() {
    echo -e "\n${CYAN}--- 4. 生成 Xray 配置文件 (Config) ---${PLAIN}"

    # 1. 强力清理系统级冲突配置 [解决 status=23]
    local dropin_dir="/etc/systemd/system/xray.service.d"
    rm -rf "${dropin_dir}/10-donot_touch_single_conf.conf"
    mkdir -p "$dropin_dir"

    # 2. 环境与变量准备
    XRAY_BIN="/usr/local/bin/xray"
    OLD_CONFIG="/usr/local/etc/xray/config.json"
    mkdir -p /usr/local/etc/xray

    # 3. 智能读取或生成节点信息 [防止删除节点信息]
    if [ -f "$OLD_CONFIG" ] && command -v jq &>/dev/null; then
        echo -e "${INFO} 检测到旧配置，正在提取原有节点信息..."
        UUID=$(jq -r '.inbounds[0].settings.clients[0].id' "$OLD_CONFIG")
        PRIVATE_KEY=$(jq -r '.inbounds[0].streamSettings.realitySettings.privateKey' "$OLD_CONFIG")
        SHORT_ID=$(jq -r '.inbounds[0].streamSettings.realitySettings.shortIds[0]' "$OLD_CONFIG")
        XHTTP_PATH=$(jq -r '.inbounds[] | select(.tag=="xhttp_node") | .streamSettings.xhttpSettings.path' "$OLD_CONFIG")
        # 端口保护：如果外部传入的端口为空，则沿用旧配置端口
        [ -z "$PORT_VISION" ] && PORT_VISION=$(jq -r '.inbounds[] | select(.tag=="vision_node") | .port' "$OLD_CONFIG")
        [ -z "$PORT_XHTTP" ] && PORT_XHTTP=$(jq -r '.inbounds[] | select(.tag=="xhttp_node") | .port' "$OLD_CONFIG")
    fi

    # 兜底逻辑：如果提取失败或为首次安装，则生成新信息
    [ -z "$UUID" ] && UUID=$("$XRAY_BIN" uuid)
    [ -z "$PRIVATE_KEY" ] && PRIVATE_KEY=$("$XRAY_BIN" x25519 | grep -iE "^PrivateKey:" | awk -F':' '{print $2}' | tr -d ' \r\n')
    [ -z "$SHORT_ID" ] && SHORT_ID=$(openssl rand -hex 4)
    [ -z "$XHTTP_PATH" ] && XHTTP_PATH="/$(openssl rand -hex 4)"
    [ -z "$PORT_VISION" ] && PORT_VISION=443
    [ -z "$PORT_XHTTP" ] && PORT_XHTTP=8080

    SNI_HOST="www.icloud.com"

    # 4. 写入完整架构 config.json (包含 Inbounds 与 Outbounds)
    cat > /usr/local/etc/xray/config.json <<EOF
{
  "log": { 
    "loglevel": "warning",
    "access": "/var/log/xray/access.log",
    "error": "/var/log/xray/error.log"
  },
  "dns": { "servers": [ "localhost" ] },
  "inbounds": [
    {
      "tag": "vision_node",
      "port": ${PORT_VISION},
      "protocol": "vless",
      "settings": {
        "clients": [ { "id": "${UUID}", "flow": "xtls-rprx-vision", "email": "admin" } ],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "tcp",
        "security": "reality",
        "realitySettings": {
          "show": false,
          "dest": "${SNI_HOST}:443",
          "serverNames": [ "${SNI_HOST}" ],
          "privateKey": "${PRIVATE_KEY}",
          "shortIds": [ "${SHORT_ID}" ],
          "fingerprint": "chrome"
        }
      },
      "sniffing": { "enabled": true, "destOverride": [ "http", "tls", "quic" ], "routeOnly": true }
    },
    {
      "tag": "xhttp_node",
      "port": ${PORT_XHTTP},
      "protocol": "vless",
      "settings": {
        "clients": [ { "id": "${UUID}", "email": "admin" } ],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "xhttp",
        "security": "reality",
        "xhttpSettings": { "path": "${XHTTP_PATH}" },
        "realitySettings": {
          "show": false,
          "dest": "${SNI_HOST}:443",
          "serverNames": [ "${SNI_HOST}" ],
          "privateKey": "${PRIVATE_KEY}",
          "shortIds": [ "${SHORT_ID}" ],
          "fingerprint": "chrome"
        }
      },
      "sniffing": { "enabled": true, "destOverride": [ "http", "tls", "quic" ], "routeOnly": true }
    }
  ],
  "outbounds": [
    { "protocol": "freedom", "tag": "direct" },
    {
      "tag": "warp_proxy",
      "protocol": "socks",
      "settings": { "servers": [ { "address": "127.0.0.1", "port": 40000 } ] }
    },
    { "protocol": "blackhole", "tag": "block" }
  ],
  "routing": {
    "domainStrategy": "${DOMAIN_STRATEGY:-IPIfNonMatch}",
    "rules": [
      { "type": "field", "ip": [ "geoip:private" ], "outboundTag": "block" },
      { "type": "field", "protocol": [ "bittorrent" ], "outboundTag": "block" }
    ]
  }
}
EOF

    # 5. 初始化系统权限
    mkdir -p /var/log/xray/
    chown -R nobody:nogroup /var/log/xray/ 2>/dev/null || chown -R nobody:nobody /var/log/xray/
    chmod -R 755 /var/log/xray/

    cat > "${dropin_dir}/override.conf" <<EOF
[Service]
LimitNOFILE=infinity
LimitNPROC=65535
TasksMax=infinity
Environment="XRAY_LOCATION_ASSET=/usr/local/share/xray/"
EOF

    systemctl daemon-reload >/dev/null 2>&1
    echo -e "${OK} Xray 节点信息已保留，配置文件更新完毕。"
}
