#!/bin/bash

# ─────────────────────────────────────────────
#  4_config.sh — 生成 Xray 配置文件 (已集成 status=23 修复)
# ─────────────────────────────────────────────

# ─── Xray 配置生成入口 ───────────────────────
core_config() {
    echo -e "\n${CYAN}--- 4. 生成 Xray 配置文件 (Config) ---${PLAIN}"

    # ─── 参数与环境校验 ──────────────────────
    if [ -z "$PORT_VISION" ] || [ -z "$PORT_XHTTP" ]; then
        echo -e "${RED}[FATAL] 端口参数丢失，请检查系统配置步骤。${PLAIN}"
        exit 1
    fi

    SNI_HOST="www.icloud.com"
    echo -e "${OK} 使用 SNI 域名: ${GREEN}${SNI_HOST}${PLAIN}"

    mkdir -p /usr/local/etc/xray
    XRAY_BIN="/usr/local/bin/xray"

    if [ ! -x "$XRAY_BIN" ]; then
        echo -e "${RED}[FATAL] 找不到 Xray 核心文件或不可执行，请检查安装步骤。${PLAIN}"
        exit 1
    fi

    # ─── 密钥对与 UUID 生成 ──────────────────
    echo -e "${INFO} 正在生成密钥对与 UUID..."

    UUID=$("$XRAY_BIN" uuid)
    local keys_output
    keys_output=$("$XRAY_BIN" x25519)

    PRIVATE_KEY=$(echo "$keys_output" | grep -iE "^PrivateKey:"          | head -n 1 | awk -F':' '{print $2}' | tr -d ' \r\n')
    PUBLIC_KEY=$(echo  "$keys_output" | grep -iE "^(PublicKey|Password):" | head -n 1 | awk -F':' '{print $2}' | tr -d ' \r\n')

    SHORT_ID=$(openssl rand -hex 4)
    XHTTP_PATH="/$(openssl rand -hex 4)"

    if [ -z "$UUID" ] || [ -z "$PRIVATE_KEY" ] || [ -z "$PUBLIC_KEY" ]; then
        echo -e "${ERR} 密钥生成失败或解析异常，无法继续。"
        exit 1
    fi

    # ─── config.json 写入 ────────────────────
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
    { "protocol": "freedom",   "tag": "direct" },
    { "protocol": "blackhole", "tag": "block"  }
  ],
  "routing": {
    "domainStrategy": "${DOMAIN_STRATEGY:-IPIfNonMatch}",
    "rules": [
      { "type": "field", "ip":       [ "geoip:private" ], "outboundTag": "block" },
      { "type": "field", "protocol": [ "bittorrent" ],     "outboundTag": "block" }
    ]
  }
}
EOF

    # ─── 关键修复：初始化日志目录与权限 ───
    # 解决 status=23 报错的核心步骤
    echo -e "${INFO} 正在初始化日志权限..."
    mkdir -p /var/log/xray/
    if getent group nogroup > /dev/null; then
        chown -R nobody:nogroup /var/log/xray/
    else
        chown -R nobody:nobody /var/log/xray/
    fi
    chmod -R 755 /var/log/xray/

    # ─── Systemd 服务覆写配置 ────────────────
    # 清除可能存在的第三方冲突配置文件
    rm -f /etc/systemd/system/xray.service.d/10-donot_touch_single_conf.conf

    mkdir -p /etc/systemd/system/xray.service.d
    cat > /etc/systemd/system/xray.service.d/override.conf <<EOF
[Service]
LimitNOFILE=infinity
LimitNPROC=65535
TasksMax=infinity
Environment="XRAY_LOCATION_ASSET=/usr/local/share/xray/"
EOF

    # ─── 配置文件有效性验证 ──────────────────
    echo -e "${INFO} 正在验证配置文件有效性..."
    if "$XRAY_BIN" run -test -confdir /usr/local/etc/xray >/dev/null 2>&1; then
        echo -e "${OK} Xray 配置验证通过 (Syntax OK)"
    else
        echo -e "${RED}[FATAL] 生成的配置文件无效。${PLAIN}"
        "$XRAY_BIN" run -test -confdir /usr/local/etc/xray
        exit 1
    fi

    systemctl daemon-reload >/dev/null 2>&1
    echo -e "${OK} Xray 配置文件生成完毕。"
}
