#!/bin/bash

# ─────────────────────────────────────────────
#  Xray 网络优先级管理器
# ─────────────────────────────────────────────

RED="\033[31m"; GREEN="\033[32m"; YELLOW="\033[33m"; CYAN="\033[36m"; GRAY="\033[90m"; PLAIN="\033[0m"

UI_MESSAGE=""

CONFIG_FILE="/usr/local/etc/xray/config.json"
GAI_CONF="/etc/gai.conf"
SYSCTL_CONF="/etc/sysctl.conf"

# ─── 环境检查 ────────────────────────────────
if ! command -v jq &> /dev/null; then echo -e "${RED}错误: 缺少 jq 组件。${PLAIN}"; exit 1; fi

# ─── 网络连通性检测 ──────────────────────────
check_connectivity() {
    local target_ver=$1

    if [ "$target_ver" == "v4" ]; then
        curl -s4m 1 https://1.1.1.1         >/dev/null 2>&1 && return 0
        curl -s4m 1 https://8.8.8.8         >/dev/null 2>&1 && return 0
        curl -s4m 1 https://208.67.222.222  >/dev/null 2>&1 && return 0
    elif [ "$target_ver" == "v6" ]; then
        curl -s6m 1 https://2606:4700:4700::1111    >/dev/null 2>&1 && return 0
        curl -s6m 1 https://2001:4860:4860::8888    >/dev/null 2>&1 && return 0
    fi

    return 1
}

# ─── SSH 连接协议检测 ────────────────────────
check_ssh_connection() {
    local client_info="${SUDO_SSH_CLIENT:-$SSH_CLIENT}"

    if [ -z "$client_info" ]; then
        client_info=$(who -m 2>/dev/null | awk '{print $NF}' | tr -d '()')
    fi

    if [[ "$client_info" =~ : ]]; then
        echo "v6"
    else
        echo "v4"
    fi
}

# ─── 系统级 IPv6 开关 ────────────────────────
toggle_system_ipv6() {
    local state=$1
    if [ "$state" == "off" ]; then
        if [ "$(check_ssh_connection)" == "v6" ]; then
            echo -e "${RED}[危险拦截] 检测到您当前通过 IPv6 连接 SSH！${PLAIN}"
            echo -e "${YELLOW}禁止在此状态下关闭系统 IPv6，否则您将立即失联。${PLAIN}"
            read -n 1 -s -r -p "按任意键返回..."
            return 1
        fi
        sysctl -w net.ipv6.conf.all.disable_ipv6=1     >/dev/null
        sysctl -w net.ipv6.conf.default.disable_ipv6=1 >/dev/null
        sed -i '/net.ipv6.conf.all.disable_ipv6/d' "$SYSCTL_CONF"
        echo "net.ipv6.conf.all.disable_ipv6 = 1" >> "$SYSCTL_CONF"
    else
        sysctl -w net.ipv6.conf.all.disable_ipv6=0     >/dev/null
        sysctl -w net.ipv6.conf.default.disable_ipv6=0 >/dev/null
        sed -i '/net.ipv6.conf.all.disable_ipv6/d' "$SYSCTL_CONF"
    fi
    return 0
}

# ─── 系统地址优先级设置 ──────────────────────
set_system_prio() {
    [ ! -f "$GAI_CONF" ] && touch "$GAI_CONF"
    sed -i '/^precedence ::ffff:0:0\/96  100/d' "$GAI_CONF"

    if [ "$1" == "v4" ]; then
        echo "precedence ::ffff:0:0/96  100" >> "$GAI_CONF"
    fi
}

# ─── 策略应用 ────────────────────────────────
apply_strategy() {
    local sys_action=$1
    local xray_strategy=$2
    local desc=$3

    if [ "$sys_action" == "v4_only" ]; then
        if ! toggle_system_ipv6 "off"; then return; fi
        set_system_prio "v4"
    elif [ "$sys_action" == "v6_only" ]; then
        toggle_system_ipv6 "on"
        set_system_prio "v6"
    else
        toggle_system_ipv6 "on"
        if [ "$sys_action" == "v4_prio" ]; then set_system_prio "v4"; else set_system_prio "v6"; fi
    fi

    if [ "$xray_strategy" == "UseIPv4" ] && ! check_connectivity "v4"; then
        UI_MESSAGE="${RED}错误：本机无法连接 IPv4 网络，无法执行纯 IPv4 策略！${PLAIN}"
        toggle_system_ipv6 "on"
        return
    fi

    if [ -f "$CONFIG_FILE" ]; then
        tmp=$(mktemp)
        jq 'if .routing == null then .routing = {} else . end' "$CONFIG_FILE" > "$tmp" && mv "$tmp" "$CONFIG_FILE"
        jq --arg s "$xray_strategy" '.routing.domainStrategy = $s' "$CONFIG_FILE" > "$tmp" && mv "$tmp" "$CONFIG_FILE"
        rm -f "$tmp"
        systemctl restart xray >/dev/null 2>&1
        UI_MESSAGE="${GREEN}设置成功：${desc}${PLAIN}"
    else
        UI_MESSAGE="${RED}错误：找不到配置文件 $CONFIG_FILE${PLAIN}"
    fi
}

# ─── 当前状态读取 ────────────────────────────
get_current_status() {
    local xray_conf="Unknown"
    if [ -f "$CONFIG_FILE" ]; then
        xray_conf=$(jq -r '.routing.domainStrategy // "Unknown"' "$CONFIG_FILE")
    fi

    local sys_v6_val=$(sysctl -n net.ipv6.conf.all.disable_ipv6 2>/dev/null)
    [ -z "$sys_v6_val" ] && sys_v6_val=0

    local is_v4_prio=false
    if grep -q "^precedence ::ffff:0:0/96  100" "$GAI_CONF" 2>/dev/null; then
        is_v4_prio=true
    fi

    if [ "$xray_conf" == "UseIPv6" ]; then
        STATUS_TEXT="${YELLOW}仅 IPv6 (Xray 强制)${PLAIN}"
    elif [ "$xray_conf" == "UseIPv4" ]; then
        if [ "$sys_v6_val" -eq 1 ]; then
            STATUS_TEXT="${YELLOW}仅 IPv4 (系统级禁用 IPv6)${PLAIN}"
        else
            STATUS_TEXT="${YELLOW}仅 IPv4 (Xray 策略)${PLAIN} ${GRAY}- 系统 IPv6 仍开启${PLAIN}"
        fi
    elif [ "$sys_v6_val" -eq 1 ]; then
        STATUS_TEXT="${YELLOW}仅 IPv4 (系统级禁用 IPv6)${PLAIN}"
    else
        if [ "$is_v4_prio" = true ]; then
            STATUS_TEXT="${GREEN}双栈网络 (IPv4 优先)${PLAIN}"
        else
            STATUS_TEXT="${GREEN}双栈网络 (IPv6 优先 - 默认)${PLAIN}"
        fi
    fi
}

# ─── 菜单界面 ────────────────────────────────
show_menu() {
    tput cup 0 0
    echo -e "${CYAN}================================================${PLAIN}\033[K"
    echo -e "${CYAN}         网络优先级切换 (Network Priority)      ${PLAIN}\033[K"
    echo -e "${CYAN}================================================${PLAIN}\033[K"
    echo -e " 当前状态: ${STATUS_TEXT}\033[K"
    echo -e "------------------------------------------------\033[K"
    echo -e " [双栈模式]\033[K"
    echo -e " 1. IPv4 优先   ${GRAY}- IPv6 保持开启${PLAIN}\033[K"
    echo -e " 2. IPv6 优先   ${GRAY}- IPv4 保持开启${PLAIN}\033[K"
    echo -e "------------------------------------------------\033[K"
    echo -e " [强制模式]\033[K"
    echo -e " 3. 仅 IPv4     ${GRAY}- 系统禁用 IPv6 + Xray 强制 v4${PLAIN}\033[K"
    echo -e " 4. 仅 IPv6     ${GRAY}- 系统保留 IPv4 + Xray 强制 v6${PLAIN}\033[K"
    echo -e "------------------------------------------------\033[K"
    echo -e " 0. 退出\033[K"
    echo -e "================================================\033[K"
    if [ -n "$UI_MESSAGE" ]; then
        echo -e "${YELLOW}当前操作${PLAIN}: ${UI_MESSAGE}\033[K"
    else
        echo -e "${YELLOW}当前操作${PLAIN}: ${GRAY}等待输入...${PLAIN}\033[K"
    fi
    echo -e "================================================\033[K"
    tput ed
    UI_MESSAGE=""
}

# ─── 主循环 ──────────────────────────────────
clear
while true; do
    get_current_status
    show_menu

    error_msg=""
    while true; do
        if [ -n "$error_msg" ]; then
            echo -ne "\r\033[K${RED}${error_msg}${PLAIN} 请输入选项 [0-4]: "
        else
            echo -ne "\r\033[K请输入选项 [0-4]: "
        fi
        read -r choice
        case "$choice" in
            1|2|3|4|0) break ;;
            *) error_msg="输入无效！"; echo -ne "\033[1A" ;;
        esac
    done

    case "$choice" in
        1) apply_strategy "v4_prio" "IPIfNonMatch" "IPv4 优先 (双栈)" ;;
        2) apply_strategy "v6_prio" "IPIfNonMatch" "IPv6 优先 (双栈)" ;;
        3) apply_strategy "v4_only" "UseIPv4"      "纯 IPv4 模式" ;;
        4) apply_strategy "v6_only" "UseIPv6"      "纯 IPv6 模式" ;;
        0) clear; exit 0 ;;
    esac
done
