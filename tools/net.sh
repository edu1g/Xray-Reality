#!/bin/bash
RED="\033[31m"; GREEN="\033[32m"; YELLOW="\033[33m"; BLUE="\033[36m"; PLAIN="\033[0m"
GRAY="\033[90m"
UI_MESSAGE=""

CONFIG_FILE="/usr/local/etc/xray/config.json"
GAI_CONF="/etc/gai.conf"
SYSCTL_CONF="/etc/sysctl.conf"

# 检查依赖
if ! command -v jq &> /dev/null; then echo -e "${RED}错误: 缺少 jq 组件。${PLAIN}"; exit 1; fi

# 核心辅助函数
# 1. 连通性检测 
check_connectivity() {
    local target_ver=$1
    local ret_code=1

    if [ "$target_ver" == "v4" ]; then
        if curl -s4m 1 https://1.1.1.1 >/dev/null 2>&1; then
            return 0
        elif curl -s4m 1 https://8.8.8.8 >/dev/null 2>&1; then
            return 0
        elif curl -s4m 1 https://208.67.222.222 >/dev/null 2>&1; then
            return 0
        fi
        
    elif [ "$target_ver" == "v6" ]; then
        if curl -s6m 1 https://2606:4700:4700::1111 >/dev/null 2>&1; then
            return 0
        elif curl -s6m 1 https://2001:4860:4860::8888 >/dev/null 2>&1; then
            return 0
        fi
    fi

    return 1
}

# 2. SSH 连接方式检测
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

# 3. 系统级 IPv6 开关
toggle_system_ipv6() {
    local state=$1
    if [ "$state" == "off" ]; then
        # 安全拦截
        if [ "$(check_ssh_connection)" == "v6" ]; then
            echo -e "${RED}[危险拦截] 检测到您当前通过 IPv6 连接 SSH！${PLAIN}"
            echo -e "${YELLOW}禁止在此状态下关闭系统 IPv6，否则您将立即失联。${PLAIN}"
            read -n 1 -s -r -p "按任意键返回..."
            return 1
        fi
        
        sysctl -w net.ipv6.conf.all.disable_ipv6=1 >/dev/null
        sysctl -w net.ipv6.conf.default.disable_ipv6=1 >/dev/null
        # 持久化
        sed -i '/net.ipv6.conf.all.disable_ipv6/d' "$SYSCTL_CONF"
        echo "net.ipv6.conf.all.disable_ipv6 = 1" >> "$SYSCTL_CONF"
    else
        sysctl -w net.ipv6.conf.all.disable_ipv6=0 >/dev/null
        sysctl -w net.ipv6.conf.default.disable_ipv6=0 >/dev/null
        sed -i '/net.ipv6.conf.all.disable_ipv6/d' "$SYSCTL_CONF"
    fi
    return 0
}

# 4. 设置系统优先级 (gai.conf)
set_system_prio() {
    [ ! -f "$GAI_CONF" ] && touch "$GAI_CONF"
    sed -i '/^precedence ::ffff:0:0\/96  100/d' "$GAI_CONF"
    
    # 如果是 v4 优先，写入规则
    if [ "$1" == "v4" ]; then 
        echo "precedence ::ffff:0:0/96  100" >> "$GAI_CONF"
    fi
    # 注意：v6 优先是 Linux 默认行为，所以只要删掉上面的规则就是 v6 优先
}

# 5. 应用策略总控
apply_strategy() {
    local sys_action=$1
    local xray_strategy=$2
    local desc=$3

    # --- 执行系统级变更 ---
    if [ "$sys_action" == "v4_only" ]; then
        if ! toggle_system_ipv6 "off"; then return; fi
        set_system_prio "v4"
    elif [ "$sys_action" == "v6_only" ]; then
        toggle_system_ipv6 "on"
        set_system_prio "v6"
    else
        # 双栈模式
        toggle_system_ipv6 "on"
        if [ "$sys_action" == "v4_prio" ]; then set_system_prio "v4"; else set_system_prio "v6"; fi
    fi

    # --- 连通性复查 ---
    if [ "$xray_strategy" == "UseIPv4" ] && ! check_connectivity "v4"; then
        UI_MESSAGE="${RED}错误：本机无法连接 IPv4 网络，无法执行纯 IPv4 策略！${PLAIN}"
        toggle_system_ipv6 "on"
        return
    fi

    # --- 修改 Xray 配置 ---
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

# 状态显示逻辑
get_current_status() {
    # 1. 获取 Xray 策略
    local xray_conf="Unknown"
    if [ -f "$CONFIG_FILE" ]; then
        xray_conf=$(jq -r '.routing.domainStrategy // "Unknown"' "$CONFIG_FILE")
    fi
    
    # 2. 获取系统 IPv6 开关 (0=开启, 1=禁用)
    local sys_v6_val=$(sysctl -n net.ipv6.conf.all.disable_ipv6 2>/dev/null)
    [ -z "$sys_v6_val" ] && sys_v6_val=0

    # 3. 获取优先级
    local is_v4_prio=false
    if grep -q "^precedence ::ffff:0:0/96  100" "$GAI_CONF" 2>/dev/null; then
        is_v4_prio=true
    fi

    # 4. 判定逻辑
    
    # 情况 A: Xray 强制 IPv6
    if [ "$xray_conf" == "UseIPv6" ]; then
        STATUS_TEXT="${YELLOW}仅 IPv6 (Xray 强制)${PLAIN}"
        
    # 情况 B: Xray 强制 IPv4
    elif [ "$xray_conf" == "UseIPv4" ]; then
        if [ "$sys_v6_val" -eq 1 ]; then
            # Xray 限 v4 且 系统也禁了 v4 -> 真正的纯净模式
            STATUS_TEXT="${YELLOW}仅 IPv4 (系统级禁用 IPv6)${PLAIN}"
        else
            # Xray 限 v4 但 系统 v6 还开着 -> 混合模式
            STATUS_TEXT="${YELLOW}仅 IPv4 (Xray 策略)${PLAIN} ${GRAY}- 系统 IPv6 仍开启${PLAIN}"
        fi
        
    # 情况 C: 系统禁用 IPv6
    elif [ "$sys_v6_val" -eq 1 ]; then
        STATUS_TEXT="${YELLOW}仅 IPv4 (系统级禁用 IPv6)${PLAIN}"
        
    # 情况 D: 双栈模式 (Xray 没限制，系统也没限制)
    else
        if [ "$is_v4_prio" = true ]; then
            STATUS_TEXT="${GREEN}双栈网络 (IPv4 优先)${PLAIN}"
        else
            STATUS_TEXT="${GREEN}双栈网络 (IPv6 优先 - 默认)${PLAIN}"
        fi
    fi
}

# 主菜单循环
clear
while true; do
    get_current_status
    
    tput cup 0 0
    
    echo -e "${BLUE}================================================${PLAIN}\033[K"
    echo -e "${BLUE}           网络优先级切换 (Network Priority)    ${PLAIN}\033[K"
    echo -e "${BLUE}================================================${PLAIN}\033[K"
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
    error_msg=""
    while true; do
        if [ -n "$error_msg" ]; then
            echo -ne "\r\033[K${RED}${error_msg}${PLAIN} 请输入选项 [0-4]: "
        else
            echo -ne "\r\033[K请输入选项 [0-4]: "
        fi
        read -r choice
        case "$choice" in
            1|2|3|4|0) 
                break
                ;;
            *) 
                error_msg="输入无效！"
                echo -ne "\033[1A"
                ;;
        esac
    done

    case "$choice" in
        1) apply_strategy "v4_prio" "IPIfNonMatch" "IPv4 优先 (双栈)" ;;
        2) apply_strategy "v6_prio" "IPIfNonMatch" "IPv6 优先 (双栈)" ;;
        3) apply_strategy "v4_only" "UseIPv4"      "纯 IPv4 模式" ;;
        4) apply_strategy "v6_only" "UseIPv6"      "纯 IPv6 模式" ;;
        0) clear; exit 0 ;;
        *) ;;
    esac
done
