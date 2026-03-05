#!/bin/bash

# ─────────────────────────────────────────────
#  2_install.sh — 核心组件安装
# ─────────────────────────────────────────────

# ─── 显式初始化 ───
FIXED_VER=""

# ─── Xray 核心安装 ──────────────────
install_xray_robust() {
    local max_tries=3
    local count=0
    local bin_path="/usr/local/bin/xray"
    local VER_ARG=""

    if [ -n "$FIXED_VER" ]; then
        VER_ARG="--version $FIXED_VER"
    fi

    mkdir -p /usr/local/share/xray/

    while [ $count -lt $max_tries ]; do
        local desc="安装 Xray Core"
        if [ $count -gt 0 ]; then desc="安装 Xray Core (重试: $((count+1)))"; fi

        local install_cmd="bash -c \"\$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)\" @ install --without-geodata $VER_ARG"

        if execute_task "$install_cmd" "$desc"; then
            if [ -f "$bin_path" ] && "$bin_path" version &>/dev/null; then
                local ver
                ver=$("$bin_path" version | head -n 1 | awk '{print $2}')
                echo -e "       └─ 版本: ${GREEN}${ver}${PLAIN}"
                return 0
            fi
        fi

        rm -rf "$bin_path" \
               "/usr/local/share/xray/" \
               "/etc/systemd/system/xray.service" \
               "/etc/systemd/system/xray.service.d/"
        ((count++))
        sleep 2
    done

    echo -e "${ERR} [FATAL] Xray Core 安装失败，请检查网络。"
    exit 1
}

# ─── GeoData 自动更新脚本生成 ────────────────
_install_geodata_updater() {
    local share_dir="$1"
    local url_ip="$2"
    local url_site="$3"
    local updater="/usr/local/bin/xray-update-geo"

    cat > "$updater" <<UPDATER_EOF
#!/bin/bash
# xray-update-geo — GeoData 自动更新脚本
# 由安装程序生成，可手动执行：sudo xray-update-geo

SHARE_DIR="${share_dir}"
URL_IP="${url_ip}"
URL_SITE="${url_site}"

tmp_ip=\$(mktemp)
tmp_site=\$(mktemp)

curl -sSLk --retry 3 -o "\$tmp_ip"   "\$URL_IP"
curl -sSLk --retry 3 -o "\$tmp_site" "\$URL_SITE"

size_ip=\$(du -k "\$tmp_ip"   | awk '{print \$1}')
size_site=\$(du -k "\$tmp_site" | awk '{print \$1}')

if [ "\${size_ip:-0}" -gt 1000 ] && [ "\${size_site:-0}" -gt 1000 ]; then
    mv -f "\$tmp_ip"   "\$SHARE_DIR/geoip.dat"
    mv -f "\$tmp_site" "\$SHARE_DIR/geosite.dat"
    systemctl restart xray
    echo "\$(date '+%Y-%m-%d %H:%M:%S') GeoData 更新成功" >> /var/log/xray-update-geo.log
else
    rm -f "\$tmp_ip" "\$tmp_site"
    echo "\$(date '+%Y-%m-%d %H:%M:%S') GeoData 更新失败（文件损坏）" >> /var/log/xray-update-geo.log
fi
UPDATER_EOF

    chmod +x "$updater"

    # ─── 定时任务注册 ────────────────────────
    if command -v crontab &>/dev/null; then
        if systemctl is-active --quiet cron 2>/dev/null || systemctl is-active --quiet crond 2>/dev/null; then
            (crontab -l 2>/dev/null | grep -v "xray-update-geo"; echo "0 4 * * 0 $updater >/dev/null 2>&1") | crontab -
            echo -e "       └─ 自动更新: ${GREEN}已配置 (每周日 4:00，执行 xray-update-geo)${PLAIN}"
        else
            echo -e "      ${WARN} cron 服务未运行，自动更新未配置。可手动执行: xray-update-geo"
        fi
    else
        echo -e "      ${WARN} 未检测到 crontab，跳过自动更新配置。可手动执行: xray-update-geo"
    fi
}

# ─── GeoData 规则库安装 ─────────────
install_geodata_robust() {
    echo -e "${INFO} 正在安装 GeoData 路由规则库..."

    local share_dir="/usr/local/share/xray"
    mkdir -p "$share_dir"

    local url_ip="https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geoip.dat"
    local url_site="https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geosite.dat"

    local tmp_ip tmp_site
    tmp_ip=$(mktemp)
    tmp_site=$(mktemp)

    local max_retries=3
    local attempt=1
    local success=false

    while [ $attempt -le $max_retries ]; do
        echo -e "       直连拉取 GeoData (尝试 $attempt/$max_retries) ..."

        curl -sSLk --retry 3 -o "$tmp_ip"   "$url_ip"
        curl -sSLk --retry 3 -o "$tmp_site" "$url_site"

        local size_ip size_site
        size_ip=$(du -k "$tmp_ip"   | awk '{print $1}')
        size_site=$(du -k "$tmp_site" | awk '{print $1}')

        if [ "${size_ip:-0}" -gt 1000 ] && [ "${size_site:-0}" -gt 1000 ]; then
            success=true
            break
        else
            echo -e "   ${WARN} 第 $attempt 次拉取失败（文件损坏或过小），准备重试..."
            sleep 2
            attempt=$((attempt + 1))
        fi
    done

    if [ "$success" = true ]; then
        mv -f "$tmp_ip"   "$share_dir/geoip.dat"
        mv -f "$tmp_site" "$share_dir/geosite.dat"
        chmod 644 "$share_dir"/*.dat
        echo -e "${OK} GeoData 规则库下载并校验成功！"
    else
        echo -e "${ERR} GeoData 下载失败（连续 $max_retries 次均损坏），安装终止。"
        rm -f "$tmp_ip" "$tmp_site"
        exit 1
    fi

    _install_geodata_updater "$share_dir" "$url_ip" "$url_site"
}

# ─── 核心组件安装入口 ────────────────────────
core_install() {
    echo -e "\n${CYAN}--- 2. 核心组件 (Core) ---${PLAIN}"

    # ─── APT 环境准备 ────────────────────────
    export DEBIAN_FRONTEND=noninteractive
    mkdir -p /etc/needrestart/conf.d
    echo "\$nrconf{restart} = 'a';" > /etc/needrestart/conf.d/99-xray-auto.conf
    rm -f /var/lib/apt/lists/lock /var/cache/apt/archives/lock /var/lib/dpkg/lock*

    execute_task \
        "apt-get update -qq && DEBIAN_FRONTEND=noninteractive apt-get -y \
         -o Dpkg::Options::='--force-confdef' \
         -o Dpkg::Options::='--force-confold' upgrade" \
        "系统更新与升级" || { echo -e "${ERR} 系统更新失败，安装终止。"; exit 1; }

    # ─── 依赖检查与安装 ──────────────────────
    local DEPENDENCIES=("curl" "wget" "tar" "unzip" "fail2ban" "rsyslog" "chrony"
                        "iptables" "iptables-persistent" "qrencode" "jq" "cron"
                        "python3-systemd" "lsof")
    local MISSING_PKGS=()

    echo -ne "${INFO} 正在检查系统依赖..."
    for pkg in "${DEPENDENCIES[@]}"; do
        if ! dpkg -s "$pkg" &>/dev/null; then
            MISSING_PKGS+=("$pkg")
        fi
    done
    echo -e "\r\033[K${OK} 系统依赖检查完成"

    if [ ${#MISSING_PKGS[@]} -gt 0 ]; then
        for pkg in "${MISSING_PKGS[@]}"; do
            if ! execute_task "apt-get install -y $pkg" "安装依赖组件: $pkg"; then
                apt-get update -qq --fix-missing
                execute_task "apt-get install -y $pkg" "重试安装依赖: $pkg" \
                    || { echo -e "${ERR} 依赖 $pkg 安装失败，安装终止。"; exit 1; }
            fi
        done
    else
        echo -e "       └─ ${GREEN}所有依赖已就绪，跳过安装。${PLAIN}"
    fi

    # ─── Xray 与 GeoData 安装 ────────────────
    install_xray_robust
    install_geodata_robust

    echo -e "${INFO} ${GREEN}核心组件部署完成。${PLAIN}"
}
