#!/bin/bash

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
if [ "$KERNEL_MAJOR" -gt 4 ] || { [ "$KERNEL_MAJOR" -eq 4 ] && [ "$KERNEL_MINOR" -ge 9 ]; }; then
    BBR_SUPPORTED=1
fi

# ─── Root 检查 ────────────────────────────────
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}请使用 sudo 运行此脚本！${PLAIN}"
    exit 1
fi
clear

# ─── 内核升级指引 ─────────────────────────────
show_kernel_upgrade_guide() {
    clear
    echo -e "${CYAN}===================================================${PLAIN}"
    echo -e "${BOLD}  ${RED}当前内核不支持 BBR${PLAIN}"
    echo -e "${CYAN}===================================================${PLAIN}"
    echo -e "  BBR 需要 Linux 内核 4.9 或更高版本。"
    echo -e "  当前内核: ${YELLOW}${KERNEL_VERSION}${PLAIN}"
    echo ""
    echo -e "${CYAN}  ── 升级指引 ────────────────────────────────────${PLAIN}"
    echo ""

    if [ -f /etc/os-release ]; then
        # shellcheck source=/dev/null
        . /etc/os-release
        DISTRO_ID="${ID,,}"
    else
        DISTRO_ID="unknown"
    fi

    case "$DISTRO_ID" in
        ubuntu|debian|linuxmint)
            echo -e "  ${GREEN}Debian / Ubuntu${PLAIN}"
            HWE_VER=$(lsb_release -rs 2>/dev/null || echo "")
            if [ -n "$HWE_VER" ]; then
                echo -e "  ${YELLOW}apt update && apt install --install-recommends linux-generic-hwe-${HWE_VER}${PLAIN}"
            else
                echo -e "  ${YELLOW}apt update && apt install --install-recommends linux-generic-hwe-*${PLAIN}"
            fi
            echo -e "  ${YELLOW}reboot${PLAIN}"
            ;;
        centos|rhel|rocky|almalinux)
            echo -e "  ${GREEN}CentOS / RHEL / Rocky / AlmaLinux${PLAIN}"
            echo -e "  ${YELLOW}# Step 1: 启用 ELRepo"
            echo -e "  rpm --import https://www.elrepo.org/RPM-GPG-KEY-elrepo.org"
            echo -e "  yum install https://www.elrepo.org/elrepo-release-8.el8.elrepo.noarch.rpm"
            echo -e "  # Step 2: 安装主线内核"
            echo -e "  yum --enablerepo=elrepo-kernel install kernel-ml"
            echo -e "  reboot${PLAIN}"
            ;;
        fedora)
            echo -e "  ${GREEN}Fedora${PLAIN}"
            echo -e "  ${YELLOW}dnf update kernel && reboot${PLAIN}"
            ;;
        *)
            echo -e "  请通过您的发行版包管理器升级至内核 ≥ 4.9。"
            echo -e "  参考: https://kernel.org 或您的发行版官方文档"
            ;;
    esac

    echo ""
    echo -e "  ${GRAY}升级并重启后，重新运行此脚本即可。${PLAIN}"
    echo -e "${CYAN}===================================================${PLAIN}"
    echo ""
    read -rp "  按 Enter 返回..." _
    clear
}

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
        # shellcheck source=/dev/null
        source "$BACKUP_STATE"
        [ -n "$ORIG_CC" ] && rest_cc="$ORIG_CC"
        [ -n "$ORIG_QD" ] && rest_qd="$ORIG_QD"
    fi
    sysctl -w net.ipv4.tcp_congestion_control="$rest_cc" >/dev/null 2>&1
    sysctl -w net.core.default_qdisc="$rest_qd" >/dev/null 2>&1
    sysctl --system >/dev/null 2>&1
}

# ─── BBR 验证 ────────────────────────────────
verify_bbr() {
    local active_cc
    active_cc=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null)
    if [[ "$active_cc" == "BBR" ]]; then
        echo "${GREEN} 验证通过${PLAIN} (当前: ${active_cc})"
    else
        echo "${RED} 验证失败${PLAIN} — BBR 未实际生效 (当前: ${active_cc})"
    fi
}

# ─── 状态读取 ────────────────────────────────
get_status() {
    local cc has_file=0
    cc=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null)
    [ -f "$SYSCTL_CONF" ] && has_file=1

    if [ $has_file -eq 1 ]; then
        if grep -q "tcp_keepalive_time" "$SYSCTL_CONF" 2>/dev/null; then
            STATUS_MAIN="${GREEN}已启用 - BBR 加固${PLAIN}"
        else
            STATUS_MAIN="${GREEN}已启用 - BBR 原生${PLAIN}"
        fi
    else
        if [[ "$cc" == "bbr" ]]; then
            STATUS_MAIN="${YELLOW}已启用 (系统默认)${PLAIN}"
        else
            STATUS_MAIN="${GRAY}未启用 (系统默认)${PLAIN}"
        fi
    fi

    local has_dog
    has_dog=$(crontab -l 2>/dev/null | grep -c "bbr_watchdog.sh")
    if [ "$has_dog" -gt 0 ] && [ -f "/usr/local/bin/bbr_watchdog.sh" ]; then
        STATUS_DOG="${GREEN}运行中${PLAIN}"
    else
        STATUS_DOG="${GRAY}未启用${PLAIN}"
    fi

    if [ $BBR_SUPPORTED -eq 1 ]; then
        STATUS_KERNEL="${KERNEL_VERSION} — ${GREEN}支持 (≥4.9)${PLAIN}"
    else
        STATUS_KERNEL="${KERNEL_VERSION} — ${RED}不支持 (<4.9)${PLAIN}"
    fi
}

apply_sysctl() {
    sysctl -p "$SYSCTL_CONF" >/dev/null 2>&1
}

# ─── 启用 / 关闭 BBR ──────────────────────────
enable_bbr() {
    if [ $BBR_SUPPORTED -eq 0 ]; then
        show_kernel_upgrade_guide
        return
    fi
    record_backup
    modprobe tcp_bbr 2>/dev/null && modprobe sch_fq 2>/dev/null
    cat > "$SYSCTL_CONF" <<CONF
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr

fs.file-max = 1000000
net.ipv4.ip_local_port_range = 1024 65535
net.ipv4.tcp_mtu_probing = 1
net.ipv4.tcp_fastopen = 3

net.ipv4.tcp_window_scaling = 1
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_fin_timeout = 15

net.ipv4.tcp_keepalive_time = 600
net.ipv4.tcp_keepalive_intvl = 30
net.ipv4.tcp_keepalive_probes = 3
CONF
    apply_sysctl
    UI_MESSAGE="${GREEN}BBR 基础加固已启用！${PLAIN}  $(verify_bbr)"
}

enable_native_bbr() {
    if [ $BBR_SUPPORTED -eq 0 ]; then
        show_kernel_upgrade_guide
        return
    fi
    record_backup
    modprobe tcp_bbr 2>/dev/null && modprobe sch_fq 2>/dev/null
    cat > "$SYSCTL_CONF" <<CONF
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
CONF
    apply_sysctl
    UI_MESSAGE="${GREEN}BBR 原生模式已启用！${PLAIN}  $(verify_bbr)"
}

disable_bbr() {
    do_rollback
    UI_MESSAGE="${YELLOW}BBR 已关闭，已恢复系统默认状态。${PLAIN}"
}

# ─── 过载保护 Watchdog ────────────────────────
install_watchdog() {
    cat > /usr/local/bin/bbr_watchdog.sh << 'EOF_DOG'
#!/bin/bash
CRITICAL_RAM_PERCENT=95
SYSCTL_CONF="/etc/sysctl.d/99-xray-bbr.conf"
LOG_FILE="/var/log/bbr_watchdog_rescue.log"
BACKUP_STATE="/etc/sysctl.d/.bbr_backup_state"

total_ram=$(free -m | awk '/^Mem:/{print $2}')
avail_ram=$(free -m | awk '/^Mem:/{print $7}')
used_percent=$(( (total_ram - avail_ram) * 100 / total_ram ))

if [ "$used_percent" -ge "$CRITICAL_RAM_PERCENT" ]; then
    if [ -f "$SYSCTL_CONF" ]; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] [CRITICAL] RAM spiked to ${used_percent}%! Triggering auto-circuit breaker!" >> "$LOG_FILE"
        rm -f "$SYSCTL_CONF"
        rest_cc="cubic"; rest_qd="fq_codel"
        if [ -f "$BACKUP_STATE" ]; then
            source "$BACKUP_STATE"
            [ -n "$ORIG_CC" ] && rest_cc="$ORIG_CC"
            [ -n "$ORIG_QD" ] && rest_qd="$ORIG_QD"
        fi
        sysctl -w net.ipv4.tcp_congestion_control="$rest_cc" >/dev/null 2>&1
        sysctl -w net.core.default_qdisc="$rest_qd" >/dev/null 2>&1
        sync; echo 3 > /proc/sys/vm/drop_caches
        sysctl --system >/dev/null 2>&1
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] [RECOVERED] Circuit broken. System restored to safe defaults." >> "$LOG_FILE"
    fi
fi
EOF_DOG
    chmod +x /usr/local/bin/bbr_watchdog.sh
    (crontab -l 2>/dev/null | grep -v "bbr_watchdog.sh"; echo "* * * * * /usr/local/bin/bbr_watchdog.sh") | crontab -
    UI_MESSAGE="${GREEN}内存过载保护已启用！${PLAIN}"
}

uninstall_watchdog() {
    (crontab -l 2>/dev/null | grep -v "bbr_watchdog.sh") | crontab -
    rm -f /usr/local/bin/bbr_watchdog.sh
    UI_MESSAGE="${YELLOW}内存过载保护已关闭。${PLAIN}"
}

# ─── 菜单界面 ────────────────────────────────
show_menu_ui() {
    tput cup 0 0
    get_status

    echo -e "${CYAN}===================================================${PLAIN}\033[K"
    echo -e "${CYAN}          BBR 网络优化 (Network Manager)          ${PLAIN}\033[K"
    echo -e "${CYAN}===================================================${PLAIN}\033[K"
    echo -e "  BBR 状态 : ${STATUS_MAIN}\033[K"
    echo -e "  过载保护 : ${STATUS_DOG}\033[K"
    echo -e "  内核版本 : ${STATUS_KERNEL}\033[K"
    echo -e "---------------------------------------------------\033[K"
    echo -e "  1. ${GREEN}开启 BBR 原生${PLAIN}     - BBR+FQ\033[K"
    echo -e "  2. ${GREEN}开启 BBR 加固${PLAIN}     - BBR+FQ+基础加固\033[K"
    echo -e "  3. ${YELLOW}关闭 BBR${PLAIN}          - 恢复系统默认\033[K"
    echo -e "---------------------------------------------------\033[K"
    echo -e "  4. ${GREEN}开启 内存过载保护${PLAIN} - 95%自动熔断→恢复系统默认\033[K"
    echo -e "  5. ${YELLOW}关闭 内存过载保护${PLAIN}\033[K"
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

    error_msg=""
    while true; do
        if [ -n "$error_msg" ]; then
            echo -ne "\r\033[K${RED}${error_msg}${PLAIN} 请输入选项 [0-5]: "
        else
            echo -ne "\r\033[K请输入选项 [0-5]: "
        fi
        read -r choice
        case "$choice" in
            0|1|2|3|4|5) break ;;
            *)
                error_msg="输入无效！"
                echo -ne "\033[1A"
                ;;
        esac
    done

    case "$choice" in
        1) enable_native_bbr ;;
        2) enable_bbr ;;
        3) disable_bbr ;;
        4) install_watchdog ;;
        5) uninstall_watchdog ;;
        0) clear; exit 0 ;;
    esac
done
