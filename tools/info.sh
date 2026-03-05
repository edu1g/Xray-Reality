#!/bin/bash

# ─────────────────────────────────────────────────────────────────────────────
#  Xray 配置信息查看器
# ─────────────────────────────────────────────────────────────────────────────

RED="\033[31m"; GREEN="\033[32m"; YELLOW="\033[33m"; CYAN="\033[36m"; GRAY="\033[90m"; PLAIN="\033[0m"

CONFIG_FILE="/usr/local/etc/xray/config.json"
SSH_CONFIG="/etc/ssh/sshd_config"
XRAY_BIN="/usr/local/bin/xray"

# ─── 环境检查 ────────────────────────────────
if [ ! -f "$CONFIG_FILE" ]; then
    echo -e "${RED}Error: 配置文件不存在: ${CONFIG_FILE}${PLAIN}"
    exit 1
fi

if ! command -v jq &>/dev/null; then
    echo -e "${RED}Error: 缺少 jq 依赖。${PLAIN}"
    exit 1
fi

if [ ! -x "$XRAY_BIN" ]; then
    echo -e "${RED}Error: 找不到 Xray 核心文件或不可执行: ${XRAY_BIN}${PLAIN}"
    exit 1
fi

# ─── 基础信息读取 ────────────────────────────
SSH_PORT=$(grep "^Port" "$SSH_CONFIG" | head -n 1 | awk '{print $2}')
[ -z "$SSH_PORT" ] && SSH_PORT=22
HOST_NAME=$(hostname)

# ─── Xray 配置解析 ───────────────────────────
UUID=$(jq -r '.inbounds[0].settings.clients[0].id' "$CONFIG_FILE")
PRIVATE_KEY=$(jq -r '.inbounds[0].streamSettings.realitySettings.privateKey' "$CONFIG_FILE")
SHORT_ID=$(jq -r '.inbounds[0].streamSettings.realitySettings.shortIds[0]' "$CONFIG_FILE")
SNI_HOST=$(jq -r '.inbounds[0].streamSettings.realitySettings.serverNames[0]' "$CONFIG_FILE")
PORT_VISION=$(jq -r '.inbounds[] | select(.tag=="vision_node") | .port' "$CONFIG_FILE")
PORT_XHTTP=$(jq -r '.inbounds[] | select(.tag=="xhttp_node") | .port' "$CONFIG_FILE")
XHTTP_PATH=$(jq -r '.inbounds[] | select(.tag=="xhttp_node") | .streamSettings.xhttpSettings.path' "$CONFIG_FILE")

# ─── 公钥计算 ────────────────────────────────
RAW_OUTPUT=$("$XRAY_BIN" x25519 -i "$PRIVATE_KEY")
PUBLIC_KEY=$(echo "$RAW_OUTPUT" | grep -iE "Public|Password" | head -n 1 | awk -F':' '{print $2}' | tr -d ' \r\n')

if [ -z "$PUBLIC_KEY" ]; then
    echo -e "${RED}严重错误：公钥计算失败或解析异常！${PLAIN}"
    exit 1
fi

# ─── IP 获取 ────────────────────────────
IPV4=$(curl -s4 -m 3 https://api.ipify.org 2>/dev/null || echo "N/A")
IPV6=$(curl -s6 -m 3 https://api64.ipify.org 2>/dev/null || echo "N/A")

# ─── 链接生成 ────────────────────────────
LINK_V4_VIS=""
LINK_V4_XHT=""
if [[ "$IPV4" != "N/A" ]]; then
    LINK_V4_VIS="vless://${UUID}@${IPV4}:${PORT_VISION}?security=reality&encryption=none&pbk=${PUBLIC_KEY}&headerType=none&fp=chrome&type=tcp&flow=xtls-rprx-vision&sni=${SNI_HOST}&sid=${SHORT_ID}#${HOST_NAME}_IPv4_Vision"
    LINK_V4_XHT="vless://${UUID}@${IPV4}:${PORT_XHTTP}?security=reality&encryption=none&pbk=${PUBLIC_KEY}&headerType=none&fp=chrome&type=xhttp&path=${XHTTP_PATH}&sni=${SNI_HOST}&sid=${SHORT_ID}#${HOST_NAME}_IPv4_xhttp"
fi

LINK_V6_VIS=""
LINK_V6_XHT=""
if [[ "$IPV6" != "N/A" ]]; then
    LINK_V6_VIS="vless://${UUID}@[${IPV6}]:${PORT_VISION}?security=reality&encryption=none&pbk=${PUBLIC_KEY}&headerType=none&fp=chrome&type=tcp&flow=xtls-rprx-vision&sni=${SNI_HOST}&sid=${SHORT_ID}#${HOST_NAME}_IPv6_Vision"
    LINK_V6_XHT="vless://${UUID}@[${IPV6}]:${PORT_XHTTP}?security=reality&encryption=none&pbk=${PUBLIC_KEY}&headerType=none&fp=chrome&type=xhttp&path=${XHTTP_PATH}&sni=${SNI_HOST}&sid=${SHORT_ID}#${HOST_NAME}_IPv6_xhttp"
fi

# ─── 配置信息展示 ────────────────────────────
clear
SEP="${CYAN}=====================================================================${PLAIN}"

echo -e "${SEP}"
echo -e "${CYAN} Xray 配置信息 (Info) ${PLAIN}"
echo -e "${SEP}"

printf " ${CYAN}%-12s${PLAIN} : %s\n"          "SSH"         "${SSH_PORT}"
printf " ${CYAN}%-12s${PLAIN} : %s\n"          "IPv4"        "${IPV4}"
printf " ${CYAN}%-12s${PLAIN} : %s\n"          "IPv6"        "${IPV6}"
printf " ${CYAN}%-12s${PLAIN} : %s\n"          "SNI"         "${SNI_HOST}"
printf " ${CYAN}%-12s${PLAIN} : %s\n"          "UUID"        "${UUID}"
printf " ${CYAN}%-12s${PLAIN} : %s\n"          "Short ID"    "${SHORT_ID}"
printf " ${CYAN}%-12s${PLAIN} : %s (客户端)\n" "Public Key"  "${PUBLIC_KEY}"
printf " ${CYAN}%-12s${PLAIN} : %s (服务端)\n" "Private Key" "${PRIVATE_KEY}"

echo -e "${SEP}"

printf " ${CYAN}%-12s${PLAIN} : ${CYAN}端口:${PLAIN} %-6s ${CYAN}流控:${PLAIN} %s\n" \
  "Vision" "${PORT_VISION}" "xtls-rprx-vision"

printf " ${CYAN}%-12s${PLAIN} : ${CYAN}端口:${PLAIN} %-6s ${CYAN}协议:${PLAIN} %-16s ${CYAN}Path:${PLAIN} %s\n" \
  "xhttp" "${PORT_XHTTP}" "xhttp" "${XHTTP_PATH}"

echo -e "${SEP}"

# ─── vless 链接 ───
if [[ -n "$LINK_V4_VIS" ]]; then
    echo -e "\n${CYAN}IPv4 Vision:${PLAIN}"
    echo -e "${LINK_V4_VIS}"
    echo -e "\n${CYAN}IPv4 XHTTP :${PLAIN}"
    echo -e "${LINK_V4_XHT}"
    echo ""
fi

if [[ -n "$LINK_V6_VIS" ]]; then
    echo -e "${CYAN}IPv6 Vision:${PLAIN}"
    echo -e "${LINK_V6_VIS}"
    echo -e "\n${CYAN}IPv6 XHTTP :${PLAIN}"
    echo -e "${LINK_V6_XHT}"
    echo ""
fi

# ─── 订阅二维码 ──────────────────────────
if ! command -v qrencode &>/dev/null; then
    echo -e "${RED}Error: 缺少 qrencode 依赖，无法生成二维码。${PLAIN}"
elif ! command -v python3 &>/dev/null; then
    echo -e "${RED}Error: 缺少 python3，无法启动临时订阅服务。${PLAIN}"
else
    # ─── 收集所有可用链接 ────────────────────
    ALL_LINKS=""
    [[ -n "$LINK_V4_VIS" ]] && ALL_LINKS+="${LINK_V4_VIS}\n"
    [[ -n "$LINK_V4_XHT" ]] && ALL_LINKS+="${LINK_V4_XHT}\n"
    [[ -n "$LINK_V6_VIS" ]] && ALL_LINKS+="${LINK_V6_VIS}\n"
    [[ -n "$LINK_V6_XHT" ]] && ALL_LINKS+="${LINK_V6_XHT}\n"

    if [ -z "$ALL_LINKS" ]; then
        echo -e "${RED}Error: 未检测到任何可用链接，请确认网络状态。${PLAIN}"
    else
        # ─── 随机选取 10000 以上的空闲端口 ──────
        _pick_sub_port() {
            local port attempt=0
            while [ $attempt -lt 100 ]; do
                port=$(shuf -i 10000-65535 -n 1)
                if ! lsof -i:"$port" -P -n >/dev/null 2>&1 \
                    && [ "$port" != "$PORT_VISION" ] \
                    && [ "$port" != "$PORT_XHTTP" ] \
                    && [ "$port" != "$SSH_PORT" ]; then
                    echo "$port"
                    return 0
                fi
                ((attempt++))
            done
            echo -e "${RED}Error: 无法找到可用端口，请检查系统端口占用情况。${PLAIN}" >&2
            return 1
        }

        SUB_PORT=$(_pick_sub_port) || exit 1

        # ─── 临时开放防火墙入站规则 ──
        _fw_open_sub_port() {
            iptables  -A INPUT -p tcp --dport "$SUB_PORT" -j ACCEPT 2>/dev/null
            if [ -f /proc/net/if_inet6 ]; then
                ip6tables -A INPUT -p tcp --dport "$SUB_PORT" -j ACCEPT 2>/dev/null
            fi
        }

        # ─── 服务结束后撤销防火墙规则 ────────────
        _fw_close_sub_port() {
            iptables  -D INPUT -p tcp --dport "$SUB_PORT" -j ACCEPT 2>/dev/null
            if [ -f /proc/net/if_inet6 ]; then
                ip6tables -D INPUT -p tcp --dport "$SUB_PORT" -j ACCEPT 2>/dev/null
            fi
        }

        # ─── 注册信号捕获，确保异常退出时规则同样被清理 ──
        trap '_fw_close_sub_port; rm -rf "$SUB_DIR"; exit' INT TERM EXIT

        # ─── 生成 base64 订阅内容并写入临时目录 ──
        SUB_CONTENT=$(printf "%b" "$ALL_LINKS" | base64 -w 0)
        SUB_DIR=$(mktemp -d)
        printf "%s" "$SUB_CONTENT" > "$SUB_DIR/sub"

        _fw_open_sub_port

        # ─── 启动临时 HTTP 服务（60 秒）──
        python3 -c "
import http.server, os, threading
os.chdir('$SUB_DIR')
class H(http.server.SimpleHTTPRequestHandler):
    def log_message(self, *a): pass
    def do_GET(self):
        if self.path != '/sub':
            self.send_error(404)
            return
        with open('sub', 'rb') as f:
            content = f.read()
        self.send_response(200)
        self.send_header('Content-Type', 'text/plain; charset=utf-8')
        self.send_header('Content-Length', str(len(content)))
        self.send_header('Cache-Control', 'no-cache')
        self.end_headers()
        self.wfile.write(content)
srv = http.server.HTTPServer(('0.0.0.0', $SUB_PORT), H)
threading.Timer(60, srv.shutdown).start()
srv.serve_forever()
" &
        HTTP_PID=$!

        # ─── 生成订阅 URL ─────────────────
        if [[ "$IPV4" != "N/A" ]]; then
            SUB_HOST="$IPV4"
        else
            SUB_HOST="[$IPV6]"
        fi
        SUB_URL="http://${SUB_HOST}:${SUB_PORT}/sub"

        NODE_COUNT=$(printf "%b" "$ALL_LINKS" | grep -c 'vless://')
        echo -e "\n${CYAN}订阅地址（含 ${NODE_COUNT} 个节点）:${PLAIN}"
        echo -e "${YELLOW}${SUB_URL}${PLAIN}\n"
        echo -e "${CYAN}订阅二维码（60s 内有效）:${PLAIN}\n"
        qrencode -t ANSIUTF8 "${SUB_URL}"
		echo -e ""

        # ─── 倒计时提示 ──────────────────────────
        tput civis
        for ((i=60; i>=0; i--)); do
            if [ $i -gt 0 ]; then
                printf "\r\033[90m已开放临时端口 ${SUB_PORT}，\033[31m%2d\033[90m 秒后自动关闭并撤销防火墙规则。\033[0m" "$i"
            else
                printf "\r\033[32m已撤销临时端口 ${SUB_PORT}，并清理临时防火墙规则。                    \033[0m"
            fi
            sleep 1
        done
        tput cnorm
        echo

        # ─── 等待服务退出并清理 ──────────────────
        wait "$HTTP_PID" 2>/dev/null
        rm -rf "$SUB_DIR"
        _fw_close_sub_port
        trap - INT TERM EXIT
    fi
fi

# ─── 管理命令速查 ────────────────────────────
echo -e "\n---------------------------------------------------------------------------------------------------------------------------------"
echo -e " ${CYAN}管理命令:${PLAIN}"
echo -e " ${YELLOW}info${PLAIN} (管理员信息) | ${YELLOW}net${PLAIN} (网络) | ${YELLOW}xw${PLAIN} (WARP分流) | ${YELLOW}swap${PLAIN}  (内存) | ${YELLOW}backup${PLAIN} (备份) | ${YELLOW}f2b${PLAIN} (防火墙) | ${YELLOW}sniff${PLAIN}  (流量嗅探)"
echo -e " ${YELLOW}user${PLAIN} (多用户管理) | ${YELLOW}sni${PLAIN} (域名) | ${YELLOW}bt${PLAIN} (BT封禁)   | ${YELLOW}ports${PLAIN} (端口) | ${YELLOW}zone${PLAIN}   (时区) | ${YELLOW}bbr${PLAIN} (内核)   | ${YELLOW}update${PLAIN} (内核更新) | ${YELLOW}remove${PLAIN} (卸载)"
echo -e "---------------------------------------------------------------------------------------------------------------------------------"
echo ""
