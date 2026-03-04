#!/bin/bash

RED="\033[31m"
GREEN="\033[32m"
YELLOW="\033[33m"
BLUE="\033[36m"
PLAIN="\033[0m"
GRAY="\033[90m"

UI_MESSAGE=""

CONFIG_FILE="/usr/local/etc/xray/config.json"
XRAY_BIN="/usr/local/bin/xray"

if ! command -v jq &> /dev/null; then echo -e "${RED}Error: 缺少 jq 组件。${PLAIN}"; exit 1; fi
if ! [ -x "$XRAY_BIN" ]; then echo -e "${RED}Error: 缺少 xray 核心。${PLAIN}"; exit 1; fi

_print_list() {
    echo -e "${BLUE}>>> 当前用户列表 (User List)${PLAIN}"
    echo -e "${GRAY}------------------------------------------------------------------${PLAIN}"
    printf "${YELLOW}%-5s %-25s %-40s${PLAIN}\n" "ID" "备注" "UUID"
    echo -e "${GRAY}------------------------------------------------------------------${PLAIN}"
    
    jq -r '.inbounds[0].settings.clients | to_entries[] | "\(.key) \(.value.email // "无备注") \(.value.id)"' "$CONFIG_FILE" | while read idx email uuid; do
        if [ "$idx" -eq 0 ]; then
            printf "${RED}%-5s %-23s %-40s${PLAIN}\n" "#" "$email" "$uuid"
        else
            printf "${GREEN}%-5s${PLAIN} %-23s %-40s\n" "$idx" "$email" "$uuid"
        fi
    done
    echo -e "${GRAY}------------------------------------------------------------------${PLAIN}"
}

_show_connection_info() {
    local target_uuid=$1
    local target_email=$2

    echo -e "\n${BLUE}>>> 正在获取连接信息...${PLAIN}"

    local PRIVATE_KEY=$(jq -r '.inbounds[0].streamSettings.realitySettings.privateKey' "$CONFIG_FILE")
    local SHORT_ID=$(jq -r '.inbounds[0].streamSettings.realitySettings.shortIds[0]' "$CONFIG_FILE")
    local SNI_HOST=$(jq -r '.inbounds[0].streamSettings.realitySettings.serverNames[0]' "$CONFIG_FILE")
    
    local PORT_VISION=$(jq -r '.inbounds[] | select(.tag=="vision_node") | .port' "$CONFIG_FILE")
    local PORT_XHTTP=$(jq -r '.inbounds[] | select(.tag=="xhttp_node") | .port' "$CONFIG_FILE")
    local XHTTP_PATH=$(jq -r '.inbounds[] | select(.tag=="xhttp_node") | .streamSettings.xhttpSettings.path' "$CONFIG_FILE")

    local PUBLIC_KEY=""
    if [ -n "$PRIVATE_KEY" ]; then
        local RAW_OUTPUT=$($XRAY_BIN x25519 -i "$PRIVATE_KEY")
        PUBLIC_KEY=$(echo "$RAW_OUTPUT" | grep -iE "Public|Password" | head -n 1 | awk -F':' '{print $2}' | tr -d ' \r\n')
    fi
    
    if [ -z "$PUBLIC_KEY" ]; then 
        echo -e "${RED}严重错误：无法计算公钥，请检查 config.json。${PLAIN}"
        return
    fi

    local IPV4=$(curl -s4m 1 https://api.ipify.org || echo "N/A")
    local IPV6=$(curl -s6m 1 https://api64.ipify.org || echo "N/A")

    echo -e "\n${YELLOW}=== 用户 [${target_email}] 连接配置 ===${PLAIN}"

    if [[ "$IPV4" != "N/A" ]]; then
        if [ -n "$PORT_VISION" ]; then
            local link="vless://${target_uuid}@${IPV4}:${PORT_VISION}?security=reality&encryption=none&pbk=${PUBLIC_KEY}&headerType=none&fp=chrome&type=tcp&flow=xtls-rprx-vision&sni=${SNI_HOST}&sid=${SHORT_ID}#${target_email}_IPv4_Vision"
            echo -e "${BLUE}IPv4 Vision:${PLAIN}"
			echo "${link}$"
        fi
        if [ -n "$PORT_XHTTP" ]; then
            local link="vless://${target_uuid}@${IPV4}:${PORT_XHTTP}?security=reality&encryption=none&pbk=${PUBLIC_KEY}&headerType=none&fp=chrome&type=xhttp&path=${XHTTP_PATH}&sni=${SNI_HOST}&sid=${SHORT_ID}#${target_email}_IPv4_xhttp"
            echo -e "${BLUE}IPv4 XHTTP :${PLAIN}"
			echo "${link}$"
        fi
        echo ""
    fi

    if [[ "$IPV6" != "N/A" ]]; then
        if [ -n "$PORT_VISION" ]; then
            local link="vless://${target_uuid}@[${IPV6}]:${PORT_VISION}?security=reality&encryption=none&pbk=${PUBLIC_KEY}&headerType=none&fp=chrome&type=tcp&flow=xtls-rprx-vision&sni=${SNI_HOST}&sid=${SHORT_ID}#${target_email}_IPv6_Vision"
            echo -e "${BLUE}IPv6 Vision:${PLAIN}"
			echo "${link}$"
        fi
        if [ -n "$PORT_XHTTP" ]; then
            local link="vless://${target_uuid}@[${IPV6}]:${PORT_XHTTP}?security=reality&encryption=none&pbk=${PUBLIC_KEY}&headerType=none&fp=chrome&type=xhttp&path=${XHTTP_PATH}&sni=${SNI_HOST}&sid=${SHORT_ID}#${target_email}_IPv6_xhttp"
            echo -e "${BLUE}IPv6 XHTTP :${PLAIN}"
			echo "${link}$"
        fi
        echo ""
    fi
}

view_user_details() {
    clear
    _print_list

    local len=$(jq '.inbounds[0].settings.clients | length' "$CONFIG_FILE")
    local error_msg=""

    while true; do
        if [ -n "$error_msg" ]; then
            echo -ne "\r\033[K${RED}${error_msg}${PLAIN} 输入序号查看连接信息 [回车或 0 返回]: "
        else
            echo -ne "\r\033[K输入序号查看连接信息 [回车或 0 返回]: "
        fi
        read -r idx

        if [[ -z "$idx" || "$idx" == "0" ]]; then
            return
        fi

        if ! [[ "$idx" =~ ^[0-9]+$ ]]; then
            error_msg="输入无效：\"$idx\" 不是数字！"
            echo -ne "\033[1A"
            continue
        fi

        if [ "$idx" -lt 1 ] || [ "$idx" -ge "$len" ]; then
            error_msg="序号不存在，有效范围: 1-$((len-1))！"
            echo -ne "\033[1A"
            continue
        fi

        error_msg=""
        local email=$(jq -r ".inbounds[0].settings.clients[$idx].email // \"无备注\"" "$CONFIG_FILE")
        local uuid=$(jq -r ".inbounds[0].settings.clients[$idx].id" "$CONFIG_FILE")
        echo ""
        _show_connection_info "$uuid" "$email"
        echo -e "${BLUE}------------------------------------------------${PLAIN}"
    done
}

restart_service() {
    local backup_file="${CONFIG_FILE}.bak"
    chmod 644 "$CONFIG_FILE"
    systemctl restart xray
    sleep 2

    if systemctl is-active --quiet xray; then
        rm -f "$backup_file"
        return 0
    else
        if [ -f "$backup_file" ]; then
            cp "$backup_file" "$CONFIG_FILE"
            chmod 644 "$CONFIG_FILE"
            systemctl restart xray
            rm -f "$backup_file"
            if systemctl is-active --quiet xray; then
                return 2
            else
                return 3
            fi
        else
            return 1
        fi
    fi
}

add_user() {
    clear
    echo -e "${BLUE}>>> 添加新用户${PLAIN}"
    echo ""

    while true; do
        local email=""
        local error_msg=""

        while true; do
            if [ -n "$error_msg" ]; then
                echo -ne "\r\033[K${RED}${error_msg}${PLAIN} 请输入用户备注 [回车或 0 返回]: "
            else
                echo -ne "\r\033[K请输入用户备注 [回车或 0 返回]: "
            fi
            read -r email

            if [[ -z "$email" || "$email" == "0" ]]; then
                return
            fi

            if grep -q "\"email\": \"$email\"" "$CONFIG_FILE"; then
                error_msg="备注 \"$email\" 已存在，请换一个名字！"
                echo -ne "\033[1A"
                continue
            fi

            break
        done

        local new_uuid=$(xray uuid)
        cp "$CONFIG_FILE" "${CONFIG_FILE}.bak"

        tmp=$(mktemp)
        jq --arg uuid "$new_uuid" --arg email "$email" '
            .inbounds |= map(
                if .settings.clients then
                    .settings.clients += [{
                        "id": $uuid,
                        "email": $email,
                        "flow": (.settings.clients[0].flow // "")
                    }]
                else . end
            )' "$CONFIG_FILE" > "$tmp" && mv "$tmp" "$CONFIG_FILE"

        restart_service
        local ret=$?
        case "$ret" in
            0) UI_MESSAGE="${GREEN}用户 ${email} 添加成功。${PLAIN}" ;;
            1) UI_MESSAGE="${RED}添加失败：Xray 启动失败，且未找到备份文件！${PLAIN}" ;;
            2) UI_MESSAGE="${YELLOW}添加失败：Xray 启动失败，已自动回滚至旧配置。${PLAIN}" ;;
            3) UI_MESSAGE="${RED}严重错误：回滚后 Xray 依然无法启动，请立即检查！${PLAIN}" ;;
        esac

        _show_connection_info "$new_uuid" "$email"
        echo -e "${BLUE}------------------------------------------------${PLAIN}"

        echo -ne "\r\033[K继续添加下一个用户？[回车继续 / 0 返回]: "
        read -r cont
        [ "$cont" == "0" ] && return
        echo ""
    done
}

del_user() {
    clear
    _print_list

    while true; do
        local len=$(jq '.inbounds[0].settings.clients | length' "$CONFIG_FILE")

        if [ "$len" -le 1 ]; then
            echo -e "\n${YELLOW}当前已无普通用户可删除。${PLAIN}"
            read -n 1 -s -r -p "按任意键返回..."
            return
        fi

        local error_msg=""
        local idx=""

        while true; do
            if [ -n "$error_msg" ]; then
                echo -ne "\r\033[K${RED}${error_msg}${PLAIN} 请输入要删除的序号 [回车或 0 返回]: "
            else
                echo -ne "\r\033[K请输入要删除的序号 [回车或 0 返回]: "
            fi
            read -r idx

            if [[ -z "$idx" || "$idx" == "0" ]]; then return; fi

            if ! [[ "$idx" =~ ^[0-9]+$ ]]; then
                error_msg="输入无效，请输入数字！"
                echo -ne "\033[1A"
                continue
            fi

            if [ "$idx" -lt 1 ] || [ "$idx" -ge "$len" ]; then
                error_msg="序号不存在，有效范围: 1-$((len-1))！"
                echo -ne "\033[1A"
                continue
            fi

            break
        done

        local email=$(jq -r ".inbounds[0].settings.clients[$idx].email // \"无备注\"" "$CONFIG_FILE")
        local confirm_error=""

        while true; do
            if [ -n "$confirm_error" ]; then
                echo -ne "\r\033[K${RED}${confirm_error}${PLAIN} 确认删除用户 ${RED}${email}${PLAIN}？[y/n]: "
            else
                echo -ne "\r\033[K确认删除用户 ${RED}${email}${PLAIN}？[y/n]: "
            fi
            read -r key

            case "$key" in
                [yY])
                    cp "$CONFIG_FILE" "${CONFIG_FILE}.bak"
                    tmp=$(mktemp)
                    jq "del(.inbounds[].settings.clients[$idx])" "$CONFIG_FILE" > "$tmp" && mv "$tmp" "$CONFIG_FILE"

                    restart_service
                    local ret=$?
                    case "$ret" in
                        0) UI_MESSAGE="${YELLOW}用户 ${email} 已删除。${PLAIN}" ;;
                        1) UI_MESSAGE="${RED}删除失败：Xray 启动失败，且未找到备份文件！${PLAIN}" ;;
                        2) UI_MESSAGE="${YELLOW}删除失败：Xray 启动失败，已自动回滚至旧配置。${PLAIN}" ;;
                        3) UI_MESSAGE="${RED}严重错误：回滚后 Xray 依然无法启动，请立即检查！${PLAIN}" ;;
                    esac

                    clear
                    _print_list
                    break
                    ;;
                [nN])
                    echo -ne "\r\033[K${YELLOW}操作已取消。${PLAIN}\033[K"
                    echo ""
                    break
                    ;;
                *)
                    confirm_error="必须输入 y 或 n！"
                    echo -ne "\033[1A"
                    ;;
            esac
        done
    done
}

while true; do
    tput cup 0 0

    echo -e "${BLUE}===================================================${PLAIN}\033[K"
    echo -e "${BLUE}              多用户管理 (User Manager)           ${PLAIN}\033[K"
    echo -e "${BLUE}===================================================${PLAIN}\033[K"
    echo -e "  1. 查看列表 & 连接信息\033[K"
    echo -e "  2. ${GREEN}添加新用户${PLAIN}\033[K"
    echo -e "  3. ${RED}删除旧用户${PLAIN}\033[K"
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
        1) view_user_details ;;
        2) add_user ;;
        3) del_user ;;
        0) clear; exit 0 ;;
    esac
done
