#!/bin/bash

# ─────────────────────────────────────────────
#  install.sh — 主安装入口 (全自动版)
# ─────────────────────────────────────────────

BASE_DIR=$(cd "$(dirname "$0")" && pwd)

# ─── 1. 严格顺序加载工具库 ───
if [ -f "$BASE_DIR/lib/utils.sh" ]; then
    source "$BASE_DIR/lib/utils.sh"
else
    echo "Error: Cannot find lib/utils.sh"
    exit 1
fi

if [ -f "$BASE_DIR/core/1_env.sh" ]; then
    source "$BASE_DIR/core/1_env.sh"
else
    echo "Error: Cannot find core/1_env.sh"
    exit 1
fi

# ─── 2. 启动流程 ───
print_banner

if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}Error: 请使用 root 运行！${PLAIN}"
    exit 1
fi

lock_acquire || exit 1
confirm_installation

# ─── 3. 执行分步任务 ───
pre_flight_check
check_net_stack
setup_base_env

source "$BASE_DIR/core/2_install.sh"
core_install

source "$BASE_DIR/core/3_system.sh"
setup_firewall_and_security

source "$BASE_DIR/core/4_config.sh"
core_config

# ─── 4. 部署与启动 ───
echo -e "\n${CYAN}>>> 正在部署工具并启动服务...${PLAIN}"
BIN_DIR="/usr/local/bin"
for script in "$BASE_DIR/tools"/*.sh; do
    [ -f "$script" ] || continue
    filename=$(basename "$script" .sh)
    cp "$script" "$BIN_DIR/$filename"
    chmod +x "$BIN_DIR/$filename"
done

systemctl daemon-reload
systemctl enable xray
if ! systemctl restart xray; then
    # 权限补救逻辑
    mkdir -p /var/log/xray/
    chown -R nobody:nogroup /var/log/xray/ 2>/dev/null || chown -R nobody:nobody /var/log/xray/
    chmod -R 755 /var/log/xray/
    systemctl restart xray
fi

# ─── 5. 安装完成展示信息 ───
if [ -f "$BIN_DIR/info" ]; then
    bash "$BIN_DIR/info"
fi
