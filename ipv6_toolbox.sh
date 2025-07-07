#!/bin/bash

# ================================================================= #
#                 Euserv (德鸡) 终极工具箱 v2.4 (最终版)            #
#                                                                 #
#               总设计师: Gemini & 首席指挥官: 張財多             #
#                                                                 #
#   更新: 安装 Navidrome 后增加明确的音乐上传路径指引。            #
# ================================================================= #

# --- 颜色定义 ---
GREEN="\033[32m"; YELLOW="\033[33m"; RED="\033[31m"; BLUE="\033[34m"; NC="\033[0m"

# --- 检查是否为 root 用户 ---
if [ "$(id -u)" -ne 0 ]; then
   echo -e "${RED}错误：该脚本必须以 root 用户身份运行！${NC}" 1>&2; exit 1
fi

# --- 安装状态标记文件 ---
STATE_DIR="/root/.euserv_toolbox_state"
mkdir -p "$STATE_DIR"

# --- 各功能安装检测函数 ---
is_nginx_installed() { dpkg -s nginx &> /dev/null; }
is_wordpress_installed() { [ -f "${STATE_DIR}/wordpress_installed" ]; }
is_memos_installed() { [ -f "/etc/systemd/system/memos.service" ]; }
is_navidrome_installed() { [ -f "/etc/systemd/system/navidrome.service" ]; }
is_fail2ban_installed() { dpkg -s fail2ban &> /dev/null; }
is_warp_installed() { [ -f "${STATE_DIR}/warp_installed" ]; }
is_argo_installed() { [ -f "${STATE_DIR}/argo_installed" ]; }

# --- 各功能卸载函数 ---
uninstall_wordpress() {
    echo -e "${YELLOW}开始卸载 WordPress...${NC}"
    if ! is_wordpress_installed; then echo "${RED}WordPress 未安装。${NC}"; return; fi
    WP_DOMAIN=$(cat "${STATE_DIR}/wordpress_installed")
    rm -f "/etc/nginx/sites-enabled/${WP_DOMAIN}"
    rm -f "/etc/nginx/sites-available/${WP_DOMAIN}"
    certbot delete --cert-name "${WP_DOMAIN}" --non-interactive
    systemctl reload nginx
    rm -rf "/var/www/${WP_DOMAIN}"
    if [ -f "${STATE_DIR}/db_root_password" ]; then
        DB_ROOT_PASSWORD=$(cat "${STATE_DIR}/db_root_password")
        mysql -u root -p"$DB_ROOT_PASSWORD" -e "DROP DATABASE IF EXISTS wordpress;"
        mysql -u root -p"$DB_ROOT_PASSWORD" -e "DROP USER IF EXISTS 'wp_user'@'localhost';"
    fi
    rm -f "${STATE_DIR}/wordpress_installed" "${STATE_DIR}/db_root_password"
    echo -e "${GREEN}WordPress 卸载完成！${NC}"
}

uninstall_memos() {
    echo -e "${YELLOW}开始卸载 Memos...${NC}"
    systemctl stop memos &>/dev/null
    systemctl disable memos &>/dev/null
    rm -f /etc/systemd/system/memos.service
    rm -f /usr/local/bin/memos
    rm -rf /var/opt/memos
    systemctl daemon-reload
    echo -e "${GREEN}Memos 卸载完成！${NC}"
}

uninstall_fail2ban() {
    echo -e "${YELLOW}开始卸载 Fail2ban...${NC}"
    systemctl stop fail2ban &>/dev/null
    systemctl disable fail2ban &>/dev/null
    apt-get purge -y fail2ban &>/dev/null
    rm -f /etc/fail2ban/jail.local
    echo -e "${GREEN}Fail2ban 卸载完成！${NC}"
}

uninstall_navidrome() {
    echo -e "${RED}=========================== 警告！ ==========================${NC}"
    echo -e "${YELLOW}您即将从服务器上彻底卸载 Navidrome。${NC}"
    read -p "您确定要继续吗? (输入 'yes' 确认): " CONFIRM
    if [ "$CONFIRM" != "yes" ]; then
        echo -e "${GREEN}操作已取消。${NC}"; return
    fi

    echo -e "${YELLOW}>>> 正在停止并禁用 Navidrome 服务...${NC}"
    systemctl stop navidrome &>/dev/null
    systemctl disable navidrome &>/dev/null

    echo -e "${YELLOW}>>> 正在删除程序文件和服务文件...${NC}"
    rm -f /etc/systemd/system/navidrome.service
    systemctl daemon-reload
    rm -f /opt/navidrome-bin

    echo -e "${RED}======================== 核弹级操作确认！========================${NC}"
    echo -e "${YELLOW}您是否要彻底删除 Navidrome 的所有数据和音乐文件？${NC}"
    echo -e "${RED}警告：此操作将删除 /var/lib/navidrome 目录！${NC}"
    read -p "请再次确认，是否删除所有数据和音乐？ (输入 'yes' 确认): " DELETE_DATA
    if [ "$DELETE_DATA" == "yes" ]; then
        echo -e "${YELLOW}>>> 正在执行数据和音乐的湮灭程序...${NC}"
        rm -rf /var/lib/navidrome
        echo -e "${GREEN}所有数据和音乐已抹除。${NC}"
    else
        echo -e "${YELLOW}>>> 已跳过删除数据和音乐的步骤。${NC}"
    fi
    
    echo -e "${YELLOW}>>> 正在删除 navidrome 专用用户...${NC}"
    userdel navidrome &>/dev/null || echo -e "${YELLOW}用户 navidrome 未找到，已跳过。${NC}"

    rm -f "${STATE_DIR}/navidrome_installed"
    echo -e "${GREEN}✨ Navidrome 善后工作已完成！${NC}"
    echo -e "${BLUE}提示：请记得使用 Nginx 管家手动删除为此应用添加的反向代理配置。${NC}"
}

# --- 各功能安装函数 ---
install_nginx_manager() {
    set -e
    BASE_DOMAIN_FILE="/root/.nginx_manager_domain"
    if [ -f "$BASE_DOMAIN_FILE" ]; then
        BASE_DOMAIN=$(cat "$BASE_DOMAIN_FILE")
        echo -e "${YELLOW}检测到已配置的主域名: ${GREEN}${BASE_DOMAIN}${NC}"
        read -p "是否使用此域名? (Y/n): " use_existing_domain
        if [[ "$use_existing_domain" =~ ^[nN]$ ]]; then rm "$BASE_DOMAIN_FILE"; fi
    fi

    if [ ! -f "$BASE_DOMAIN_FILE" ]; then
        read -p "请输入你的主域名 (例如: zhangcaiduo.com): " BASE_DOMAIN
        if [ -z "$BASE_DOMAIN" ]; then echo -e "${RED}错误：主域名不能为空！${NC}"; return 1; fi
        echo "$BASE_DOMAIN" > "$BASE_DOMAIN_FILE"
    fi

    read -p "请输入要添加的【子域名】部分 (例如: memos): " SUBDOMAIN
    if [ -z "$SUBDOMAIN" ]; then echo -e "${RED}错误：子域名不能为空！${NC}"; return 1; fi
    FULL_DOMAIN="${SUBDOMAIN}.${BASE_DOMAIN}"

    read -p "请输入后端应用的【IP和端口】 (例如: http://localhost:5230): " BACKEND_URL
    if [ -z "$BACKEND_URL" ]; then echo -e "${RED}错误：后端地址不能为空！${NC}"; return 1; fi
    
    CONF_FILE="/etc/nginx/sites-available/${FULL_DOMAIN}"
    if [ -f "$CONF_FILE" ]; then echo -e "${RED}错误：该域名 (${FULL_DOMAIN}) 的配置文件已存在！${NC}"; return 1; fi

    echo -e "${YELLOW}>>> 正在生成 Nginx 配置文件...${NC}"
    cat > "$CONF_FILE" <<EOF
server {
    listen 80; listen [::]:80;
    server_name ${FULL_DOMAIN};
    location / {
        proxy_pass ${BACKEND_URL};
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
    }
}
EOF
    ln -s -f "$CONF_FILE" /etc/nginx/sites-enabled/
    
    echo -e "${YELLOW}>>> 正在测试 Nginx 配置并申请 SSL 证书...${NC}"
    if ! nginx -t; then
        echo -e "${RED}错误：Nginx 配置测试失败！正在回滚...${NC}"
        rm -f "$CONF_FILE" "/etc/nginx/sites-enabled/${FULL_DOMAIN}"
        return 1
    fi
    
    certbot --nginx -d "${FULL_DOMAIN}" --redirect --agree-tos --no-eff-email --non-interactive
    if [ $? -ne 0 ]; then
        echo -e "${RED}错误：SSL 证书申请失败！请检查DNS解析。正在回滚...${NC}"
        rm -f "$CONF_FILE" "/etc/nginx/sites-enabled/${FULL_DOMAIN}"
        systemctl restart nginx
        return 1
    fi

    systemctl restart nginx
    echo -e "${GREEN}✨ 恭喜！反向代理部署完成！ ✨${NC}"
    echo -e "您的新应用现在可以通过: ${BLUE}https://${FULL_DOMAIN}${NC} 安全访问"
    set +e
}

install_wordpress() {
    set -e
    read -p "请输入您要用于 WordPress 的【完整域名】: " WP_DOMAIN
    if [ -z "$WP_DOMAIN" ]; then echo -e "${RED}错误：域名不能为空！${NC}"; return 1; fi

    echo -e "${YELLOW}>>> 步骤 1/5: 安装依赖...${NC}"
    apt-get update && apt-get install -y nginx mariadb-server php-fpm php-mysql php-curl php-gd php-mbstring php-xml php-xmlrpc php-zip wget unzip certbot python3-certbot-nginx openssl
    
    echo -e "${YELLOW}>>> 步骤 2/5: 配置数据库...${NC}"
    DB_ROOT_PASSWORD=$(openssl rand -hex 12)
    DB_USER_PASSWORD=$(openssl rand -hex 12)
    systemctl start mariadb && systemctl enable mariadb
    mysql -e "SET PASSWORD FOR 'root'@'localhost' = PASSWORD('$DB_ROOT_PASSWORD');"
    mysql -e "CREATE DATABASE wordpress CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;"
    mysql -e "CREATE USER 'wp_user'@'localhost' IDENTIFIED BY '$DB_USER_PASSWORD';"
    mysql -e "GRANT ALL PRIVILEGES ON wordpress.* TO 'wp_user'@'localhost';"
    mysql -e "FLUSH PRIVILEGES;"
    
    echo -e "${YELLOW}>>> 步骤 3/5: 配置 WordPress...${NC}"
    WP_DIR="/var/www/$WP_DOMAIN"
    mkdir -p "$WP_DIR" && cd "$WP_DIR"
    wget -q https://wordpress.org/latest.zip && unzip -o latest.zip && rm latest.zip
    mv wordpress/* . && rmdir wordpress
    chown -R www-data:www-data "$WP_DIR"
    cp wp-config-sample.php wp-config.php
    sed -i "s/database_name_here/wordpress/" wp-config.php
    sed -i "s/username_here/wp_user/" wp-config.php
    sed -i "s/password_here/$DB_USER_PASSWORD/" wp-config.php
    SALT=$(curl -sL https://api.wordpress.org/secret-key/1.1/salt/)
    printf '%s\n' "define('FS_METHOD', 'direct');" >> wp-config.php
    printf '%s\n' "$SALT" >> wp-config.php
    
    echo -e "${YELLOW}>>> 步骤 4/5: 配置 Nginx & SSL...${NC}"
    NGINX_CONF="/etc/nginx/sites-available/$WP_DOMAIN"
    cat > "$NGINX_CONF" <<EOF
server {
    listen 80; listen [::]:80;
    server_name $WP_DOMAIN;
    root /var/www/$WP_DOMAIN;
    index index.php;
    location / { try_files \$uri \$uri/ /index.php?\$args; }
    location ~ \.php$ { include snippets/fastcgi-php.conf; fastcgi_pass unix:/var/run/php/php8.2-fpm.sock; }
}
EOF
    ln -s -f "$NGINX_CONF" /etc/nginx/sites-enabled/
    nginx -t && systemctl restart nginx
    certbot --nginx -d "$WP_DOMAIN" --redirect --agree-tos --no-eff-email --non-interactive
    
    echo -e "${YELLOW}>>> 步骤 5/5: 重启服务...${NC}"
    systemctl restart nginx php8.2-fpm
    
    echo "$WP_DOMAIN" > "${STATE_DIR}/wordpress_installed"
    echo "$DB_ROOT_PASSWORD" > "${STATE_DIR}/db_root_password"

    echo -e "${GREEN}✨✨✨ 恭喜！WordPress 部署完成！ ✨✨✨${NC}"
    echo -e "请访问: ${BLUE}https://${WP_DOMAIN}${NC}"
    echo -e "数据库用户名: ${GREEN}wp_user${NC} | 数据库用户密码: ${GREEN}$DB_USER_PASSWORD${NC}"
    set +e
}

install_memos() {
    set -e
    echo -e "${YELLOW}>>> 正在从 GitHub 下载最新版 Memos...${NC}"
    LATEST_VERSION=$(curl -s "https://api.github.com/repos/usememos/memos/releases/latest" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
    wget -O /tmp/memos.tar.gz "https://github.com/usememos/memos/releases/download/${LATEST_VERSION}/memos_${LATEST_VERSION:1}_linux_amd64.tar.gz"
    tar -xzf /tmp/memos.tar.gz -C /usr/local/bin/
    mkdir -p /var/opt/memos && rm /tmp/memos.tar.gz
    
    echo -e "${YELLOW}>>> 正在创建 systemd 服务...${NC}"
    cat > /etc/systemd/system/memos.service <<EOF
[Unit]
Description=Memos
After=network.target
[Service]
ExecStart=/usr/local/bin/memos --mode prod --port 5230 --data /var/opt/memos
Restart=always
User=root
[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload && systemctl enable memos && systemctl start memos
    
    if systemctl is-active --quiet memos; then
        echo -e "${GREEN}恭喜！Memos 已成功部署！监听于: ${YELLOW}http://<你的服务器IP>:5230${NC}"
    else
        echo -e "${RED}部署失败！${NC}"
    fi
    set +e
}

install_navidrome() {
    set -e
    read -p "请输入您要创建的 Navidrome 【管理员用户名】: " ND_USER
    if [ -z "$ND_USER" ]; then echo -e "${RED}错误：管理员用户名不能为空！${NC}"; return 1; fi

    echo -e "${YELLOW}>>> 正在安装依赖 (ffmpeg, wget)...${NC}"
    apt-get update && apt-get install -y ffmpeg wget tar

    echo -e "${YELLOW}>>> 正在下载并安装 Navidrome...${NC}"
    LATEST_URL=$(curl -s https://api.github.com/repos/navidrome/navidrome/releases/latest | grep "browser_download_url.*_linux_amd64.tar.gz" | cut -d '"' -f 4)
    id -u navidrome &>/dev/null || useradd -r -s /bin/false navidrome
    DATA_DIR="/var/lib/navidrome"
    MUSIC_DIR="/var/lib/navidrome/music"
    mkdir -p "$DATA_DIR"; mkdir -p "$MUSIC_DIR"
    chown -R navidrome:navidrome "$DATA_DIR"
    cd /opt
    wget -q -O navidrome.tar.gz "$LATEST_URL"
    tar -xzf navidrome.tar.gz && rm navidrome.tar.gz
    mv navidrome navidrome-bin
    
    cat > "$DATA_DIR/navidrome.toml" <<EOF
MusicFolder = "$MUSIC_DIR"
DataFolder = "$DATA_DIR"
Port = 4533
Address = "127.0.0.1"
EOF
    chown navidrome:navidrome "$DATA_DIR/navidrome.toml"
    
    echo -e "${YELLOW}>>> 正在创建系统服务...${NC}"
    cat > /etc/systemd/system/navidrome.service <<EOF
[Unit]
Description=Navidrome Music Server
After=network.target
[Service]
User=navidrome
Group=navidrome
Type=simple
ExecStart=/opt/navidrome-bin --configfile "$DATA_DIR/navidrome.toml"
Restart=always
[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload && systemctl enable --now navidrome
    
    touch "${STATE_DIR}/navidrome_installed"
    echo -e "${GREEN}====================================================================${NC}"
    echo -e "${GREEN}      ✨ 神兽已就位！Navidrome 核心引擎安装成功！ ✨         ${NC}"
    echo -e "${GREEN}====================================================================${NC}"
    echo -e "Navidrome 正在后台运行，监听于: ${BLUE}http://localhost:4533${NC}"
    echo ""
    echo -e "${BLUE}===================== 后续操作提醒 =====================${NC}"
    echo -e "请使用菜单中的【Nginx 反向代理管家】为它配置域名。"
    echo -e "然后，您可以退出本脚本，并执行以下命令进入音乐文件夹："
    echo -e "${YELLOW}cd /var/lib/navidrome/music${NC}"
    echo -e "最后，使用您喜欢的 SSH 工具 (如 FinalShell, Xshell 等) 将音乐文件上传到此目录。"
    echo -e "${BLUE}========================================================${NC}"
    set +e
}

install_fail2ban() {
    set -e
    read -p "请输入您自己电脑的公网IP (用于白名单，可留空): " user_ip
    apt-get update && apt-get install -y fail2ban
    cat > /etc/fail2ban/jail.local <<EOF
[DEFAULT]
bantime = 2h
findtime = 10m
maxretry = 5
backend = systemd
ignoreip = 127.0.0.1/8 ::1 ${user_ip}
[sshd]
enabled = true
EOF
    systemctl restart fail2ban && systemctl enable fail2ban
    echo -e "${GREEN}🎉 Fail2ban 已上线！${NC}"
    set +e
}

install_warp() {
    wget -N https://gitlab.com/fscarmen/warp/-/raw/main/menu.sh && bash menu.sh
    read -p "WARP 脚本是否已成功执行并安装？(y/n): " installed
    if [[ "$installed" =~ ^[yY]$ ]]; then
        touch "${STATE_DIR}/warp_installed"
    else
        rm -f "${STATE_DIR}/warp_installed"
    fi
}

install_argo() {
    bash <(wget -qO- https://raw.githubusercontent.com/fscarmen/argox/main/argox.sh)
    read -p "Argo 脚本是否已成功执行并安装？(y/n): " installed
    if [[ "$installed" =~ ^[yY]$ ]]; then
        touch "${STATE_DIR}/argo_installed"
    else
        rm -f "${STATE_DIR}/argo_installed"
    fi
}

# --- 主菜单 ---
show_menu() {
    clear
    cat << "EOT"


    ██╗██████╗ ██╗   ██╗ ██████╗     ██╗   ██╗██████╗ ███████╗
    ██║██╔══██╗██║   ██║██╔════╝     ██║   ██║██╔══██╗██╔════╝
    ██║██████╔╝██║   ██║███████╗     ██║   ██║██████╔╝███████╗
    ██║██╔═══╝ ╚██╗ ██╔╝██╔═══██╗    ╚██╗ ██╔╝██╔═══╝ ╚════██║
    ██║██║      ╚████╔╝ ╚██████╔╝     ╚████╔╝ ██║     ███████║
    ╚═╝╚═╝       ╚═══╝   ╚═════╝       ╚═══╝  ╚═╝     ╚══════╝

EOT
    echo -e "${GREEN}============ VPS 从毛坯房开始装修VPS 包工头面板 v6.6.6 ============================================${NC}"
    echo -e "${BLUE}本脚本是包工头面板的子选项，适用于各种 IPV6 免费小鸡的常用项目部署 ${NC}"
    echo -e "${BLUE}如果您退出了装修面板，输入 zhangcaiduo 可再次调出 ${NC}"
    echo -e "${BLUE}本脚本是小白学习的总结，不做任何商业用途和盈利，感谢 Gemini 地球之神的全局帮助。${NC}"
    echo -e "${GREEN}===================================================================================================${NC}"

    echo -e "${YELLOW}请选择要执行的操作:${NC}"
    
    is_nginx_installed && echo -e "  ${GREEN}1) ✅ 打开 Nginx 反向代理管家${NC}" || echo -e "  ${GREEN}1)${NC}  安装 Nginx 并打开反代管家"
    is_navidrome_installed && echo -e "  ${GREEN}2) ✅ 卸载 Navidrome 音乐服务器${NC}" || echo -e "  ${GREEN}2)${NC}  一键部署 Navidrome 音乐服务器"
    is_wordpress_installed && echo -e "  ${GREEN}3) ✅ 卸载 WordPress 博客${NC}" || echo -e "  ${GREEN}3)${NC}  一键部署 WordPress 博客"
    is_memos_installed && echo -e "  ${GREEN}4) ✅ 卸载 Memos 微博客${NC}" || echo -e "  ${GREEN}4)${NC}  一键部署 Memos 微博客"
    is_fail2ban_installed && echo -e "  ${GREEN}5) ✅ 卸载 Fail2ban 安全防护${NC}" || echo -e "  ${GREEN}5)${NC}  安装 Fail2ban 安全防护"
    
    echo -e "  ---"
    
    is_warp_installed && status_warp="✅ 管理/卸载" || status_warp="安装"
    echo -e "  ${GREEN}6)${NC}  ${status_warp} WARP 网络接口"
    echo -e "     ${BLUE}(免责声明: 感谢 fscarmen。本功能仅供学习，请遵守当地法律法规)${NC}"

    is_argo_installed && status_argo="✅ 管理/卸载" || status_argo="安装"
    echo -e "  ${GREEN}7)${NC}  ${status_argo} Argo Tunnel 隧道"
    echo -e "     ${BLUE}(免责声明: 感谢 fscarmen。本功能仅供学习，请遵守当地法律法规)${NC}"

    echo -e ""
    echo -e "  ${RED}0) 退出脚本${NC}"
    echo -e "${GREEN}====================================================================${NC}"
}

# --- 主循环 ---
while true; do
    show_menu
    read -p "请输入选项 [0-7]: " choice

    case $choice in
        1) if ! is_nginx_installed; then apt-get update && apt-get install -y nginx certbot python3-certbot-nginx; fi; install_nginx_manager ;;
        2) if is_navidrome_installed; then uninstall_navidrome; else install_navidrome; fi ;;
        3) if is_wordpress_installed; then read -p "确定卸载？[y/N]: " c && [[ $c == [yY] ]] && uninstall_wordpress; else install_wordpress; fi ;;
        4) if is_memos_installed; then read -p "确定卸载？[y/N]: " c && [[ $c == [yY] ]] && uninstall_memos; else install_memos; fi ;;
        5) if is_fail2ban_installed; then read -p "确定卸载？[y/N]: " c && [[ $c == [yY] ]] && uninstall_fail2ban; else install_fail2ban; fi ;;
        6) install_warp ;;
        7) install_argo ;;
        0) echo -e "${BLUE}感谢使用！指挥官再见！${NC}"; exit 0 ;;
        *) echo -e "${RED}无效输入...${NC}" ;;
    esac
    echo ""; read -p "按 [Enter] 键返回主菜单..."
done
