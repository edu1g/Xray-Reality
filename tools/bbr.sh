#!/bin/bash

# ─────────────────────────────────────────────
#  BBR 网络优化管理器 (已更新：支持 BBR + CAKE/FQ)
# ─────────────────────────────────────────────

RED="\033[31m"; GREEN="\033[32m"; YELLOW="\033[33m"
CYAN="\033[36m"; GRAY="\033[90m"; PLAIN="\033[0m"; BOLD="\033[1m"

UI_MESSAGE=""

SYSCTL_CONF="/etc/sysctl.d/99-xray-bbr.conf"
BACKUP_STATE="/etc/sysctl.d/.bbr_backup_state"

# ─── 内核兼容性检测 ───────────────────────────
KERNEL_VERSION=$(uname -r)
KERNEL_MAJOR=$(echo "$KERNEL_VERSION" | cut -d. -f1)
KERNEL_MINOR=$(echo "$KERNEL_VERSION" | cut -d. -f2)
BBR_SUPPORTED=0
# BBR 需要内核 4.9+
if [ "$KERNEL_MAJOR" -gt 4 ] || { [ "$KERNEL_MAJOR" -eq 4 ] && [ "$KERNEL_MINOR" -ge 9 ]; }; then
    BBR_SUPPORTED=1
fi

# ─── Root 检查 ────────────────────────────────
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}请使用 sudo 运行此脚本！${PLAIN}"
    exit 1
fi
clear

# ─── 备份 / 回滚 ──────────────────────────────
record_backup() {
    if [ ! -f "$BACKUP_STATE" ]; then
        local orig_cc orig_qd
        orig_cc=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null)
        orig_qd=$(sysctl -n net.core.default_qdisc 2>/dev/null)
        if [[ "$orig_cc" != "bbr" ]]; then
            echo "ORIG_CC=$orig_cc" > "$BACKUP_STATE"
            echo "ORIG_QD=$orig_qd" >> "$BACKUP_STATE"
        fi
    fi
}

do_rollback() {
    rm -f "$SYSCTL_CONF"
    local rest_cc="cubic" rest_qd="fq_codel"
    if [ -f "$BACKUP_STATE" ]; then
        source "$BACKUP_STATE"
        [ -n "$ORIG_CC" ] && rest_cc="$ORIG_CC"
        [ -n "$ORIG_QD" ] && rest_qd="$ORIG_QD"
    fi
    sysctl -w net.ipv4.tcp_congestion_control="$rest_cc" >/dev/null 2>&1
    sysctl -w net.core.default_qdisc="$rest_qd" >/dev/null 2>&1
    sysctl --system >/dev/null 2>&1
}

# ─── 状态读取 ────────────────────────────────
get_status() {
    local cc qd
    cc=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null)
    qd=$(sysctl -n net.core.default_qdisc 2>/dev/null)

    if [ -f "$SYSCTL_CONF" ]; then
        STATUS_MAIN="${GREEN}已启用 - BBR + ${qd^^}${PLAIN}"
    else
        if [[ "$cc" == "bbr" ]]; then
            STATUS_MAIN="${YELLOW}已启用 (系统默认 BBR + ${qd^^})${PLAIN}"
        else
            STATUS_MAIN="${GRAY}未启用 (当前: ${cc} + ${qd})${PLAIN}"
        fi
    fi

    if [ $BBR_SUPPORTED -eq 1 ]; then
        STATUS_KERNEL="${KERNEL_VERSION} — ${GREEN}支持 BBR${PLAIN}"
    else
        STATUS_KERNEL="${KERNEL_VERSION} — ${RED}内核过旧，不支持 BBR${PLAIN}"
    fi
}

# ─── 启用 BBR + CAKE (推荐) ──────────────────
enable_bbr_cake() {
    if [ $BBR_SUPPORTED -eq 0 ]; then echo -e "${RED}内核不支持 BBR${PLAIN}"; return; fi
    record_backup
    
    # 检测 CAKE 支持 (内核 4.19+)
    if ! modprobe sch_cake 2>/dev/null; then
        UI_MESSAGE="${RED}错误：当前内核不支持 CAKE 算法 (需 4.19+)。${PLAIN}"
        return
    fi

    cat > "$SYSCTL_CONF" <<CONF
net.core.default_qdisc = cake
net.ipv4.tcp_congestion_control = bbr
# 基础性能优化
fs.file-max = 1000000
net.ipv4.tcp_fastopen = 3
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_fin_timeout = 15
CONF
    sysctl -p "$SYSCTL_CONF" >/dev/null 2>&1
    UI_MESSAGE="${GREEN}BBR + CAKE 模式已成功启用！${PLAIN}"
}

# ─── 启用 BBR + FQ (兼容) ────────────────────
enable_bbr_fq() {
    if [ $BBR_SUPPORTED -eq 0 ]; then echo -e "${RED}内核不支持 BBR${PLAIN}"; return; fi
    record_backup
    modprobe tcp_bbr 2>/dev/null && modprobe sch_fq 2>/dev/null
    
    cat > "$SYSCTL_CONF" <<CONF
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
# 基础性能优化
fs.file-max = 1000000
net.ipv4.tcp_fastopen = 3
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_fin_timeout = 15
CONF
    sysctl -p "$SYSCTL_CONF" >/dev/null 2>&1
    UI_MESSAGE="${GREEN}BBR + FQ 模式已成功启用！${PLAIN}"
}

# ─── 菜单界面 ────────────────────────────────
show_menu_ui() {
    tput cup 0 0
    get_status
    echo -e "${CYAN}===================================================${PLAIN}\033[K"
    echo -e "${CYAN}          BBR 网络优化 (CAKE & FQ 模式)           ${PLAIN}\033[K"
    echo -e "${CYAN}===================================================${PLAIN}\033[K"
    echo -e "  当前状态 : ${STATUS_MAIN}\033[K"
    echo -e "  内核版本 : ${STATUS_KERNEL}\033[K"
    echo -e "---------------------------------------------------\033[K"
    echo -e "  1. ${GREEN}启用 BBR + CAKE${PLAIN}  (推荐 - 适合 4.19+ 内核)\033[K"
    echo -e "  2. ${GREEN}启用 BBR + FQ${PLAIN}    (通用 - 适合 4.9+ 内核)\033[K"
    echo -e "  3. ${YELLOW}关闭 BBR 优化${PLAIN}    (恢复系统默认)\033[K"
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
    show_menu_ui
    read -r -p "请输入选项 [0-3]: " choice
    case "$choice" in
        1) enable_bbr_cake ;;
        2) enable_bbr_fq ;;
        3) do_rollback; UI_MESSAGE="${YELLOW}已恢复系统默认网络配置。${PLAIN}" ;;
        0) clear; exit 0 ;;
        *) UI_MESSAGE="${RED}输入无效！${PLAIN}" ;;
    esac
done
