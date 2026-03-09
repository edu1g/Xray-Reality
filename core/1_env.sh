#!/bin/bash

# ─────────────────────────────────────────────
#  1_env.sh — 环境准备与检测 (全自动无人值守版)
# ─────────────────────────────────────────────

# ─── 系统与架构检测 ──────────────────────────
check_sys_arch() {
    if [ ! -f /etc/debian_version ]; then
        echo -e "${ERR} 本脚本仅支持 Debian/Ubuntu 系统！"
        echo -e "${YELLOW}请更换系统后重试。${PLAIN}"
        exit 1
    fi

    ARCH=$(uname -m)
    case $ARCH in
        x86_64)  ARCH="amd64" ;;
        aarch64) ARCH="arm64" ;;
        *)
            echo -e "${ERR} 不支持的 CPU 架构: ${ARCH}"
            exit 1
            ;;
    esac

    echo -e "${OK} 系统检查 (OS & Arch): Debian/Ubuntu (${ARCH})"
}

# ─── 环境预检 & 包管理锁等待 (已修改为自动处理) ─────────────────
pre_flight_check() {
    is_package_manager_running() {
        pgrep -x apt >/dev/null || pgrep -x apt-get >/dev/null || \
        pgrep -x dpkg >/dev/null || pgrep -f "unattended-upgr" >/dev/null
    }

    local desc="环境预检 (Pre-flight Check)"
    local max_ticks=300 # 5分钟
    local ticks=0

    if is_package_manager_running; then
        echo -e "${INFO} 检测到系统更新进程正在运行，正在等待释放锁..."
        tput civis
        while is_package_manager_running; do
            # 如果等待超过 5 分钟，自动强制清理，不再进行 y/n 询问
            if [ $ticks -ge $max_ticks ]; then
                tput cnorm
                echo -e "\n${WARN} 等待超时！检测到全自动模式，正在强制清理占用进程..."
                
                # 自动强制终止占用进程并清理锁文件
                killall apt apt-get dpkg 2>/dev/null
                rm -f /var/lib/apt/lists/lock /var/cache/apt/archives/lock /var/lib/dpkg/lock*
                echo -e "${OK} 进程锁已强制释放。"
                break
            fi

            local frame=${UI_SPINNER_FRAMES[$((ticks % 4))]}
            printf "\r ${CYAN}[ %s ]${PLAIN} 系统繁忙，等待锁释放中... (${ticks}s)" "$frame"
            sleep 1
            ((ticks++))
        done
        tput cnorm
        echo -ne "\r\033[K"
    fi

    # ─── dpkg 数据库完整性校验 ───────────────
    if ! dpkg --audit >/dev/null 2>&1; then
        echo -e "${INFO} 检测到 dpkg 状态异常，正在尝试自动修复..."
        dpkg --configure -a >/dev/null 2>&1
    fi

    # ─── 基础网络工具安装 ────────────────────
    if ! command -v curl >/dev/null 2>&1 || ! dpkg -s ca-certificates >/dev/null 2>&1; then
        echo -e "${INFO} 正在安装基础网络工具 (curl, ca-certificates)..."
        apt-get update -qq >/dev/null 2>&1
        apt-get install -y -qq curl wget ca-certificates >/dev/null 2>&1
    fi

    echo -e "${OK} ${desc}"
}

# ─── 网络栈检测 ────────
check_net_stack() {
    HAS_V4=false; HAS_V6=false; CURL_OPT=""

    if curl -
