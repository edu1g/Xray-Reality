#!/bin/bash

# ─────────────────────────────────────────────
#  1_env.sh — 环境准备与检测
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

# ─── 环境预检 & 包管理锁等待 ─────────────────
pre_flight_check() {
    is_package_manager_running() {
        pgrep -x apt >/dev/null || pgrep -x apt-get >/dev/null || \
        pgrep -x dpkg >/dev/null || pgrep -f "unattended-upgr" >/dev/null
    }

    local desc="环境预检 (Pre-flight Check)"
    local max_ticks=300
    local ticks=0

    if is_package_manager_running; then
        echo -e "${INFO} 检测到系统更新进程正在运行，正在等待释放锁..."
        tput civis
        while is_package_manager_running; do
            if [ $ticks -ge $max_ticks ]; then
                tput cnorm
                echo -e "\n${WARN} 等待超时！"

                # ─── 超时处理：询问是否强制终止 ──
                local kill_choice=""
                local error_msg=""
                while true; do
                    if [ -n "$error_msg" ]; then
                        echo -ne "\r\033[K${RED}${error_msg}${PLAIN} 是否强制终止占用进程? (y/n) [n]: "
                    else
                        echo -ne "\r\033[K是否强制终止占用进程? (y/n) [n]: "
                    fi
                    read -r raw_input

                    if [ -z "$raw_input" ]; then
                        kill_choice="n"; break
                    fi

                    if [[ "$raw_input" =~ ^[yYnN]$ ]]; then
                        kill_choice="$raw_input"; break
                    else
                        error_msg="输入无效 '${raw_input}'，请按 y 或 n！"
                        echo -ne "\033[1A"
                    fi
                done

                if [[ "$kill_choice" =~ ^[yY]$ ]]; then
                    echo -e "${WARN} 强制终止可能导致 dpkg 数据库损坏，建议事后执行 'dpkg --configure -a' 确认系统状态。"
                    echo -e "${INFO} 正在强制终止进程..."
                    killall apt apt-get 2>/dev/null
                    rm -f /var/lib/apt/lists/lock /var/cache/apt/archives/lock /var/lib/dpkg/lock*
                    break
                else
                    echo -e "${ERR} 用户取消，安装终止。"; exit 1
                fi
            fi

            local frame=${UI_SPINNER_FRAMES[$((ticks % 4))]}
            printf "\r ${CYAN}[ %s ]${PLAIN} System busy... (${ticks}s)" "$frame"
            sleep 0.5
            ((ticks++))
        done
        tput cnorm
        echo -ne "\r\033[K"
    fi

    # ─── dpkg 数据库完整性校验 ───────────────
    if ! dpkg --audit >/dev/null 2>&1; then
        echo -e "${ERR} 检测到 dpkg 数据库状态异常！"
        echo -e "${YELLOW}建议执行: 'dpkg --configure -a' 修复系统。${PLAIN}"
        exit 1
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

    if curl -s4k -m 3 https://1.1.1.1 >/dev/null 2>&1; then HAS_V4=true; fi
    if curl -s6k -m 3 https://2606:4700:4700::1111 >/dev/null 2>&1; then HAS_V6=true; fi

    if [ "$HAS_V4" = true ] && [ "$HAS_V6" = true ]; then
        NET_TYPE="Dual-Stack (双栈)"
        CURL_OPT="-4"
        DOMAIN_STRATEGY="IPIfNonMatch"
    elif [ "$HAS_V4" = true ]; then
        NET_TYPE="IPv4 Only"
        CURL_OPT="-4"
        DOMAIN_STRATEGY="UseIPv4"
    elif [ "$HAS_V6" = true ]; then
        NET_TYPE="IPv6 Only"
        CURL_OPT="-6"
        DOMAIN_STRATEGY="UseIPv6"

        # ─── IPv6 环境配置 ────────
        echo -e "${INFO} 为纯 IPv6 环境配置 NAT64/DNS64 网关..."
        if [ -f /etc/resolv.conf ]; then
            cp /etc/resolv.conf /etc/resolv.conf.bak
        fi
        printf 'nameserver 2a00:1098:2b::1\nnameserver 2a00:1098:2fac::1\n' > /etc/resolv.conf
    else
        echo -e "${ERR} 无法连接互联网，请检查网络配置！"
        exit 1
    fi

    echo -e "${OK} 网络检测: ${GREEN}${NET_TYPE}${PLAIN}"
}

# ─── 基础环境初始化入口 ──────────────────────
setup_base_env() {
    echo -e "\n${CYAN}--- 1. 基础环境配置 (Basic Env) ---${PLAIN}"

    check_sys_arch

    timedatectl set-ntp true >/dev/null 2>&1

    local current_tz
    current_tz=$(timedatectl show -p Timezone --value 2>/dev/null)
    if [ -z "$current_tz" ]; then
        timedatectl set-timezone UTC
        current_tz="UTC (Default)"
    fi

    echo -e "${OK} 当前时区: ${YELLOW}${current_tz}${PLAIN}"
}
