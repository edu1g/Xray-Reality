#!/bin/bash

# 定义颜色
RED="\033[31m"
GREEN="\033[32m"
YELLOW="\033[33m"
BLUE="\033[36m"
PLAIN="\033[0m"
GRAY="\033[90m"

UI_MESSAGE=""

BACKUP_DIR="/usr/local/etc/xray/backup"
CONFIG_FILE="/usr/local/etc/xray/config.json"
XRAY_BIN="/usr/local/bin/xray"
ASSET_DIR="/usr/local/share/xray"

# 确保备份目录存在
mkdir -p "$BACKUP_DIR"

# 1. 创建备份
create_backup() {
    if [ ! -f "$CONFIG_FILE" ]; then
        UI_MESSAGE="${RED}错误：找不到配置文件，无法备份${PLAIN}"
        return
    fi

    local timestamp=$(date "+%Y%m%d_%H%M%S")
    local backup_file="$BACKUP_DIR/config_$timestamp.json"
    cp "$CONFIG_FILE" "$backup_file"

    # 清理超过60天的备份，但至少保留最新1份
    local all_files=($(ls -t "$BACKUP_DIR"/config_*.json 2>/dev/null))
    local newest="${all_files[0]}"
    find "$BACKUP_DIR" -name "config_*.json" -mtime +60 ! -path "$newest" -delete 2>/dev/null

    # 保留最近5份
    local count=$(ls -1 "$BACKUP_DIR"/config_*.json 2>/dev/null | wc -l)
    if [ "$count" -gt 5 ]; then
        cd "$BACKUP_DIR"
        ls -t config_*.json | tail -n +6 | xargs -I {} rm -- {} 2>/dev/null
        UI_MESSAGE="${GREEN}备份成功，自动清理旧备份（保留最近5份）${PLAIN}"
    else
        UI_MESSAGE="${GREEN}备份成功：$(basename "$backup_file")${PLAIN}"
    fi
}

# 2. 还原备份
restore_backup() {
    local files=($(ls -t "$BACKUP_DIR"/config_*.json 2>/dev/null))

    if [ ${#files[@]} -eq 0 ]; then
        UI_MESSAGE="${RED}没有找到任何备份文件${PLAIN}"
        return
    fi

    echo -e "${BLUE}>>> 请选择要还原的备份点：${PLAIN}"
    echo -e "-------------------------------------------------------"
    local i=1
    for file in "${files[@]}"; do
        filename=$(basename "$file")
        filetime=$(date -r "$file" "+%Y-%m-%d %H:%M:%S")

        local tag=""
        if [ "$i" -eq 1 ]; then
            tag="${GREEN}最新${PLAIN}"
        fi

        echo -e "  ${GREEN}$i.${PLAIN} $filename  ${YELLOW}($filetime)${PLAIN} $tag"
        let i++
    done

    echo -e "-------------------------------------------------------"
    echo -e "  0. 取消"
    echo -e ""

    local limit=${#files[@]}

    error_msg=""
    while true; do
        if [ -n "$error_msg" ]; then
            echo -ne "\r\033[K${RED}${error_msg}${PLAIN} 请输入选项 [0-$limit]: "
        else
            echo -ne "\r\033[K请输入选项 [0-$limit]: "
        fi
        read -r key < /dev/tty
        if [[ "$key" =~ ^[0-9]$ ]] && [ "$key" -le "$limit" ]; then
            break
        else
            error_msg="输入无效！"
            echo -ne "\033[1A"
        fi
    done

    if [ "$key" -eq 0 ]; then
        UI_MESSAGE="${YELLOW}还原操作已取消${PLAIN}"
        return
    fi

    local target_file="${files[$((key-1))]}"

    echo -e "\n您选择了: ${YELLOW}$(basename "$target_file")${PLAIN}"
    echo -e "正在校验备份文件..."

    if ! XRAY_LOCATION_ASSET="$ASSET_DIR" "$XRAY_BIN" run -test -c "$target_file" >/dev/null 2>&1; then
        echo -e "${RED}错误：该备份文件校验失败，无法还原！${PLAIN}"
        echo -e "${YELLOW}>>> 错误详情 (Debug Info):${PLAIN}"
        XRAY_LOCATION_ASSET="$ASSET_DIR" "$XRAY_BIN" run -test -c "$target_file"
        return
    fi

    local confirm_msg="确定要覆盖当前配置吗？[y/n]: "

    error_msg=""
    while true; do
        if [ -n "$error_msg" ]; then
            echo -ne "\r\033[K${RED}${error_msg}${PLAIN} $confirm_msg"
        else
            echo -ne "\r\033[K$confirm_msg"
        fi
        read -r key < /dev/tty
        case "$key" in
            [yY]) break ;;
            [nN]) UI_MESSAGE="${YELLOW}还原操作已取消${PLAIN}"; return ;;
            *) error_msg="输入无效！"; echo -ne "\033[1A" ;;
        esac
    done

    echo -e "\n${BLUE}>>> 正在还原...${PLAIN}"
    cp "$target_file" "$CONFIG_FILE"
    chmod 644 "$CONFIG_FILE"
    systemctl restart xray >/dev/null 2>&1

    if systemctl is-active --quiet xray; then
        UI_MESSAGE="${GREEN}还原成功，服务已重启${PLAIN}"
    else
        UI_MESSAGE="${RED}配置已还原，但服务启动失败，请检查日志${PLAIN}"
    fi
}

# 3. 导出备份
export_backup() {
    if [ ! -f "$CONFIG_FILE" ]; then echo -e "${RED}无配置可导出${PLAIN}"; return; fi
    
    echo -e "${BLUE}=======================================================${PLAIN}"
    echo -e "${BLUE}           配置内容预览 (Copy & Paste)           ${PLAIN}"
    echo -e "${BLUE}=======================================================${PLAIN}"
    cat "$CONFIG_FILE"
    echo -e "\n${BLUE}=======================================================${PLAIN}"
    echo -e "${YELLOW}提示：你可以复制上方内容保存到本地 config.json${PLAIN}"
}

# 菜单显示函数
show_menu() {
    tput cup 0 0
    echo -e "${BLUE}=======================================================${PLAIN}\033[K"
    echo -e "${BLUE}           Xray 配置备份与还原 (Backup)               ${PLAIN}\033[K"
    echo -e "${BLUE}=======================================================${PLAIN}\033[K"
    echo -e "  1. ${GREEN}创建新备份 ${PLAIN}\033[K"
    echo -e "  2. ${RED}还原旧配置 ${PLAIN}\033[K"
    echo -e "  3. 查看当前配置\033[K"
    echo -e "-------------------------------------------------------\033[K"
    echo -e "  0. 退出\033[K"
    echo -e "=======================================================\033[K"
    if [ -n "$UI_MESSAGE" ]; then
        echo -e "${YELLOW}当前操作${PLAIN}: ${UI_MESSAGE}\033[K"
    else
        echo -e "${YELLOW}当前操作${PLAIN}: ${GRAY}等待输入...${PLAIN}\033[K"
    fi
    echo -e "=======================================================\033[K"
    tput ed
    UI_MESSAGE=""
}

# 主程序逻辑
clear
while true; do
    show_menu

    error_msg=""
    while true; do
        if [ -n "$error_msg" ]; then
            echo -ne "\r\033[K${RED}${error_msg}${PLAIN} 请输入选项 [0-3]: "
        else
            echo -ne "\r\033[K请输入选项 [0-3]: "
        fi
        read -r choice
        case "$choice" in
            [0-3]) break ;;
            *) error_msg="输入无效！"; echo -ne "\033[1A" ;;
        esac
    done

    case "$choice" in
        1) create_backup ;;
        2) restore_backup ;;
        3) export_backup; read -n 1 -s -r -p "按任意键返回菜单..."; clear ;;
        0) clear; exit 0 ;;
    esac
done
