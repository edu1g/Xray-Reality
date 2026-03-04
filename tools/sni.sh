#!/bin/bash
RED="\033[31m"; GREEN="\033[32m"; YELLOW="\033[33m"; BLUE="\033[36m"; GRAY="\033[90m"; PLAIN="\033[0m"

UI_MESSAGE=""

CONFIG_FILE="/usr/local/etc/xray/config.json"

clear
if [ "$EUID" -ne 0 ]; then echo -e "${RED}请使用 sudo 运行此脚本！${PLAIN}"; exit 1; fi
if ! command -v jq &> /dev/null; then echo -e "${RED}错误: 缺少 jq 依赖。${PLAIN}"; exit 1; fi

get_current_sni() {
    if [ -f "$CONFIG_FILE" ]; then
        CURRENT_SNI=$(jq -r '.inbounds[0].streamSettings.realitySettings.serverNames[0] // "获取失败"' "$CONFIG_FILE")
    else
        CURRENT_SNI="${RED}配置文件不存在${PLAIN}"
    fi
}

apply_sni() {
    local new_domain=$1

    cp "$CONFIG_FILE" "${CONFIG_FILE}.bak"

    jq --arg d "$new_domain" '
        (.inbounds[].streamSettings.realitySettings | select(. != null)) |= 
        (.serverNames = [$d] | .dest = ($d + ":443"))
    ' "$CONFIG_FILE" > "${CONFIG_FILE}.tmp" && mv "${CONFIG_FILE}.tmp" "$CONFIG_FILE"

    if systemctl restart xray; then
        UI_MESSAGE="${GREEN}修改成功！当前SNI: ${YELLOW}${new_domain}${GREEN}，请同步更新客户端配置。${PLAIN}"
    else
        mv "${CONFIG_FILE}.bak" "$CONFIG_FILE"
        systemctl restart xray
        UI_MESSAGE="${RED}Xray 重启失败，已自动还原旧配置。请检查新域名是否合法。${PLAIN}"
    fi
}

manual_change() {
    clear
    echo -e "${BLUE}===================================================${PLAIN}"
    echo -e "${BLUE}               手动修改 SNI 域名                   ${PLAIN}"
    echo -e "${BLUE}===================================================${PLAIN}"
    echo -e "  请输入您想要使用的SNI域名 (例: www.example.com)"
    echo -e "  输入 0 取消操作"
    echo -e "---------------------------------------------------"

    while true; do
        read -p "  域名: " input_domain

        if [ "$input_domain" == "0" ]; then
            UI_MESSAGE="${GRAY}操作已取消。${PLAIN}"
            return
        fi

        if [ -z "$input_domain" ]; then
            echo -e "\033[1A\033[K${RED}  输入不能为空，请重新输入${PLAIN}"
            continue
        fi

        if [[ "$input_domain" =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)+$ ]]; then
            apply_sni "$input_domain"
            return
        else
            echo -e "\033[1A\033[K${RED}  域名格式无效 (例: www.example.com)${PLAIN}"
        fi
    done
}

auto_select() {
    clear
    echo -e "${BLUE}===================================================${PLAIN}"
    echo -e "${BLUE}          自动优选 SNI (寻找最低延迟)              ${PLAIN}"
    echo -e "${BLUE}===================================================${PLAIN}"

    DOMAINS=("www.icloud.com" "www.apple.com" "itunes.apple.com" "learn.microsoft.com" "www.bing.com" "www.tesla.com" "www.nvidia.com" "www.intel.com" "www.amazon.com")

    TEMP_FILE=$(mktemp)
    echo -e "  正在 Ping 检测..."

    tput civis
    for domain in "${DOMAINS[@]}"; do
        printf "\r   Ping: %-25s" "${domain}..."
        time_cost=$(curl -w "%{time_connect}" -o /dev/null -s --connect-timeout 2 "https://$domain")
        if [ -n "$time_cost" ] && [ "$time_cost" != "0.000" ]; then
            ms=$(awk -v t="$time_cost" 'BEGIN { printf "%.0f", t * 1000 }')
            echo "$ms $domain" >> "$TEMP_FILE"
        else
            echo "9999 $domain" >> "$TEMP_FILE"
        fi
    done
    tput cnorm
    echo -ne "\r\033[K"

    echo -e "  延迟排序清单:"
    echo -e "---------------------------------------------------"
    SORTED_DOMAINS=()
    local idx=1

    while read ms domain; do
        if [ "$ms" == "9999" ]; then ms_show="超时"; else ms_show="${ms}ms"; fi
        SORTED_DOMAINS+=("$domain")
        if [ "$idx" -eq 1 ]; then
            printf "   ${GREEN}%d. %-25s %-6s [推荐]${PLAIN}\n" "$idx" "${domain}" "${ms_show}"
        else
            printf "   %d. %-25s %-6s\n" "$idx" "${domain}" "${ms_show}"
        fi
        ((idx++))
    done < <(sort -n "$TEMP_FILE")
    rm -f "$TEMP_FILE"

    echo -e "---------------------------------------------------"
    echo -e "   0. 取消 (Cancel)"
    echo ""

    local len=${#SORTED_DOMAINS[@]}
    local sel_error=""
    while true; do
        if [ -n "$sel_error" ]; then
            echo -ne "\r\033[K${RED}${sel_error}${PLAIN} 请输入序号选择 [0-${len}]: "
        else
            echo -ne "\r\033[K请输入序号选择 [0-${len}]: "
        fi
        read -r sel_idx

        if [ "$sel_idx" == "0" ]; then
            UI_MESSAGE="${GRAY}操作已取消。${PLAIN}"
            return
        elif [[ "$sel_idx" =~ ^[1-9]$ ]] && [ "$sel_idx" -le "$len" ]; then
            apply_sni "${SORTED_DOMAINS[$((sel_idx-1))]}"
            return
        else
            sel_error="输入无效！"
            echo -ne "\033[1A"
        fi
    done
}

while true; do
    get_current_sni
    tput cup 0 0

    echo -e "${BLUE}===================================================${PLAIN}\033[K"
    echo -e "${BLUE}          SNI 域名管理 (Reality Config)           ${PLAIN}\033[K"
    echo -e "${BLUE}===================================================${PLAIN}\033[K"
    echo -e "  当前SNI域名: ${YELLOW}${CURRENT_SNI}${PLAIN}\033[K"
    echo -e "---------------------------------------------------\033[K"
    echo -e "  1. 手动修改域名\033[K"
    echo -e "  2. 自动优选域名\033[K"
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

    error_msg=""
    while true; do
        if [ -n "$error_msg" ]; then
            echo -ne "\r\033[K${RED}${error_msg}${PLAIN} 请输入选项 [0-2]: "
        else
            echo -ne "\r\033[K请输入选项 [0-2]: "
        fi
        read -r choice
        case "$choice" in
            1|2|0)
                break
                ;;
            *)
                error_msg="输入无效！"
                echo -ne "\033[1A"
                ;;
        esac
    done

    case "$choice" in
        1) manual_change ;;
        2) auto_select ;;
        0) clear; exit 0 ;;
    esac
done
