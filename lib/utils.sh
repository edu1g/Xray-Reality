#!/bin/bash

# ─────────────────────────────────────────────
#  utils.sh — 公共工具函数库
# ─────────────────────────────────────────────

# ─── 颜色与标签定义 ──────────────────────────
RED="\033[31m"; GREEN="\033[32m"; YELLOW="\033[33m"; CYAN="\033[36m"; GRAY="\033[90m"; PLAIN="\033[0m"

INFO="${CYAN}[INFO]${PLAIN}"
WARN="${YELLOW}[WARN]${PLAIN}"
ERR="${RED}[ERR] ${PLAIN}"
OK="${GREEN}[OK]  ${PLAIN}"

UI_SPINNER_FRAMES=("|" "/" "-" "\\")

# ─── 进程锁文件 ──────────────────────────────
_LOCK_FILE="/tmp/xray_install.lock"

# ─── 任务执行封装 ────────────────────────────
_cleanup() {
    rm -f "$_LOCK_FILE"
    if [ -f /etc/resolv.conf.bak ]; then
        cp /etc/resolv.conf.bak /etc/resolv.conf 2>/dev/null
    fi
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

# ─── 安装前确认 ──────────────────────────────
confirm_installation() {
    echo -e "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${PLAIN}"
    echo -e "${RED}                    安装说明 (What's Included)                ${PLAIN}"
    echo -e "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${PLAIN}"
    echo -e " ${CYAN}预计耗时${PLAIN}: 1 ~ 5 分钟（取决于网络环境）"
    echo -e " ${CYAN}支持系统${PLAIN}: Debian / Ubuntu (amd64 / arm64)"
    echo -e " ${CYAN}项目地址${PLAIN}: https://github.com/ISFZY/Xray-Reality"
    echo -e " ${CYAN}项目地址${PLAIN}: ${GREEN}https://github.com/uxswl/Xray-Reality ${YELLOW}(备用)${PLAIN}"
    echo -e "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${PLAIN}"
    echo -e ""

    local error_msg=""
    while true; do
        if [ -n "$error_msg" ]; then
            echo -ne "\r\033[K${RED}${error_msg}${PLAIN} 确认继续安装? [y/n]: "
        else
            echo -ne "\r\033[K确认继续安装? [y/n]: "
        fi
        read -r key
        case "$key" in
            y|Y)
                echo -e "\n${OK} 用户确认，开始执行安装程序。${PLAIN}"
                break
                ;;
            n|N)
                echo -e "\n${WARN} 用户取消安装。${PLAIN}"
                exit 1
                ;;
            *)
                error_msg="错误：必须输入 y 或 n！"
                echo -ne "\033[1A"
                ;;
        esac
    done
}
