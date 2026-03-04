#!/bin/bash

# ─────────────────────────────────────────────
#  Xray 流量拦截管理器
# ─────────────────────────────────────────────

RED="\033[31m"; GREEN="\033[32m"; YELLOW="\033[33m"; CYAN="\033[36m"; GRAY="\033[90m"; PLAIN="\033[0m"

CONFIG_FILE="/usr/local/etc/xray/config.json"

UI_MESSAGE=""

# ─── 环境检查 ────────────────────────────────
if [ "$EUID" -ne 0 ]; then echo -e "${RED}请使用 sudo 运行此脚本！${PLAIN}"; exit 1; fi
if ! command -v jq &> /dev/null; then echo -e "${RED}错误: 未检测到 jq，请先安装 (apt install jq / yum install jq)。${PLAIN}"; exit 1; fi

clear

# ─── 状态读取 ────────────────────────────────
get_status() {
    if jq -e '.routing.rules[] | select(.outboundTag=="block" and (.protocol | index("bittorrent")))' "$CONFIG_FILE" >/dev/null 2>&1; then
        STATUS_BT="${GREEN}已封禁 (Safe)${PLAIN}"
        IS_BT_BLOCKED=true
    else
        STATUS_BT="${YELLOW}未封禁 (Risk)${PLAIN}"
        IS_BT_BLOCKED=false
    fi

    if jq -e '.routing.rules[] | select(.outboundTag=="block" and (.ip | index("geoip:private")))' "$CONFIG_FILE" >/dev/null 2>&1; then
        STATUS_PRIVATE="${GREEN}已封禁 (Safe)${PLAIN}"
        IS_PRIVATE_BLOCKED=true
    else
        STATUS_PRIVATE="${YELLOW}未封禁 (Risk)${PLAIN}"
        IS_PRIVATE_BLOCKED=false
    fi
}

# ─── 应用配置 & 重启服务 ─────────────────────
apply_changes() {
    systemctl restart xray >/dev/null 2>&1
}

# ─── BT / P2P 拦截开关 ───────────────────────
toggle_bt() {
    if [ "$IS_BT_BLOCKED" = true ]; then
        jq 'del(.routing.rules[] | select(.outboundTag=="block" and (.protocol | index("bittorrent"))))' "$CONFIG_FILE" > "${CONFIG_FILE}.tmp" && mv "${CONFIG_FILE}.tmp" "$CONFIG_FILE"
        UI_MESSAGE="${YELLOW}已解除 BT/P2P 限制${PLAIN}"
    else
        local new_rule='{"type": "field", "protocol": ["bittorrent"], "outboundTag": "block"}'
        jq --argjson rule "$new_rule" '.routing.rules = [$rule] + .routing.rules' "$CONFIG_FILE" > "${CONFIG_FILE}.tmp" && mv "${CONFIG_FILE}.tmp" "$CONFIG_FILE"
        UI_MESSAGE="${GREEN}已封禁 BT/P2P 流量${PLAIN}"
    fi
    apply_changes
}

# ─── 私有 IP 拦截开关 ────────────────────────
toggle_private() {
    if [ "$IS_PRIVATE_BLOCKED" = true ]; then
        jq 'del(.routing.rules[] | select(.outboundTag=="block" and (.ip | index("geoip:private"))))' "$CONFIG_FILE" > "${CONFIG_FILE}.tmp" && mv "${CONFIG_FILE}.tmp" "$CONFIG_FILE"
        UI_MESSAGE="${YELLOW}已解除私有 IP 限制${PLAIN}"
    else
        local new_rule='{"type": "field", "ip": ["geoip:private"], "outboundTag": "block"}'
        jq --argjson rule "$new_rule" '.routing.rules = [$rule] + .routing.rules' "$CONFIG_FILE" > "${CONFIG_FILE}.tmp" && mv "${CONFIG_FILE}.tmp" "$CONFIG_FILE"
        UI_MESSAGE="${GREEN}已封禁私有 IP 流量${PLAIN}"
    fi
    apply_changes
}

# ─── 菜单界面 ────────────────────────────────
show_menu() {
    tput cup 0 0
    echo -e "${CYAN}===================================================${PLAIN}\033[K"
    echo -e "${CYAN}          流量拦截管理 (Traffic Blocker)          ${PLAIN}\033[K"
    echo -e "${CYAN}===================================================${PLAIN}\033[K"
    echo -e "  BT / P2P 下载   : ${STATUS_BT}\033[K"
    echo -e "  私有 IP (局域网): ${STATUS_PRIVATE}\033[K"
    echo -e "---------------------------------------------------\033[K"
    echo -e "  1. 启用 / 禁止 ${YELLOW}BT 下载${PLAIN}\033[K"
    echo -e "  2. 启用 / 禁止 ${YELLOW}私有 IP (局域网)${PLAIN}\033[K"
    echo -e "---------------------------------------------------\033[K"
    echo -e "  0. 退出 (Exit)\033[K"
    echo -e "===================================================\033[K"
    if [ -n "$UI_MESSAGE" ]; then
        echo -e "${YELLOW}当前操作${PLAIN}: ${UI_MESSAGE}\033[K"
    else
        echo -e "${YELLOW}当前操作${PLAIN}: ${GRAY}等待输入...${PLAIN}\033[K"
    fi
    echo -e "===================================================\033[K"
    tput ed
    UI_MESSAGE=""
}

# ─── 主循环 ──────────────────────────────────
while true; do
    get_status
    show_menu

    error_msg=""
    while true; do
        if [ -n "$error_msg" ]; then
            echo -ne "\r\033[K${RED}${error_msg}${PLAIN} 请输入选项 [0-2]: "
        else
            echo -ne "\r\033[K请输入选项 [biddu0-2]: "
        fi
        read -r choice
        case "$choice" in
            1|2|0) break ;;
            *) error_msg="输入无效！"; echo -ne "\033[1A" ;;
        esac
    done

    case "$choice" in
        1) toggle_bt ;;
        2) toggle_private ;;
        0) clear; exit 0 ;;
    esac
done
