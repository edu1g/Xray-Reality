#!/bin/bash

# ─────────────────────────────────────────────
#  4_config.sh — 生成 Xray 配置文件 (深度修复与架构优化版)
# ─────────────────────────────────────────────

# ─── Xray 配置生成入口 ───────────────────────
core_config() {
    echo -e "\n${CYAN}--- 4. 生成 Xray 配置文件 (Config) ---${PLAIN}"

    # ─── 1. 强力清理冲突配置 [解决 status=23] ────────────────
    echo -e "${INFO} 正在检查并清理系统冲突配置..."
    local dropin_dir="/etc/systemd/system/xray.service.d"
    # 强制删除可能导致读取失败的第三方残留文件
    rm -f "${dropin_dir}/10-donot_touch_single_conf.conf"
    mkdir -p "$dropin_dir"

    # ─── 2. 参数与环境校验 ──────────────────────
    if [ -z "$PORT_VISION" ] || [ -z "$PORT_XHTTP" ]; then
        echo -e "${RED}[FATAL] 端口参数丢失，请检查系统配置步骤。${PLAIN}"
        exit 1
    fi

    SNI_HOST="www.icloud.com"
    XRAY_BIN="/usr/local/bin/xray"
    OLD_CONFIG="/usr/local/etc/xray/config.json"
    mkdir -p /usr/local/etc/xray

    if [ ! -x "$XRAY_BIN" ]; then
        echo -e "${RED}[FATAL] 找不到 Xray 核心文件或不可执行。${PLAIN}"
        exit 1
    fi

    # ─── 3. 智能读取或生成节点信息 [防止解析 null 错误] ──────
    # 预检：只有当文件存在且是合法 JSON 时才尝试提取
    if [ -f "$OLD_CONFIG" ] && jq . "$OLD_CONFIG" >/dev/null 2>&1; then
        echo -e "${INFO} 检测到旧配置且格式正确，正在提取原有节点信息..."
        UUID=$(jq -r '.inbounds[0].settings.clients[0].id // empty' "$OLD_CONFIG")
        PRIVATE_KEY=$(jq -r '.inbounds[0].streamSettings.realitySettings.privateKey // empty' "$OLD_CONFIG")
        SHORT_ID=$(jq -r '.inbounds[0].streamSettings.realitySettings.shortIds[0] // empty' "$OLD_CONFIG")
        XHTTP_PATH=$(jq -r '.inbounds[] | select(.tag=="xhttp_node") | .streamSettings.xhttpSettings.path // empty' "$OLD_CONFIG")
    else
        echo -e "${WARN} 旧配置不存在或已损坏，将生成全新的节点信息..."
    fi

    # 兜底生成逻辑
    [ -z "$UUID" ] && UUID=$("$XRAY_BIN" uuid)
    if [ -z "$PRIVATE_KEY" ]; then
        keys_output=$("$XRAY_BIN" x25519)
        PRIVATE_KEY=$(echo "$keys_output" | grep -iE "^PrivateKey:" | head -n 1 | awk -F':' '{print $2}' | tr -d ' \r\n')
    fi
    [ -z "$SHORT_ID" ] && SHORT_ID=$(openssl rand -hex 4)
    [ -z "$XHTTP_PATH" ] && XHTTP_PATH="/$(openssl rand -hex 4)"

    # ─── 4. config.json 写入 (包含完整架构) ────────────────────
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

    # ─── 5. 权限与日志初始化 ────────────────────────
    echo -e "${INFO} 正在初始化日志权限..."
    mkdir -p /var/log/xray/
    chown -R nobody:nogroup /var/log/xray/ 2>/dev/null || chown -R nobody:nobody /var/log/xray/
    chmod -R 755 /var/log/xray/

    # ─── 6. Systemd 服务覆写配置 ────────────────────
    cat > /etc/systemd/system/xray.service.d/override.conf <<EOF
[Service]
LimitNOFILE=infinity
LimitNPROC=65535
TasksMax=infinity
Environment="XRAY_LOCATION_ASSET=/usr/local/share/xray/"
EOF

    # ─── 7. 配置文件有效性验证 ──────────────────────
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
