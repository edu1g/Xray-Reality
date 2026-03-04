#!/bin/bash

# ─────────────────────────────────────────────
#  Xray 流量嗅探管理器
# ─────────────────────────────────────────────

RED="\033[31m"; GREEN="\033[32m"; YELLOW="\033[33m"; CYAN="\033[36m"; GRAY="\033[90m"; PLAIN="\033[0m"

UI_MESSAGE=""

CONFIG_FILE="/usr/local/etc/xray/config.json"
LOG_FILE="/var/log/xray/access.log"

# ─── 环境检查 ────────────────────────────────
if ! command -v jq &> /dev/null; then echo -e "${RED}错误: 缺少 jq 组件。${PLAIN}"; exit 1; fi

# ─── 状态读取 ────────────────────────────────
get_sniff_status() {
    if [ ! -f "$CONFIG_FILE" ]; then echo "Error"; return; fi
    local status=$(jq -r '.inbounds[0].sniffing.enabled // false' "$CONFIG_FILE")
    if [ "$status" == "true" ]; then
        echo -e "${GREEN}已开启 (Enabled)${PLAIN}"
    else
        echo -e "${RED}已关闭 (Disabled)${PLAIN}"
    fi
}

get_log_status() {
    local access_path=$(jq -r '.log.access // ""' "$CONFIG_FILE")
    if [[ "$access_path" != "" ]]; then
        echo -e "${GREEN}已开启${PLAIN}"
    else
        echo -e "${RED}未配置${PLAIN}"
    fi
}

# ─── 流量嗅探开关 ────────────────────────────
toggle_sniffing() {
    local current=$(jq -r '.inbounds[0].sniffing.enabled // false' "$CONFIG_FILE")
    local target_state
    if [ "$current" == "true" ]; then target_state="false"; else target_state="true"; fi
    cp "$CONFIG_FILE" "${CONFIG_FILE}.bak"
    tmp=$(mktemp)

    if [ "$target_state" == "true" ]; then
        jq '
          .inbounds |= map(
            if .protocol == "vless" then
              .sniffing = {"enabled": true, "destOverride": ["http", "tls", "quic"], "routeOnly": true}
            else . end
          )
        ' "$CONFIG_FILE" > "$tmp"
    else
        jq '
          .inbounds |= map(
            if .protocol == "vless" then
              .sniffing.enabled = false
            else . end
          )
        ' "$CONFIG_FILE" > "$tmp"
    fi

    if [ -s "$tmp" ]; then
        mv "$tmp" "$CONFIG_FILE"
        chmod 644 "$CONFIG_FILE"
        systemctl restart xray >/dev/null 2>&1

        if systemctl is-active --quiet xray; then
            if [ "$target_state" == "true" ]; then
                UI_MESSAGE="${GREEN}流量嗅探已开启${PLAIN}"
            else
                UI_MESSAGE="${YELLOW}流量嗅探已关闭${PLAIN}"
            fi
            rm -f "${CONFIG_FILE}.bak"
        else
            mv "${CONFIG_FILE}.bak" "$CONFIG_FILE"
            chmod 644 "$CONFIG_FILE"
            systemctl restart xray >/dev/null 2>&1
            if systemctl is-active --quiet xray; then
                UI_MESSAGE="${YELLOW}重启失败，已自动回滚，服务已恢复${PLAIN}"
            else
                UI_MESSAGE="${RED}灾难性错误：回滚后无法启动，请查询日志${PLAIN}"
            fi
        fi
    else
        UI_MESSAGE="${RED}JSON 处理失败，未做任何修改${PLAIN}"
        rm -f "$tmp"
    fi
}

# ─── 访问日志开关 ────────────────────────────
toggle_logging() {
    local access_path=$(jq -r '.log.access // ""' "$CONFIG_FILE")
    local action
    if [[ "$access_path" != "" ]]; then action="off"; else action="on"; fi
    tmp=$(mktemp)

    if [ "$action" == "on" ]; then
        mkdir -p /var/log/xray
        touch "$LOG_FILE"
        chown nobody:nogroup "$LOG_FILE" 2>/dev/null || chown nobody:nobody "$LOG_FILE" 2>/dev/null
        chmod 644 "$LOG_FILE"
        jq --arg path "$LOG_FILE" '.log.access = $path | .log.loglevel = "info"' "$CONFIG_FILE" > "$tmp"
    else
        jq 'del(.log.access) | .log.loglevel = "warning"' "$CONFIG_FILE" > "$tmp"
        echo "" > "$LOG_FILE"
    fi

    if [ -s "$tmp" ]; then
        mv "$tmp" "$CONFIG_FILE"
        chmod 644 "$CONFIG_FILE"
        systemctl restart xray >/dev/null 2>&1
        if [ "$action" == "on" ]; then
            UI_MESSAGE="${GREEN}访问日志已开启${PLAIN}"
        else
            UI_MESSAGE="${YELLOW}访问日志已关闭${PLAIN}"
        fi
    else
        UI_MESSAGE="${RED}JSON 处理失败${PLAIN}"
        rm -f "$tmp"
    fi
}

# ─── 实时流量审计 ────────────────────────────
trap 'trap - INT; return' INT
watch_traffic() {
    local access_path=$(jq -r '.log.access // ""' "$CONFIG_FILE")
    if [[ "$access_path" == "" ]]; then
        echo -e "${YELLOW}提示：检测到未开启访问日志，正在自动开启...${PLAIN}"
        toggle_logging "on"
        sleep 1
    fi

    clear
    echo -e "${GREEN}=================================================${PLAIN}"
    echo -e "${GREEN}        实时监视 (Ctrl+C 返回主菜单)${PLAIN}"
    echo -e "${GREEN}=================================================${PLAIN}"
    echo -e "Listening: ${YELLOW}$LOG_FILE${PLAIN}"
    echo ""

    printf "${GRAY}%-15s %-22s %-25s %-63s %s${PLAIN}\n" "[Time]" "[Source IP]" "[Routing]" "[Destination]" "[User]"
    echo -e "${GRAY}---------------------------------------------------------------------------------------------------------------------------------------${PLAIN}"

    tail -f "$LOG_FILE" | awk '{
        if ($5 == "accepted") {
            printf "\033[36m%-15s\033[0m \033[33m%-22s\033[0m \033[35m%-25s\033[0m \033[32m%-63s\033[0m \033[37m%s\033[0m\n", substr($2,1,12), $4, $7$8$9, $6, $11
        }
    }'
    trap - INT
    clear
}

# ─── 菜单界面 ────────────────────────────────
show_menu() {
    tput cup 0 0
    echo -e "${CYAN}=================================================${PLAIN}\033[K"
    echo -e "${CYAN}          Xray 流量嗅探 (Sniffing)              ${PLAIN}\033[K"
    echo -e "${CYAN}=================================================${PLAIN}\033[K"
    echo -e " 流量嗅探: $(get_sniff_status)\033[K"
    echo -e " 日志记录: $(get_log_status)\033[K"
    echo -e "-------------------------------------------------\033[K"
    echo -e " 1. 开启 / 关闭 流量嗅探\033[K"
    echo -e " 2. 开启 / 关闭 访问日志\033[K"
    echo -e " 3. ${YELLOW}进入实时流量审计模式${PLAIN}\033[K"
    echo -e "-------------------------------------------------\033[K"
    echo -e " 0. 退出\033[K"
    echo -e "=================================================\033[K"
    if [ -n "$UI_MESSAGE" ]; then
        echo -e "${YELLOW}当前操作${PLAIN}: ${UI_MESSAGE}\033[K"
    else
        echo -e "${YELLOW}当前操作${PLAIN}: ${GRAY}等待输入...${PLAIN}\033[K"
    fi
    echo -e "=================================================\033[K"
    tput ed
    UI_MESSAGE=""
}

# ─── 主循环 ──────────────────────────────────
clear
while true; do
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
            [0-3]) break ;;
            *) error_msg="输入无效！"; echo -ne "\033[1A" ;;
        esac
    done

    case "$choice" in
        1) toggle_sniffing ;;
        2) toggle_logging ;;
        3) watch_traffic ;;
        0) clear; exit 0 ;;
    esac
done
