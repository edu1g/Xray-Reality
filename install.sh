#!/bin/bash

# ─────────────────────────────────────────────
#  install.sh — 主安装入口 (已集成 status=23 启动修复)
#
#  模块加载顺序与变量流转：
#    utils.sh      →  定义 _LOCK_FILE, execute_task, 颜色变量等基础工具
#    1_env.sh      →  输出 ARCH, HAS_V4, HAS_V6, CURL_OPT, DOMAIN_STRATEGY
#    2_install.sh  →  消费无显式变量，结果体现于文件系统
#    3_system.sh   →  消费 HAS_V4, HAS_V6；输出 SSH_PORT, PORT_VISION, PORT_XHTTP
#    4_config.sh   →  消费 PORT_VISION, PORT_XHTTP, DOMAIN_STRATEGY
#                     输出 UUID, PUBLIC_KEY, PRIVATE_KEY, SHORT_ID, SNI_HOST, XHTTP_PATH
# ─────────────────────────────────────────────

BASE_DIR=$(cd "$(dirname "$0")" && pwd)

# ─── 基础工具加载 ────────────────────────────
if [ -f "$BASE_DIR/lib/utils.sh" ]; then
    source "$BASE_DIR/lib/utils.sh"
else
    echo "Error: lib/utils.sh not found!"
    exit 1
fi

# ─── 预检与交互 ──────────────────────────────
print_banner

if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}Error: 请使用 root 运行！${PLAIN}"
    exit 1
fi

if ! lock_acquire; then
    echo -e "${RED}脚本已在运行！${PLAIN}"
    exit 1
fi

confirm_installation

# ─── 1. 环境准备 ─────────────────────────────
source "$BASE_DIR/core/1_env.sh"
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
    count=$(find "$TOOLS_DIR" -maxdepth 1 -name "*.sh" | wc -l)
    if [ "$count" -gt 0 ]; then
        for script in "$TOOLS_DIR"/*.sh; do
            [ -f "$script" ] || continue
            filename=$(basename "$script" .sh)
            cp "$script" "$BIN_DIR/$filename"
            chmod +x "$BIN_DIR/$filename"
            echo -e "${OK} 部署命令: ${GREEN}${filename}${PLAIN}"
        done
    else
        echo -e "${WARN} tools 目录为空，跳过部署。"
    fi
else
    echo -e "${ERR} tools 目录缺失，请检查项目完整性。"
fi

# ─── 6. 启动服务 ─────────────────────────────
echo -e "\n${CYAN}>>> 6. 正在启动服务...${PLAIN}"

# 解决 status=23 的关键点：启动前确保环境彻底重载
systemctl daemon-reload
systemctl enable xray

# 尝试启动并增加自动纠错逻辑
if ! systemctl restart xray; then
    echo -e "${WARN} 首次启动失败，正在尝试权限修复与二次重载..."
    # 强制初始化日志目录权限 (防止 status=23)
    mkdir -p /var/log/xray/
    if getent group nogroup > /dev/null; then
        chown -R nobody:nogroup /var/log/xray/
    else
        chown -R nobody:nobody /var/log/xray/
    fi
    chmod -R 755 /var/log/xray/
    
    # 二次尝试
    systemctl daemon-reload
    systemctl restart xray
fi

# 最终状态校验
if ! systemctl is-active --quiet xray; then
    echo -e "\n${RED}Error: Xray 服务启动失败！${PLAIN}"
    echo -e "请执行 'journalctl -u xray -n 20 --no-pager' 查看具体错误原因。"
    exit 1
fi

# ─── 7. 安装完成 ─────────────────────────
echo -e "\n${GREEN}=====================================================================${PLAIN}"
echo -e "${GREEN} 安装完成！${PLAIN}"
echo -e "${GREEN}=====================================================================${PLAIN}"

if [ -f "$BIN_DIR/info" ]; then
    bash "$BIN_DIR/info"
fi
