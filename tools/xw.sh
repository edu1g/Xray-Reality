#!/bin/bash

# ─────────────────────────────────────────────
#  Xray WARP 分流管理器 (界面与逻辑深度重构版)
# ─────────────────────────────────────────────

RED="\033[31m"; GREEN="\033[32m"; YELLOW="\033[33m"; CYAN="\033[36m"; GRAY="\033[90m"; PLAIN="\033[0m"

CONFIG_FILE="/usr/local/etc/xray/config.json"
WARP_PORT=40000

UI_MESSAGE=""

# ─── 环境检查 ────────────────────────────────
if [ "$EUID" -ne 0 ]; then echo -e "${RED}请使用 sudo 运行此脚本！${PLAIN}"; exit 1; fi
if ! command -v jq &> /dev/null; then apt-get install -y jq >/dev/null 2>&1; fi

# ─── 数据读取 ────────────────────────────────
get_warp_ip() {
    local res
    res=$(curl -s4m 2 --proxy socks5h://127.0.0.1:$WARP_PORT https://www.cloudflare.com/cdn-cgi/trace | grep -E "ip=|loc=" | awk -F= '{print $2}' | xargs)
    if [ -n "$res" ]; then echo -e "${GREEN}${res}${PLAIN}"; else echo -e "${RED}无法获取${PLAIN}"; fi
}

get_main_ip() {
    local res
    res=$(curl -s4m 2 https://www.cloudflare.com/cdn-cgi/trace | grep -E "ip=|loc=" | awk -F= '{print $2}' | xargs)
    echo -e "${CYAN}${res}${PLAIN}"
}

_get_domains_by_tag() {
    local tag=$1
    local res=$(jq -r --arg t "$tag" '.routing.rules[] | select(.outboundTag==$t) | .domain[]' "$CONFIG_FILE" 2>/dev/null | xargs)
    [ -n "$res" ] && echo -e "${YELLOW}${res}${PLAIN}" || echo -e "${GRAY}未配置${PLAIN}"
}

check_warp_socket() {
    (echo > /dev/tcp/127.0.0.1/$WARP_PORT) >/dev/null 2>&1
}

check_xray_outbound() {
    jq -e '.outbounds[] | select(.tag=="warp_proxy")' "$CONFIG_FILE" >/dev/null 2>&1
}

# ─── 核心功能实现 ─────────────────────────────

install_warp() {
    clear
    echo -e "\n${CYAN}正在全自动安装 WARP (Socks5 模式 - 端口 $WARP_PORT)...${PLAIN}"
    printf "2\n\n" | bash <(curl -sL https://gitlab.com/fscarmen/warp/-/raw/main/menu.sh) c
    if ! check_xray_outbound; then
        local out_obj='{"tag": "warp_proxy", "protocol": "socks", "settings": {"servers": [{"address": "127.0.0.1", "port": '$WARP_PORT'}]}}'
        jq --argjson obj "$out_obj" '.outbounds += [$obj]' "$CONFIG_FILE" > "${CONFIG_FILE}.tmp" && mv "${CONFIG_FILE}.tmp" "$CONFIG_FILE"
    fi
    systemctl restart xray >/dev/null 2>&1
    UI_MESSAGE="${GREEN}WARP 安装及 Xray 接口配置完成。${PLAIN}"
}

uninstall_warp() {
    bash <(curl -sL https://gitlab.com/fscarmen/warp/-/raw/main/menu.sh) u
    jq 'del(.outbounds[] | select(.tag=="warp_proxy")) | del(.routing.rules[] | select(.outboundTag=="warp_proxy"))' "$CONFIG_FILE" > "${CONFIG_FILE}.tmp" && mv "${CONFIG_FILE}.tmp" "$CONFIG_FILE"
    systemctl restart xray >/dev/null 2>&1
    UI_MESSAGE="${YELLOW}WARP 已卸载并清理分流规则。${PLAIN}"
}

rotate_ip() { bash <(curl -sL https://gitlab.com/fscarmen/warp/-/raw/main/menu.sh) i; UI_MESSAGE="${GREEN}出口 IP 刷取指令已执行。${PLAIN}"; }
change_region() {
    echo -ne "${YELLOW}请输入目标地域代码 (如 hk, sg, jp, us): ${PLAIN}"
    read -r region
    [ -n "$region" ] && bash <(curl -sL https://gitlab.com/fscarmen/warp/-/raw/main/menu.sh) e "$region"
    UI_MESSAGE="${GREEN}地域切换指令已发送。${PLAIN}"
}

manage_domain_rule() {
    local target_tag=$1
    local desc=$2
    echo -ne "${YELLOW}请输入要操作的域名或 GeoSite (例如 geosite:google): ${PLAIN}"
    read -r input_domain
    [ -z "$input_domain" ] && return

    tmp=$(mktemp)
    # 步骤1: 先移除该域名在所有规则中的存在
    jq --arg d "$input_domain" '
        .routing.rules |= map(
            if .domain then .domain |= map(select(. != $d)) else . end
        ) | .routing.rules |= map(select(.domain == null or (.domain | length > 0)))
    ' "$CONFIG_FILE" > "$tmp"

    # 步骤2: 检查是否需要添加（若之前不在目标 tag 下则添加）
    if ! jq -e --arg d "$input_domain" --arg t "$target_tag" '.routing.rules[] | select(.outboundTag==$t and (.domain // [] | contains([$d])))' "$CONFIG_FILE" >/dev/null 2>&1; then
        # 构造新规则并强制排序：Direct 规则置顶，Proxy 规则随后
        local new_rule="{\"type\": \"field\", \"domain\": [\"$input_domain\"], \"outboundTag\": \"$target_tag\"}"
        jq --argjson rule "$new_rule" '.routing.rules += [$rule]' "$tmp" > "${tmp}.new"
        # 核心逻辑：重构 rules 数组顺序，确保 outboundTag 为 direct 的在前
        jq '(.routing.rules | map(select(.outboundTag == "direct"))) + (.routing.rules | map(select(.outboundTag != "direct")))' "${tmp}.new" > "$tmp"
        rm -f "${tmp}.new"
        UI_MESSAGE="${GREEN}已添加 ${desc}: $input_domain${PLAIN}"
    else
        UI_MESSAGE="${YELLOW}已移除 ${desc}: $input_domain${PLAIN}"
    fi
    
    mv "$tmp" "$CONFIG_FILE"
    systemctl restart xray >/dev/null 2>&1
    rm -f "$tmp"
}

# ─── 菜单界面 ────────────────────────────────
show_menu() {
    clear
    check_warp_socket && STATUS_SOCK="${GREEN}● 运行中${PLAIN}" || STATUS_SOCK="${RED}● 未运行${PLAIN}"
    check_xray_outbound && STATUS_XRAY="${GREEN}● 已连接${PLAIN}" || STATUS_XRAY="${RED}● 未连接${PLAIN}"

    echo -e "${CYAN}===================================================${PLAIN}"
    echo -e "${CYAN}           WARP 分流管理面板 (Xray Warp)          ${PLAIN}"
    echo -e "${CYAN}===================================================${PLAIN}"
    echo -e " Warp 服务 : ${STATUS_SOCK}"
    echo -e " Xray 接口 : ${STATUS_XRAY}"
    echo -e " Warp IP   : $(get_warp_ip)"
    echo -e " 默认出口  : $(get_main_ip)"
    echo -e " 直连域名  : $(_get_domains_by_tag 'direct')"
    echo -e " WARP 域名 : $(_get_domains_by_tag 'warp_proxy')"
    echo -e "---------------------------------------------------"
    echo -e " 1. 安装/重装 WARP    ${GRAY}(自动配置 Socks5 端口 40000)${PLAIN}"
    echo -e " 2. 卸载 WARP         ${GRAY}(清理分流规则)${PLAIN}"
    echo -e " 3. 更换出口 IP       ${GRAY}(刷取新的 IP )${PLAIN}"
    echo -e " 4. 更换出口地域      ${GRAY}(指定地域，如 hk, sg, jp, us)${PLAIN}"
    echo -e " 5. 添加/删除 直连分流 ${GRAY}(油管无广告)${PLAIN}"
    echo -e " 6. 添加/删除 WARP 分流 ${GRAY}(谷歌无内陆)${PLAIN}"
    echo -e "---------------------------------------------------"
    echo -e " 0. 退出 (Exit)"
    echo -e "==================================================="

    if [ -n "$UI_MESSAGE" ]; then
        echo -e "${YELLOW}提示: ${UI_MESSAGE}${PLAIN}"
        UI_MESSAGE=""
    fi
}

# ─── 主循环 ──────────────────────────────────
while true; do
    show_menu
    read -r -p "请输入选项 [0-6]: " choice
    case "$choice" in
        1) install_warp ;;
        2) uninstall_warp ;;
        3) rotate_ip ;;
        4) change_region ;;
        5) manage_domain_rule "direct" "直连分流" ;;
        6) manage_domain_rule "warp_proxy" "WARP 分流" ;;
        0) exit 0 ;;
        *) UI_MESSAGE="${RED}无效选项${PLAIN}" ;;
    esac
done
