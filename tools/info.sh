#!/bin/bash

# ─────────────────────────────────────────────
#  Xray 配置信息查看器
# ─────────────────────────────────────────────

RED="\033[31m"; GREEN="\033[32m"; YELLOW="\033[33m"; CYAN="\033[36m"; GRAY="\033[90m"; PLAIN="\033[0m"

CONFIG_FILE="/usr/local/etc/xray/config.json"
SSH_CONFIG="/etc/ssh/sshd_config"
XRAY_BIN="/usr/local/bin/xray"

# ─── 环境检查 ────────────────────────────────
if ! command -v jq &> /dev/null; then echo -e "${RED}Error: 缺少 jq 依赖。${PLAIN}"; exit 1; fi

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
if [ -n "$PRIVATE_KEY" ] && [ -x "$XRAY_BIN" ]; then
    RAW_OUTPUT=$($XRAY_BIN x25519 -i "$PRIVATE_KEY")
    PUBLIC_KEY=$(echo "$RAW_OUTPUT" | grep -iE "Public|Password" | head -n 1 | awk -F':' '{print $2}' | tr -d ' \r\n')
fi
if [ -z "$PUBLIC_KEY" ]; then echo -e "${RED}严重错误：无法计算公钥！${PLAIN}"; exit 1; fi

# ─── 公网 IP 获取 ────────────────────────────
IPV4=$(curl -s4m 1 https://api.ipify.org || echo "N/A")
IPV6=$(curl -s6m 1 https://api64.ipify.org || echo "N/A")

# ─── 分享链接生成 ────────────────────────────
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

printf " ${CYAN}%-12s${PLAIN} : %s\n"         "SSH"         "${SSH_PORT}"
printf " ${CYAN}%-12s${PLAIN} : %s\n"         "IPv4"        "${IPV4}"
printf " ${CYAN}%-12s${PLAIN} : %s\n"         "IPv6"        "${IPV6}"
printf " ${CYAN}%-12s${PLAIN} : %s\n"         "SNI"         "${SNI_HOST}"
printf " ${CYAN}%-12s${PLAIN} : %s\n"         "UUID"        "${UUID}"
printf " ${CYAN}%-12s${PLAIN} : %s\n"         "Short ID"    "${SHORT_ID}"
printf " ${CYAN}%-12s${PLAIN} : %s (客户端)\n" "Public Key"  "${PUBLIC_KEY}"
printf " ${CYAN}%-12s${PLAIN} : %s (服务端)\n" "Private Key" "${PRIVATE_KEY}"

echo -e "${SEP}"

printf " ${CYAN}%-12s${PLAIN} : ${CYAN}端口:${PLAIN} %-6s ${CYAN}流控:${PLAIN} %s\n" \
  "Vision" "${PORT_VISION}" "xtls-rprx-vision"

printf " ${CYAN}%-12s${PLAIN} : ${CYAN}端口:${PLAIN} %-6s ${CYAN}协议:${PLAIN} %-16s ${CYAN}Path:${PLAIN} %s\n" \
  "xhttp" "${PORT_XHTTP}" "xhttp" "${XHTTP_PATH}"

echo -e "${SEP}"

# ─── 分享链接输出 ────────────────────────────
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

# ─── 二维码展示 ──────────────────────────────
read -n 1 -p "是否展示二维码？[y/N] " CHOICE
echo
if [[ "$CHOICE" =~ ^[yY]$ ]]; then
    if [[ -n "$LINK_V4_VIS" ]]; then
        echo -e "\n${CYAN}IPv4 Vision:${PLAIN}"
        qrencode -t ANSIUTF8 "${LINK_V4_VIS}"
        echo -e "\n${CYAN}IPv4 XHTTP :${PLAIN}"
        qrencode -t ANSIUTF8 "${LINK_V4_XHT}"
    fi
    if [[ -n "$LINK_V6_VIS" ]]; then
        echo -e "\n${CYAN}IPv6 Vision:${PLAIN}"
        qrencode -t ANSIUTF8 "${LINK_V6_VIS}"
        echo -e "\n${CYAN}IPv6 XHTTP :${PLAIN}"
        qrencode -t ANSIUTF8 "${LINK_V6_XHT}"
    fi
fi

# ─── 管理命令速查 ────────────────────────────
echo -e "\n---------------------------------------------------------------------------------------------------------------------------------"
echo -e " ${CYAN}管理命令:${PLAIN}"
echo -e " ${YELLOW}info${PLAIN} (管理员信息) | ${YELLOW}net${PLAIN} (网络) | ${YELLOW}xw${PLAIN} (WARP分流) | ${YELLOW}swap${PLAIN}  (内存) | ${YELLOW}backup${PLAIN} (备份) | ${YELLOW}f2b${PLAIN} (防火墙) | ${YELLOW}sniff${PLAIN}  (流量嗅探)"
echo -e " ${YELLOW}user${PLAIN} (多用户管理) | ${YELLOW}sni${PLAIN} (域名) | ${YELLOW}bt${PLAIN} (BT封禁)   | ${YELLOW}ports${PLAIN} (端口) | ${YELLOW}zone${PLAIN}   (时区) | ${YELLOW}bbr${PLAIN} (内核)   | ${YELLOW}updata${PLAIN} (内核更新) | ${YELLOW}remove${PLAIN} (卸载)"
echo -e "---------------------------------------------------------------------------------------------------------------------------------"
echo ""
