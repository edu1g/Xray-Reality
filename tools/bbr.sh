#!/bin/bash

# 基础配置
RED="\033[31m"; GREEN="\033[32m"; YELLOW="\033[33m"; BLUE="\033[36m"; GRAY="\033[90m"; PLAIN="\033[0m"
SYSCTL_CONF="/etc/sysctl.d/99-xray-bbr.conf"

if [ "$EUID" -ne 0 ]; then echo -e "${RED}请使用 sudo 运行此脚本！${PLAIN}"; exit 1; fi
clear

# 核心函数
get_status() {
    local cc=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null)
    local qd=$(sysctl -n net.core.default_qdisc 2>/dev/null)
    local has_file=0
    [ -f "$SYSCTL_CONF" ] && has_file=1

    # --- 1. 拥塞算法状态 ---
    if [[ "$cc" == "bbr" ]]; then
        STATUS_BBR="${GREEN}已开启 (BBR)${PLAIN}"
    else
        STATUS_BBR="${YELLOW}未开启 (${cc})${PLAIN}"
    fi

    # --- 2. 策略模式判定 ---
    if [[ "$cc" == "bbr" ]] && [ $has_file -eq 1 ]; then
        # 侦测是否包含硬核参数特征值
        if grep -q "tcp_mem" "$SYSCTL_CONF" 2>/dev/null; then
            STATUS_MODE="${BLUE}自定义调参 (硬核模式)${PLAIN}"
        else
            STATUS_MODE="${GREEN}Google 优化 (脚本管理)${PLAIN}"
        fi
        
    elif [[ "$cc" != "bbr" ]] && [ $has_file -eq 0 ]; then
        STATUS_MODE="${GRAY}Linux 默认 (${cc})${PLAIN}"
        
    elif [[ "$cc" == "bbr" ]] && [ $has_file -eq 0 ]; then
        STATUS_MODE="${GRAY}Linux 默认 (系统自带 BBR)${PLAIN}"
        
    else
        STATUS_MODE="${RED}配置异常 (未生效)${PLAIN}"
    fi

    # --- 3. 队列调度状态 ---
    if [[ "$STATUS_MODE" == *Google* ]] || [[ "$STATUS_MODE" == *自定义* ]]; then
        if [[ "$qd" == "fq" ]]; then
            STATUS_QDISC="${GREEN}FQ${PLAIN}"
        else
            STATUS_QDISC="${RED}${qd} (建议 FQ)${PLAIN}"
        fi
    else
        STATUS_QDISC="${GRAY}${qd}${PLAIN}"
    fi
}

apply_sysctl() {
    echo -e "\n${BLUE}[INFO] 正在应用内核参数...${PLAIN}"
    sysctl -p "$SYSCTL_CONF" >/dev/null 2>&1
    echo -e "${GREEN}设置已生效！${PLAIN}"
    sleep 2
}

enable_bbr() {
    echo -e "\n${BLUE}正在应用 Google BBR 优化策略...${PLAIN}"
    modprobe tcp_bbr && modprobe sch_fq
    
    cat > "$SYSCTL_CONF" <<CONF
# Google BBR Strategy
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
CONF
    apply_sysctl
}

disable_bbr() {
    echo -e "\n${BLUE}正在恢复 Linux 系统默认策略...${PLAIN}"
    rm -f "$SYSCTL_CONF"
    sysctl --system >/dev/null 2>&1
    echo -e "${GREEN}已恢复至 Linux 原生标准。${PLAIN}"
    sleep 2
}

custom_tuning() {
    echo -e "${RED}==========================================================${PLAIN}"
    echo -e "${RED}【警告】您即将进入无限制调参模式！                                      ${PLAIN}"
    echo -e "${YELLOW}本脚本已解除所有硬件数值的合理性限制。                               ${PLAIN}"
    echo -e "${YELLOW}允许您键入任何数值，但您须为此负责！                                ${PLAIN}"
    echo -e "${YELLOW}极端的参数可能导致服务器内存溢出(OOM)、网络瘫痪或直接死机。             ${PLAIN}"
    echo -e "${RED}==========================================================${PLAIN}"

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
                echo -en "${RED}错误：必须输入正整数。${PLAIN}"
                sleep 1
                echo -en "\r\033[K"
            fi
        done
    }

    get_valid_input "1. 输入服务器物理内存(MB)   (提示: 1GB=1024MB)    : " RAM_MB
    get_valid_input "2. 输入服务器CPU核心数(个)  (提示: 输入正整数)    : " CPU_CORES
    get_valid_input "3. 输入服务器最大带宽(Mbps) (提示: 1Gbps=1000Mbps): " BANDWIDTH_MBPS

    echo -e "\n${GREEN}接收指令！正在根据您的输入计算并应用网络参数...${PLAIN}"

    TOTAL_PAGES=$(( RAM_MB * 256 ))
    TCP_MEM_MIN=$(( TOTAL_PAGES * 10 / 100 ))
    TCP_MEM_PRESSURE=$(( TOTAL_PAGES * 15 / 100 ))
    TCP_MEM_MAX=$(( TOTAL_PAGES * 20 / 100 ))

    BUFFER_MAX=$(( BANDWIDTH_MBPS * 1024 * 1024 / 8 * 2 / 10 ))
    QUEUE_SIZE=$(( CPU_CORES * 2048 ))

    cat > "$SYSCTL_CONF" <<EOF
# 自定义调参
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr

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

    sysctl -p "$SYSCTL_CONF"
    echo -e "\n${GREEN}配置完成！网络优化已生效${PLAIN}"
    read -n 1 -s -r -p "按任意键返回..." 
}

# 主交互逻辑
while true; do
    get_status
    
    tput cup 0 0
    echo -e "${BLUE}===================================================${PLAIN}"
    echo -e "${BLUE}          BBR 网络优化 (Network Manager)          ${PLAIN}"
    echo -e "${BLUE}===================================================${PLAIN}"
    echo -e "  拥塞算法 : ${STATUS_BBR}\033[K"
    echo -e "  队列调度 : ${STATUS_QDISC}\033[K"
    echo -e "  当前策略 : ${STATUS_MODE}\033[K"
    echo -e "---------------------------------------------------"
    echo -e "  1. ${GREEN}Google 优化策略${PLAIN} (BBR + FQ)"
    echo -e "  2. ${YELLOW}Linux  默认策略${PLAIN} (Cubic + FQ_CODEL)"
    echo -e "  3. ${BLUE}自定义策略${PLAIN}      (硬核调参)"
    echo -e "---------------------------------------------------"
    echo -e "  0. 退出 (Exit)"
    echo -e ""
    
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
        0) echo -e "\nbye."; clear; exit 0 ;;
    esac
done
