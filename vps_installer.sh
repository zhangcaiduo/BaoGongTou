#!/bin/bash
#================================================================
# “    VPS 从零开始装修面板    ” v7.3.0 -    写入性能终极优化版
#    1.   优化 Rclone 挂载参数，将 --vfs-cache-mode 改为 full，大幅提升下载写入稳定性和性能。
#    2.   在主菜单和关联操作后增加清晰的应用内路径设置指引，防止用户混淆。
#    3.   修复下载器路径关联的逻辑 Bug，确保每个下载器都能被独立正确地配置。
#     作者     : 張財多 zhangcaiduo.com
#================================================================

# ---     全局函数与配置     ---

STATE_FILE="/root/.vps_setup_credentials" #     用于存储密码的凭证文件
RCLONE_CONFIG_FILE="/root/.config/rclone/rclone.conf"
RCLONE_LOG_FILE="/var/log/rclone.log"
GREEN=''
BLUE=''
RED=''
YELLOW=''
CYAN=''
NC=''

# ---     首次运行自安装快捷命令  ---
if [[ "$0" != "bash" && "$0" != "sh" ]]; then
    SCRIPT_PATH=$(realpath "$0")
    LINK_PATH="/usr/local/bin/zhangcaiduo"
    if [[ -n "$SCRIPT_PATH" ]] && { [ ! -L "${LINK_PATH}" ] || [ "$(readlink -f ${LINK_PATH})" != "${SCRIPT_PATH}" ]; }; then
        echo -e "${GREEN} 为方便您使用，正在创建快捷命令 'zhangcaiduo'...${NC}"
        chmod +x "${SCRIPT_PATH}"
        sudo ln -sf "${SCRIPT_PATH}" "${LINK_PATH}"
        if [ $? -eq 0 ]; then
            echo -e "${GREEN} 快捷命令创建成功！请重新登录 SSH 后，或在新的终端会话中，输入 'zhangcaiduo' 即可启动此面板。 ${NC}"
        else
            echo -e "${RED} 快捷命令创建失败。您仍需使用 'bash ${SCRIPT_PATH}' 来运行。 ${NC}"
        fi
        sleep 4
    fi
fi

# ---     核心环境检查函数 (v7.1.0 新增) ---
ensure_docker_installed() {
    if ! command -v docker &> /dev/null || ! command -v docker-compose &> /dev/null; then
        echo -e "${YELLOW}--- 检查到 Docker 或 Docker-Compose 未安装，现在开始自动安装 ---${NC}"
        sleep 2
        sudo apt-get update
        sudo apt-get install -y ca-certificates curl gnupg
        if ! command -v docker &> /dev/null; then
            echo -e "${YELLOW} 正在安装 Docker Engine...${NC}"
            curl -fsSL https://get.docker.com -o get-docker.sh
            sudo sh get-docker.sh && rm get-docker.sh
            sudo systemctl restart docker
            sudo systemctl enable docker
        fi
        if ! command -v docker-compose &> /dev/null; then
            echo -e "${YELLOW} 正在安装 Docker-Compose...${NC}"
            sudo curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
            sudo chmod +x /usr/local/bin/docker-compose
        fi
        if ! command -v docker &> /dev/null || ! command -v docker-compose &> /dev/null; then
            echo -e "${RED} 错误：Docker 环境自动安装失败，请检查网络或手动安装后重试。${NC}"
            sleep 5
            return 1
        else
            echo -e "${GREEN}✅ Docker 环境已成功安装并准备就绪！${NC}"
            sleep 2
        fi
    fi

    # 确保 Docker 服务正在运行
    if ! sudo docker info >/dev/null 2>&1; then
        echo -e "${YELLOW}检测到 Docker 服务未运行，正在尝试启动...${NC}"
        sudo systemctl start docker
        sleep 3
        if ! sudo docker info >/dev/null 2>&1; then
            echo -e "${RED}错误：无法启动 Docker 服务！请手动检查 'sudo systemctl status docker'。${NC}"
            return 1
        fi
        echo -e "${GREEN}✅ Docker 服务已成功启动！${NC}"
    fi
    return 0
}

# ---     系统更新函数  ---
update_system() {
    clear
    echo -e "${BLUE}---  更新系统与软件  (apt update && upgrade) ---${NC}"
    echo -e "${YELLOW} 即将开始更新系统软件包列表并升级所有已安装的软件 ...${NC}"
    sudo apt-get update && sudo apt-get upgrade -y
    echo -e "\n${GREEN} ✅  系统更新完成！ ${NC}"
    echo -e "\n${GREEN} 按任意键返回主菜单 ...${NC}"; read -n 1 -s
}

run_unminimize() {
    clear
    echo -e "${BLUE}---  恢复至标准系统  (unminimize) ---${NC}"
    if grep -q -i "ubuntu" /etc/os-release; then
        echo -e "${YELLOW} 此操作将为您的最小化 Ubuntu 系统安装完整的标准系统包。 ${NC}"
        echo -e "${YELLOW} 它会增加一些磁盘占用，但可以解决某些软件的兼容性问题。 ${NC}"
        read -p " 您确定要继续吗？  (y/n): " confirm
        if [[ "$confirm" == "y" || "$confirm" == "Y" ]]; then
            echo -e "${GREEN} 正在执行 unminimize ，请稍候 ...${NC}"
            sudo unminimize
            echo -e "\n${GREEN} ✅  操作完成！ ${NC}"
        else
            echo -e "${GREEN} 操作已取消。 ${NC}"
        fi
    else
        echo -e "${RED} 此功能专为 Ubuntu 系统设计，您当前的系统似乎不是 Ubuntu 。 ${NC}"
    fi
    echo -e "\n${GREEN} 按任意键返回主菜单 ...${NC}"; read -n 1 -s
}

manage_swap() {
    clear
    echo -e "${BLUE}---  配置虚拟内存 (Swap) ---${NC}"
    if swapon --show | grep -q '/swapfile'; then
        echo -e "${YELLOW} 检测到已存在 /swapfile 虚拟内存。${NC}"
        read -p " 您想移除现有的虚拟内存吗? (y/n): " confirm_remove
        if [[ "$confirm_remove" == "y" || "$confirm_remove" == "Y" ]]; then
            echo -e "${YELLOW} 正在停止并移除虚拟内存...${NC}"
            sudo swapoff /swapfile
            sudo sed -i '/\/swapfile/d' /etc/fstab
            sudo rm -f /swapfile
            echo -e "${GREEN} ✅  虚拟内存已成功移除！${NC}"
            free -h
        else
            echo -e "${GREEN} 操作已取消。${NC}"
        fi
    else
        echo -e "${YELLOW} 未检测到虚拟内存。现在为您创建。${NC}"
        read -p " 请输入您期望的 Swap 大小 (例如: 4G, 8G, 10G) [建议为内存的1-2倍]: " swap_size
        if [ -z "$swap_size" ]; then
            echo -e "${RED} 输入为空，操作取消。${NC}"; sleep 2; return
        fi
        echo -e "${YELLOW} 🚀  [1/5] 正在创建 ${swap_size} 大小的交换文件...${NC}"
        sudo fallocate -l ${swap_size} /swapfile
        echo -e "${YELLOW} 🚀  [2/5] 正在设置文件权限...${NC}"
        sudo chmod 600 /swapfile
        echo -e "${YELLOW} 🚀  [3/5] 正在将文件格式化为 Swap...${NC}"
        sudo mkswap /swapfile
        echo -e "${YELLOW} 🚀  [4/5] 正在启用 Swap 文件...${NC}"
        sudo swapon /swapfile
        echo -e "${YELLOW} 🚀  [5/5] 正在设置开机自动挂载...${NC}"
        if ! grep -q "/swapfile" /etc/fstab; then
            sudo cp /etc/fstab /etc/fstab.bak
            echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab
        fi
        echo -e "\n${GREEN} ✅  虚拟内存创建并启用成功！${NC}"
        echo -e "${CYAN} 当前内存和虚拟内存状态:${NC}"
        free -h
    fi
    echo -e "\n${GREEN} 按任意键返回主菜单 ...${NC}"; read -n 1 -s
}


# ---     检查与菜单显示函数 (Tab对齐重构) ---
check_and_display() {
    local option_num="$1"
    local text="$2"
    local check_path="$3"
    local status_info="$4"
    local display_text="${option_num}) ${text}"
    local status_string="[ ❌  未安装 ]"

    if [ -e "$check_path" ]; then
        local type=$(echo "$status_info" | cut -d':' -f1)
        local details=$(echo "$status_info" | cut -d':' -f2-)
        local formatted_details=""
        case "$type" in
            docker)
                local container_name=$(echo "$details" | cut -d':' -f1); local port=$(echo "$details" | cut -d':' -f2)
                formatted_details=" 容器:${container_name}, 端口:${port}"
                ;;
            docker_nopm) formatted_details=" 容器:${details} (已接入总线)";;
            system) formatted_details=" 系统服务 ";;
            system_port) formatted_details=" 服务端口: ${details}";;
            rclone)
                if grep -q "RCLONE_REMOTE" "${STATE_FILE}"; then
                    local remote_name=$(grep "RCLONE_REMOTE" "${STATE_FILE}" | cut -d'=' -f2)
                    formatted_details=" 已配置: ${remote_name} "
                else
                    formatted_details=" 已配置 "
                fi
                display_text="${GREEN}${option_num}) ${text}${NC}";;
            *) formatted_details=" 已安装 ";;
        esac
        status_string="[ ✅ ${formatted_details}]"
    fi
    # 使用 Tab 进行对齐
    printf "  %-48s\t%s\n" "${display_text}" "${status_string}"
}

show_main_menu() {
    clear
    echo -e "
   ███████╗██╗  ██╗ █████╗ ███╗   ██╗ ██████╗  ██████╗ █████╗ ██╗██████╗ ██╗   ██╗ ██████╗ 
   ╚══███╔╝██║  ██║██╔══██╗████╗  ██║██╔════╝ ██╔════╝██╔══██╗██║██╔══██╗██║   ██║██╔═══██╗
     ███╔╝ ███████║███████║██╔██╗ ██║██║  ███╗██║     ███████║██║██║  ██║██║   ██║██║   ██║
    ███╔╝  ██╔══██║██╔══██║██║╚██╗██║██║   ██║██║     ██╔══██║██║██║  ██║██║   ██║██║   ██║
   ███████╗██║  ██║██║  ██║██║ ╚████║╚██████╔╝╚██████╗██║  ██║██║██████╔╝╚██████╔╝╚██████╔╝
   ╚══════╝╚═╝  ╚═╝╚═╝  ╚═╝╚═╝  ╚═══╝ ╚═════╝  ╚═════╝╚═╝  ╚═╝╚═╝╚═════╝  ╚═════╝  ╚═════╝ 
                                           zhangcaiduo.com
"

    echo -e "${GREEN}============ VPS 从毛坯房开始装修VPS 包工头面板 v7.3.0 ============================================${NC}"
    echo -e "${BLUE}本脚本适用于 Ubuntu 和 Debian 系统的 VPS 常用项目部署 ${NC}"
    echo -e "${BLUE}如果您退出了装修面板，输入 zhangcaiduo 可再次调出 ${NC}"
    echo -e "${BLUE}=========================================================================================${NC}"

    echo -e "  ${GREEN}---  地基与系统 (基础)  ---${NC}"
    printf "  %-48s\t%s\n" "u)  更新系统与软件" "[ apt update && upgrade ]"
    printf "  %-48s\t%s\n" "m)  恢复至标准系统" "[ unminimize, 仅限 Ubuntu 系统 ]"
    printf "  %-48s\t%s\n" "s)  配置虚拟内存 (Swap)" "[ 增强低配VPS性能 ]"
    echo -e "  ----------------------------------------------------------------------------------------"
    echo ""
    echo -e "  ${GREEN}---  主体装修选项 (应用部署)  ---${NC}"
    check_and_display "1" "部署网络水电总管 (NPM)" "/root/npm_data" "docker:npm_app:81"
    echo -e "      ${YELLOW}首次登陆 NPM 请用你的IP地址加:端口81，默认用户: admin@example.com 密码: changeme${NC}"
    echo -e "      ${YELLOW}首次登陆后请立即修改密码！配置教程请参考我的博客。${NC}"
    echo ""
    check_and_display "2" "部署 Nextcloud 家庭数据中心" "/root/nextcloud_data" "docker_nopm:nextcloud_app"
    check_and_display "3" "部署 WordPress 个人博客" "/root/wordpress_data" "docker_nopm:wordpress_app"
    check_and_display "4" "部署 AI 大脑 (Ollama+WebUI)" "/root/ai_stack" "docker_nopm:open_webui_app"
    echo ""
    check_and_display "5" "部署 Jellyfin 家庭影院" "/root/jellyfin_data" "docker:jellyfin_app:8096"
    check_and_display "6" "部署 Navidrome 音乐服务器" "/root/navidrome_data" "docker:navidrome_app:4533"
    check_and_display "7" "部署 Alist 网盘挂载" "/root/alist_data" "docker:alist_app:5244"
    check_and_display "8" "部署 Gitea 代码仓库" "/root/gitea_data" "docker:gitea_app:3000"
    check_and_display "9" "部署 Memos 轻量笔记" "/root/memos_data" "docker:memos_app:5230"
    echo ""
    check_and_display "10" "部署 qBittorrent 下载器" "/root/qbittorrent_data" "docker:qbittorrent_app:8080"
    check_and_display "11" "部署 JDownloader 下载器" "/root/jdownloader_data" "docker:jdownloader_app:5800"
    check_and_display "12" "部署 yt-dlp 视频下载器" "/root/ytdlp_data" "docker_nopm:ytdlp_app"
    
    echo -e "      ${CYAN}注意: 关联Rclone后, 请确保在下载器WEB界面中, 保存路径为 /downloads 或 /output ${NC}"

    echo -e "  ${GREEN}---  安防与工具  ---${NC}"
    check_and_display "15" "部署全屋安防系统 (Fail2ban)" "/etc/fail2ban/jail.local" "system"
    check_and_display "16" "部署远程工作台 (Xfce)" "/etc/xrdp/xrdp.ini" "system_port:3389"
    check_and_display "17" "部署邮件管家 (自动报告)" "/etc/msmtprc" "system"
    check_and_display "18" "配置 Rclone 数据同步桥 (全盘跃迁)" "${RCLONE_CONFIG_FILE}" "rclone"

    echo -e "  ${GREEN}---  高级功能与维护  ---${NC}"
    printf "  %-48s\n" "21) 为 AI 大脑安装知识库 (安装模型)"
    printf "  %-48s\n" "22) 执行 Nextcloud 最终性能优化"
    printf "  %-48s\t%s\n" "23) ${CYAN}进入服务控制中心${NC}" "[ 启停/重启/关联Rclone ]"
    printf "  %-48s\t%s\n" "24) ${CYAN}查看密码与数据路径${NC}" "[ 重要凭证 ]"
    printf "  %-48s\t%s\n" "25) ${RED}打开“科学上网”工具箱${NC}" "[ Warp, Argo, OpenVPN ]"
    echo -e "  ----------------------------------------------------------------------------------------"
    printf "  %-48s\t%s\n" "99) ${RED}一键辞退包工头${NC}" "${RED}[ 注：此选项将会拆卸本脚本！！！ ]${NC}"
    printf "  %-48s\t%s\n" "q)  退出面板" ""
    echo -e "${GREEN}===================================================================================================${NC}"
}


# ---     前置检查     ---
check_npm_installed() {
    if [ ! -d "/root/npm_data" ]; then
        echo -e "${RED}     错误：此功能依赖“网络水电总管”，请先执行选项 1 进行安装！    ${NC}"
        sleep 3
        return 1
    fi
    return 0
}

# ---     部署与功能函数  ---

# 1. 网络水电总管 (NPM)
install_npm() {
    ensure_docker_installed || return
    clear
    echo -e "${BLUE}--- “网络水电总管”开始施工！ ---${NC}";
    echo -e "\n${YELLOW}     🚀     部署     NPM     并创建专属网络总线    ...${NC}"
    sudo docker network create npm_data_default || true
    mkdir -p /root/npm_data
    cat > /root/npm_data/docker-compose.yml <<'EOF'
services:
  app:
    image: 'jc21/nginx-proxy-manager:latest'
    container_name: npm_app
    restart: unless-stopped
    ports:
      - '80:80'
      - '443:443'
      - '81:81'
    volumes:
      - './data:/data'
      - './letsencrypt:/etc/letsencrypt'
    networks:
      - npm_network

networks:
  npm_network:
    name: npm_data_default
    external: true
EOF
    if (cd /root/npm_data && sudo docker-compose up -d); then
        echo -e "${GREEN}     ✅     网络水电总管 (NPM)     部署完毕！    ${NC}"
    else
        echo -e "${RED}     ❌     NPM 部署失败！请检查 Docker 是否正常运行。    ${NC}"
    fi
    echo -e "\n${GREEN}    按任意键返回主菜单    ...${NC}"; read -n 1 -s
}

# 2. Nextcloud     套件
install_nextcloud_suite() {
    ensure_docker_installed || return
    check_npm_installed || return
    read -p "    请输入您的主域名     (    例如     zhangcaiduo.com): " MAIN_DOMAIN
    if [ -z "$MAIN_DOMAIN" ]; then echo -e "${RED}     错误：主域名不能为空！    ${NC}"; sleep 2; return; fi

    NEXTCLOUD_DOMAIN="nextcloud.${MAIN_DOMAIN}"
    ONLYOFFICE_DOMAIN="onlyoffice.${MAIN_DOMAIN}"
    DB_PASSWORD="NcDb-pW_$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 12)"
    ONLYOFFICE_JWT_SECRET="JwtS3cr3t-$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 16)"

    clear
    echo -e "${BLUE}--- “Nextcloud 家庭数据中心”部署计划启动！ ---${NC}";
    
    mkdir -p /root/nextcloud_data
    cat > /root/nextcloud_data/docker-compose.yml <<EOF
services:
  db:
    image: mariadb:11.4
    container_name: nextcloud_db
    restart: unless-stopped
    command: [--transaction-isolation=READ-COMMITTED, --binlog-format=ROW, --character-set-server=utf8mb4, --collation-server=utf8mb4_unicode_ci]
    volumes:
      - './db:/var/lib/mysql'
    environment:
      MYSQL_DATABASE: nextclouddb
      MYSQL_USER: nextclouduser
      MYSQL_PASSWORD: ${DB_PASSWORD}
      MYSQL_ROOT_PASSWORD: ${DB_PASSWORD}_root
    networks:
      - npm_network
  
  redis:
    image: redis:alpine
    container_name: nextcloud_redis
    restart: unless-stopped
    networks:
      - npm_network

  app:
    image: nextcloud:latest
    container_name: nextcloud_app
    restart: unless-stopped
    volumes:
      - './html:/var/www/html'
      - './php-opcache.ini:/usr/local/etc/php/conf.d/opcache-recommended.ini'
    depends_on:
      - db
      - redis
    networks:
      - npm_network

networks:
  npm_network:
    name: npm_data_default
    external: true
EOF
    echo -e "opcache.memory_consumption=512\nopcache.interned_strings_buffer=16" > /root/nextcloud_data/php-opcache.ini
    if (cd /root/nextcloud_data && sudo docker-compose up -d); then
        echo -e "${GREEN}     ✅        数据中心主体     (Nextcloud)     启动完毕！    ${NC}"
    else
        echo -e "${RED}     ❌     Nextcloud 部署失败！请检查 Docker 是否正常运行。    ${NC}"; sleep 4; return
    fi

    mkdir -p /root/onlyoffice_data
    cat > /root/onlyoffice_data/docker-compose.yml <<EOF
services:
  onlyoffice:
    image: onlyoffice/documentserver:latest
    container_name: onlyoffice_app
    restart: always
    volumes:
      - './data:/var/www/onlyoffice/Data'
      - './logs:/var/log/onlyoffice'
    environment:
      JWT_ENABLED: 'true'
      JWT_SECRET: ${ONLYOFFICE_JWT_SECRET}
    networks:
      - npm_network

networks:
  npm_network:
    name: npm_data_default
    external: true
EOF
    if (cd /root/onlyoffice_data && sudo docker-compose up -d); then
        echo -e "${GREEN}     ✅        在线办公室     (OnlyOffice)     部署完毕！    ${NC}"
    else
        echo -e "${RED}     ❌     OnlyOffice 部署失败！请检查 Docker 是否正常运行。    ${NC}"; sleep 4; return
    fi

    echo "##     Nextcloud 套件凭证     (    部署于    : $(date))" > ${STATE_FILE}
    echo "NEXTCLOUD_DOMAIN=${NEXTCLOUD_DOMAIN}" >> ${STATE_FILE}
    echo "ONLYOFFICE_DOMAIN=${ONLYOFFICE_DOMAIN}" >> ${STATE_FILE}
    echo "DB_PASSWORD=${DB_PASSWORD}" >> ${STATE_FILE}
    echo "ONLYOFFICE_JWT_SECRET=${ONLYOFFICE_JWT_SECRET}" >> ${STATE_FILE}

    show_credentials
    echo -e "\n${GREEN}    所有后台任务已完成，按任意键返回主菜单    ...${NC}"; read -n 1 -s
}

# 3. WordPress
install_wordpress() {
    ensure_docker_installed || return
    check_npm_installed || return
    read -p "    请输入您的     WordPress     主域名     (    例如     zhangcaiduo.com): " WP_DOMAIN
    if [ -z "$WP_DOMAIN" ]; then echo -e "${RED}     错误：域名不能为空！    ${NC}"; sleep 2; return; fi

    WP_DB_PASS="WpDb-pW_$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 12)"
    WP_DB_ROOT_PASS="WpRoot-pW_$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 12)"

    clear
    echo -e "${BLUE}--- “WordPress 个人博客”建造计划启动！ ---${NC}";
    mkdir -p /root/wordpress_data
    cat > /root/wordpress_data/docker-compose.yml <<EOF
services:
  db:
    image: mariadb:11.4
    container_name: wordpress_db
    restart: unless-stopped
    volumes:
      - './db_data:/var/lib/mysql'
    environment:
      MYSQL_ROOT_PASSWORD: ${WP_DB_ROOT_PASS}
      MYSQL_DATABASE: wordpress
      MYSQL_USER: wordpress
      MYSQL_PASSWORD: ${WP_DB_PASS}
    networks:
      - npm_network

  wordpress:
    image: wordpress:latest
    container_name: wordpress_app
    restart: unless-stopped
    volumes:
      - './html:/var/www/html'
    environment:
      WORDPRESS_DB_HOST: wordpress_db
      WORDPRESS_DB_USER: wordpress
      WORDPRESS_DB_PASSWORD: ${WP_DB_PASS}
      WORDPRESS_DB_NAME: wordpress
    depends_on:
      - db
    networks:
      - npm_network

networks:
  npm_network:
    name: npm_data_default
    external: true
EOF
    if (cd /root/wordpress_data && sudo docker-compose up -d); then
        echo -e "${GREEN}     ✅     WordPress     已在后台启动！    ${NC}"
        echo -e "\n## WordPress     凭证     (    部署于    : $(date))" >> ${STATE_FILE}
        echo "WORDPRESS_DOMAIN=${WP_DOMAIN}" >> ${STATE_FILE}
        echo -e "\n${GREEN}===============     ✅     WordPress     部署完成        ✅     ===============${NC}"
        echo "    请在     NPM     中为     ${BLUE}${WP_DOMAIN}${NC} (    以及     www.${WP_DOMAIN})     配置代理，指向     ${BLUE}wordpress_app:80${NC}"
    else
        echo -e "${RED}     ❌     WordPress 部署失败！请检查上面的错误信息。    ${NC}"
    fi
    echo -e "\n${GREEN}    按任意键返回主菜单    ...${NC}"; read -n 1 -s
}

# 4. AI     核心
install_ai_suite() {
    ensure_docker_installed || return
    check_npm_installed || return
    read -p "    请输入您为     AI     规划的子域名     (    例如     ai.zhangcaiduo.com): " AI_DOMAIN
    if [ -z "$AI_DOMAIN" ]; then echo -e "${RED}     错误：    AI     域名不能为空！    ${NC}"; sleep 2; return; fi
    clear
    echo -e "${BLUE}--- “AI 大脑”激活计划启动！ ---${NC}";
    mkdir -p /root/ai_stack
    cat > /root/ai_stack/docker-compose.yml <<'EOF'
services:
  ollama:
    image: ollama/ollama
    container_name: ollama_app
    restart: unless-stopped
    volumes:
      - './ollama_data:/root/.ollama'
    networks:
      - npm_network

  open-webui:
    image: 'ghcr.io/open-webui/open-webui:latest'
    container_name: open_webui_app
    restart: unless-stopped
    environment:
      - 'OLLAMA_BASE_URL=http://ollama_app:11434'
    depends_on:
      - ollama
    networks:
      - npm_network

networks:
  npm_network:
    name: npm_data_default
    external: true
EOF
    if (cd /root/ai_stack && sudo docker-compose up -d); then
        echo -e "${GREEN}     ✅     AI     核心已在后台启动！    ${NC}"
        echo -e "\n## AI     核心凭证     (    部署于    : $(date))" >> ${STATE_FILE}
        echo "AI_DOMAIN=${AI_DOMAIN}" >> ${STATE_FILE}
        echo -e "\n${GREEN}AI     核心部署完成    !     强烈建议立即选择一个知识库进行安装    !${NC}"
        install_ai_model
    else
        echo -e "${RED}     ❌     AI 核心部署失败！请检查上面的错误信息。    ${NC}"
        echo -e "\n${GREEN}    按任意键返回主菜单    ...${NC}"; read -n 1 -s
    fi
}

# 5. Jellyfin
install_jellyfin() {
    ensure_docker_installed || return
    check_npm_installed || return
    clear
    echo -e "${BLUE}--- “Jellyfin 家庭影院”建造计划启动！ ---${NC}";
    mkdir -p /root/jellyfin_data/config /mnt/Movies /mnt/TVShows /mnt/Music
    cat > /root/jellyfin_data/docker-compose.yml <<'EOF'
services:
  jellyfin:
    image: jellyfin/jellyfin:latest
    container_name: jellyfin_app
    restart: unless-stopped
    environment:
      - 'PUID=1000'
      - 'PGID=1000'
      - 'TZ=Asia/Shanghai'
    volumes:
      - './config:/config'
      - '/mnt/Movies:/media/movies'
      - '/mnt/TVShows:/media/tvshows'
      - '/mnt/Music:/media/music'
    networks:
      - npm_network

networks:
  npm_network:
    name: npm_data_default
    external: true
EOF
    if (cd /root/jellyfin_data && sudo docker-compose up -d); then
        echo -e "${GREEN}     ✅     Jellyfin     已在后台启动！    ${NC}"
        echo -e "\n${GREEN}===============     ✅     Jellyfin     部署完成        ✅     ===============${NC}"
        echo "    请在     NPM     中为您规划的域名配置代理，指向     ${BLUE}jellyfin_app:8096${NC}"
        echo "    媒体库目录已创建    : /mnt/Movies, /mnt/TVShows, /mnt/Music"
    else
        echo -e "${RED}     ❌     Jellyfin 部署失败！请检查上面的错误信息。    ${NC}"
    fi
    echo -e "\n${GREEN}    按任意键返回主菜单    ...${NC}"; read -n 1 -s
}

# 6. Navidrome
install_navidrome() {
    ensure_docker_installed || return
    check_npm_installed || return
    clear
    echo -e "${BLUE}--- “Navidrome 音乐服务器”部署计划启动！ ---${NC}"
    mkdir -p /root/navidrome_data /mnt/Music
    cat > /root/navidrome_data/docker-compose.yml <<'EOF'
services:
  navidrome:
    image: deluan/navidrome:latest
    container_name: navidrome_app
    restart: unless-stopped
    volumes:
      - '/mnt/Music:/music'
      - './data:/data'
    environment:
      - 'PUID=1000'
      - 'PGID=1000'
      - 'ND_LOGLEVEL=info'
      - 'TZ=Asia/Shanghai'
    networks:
      - npm_network
networks:
  npm_network:
    name: npm_data_default
    external: true
EOF
    if (cd /root/navidrome_data && sudo docker-compose up -d); then
        echo -e "${GREEN} ✅  Navidrome 已启动！内部端口: 4533. 媒体库: /mnt/Music ${NC}"
        echo "    请在     NPM     中为您规划的域名配置代理，指向     ${BLUE}navidrome_app:4533${NC}"
    else
        echo -e "${RED}     ❌     Navidrome 部署失败！请检查上面的错误信息。    ${NC}"
    fi
    echo -e "\n${GREEN}    按任意键返回主菜单    ...${NC}"; read -n 1 -s
}

# 7. Alist
install_alist() {
    ensure_docker_installed || return
    check_npm_installed || return
    clear
    echo -e "${BLUE}--- “Alist 网盘挂载”部署计划启动！ ---${NC}"
    mkdir -p /root/alist_data
    cat >/root/alist_data/docker-compose.yml <<'EOF'
services:
  alist:
    image: xhofe/alist:latest
    container_name: alist_app
    restart: unless-stopped
    volumes:
      - './data:/opt/alist/data'
    networks:
      - npm_network
networks:
  npm_network:
    name: npm_data_default
    external: true
EOF
    if (cd /root/alist_data && sudo docker-compose up -d); then
        echo -e "${GREEN} ✅  Alist 已启动！内部端口: 5244 ${NC}"
        echo "    请在     NPM     中为您规划的域名配置代理，指向     ${BLUE}alist_app:5244${NC}"
        echo -e "${CYAN} 请使用以下命令查看初始密码: sudo docker exec alist_app ./alist admin ${NC}"
    else
        echo -e "${RED}     ❌     Alist 部署失败！请检查上面的错误信息。    ${NC}"
    fi
    echo -e "\n${GREEN}    按任意键返回主菜单    ...${NC}"; read -n 1 -s
}

# 8. Gitea
install_gitea() {
    ensure_docker_installed || return
    check_npm_installed || return
    clear
    echo -e "${BLUE}--- “Gitea 代码仓库”部署计划启动！ ---${NC}"
    mkdir -p /root/gitea_data
    cat >/root/gitea_data/docker-compose.yml <<'EOF'
services:
  server:
    image: gitea/gitea:latest
    container_name: gitea_app
    restart: unless-stopped
    environment:
      - 'USER_UID=1000'
      - 'USER_GID=1000'
    volumes:
      - './gitea:/data'
      - '/etc/timezone:/etc/timezone:ro'
      - '/etc/localtime:/etc/localtime:ro'
    networks:
      - npm_network
networks:
  npm_network:
    name: npm_data_default
    external: true
EOF
    if (cd /root/gitea_data && sudo docker-compose up -d); then
        echo -e "${GREEN} ✅  Gitea 已启动！内部端口: 3000 ${NC}"
        echo "    请在     NPM     中为您规划的域名配置代理，指向     ${BLUE}gitea_app:3000${NC}"
    else
        echo -e "${RED}     ❌     Gitea 部署失败！请检查上面的错误信息。    ${NC}"
    fi
    echo -e "\n${GREEN}    按任意键返回主菜单    ...${NC}"; read -n 1 -s
}

# 9. Memos
install_memos() {
    ensure_docker_installed || return
    check_npm_installed || return
    clear
    echo -e "${BLUE}--- “Memos 轻量笔记”部署计划启动！ ---${NC}"
    mkdir -p /root/memos_data
    cat >/root/memos_data/docker-compose.yml <<'EOF'
services:
  memos:
    image: neosmemo/memos:latest
    container_name: memos_app
    restart: always
    volumes:
      - './data:/var/opt/memos'
    networks:
      - npm_network
networks:
  npm_network:
    name: npm_data_default
    external: true
EOF
    if (cd /root/memos_data && sudo docker-compose up -d); then
        echo -e "${GREEN} ✅  Memos 已启动！内部端口: 5230 ${NC}"
        echo "    请在     NPM     中为您规划的域名配置代理，指向     ${BLUE}memos_app:5230${NC}"
    else
        echo -e "${RED}     ❌     Memos 部署失败！请检查上面的错误信息。    ${NC}"
    fi
    echo -e "\n${GREEN}    按任意键返回主菜单    ...${NC}"; read -n 1 -s
}

# 10. qBittorrent
install_qbittorrent() {
    ensure_docker_installed || return
    check_npm_installed || return
    clear
    echo -e "${BLUE}--- “qBittorrent 下载器”部署计划启动！ ---${NC}"
    mkdir -p /root/qbittorrent_data /mnt/Downloads
    cat > /root/qbittorrent_data/docker-compose.yml <<'EOF'
services:
  qbittorrent:
    image: lscr.io/linuxserver/qbittorrent:latest
    container_name: qbittorrent_app
    restart: unless-stopped
    environment:
      - 'PUID=1000'
      - 'PGID=1000'
      - 'TZ=Asia/Shanghai'
      - 'WEBUI_PORT=8080'
    volumes:
      - './config:/config'
      - '/mnt/Downloads:/downloads'
    networks:
      - npm_network
networks:
  npm_network:
    name: npm_data_default
    external: true
EOF
    if (cd /root/qbittorrent_data && sudo docker-compose up -d); then
        echo -e "${GREEN} ✅  qBittorrent 已启动！内部端口: 8080, 下载目录: /mnt/Downloads ${NC}"
        echo "    请在     NPM     中为您规划的域名配置代理，指向     ${BLUE}qbittorrent_app:8080${NC}"
    else
        echo -e "${RED}     ❌     qBittorrent 部署失败！请检查上面的错误信息。    ${NC}"
    fi
    echo -e "\n${GREEN}    按任意键返回主菜单    ...${NC}"; read -n 1 -s
}

# 11. JDownloader
install_jdownloader() {
    ensure_docker_installed || return
    check_npm_installed || return
    clear
    echo -e "${BLUE}--- “JDownloader 下载器”部署计划启动！ ---${NC}"
    JDOWNLOADER_PASS="VNC-Pass-$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 8)"
    mkdir -p /root/jdownloader_data /mnt/Downloads
    cat > /root/jdownloader_data/docker-compose.yml <<EOF
services:
  jdownloader-2:
    image: jlesage/jdownloader-2
    container_name: jdownloader_app
    restart: unless-stopped
    environment:
      - 'USER_ID=1000'
      - 'GROUP_ID=1000'
      - 'TZ=Asia/Shanghai'
      - 'VNC_PASSWORD=${JDOWNLOADER_PASS}'
    volumes:
      - './config:/config'
      - '/mnt/Downloads:/output'
    networks:
      - npm_network
networks:
  npm_network:
    name: npm_data_default
    external: true
EOF
    if (cd /root/jdownloader_data && sudo docker-compose up -d); then
        echo "JDOWNLOADER_VNC_PASSWORD=${JDOWNLOADER_PASS}" >> ${STATE_FILE}
        echo -e "${GREEN} ✅  JDownloader 已启动！VNC 密码 ${JDOWNLOADER_PASS} 已保存。内部端口 5800 ${NC}"
        echo "    请在     NPM     中为您规划的域名配置代理，指向     ${BLUE}jdownloader_app:5800${NC}"
    else
        echo -e "${RED}     ❌     JDownloader 部署失败！请检查上面的错误信息。    ${NC}"
    fi
    echo -e "\n${GREEN}    按任意键返回主菜单    ...${NC}"; read -n 1 -s
}

# 12. yt-dlp
install_ytdlp() {
    ensure_docker_installed || return
    check_npm_installed || return
    clear
    read -p "    请输入您为 yt-dlp 规划的子域名 (例如 ytdl.zhangcaiduo.com): " YTDL_DOMAIN
    if [ -z "$YTDL_DOMAIN" ]; then echo -e "${RED}yt-dlp 域名不能为空，安装取消。${NC}"; sleep 2; return; fi
    echo -e "${BLUE}--- “yt-dlp 视频下载器”部署计划启动！ ---${NC}"
    mkdir -p /root/ytdlp_data /mnt/Downloads
    cat > /root/ytdlp_data/docker-compose.yml <<EOF
services:
  ytdlp-ui:
    image: tzahi12345/youtubedl-material:latest
    container_name: ytdlp_app
    restart: unless-stopped
    environment:
      - 'BACKEND_URL=https://${YTDL_DOMAIN}'
    volumes:
      - '/mnt/Downloads:/app/downloads'
      - './config:/app/config'
    networks:
      - npm_network
networks:
  npm_network:
    name: npm_data_default
    external: true
EOF
    if (cd /root/ytdlp_data && sudo docker-compose up -d); then
        echo "YTDL_DOMAIN=${YTDL_DOMAIN}" >> ${STATE_FILE}
        echo -e "${GREEN} ✅  yt-dlp 已启动！内部端口 8080。请配置NPM反代到 ytdlp_app:8080 ${NC}"
        echo "    请在     NPM     中为     ${BLUE}${YTDL_DOMAIN}${NC} 配置代理，指向     ${BLUE}ytdlp_app:8080${NC}"
    else
        echo -e "${RED}     ❌     yt-dlp 部署失败！请检查上面的错误信息。    ${NC}"
    fi
    echo -e "\n${GREEN}    按任意键返回主菜单    ...${NC}"; read -n 1 -s
}


# 15. Fail2ban
install_fail2ban() {
    clear
    echo -e "${BLUE}--- “全屋安防系统”部署计划启动！ ---${NC}";
    sleep 2
    echo -e "\n${YELLOW}     🚀     [1/2]     正在安装     Fail2ban     主程序    ...${NC}"
    sudo apt-get install -y fail2ban
    echo -e "${GREEN}     ✅     Fail2ban     安装完毕！    ${NC}"

    echo -e "\n${YELLOW}     🚀     [2/2]     正在配置安防规则    ...${NC}"
    sudo tee /etc/fail2ban/jail.local > /dev/null <<'EOF'
[DEFAULT]
bantime = 2h
findtime = 10m
maxretry = 5
backend = systemd
[sshd]
enabled = true
[nginx-http-auth]
enabled = true
logpath = /root/npm_data/data/logs/*.log
[nginx-badbots]
enabled = true
logpath = /root/npm_data/data/logs/*.log
[nextcloud]
enabled = true
logpath = /root/nextcloud_data/html/data/nextcloud.log
[recidive]
enabled = true
logpath = /var/log/fail2ban.log
bantime = 1w
findtime = 1d
maxretry = 5
EOF
    sudo systemctl restart fail2ban
    sudo systemctl enable fail2ban
    echo -e "${GREEN}     ✅        安防规则配置完毕并已激活！    ${NC}"
    echo -e "\n${GREEN}    按任意键返回主菜单    ...${NC}"; read -n 1 -s
}

# 16.     远程桌面
install_desktop_env() {
    clear
    echo -e "${BLUE}--- “远程工作台”建造计划启动！ ---${NC}";
    sleep 2
    echo -e "\n${YELLOW}     🚀     [1/4]     正在安装核心桌面组件     (Xfce)...${NC}"
    export DEBIAN_FRONTEND=noninteractive
    sudo apt-get update
    sudo apt-get install -y xfce4 xfce4-goodies -y
    echo -e "${GREEN}     ✅        核心桌面组件安装完毕！    ${NC}"

    echo -e "\n${YELLOW}     🚀     [2/4]     正在安装并加固远程连接服务     (XRDP)...${NC}"
    sudo apt-get install -y xrdp
    
    if [ -f /etc/xrdp/sesman.ini ]; then
        echo -e "${YELLOW}正在加固 XRDP，禁止 root 用户登录...${NC}"
        sudo sed -i 's/AllowRootLogin=true/AllowRootLogin=false/g' /etc/xrdp/sesman.ini
    fi

    sudo systemctl enable --now xrdp
    echo xfce4-session > ~/.xsession
    sudo adduser xrdp ssl-cert
    sudo systemctl restart xrdp
    echo -e "${GREEN}     ✅        远程连接服务安装并启动完毕！    ${NC}"

    echo -e "\n${YELLOW}     🚀     [3/4]     正在创建您的专属工作台账户    ...${NC}"
    read -p "    请输入您想创建的新用户名     (    例如     zhangcaiduo): " NEW_USER
    if [ -z "$NEW_USER" ]; then echo -e "${RED}     用户名不能为空，操作取消。    ${NC}"; sleep 2; return; fi
    sudo adduser --gecos "" "$NEW_USER"
    echo "DESKTOP_USER=${NEW_USER}" >> ${STATE_FILE} # 保存用户名用于卸载
    echo -e "${GREEN}     ✅        专属账户     '$NEW_USER'     创建成功！    ${NC}"

    echo -e "\n${YELLOW}     🚀     [4/4]     请为新账户 '$NEW_USER' 设置登录密码...${NC}"
    sudo passwd "$NEW_USER"

    echo -e "\n${GREEN}===============     ✅        远程工作台建造完毕！        ✅     ===============${NC}"
    echo "    请使用您电脑的“远程桌面连接”工具，连接到您的服务器     IP    。    "
    echo -e "    ${YELLOW}在登录界面，请使用您刚刚创建的【用户名】和【新密码】。${NC}"
    echo -e "\n${GREEN}    按任意键返回主菜单    ...${NC}"; read -n 1 -s
}

# 17.     邮件管家
install_mail_reporter() {
    clear
    echo -e "${BLUE}--- “服务器每日管家”安装程序 ---${NC}";
    sleep 2
    echo -e "\n${YELLOW}     🚀     [1/3]     正在安装邮件工具   ...${NC}"
    sudo apt-get update
    DEBIAN_FRONTEND=noninteractive sudo apt-get install -y --no-install-recommends s-nail msmtp cron vnstat
    if ! command -v s-nail >/dev/null 2>&1; then
        echo -e "${RED}     核心     's-nail'     命令安装失败！请检查您的     apt     源后重试。    ${NC}";
        sleep 3; return
    fi
    echo -e "${GREEN}     ✅        所需工具已安装完毕。    ${NC}"

    echo -e "\n${YELLOW}     🚀     [2/3]     正在收集您的邮箱配置    ...${NC}"
    read -p "    请输入您的邮箱地址     (    例如    : yourname@qq.com): " mail_user
    read -sp "    请输入上面邮箱的“应用密码”或“授权码”(可粘贴): " mail_pass
    echo
    read -p "    请输入邮箱的     SMTP     服务器地址     (    例如    : smtp.qq.com): " mail_server
    read -p "    请输入接收报告的邮箱地址     (    可以和上面相同    ): " to_email

    MSMTP_CONFIG_PATH="/etc/msmtprc"
    sudo tee $MSMTP_CONFIG_PATH > /dev/null <<EOF
defaults
auth           on
tls            on
tls_starttls   on
tls_trust_file /etc/ssl/certs/ca-certificates.crt
logfile        ~/.msmtp.log
account        default
host           ${mail_server}
port           587
from           ${mail_user}
user           ${mail_user}
password       ${mail_pass}
EOF
    sudo chmod 600 $MSMTP_CONFIG_PATH

    SNAIL_CONFIG_PATH="/etc/s-nail.rc"
    echo "set mta=/usr/bin/msmtp" | sudo tee ${SNAIL_CONFIG_PATH} > /dev/null
    echo -e "${GREEN}     ✅        邮件发送服务配置完毕。    ${NC}"

    echo -e "\n${YELLOW}     🚀     [3/3]     正在创建报告脚本并设置定时任务    ...${NC}"
    REPORT_SCRIPT_PATH="/usr/local/bin/daily_server_report.sh"
    sudo tee $REPORT_SCRIPT_PATH > /dev/null <<EOF
#!/bin/bash
HOSTNAME=\$(hostname); CURRENT_TIME=\$(date "+%Y-%m-%d %H:%M:%S"); UPTIME=\$(uptime -p)
TRAFFIC_INFO=\$(vnstat -d 1); FAILED_LOGINS=\$(grep -c "Failed password" /var/log/auth.log || echo "0")
SUBJECT="    【服务器管家报告】来自     \$HOSTNAME - \$(date "+%Y-%m-%d")"
HTML_BODY="<html><body><h2>    服务器每日管家报告    </h2><p><b>    主机名    :</b> \$HOSTNAME</p><p><b>    报告时间    :</b> \$CURRENT_TIME</p><hr><h3>    核心状态摘要    :</h3><ul><li><b>    已持续运行    :</b> \$UPTIME</li><li><b>SSH     登录失败次数     (    今日    ):</b><strong style='color:red;'>\$FAILED_LOGINS     次    </strong></li></ul><hr><h3>    今日网络流量报告    :</h3><pre style='background-color:#f5f5f5; padding:10px;'>\$TRAFFIC_INFO</pre></body></html>"
echo "\$HTML_BODY" | s-nail -s "\$SUBJECT" -a "Content-Type: text/html" "$to_email"
EOF
    sudo chmod +x $REPORT_SCRIPT_PATH
    (crontab -l 2>/dev/null | grep -v "$REPORT_SCRIPT_PATH" ; echo "30 23 * * * $REPORT_SCRIPT_PATH") | crontab -
    echo -e "${GREEN}     ✅        报告系统部署完毕！    ${NC}"

    echo -e "\n${YELLOW}     正在发送测试邮件    ...${NC}"
    echo "    这是一封来自【服务器每日管家】的安装成功测试邮件！    " |
    s-nail -s "    【服务器管家】安装成功测试    " "$to_email"
    echo -e "\n${GREEN}===============     ✅        邮件管家部署完成！        ✅     ===============${NC}"
    echo -e "\n${GREEN}    按任意键返回主菜单    ...${NC}"; read -n 1 -s
}

# 18. Rclone 数据同步桥 (v7.3.0 优化)
configure_rclone_engine() {
    clear
    echo -e "${BLUE}--- “Rclone 数据同步桥”配置向导 (全盘跃迁模式) ---${NC}"

    # 安装 Rclone
    if ! command -v rclone &> /dev/null; then
        echo -e "\n${YELLOW}     🚀        正在为您安装 Rclone 主程序...${NC}"
        curl https://rclone.org/install.sh | sudo bash
        sudo apt-get install -y fuse3
        echo -e "${GREEN}     ✅     Rclone 已安装完毕！    ${NC}"
        sleep 2
    fi

    # 交互式配置 Rclone
    if [ ! -f "${RCLONE_CONFIG_FILE}" ]; then
        echo -e "\n${YELLOW}     未检测到 Rclone 配置文件。${NC}"
        echo -e "${CYAN}     即将启动 Rclone 官方交互式配置工具...${NC}"
        echo "----------------------------------------------------------"
        echo -e "     您将进入一个问答式配置流程，请根据提示操作："
        echo -e "  - ${YELLOW}   新建 remote 时，请记住您为它取的名字 (name)。${NC}"
        echo -e "  - ${YELLOW}   当询问 'Use auto config?' 时，必须选 'n' (no)。${NC}"
        echo -e "  - ${YELLOW}   复制浏览器打开的链接完成授权，再将 token 粘贴回来。${NC}"
        echo "----------------------------------------------------------"
        read -p "     准备好后，请按任意键继续..." -n 1 -s
        echo -e "\n"
        rclone config
        if [ ! -f "${RCLONE_CONFIG_FILE}" ]; then
            echo -e "\n${RED}     错误：配置似乎未成功保存。请重新尝试。${NC}"
            sleep 3
            return
        fi
        echo -e "\n${GREEN}     ✅        检测到 Rclone 配置文件已成功创建！${NC}"
        sleep 2
    fi

    echo -e "\n${CYAN}--- 设置 Rclone 全盘自动挂载 ---${NC}"
    
    # 获取用户配置的 remote 名称
    read -p "    请输入您在上面配置中设置的 remote 名称 (例如 onedrive): " rclone_remote_name
    if [ -z "$rclone_remote_name" ]; then
        echo -e "${RED} remote 名称不能为空，配置中止。${NC}"; sleep 3; return
    fi

    local rclone_mount_path="/mnt/onedrive"
    
    # 保存配置到状态文件，以便其他功能调用
    sed -i '/^RCLONE_REMOTE/d' ${STATE_FILE}
    sed -i '/^RCLONE_MOUNT_PATH/d' ${STATE_FILE}
    echo "RCLONE_REMOTE=${rclone_remote_name}" >> ${STATE_FILE}
    echo "RCLONE_MOUNT_PATH=${rclone_mount_path}" >> ${STATE_FILE}

    echo -e "\n${YELLOW}     正在为 ${rclone_remote_name} 创建全盘挂载通道...${NC}"
    echo -e "${YELLOW}     远程路径: ${rclone_remote_name}:/  ->  本地路径: ${rclone_mount_path}${NC}"
    
    sudo mkdir -p "${rclone_mount_path}"
    
    # 创建 systemd 服务文件
    sudo tee "/etc/systemd/system/rclone-vps-mount.service" > /dev/null <<EOF
[Unit]
Description=Rclone Mount Service for ${rclone_remote_name}
Wants=network-online.target
After=network-online.target
[Service]
Type=simple
User=root
Group=root
RestartSec=10
Restart=on-failure
ExecStart=/usr/bin/rclone mount ${rclone_remote_name}: ${rclone_mount_path} \\
--config ${RCLONE_CONFIG_FILE} \\
--uid 1000 \\
--gid 1000 \\
--allow-other \\
--allow-non-empty \\
--vfs-cache-mode full \\
--vfs-cache-max-size 5G \\
--log-level INFO \\
--log-file ${RCLONE_LOG_FILE}
ExecStop=/bin/fusermount -u ${rclone_mount_path}
[Install]
WantedBy=default.target
EOF

    # 启动并激活服务
    sudo systemctl daemon-reload
    sudo systemctl enable --now "rclone-vps-mount.service"
    sleep 2
    
    if systemctl is-active --quiet "rclone-vps-mount.service"; then
        echo -e "${GREEN}     ✅        Rclone 全盘跃迁通道已激活！写入性能已优化！${NC}"
        echo -e "${GREEN}     您的 ${rclone_remote_name} 网盘已完整挂载到 ${rclone_mount_path} ${NC}"
    else
        echo -e "${RED}     ❌        挂载通道启动失败！请检查日志。${NC}"
        echo -e "${YELLOW}     显示最近的 10 行日志 (${RCLONE_LOG_FILE}):${NC}"
        sudo tail -n 10 ${RCLONE_LOG_FILE}
    fi
    
    echo -e "\n${GREEN}Rclone 数据同步桥配置完成！按任意键返回主菜单...${NC}"; read -n 1 -s
}

# 21.     安装     AI     知识库
install_ai_model() {
    ensure_docker_installed || return
    if [ ! -d "/root/ai_stack" ]; then echo -e "${RED}     错误：AI 大脑未安装!${NC}"; sleep 3; return; fi
    clear
    echo -e "${BLUE}---     为 AI 大脑安装知识库 (安装大语言模型) ---${NC}"
    echo "  ${YELLOW}---     轻量级    /    速度型     (    适合     <=4G     内存    ) ---${NC}"
    echo "  1) qwen:1.8b   -     阿里通义千问    ,     中文优秀    "
    echo "  2) gemma:2b    - Google     出品    ,     综合不错    "
    echo "  3) tinyllama   -     极限轻量    ,     速度飞快    "
    echo "  ${YELLOW}---     主流    /    性能型     (    推荐     >=8G     内存    ) ---${NC}"
    echo "  4) llama3:8b   - Meta     出品    ,     综合性能最强     (    推荐    )"
    echo "  5) qwen:4b     -     通义千问    ,     更强的中文模型    "
    echo "  6) phi3        -     微软出品    ,     强大的小模型    "
    echo "  ${YELLOW}---     重量级    /    专业型     (    推荐     >=16G     内存    ) ---${NC}"
    echo "  7) qwen:14b    -     通义千问    ,     准专业级    "
    echo "  8) llama3:70b  - Llama3     旗舰版    ,     性能怪兽    "
    echo "  b)     返回主菜单    "
    read -p "    请输入您的选择    : " model_choice

    local model_name=""
    case $model_choice in
        1) model_name="qwen:1.8b";; 2) model_name="gemma:2b";;
        3) model_name="tinyllama";; 4) model_name="llama3:8b";;
        5) model_name="qwen:4b";;   6) model_name="phi3";;
        7) model_name="qwen:14b";;  8) model_name="llama3:70b";;
        b) return;; *) echo -e "${RED}     无效选择    !${NC}"; sleep 2; return;;
    esac

    echo -e "\n${YELLOW}     即将开始下载模型    : ${model_name}    。此过程可能需要一些时间，请耐心等待    ...${NC}"
    sudo docker exec -it ollama_app ollama pull ${model_name}
    echo -e "\n${GREEN}===============     ✅        知识库     ${model_name}     安装完成！        ✅     ===============${NC}"
    echo -e "\n${GREEN}    按任意键返回主菜单    ...${NC}"; read -n 1 -s
}

# 22. Nextcloud     优化
run_nextcloud_optimization() {
    ensure_docker_installed || return
    if [ ! -d "/root/nextcloud_data" ]; then echo -e "${RED}     错误：Nextcloud 套件未安装!${NC}"; sleep 3; return; fi
    clear
    echo -e "${BLUE}--- “Nextcloud 精装修”计划启动！ ---${NC}";
    sleep 2
    local nc_domain=$(grep 'NEXTCLOUD_DOMAIN' ${STATE_FILE} | cut -d'=' -f2)
    if [ -z "$nc_domain" ]; then echo -e "${RED}     错误    :     无法从凭证文件找到     Nextcloud     域名    !${NC}"; sleep 3; return; fi

    echo -e "\n${YELLOW}     🚀     [1/4]     配置反向代理信任    ...${NC}"
    sudo docker exec --user www-data nextcloud_app php occ config:system:set trusted_proxies 0 --value='172.16.0.0/12'
    sudo docker exec --user www-data nextcloud_app php occ config:system:set overwrite.cli.url --value="https://${nc_domain}"
    sudo docker exec --user www-data nextcloud_app php occ config:system:set overwriteprotocol --value='https'

    echo -e "\n${YELLOW}     🚀     [2/4]     启用     Redis     高性能缓存    ...${NC}"
    sudo docker exec --user www-data nextcloud_app php occ config:system:set memcache.local --value '\\OC\\Memcache\\Redis'
    sudo docker exec --user www-data nextcloud_app php occ config:system:set memcache.locking --value '\\OC\\Memcache\\Redis'
    sudo docker exec --user www-data nextcloud_app php occ config:system:set redis host --value 'nextcloud_redis'

    echo -e "\n${YELLOW}     🚀     [3/4]     执行数据库维护与优化    ...${NC}"
    sudo docker exec --user www-data nextcloud_app php occ db:add-missing-indices
    sudo docker exec --user www-data nextcloud_app php occ maintenance:repair --include-expensive

    echo -e "\n${YELLOW}     🚀     [4/4]     配置系统常规设置    ...${NC}"
    sudo docker exec --user www-data nextcloud_app php occ config:system:set maintenance_window_start --type=integer --value=1
    sudo docker exec --user www-data nextcloud_app php occ config:system:set default_phone_region --value="CN"

    echo -e "\n${GREEN}===============     ✅     Nextcloud     精装修完成！        ✅     ===============${NC}"
    echo -e "\n${GREEN}    按任意键返回主菜单    ...${NC}"; read -n 1 -s
}

# 23. 服务控制中心 (v7.3.0 修复版)
show_service_control_panel() {
    ensure_docker_installed || return
    while true; do
        clear
        echo -e "${BLUE}---     服务控制中心     ---${NC}"
        echo "    请选择要操作的服务    :"

        declare -a services=(
            "Nextcloud 数据中心:/root/nextcloud_data" "网络水电总管 (NPM):/root/npm_data" "OnlyOffice 办公室:/root/onlyoffice_data"
            "WordPress 博客:/root/wordpress_data" "AI 大脑:/root/ai_stack" "Jellyfin 影院:/root/jellyfin_data"
            "Navidrome 音乐:/root/navidrome_data" "Alist 网盘:/root/alist_data" "Gitea 仓库:/root/gitea_data"
            "Memos 笔记:/root/memos_data" "qBittorrent:/root/qbittorrent_data" "JDownloader:/root/jdownloader_data"
            "yt-dlp 下载:/root/ytdlp_data"
        )

        local i=1
        declare -a active_services=()
        for service_entry in "${services[@]}"; do
            local name=$(echo $service_entry | cut -d':' -f1)
            local path=$(echo $service_entry | cut -d':' -f2)
            if [ -f "${path}/docker-compose.yml" ]; then
                if sudo docker-compose -f ${path}/docker-compose.yml ps -q 2>/dev/null | grep -q .; then
                    status="${GREEN}[     运行中     ]${NC}"
                else
                    status="${RED}[     已停止     ]${NC}"
                fi
                printf "  %2d) %-25s %s\n" "$i" "$name" "$status"
                active_services+=("$name:$path")
                i=$((i+1))
            fi
        done

        echo "------------------------------------"
        echo "  b)     返回主菜单    "
        read -p "    请输入数字选择服务    ,     或     'b'     返回    : " service_choice

        if [[ "$service_choice" == "b" || "$service_choice" == "B" ]]; then break; fi

        local index=$((service_choice-1))
        if ! [[ $index -ge 0 && $index -lt ${#active_services[@]} ]]; then
             echo -e "${RED}     无效选择    !${NC}"; sleep 2; continue
        fi

        local selected_service=${active_services[$index]}
        local s_name=$(echo $selected_service | cut -d':' -f1)
        local s_path=$(echo $selected_service | cut -d':' -f2)
        local compose_file="${s_path}/docker-compose.yml"

        local is_linkable=false
        local container_paths=()
        local path_labels=()
        local default_local_paths=()

        case "$s_name" in
            "Jellyfin 影院")
                is_linkable=true
                container_paths=("/media/music" "/media/movies" "/media/tvshows")
                path_labels=("音乐库" "电影库" "电视剧库")
                default_local_paths=("/mnt/Music" "/mnt/Movies" "/mnt/TVShows")
                ;;
            "Navidrome 音乐")
                is_linkable=true
                container_paths=("/music")
                path_labels=("音乐库")
                default_local_paths=("/mnt/Music")
                ;;
            "qBittorrent")
                is_linkable=true
                container_paths=("/downloads")
                path_labels=("下载目录")
                default_local_paths=("/mnt/Downloads")
                ;;
            "JDownloader")
                is_linkable=true
                container_paths=("/output")
                path_labels=("下载目录")
                default_local_paths=("/mnt/Downloads")
                ;;
            "yt-dlp 下载")
                is_linkable=true
                container_paths=("/app/downloads")
                path_labels=("下载目录")
                default_local_paths=("/mnt/Downloads")
                ;;
        esac

        clear
        echo "    正在操作服务    : ${CYAN}${s_name}${NC}"

        if $is_linkable; then
            echo "1)     启动"
            echo "2)     停止"
            echo "3)     重启"
            echo "4)     查看本项目文件夹地址"
            echo "5)     将文件夹地址关联到Rclone跃迁的网盘"
            echo "6)     查看日志 (按 Ctrl+C 退出)"
            echo "b)     返回"
            read -p "    请选择操作: " action_choice

            case $action_choice in
                1) (cd $s_path && sudo docker-compose up -d); echo -e "${GREEN}${s_name} 已启动!${NC}";;
                2) (cd $s_path && sudo docker-compose stop); echo -e "${YELLOW}${s_name} 已停止!${NC}";;
                3) (cd $s_path && sudo docker-compose restart); echo -e "${CYAN}${s_name} 已重启!${NC}";;
                4)
                    echo -e "\n${CYAN}--- ${s_name} 当前文件夹地址 ---${NC}"
                    for i in ${!container_paths[@]}; do
                        local c_path=${container_paths[$i]}
                        local label=${path_labels[$i]}
                        local line=$(grep -E ":${c_path}['\"]?$" "$compose_file" | head -n 1)
                        if [ -n "$line" ]; then
                           local host_path=$(echo "$line" | awk -F: '{print $1}' | sed -e 's/^[ \t-]*//' -e "s/['\"]//g")
                           echo "  - ${label}: ${GREEN}${host_path}${NC}"
                        fi
                    done
                    read -n 1 -s -r -p "按任意键返回..."
                    continue
                    ;;
                5)
                    if ! grep -q "RCLONE_MOUNT_PATH" "${STATE_FILE}"; then
                        echo -e "${RED}错误：Rclone 未配置或未完全配置。请先在主菜单选择 '18' 完成配置。${NC}"; sleep 4; continue
                    fi
                    local rclone_mount_path=$(grep "RCLONE_MOUNT_PATH" "${STATE_FILE}" | cut -d'=' -f2)
                    if ! mount | grep -q "${rclone_mount_path}"; then
                         echo -e "${RED}错误：Rclone 挂载点 ${rclone_mount_path} 未生效。请检查服务状态。${NC}"; sleep 4; continue
                    fi

                    echo -e "\n${CYAN}--- 关联 Rclone 网盘文件夹 ---${NC}"
                    for i in ${!container_paths[@]}; do
                        local c_path=${container_paths[$i]}
                        local label=${path_labels[$i]}
                        local default_local_path=${default_local_paths[$i]}
                        local line_to_replace=$(grep -E ":${c_path}['\"]?$" "$compose_file" | head -n 1)
                        if [ -z "$line_to_replace" ]; then continue; fi

                        echo -e "${YELLOW}(留空则恢复默认VPS的 ${default_local_path} 文件夹，输入如“Music”这样的网盘文件夹名)${NC}"
                        read -p "请输入用于[${label}]的网盘文件夹名 : " rclone_subfolder

                        local new_host_path=""
                        if [ -z "$rclone_subfolder" ]; then
                           new_host_path=$default_local_path
                           echo -e "${YELLOW}  -> 正在将 ${label} 恢复为本地路径: ${new_host_path}${NC}"
                        else
                           new_host_path="${rclone_mount_path}/${rclone_subfolder}"
                           echo -e "${YELLOW}  -> 正在将 ${label} 关联到 Rclone 路径: ${new_host_path}${NC}"
                        fi

                        sudo mkdir -p "${new_host_path}"
                        local indentation=$(echo "$line_to_replace" | awk '{gsub(/[^ ].*/, ""); print}')
                        local new_line="${indentation}- '${new_host_path}:${c_path}'"
                        sudo sed -i "s|${line_to_replace}|${new_line}|" "${compose_file}"
                    done

                    echo -e "\n${GREEN} ✅ 配置文件更新完毕，正在重启服务以应用更改...${NC}"
                    (cd $s_path && sudo docker-compose up -d --force-recreate)
                    sleep 2
                    echo -e "${GREEN} ✅ 服务已重启！${NC}"

                    local app_internal_path=""
                    case "$s_name" in
                        "qBittorrent") app_internal_path="/downloads" ;;
                        "JDownloader") app_internal_path="/output" ;;
                        "yt-dlp 下载") app_internal_path="/app/downloads" ;;
                    esac

                    if [ -n "$app_internal_path" ]; then
                        echo -e "\n${YELLOW}🔔 温馨提示：关联已成功！这只是第一步。${NC}"
                        echo -e "${YELLOW}   您还需要在【${s_name}的Web界面】里，将文件的【保存路径】或【下载目录】设置为 ${GREEN}${app_internal_path}${NC}"
                        echo -e "${YELLOW}   这样，新任务才会默认保存到您刚刚关联的Rclone网盘文件夹中！${NC}"
                    fi
                    ;;
                6) sudo docker-compose -f ${compose_file} logs -f --tail 50;;
                b) continue;;
                *) echo -e "${RED}     无效操作    !${NC}";;
            esac
        else
            echo "1)     启动"
            echo "2)     停止"
            echo "3)     重启"
            echo "4)     查看日志 (按 Ctrl+C 退出)"
            echo "b)     返回"
            read -p "    请选择操作: " action_choice
            case $action_choice in
                1) (cd $s_path && sudo docker-compose up -d); echo -e "${GREEN}${s_name} 已启动!${NC}";;
                2) (cd $s_path && sudo docker-compose stop); echo -e "${YELLOW}${s_name} 已停止!${NC}";;
                3) (cd $s_path && sudo docker-compose restart); echo -e "${CYAN}${s_name} 已重启!${NC}";;
                4) sudo docker-compose -f ${compose_file} logs -f --tail 50;;
                b) continue;;
                *) echo -e "${RED}     无效操作    !${NC}";;
            esac
        fi
        sleep 2
    done
}


# 24.     显示凭证
show_credentials() {
    if [ ! -f "${STATE_FILE}" ]; then echo -e "\n${YELLOW}     尚未开始装修，没有凭证信息。    ${NC}"; sleep 2; return; fi
    clear
    echo -e "${RED}====================     🔑        【重要凭证保险箱】        🔑     ====================${NC}"
    echo -e "${YELLOW}"
    if grep -q "DB_PASSWORD" "${STATE_FILE}"; then
        echo -e "${CYAN}--- Nextcloud     安装所需信息     ---${NC}"
        echo "       数据库用户    : nextclouduser"
        echo "       数据库密码    : $(grep 'DB_PASSWORD' ${STATE_FILE} | cut -d'=' -f2)"
        echo "       数据库名    :   nextclouddb"
        echo "       数据库主机    : nextcloud_db"
        echo ""
    fi
    grep -v -e "DB_PASSWORD" -e "DESKTOP_USER" "${STATE_FILE}" | sed 's/^/  /'
    echo -e "${NC}"

    echo -e "\n${CYAN}---     应用数据目录     (    用于上传文件    ) ---${NC}"
    [ -d "/mnt/Music" ] && echo "       🎵     音乐库 (Navidrome/Jellyfin): /mnt/Music"
    [ -d "/mnt/Movies" ] && echo "       🎬     电影库 (Jellyfin): /mnt/Movies"
    [ -d "/mnt/TVShows" ] && echo "       📺     电视剧库 (Jellyfin): /mnt/TVShows"
    [ -d "/mnt/Downloads" ] && echo "       🔽     默认下载目录: /mnt/Downloads"
    if grep -q "RCLONE_MOUNT_PATH" "${STATE_FILE}"; then
        echo "       ☁️     Rclone 网盘挂载点: $(grep 'RCLONE_MOUNT_PATH' ${STATE_FILE} | cut -d'=' -f2)"
    fi

    echo -e "${RED}==================================================================${NC}"
    echo -e "\n${GREEN}    这是您已保存的所有重要信息。按任意键返回主菜单    ...${NC}"
    read -n 1 -s
}

# 25.     科学工具箱
install_science_tools() {
    clear
    echo -e "${RED}--- “    科学    ”    工具箱     ---${NC}"
    echo -e "${YELLOW}    免责声明：以下脚本均来自网络上的开源项目作者。    ${NC}"
    echo -e "${YELLOW}    本面板仅为集成与调用，请感谢并支持原作者的辛勤付出。    ${NC}"
    echo "----------------------------------------------------------"
    echo "    请选择要使用的工具    :"
    echo "1) Warp (by fscarmen)"
    echo "2) ArgoX (by fscarmen)"
    echo "3) OpenVPN (by Nyr)"
    echo "b)     返回主菜单    "
    read -p "    请输入您的选择    : " science_choice

    case $science_choice in
        1) bash <(wget -qO- https://gitlab.com/fscarmen/warp/-/raw/main/menu.sh) ;;
        2) bash <(wget -qO- https://raw.githubusercontent.com/fscarmen/argox/main/argox.sh) ;;
        3) wget https://git.io/vpn -O openvpn-install.sh && sudo bash openvpn-install.sh ;;
        b) return ;;
        *) echo -e "${RED}     无效选择    !${NC}"; sleep 2; return;;
    esac
    echo -e "\n${GREEN}    操作完成，按任意键返回主菜单    ...${NC}"; read -n 1 -s
}

# 99.     一键还原毛坯 (终极重构版)
uninstall_everything() {
    clear
    echo -e "${RED}====================     【！！！终极警告！！！】     ====================${NC}"
    echo -e "${YELLOW}    此操作将【不可逆转地】彻底清除本面板安装的所有服务、数据和相关配置！    ${NC}"
    echo "    这包括 Docker 环境、系统级工具、用户账户、所有配置文件和数据目录。"
    echo -e "${RED}    此操作将彻底告别張財多的包工头代码，如果需要再次安装，请重装系统避免出岔子。    ${NC}"
    echo -e "----------------------------------------------------------------------------------"
    read -p "    为确认执行此终极毁灭操作，请输入【    yEs-i-aM-sUrE    】    : " confirmation
    if [[ "$confirmation" != "yEs-i-aM-sUrE" ]]; then
        echo -e "${GREEN}     操作已取消，您的房子安然无恙。    ${NC}"; sleep 3; return
    fi

    echo -e "\n${RED}     最终确认通过    ...     开始执行终极全屋拆除程序    ...${NC}";
    sleep 3

    echo -e "\n${YELLOW}     🚀     [1/6]     正在进行 Docker 系统级清理 (容器, 镜像, 数据卷, 网络)...${NC}"
    if command -v docker &> /dev/null; then
      sudo docker system prune -a --volumes -f
    fi
    echo -e "${GREEN}     ✅     Docker 环境已彻底清理。    ${NC}"

    echo -e "\n${YELLOW}     🚀     [2/6]     正在清理所有服务的数据和配置文件夹    ...${NC}"
    sudo rm -rf /root/npm_data /root/nextcloud_data /root/onlyoffice_data /root/wordpress_data \
        /root/jellyfin_data /root/ai_stack /root/alist_data /root/gitea_data \
        /root/memos_data /root/navidrome_data /root/qbittorrent_data \
        /root/jdownloader_data /root/ytdlp_data /root/.config/rclone
    
    if grep -q "RCLONE_MOUNT_PATH" "${STATE_FILE}"; then
        local rclone_mount_path=$(grep "RCLONE_MOUNT_PATH" "${STATE_FILE}" | cut -d'=' -f2)
        sudo umount "${rclone_mount_path}" >/dev/null 2>&1
        sudo rm -rf "${rclone_mount_path}"
    fi
    sudo umount /mnt/* >/dev/null 2>&1
    sudo rm -rf /mnt/*

    echo -e "${GREEN}     ✅     所有数据文件夹已清理。    ${NC}"

    echo -e "\n${YELLOW}     🚀     [3/6]     正在卸载脚本安装的系统级工具...${NC}"
    if [ -f "/etc/systemd/system/rclone-vps-mount.service" ]; then
        sudo systemctl stop rclone-vps-mount.service
        sudo systemctl disable rclone-vps-mount.service
        sudo rm -f /etc/systemd/system/rclone-vps-mount.service
    fi
    sudo systemctl daemon-reload
    (crontab -l 2>/dev/null | grep -v "/usr/local/bin/daily_server_report.sh") | crontab -
    if [ -f "/etc/xrdp/xrdp.ini" ]; then
        local desktop_user=$(grep 'DESKTOP_USER' ${STATE_FILE} 2>/dev/null | cut -d'=' -f2)
        if [ -n "$desktop_user" ] && id "$desktop_user" &>/dev/null; then
            echo -e "${YELLOW} 正在删除远程桌面用户: ${desktop_user} ...${NC}"
            sudo deluser --remove-home "$desktop_user" &>/dev/null
        fi
        sudo rm -f /root/.xsession
    fi
    sudo apt-get purge -y fail2ban s-nail msmtp vnstat xrdp xfce4* &>/dev/null
    sudo rm -f /etc/msmtprc /etc/s-nail.rc /usr/local/bin/daily_server_report.sh /etc/fail2ban/jail.local
    echo -e "${GREEN}     ✅     脚本安装的系统级工具已卸载。    ${NC}"

    echo -e "\n${YELLOW}     🚀     [4/6]     正在检查并可选卸载系统级Web服务器...${NC}"
    if command -v nginx &> /dev/null; then
        read -p "检测到系统范围的 Nginx，这并非本脚本安装。是否彻底卸载它及其配置? (y/n): " uninstall_nginx
        if [[ "$uninstall_nginx" == "y" || "$uninstall_nginx" == "Y" ]]; then
            sudo systemctl stop nginx
            sudo apt-get purge -y nginx nginx-common
            sudo rm -rf /etc/nginx
            echo -e "${GREEN} ✅ 系统 Nginx 已卸载。${NC}"
        fi
    fi
    if command -v apache2 &> /dev/null; then
        read -p "检测到系统范围的 Apache2，这并非本脚本安装。是否彻底卸载它及其配置? (y/n): " uninstall_apache
        if [[ "$uninstall_apache" == "y" || "$uninstall_apache" == "Y" ]]; then
            sudo systemctl stop apache2
            sudo apt-get purge -y apache2 apache2-utils
            sudo rm -rf /etc/apache2
            echo -e "${GREEN} ✅ 系统 Apache2 已卸载。${NC}"
        fi
    fi
    echo -e "${YELLOW}正在清理无用依赖...${NC}"
    sudo apt-get autoremove -y &>/dev/null
    echo -e "${GREEN}     ✅     系统环境清理完毕。    ${NC}"


    echo -e "\n${YELLOW}     🚀     [5/6]     正在销毁凭证保险箱和日志...${NC}"
    sudo rm -f ${STATE_FILE} ${RCLONE_LOG_FILE}
    echo -e "${GREEN}     ✅     凭证保险箱已销毁。    ${NC}"
    
    echo -e "\n${YELLOW}     🚀     [6/6]     正在执行最终清理... 过河拆桥...${NC}"
    sudo rm -f /usr/local/bin/zhangcaiduo
    echo -e "${GREEN}     ✅     快捷方式已移除。    ${NC}"
    
    echo -e "\n${GREEN}====================     ✅        终极还原完成        ✅     ====================${NC}"
    echo "    所有相关服务和数据已被清除。您的服务器已最大程度恢复纯净。"
    echo -e "${RED}    强烈建议您【重启服务器】以确保所有变更生效。如果想再次使用本面板，最好【重装操作系统】。${NC}"
    
    rm -- "$0"

    echo -e "\n${GREEN}    按任意键退出...${NC}"; read -n 1 -s
    exit 0
}


# ---     主循环     ---
while true; do
    show_main_menu
    read -p "    请输入您的选择 (u, m, s, 1-25, 99, q): " choice

    case $choice in
        u|U) update_system ;;
        m|M) run_unminimize ;;
        s|S) manage_swap ;;
        1) [ -d "/root/npm_data" ] && { echo -e "\n${YELLOW}网络水电总管已安装。${NC}"; sleep 2; } || install_npm ;;
        2) [ -d "/root/nextcloud_data" ] && { echo -e "\n${YELLOW}Nextcloud 套件已安装。${NC}"; sleep 2; } || install_nextcloud_suite ;;
        3) [ -d "/root/wordpress_data" ] && { echo -e "\n${YELLOW}WordPress 已安装。${NC}"; sleep 2; } || install_wordpress ;;
        4) [ -d "/root/ai_stack" ] && { echo -e "\n${YELLOW}AI 大脑已安装。${NC}"; sleep 2; } || install_ai_suite ;;
        5) [ -d "/root/jellyfin_data" ] && { echo -e "\n${YELLOW}Jellyfin 已安装。${NC}"; sleep 2; } || install_jellyfin ;;
        6) [ -d "/root/navidrome_data" ] && { echo -e "\n${YELLOW}Navidrome 已安装。${NC}"; sleep 2; } || install_navidrome ;;
        7) [ -d "/root/alist_data" ] && { echo -e "\n${YELLOW}Alist 已安装。${NC}"; sleep 2; } || install_alist ;;
        8) [ -d "/root/gitea_data" ] && { echo -e "\n${YELLOW}Gitea 已安装。${NC}"; sleep 2; } || install_gitea ;;
        9) [ -d "/root/memos_data" ] && { echo -e "\n${YELLOW}Memos 已安装。${NC}"; sleep 2; } || install_memos ;;
        10) [ -d "/root/qbittorrent_data" ] && { echo -e "\n${YELLOW}qBittorrent 已安装。${NC}"; sleep 2; } || install_qbittorrent ;;
        11) [ -d "/root/jdownloader_data" ] && { echo -e "\n${YELLOW}JDownloader 已安装。${NC}"; sleep 2; } || install_jdownloader ;;
        12) [ -d "/root/ytdlp_data" ] && { echo -e "\n${YELLOW}yt-dlp 已安装。${NC}"; sleep 2; } || install_ytdlp ;;
        15) [ -f "/etc/fail2ban/jail.local" ] && { echo -e "\n${YELLOW}Fail2ban 已安装。${NC}"; sleep 2; } || install_fail2ban ;;
        16) [ -f "/etc/xrdp/xrdp.ini" ] && { echo -e "\n${YELLOW}远程工作台已安装。${NC}"; sleep 2; } || install_desktop_env ;;
        17) [ -f "/etc/msmtprc" ] && { echo -e "\n${YELLOW}邮件管家已安装。${NC}"; sleep 2; } || install_mail_reporter ;;
        18) configure_rclone_engine ;;
        21) install_ai_model ;;
        22) run_nextcloud_optimization ;;
        23) show_service_control_panel ;;
        24) show_credentials ;;
        25) install_science_tools ;;
        99) uninstall_everything ;;
        q|Q) echo -e "${BLUE}    装修愉快，房主再见！    ${NC}"; exit 0 ;;
        *) echo -e "${RED}    无效的选项，请重新输入。    ${NC}"; sleep 2 ;;
    esac
done
