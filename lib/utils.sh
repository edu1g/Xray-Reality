#!/bin/bash

# ─────────────────────────────────────────────
#  utils.sh — 公共工具函数库 (全自动无人值守版)
# ─────────────────────────────────────────────

# ─── 颜色与标签定义 ───
RED="\033[31m"; GREEN="\033[32m"; YELLOW="\033[33m"; CYAN="\033[36m"; GRAY="\033[90m"; PLAIN="\033[0m"
INFO="${CYAN}[INFO]${PLAIN}"; WARN="${YELLOW}[WARN]${PLAIN}"; ERR="${RED}[ERR] ${PLAIN}"; OK="${GREEN}[OK]  ${PLAIN}"

_LOCK_FILE="/tmp/xray_install.lock"

# ─── 基础工具函数 ───
_cleanup() {
    rm -f "$_LOCK_FILE"
}

print_banner() {
    clear
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${PLAIN}"
    echo -e "                Xray Reality 一键安装脚本                "
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${PLAIN}"
}

lock_acquire() {
    if [ -f "$_LOCK_FILE" ]; then
        local pid=$(cat "$_LOCK_FILE")
        if kill -0 "$pid" 2>/dev/null; then
            echo -e "${ERR} 检测到脚本正在运行 (PID: $pid)"
            return 1
        else
            rm -f "$_LOCK_FILE"
        fi
    fi
    echo $$ > "$_LOCK_FILE"
    trap '_cleanup; exit' INT TERM EXIT
    return 0
}

# ─── 全自动确认函数 (关键修改) ───
confirm_installation() {
    echo -e "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${PLAIN}"
    echo -e "${RED}                    安装说明 (What's Included)                ${PLAIN}"
    echo -e "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${PLAIN}"
    echo -e " ${CYAN}模式${PLAIN}: 全自动无人值守安装"
    echo -e " ${CYAN}系统${PLAIN}: Debian / Ubuntu"
    echo -e " ${CYAN}项目${PLAIN}: https://github.com/edu1g/Xray-Reality"
    echo -e "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${PLAIN}"
    echo -e ""
    echo -ne "${YELLOW} 检测到自动模式，安装程序将在 ${RED}3${YELLOW} 秒后自动启动...${PLAIN}"
    sleep 1
    echo -ne "\r\033[K${YELLOW} 检测到自动模式，安装程序将在 ${RED}2${YELLOW} 秒后自动启动...${PLAIN}"
    sleep 1
    echo -ne "\r\033[K${YELLOW} 检测到自动模式，安装程序将在 ${RED}1${YELLOW} 秒后自动启动...${PLAIN}"
    sleep 1
    echo -e "\r\033[K${OK} 正在启动安装程序...\n"
}

execute_task() {
    local cmd="$1"
    local desc="$2"
    echo -ne "${INFO} 正在处理 : ${desc}..."
    if eval "$cmd" >/dev/null 2>&1; then
        echo -e "\r\033[K${OK} ${desc}"
        return 0
    else
        echo -e "\r\033[K${ERR} ${desc} [FAILED]"
        return 1
    fi
}
