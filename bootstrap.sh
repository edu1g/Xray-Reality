#!/bin/bash

# ─────────────────────────────────────────────
#  bootstrap.sh — 远程引导安装入口
# ─────────────────────────────────────────────

RED="\033[31m"; GREEN="\033[32m"; YELLOW="\033[33m"; CYAN="\033[36m"; PLAIN="\033[0m"

INSTALL_DIR="xray-install"
REPO_URL="https://github.com/edu1g/Xray-Reality.git"

# ─── 分支选择 ────────────────────────────────
TARGET_BRANCH="${VERSION:-${1:-main}}"
echo -e "${GREEN}>>> 准备安装分支/版本: ${YELLOW}${TARGET_BRANCH}${PLAIN}"

# ─── Root 检查 ───────────────────────────────
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}Error: 请使用 sudo 或 root 用户运行此脚本！${PLAIN}"
    exit 1
fi

# ─── 系统支持范围检查 ────────────────────────
if [ ! -f /etc/debian_version ]; then
    echo -e "${RED}Error: 本安装程序仅支持 Debian/Ubuntu 系统！${PLAIN}"
    echo -e "${YELLOW}当前系统不受支持，请更换后重试。${PLAIN}"
    exit 1
fi

# ─── 纯 IPv6 环境检测 & DNS64 配置 ──────────
if ! curl -s4k -m 3 https://1.1.1.1 >/dev/null 2>&1; then
    if curl -s6k -m 3 https://2606:4700:4700::1111 >/dev/null 2>&1; then
        echo -e "${YELLOW}检测到纯 IPv6 环境，正在配置 DNS64 (Trex) 以连接 GitHub 等 IPv4 资源...${PLAIN}"
        cp /etc/resolv.conf /etc/resolv.conf.bak 2>/dev/null
        printf 'nameserver 2a00:1098:2b::1\nnameserver 2a00:1098:2fac::1\n' > /etc/resolv.conf
    fi
fi

# ─── Git 安装检查 ────────────────────────────
if ! command -v git &>/dev/null; then
    echo -e "${YELLOW}检测到未安装 Git，正在自动安装...${PLAIN}"
    apt-get update -y && apt-get install -y git

    if ! command -v git &>/dev/null; then
        echo -e "${RED}Git 安装失败，请检查网络或源设置。${PLAIN}"
        exit 1
    fi
fi

# ─── 代码拉取 ────────────────────────────────
if [ -d "$INSTALL_DIR" ]; then
    echo -e "${YELLOW}清理旧安装目录...${PLAIN}"
    rm -rf "$INSTALL_DIR"
fi

echo -e "${GREEN}>>> 正在拉取代码...${PLAIN}"

if ! git clone -b "${TARGET_BRANCH}" --depth 1 "$REPO_URL" "$INSTALL_DIR"; then
    echo -e "${RED}代码拉取失败！${PLAIN}"
    echo -e "请检查分支名称 '${TARGET_BRANCH}' 是否存在，或检查网络连接。"
    exit 1
fi

echo -e "${GREEN}代码拉取成功！${PLAIN}"

# ─── 目录完整性校验 ──────────────────────────
if [ ! -f "$INSTALL_DIR/install.sh" ]; then
    echo -e "${RED}Error: 仓库结构异常，未找到 install.sh，请检查分支内容。${PLAIN}"
    exit 1
fi

# ─── 权限设置 & 移交执行 ─────────────────────
cd "$INSTALL_DIR" || exit 1

chmod +x install.sh
chmod +x core/*.sh  2>/dev/null
chmod +x lib/*.sh   2>/dev/null
chmod +x tools/*.sh 2>/dev/null

echo -e "${GREEN}>>> 启动安装程序...${PLAIN}"
echo ""

bash install.sh
