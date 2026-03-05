#!/bin/bash

# ─────────────────────────────────────────────
#  Fail2ban 防火墙管理器
# ─────────────────────────────────────────────

RED="\033[31m"; GREEN="\033[32m"; YELLOW="\033[33m"; CYAN="\033[36m"; GRAY="\033[90m"; PLAIN="\033[0m"

UI_MESSAGE=""

JAIL_FILE="/etc/fail2ban/jail.local"

# ─── 环境检查 ────────────────────────────────
clear
if [ "$EUID" -ne 0 ]; then echo -e "${RED}请使用 sudo 运行此脚本！${PLAIN}"; exit 1; fi

# ─── 配置读写 ────────────────────────────────
get_conf() {
    local key=$1
    grep "^${key}\s*=" "$JAIL_FILE" | awk -F'=' '{print $2}' | tr -d ' '
}

set_conf() {
    local key=$1; local val=$2
    if grep -q "^${key}\s*=" "$JAIL_FILE"; then
        sed -i "s/^${key}\s*=.*/${key} = ${val}/" "$JAIL_FILE"
    else
        sed -i "2i ${key} = ${val}" "$JAIL_FILE"
    fi
}

# ─── 服务重启 ────────────────────────────────
restart_f2b() {
    systemctl restart fail2ban >/dev/null 2>&1
    return $?
}

# ─── 状态读取 ────────────────────────────────
get_status() {
    if systemctl is-active fail2ban >/dev/null 2>&1; then
        local count=$(fail2ban-client status sshd 2>/dev/null | grep "Currently banned" | grep -o "[0-9]*")
        echo -e "${GREEN}运行中 (Active)${PLAIN} | 当前封禁: ${RED}${count:-0}${PLAIN} IP"
    else
        echo -e "${RED}已停止 (Stopped)${PLAIN}"
    fi
}

# ─── 输入校验 ────────────────────────────────
validate_time() {
    if [[ "$1" =~ ^[0-9]+[smhdw]?$ ]]; then return 0; else return 1; fi
}

validate_float() {
    if [[ "$1" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then return 0; else return 1; fi
}

validate_int() {
    if [[ "$1" =~ ^[0-9]+$ ]]; then return 0; else return 1; fi
}

validate_ip_format() {
    local ip=$1
    if [[ "$ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}(/([0-9]|[1-2][0-9]|3[0-2]))?$ ]]; then
        IFS='./' read -r -a octets <<< "$ip"
        for octet in "${octets[@]:0:4}"; do
            if [[ "$octet" -gt 255 ]]; then return 1; fi
        done
        return 0
    fi

    if [[ "$ip" =~ ^([0-9a-fA-F]{0,4}:){1,7}[0-9a-fA-F]{0,4}(/[0-9]{1,3})?$ ]]; then
        if [[ "$ip" =~ :: || "$ip" =~ : ]]; then return 0; fi
    fi

    return 1
}

# ─── 参数修改 ────────────────────────────────
change_param() {
    local name=$1; local key=$2; local type=$3; local hint=$4
    local current=$(get_conf "$key")

    clear
    echo -e "${CYAN}正在修改: ${name}${PLAIN}"
    echo -e "当前值: ${GREEN}${current}${PLAIN}"
    if [ -n "$hint" ]; then
        echo -e "${GRAY}说明: ${hint}${PLAIN}"
    fi
    echo ""

    while true; do
        echo -ne "\r\033[K请输入新值 (留空取消): "
        read -r new_val

        if [ -z "$new_val" ]; then
            UI_MESSAGE="${GRAY}${name} 修改已取消。${PLAIN}"
            return
        fi

        local check_pass=false
        local err=""

        case "$type" in
            "time")
                if validate_time "$new_val"; then check_pass=true
                else err="格式无效，必须是整数时间，支持单位 s/m/h/d/w (如 10m)。"; fi
                ;;
            "float")
                if validate_float "$new_val"; then check_pass=true
                else err="格式无效，必须是纯数字或小数 (如 1.5)。"; fi
                ;;
            "int")
                if validate_int "$new_val"; then check_pass=true
                else err="格式无效，仅支持纯整数。"; fi
                ;;
        esac

        if [ "$check_pass" == "true" ]; then
            break
        else
            echo -ne "\033[1A\033[K${RED}[错误] ${err}${PLAIN} "
        fi
    done

    set_conf "$key" "$new_val"
    if restart_f2b; then
        UI_MESSAGE="${GREEN}${name} 已修改为 ${YELLOW}${new_val}${GREEN}，配置已生效。${PLAIN}"
    else
        UI_MESSAGE="${RED}${name} 写入成功，但 Fail2ban 重启失败，请检查配置！${PLAIN}"
    fi
    clear; printf '\033[3J'
}

# ─── 服务开关 ────────────────────────────────
toggle_service() {
    clear
    echo -e "${CYAN}--- 服务开关 (Service Switch) ---${PLAIN}"
    echo ""

    local is_running=false
    if systemctl is-active fail2ban >/dev/null 2>&1; then
        is_running=true
        echo -e "当前状态: ${GREEN}运行中 (Active)${PLAIN}"
        echo -e "${YELLOW}警告: 停止服务将导致不再拦截恶意 IP。${PLAIN}"
    else
        echo -e "当前状态: ${RED}已停止 (Stopped)${PLAIN}"
    fi
    echo ""

    local prompt_msg=""
    if [ "$is_running" == "true" ]; then
        prompt_msg="是否 **停止** 并禁用 Fail2ban? (y/n): "
    else
        prompt_msg="是否 **启动** 并启用 Fail2ban? (y/n): "
    fi

    local confirm_error=""
    while true; do
        if [ -n "$confirm_error" ]; then
            echo -ne "\r\033[K${RED}${confirm_error}${PLAIN} ${prompt_msg}"
        else
            echo -ne "\r\033[K${prompt_msg}"
        fi
        read -r input
        case "$input" in
            [yY])
                if [ "$is_running" == "true" ]; then
                    systemctl stop fail2ban && systemctl disable fail2ban
                    UI_MESSAGE="${RED}Fail2ban 服务已停止并禁用。${PLAIN}"
                else
                    systemctl enable fail2ban && systemctl start fail2ban
                    UI_MESSAGE="${GREEN}Fail2ban 服务已启动并启用。${PLAIN}"
                fi
                clear; printf '\033[3J'
                return
                ;;
            [nN])
                UI_MESSAGE="${GRAY}服务开关操作已取消。${PLAIN}"
                clear; printf '\033[3J'
                return
                ;;
            *)
                confirm_error="错误：必须输入 y 或 n！"
                echo -ne "\033[1A"
                ;;
        esac
    done
}

# ─── IP 封禁 / 解封管理 ──────────────────────
unban_ip() {
    local current_ip=$(echo $SSH_CLIENT | awk '{print $1}')

    while true; do
        clear
        echo -e "\n${CYAN}--- IP 封禁/解封管理 (Ban/Unban Manager) ---${PLAIN}"

        local clean_list=$(fail2ban-client status sshd 2>/dev/null | grep "Banned IP list" | awk -F':' '{print $2}' | xargs)
        IFS=' ' read -r -a ip_array <<< "$clean_list"

        echo -e "${GRAY}------------------------------------------${PLAIN}"
        printf "${YELLOW}%-4s %-20s${PLAIN}\n" "ID" "Banned IP Address"
        echo -e "${GRAY}------------------------------------------${PLAIN}"
        if [ ${#ip_array[@]} -eq 0 ]; then
            echo -e "      (当前无封禁 IP / None)"
        else
            local i=1
            for ip in "${ip_array[@]}"; do
                printf "${GREEN}%-4s${PLAIN} %-20s\n" "$i" "$ip"
                ((i++))
            done
        fi
        echo -e "${GRAY}------------------------------------------${PLAIN}"
        echo -e "${YELLOW}指令说明: ${PLAIN}"
        echo -e "  - ${RED}ban${PLAIN}   -> 封禁 IP"
        echo -e "  - ${GREEN}unban${PLAIN} -> 解封 IP"
        echo -e "  - ${GRAY}0${PLAIN}     -> 返回"
        echo -e "${GRAY}------------------------------------------${PLAIN}"

        local cmd_error=""
        while true; do
            if [ -n "$cmd_error" ]; then
                echo -ne "\r\033[K${RED}${cmd_error}${PLAIN} 请输入指令: "
            else
                echo -ne "\r\033[K请输入指令: "
            fi
            read -r raw_input
            local input=$(echo "$raw_input" | tr '[:upper:]' '[:lower:]' | xargs)

            if [ -z "$input" ]; then
                echo -ne "\033[1A"
                continue
            fi

            case "$input" in
                0) return ;;

                "ban")
                    local ban_error=""
                    while true; do
                        echo ""
                        if [ -n "$ban_error" ]; then
                            echo -ne "\r\033[K${RED}${ban_error}${PLAIN} 请输入封禁IP (留空取消): "
                        else
                            echo -ne "\r\033[K  > 请输入封禁IP (留空取消): "
                        fi
                        read -r ban_target

                        if [ -z "$ban_target" ]; then
                            echo -ne "\033[1A\033[K\033[1A\033[K"
                            break
                        fi

                        if ! validate_ip_format "$ban_target"; then
                            ban_error="IP 格式无效！"
                            echo -ne "\033[1A\033[K\033[1A\033[K"
                            continue
                        fi

                        if [ "$ban_target" == "$current_ip" ]; then
                            ban_error="禁止封禁本机 IP (${current_ip})！"
                            echo -ne "\033[1A\033[K\033[1A\033[K"
                            continue
                        fi

                        local output=$(fail2ban-client set sshd banip "$ban_target")
                        if [[ "$output" == "1" ]] || [[ "$output" == *"$ban_target"* ]]; then
                            UI_MESSAGE="${RED}IP ${ban_target} 封禁成功。${PLAIN}"
                        else
                            UI_MESSAGE="${RED}封禁操作失败：${output}${PLAIN}"
                        fi
                        break 2
                    done
                    ;;

                "unban")
                    local unban_error=""
                    while true; do
                        echo ""
                        if [ -n "$unban_error" ]; then
                            echo -ne "\r\033[K${RED}${unban_error}${PLAIN} 请输入解封 IP 或 ID (留空取消): "
                        else
                            echo -ne "\r\033[K  > 请输入解封 IP 或 ID (留空取消): "
                        fi
                        read -r unban_target

                        if [ -z "$unban_target" ]; then
                            echo -ne "\033[1A\033[K\033[1A\033[K"
                            break
                        fi

                        local target_ip=""
                        local is_valid=true
                        local err_msg=""

                        if [[ "$unban_target" =~ ^[0-9]+$ ]]; then
                            if [ "$unban_target" -ge 1 ] && [ "$unban_target" -le "${#ip_array[@]}" ]; then
                                target_ip="${ip_array[$((unban_target-1))]}"
                            else
                                is_valid=false
                                err_msg="序号 ${unban_target} 不存在！"
                            fi
                        elif validate_ip_format "$unban_target"; then
                            target_ip="$unban_target"
                        else
                            is_valid=false
                            err_msg="格式无效！"
                        fi

                        if [ "$is_valid" == "false" ]; then
                            unban_error="$err_msg"
                            echo -ne "\033[1A\033[K\033[1A\033[K"
                            continue
                        fi

                        local output=$(fail2ban-client set sshd unbanip "$target_ip")
                        if [[ "$output" == *"$target_ip"* ]] || [[ "$output" == "1" ]]; then
                            UI_MESSAGE="${GREEN}IP ${target_ip} 解封成功。${PLAIN}"
                        else
                            UI_MESSAGE="${RED}解封失败，Fail2ban 未找到该 IP。${PLAIN}"
                        fi
                        break 2
                    done
                    ;;

                *)
                    cmd_error="无效指令 '${input}'，请输入 ban、unban 或 0！"
                    echo -ne "\033[1A"
                    ;;
            esac
        done
    done
}

# ─── 白名单管理 ──────────────────────────────
add_whitelist() {
    local current_ip=$(echo $SSH_CLIENT | awk '{print $1}')

    while true; do
        clear
        echo -e "\n${CYAN}--- 白名单管理 (Whitelist Manager) ---${PLAIN}"

        local raw_list=$(grep "^ignoreip" "$JAIL_FILE" | awk -F'=' '{print $2}' | sed 's/^[ \t]*//;s/[ \t]*$//')
        IFS=' ' read -r -a ip_array <<< "$raw_list"

        echo -e "${GRAY}-------------------------------------------${PLAIN}"
        printf "${YELLOW}%-6s %-25s %s${PLAIN}\n" "ID" "IP / Network" "Type"
        echo -e "${GRAY}-------------------------------------------${PLAIN}"

        local user_ips=()
        if [ ${#ip_array[@]} -eq 0 ]; then
            echo -e "      (当前无白名单 / None)"
        else
            local display_idx=1
            for ip in "${ip_array[@]}"; do
                if [[ "$ip" =~ ^127\. ]] || [[ "$ip" == "::1" ]]; then
                    printf "${RED}%-6s${PLAIN} %-25s ${GRAY}[System]${PLAIN}\n" "#" "$ip"
                else
                    printf "${GREEN}%-6s${PLAIN} %-25s ${CYAN}[User]${PLAIN}\n" "$display_idx" "$ip"
                    user_ips+=("$ip")
                    ((display_idx++))
                fi
            done
        fi
        echo -e "${GRAY}-------------------------------------------${PLAIN}"
        echo -e "${YELLOW}本机 IP: ${GREEN}${current_ip}${PLAIN}"
        echo -e "  - ${GREEN}添加${PLAIN}: 直接输入 IP (回车默认添加本机)"
        echo -e "  - ${RED}删除${PLAIN}: 输入 'd' + 序号 (如 ${RED}d1${PLAIN})"
        echo -e "  - ${GRAY}返回${PLAIN}: 输入 0"
        echo -e "${GRAY}-------------------------------------------${PLAIN}"

        local wl_error=""
        while true; do
            if [ -n "$wl_error" ]; then
                echo -ne "\r\033[K${RED}${wl_error}${PLAIN} 请输入指令: "
            else
                echo -ne "\r\033[K请输入指令: "
            fi
            read -r input

            if [ "$input" == "0" ]; then return; fi

            if [ -z "$input" ]; then
                input="$current_ip"
                echo -ne "\033[1A\033[K"
                echo -e "请输入指令: ${GREEN}${input} (自动填入)${PLAIN}"
            fi

            if [[ "$input" =~ ^[dD]([0-9]+)$ ]]; then
                local del_id=${BASH_REMATCH[1]}
                if [ "$del_id" -lt 1 ] || [ "$del_id" -gt "${#user_ips[@]}" ]; then
                    wl_error="序号 ${del_id} 不存在！"
                    echo -ne "\033[1A\033[K"
                    continue
                fi

                local target_ip="${user_ips[$((del_id-1))]}"
                local new_line="ignoreip ="
                for ip in "${ip_array[@]}"; do
                    if [ "$ip" != "$target_ip" ]; then new_line="${new_line} ${ip}"; fi
                done
                sed -i "s|^ignoreip.*|${new_line}|" "$JAIL_FILE"

                if restart_f2b; then
                    UI_MESSAGE="${YELLOW}白名单 ${target_ip} 已删除，配置已生效。${PLAIN}"
                else
                    UI_MESSAGE="${RED}白名单已更新，但 Fail2ban 重启失败！${PLAIN}"
                fi
                break
            fi

            if ! validate_ip_format "$input"; then
                wl_error="IP 格式无效：'${input}'！"
                echo -ne "\033[1A\033[K"
                continue
            fi

            local exists=false
            for ip in "${ip_array[@]}"; do
                if [[ "$ip" == "$input" ]]; then
                    wl_error="IP ${input} 已存在于白名单中！"
                    exists=true
                    break
                fi
            done
            if [ "$exists" == "true" ]; then
                echo -ne "\033[1A\033[K"
                continue
            fi

            sed -i "/^ignoreip/ s/$/ ${input}/" "$JAIL_FILE"
            if restart_f2b; then
                UI_MESSAGE="${GREEN}${input} 已加入白名单，配置已生效。${PLAIN}"
            else
                UI_MESSAGE="${RED}白名单已更新，但 Fail2ban 重启失败！${PLAIN}"
            fi
            break
        done
    done
}

# ─── 日志查看 ────────────────────────────────
view_logs() {
    local log_file="/var/log/fail2ban.log"

    clear
    if [ ! -f "$log_file" ]; then
        echo -e "${YELLOW}日志文件不存在 ($log_file)。${PLAIN}"
        read -n 1 -s -r -p "按任意键返回..."
        UI_MESSAGE="${YELLOW}日志文件不存在。${PLAIN}"
        clear; printf '\033[3J'
        return
    fi

    echo -e "${CYAN}=================================================================${PLAIN}"
    echo -e "${CYAN}           Fail2ban 管理日志 (最近 33 条)                        ${PLAIN}"
    echo -e "${CYAN}=================================================================${PLAIN}"
    printf "${GRAY}%-20s %-12s %-16s %s${PLAIN}\n" "[Date / Time]" "[Jail]" "[IP Address]" "[Action]"
    echo -e "${GRAY}-----------------------------------------------------------------${PLAIN}"

    grep --color=never -E "(Ban|Unban)" "$log_file" 2>/dev/null | tail -n 33 | sed -r "s/\x1b\[[0-9;]*m//g" | awk '{
        dt = $1 " " substr($2, 1, 8);
        jail = ""; action = ""; ip = "";
        for(i=3; i<=NF; i++) {
            if ($i ~ /^\[.*\]$/) jail = $i;
            if ($i == "Ban" || $i == "Unban") { action = $i; ip = $(i+1); break; }
            if ($i == "Restore" && $(i+1) == "Ban") { action = "ResBan"; ip = $(i+2); break; }
        }
        if (action == "Ban") act_str = "\033[31m" action "\033[0m";
        else if (action == "Unban") act_str = "\033[32m" action "\033[0m";
        else act_str = "\033[33m" action "\033[0m";
        if (jail != "" && ip != "") printf "%-20s %-12s %-16s %s\n", dt, jail, ip, act_str
    }'

    echo -e "${GRAY}-----------------------------------------------------------------${PLAIN}"
    read -n 1 -s -r -p "按任意键返回主菜单..."
    UI_MESSAGE="${GRAY}日志查看完毕。${PLAIN}"
    clear; printf '\033[3J'
}

# ─── 指数封禁子菜单 ──────────────────────────
menu_exponential() {
    local SUB_MESSAGE=""
    while true; do
        local inc=$(get_conf "bantime.increment")
        local fac=$(get_conf "bantime.factor")
        local max=$(get_conf "bantime.maxtime")
        local S_INC=""
        [ "$inc" == "true" ] && S_INC="${GREEN}ON${PLAIN}" || S_INC="${RED}OFF${PLAIN}"

        tput cup 0 0
        echo -e "${CYAN}===================================================${PLAIN}\033[K"
        echo -e "${CYAN}       递增封禁设置 (Exponential Backoff)         ${PLAIN}\033[K"
        echo -e "${CYAN}===================================================${PLAIN}\033[K"
        echo -e "  1. 递增模式开关   [${S_INC}]\033[K"
        echo -e "  2. 修改增长系数   [${YELLOW}${fac}${PLAIN}]\033[K"
        echo -e "  3. 修改封禁上限   [${YELLOW}${max}${PLAIN}]\033[K"
        echo -e "---------------------------------------------------\033[K"
        echo -e "  0. 返回\033[K"
        echo -e "===================================================\033[K"

        if [ -n "$SUB_MESSAGE" ]; then
            echo -e "${YELLOW}当前操作${PLAIN}: ${SUB_MESSAGE}\033[K"
            SUB_MESSAGE=""
        else
            echo -e "${YELLOW}当前操作${PLAIN}: ${GRAY}等待输入...${PLAIN}\033[K"
        fi
        echo -e "===================================================\033[K"

        tput ed

        local error_msg=""
        while true; do
            if [ -n "$error_msg" ]; then
                echo -ne "\r\033[K${RED}${error_msg}${PLAIN} 请输入选项 [0-3]: "
            else
                echo -ne "\r\033[K请输入选项 [0-3]: "
            fi
            read -r choice
            case "$choice" in
                1|2|3|0) break ;;
                *) error_msg="输入无效！"; echo -ne "\033[1A" ;;
            esac
        done

        case "$choice" in
            1)
                [ "$inc" == "true" ] && ns="false" || ns="true"
                set_conf "bantime.increment" "$ns"
                if restart_f2b; then
                    SUB_MESSAGE="${GREEN}递增模式已切换为 ${ns}，配置已生效。${PLAIN}"
                else
                    SUB_MESSAGE="${RED}配置已写入，但 Fail2ban 重启失败！${PLAIN}"
                fi
                ;;
            2)
                change_param "增长系数 (Factor)" "bantime.factor" "float" \
                "封禁时间的增长倍率。必须是纯数字，禁止加单位。公式: 初始时长 * 系数^封禁次数"
                SUB_MESSAGE="$UI_MESSAGE"; UI_MESSAGE=""
                ;;
            3)
                change_param "封禁上限 (MaxTime)" "bantime.maxtime" "time" \
                "封禁时长的最大值。支持单位 s/m/h/d/w，不带单位默认为秒。"
                SUB_MESSAGE="$UI_MESSAGE"; UI_MESSAGE=""
                ;;
            0) return ;;
        esac
    done
}

# ─── 菜单界面 ────────────────────────────────
clear
show_menu() {
    VAL_MAX=$(get_conf "maxretry"); VAL_BAN=$(get_conf "bantime"); VAL_FIND=$(get_conf "findtime")

    tput cup 0 0
    echo -e "${CYAN}===================================================${PLAIN}\033[K"
    echo -e "${CYAN}         Fail2ban 防火墙管理 (F2B Panel)          ${PLAIN}\033[K"
    echo -e "${CYAN}===================================================${PLAIN}\033[K"
    echo -e "  状态: $(get_status)\033[K"
    echo -e "---------------------------------------------------\033[K"
    echo -e "  1. 修改 最大重试次数 [${YELLOW}${VAL_MAX}${PLAIN}]\033[K"
    echo -e "  2. 修改 初始封禁时长 [${YELLOW}${VAL_BAN}${PLAIN}]\033[K"
    echo -e "  3. 修改 监测时间窗口 [${YELLOW}${VAL_FIND}${PLAIN}]\033[K"
    echo -e "---------------------------------------------------\033[K"
    echo -e "  4. ${GREEN}IP 封禁/解封管理${PLAIN}\033[K"
    echo -e "  5. ${GREEN}IP 白名单管理${PLAIN}\033[K"
    echo -e "  6. 查看日志\033[K"
    echo -e "  7. ${YELLOW}递增封禁设置${PLAIN}\033[K"
    echo -e "---------------------------------------------------\033[K"
    echo -e "  8. ${GREEN}开启${PLAIN}/${RED}停止${PLAIN} Fail2ban 服务\033[K"
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
}

# ─── 主循环 ──────────────────────────────────
while true; do
    show_menu

    error_msg=""
    while true; do
        if [ -n "$error_msg" ]; then
            echo -ne "\r\033[K${RED}${error_msg}${PLAIN} 请输入选项 [0-8]: "
        else
            echo -ne "\r\033[K请输入选项 [0-8]: "
        fi
        read -r choice
        case "$choice" in
            1|2|3|4|5|6|7|8|0) break ;;
            *) error_msg="输入无效！"; echo -ne "\033[1A" ;;
        esac
    done

    case "$choice" in
        1)
            change_param "最大重试次数 (MaxRetry)" "maxretry" "int" \
            "允许 IP 失败的最大次数。必须是纯数字，禁止加单位。超过此次数后 IP 将被封禁。推荐值: 3~5 次。"
            ;;
        2)
            change_param "初始封禁时长 (BanTime)" "bantime" "time" \
            "IP 被封禁的基础时长。支持单位 s/m/h/d/w，不带单位默认为秒。推荐: 1h 或 1d。"
            ;;
        3)
            change_param "监测时间窗口 (FindTime)" "findtime" "time" \
            "统计失败次数的时间范围。支持单位 s/m/h/d/w，不带单位默认为秒。推荐: 1d。"
            ;;
        4) unban_ip ;;
        5) add_whitelist ;;
        6) view_logs ;;
        7) menu_exponential ;;
        8) toggle_service ;;
        0) clear; exit 0 ;;
    esac
done
