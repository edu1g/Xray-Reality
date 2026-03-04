#!/bin/bash
RED="\033[31m"; GREEN="\033[32m"; YELLOW="\033[33m"; BLUE="\033[36m"; GRAY="\033[90m"; PLAIN="\033[0m"

UI_MESSAGE=""

if [ "$EUID" -ne 0 ]; then echo -e "${RED}请使用 sudo 运行此脚本！${PLAIN}"; exit 1; fi

print_error() {
    local msg="$1"
    printf "\r\033[K${RED}%s${PLAIN}" "$msg"
    sleep 1
    printf "\r\033[K"
}

get_valid_int() {
    local prompt="$1"
    local __resultvar=$2
    local min=${3:-0}
    local max=${4:-999999}
    local input_val
    local error_msg=""

    while true; do
        if [ -n "$error_msg" ]; then
            echo -ne "\r\033[K${RED}${error_msg}${PLAIN} ${prompt}"
        else
            echo -ne "\r\033[K${prompt}"
        fi
        read -r input_val

        if [ -z "$input_val" ]; then
            eval $__resultvar="DEFAULT"
            return 0
        fi

        if [[ ! "$input_val" =~ ^[0-9]+$ ]]; then
            error_msg="错误：请输入有效的数字！"
            echo -ne "\033[1A"
            continue
        fi

        if [ "$input_val" -lt "$min" ] || [ "$input_val" -gt "$max" ]; then
            error_msg="错误：数值必须在 ${min}-${max} 之间！"
            echo -ne "\033[1A"
            continue
        fi

        eval $__resultvar="'$input_val'"
        break
    done
}

get_status() {
    SWAP_TOTAL=$(free -m | grep Swap | awk '{print $2}')
    if [ "$SWAP_TOTAL" -eq 0 ]; then
        STATUS_SWAP="${RED}未启用${PLAIN}"
    else
        STATUS_SWAP="${GREEN}已启用 (${SWAP_TOTAL}MB)${PLAIN}"
    fi

    SWAPPINESS=$(sysctl -n vm.swappiness 2>/dev/null)
    if [ -z "$SWAPPINESS" ]; then
        SWAPPINESS=$(cat /proc/sys/vm/swappiness 2>/dev/null)
    fi
    
    if [ -z "$SWAPPINESS" ]; then
        SWAPPINESS="${RED}读取失败${PLAIN}"
    fi
}

add_swap() {
    clear
    echo -e "${BLUE}正在创建 Swap 分区...${PLAIN}"
    echo ""

    local swap_size
    get_valid_int "请输入 Swap 大小 (MB) [回车默认 1024]: " swap_size 1 65536
    [ "$swap_size" == "DEFAULT" ] && swap_size=1024

    if [ -f /swapfile ]; then
        echo -e "${YELLOW}发现旧 Swap，正在清理...${PLAIN}"
        swapoff /swapfile 2>/dev/null
        rm -f /swapfile
    fi

    echo -e "${BLUE}正在分配空间 (大小: ${swap_size}MB)...${PLAIN}"
    fallocate -l ${swap_size}M /swapfile
    chmod 600 /swapfile
    mkswap /swapfile
    swapon /swapfile

    if ! grep -q "/swapfile" /etc/fstab; then
        echo '/swapfile none swap sw 0 0' >> /etc/fstab
    fi

    if ! grep -q "vm.swappiness" /etc/sysctl.conf; then
        echo "vm.swappiness = 10" >> /etc/sysctl.conf
        sysctl -w vm.swappiness=10 >/dev/null
        UI_MESSAGE="${GREEN}已成功创建 ${swap_size}MB Swap，Swappiness 已自动优化为 10。${PLAIN}"
    else
        current_swappiness=$(sysctl -n vm.swappiness 2>/dev/null)
        UI_MESSAGE="${GREEN}已成功创建 ${swap_size}MB Swap，当前 Swappiness 保持为 ${current_swappiness}。${PLAIN}"
    fi

    read -n 1 -s -r -p "按任意键返回主菜单..."
    clear; printf '\033[3J'
}

set_swappiness() {
    clear
    echo -e "${BLUE}调整 Swappiness 亲和度${PLAIN}"
    echo -e "当前值: ${YELLOW}${SWAPPINESS}${PLAIN}"
    echo -e "说明: 值越小 (0-10)，越倾向于使用物理内存；值越大 (60-100)，越倾向于使用硬盘交换。"
    echo -e "------------------------------------------------"
    echo ""

    local new_val
    get_valid_int "请输入新的值 [0-100] (回车默认 60): " new_val 0 100
    [ "$new_val" == "DEFAULT" ] && new_val=60

    sysctl -w vm.swappiness=$new_val >/dev/null
    if grep -q "vm.swappiness" /etc/sysctl.conf; then
        sed -i "s/^vm.swappiness.*/vm.swappiness = $new_val/" /etc/sysctl.conf
    else
        echo "vm.swappiness = $new_val" >> /etc/sysctl.conf
    fi

    UI_MESSAGE="${GREEN}Swappiness 已修改为 ${YELLOW}${new_val}${GREEN}，已永久生效。${PLAIN}"
    clear; printf '\033[3J'
}

while true; do
    get_status
    tput cup 0 0

    echo -e "${BLUE}===================================================${PLAIN}\033[K"
    echo -e "${BLUE}           虚拟内存管理 (Swap Manager)            ${PLAIN}\033[K"
    echo -e "${BLUE}===================================================${PLAIN}\033[K"
    echo -e "  Swap 状态   : ${STATUS_SWAP}\033[K"
    echo -e "  Swappiness  : ${YELLOW}${SWAPPINESS}${PLAIN}\033[K"
    echo -e "---------------------------------------------------\033[K"
    echo -e "  1. 添加 / 修改 Swap\033[K"
    echo -e "  2. 关闭 / 删除 Swap\033[K"
    echo -e "---------------------------------------------------\033[K"
    echo -e "  3. 调整 Swappiness (性能优化)\033[K"
    echo -e "---------------------------------------------------\033[K"
    echo -e "  0. 退出\033[K"
    echo -e "===================================================\033[K"

    if [ -n "$UI_MESSAGE" ]; then
        echo -e "${YELLOW}当前操作${PLAIN}: ${UI_MESSAGE}\033[K"
        UI_MESSAGE=""
    else
        echo -e "${YELLOW}当前操作${PLAIN}: ${GRAY}等待输入...${PLAIN}\033[K"
    fi
    echo -e "===================================================\033[K"

    tput ed

    error_msg=""
    while true; do
        if [ -n "$error_msg" ]; then
            echo -ne "\r\033[K${RED}${error_msg}${PLAIN} 请输入选项 [0-3]: "
        else
            echo -ne "\r\033[K请输入选项 [0-3]: "
        fi
        read -r choice
        case "$choice" in
            1|2|3|0)
                break
                ;;
            *)
                error_msg="输入无效！"
                echo -ne "\033[1A"
                ;;
        esac
    done

    case "$choice" in
        1) add_swap ;;
        2)
            swapoff /swapfile 2>/dev/null
            rm -f /swapfile
            sed -i '/\/swapfile/d' /etc/fstab
            UI_MESSAGE="${YELLOW}Swap 已关闭并删除。${PLAIN}"
            ;;
        3) set_swappiness ;;
        0) clear; exit 0 ;;
    esac
done
