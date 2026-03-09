#!/bin/bash

# ─────────────────────────────────────────────
#  3_system.sh — 安全与防火墙配置及网络优化
# ─────────────────────────────────────────────

# ─── 随机可用端口获取 ────────────────────────
get_random_port() {
    local port
    local max_attempts=100
    local attempt=0

    while [ $attempt -lt $max_attempts ]; do
        port=$(shuf -i 10000-65535 -n 1)
        if ! lsof -i:"$port" -P -n >/dev/null 2>&1; then
            echo "$port"
            return 0
        fi
        ((attempt++))
    done

    echo -e "${ERR} 无法在 10000-65535 范围内找到可用端口，请检查系统端口占用情况。" >&2
    return 1
}

# ─── 防火墙规则添加工具 ──────────────────────
_add_fw_rule() {
    local port=$1
    local v4=$2
    local v6=$3

    if ! command -v iptables >/dev/null 2>&1; then
        echo -e "${WARN} 未检测到 iptables，跳过端口 $port 的防火墙规则配置。请手动放行该端口。"
        return 1
    fi

    if [ "$v4" = true ]; then
        iptables  -C INPUT -p tcp --dport "$port" -j ACCEPT 2>/dev/null || iptables  -A INPUT -p tcp --dport "$port" -j ACCEPT
        iptables  -C INPUT -p udp --dport "$port" -j ACCEPT 2>/dev/null || iptables  -A INPUT -p udp --dport "$port" -j ACCEPT
    fi

    if [ "$v6" = true ] && [ -f /proc/net/if_inet6 ]; then
        ip6tables -C INPUT -p tcp --dport "$port" -j ACCEPT 2>/dev/null || ip6tables -A INPUT -p tcp --dport "$port" -j ACCEPT
        ip6tables -C INPUT -p udp --dport "$port" -j ACCEPT 2>/dev/null || ip6tables -A INPUT -p udp --dport "$port" -j ACCEPT
    fi
}

# ─── 防火墙与安全配置入口 ────────────────────
setup_firewall_and_security() {
    echo -e "\n${CYAN}--- 3. 端口与安全 (Security) ---${PLAIN}"

    # ─── 端口分配 ────────────────────────────
    local current_ssh_port
    current_ssh_port=$(grep "^Port" /etc/ssh/sshd_config | head -n 1 | awk '{print $2}' | tr -d '\r')
    SSH_PORT=${current_ssh_port:-22}

    while true; do
        PORT_VISION=$(get_random_port) || exit 1
        [ "$PORT_VISION" != "$SSH_PORT" ] && break
    done

    while true; do
        PORT_XHTTP=$(get_random_port) || exit 1
        [ "$PORT_XHTTP" != "$PORT_VISION" ] && [ "$PORT_XHTTP" != "$SSH_PORT" ] && break
    done

    echo -e "${OK} SSH    端口 : ${GREEN}${SSH_PORT}${PLAIN}"
    echo -e "${OK} Vision 端口 : ${GREEN}${PORT_VISION}${PLAIN}"
    echo -e "${OK} XHTTP  端口 : ${GREEN}${PORT_XHTTP}${PLAIN}"

    # ─── 默认启用 BBR + CAKE 优化 ───
    # 自动检测并应用最优队列调度算法
    echo -e "${INFO} 正在优化网络内核参数 (BBR + CAKE)..."
    
    # 检查内核模块支持情况 (CAKE 通常需要内核 4.19+)
    if modprobe sch_cake >/dev/null 2>&1; then
        local qdisc="cake"
    else
        local qdisc="fq" # 若不支持 CAKE 则回退到 FQ
    fi

    cat > /etc/sysctl.d/99-xray-bbr.conf <<EOF
# 启用 BBR 拥塞控制与 FQ/CAKE 队列
net.core.default_qdisc = $qdisc
net.ipv4.tcp_congestion_control = bbr

# 基础网络性能加固
fs.file-max = 1000000
net.ipv4.ip_local_port_range = 1024 65535
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_fin_timeout = 15
net.ipv4.tcp_keepalive_time = 600
net.ipv4.tcp_fastopen = 3
net.ipv4.tcp_mtu_probing = 1
EOF
    sysctl -p /etc/sysctl.d/99-xray-bbr.conf >/dev/null 2>&1
    echo -e "${OK} 网络优化已应用: ${GREEN}BBR + $qdisc${PLAIN}"

    # ─── Fail2ban 配置 ───────────────────────
    cat > /etc/fail2ban/jail.local <<EOF

# ─── 基础设置 ───
bantime = 1d
findtime = 1d
maxretry = 3

# ─── 递增封禁 ───
bantime.increment = true
bantime.factor = 1
bantime.maxtime = 5w

# ─── 系统设置 ───
backend = systemd
mode = normal

[sshd]
enabled = true
port = $SSH_PORT

[DEFAULT]
ignoreip = 127.0.0.1/8 ::1
EOF
    # ─── 重启 Fail2ban 服务 ───
    systemctl unmask  fail2ban >/dev/null 2>&1
    systemctl enable  fail2ban >/dev/null 2>&1
    systemctl restart fail2ban >/dev/null 2>&1
    echo -e "${OK} Fail2ban 已启用 (默认策略: 递增封禁)"

    # ─── 防火墙规则写入 & 持久化 ─────────────
    _add_fw_rule "$SSH_PORT"    "$HAS_V4" "$HAS_V6"
    _add_fw_rule "$PORT_VISION" "$HAS_V4" "$HAS_V6"
    _add_fw_rule "$PORT_XHTTP"  "$HAS_V4" "$HAS_V6"

    netfilter-persistent save >/dev/null 2>&1
    echo -e "${OK} 防火墙规则已持久化保存"
}
