#!/bin/bash

RED="\033[31m"; GREEN="\033[32m"; YELLOW="\033[33m"; BLUE="\033[36m"; GRAY="\033[90m"; PLAIN="\033[0m"
SYSCTL_CONF="/etc/sysctl.d/99-xray-bbr.conf"
BACKUP_STATE="/etc/sysctl.d/.bbr_backup_state"

if [ "$EUID" -ne 0 ]; then echo -e "${RED}请使用 sudo 运行此脚本！${PLAIN}"; exit 1; fi
clear

# 底层状态快照与回滚引擎
record_backup() {
    if [ ! -f "$BACKUP_STATE" ]; then
        local orig_cc=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null)
        local orig_qd=$(sysctl -n net.core.default_qdisc 2>/dev/null)
        if [[ "$orig_cc" != "bbr" ]]; then
            echo "ORIG_CC=$orig_cc" > "$BACKUP_STATE"
            echo "ORIG_QD=$orig_qd" >> "$BACKUP_STATE"
        fi
    fi
}

do_rollback() {
    rm -f "$SYSCTL_CONF"
    local rest_cc="cubic"
    local rest_qd="fq_codel"
    
    if [ -f "$BACKUP_STATE" ]; then
        source "$BACKUP_STATE"
        [ -n "$ORIG_CC" ] && rest_cc="$ORIG_CC"
        [ -n "$ORIG_QD" ] && rest_qd="$ORIG_QD"
    fi
    
    sysctl -w net.ipv4.tcp_congestion_control="$rest_cc" >/dev/null 2>&1
    sysctl -w net.core.default_qdisc="$rest_qd" >/dev/null 2>&1
    sysctl --system >/dev/null 2>&1
}

# 核心功能模块
get_status() {
    local cc=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null)
    local has_file=0
    [ -f "$SYSCTL_CONF" ] && has_file=1

    # 1. 状态侦测
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

    # 2. 内存过载保护状态侦测
    local has_dog=$(crontab -l 2>/dev/null | grep -c "bbr_watchdog.sh")
    if [ "$has_dog" -gt 0 ] && [ -f "/usr/local/bin/bbr_watchdog.sh" ]; then
        STATUS_DOG="${GREEN}运行中${PLAIN}"
    else
        STATUS_DOG="${GRAY}未启用${PLAIN}"
    fi
}

apply_sysctl() {
    echo -e "\n${BLUE}正在应用内核参数...${PLAIN}"
    sysctl -p "$SYSCTL_CONF" >/dev/null 2>&1
    echo -e "${GREEN}设置已生效！${PLAIN}"
    sleep 2
}

enable_bbr() {
    echo -e "\n${BLUE}正在开启 BBR 并进行基础加固...${PLAIN}"
    record_backup
    modprobe tcp_bbr && modprobe sch_fq
    
    cat > "$SYSCTL_CONF" <<CONF
# 启用 BBR 拥塞控制算法
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr

# 系统级并发与进阶代理优化 (静默集成)
fs.file-max = 1000000
net.ipv4.ip_local_port_range = 1024 65535
net.ipv4.tcp_mtu_probing = 1
net.ipv4.tcp_fastopen = 3

# TCP 连接生命周期管理与回收
net.ipv4.tcp_window_scaling = 1
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_fin_timeout = 15

# TCP 保活探测 (代理节点静默优化)
net.ipv4.tcp_keepalive_time = 600
net.ipv4.tcp_keepalive_intvl = 30
net.ipv4.tcp_keepalive_probes = 3
CONF
    apply_sysctl
}

enable_native_bbr() {
    echo -e "\n${BLUE}正在开启原生 BBR...${PLAIN}"
    record_backup
    modprobe tcp_bbr && modprobe sch_fq
    
    cat > "$SYSCTL_CONF" <<CONF
# 原生 BBR 拥塞控制算法
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
CONF
    apply_sysctl
}

disable_bbr() {
    echo -e "\n${BLUE}正在关闭 BBR 并恢复系统默认...${PLAIN}"
    do_rollback
    echo -e "${GREEN}已恢复至系统默认状态。${PLAIN}"
    sleep 2
}

install_watchdog() {
    echo -e "\n${BLUE}正在部署内存过载保护...${PLAIN}"
    
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
        rest_cc="cubic"
        rest_qd="fq_codel"
        if [ -f "$BACKUP_STATE" ]; then
            source "$BACKUP_STATE"
            [ -n "$ORIG_CC" ] && rest_cc="$ORIG_CC"
            [ -n "$ORIG_QD" ] && rest_qd="$ORIG_QD"
        fi
        
        sysctl -w net.ipv4.tcp_congestion_control="$rest_cc" >/dev/null 2>&1
        sysctl -w net.core.default_qdisc="$rest_qd" >/dev/null 2>&1
        sync; echo 3 > /proc/sys/vm/drop_caches
        sysctl --system >/dev/null 2>&1
        
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] [RECOVERED] Circuit broken. System restored to safe defaults to prevent SSH drop." >> "$LOG_FILE"
    fi
fi
EOF_DOG

    chmod +x /usr/local/bin/bbr_watchdog.sh
    (crontab -l 2>/dev/null | grep -v "bbr_watchdog.sh"; echo "* * * * * /usr/local/bin/bbr_watchdog.sh") | crontab -
    
    echo -e "${GREEN}内存过载保护已启用！${PLAIN}"
    sleep 2
}

uninstall_watchdog() {
    echo -e "\n${BLUE}正在关闭内存过载保护...${PLAIN}"
    (crontab -l 2>/dev/null | grep -v "bbr_watchdog.sh") | crontab -
    rm -f /usr/local/bin/bbr_watchdog.sh
    echo -e "${GREEN}内存过载保护已关闭。${PLAIN}"
    sleep 2
}

# 主菜单循环
clear
while true; do
    get_status
    
    tput cup 0 0
    echo -e "${BLUE}===================================================${PLAIN}\033[K"
    echo -e "${BLUE}          BBR 网络优化 (Network Manager)          ${PLAIN}\033[K"
    echo -e "${BLUE}===================================================${PLAIN}\033[K"
    echo -e "  BBR 状态 : ${STATUS_MAIN}\033[K"
    echo -e "  过载保护 : ${STATUS_DOG}\033[K"
    echo -e "---------------------------------------------------\033[K"
    echo -e "  1. ${GREEN}开启 BBR 原生${PLAIN}     - BBR+FQ\033[K"
    echo -e "  2. ${GREEN}开启 BBR 加固${PLAIN}     - BBR+FQ+基础加固\033[K"
    echo -e "  3. ${YELLOW}关闭 BBR${PLAIN}          - 恢复系统默认\033[K"
    echo -e "---------------------------------------------------\033[K"
    echo -e "  4. ${GREEN}开启 内存过载保护${PLAIN} - 95%自动熔断-->恢复系统默认\033[K"
    echo -e "  5. ${YELLOW}关闭 内存过载保护${PLAIN}\033[K"
    echo -e "---------------------------------------------------\033[K"
    echo -e "  0. 退出 (Exit)\033[K"
    echo -e "\033[K"
    
    tput ed

    while true; do
        echo -ne "\r\033[K请输入选项 [0-5]: "
        read -r choice
        case "$choice" in
            1|2|3|4|5|0) break ;;
            *) echo -ne "\r\033[K${RED}输入无效...${PLAIN}"; sleep 0.5 ;;
        esac
    done

    case "$choice" in
        1) enable_native_bbr ;;
        2) enable_bbr ;;
        3) disable_bbr ;;
        4) install_watchdog ;;
        5) uninstall_watchdog ;;
        0) echo -e "\nbye."; clear; exit 0 ;;
    esac
done
