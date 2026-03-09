#!/bin/bash

# ─────────────────────────────────────────────
#  Xray WARP 分流管理器 (优化版：全自动安装与增强面板)
# ─────────────────────────────────────────────

RED="\033[31m"; GREEN="\033[32m"; YELLOW="\033[33m"; CYAN="\033[36m"; GRAY="\033[90m"; PLAIN="\033[0m"

CONFIG_FILE="/usr/local/etc/xray/config.json"
WARP_PORT=40000

UI_MESSAGE=""

# ─── 环境检查 ────────────────────────────────
if [ "$EUID" -ne 0 ]; then echo -e "${RED}请使用 sudo 运行此脚本！${PLAIN}"; exit 1; fi

# ─── 数据读取 ────────────────────────────────
# 获取 WARP 代理后的 IP 信息
get_warp_ip() {
    local res
    res=$(curl -s4m 2 --proxy socks5h://127.0.0.1:$WARP_PORT https://www.cloudflare.com/cdn-cgi/trace | grep -E "ip=|loc=" | awk -F= '{print $2}' | xargs)
    if [ -n "$res" ]; then
        echo -e "${GREEN}${res}${PLAIN}"
    else
        echo -e "${RED}无法获取${PLAIN}"
    fi
}

# 获取本机真实 IP 信息
get_main_ip() {
    local res
    res=$(curl -s4m 2 https://www.cloudflare.com/cdn-cgi/trace | grep -E "ip=|loc=" | awk -F= '{print $2}' | xargs)
    echo -e "${CYAN}${res}${PLAIN}"
}

# 获取当前已配置的分流域名
get_split_domains() {
    local domains
    domains=$(jq -r '.routing.rules[] | select(.outboundTag=="warp_proxy") | .domain[]' "$CONFIG_FILE" 2>/dev/null | xargs)
    if [ -n "$domains" ]; then
        echo -e "${YELLOW}${domains}${PLAIN}"
    else
        echo -e "${GRAY}未配置${PLAIN}"
    fi
}

# ─── WARP 连通性检测 ─────────────────────────
check_warp_socket() {
    (echo > /dev/tcp/127.0.0.1/$WARP_PORT) >/dev/null 2>&1
}

# ─── Xray 配置操作 ───────────────────────────
check_xray_outbound() {
    jq -e '.outbounds[] | select(.tag=="warp_proxy")' "$CONFIG_FILE" >/dev/null 2>&1
}

ensure_outbound() {
    if check_xray_outbound; then return; fi
    local out_obj='{"tag": "warp_proxy", "protocol": "socks", "settings": {"servers": [{"address": "127.0.0.1", "port": '$WARP_PORT'}]}}'
    jq --argjson obj "$out_obj" '.outbounds += [$obj]' "$CONFIG_FILE" > "${CONFIG_FILE}.tmp" && mv "${CONFIG_FILE}.tmp" "$CONFIG_FILE"
}

# ─── 安装 WARP (优化：自动中文，自动确认) ───────
install_warp() {
    clear
    echo -e "\n${CYAN}正在自动安装 WARP (Socks5 模式 - 端口 $WARP_PORT)...${PLAIN}"
    
    # 模拟输入：2 (中文) -> [回车] (默认 Socks5 端口)
    printf "2\n\n" | bash <(curl -sL https://gitlab.com/fscarmen/warp/-/raw/main/menu.sh) c

    ensure_outbound
    systemctl restart xray >/dev/null 2>&1
    UI_MESSAGE="${GREEN}WARP 安装指令已发送。${PLAIN}"
    read -n 1 -s -r -p "按任意键返回..."
}

# ─── 优选 IP 与 自定义分流 ─────────────────────
optimize_warp() {
    echo -e "${CYAN}正在启动 WARP 优选程序...${PLAIN}"
    bash <(curl -sL https://gitlab.com/fscarmen/warp/-/raw/main/menu.sh) e
}

toggle_custom_domain() {
    echo -ne "${YELLOW}请输入要添加或删除的域名 (例如 netflix.com): ${PLAIN}"
    read -r input_domain
    [ -z "$input_domain" ] && return

    ensure_outbound
    
    # 检查域名是否已存在
    if jq -e --arg d "$input_domain" '.routing.rules[] | select(.outboundTag=="warp_proxy" and (.domain | contains([$d])))' "$CONFIG_FILE" >/dev/null 2>&1; then
        # 删除逻辑
        jq --arg d "$input_domain" 'del(.routing.rules[] | select(.outboundTag=="warp_proxy")).domain |= map(select(. != $d))' "$CONFIG_FILE" > "${CONFIG_FILE}.tmp"
        UI_MESSAGE="${YELLOW}已移除分流域名: $input_domain${PLAIN}"
    else
        # 添加逻辑 (插入到第一条规则)
        local new_rule="{\"type\": \"field\", \"domain\": [\"$input_domain\"], \"outboundTag\": \"warp_proxy\"}"
        jq --argjson rule "$new_rule" '.routing.rules = [$rule] + .routing.rules' "$CONFIG_FILE" > "${CONFIG_FILE}.tmp"
        UI_MESSAGE="${GREEN}已添加分流域名: $input_domain${PLAIN}"
    fi
    mv "${CONFIG_FILE}.tmp" "$CONFIG_FILE"
    systemctl restart xray >/dev/null 2>&1
}

# ─── 菜单界面 ────────────────────────────────
show_menu() {
    tput cup 0 0
    check_warp_socket && STATUS_SOCK="${GREEN}● 运行中${PLAIN}" || STATUS_SOCK="${RED}● 未运行${PLAIN}"
    check_xray_outbound && STATUS_XRAY="${GREEN}● 已连接${PLAIN}" || STATUS_XRAY="${RED}● 未连接${PLAIN}"

    echo -e "${CYAN}===================================================${PLAIN}\033[K"
    echo -e "${CYAN}           WARP 分流管理面板 (Xray Warp)          ${PLAIN}\033[K"
    echo -e "${CYAN}===================================================${PLAIN}\033[K"
    echo -e "  Warp 服务 : ${STATUS_SOCK}    Xray 接口: ${STATUS_XRAY}\033[K"
    echo -e "  Warp IP   : $(get_warp_ip)\033[K"
    echo -e "  默认出口  : $(get_main_ip)\033[K"
    echo -e "  分流域名  : $(get_split_domains)\033[K"
    echo -e "---------------------------------------------------\033[K"
    echo -e "  1. 安装/重装 WARP    ${GRAY}(自动配置 Socks5 端口 40000)${PLAIN}\033[K"
    echo -e "  2. 卸载 WARP         ${GRAY}(清理分流规则)${PLAIN}\033[K"
    echo -e "  3. 优选 WARP IP      ${GRAY}(解决流控/Netflix 无法播放)${PLAIN}\033[K"
    echo -e "  4. 添加/删除 自定义分流域名${PLAIN}\033[K"
    echo -e "---------------------------------------------------\033[K"
    echo -e "  0. 退出 (Exit)\033[K"
    echo -e "===================================================\033[K"
    if [ -n "$UI_MESSAGE" ]; then
        echo -e "${YELLOW}当前操作${PLAIN}: ${UI_MESSAGE}\033[K"
        UI_MESSAGE=""
    else
        echo -e "${YELLOW}当前操作${PLAIN}: ${GRAY}等待输入...${PLAIN}\033[K"
    fi
    echo -e "===================================================\033[K"
    tput ed
}

# ─── 主循环 ──────────────────────────────────
while true; do
    show_menu
    read -r -p "请输入选项 [0-4]: " choice
    case "$choice" in
        1) install_warp ;;
        2) bash <(curl -sL https://gitlab.com/fscarmen/warp/-/raw/main/menu.sh) u ;;
        3) optimize_warp ;;
        4) toggle_custom_domain ;;
        0) exit 0 ;;
        *) UI_MESSAGE="${RED}无效选项${PLAIN}" ;;
    esac
done
