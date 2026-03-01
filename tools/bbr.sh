#!/bin/bash

# 基础配置
RED="\033[31m"; GREEN="\033[32m"; YELLOW="\033[33m"; BLUE="\033[36m"; GRAY="\033[90m"; PLAIN="\033[0m"
SYSCTL_CONF="/etc/sysctl.d/99-xray-bbr.conf"

if [ "$EUID" -ne 0 ]; then echo -e "${RED}请使用 sudo 运行此脚本！${PLAIN}"; exit 1; fi
clear

# 核心函数
get_status() {
    local cc=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null)
    local has_file=0
    [ -f "$SYSCTL_CONF" ] && has_file=1

    # 四象限状态侦测逻辑
    if [ $has_file -eq 1 ]; then
        # 脚本介入状态
        if grep -q "tcp_mem" "$SYSCTL_CONF" 2>/dev/null; then
            STATUS_MAIN="${GREEN}BBR 已启用 (自定义)${PLAIN}"
        else
            STATUS_MAIN="${GREEN}BBR 已启用 (基础加固)${PLAIN}"
        fi
    else
        # 恢复默认/非脚本介入状态
        if [[ "$cc" == "bbr" ]]; then
            STATUS_MAIN="${YELLOW}BBR 已启用 (系统默认)${PLAIN}"
        else
            STATUS_MAIN="${GRAY}BBR 未启用 (系统默认)${PLAIN}"
        fi
    fi
}

apply_sysctl() {
    echo -e "\n${BLUE}正在应用内核参数...${PLAIN}"
    sysctl -p "$SYSCTL_CONF" >/dev/null 2>&1
    echo -e "${GREEN}设置已生效！${PLAIN}"
    sleep 2
}

enable_bbr() {
    echo -e "\n${BLUE}正在开启 BBR 并进行基础并发加固...${PLAIN}"
    modprobe tcp_bbr && modprobe sch_fq
    
    cat > "$SYSCTL_CONF" <<CONF
# Basic BBR Strategy & Baseline Safety
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
net.ipv4.tcp_window_scaling = 1

# 基础并发防线 (静默加固)
fs.file-max = 1000000
net.ipv4.ip_local_port_range = 1024 65535
CONF
    apply_sysctl
}

disable_bbr() {
    echo -e "\n${BLUE}正在关闭 BBR 并恢复系统默认...${PLAIN}"
    rm -f "$SYSCTL_CONF"
    # 强制将内存中的运行状态拨回系统默认
    sysctl -w net.ipv4.tcp_congestion_control=cubic >/dev/null 2>&1
    sysctl -w net.core.default_qdisc=fq_codel >/dev/null 2>&1
    sysctl --system >/dev/null 2>&1
    echo -e "${OK} ${GREEN}已恢复系统默认。${PLAIN}"
    sleep 2
}

custom_tuning() {
    echo -e "${RED}============================================================================${PLAIN}"
    echo -e "${RED}【警告】您即将进入无限制调参模式！                               ${PLAIN}"
    echo -e "${YELLOW}本脚本已解除所有硬件数值的合理性限制。                        ${PLAIN}"
    echo -e "${YELLOW}允许您键入任何数值，但您须为此负责！                         ${PLAIN}"
    echo -e "${YELLOW}极端的参数可能导致服务器内存溢出(OOM)、网络瘫痪或直接死机。      ${PLAIN}"
    echo -e "${RED}============================================================================${PLAIN}"

    get_valid_input() {
        local prompt="$1"
        local var_name="$2"
        local input_val

        while true; do
            read -p "$prompt" input_val < /dev/tty
            
            if [[ "$input_val" =~ ^[1-9][0-9]*$ ]]; then
                eval "$var_name=\"$input_val\""
                break
            else
                echo -en "\033[1A\r\033[K"
                echo -en "${ERR} ${RED}错误：必须输入正整数。${PLAIN}"
                sleep 1
                echo -en "\r\033[K"
            fi
        done
    }

    # 硬件参数录入
    get_valid_input "1. 输入物理内存(MB)     (提示: 1GB=1024MB)                            : " RAM_MB
    get_valid_input "2. 输入CPU核心数(个)    (提示: 输入正整数)                            : " CPU_CORES
    
    # 动态带宽与延迟录入 (BDP计算基础)
    get_valid_input "3. 输入最大带宽(Mbps)   (提示: 1Gbps=1000Mbps)                        : " BANDWIDTH_MBPS
    get_valid_input "4. 输入平均网络延迟(ms) (提示: 跨国通常150-300，同城10-50)            : " LATENCY_MS
    get_valid_input "5. 输入缓冲区冗余系数   (提示: 稳定网络输入2，跨国恶劣网络输入3或更高): " BDP_MULTIPLIER

    echo -e "${RED}----------------------------------------------------------------------------${PLAIN}"
	
    # 1. 计算 TCP 全局内存限制 (单位: 内存页, 1页=4KB)
    TOTAL_PAGES=$(( RAM_MB * 256 ))
    TCP_MEM_MIN=$(( TOTAL_PAGES * 10 / 100 ))
    TCP_MEM_PRESSURE=$(( TOTAL_PAGES * 15 / 100 ))
    TCP_MEM_MAX=$(( TOTAL_PAGES * 20 / 100 ))

    # 2. 精确计算动态缓冲区 (BDP = 带宽 * 延迟，1Mbps=131072Bytes/s)
    BUFFER_MAX=$(( BANDWIDTH_MBPS * 131072 * LATENCY_MS / 1000 * BDP_MULTIPLIER ))

    # 3. 计算并发队列极限
    QUEUE_SIZE=$(( CPU_CORES * 2048 ))

    # 4. 计算 TIME_WAIT 数量上限 (物理内存MB * 10)
    MAX_TW_BUCKETS=$(( RAM_MB * 10 ))

    cat > "$SYSCTL_CONF" <<EOF
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
net.ipv4.tcp_max_tw_buckets = $MAX_TW_BUCKETS

# TCP 保活探测 (代理节点静默优化)
net.ipv4.tcp_keepalive_time = 600
net.ipv4.tcp_keepalive_intvl = 30
net.ipv4.tcp_keepalive_probes = 3

# 动态网络缓冲区限制 (Bytes)
net.core.rmem_max = $BUFFER_MAX
net.core.wmem_max = $BUFFER_MAX
net.ipv4.tcp_rmem = 4096 131072 $BUFFER_MAX
net.ipv4.tcp_wmem = 4096 131072 $BUFFER_MAX

# 全局 TCP 内存限制 (Pages)
net.ipv4.tcp_mem = $TCP_MEM_MIN $TCP_MEM_PRESSURE $TCP_MEM_MAX

# 动态并发连接队列数
net.core.somaxconn = $QUEUE_SIZE
net.ipv4.tcp_max_syn_backlog = $QUEUE_SIZE
net.core.netdev_max_backlog = $QUEUE_SIZE
EOF

    echo -e "\n${YELLOW}正在注入内核参数... 亡人开关已激活！${PLAIN}"
    sysctl -p "$SYSCTL_CONF"
    echo -e "${RED}----------------------------------------------------------------------------${PLAIN}"
    # 启动后台绝对守护进程 (应对 SSH 彻底断开导致主进程死亡的极端情况)
    (
        sleep 60
        if [ -f "$SYSCTL_CONF" ]; then
            rm -f "$SYSCTL_CONF"
            sysctl -w net.ipv4.tcp_congestion_control=cubic >/dev/null 2>&1
            sysctl -w net.core.default_qdisc=fq_codel >/dev/null 2>&1
            sysctl --system >/dev/null 2>&1
        fi
    ) & 
    local TIMER_PID=$! # 捕获后台定时炸弹进程ID
    echo -e "${YELLOW}参数已写入内核！${RED}SSH 连接是否存活？${PLAIN}"

    local timeout=60
    local is_alive="timeout"
    
    tput civis # 隐藏终端光标，使倒计时动画更平滑
    
    # 实时倒计时渲染循环
    while [ $timeout -gt 0 ]; do
        # 实时刷新同一行内容
        echo -ne "\r\033[K${YELLOW}自动回滚倒计时 ${RED}${timeout} ${YELLOW}秒${PLAIN}（按 ${GREEN}y${PLAIN} 确认存活，按 ${RED}N${PLAIN} 放弃更改）"
        
        # 阻塞 1 秒等待按键输入，无需回车
        if read -t 1 -n 1 -s input < /dev/tty; then
            if [[ "${input,,}" == "y" ]]; then
                is_alive="y"
                break
            elif [[ "${input,,}" == "n" ]]; then
                is_alive="n"
                break
            fi
        fi
        ((timeout--))
    done
    
    tput cnorm
    echo ""

    # 倒计时结束后的逻辑分支判断
    if [[ "$is_alive" == "y" ]]; then
        kill $TIMER_PID 2>/dev/null
        echo -e "${GREEN}确认存活！亡人开关已解除，网络优化已生效。${PLAIN}"
    read -n 1 -s -r -p "按任意键返回..." 
    elif [[ "$is_alive" == "n" ]]; then
        echo -e "${YELLOW}放弃更改。正在回滚...${PLAIN}"
        kill $TIMER_PID 2>/dev/null
        rm -f "$SYSCTL_CONF"
        sysctl -w net.ipv4.tcp_congestion_control=cubic >/dev/null 2>&1
        sysctl -w net.core.default_qdisc=fq_codel >/dev/null 2>&1
        sysctl --system >/dev/null 2>&1
        echo -e "${GREEN}已恢复系统默认。${PLAIN}"
    read -n 1 -s -r -p "按任意键返回..." 
    else
        # 倒计时归零，或用户网络卡死无法输入
        echo -e "\n${YELLOW}失去响应或倒计时结束！正在执行强制回滚...${PLAIN}"
        kill $TIMER_PID 2>/dev/null
        rm -f "$SYSCTL_CONF"
        sysctl -w net.ipv4.tcp_congestion_control=cubic >/dev/null 2>&1
        sysctl -w net.core.default_qdisc=fq_codel >/dev/null 2>&1
        sysctl --system >/dev/null 2>&1
        echo -e "${GREEN}死里逃生！已恢复系统默认值。${PLAIN}"
        read -n 1 -s -r -p "按任意键返回..." 
    fi
}

# 主交互逻辑
while true; do
    get_status
    
    tput cup 0 0
    echo -e "${BLUE}===================================================${PLAIN}\033[K"
    echo -e "${BLUE}          BBR 网络优化 (Network Manager)          ${PLAIN}\033[K"
    echo -e "${BLUE}===================================================${PLAIN}\033[K"
    echo -e "  当前状态 : ${STATUS_MAIN}\033[K"
    echo -e "---------------------------------------------------\033[K"
    echo -e "  1. ${GREEN}开启 BBR${PLAIN} (BBR+FQ+基础加固)\033[K"
    echo -e "  2. ${YELLOW}关闭 BBR${PLAIN} (恢复系统默认)\033[K"
    echo -e "  3. TCP 调优 (自定义)\033[K"
    echo -e "---------------------------------------------------\033[K"
    echo -e "  0. 退出 (Exit)\033[K"
    echo -e "\033[K"
    
    tput ed

    while true; do
        echo -ne "\r\033[K请输入选项 [0-3]: "
        read -r choice
        case "$choice" in
            1|2|3|0) break ;;
            *) echo -ne "\r\033[K${RED}输入无效...${PLAIN}"; sleep 0.5 ;;
        esac
    done

    case "$choice" in
        1) enable_bbr ;;
        2) disable_bbr ;;
        3) custom_tuning ;;
        0) echo -e "\nbye.\033[K"; clear; exit 0 ;;
    esac
done
