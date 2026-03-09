#!/bin/bash

# ─────────────────────────────────────────────
#  install.sh — 主安装入口 (全自动修复版)
# ─────────────────────────────────────────────

BASE_DIR=$(cd "$(dirname "$0")" && pwd)

# ─── 基础工具加载 (必须最先加载) ─────────────
if [ -f "$BASE_DIR/lib/utils.sh" ]; then
    source "$BASE_DIR/lib/utils.sh"
else
    echo "Error: lib/utils.sh not found!"
    exit 1
fi

# ─── 预检与交互 ──────────────────────────────
# 修正：确保 print_banner 在 utils.sh 中定义
print_banner

if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}Error: 请使用 root 运行！${PLAIN}"
    exit 1
fi

if ! lock_acquire; then
    echo -e "${RED}脚本已在运行！${PLAIN}"
    exit 1
fi

# 修正：confirm_installation 现在是自动跳过模式
confirm_installation

# ─── 1. 环境准备 ─────────────────────────────
# 确保 1_env.sh 语法正确
if [ -f "$BASE_DIR/core/1_env.sh" ]; then
    source "$BASE_DIR/core/1_env.sh"
else
    echo "Error: core/1_env.sh not found!"
    exit 1
fi

pre_flight_check
check_net_stack
setup_base_env

# ─── 2. 核心安装 ─────────────────────────────
source "$BASE_DIR/core/2_install.sh"
core_install

# ─── 3. 系统配置 ─────────────────────────────
source "$BASE_DIR/core/3_system.sh"
setup_firewall_and_security

# ─── 4. 生成配置 ─────────────────────────────
source "$BASE_DIR/core/4_config.sh"
core_config

# ─── 5. 部署管理工具 ─────────────────────────
echo -e "\n${CYAN}>>> 5. 正在部署管理脚本...${PLAIN}"
TOOLS_DIR="$BASE_DIR/tools"
BIN_DIR="/usr/local/bin"

if [ -d "$TOOLS_DIR" ]; then
    for script in "$TOOLS_DIR"/*.sh; do
        [ -f "$script" ] || continue
        filename=$(basename "$script" .sh)
        cp "$script" "$BIN_DIR/$filename"
        chmod +x "$BIN_DIR/$filename"
        echo -e "${OK} 部署命令: ${GREEN}${filename}${PLAIN}"
    done
fi

# ─── 6. 启动服务 (status=23 修复逻辑) ──────────
echo -e "\n${CYAN}>>> 6. 正在启动服务...${PLAIN}"
systemctl daemon-reload
systemctl enable xray
if ! systemctl restart xray; then
    echo -e "${WARN} 启动失败，执行权限自动修复..."
    mkdir -p /var/log/xray/
    chown -R nobody:nogroup /var/log/xray/ 2>/dev/null || chown -R nobody:nobody /var/log/xray/
    chmod -R 755 /var/log/xray/
    systemctl daemon-reload
    systemctl restart xray
fi

if ! systemctl is-active --quiet xray; then
    echo -e "\n${RED}Error: Xray 启动失败！${PLAIN}"
    exit 1
fi

# ─── 7. 安装完成 ─────────────────────────
echo -e "\n${GREEN}=====================================================================${PLAIN}"
echo -e "${GREEN} 安装完成！${PLAIN}"
echo -e "${GREEN}=====================================================================${PLAIN}"

if [ -f "$BIN_DIR/info" ]; then
    bash "$BIN_DIR/info"
fi
