#!/bin/bash

RED="\033[31m"
GREEN="\033[32m"
YELLOW="\033[33m"
BLUE="\033[36m"
GRAY="\033[90m"
PLAIN="\033[0m"

UI_MESSAGE=""


if [ "$EUID" -ne 0 ]; then echo -e "${RED}请使用 sudo 运行此脚本！${PLAIN}"; exit 1; fi

XRAY_BIN="/usr/local/bin/xray"

update_core() {
    clear
    echo -e "${BLUE}>>> 正在请求官方脚本更新 Xray 核心...${PLAIN}"

    if bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install --without-geodata; then
        systemctl restart xray
        echo -e "\n${GREEN}>>> 核心更新成功！${PLAIN}"
        "$XRAY_BIN" version | head -n 1
    else
        echo -e "\n${RED}>>> 核心更新失败，请检查网络连接。${PLAIN}"
    fi

    if bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install --without-geodata; then
        systemctl restart xray
        echo -e "\n${GREEN}>>> 核心更新成功！${PLAIN}"
        "$XRAY_BIN" version | head -n 1
        UI_MESSAGE="${GREEN}核心更新成功！${PLAIN}"   # ← 新增
    else
        echo -e "\n${RED}>>> 核心更新失败，请检查网络连接。${PLAIN}"
        UI_MESSAGE="${RED}核心更新失败，请检查网络连接。${PLAIN}"   # ← 新增
    fi

    read -n 1 -s -r -p "按任意键返回主菜单..."
    clear; printf '\033[3J'
}

update_geodata() {
    clear
    echo -e "${BLUE}>>> 正在手动更新 GeoData 路由规则库...${PLAIN}"

    local share_dir="/usr/local/share/xray"
    local urls=(
        "https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geoip.dat"
        "https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geosite.dat"
    )

    local tmp_ip=$(mktemp)
    local tmp_site=$(mktemp)
    local max_retries=3
    local attempt=1
    local success=false

    while [ $attempt -le $max_retries ]; do
        echo -e "   [-] 直连拉取 GeoData (尝试 $attempt/$max_retries) ..."

        curl -kL --retry 3 -o "$tmp_ip" "${urls[0]}"
        curl -kL --retry 3 -o "$tmp_site" "${urls[1]}"

        local size_ip=$(du -k "$tmp_ip" | awk '{print $1}')
        local size_site=$(du -k "$tmp_site" | awk '{print $1}')

        if [ -n "$size_ip" ] && [ "$size_ip" -gt 1000 ] && [ -n "$size_site" ] && [ "$size_site" -gt 1000 ]; then
            success=true
            break
        else
            echo -e "   [WARN] 第 $attempt 次拉取失败 (文件损坏或过小)，准备重试..."
            sleep 2
            attempt=$((attempt + 1))
        fi
    done

    if [ "$success" = true ]; then
        echo -e "校验通过，正在应用新规则..."
        mv -f "$tmp_ip" "$share_dir/geoip.dat"
        mv -f "$tmp_site" "$share_dir/geosite.dat"
        chmod 644 "$share_dir"/*.dat
        systemctl restart xray
        echo -e "\n${GREEN}>>> GeoData 更新完成！服务已重启以加载新规则。${PLAIN}"
        UI_MESSAGE="${GREEN}GeoData 更新完成！服务已重启以加载新规则。${PLAIN}"   # ← 新增
    else
        echo -e "${YELLOW}已自动拦截损坏的规则库，当前 Xray 服务不受影响。${PLAIN}"
        UI_MESSAGE="${RED}更新失败：连续 ${max_retries} 次拉取均异常，当前服务不受影响。${PLAIN}"   # ← 新增
        rm -f "$tmp_ip" "$tmp_site"
    fi

    read -n 1 -s -r -p "按任意键返回主菜单..."
    clear; printf '\033[3J'
}

while true; do
    tput cup 0 0

    if [ -x "$XRAY_BIN" ]; then
        LOCAL_VER=$("$XRAY_BIN" version | head -n 1 | awk '{print $2}')
    else
        LOCAL_VER="${RED}未安装${PLAIN}"
    fi

    echo -e "${BLUE}===================================================${PLAIN}\033[K"
    echo -e "${BLUE}           Xray 更新管理 (Update Manager)         ${PLAIN}\033[K"
    echo -e "${BLUE}===================================================${PLAIN}\033[K"
    echo -e "  当前核心版本: ${GREEN}${LOCAL_VER}${PLAIN}\033[K"
    echo -e "---------------------------------------------------\033[K"
    echo -e "  1. 升级 Xray 核心至最新版\033[K"
    echo -e "  2. 手动更新 GeoData 路由规则库\033[K"
    echo -e "---------------------------------------------------\033[K"
    echo -e "  0. 退出 (Exit)\033[K"
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
            echo -ne "\r\033[K${RED}${error_msg}${PLAIN} 请输入选项 [0-2]: "
        else
            echo -ne "\r\033[K请输入选项 [0-2]: "
        fi
        read -r choice
        case "$choice" in
            1|2|0)
                break
                ;;
            *)
                error_msg="输入无效！"
                echo -ne "\033[1A"
                ;;
        esac
    done

    case "$choice" in
        1) update_core ;;
        2) update_geodata ;;
        0) clear; exit 0 ;;
    esac
done
