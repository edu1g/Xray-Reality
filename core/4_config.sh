#!/bin/bash

# ─────────────────────────────────────────────
#  4_config.sh — 生成 Xray 配置文件 (纯净架构版)
# ─────────────────────────────────────────────

core_config() {
    echo -e "\n${CYAN}--- 4. 生成 Xray 配置文件 (Config) ---${PLAIN}"

    # 基础参数校验
    if [ -z "$PORT_VISION" ] || [ -z "$PORT_XHTTP" ]; then
        echo -e "${RED}[FATAL] 端口参数丢失，请检查系统配置步骤。${PLAIN}"
        exit 1
    fi

    SNI_HOST="www.icloud.com" # 默认 SNI 伪装域名
    XRAY_BIN="/usr/local/bin/xray"
    mkdir -p /usr/local/etc/xray

    # 动态生成密钥与唯一识别码
    UUID=$("$XRAY_BIN" uuid)
    keys_output=$("$XRAY_BIN" x25519)
    PRIVATE_KEY=$(echo "$keys_output" | grep -iE "^PrivateKey:" | awk -F':' '{print $2}' | tr -d ' \r\n')
    SHORT_ID=$(openssl rand -hex 4)
    XHTTP_PATH="/$(openssl rand -hex 4)"

    # 写入纯净版 config.json，不含任何预设分流域名
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

    # 权限补救逻辑
    echo -e "${INFO} 正在初始化日志权限..."
    mkdir -p /var/log/xray/
    chown -R nobody:nogroup /var/log/xray/ 2>/dev/null || chown -R nobody:nobody /var/log/xray/
    chmod -R 755 /var/log/xray/

    # 部署 Systemd 优化配置
    mkdir -p /etc/systemd/system/xray.service.d
    cat > /etc/systemd/system/xray.service.d/override.conf <<EOF
[Service]
LimitNOFILE=infinity
LimitNPROC=65535
TasksMax=infinity
Environment="XRAY_LOCATION_ASSET=/usr/local/share/xray/"
EOF

    systemctl daemon-reload >/dev/null 2>&1
    echo -e "${OK} Xray 配置文件生成完毕。"
}
