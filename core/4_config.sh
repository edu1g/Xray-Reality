#!/bin/bash

# ─────────────────────────────────────────────
#  4_config.sh — 生成 Xray 配置文件 (深度修复版)
# ─────────────────────────────────────────────

core_config() {
    echo -e "\n${CYAN}--- 4. 生成 Xray 配置文件 (Config) ---${PLAIN}"

    # 1. 强力清理冲突的 Drop-in 配置 [解决 status=23 报错的关键]
    echo -e "${INFO} 正在检查并清理系统冲突配置..."
    local dropin_dir="/etc/systemd/system/xray.service.d"
    
    # 强制删除可能导致读取失败的残留文件
    rm -f "${dropin_dir}/10-donot_touch_single_conf.conf"
    mkdir -p "$dropin_dir"

    # 2. 基础参数校验
    if [ -z "$PORT_VISION" ] || [ -z "$PORT_XHTTP" ]; then
        echo -e "${RED}[FATAL] 端口参数丢失，请检查系统配置步骤。${PLAIN}"
        exit 1
    fi

    SNI_HOST="www.icloud.com"
    XRAY_BIN="/usr/local/bin/xray"
    mkdir -p /usr/local/etc/xray

    # 3. 动态生成密钥与 UUID
    UUID=$("$XRAY_BIN" uuid)
    keys_output=$("$XRAY_BIN" x25519)
    # 提取私钥
    PRIVATE_KEY=$(echo "$keys_output" | grep -iE "^PrivateKey:" | awk -F':' '{print $2}' | tr -d ' \r\n')
    SHORT_ID=$(openssl rand -hex 4)
    XHTTP_PATH="/$(openssl rand -hex 4)"

    # 4. 写入完整架构的 config.json (包含 Inbounds 和 Outbounds)
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

    # 5. 权限补救 (解决日志写入权限导致的启动失败)
    echo -e "${INFO} 正在初始化日志权限..."
    mkdir -p /var/log/xray/
    chown -R nobody:nogroup /var/log/xray/ 2>/dev/null || chown -R nobody:nobody /var/log/xray/
    chmod -R 755 /var/log/xray/

    # 6. 重新生成标准 override.conf
    cat > "${dropin_dir}/override.conf" <<EOF
[Service]
LimitNOFILE=infinity
LimitNPROC=65535
TasksMax=infinity
Environment="XRAY_LOCATION_ASSET=/usr/local/share/xray/"
EOF

    systemctl daemon-reload >/dev/null 2>&1
    echo -e "${OK} Xray 架构修复完成，配置文件已生成。"
}
