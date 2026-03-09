#!/bin/bash

# ─────────────────────────────────────────────
#  1_env.sh — 环境准备与检测 (全自动无人值守修复版)
# ─────────────────────────────────────────────

check_sys_arch() {
    if [ ! -f /etc/debian_version ]; then
        echo -e "${ERR} 本脚本仅支持 Debian/Ubuntu 系统！"
        exit 1
    fi

    ARCH=$(uname -m)
    case $ARCH in
        x86_64)  ARCH="amd64" ;;
        aarch64) ARCH="arm64" ;;
        *) echo -e "${ERR} 不支持的架构: ${ARCH}"; exit 1 ;;
    esac
    echo -e "${OK} 系统检查: Debian/Ubuntu (${ARCH})"
}

pre_flight_check() {
    is_package_manager_running() {
        pgrep -x apt >/dev/null || pgrep -x apt-get >/dev/null || \
        pgrep -x dpkg >/dev/null || pgrep -f "unattended-upgr" >/dev/null
    }

    local max_ticks=300
    local ticks=0

    if is_package_manager_running; then
        echo -e "${INFO} 正在自动处理包管理器锁..."
        tput civis
        while is_package_manager_running; do
            if [ $ticks -ge $max_ticks ]; then
                tput cnorm
                echo -e "\n${WARN} 等待超时，正在强制清理占用进程..."
                killall apt apt-get dpkg 2>/dev/null
                rm -f /var/lib/apt/lists/lock /var/cache/apt/archives/lock /var/lib/dpkg/lock*
                break
            fi
            local frame=${UI_SPINNER_FRAMES[$((ticks % 4))]}
            printf "\r ${CYAN}[ %s ]${PLAIN} 系统繁忙，自动等待中... (${ticks}s)" "$frame"
            sleep 1
            ((ticks++))
        done
        tput cnorm
        echo -ne "\r\033[K"
    fi

    if ! dpkg --audit >/dev/null 2>&1; then
        dpkg --configure -a >/dev/null 2>&1
    fi

    if ! command -v curl >/dev/null 2>&1; then
        apt-get update -qq >/dev/null 2>&1
        apt-get install -y -qq curl ca-certificates >/dev/null 2>&1
    fi
    echo -e "${OK} 环境预检完成"
}

check_net_stack() {
    HAS_V4=false; HAS_V6=false; CURL_OPT=""
    if curl -s4k -m 3 https://1.1.1.1 >/dev/null 2>&1; then HAS_V4=true; fi
    if curl -s6k -m 3 https://2606:4700:4700::1111 >/dev/null 2>&1; then HAS_V6=true; fi

    if [ "$HAS_V4" = true ] && [ "$HAS_V6" = true ]; then
        NET_TYPE="Dual-Stack"; CURL_OPT="-4"; DOMAIN_STRATEGY="IPIfNonMatch"
    elif [ "$HAS_V4" = true ]; then
        NET_TYPE="IPv4 Only"; CURL_OPT="-4"; DOMAIN_STRATEGY="UseIPv4"
    elif [ "$HAS_V6" = true ]; then
        NET_TYPE="IPv6 Only"; CURL_OPT="-6"; DOMAIN_STRATEGY="UseIPv6"
        printf 'nameserver 2a00:1098:2b::1\nnameserver 2a00:1098:2fac::1\n' > /etc/resolv.conf
    else
        echo -e "${ERR} 网络连接失败"; exit 1
    fi
    echo -e "${OK} 网络检测: ${GREEN}${NET_TYPE}${PLAIN}"
}

setup_base_env() {
    echo -e "\n${CYAN}--- 1. 基础环境配置 ---${PLAIN}"
    check_sys_arch
    timedatectl set-ntp true >/dev/null 2>&1
    local tz=$(timedatectl show -p Timezone --value 2>/dev/null)
    [ -z "$tz" ] && timedatectl set-timezone UTC
    echo -e "${OK} 基础环境设置完成"
}
