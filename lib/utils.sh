#!/bin/bash

# ─────────────────────────────────────────────
#  utils.sh — 公共工具函数库 (全自动安装版)
# ─────────────────────────────────────────────

# ─── 颜色与标签定义 ──────────────────────────
RED="\033[31m"; GREEN="\033[32m"; YELLOW="\033[33m"; CYAN="\033[36m"; GRAY="\033[90m"; PLAIN="\033[0m"

INFO="${CYAN}[INFO]${PLAIN}"
WARN="${YELLOW}[WARN]${PLAIN}"
ERR="${RED}[ERR] ${PLAIN}"
OK="${GREEN}[OK]  ${PLAIN}"

# ─── 进程锁文件 ──────────────────────────────
_LOCK_FILE="/tmp/xray_install.lock"

# ─── 任务执行封装 ────────────────────────────
_cleanup() {
    rm -f "$_LOCK_FILE"
}

log_info() { echo -e "${INFO} $*"; }
log_warn() { echo -e "${WARN} $*"; }
log_err()  { echo -e "${ERR} $*" >&2; }

execute_task() {
    local cmd="$1"
    local desc="$2"
    echo -ne "${INFO} ${YELLOW}正在处理 : ${desc}...${PLAIN}"
    local err_log
    err_log=$(mktemp)

    if eval "$cmd" >/dev/null 2>"$err_log"; then
        rm -f "$err_log"
        echo -e "\r\033[K${OK} ${desc}"
        return 0
    else
        echo -e "\r\033[K${ERR} ${desc} [FAILED]"
        echo -e "${RED}=== 错误详情 ===${PLAIN}"
        cat "$err_log"
        echo -e "${RED}================${PLAIN}"
        rm -f "$err_log"
        return 1
    fi
}

# ─── 修复：新增 Banner 函数 ──────────────────
print_banner() {
    clear
    echo -e "${CYAN}"
    echo " ██▀███  ▓█████  ▄▄▄       ██▓     ██▓▄▄▄█████▓ ▓██   ██▓"
    echo "▓██ ▒ ██▒▓█   ▀ ▒████▄    ▓██▒    ▓██▒▓  ██▒ ▓▒  ▒██  ██▒"
    echo "▓██ ░▄█ ▒▒███   ▒██  ▀█▄  ▒██░    ▒██▒▒ ▓██░ ▒░   ▒██ ██░"
    echo "▒██▀▀█▄  ▒▓█  ▄ ░██▄▄▄▄██ ▒██░    ░██░░ ▓██▓ ░    ░ ▐██▓░"
    echo "░██▓ ▒██▒░▒████▒ ▓█   ▓██▒░██████▒░██░  ▒██▒ ░    ░ ██▒▒ "
    echo "░ ▒▓ ░▒▓░░░ ▒░ ░ ▒▒   ▓▒█░░ ▒░▓  ░░▓    ▒ ░░      ██▒░ "
    echo "  ░▒ ░ ▒░ ░ ░  ░  ▒   ▒▒ ░░ ░ ▒  ░ ▒ ░    ░       ▓██ ░  "
    echo "  ░░   ░    ░     ░   ▒     ░ ░    ▒ ░  ░         ▒ ▒    "
    echo "   ░        ░  ░      ░  ░    ░  ░ ░              ░ ░    "
    echo -e "${PLAIN}"
}

# ─── 进程锁获取 ──────────────────────────────
lock_acquire() {
    if [ -f "$_LOCK_FILE" ]; then
        local pid
        pid=$(cat "$_LOCK_FILE")
        if kill -0 "$pid" 2>/dev/null; then
            echo -e "${ERR} 检测到脚本正在运行 (PID: $pid)，请勿重复执行！"
            return 1
        else
            rm -f "$_LOCK_FILE"
        fi
    fi
    echo $$ > "$_LOCK_FILE"
    trap '_cleanup; exit' INT TERM EXIT
    return 0
}

# ─── 安装前确认 (已改为自动确认) ───────────────
confirm_installation() {
    echo -e "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${PLAIN}"
    echo -e "${RED}                    安装说明 (What's Included)                ${PLAIN}"
    echo -e "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${PLAIN}"
    echo -e " ${CYAN}预计耗时${PLAIN}: 1 ~ 5 分钟（全自动安装模式）"
    echo -e " ${CYAN}支持系统${PLAIN}: Debian / Ubuntu (amd64 / arm64)"
    echo -e " ${CYAN}项目地址${PLAIN}: ${GREEN}https
