#!/bin/bash

# ─────────────────────────────────────────────
#  系统时区与时间管理器
# ─────────────────────────────────────────────

RED="\033[31m"; GREEN="\033[32m"; YELLOW="\033[33m"; CYAN="\033[36m"; GRAY="\033[90m"; PLAIN="\033[0m"

UI_MESSAGE=""

# ─── 时间与时区状态读取 ──────────────────────
get_time_status() {
    local tz=$(timedatectl show -p Timezone --value)
    local ntp_active=$(timedatectl show -p NTP --value)
    local is_synced=$(timedatectl show -p NTPSynchronized --value)

    echo -e "-------------------------------------------------\033[K"
    echo -e "  当前时间 : ${YELLOW}$(date "+%Y-%m-%d %H:%M:%S")${PLAIN}\033[K"
    echo -e "  当前时区 : ${GREEN}${tz}${PLAIN}\033[K"

    if [ "$ntp_active" == "yes" ]; then
        echo -e "  自动同步 : ${GREEN}已开启 (Active)${PLAIN}\033[K"
    else
        echo -e "  自动同步 : ${RED}已关闭 (Inactive)${PLAIN}\033[K"
    fi

    if [ "$is_synced" == "yes" ]; then
        echo -e "  同步状态 : ${GREEN}已校准 (Synced)${PLAIN}\033[K"
    else
        echo -e "  同步状态 : ${RED}未校准 / 偏差中${PLAIN}\033[K"
    fi
    echo -e "-------------------------------------------------\033[K"
}

# ─── 时区设置 ────────────────────────────────
set_timezone() {
    local target_tz=$1
    local name=$2
    if timedatectl set-timezone "$target_tz"; then
        UI_MESSAGE="${GREEN}时区已设置为 $name ($target_tz)，当前时间: $(date '+%H:%M:%S')${PLAIN}"
    else
        UI_MESSAGE="${RED}设置失败，请检查时区名称是否正确。${PLAIN}"
    fi
}

set_custom_timezone() {
    tput cup 20 0
    echo -ne "\033[K${YELLOW}请输入目标时区 (例如: America/New_York): ${PLAIN}"
    read -r custom_tz
    tput ed

    if [ -z "$custom_tz" ]; then
        UI_MESSAGE="${GRAY}未输入时区，操作已取消。${PLAIN}"
        return
    fi

    if [ -f "/usr/share/zoneinfo/$custom_tz" ]; then
        set_timezone "$custom_tz" "$custom_tz"
    else
        UI_MESSAGE="${RED}错误：系统找不到时区 '$custom_tz'。可运行 timedatectl list-timezones 查看支持列表。${PLAIN}"
    fi
}

# ─── NTP 时间同步 ────────────────────────────
sync_time() {
    timedatectl set-ntp true

    if systemctl is-active --quiet chrony; then
        systemctl restart chrony
    elif systemctl is-active --quiet systemd-timesyncd; then
        systemctl restart systemd-timesyncd
    else
        if command -v apt-get &>/dev/null; then
            apt-get update -qq && apt-get install -y chrony -qq
            systemctl enable --now chrony
        fi
    fi

    local timeout=15
    tput civis
    for ((i=timeout; i>0; i--)); do
        if [ "$(timedatectl show -p NTPSynchronized --value)" == "yes" ]; then
            local cost=$((timeout - i))
            tput cnorm
            tput cup "$PROGRESS_ROW" 0; echo -ne "\033[K"
            hwclock -w
            UI_MESSAGE="${GREEN}网络时间同步成功！(耗时 ${cost}s)${PLAIN}"
            return
        fi
        tput cup "$PROGRESS_ROW" 0
        echo -ne "\033[K  ${YELLOW}正在与 NTP 服务器握手... 剩余 ${i} 秒${PLAIN}"
        sleep 1
    done

    tput cnorm
    tput cup "$PROGRESS_ROW" 0; echo -ne "\033[K"
    hwclock -w
    UI_MESSAGE="${RED}同步响应超时，后台仍在尝试，请手动刷新。${PLAIN}"
}

# ─── 菜单界面 ────────────────────────────────
clear
show_menu() {
    tput cup 0 0
    echo -e "${CYAN}=================================================${PLAIN}\033[K"
    echo -e "${CYAN}         系统时区与时间管理 (Zone Manager)         ${PLAIN}\033[K"
    echo -e "${CYAN}=================================================${PLAIN}\033[K"

    get_time_status

    echo -e "  1. 设置为 ${GREEN}中国上海时间${PLAIN} (Asia/Shanghai)\033[K"
    echo -e "  2. 设置为 ${GREEN}UTC 标准时间${PLAIN} (UTC)\033[K"
    echo -e "  3. 设置为 ${YELLOW}自定义时区${PLAIN}\033[K"
    echo -e "-------------------------------------------------\033[K"
    echo -e "  4. ${CYAN}强制同步网络时间 (Sync NTP)${PLAIN}\033[K"
    echo -e "-------------------------------------------------\033[K"
    echo -e "  0. 退出 (Exit)          ${YELLOW}Enter/F. 刷新 (Refresh)${PLAIN}\033[K"
    echo -e "=================================================\033[K"
    if [ -n "$UI_MESSAGE" ]; then
        echo -e "${YELLOW}当前操作${PLAIN}: ${UI_MESSAGE}\033[K"
        UI_MESSAGE=""
    else
        echo -e "${YELLOW}当前操作${PLAIN}: ${GRAY}等待输入...${PLAIN}\033[K"
    fi
    echo -e "=================================================\033[K"
    tput ed
}

# ─── 主循环 ──────────────────────────────────
clear
while true; do
    show_menu

    error_msg=""
    while true; do
        if [ -n "$error_msg" ]; then
            echo -ne "\r\033[K${RED}${error_msg}${PLAIN} 请输入选项: "
        else
            echo -ne "\r\033[K请输入选项: "
        fi
        read -r choice
        case "$choice" in
            1|2|3|4|0|f|F|"") break ;;
            *) error_msg="输入无效！"; echo -ne "\033[1A" ;;
        esac
    done

    case "$choice" in
        1) set_timezone "Asia/Shanghai" "中国上海" ;;
        2) set_timezone "UTC" "UTC 标准时" ;;
        3) set_custom_timezone ;;
        4)
            PROGRESS_ROW=$(tput lines); PROGRESS_ROW=$((PROGRESS_ROW - 3))
            sync_time
            ;;
        0) clear; exit 0 ;;
        f|F|"") UI_MESSAGE="${YELLOW}时间已刷新。${PLAIN}"; continue ;;
    esac
done
