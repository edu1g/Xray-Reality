#!/bin/bash

# ─────────────────────────────────────────────
#  Xray 一键卸载脚本
# ─────────────────────────────────────────────

RED="\033[31m"; GREEN="\033[32m"; YELLOW="\033[33m"; CYAN="\033[36m"; GRAY="\033[90m"; PLAIN="\033[0m"

CONFIG_FILE="/usr/local/etc/xray/config.json"
SUMMARY=()

# ─── 环境检查 ────────────────────────────────
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}Error: 请使用 sudo 或 root 用户运行此脚本！${PLAIN}"
    exit 1
fi

# ─── 卸载确认 ────────────────────────────────
clear
echo -e "${RED}=============================================================${PLAIN}"
echo -e "${RED}               Xray 一键卸载 (Uninstall Xray)               ${PLAIN}"
echo -e "${RED}=============================================================${PLAIN}"
echo -e "${YELLOW}警告：第一阶段将执行 Xray 核心及面板组件的彻底清理。${PLAIN}"
echo -e "  1. 停止并移除 Xray 服务及其配置"
echo -e "  2. 智能清理当初为您开放的防火墙随机端口"
echo -e "  3. 删除所有管理快捷指令 (info, user 等全部脚本)"
echo -e "  4. 清理 GeoData 定时更新任务与 Systemd 覆写残留"
echo -e "${RED}=============================================================${PLAIN}"
echo ""

while true; do
    read -p "确认要卸载 Xray 核心及应用组件吗？[y/n]: " key
    case "$key" in
        [yY])
            echo -e "\n${GREEN}>>> 操作已确认，开始应用层卸载...${PLAIN}"
            break
            ;;
        [nN])
            echo -e "\n${YELLOW}>>> 操作已取消。${PLAIN}"
            exit 0
            ;;
        *)
            echo -e "\033[1A\033[K${RED}错误：必须输入 y 或 n ${PLAIN}"
            ;;
    esac
done

# ─── 防火墙端口清理工具 ──────────────────────
_del_fw_iptables() {
    local port=$1
    iptables -D INPUT -p tcp --dport "$port" -j ACCEPT 2>/dev/null
    iptables -D INPUT -p udp --dport "$port" -j ACCEPT 2>/dev/null
    if [ -f /proc/net/if_inet6 ]; then
        ip6tables -D INPUT -p tcp --dport "$port" -j ACCEPT 2>/dev/null
        ip6tables -D INPUT -p udp --dport "$port" -j ACCEPT 2>/dev/null
    fi
    echo -e "   [OK] iptables 已关闭端口: $port"
}

_save_iptables() {
    if command -v netfilter-persistent &>/dev/null; then
        netfilter-persistent save >/dev/null 2>&1
    elif command -v iptables-save &>/dev/null; then
        iptables-save > /etc/iptables/rules.v4 2>/dev/null
        ip6tables-save > /etc/iptables/rules.v6 2>/dev/null
    fi
}

# ─── 防火墙端口清理 ──────────────────────────
echo -e "${GREEN}>>> 正在清理防火墙放行的端口...${PLAIN}"

if [ ! -f "$CONFIG_FILE" ]; then
    echo -e "   [WARN] 配置文件不存在，跳过端口清理。"
    SUMMARY+=("端口清理：跳过（配置文件不存在）")
elif ! command -v jq &>/dev/null; then
    echo -e "   [WARN] 未检测到 jq，无法解析配置文件，跳过端口清理。"
    echo -e "          如需手动清理，请执行：iptables -L INPUT --line-numbers"
    SUMMARY+=("端口清理：跳过（jq 未安装）")
else
    PORT_VISION=$(jq -r '.inbounds[] | select(.tag=="vision_node") | .port // empty' "$CONFIG_FILE" 2>/dev/null)
    PORT_XHTTP=$(jq -r '.inbounds[] | select(.tag=="xhttp_node") | .port // empty' "$CONFIG_FILE" 2>/dev/null)

    if command -v firewall-cmd &>/dev/null && systemctl is-active --quiet firewalld; then
        for port in "$PORT_VISION" "$PORT_XHTTP"; do
            [ -z "$port" ] && continue
            firewall-cmd --permanent --remove-port="${port}/tcp" >/dev/null 2>&1
            firewall-cmd --permanent --remove-port="${port}/udp" >/dev/null 2>&1
            echo -e "   [OK] firewalld 已标记移除端口: $port"
        done
        firewall-cmd --reload >/dev/null 2>&1
        echo -e "   [OK] firewalld 规则已重载"
    else
        [ -n "$PORT_VISION" ] && _del_fw_iptables "$PORT_VISION"
        [ -n "$PORT_XHTTP" ]  && _del_fw_iptables "$PORT_XHTTP"
        _save_iptables
    fi
    SUMMARY+=("端口清理：已完成（vision: ${PORT_VISION:-无}, xhttp: ${PORT_XHTTP:-无}）")
fi

# ─── 停止并移除 Xray 服务 ────────────────────
echo -e "${GREEN}>>> 正在停止并移除服务...${PLAIN}"
systemctl stop xray    >/dev/null 2>&1
systemctl disable xray >/dev/null 2>&1

rm -f /etc/systemd/system/xray.service
rm -f /lib/systemd/system/xray.service
rm -rf /etc/systemd/system/xray.service.d

if [ -d "/usr/local/etc/xray" ]; then
    rm -rf "/usr/local/etc/xray"
    echo -e "   [OK] 已删除配置目录 (/usr/local/etc/xray)"
fi

rm -f /usr/local/bin/xray
rm -rf /usr/local/share/xray
rm -rf /var/log/xray
echo -e "   [OK] 已删除核心程序、数据与日志"
SUMMARY+=("Xray 服务：已停止并移除")

# ─── 管理指令清理 ────────────────────────────
TOOLS=("user" "backup" "sniff" "info" "zone" "net" "bbr" "bt" "f2b" "ports" "sni" "swap" "xw" "updata" "remove" "uninstall")
echo -e "${GREEN}>>> 正在清理快捷指令...${PLAIN}"
for tool in "${TOOLS[@]}"; do
    rm -f "/usr/local/bin/$tool" 2>/dev/null
done
echo -e "   [OK] 已清理全部管理面板指令"
SUMMARY+=("管理指令：已全部清理")

# ─── 定时任务清理 ────────────────────────────
echo -e "${GREEN}>>> 正在清理定时任务...${PLAIN}"
if command -v crontab &>/dev/null; then
    existing_cron=$(crontab -l 2>/dev/null)
    if [ -n "$existing_cron" ]; then
        echo "$existing_cron" | grep -v "geoip.dat" | grep -v "geosite.dat" | crontab -
        echo -e "   [OK] 已清理 GeoData 定时更新任务"
        SUMMARY+=("定时任务：已清理")
    else
        echo -e "   [INFO] 无 crontab 条目，跳过。"
        SUMMARY+=("定时任务：无条目，跳过")
    fi
fi

rm -f /etc/needrestart/conf.d/99-xray-auto.conf 2>/dev/null

systemctl daemon-reload
if systemctl cat xray &>/dev/null; then
    systemctl reset-failed xray 2>/dev/null
fi

rm -rf /root/xray-install 2>/dev/null

# ─── 深度复原确认 ────────────────────────────
echo -e "\n${CYAN}=============================================================${PLAIN}"
echo -e "${CYAN}          第二阶段：系统环境深度复原 (Optional)              ${PLAIN}"
echo -e "${CYAN}=============================================================${PLAIN}"
echo -e "${YELLOW}检测到系统层面存在 Xray-Auto 的全局网络与性能优化痕迹。${PLAIN}"
echo -e "若您的服务器将用于建站或其他业务，保留它们(BBR/Swap/Fail2ban)是有益的。"
echo -e "如果需要彻底清除，您可以选择继续深度复原：\n"
echo -e "  - ${GRAY}删除虚拟内存${PLAIN} (/swapfile)"
echo -e "  - ${GRAY}移除 BBR 优化配置${PLAIN} (恢复系统默认网络队列)"
echo -e "  - ${GRAY}恢复网络优先级${PLAIN} (重置 IPv4/IPv6 双栈策略)"
echo -e "  - ${GRAY}卸载 WARP 客户端${PLAIN} (若已安装)"
echo -e "  - ${GRAY}清除 Fail2ban 配置${PLAIN} (恢复默认防爆破策略)"
echo -e "${CYAN}-------------------------------------------------------------${PLAIN}"

while true; do
    read -p "是否执行系统环境深度复原？[y/n]: " sys_key
    case "$sys_key" in
        [yY])
            echo -e "\n${GREEN}>>> 开始执行系统环境复原...${PLAIN}"

            # ─── Swap 清理 ───────────────────
            if [ -f /swapfile ]; then
                echo -e "   [-] 正在关闭并删除 Swap 分区..."
                swapoff /swapfile 2>/dev/null
                rm -f /swapfile
                sed -i '/\/swapfile/d' /etc/fstab
                SUMMARY+=("Swap：已删除 /swapfile")
            else
                SUMMARY+=("Swap：未检测到 /swapfile，跳过")
            fi
            sysctl -w vm.swappiness=60 >/dev/null 2>&1

            # ─── BBR 配置清理 ────────────────
            if [ -f /etc/sysctl.d/99-xray-bbr.conf ]; then
                echo -e "   [-] 正在移除 BBR 优化配置..."
                rm -f /etc/sysctl.d/99-xray-bbr.conf
                sysctl --system >/dev/null 2>&1
                SUMMARY+=("BBR：配置文件已移除，内核参数已重载")
            else
                SUMMARY+=("BBR：未检测到配置文件，跳过")
            fi

            # ─── 网络优先级复原 ──────────────
            echo -e "   [-] 正在恢复网络优先级与 IPv6 状态..."
            sed -i '/^precedence ::ffff:0:0\/96  100/d' /etc/gai.conf 2>/dev/null
            sysctl -w net.ipv6.conf.all.disable_ipv6=0     >/dev/null 2>&1
            sysctl -w net.ipv6.conf.default.disable_ipv6=0 >/dev/null 2>&1
            grep -rl "net.ipv6.conf.all.disable_ipv6" /etc/sysctl.d/ 2>/dev/null | while read -r f; do
                sed -i '/net.ipv6.conf.all.disable_ipv6/d' "$f"
                sed -i '/net.ipv6.conf.default.disable_ipv6/d' "$f"
            done
            sed -i '/net.ipv6.conf.all.disable_ipv6/d'     /etc/sysctl.conf 2>/dev/null
            sed -i '/net.ipv6.conf.default.disable_ipv6/d' /etc/sysctl.conf 2>/dev/null
            SUMMARY+=("网络优先级：已恢复 IPv6，已清理 gai.conf")

            # ─── WARP 卸载 ───────────────────
            warp_found=false
            if command -v warp &>/dev/null; then
                echo -e "   [-] 检测到 warp 脚本，正在卸载..."
                warp u >/dev/null 2>&1
                warp_found=true
                SUMMARY+=("WARP：已通过 warp 脚本卸载")
            fi
            if command -v warp-cli &>/dev/null; then
                echo -e "   [-] 检测到 warp-cli，正在卸载官方客户端..."
                if command -v apt-get &>/dev/null; then
                    apt-get remove -y cloudflare-warp >/dev/null 2>&1
                elif command -v yum &>/dev/null; then
                    yum remove -y cloudflare-warp >/dev/null 2>&1
                fi
                rm -rf /etc/cloudflare-warp 2>/dev/null
                warp_found=true
                SUMMARY+=("WARP：已通过包管理器卸载并清理残留配置")
            fi
            [ "$warp_found" = false ] && SUMMARY+=("WARP：未检测到安装，跳过")

            # ─── Fail2ban 配置清理 ───────────
            if [ -f /etc/fail2ban/jail.local ]; then
                echo -e "   [-] 正在移除自定义 Fail2ban 规则..."
                rm -f /etc/fail2ban/jail.local
                systemctl restart fail2ban >/dev/null 2>&1
                SUMMARY+=("Fail2ban：自定义规则已移除并重启服务")
            else
                SUMMARY+=("Fail2ban：未检测到自定义规则，跳过")
            fi

            echo -e "${GREEN}>>> 深度复原已完成。${PLAIN}"
            break
            ;;
        [nN])
            echo -e "\n${YELLOW}>>> 跳过深度复原，保留系统级优化。${PLAIN}"
            SUMMARY+=("深度复原：用户选择跳过")
            break
            ;;
        *)
            echo -e "\033[1A\033[K${RED}错误：必须输入 y 或 n ${PLAIN}"
            ;;
    esac
done

# ─── 执行摘要 ────────────────────────────────
echo -e "\n${CYAN}=============================================================${PLAIN}"
echo -e "${CYAN}                     操作执行摘要                           ${PLAIN}"
echo -e "${CYAN}=============================================================${PLAIN}"
for item in "${SUMMARY[@]}"; do
    echo -e "  ${GRAY}·${PLAIN} $item"
done

echo -e "\n${GREEN}=============================================================${PLAIN}"
echo -e "${GREEN}                卸载全部完成！(Done)                        ${PLAIN}"
echo -e "${GREEN}=============================================================${PLAIN}\n"
