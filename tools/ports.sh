#!/bin/bash

# ─────────────────────────────────────────────
#  Xray 端口管理器
# ─────────────────────────────────────────────

RED="\033[31m"; GREEN="\033[32m"; YELLOW="\033[33m"; CYAN="\033[36m"; GRAY="\033[90m"; PLAIN="\033[0m"

UI_MESSAGE=""

CONFIG_FILE="/usr/local/etc/xray/config.json"
SSH_CONFIG="/etc/ssh/sshd_config"

# ─── 环境检查 ────────────────────────────────
if ! command -v jq &> /dev/null; then
    echo -e "${RED}错误: 缺少 jq 依赖。请运行 apt-get install jq 或 yum install jq${PLAIN}"
    exit 1
fi

# ─── 端口运行状态检测 ────────────────────────
check_status() {
    local port=$1
    if ss -tulpn | grep -q ":${port} "; then
        echo -e "${GREEN}运行中${PLAIN}"
    else
        echo -e "${RED}未运行${PLAIN}"
    fi
}

# ─── 防火墙放行端口 ──────────────────────────
open_port() {
    local port=$1
    iptables -I INPUT -p tcp --dport $port -j ACCEPT
    iptables -I INPUT -p udp --dport $port -j ACCEPT
    if [ -f /proc/net/if_inet6 ]; then
        ip6tables -I INPUT -p tcp --dport $port -j ACCEPT 2>/dev/null
        ip6tables -I INPUT -p udp --dport $port -j ACCEPT 2>/dev/null
    fi
    netfilter-persistent save 2>/dev/null || service iptables save 2>/dev/null
}

# ─── 当前端口读取 ────────────────────────────
get_ports() {
    CURRENT_SSH=$(grep "^Port" "$SSH_CONFIG" | head -n 1 | awk '{print $2}')
    [ -z "$CURRENT_SSH" ] && CURRENT_SSH=22

    if [ -f "$CONFIG_FILE" ]; then
        CURRENT_VISION=$(jq -r '.inbounds[] | select(.tag=="vision_node") | .port' "$CONFIG_FILE")
        CURRENT_XHTTP=$(jq -r '.inbounds[] | select(.tag=="xhttp_node") | .port' "$CONFIG_FILE")
    else
        CURRENT_VISION="N/A"; CURRENT_XHTTP="N/A"
    fi
}

# ─── 端口输入与校验 ──────────────────────────
input_and_validate() {
    local service_name="$1"
    local current_port="$2"
    local input_port
    local error_msg=""

    while true; do
        if [ -n "$error_msg" ]; then
            echo -ne "\r\033[K${RED}${error_msg}${PLAIN} 请输入新的 $service_name 端口 (直接回车取消) [当前: $current_port]: "
        else
            echo -ne "\r\033[K请输入新的 $service_name 端口 (直接回车取消) [当前: $current_port]: "
        fi
        read -r input_port

        if [ -z "$input_port" ]; then
            return 1
        fi

        if [[ ! "$input_port" =~ ^[0-9]+$ ]]; then
            error_msg="错误：'$input_port' 不是数字！"
            echo -ne "\033[1A"
            continue
        fi

        if [ "$input_port" -lt 1 ] || [ "$input_port" -gt 65535 ]; then
            error_msg="错误：端口超出范围 (1-65535)！"
            echo -ne "\033[1A"
            continue
        fi

        TEMP_PORT="$input_port"
        return 0
    done
}

# ─── 修改 SSH 端口 ───────────────────────────
change_ssh() {
    clear
    echo -e "${RED}################################################################${PLAIN}"
    echo -e "${RED}#                    高风险操作警告 (WARNING)                  #${PLAIN}"
    echo -e "${RED}################################################################${PLAIN}"
    echo -e "${RED}#${PLAIN}  1. 请确保云服务商后台【安全组】已放行新端口。               ${RED}#${PLAIN}"
    echo -e "${RED}#${PLAIN}  2. 修改后【不要关闭窗口】，新开窗口测试连接。               ${RED}#${PLAIN}"
    echo -e "${RED}################################################################${PLAIN}"
    echo ""

    local confirm_error=""
    while true; do
        if [ -n "$confirm_error" ]; then
            echo -ne "\r\033[K${RED}${confirm_error}${PLAIN} 我已知晓风险，确认继续修改？ (y/n): "
        else
            echo -ne "\r\033[K我已知晓风险，确认继续修改？ (y/n): "
        fi
        read -r confirm
        case "$confirm" in
            [yY]) break ;;
            [nN]) UI_MESSAGE="${YELLOW}SSH 端口修改已取消。${PLAIN}"; return ;;
            *) confirm_error="错误：必须输入 y 或 n！"; echo -ne "\033[1A" ;;
        esac
    done

    echo ""
    if ! input_and_validate "SSH" "$CURRENT_SSH"; then
        UI_MESSAGE="${GRAY}SSH 端口修改已取消。${PLAIN}"
        return
    fi
    new_port=$TEMP_PORT

    echo -e "${CYAN}正在修改 SSH 端口为 $new_port ...${PLAIN}"
    sed -i "s/^Port.*/Port $new_port/" "$SSH_CONFIG"
    if ! grep -q "^Port" "$SSH_CONFIG"; then echo "Port $new_port" >> "$SSH_CONFIG"; fi

    open_port "$new_port"

    echo -e "${CYAN}正在重启 SSH 服务...${PLAIN}"
    systemctl restart ssh || systemctl restart sshd
    echo -e "${GREEN}修改成功！请务必新开窗口测试端口 $new_port 。${PLAIN}"
    UI_MESSAGE="${GREEN}SSH 端口已修改为 ${YELLOW}${new_port}${GREEN}，请新开窗口验证连接。${PLAIN}"
    read -n 1 -s -r -p "按任意键返回主菜单..."
    clear; printf '\033[3J'
}

# ─── 修改 Vision 端口 ────────────────────────
change_vision() {
    clear
    echo ""
    if ! input_and_validate "Vision" "$CURRENT_VISION"; then
        UI_MESSAGE="${GRAY}Vision 端口修改已取消。${PLAIN}"
        return
    fi
    new_port=$TEMP_PORT

    jq --argjson port $new_port '(.inbounds[] | select(.tag=="vision_node").port) |= $port' "$CONFIG_FILE" > "${CONFIG_FILE}.tmp" && mv "${CONFIG_FILE}.tmp" "$CONFIG_FILE"
    open_port "$new_port"
    systemctl restart xray
    UI_MESSAGE="${GREEN}Vision 端口已修改为 ${YELLOW}${new_port}${GREEN}，Xray 已重启。${PLAIN}"
    clear; printf '\033[3J'
}

# ─── 修改 XHTTP 端口 ─────────────────────────
change_xhttp() {
    clear
    echo ""
    if ! input_and_validate "XHTTP" "$CURRENT_XHTTP"; then
        UI_MESSAGE="${GRAY}XHTTP 端口修改已取消。${PLAIN}"
        return
    fi
    new_port=$TEMP_PORT

    jq --argjson port $new_port '(.inbounds[] | select(.tag=="xhttp_node").port) |= $port' "$CONFIG_FILE" > "${CONFIG_FILE}.tmp" && mv "${CONFIG_FILE}.tmp" "$CONFIG_FILE"
    open_port "$new_port"
    systemctl restart xray
    UI_MESSAGE="${GREEN}XHTTP 端口已修改为 ${YELLOW}${new_port}${GREEN}，Xray 已重启。${PLAIN}"
    clear; printf '\033[3J'
}

# ─── 菜单界面 ────────────────────────────────
clear
show_menu() {
    tput cup 0 0
    echo -e "${CYAN}===================================================${PLAIN}\033[K"
    echo -e "${CYAN}          端口管理面板 (Port Manager)             ${PLAIN}\033[K"
    echo -e "${CYAN}===================================================${PLAIN}\033[K"
    echo -e "  服务            端口(1-65535) 状态\033[K"
    echo -e "---------------------------------------------------\033[K"
    printf "  1. 修改 SSH     ${YELLOW}%-12s${PLAIN}  %s\033[K\n" "$CURRENT_SSH"    "$(check_status $CURRENT_SSH)"
    printf "  2. 修改 Vision  ${YELLOW}%-12s${PLAIN}  %s\033[K\n" "$CURRENT_VISION" "$(check_status $CURRENT_VISION)"
    printf "  3. 修改 XHTTP   ${YELLOW}%-12s${PLAIN}  %s\033[K\n" "$CURRENT_XHTTP"  "$(check_status $CURRENT_XHTTP)"
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
    get_ports
    show_menu

    error_msg=""
    while true; do
        if [ -n "$error_msg" ]; then
            echo -ne "\r\033[K${RED}${error_msg}${PLAIN} 请输入选项 [0-3]: "
        else
            echo -ne "\r\033[K请输入选项 [0-3]: "
        fi
        read -r choice
        case "$choice" in
            1|2|3|0) break ;;
            *) error_msg="输入无效！"; echo -ne "\033[1A" ;;
        esac
    done

    case "$choice" in
        1) change_ssh ;;
        2) change_vision ;;
        3) change_xhttp ;;
        0) clear; exit 0 ;;
    esac
done
