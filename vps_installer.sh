#!/bin/bash
#================================================================
# “    VPS 从零开始装修面板    ” v7.2.0 -    服务关联媒体库重构版
#    1.   采纳用户思路，将 Rclone 挂载与服务进行动态关联。
#    2.   Rclone 配置项(18)简化为只配置 remote。
#    3.   服务控制中心(23)为媒体应用增加“关联媒体库”功能。
#    4.   关联后自动重启应用，确保媒体库立即生效。
#     作者     : 張財多 zhangcaiduo.com
#================================================================

# ---     全局函数与配置     ---

STATE_FILE="/root/.vps_setup_credentials" #     用于存储密码的凭证文件
RCLONE_CONFIG_FILE="/root/.config/rclone/rclone.conf"
RCLONE_LOG_FILE="/var/log/rclone.log"
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

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

# ---     核心环境检查函数 ---
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

# ---     系统更新与基础配置函数 ---
update_system() {
    clear
    echo -e "${BLUE}---  更新系统与软件  (apt update && upgrade) ---${NC}"
    sudo apt-get update && sudo apt-get upgrade -y
    echo -e "\n${GREEN} ✅  系统更新完成！ ${NC}"
    echo -e "\n${GREEN} 按任意键返回主菜单 ...${NC}"; read -n 1 -s
}

run_unminimize() {
    clear
    echo -e "${BLUE}---  恢复至标准系统  (unminimize) ---${NC}"
    if grep -q -i "ubuntu" /etc/os-release; then
        read -p " 此操作将为最小化 Ubuntu 安装标准包,解决兼容性问题,是否继续? (y/n): " confirm
        if [[ "$confirm" == "y" || "$confirm" == "Y" ]]; then
            sudo unminimize
            echo -e "\n${GREEN} ✅  操作完成！ ${NC}"
        else
            echo -e "${GREEN} 操作已取消。 ${NC}"
        fi
    else
        echo -e "${RED} 此功能专为 Ubuntu 系统设计。 ${NC}"
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
            sudo swapoff /swapfile && sudo sed -i '/\/swapfile/d' /etc/fstab && sudo rm -f /swapfile
            echo -e "${GREEN} ✅  虚拟内存已成功移除！${NC}" && free -h
        else
            echo -e "${GREEN} 操作已取消。${NC}"
        fi
    else
        read -p " 请输入 Swap 大小 (例如: 4G) [建议为内存的1-2倍]: " swap_size
        if [ -z "$swap_size" ]; then echo -e "${RED} 输入为空，操作取消。${NC}"; sleep 2; return; fi
        sudo fallocate -l ${swap_size} /swapfile && sudo chmod 600 /swapfile && sudo mkswap /swapfile && sudo swapon /swapfile
        echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab
        echo -e "\n${GREEN} ✅  虚拟内存创建并启用成功！${NC}" && free -h
    fi
    echo -e "\n${GREEN} 按任意键返回主菜单 ...${NC}"; read -n 1 -s
}

# ---     菜单显示函数 ---
check_and_display() {
    local option_num="$1"; local text="$2"; local check_path="$3"; local status_info="$4"
    local display_text="${option_num}) ${text}"; local status_string="[ ❌  未安装 ]"
    if [ -e "$check_path" ]; then
        local type=$(echo "$status_info" | cut -d':' -f1); local details=$(echo "$status_info" | cut -d':' -f2-)
        local formatted_details=""; case "$type" in
            docker) local container_name=$(echo "$details" | cut -d':' -f1); local port=$(echo "$details" | cut -d':' -f2); formatted_details=" 容器:${container_name}, 端口:${port}";;
            docker_nopm) formatted_details=" 容器:${details} (已接入总线)";;
            system) formatted_details=" 系统服务 ";;
            system_port) formatted_details=" 服务端口: ${details}";;
            rclone) formatted_details=" 已配置 "; display_text="${GREEN}${option_num}) ${text}${NC}";;
            *) formatted_details=" 已安装 ";;
        esac
        status_string="[ ✅ ${formatted_details}]"
    fi
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
                                           zhangcaiduo.com v7.2.0
"
    echo -e "${BLUE}=========================================================================================${NC}"
    echo -e "  ${GREEN}---  地基与系统 (基础)  ---${NC}"
    printf "  %-48s\t%s\n" "u)  更新系统与软件" "[ apt update && upgrade ]"
    printf "  %-48s\t%s\n" "m)  恢复至标准系统" "[ unminimize, 仅限 Ubuntu ]"
    printf "  %-48s\t%s\n" "s)  配置虚拟内存 (Swap)" "[ 增强低配VPS性能 ]"
    echo ""
    echo -e "  ${GREEN}---  主体装修选项 (应用部署)  ---${NC}"
    check_and_display "1" "部署网络水电总管 (NPM)" "/root/npm_data" "docker:npm_app:81"
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
    echo ""
    echo -e "  ${GREEN}---  安防与工具  ---${NC}"
    check_and_display "15" "部署全屋安防系统 (Fail2ban)" "/etc/fail2ban/jail.local" "system"
    check_and_display "16" "部署远程工作台 (Xfce)" "/etc/xrdp/xrdp.ini" "system_port:3389"
    check_and_display "17" "部署邮件管家 (自动报告)" "/etc/msmtprc" "system"
    check_and_display "18" "配置 Rclone 云盘连接" "${RCLONE_CONFIG_FILE}" "rclone"
    echo ""
    echo -e "  ${GREEN}---  高级功能与维护  ---${NC}"
    printf "  %-48s\n" "21) 为 AI 大脑安装知识库 (安装模型)"
    printf "  %-48s\n" "22) 执行 Nextcloud 最终性能优化"
    printf "  %-48s\t%s\n" "23) ${CYAN}进入服务控制中心${NC}" "[ 启停/重启/关联媒体库 ]"
    printf "  %-48s\t%s\n" "24) ${CYAN}查看密码与数据路径${NC}" "[ 重要凭证 ]"
    printf "  %-48s\t%s\n" "25) ${RED}打开“科学上网”工具箱${NC}" "[ Warp, Argo, OpenVPN ]"
    echo -e "  ----------------------------------------------------------------------------------------"
    printf "  %-48s\t%s\n" "99) ${RED}一键辞退包工头${NC}" "${RED}[ 注：此选项将会拆卸本脚本！！！ ]${NC}"
    printf "  %-48s\t%s\n" "q)  退出面板" ""
    echo -e "${BLUE}=========================================================================================${NC}"
}

# ---     前置检查     ---
check_npm_installed() { if [ ! -d "/root/npm_data" ]; then echo -e "${RED}错误:此功能依赖“网络水电总管”,请先执行选项1安装!${NC}"; sleep 3; return 1; fi; return 0; }

# ---     应用安装函数 ---
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

install_nextcloud_suite() {
    ensure_docker_installed || return
    check_npm_installed || return
    read -p "    请输入您的主域名     (    例如     zhangcaiduo.com): " MAIN_DOMAIN
    if [ -z "$MAIN_DOMAIN" ]; then echo -e "${RED}     错误：主域名不能为空！    ${NC}"; sleep 2; return; fi

    NEXTCLOUD_DOMAIN="nextcloud.${MAIN_DOMAIN}"
    ONLYOFFICE_DOMAIN="onlyoffice.${MAIN_DOMAIN}"
    DB_PASSWORD="NcDb-pW_$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 12)"
    ONLYOFFICE_JWT_SECRET="JwtS3cr3t-$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 16)"

    clear; echo -e "${BLUE}--- “Nextcloud 家庭数据中心”部署计划启动！ ---${NC}";
    
    mkdir -p /root/nextcloud_data
    cat > /root/nextcloud_data/docker-compose.yml <<EOF
services:
  db:
    image: mariadb:11.4
    container_name: nextcloud_db
    restart: unless-stopped
    command: [--transaction-isolation=READ-COMMITTED, --binlog-format=ROW, --character-set-server=utf8mb4, --collation-server=utf8mb4_unicode_ci]
    volumes: ['./db:/var/lib/mysql']
    environment:
      MYSQL_DATABASE: nextclouddb
      MYSQL_USER: nextclouduser
      MYSQL_PASSWORD: ${DB_PASSWORD}
      MYSQL_ROOT_PASSWORD: ${DB_PASSWORD}_root
    networks: [- npm_network]
  redis:
    image: redis:alpine
    container_name: nextcloud_redis
    restart: unless-stopped
    networks: [- npm_network]
  app:
    image: nextcloud:latest
    container_name: nextcloud_app
    restart: unless-stopped
    volumes:
      - './html:/var/www/html'
      - './php-opcache.ini:/usr/local/etc/php/conf.d/opcache-recommended.ini'
    depends_on: [db, redis]
    networks: [- npm_network]
networks:
  npm_network: { name: npm_data_default, external: true }
EOF
    echo -e "opcache.memory_consumption=512\nopcache.interned_strings_buffer=16" > /root/nextcloud_data/php-opcache.ini
    if !(cd /root/nextcloud_data && sudo docker-compose up -d); then
        echo -e "${RED}❌ Nextcloud 部署失败！${NC}"; sleep 4; return
    fi; echo -e "${GREEN}✅ 数据中心主体 (Nextcloud) 启动完毕！${NC}"

    mkdir -p /root/onlyoffice_data
    cat > /root/onlyoffice_data/docker-compose.yml <<EOF
services:
  onlyoffice:
    image: onlyoffice/documentserver:latest
    container_name: onlyoffice_app
    restart: always
    volumes: ['./data:/var/www/onlyoffice/Data', './logs:/var/log/onlyoffice']
    environment: { JWT_ENABLED: 'true', JWT_SECRET: ${ONLYOFFICE_JWT_SECRET} }
    networks: [- npm_network]
networks:
  npm_network: { name: npm_data_default, external: true }
EOF
    if !(cd /root/onlyoffice_data && sudo docker-compose up -d); then
        echo -e "${RED}❌ OnlyOffice 部署失败！${NC}"; sleep 4; return
    fi; echo -e "${GREEN}✅ 在线办公室 (OnlyOffice) 部署完毕！${NC}"

    echo "## Nextcloud 套件凭证 (部署于: $(date))" > ${STATE_FILE}
    echo "NEXTCLOUD_DOMAIN=${NEXTCLOUD_DOMAIN}" >> ${STATE_FILE}
    echo "ONLYOFFICE_DOMAIN=${ONLYOFFICE_DOMAIN}" >> ${STATE_FILE}
    echo "DB_PASSWORD=${DB_PASSWORD}" >> ${STATE_FILE}
    echo "ONLYOFFICE_JWT_SECRET=${ONLYOFFICE_JWT_SECRET}" >> ${STATE_FILE}

    show_credentials; echo -e "\n${GREEN}按任意键返回主菜单 ...${NC}"; read -n 1 -s
}

install_wordpress() {
    ensure_docker_installed || return; check_npm_installed || return
    read -p "请输入您的 WordPress 主域名 (例: zhangcaiduo.com): " WP_DOMAIN
    if [ -z "$WP_DOMAIN" ]; then echo -e "${RED}错误：域名不能为空！${NC}"; sleep 2; return; fi

    WP_DB_PASS="WpDb-pW_$(head /dev/urandom|tr -dc A-Za-z0-9|head -c 12)"
    WP_DB_ROOT_PASS="WpRoot-pW_$(head /dev/urandom|tr -dc A-Za-z0-9|head -c 12)"

    clear; echo -e "${BLUE}--- “WordPress 个人博客”建造计划启动！ ---${NC}";
    mkdir -p /root/wordpress_data
    cat > /root/wordpress_data/docker-compose.yml <<EOF
services:
  db:
    image: mariadb:11.4
    container_name: wordpress_db
    restart: unless-stopped
    volumes: ['./db_data:/var/lib/mysql']
    environment:
      MYSQL_ROOT_PASSWORD: ${WP_DB_ROOT_PASS}
      MYSQL_DATABASE: wordpress
      MYSQL_USER: wordpress
      MYSQL_PASSWORD: ${WP_DB_PASS}
    networks: [- npm_network]
  wordpress:
    image: wordpress:latest
    container_name: wordpress_app
    restart: unless-stopped
    volumes: ['./html:/var/www/html']
    environment:
      WORDPRESS_DB_HOST: wordpress_db
      WORDPRESS_DB_USER: wordpress
      WORDPRESS_DB_PASSWORD: ${WP_DB_PASS}
      WORDPRESS_DB_NAME: wordpress
    depends_on: [db]
    networks: [- npm_network]
networks:
  npm_network: { name: npm_data_default, external: true }
EOF
    if (cd /root/wordpress_data && sudo docker-compose up -d); then
        echo -e "${GREEN}✅ WordPress 已在后台启动！${NC}"
        echo -e "\n## WordPress 凭证 (部署于: $(date))" >> ${STATE_FILE}
        echo "WORDPRESS_DOMAIN=${WP_DOMAIN}" >> ${STATE_FILE}
        echo -e "\n${GREEN}=============== ✅ WordPress 部署完成 ✅ ===============${NC}"
        echo "请在 NPM 中为 ${BLUE}${WP_DOMAIN}${NC} (及 www.${WP_DOMAIN}) 配置代理,指向 ${BLUE}wordpress_app:80${NC}"
    else
        echo -e "${RED}❌ WordPress 部署失败！请检查上面的错误信息。${NC}"
    fi
    echo -e "\n${GREEN}按任意键返回主菜单 ...${NC}"; read -n 1 -s
}

install_ai_suite() {
    ensure_docker_installed || return; check_npm_installed || return
    read -p "请输入您为 AI 规划的子域名 (例: ai.zhangcaiduo.com): " AI_DOMAIN
    if [ -z "$AI_DOMAIN" ]; then echo -e "${RED}错误：AI 域名不能为空！${NC}"; sleep 2; return; fi
    clear; echo -e "${BLUE}--- “AI 大脑”激活计划启动！ ---${NC}";
    mkdir -p /root/ai_stack
    cat > /root/ai_stack/docker-compose.yml <<'EOF'
services:
  ollama:
    image: ollama/ollama
    container_name: ollama_app
    restart: unless-stopped
    volumes: ['./ollama_data:/root/.ollama']
    networks: [- npm_network]
  open-webui:
    image: 'ghcr.io/open-webui/open-webui:latest'
    container_name: open_webui_app
    restart: unless-stopped
    environment: ['OLLAMA_BASE_URL=http://ollama_app:11434']
    depends_on: [ollama]
    networks: [- npm_network]
networks:
  npm_network: { name: npm_data_default, external: true }
EOF
    if (cd /root/ai_stack && sudo docker-compose up -d); then
        echo -e "${GREEN}✅ AI 核心已在后台启动！${NC}"
        echo -e "\n## AI 核心凭证 (部署于: $(date))" >> ${STATE_FILE}; echo "AI_DOMAIN=${AI_DOMAIN}" >> ${STATE_FILE}
        echo -e "\n${GREEN}AI 核心部署完成! 强烈建议立即选择一个知识库进行安装!${NC}"
        install_ai_model
    else
        echo -e "${RED}❌ AI 核心部署失败！${NC}"; echo -e "\n${GREEN}按任意键返回主菜单 ...${NC}"; read -n 1 -s
    fi
}

install_jellyfin() {
    ensure_docker_installed || return; check_npm_installed || return
    clear; echo -e "${BLUE}--- “Jellyfin 家庭影院”建造计划启动！ ---${NC}";
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
    networks: [- npm_network]
networks:
  npm_network: { name: npm_data_default, external: true }
EOF
    if (cd /root/jellyfin_data && sudo docker-compose up -d); then
        echo -e "${GREEN}✅ Jellyfin 已在后台启动！${NC}\n${CYAN}下一步: 请进入服务控制中心(23)为Jellyfin关联您的云盘媒体库。${NC}"
    else
        echo -e "${RED}❌ Jellyfin 部署失败！请检查 Docker 是否正常运行。${NC}"
    fi
    echo -e "\n${GREEN}按任意键返回主菜单 ...${NC}"; read -n 1 -s
}

install_navidrome() {
    ensure_docker_installed || return; check_npm_installed || return
    clear; echo -e "${BLUE}--- “Navidrome 音乐服务器”部署计划启动！ ---${NC}"
    mkdir -p /root/navidrome_data /mnt/Music
    cat > /root/navidrome_data/docker-compose.yml <<'EOF'
services:
  navidrome:
    image: deluan/navidrome:latest
    container_name: navidrome_app
    restart: unless-stopped
    environment:
      - 'PUID=1000'
      - 'PGID=1000'
      - 'ND_LOGLEVEL=info'
      - 'TZ=Asia/Shanghai'
    volumes:
      - './data:/data'
      - '/mnt/Music:/music'
    networks: [- npm_network]
networks:
  npm_network: { name: npm_data_default, external: true }
EOF
    if (cd /root/navidrome_data && sudo docker-compose up -d); then
        echo -e "${GREEN}✅ Navidrome 已在后台启动！${NC}\n${CYAN}下一步: 请进入服务控制中心(23)为Navidrome关联您的云盘音乐库。${NC}"
    else
        echo -e "${RED}❌ Navidrome 部署失败！请检查 Docker 是否正常运行。${NC}"
    fi
    echo -e "\n${GREEN}按任意键返回主菜单 ...${NC}"; read -n 1 -s
}

install_alist() {
    ensure_docker_installed || return; check_npm_installed || return
    clear; echo -e "${BLUE}--- “Alist 网盘挂载”部署计划启动！ ---${NC}"
    mkdir -p /root/alist_data
    cat >/root/alist_data/docker-compose.yml <<'EOF'
services:
  alist:
    image: xhofe/alist:latest
    container_name: alist_app
    restart: unless-stopped
    volumes: ['./data:/opt/alist/data']
    networks: [- npm_network]
networks:
  npm_network: { name: npm_data_default, external: true }
EOF
    if (cd /root/alist_data && sudo docker-compose up -d); then
        echo -e "${GREEN}✅ Alist 已启动！内部端口: 5244 ${NC}"
        echo -e "${CYAN}请使用以下命令查看初始密码: sudo docker exec alist_app ./alist admin ${NC}"
    else
        echo -e "${RED}❌ Alist 部署失败！${NC}"
    fi
    echo -e "\n${GREEN}按任意键返回主菜单 ...${NC}"; read -n 1 -s
}

install_gitea() {
    ensure_docker_installed || return; check_npm_installed || return
    clear; echo -e "${BLUE}--- “Gitea 代码仓库”部署计划启动！ ---${NC}"
    mkdir -p /root/gitea_data
    cat >/root/gitea_data/docker-compose.yml <<'EOF'
services:
  server:
    image: gitea/gitea:latest
    container_name: gitea_app
    restart: unless-stopped
    environment: ['USER_UID=1000', 'USER_GID=1000']
    volumes: ['./gitea:/data', '/etc/timezone:/etc/timezone:ro', '/etc/localtime:/etc/localtime:ro']
    networks: [- npm_network]
networks:
  npm_network: { name: npm_data_default, external: true }
EOF
    if (cd /root/gitea_data && sudo docker-compose up -d); then
        echo -e "${GREEN}✅ Gitea 已启动！内部端口: 3000 ${NC}"
    else
        echo -e "${RED}❌ Gitea 部署失败！${NC}"
    fi
    echo -e "\n${GREEN}按任意键返回主菜单 ...${NC}"; read -n 1 -s
}

install_memos() {
    ensure_docker_installed || return; check_npm_installed || return
    clear; echo -e "${BLUE}--- “Memos 轻量笔记”部署计划启动！ ---${NC}"
    mkdir -p /root/memos_data
    cat >/root/memos_data/docker-compose.yml <<'EOF'
services:
  memos:
    image: neosmemo/memos:latest
    container_name: memos_app
    restart: always
    volumes: ['./data:/var/opt/memos']
    networks: [- npm_network]
networks:
  npm_network: { name: npm_data_default, external: true }
EOF
    if (cd /root/memos_data && sudo docker-compose up -d); then
        echo -e "${GREEN}✅ Memos 已启动！内部端口: 5230 ${NC}"
    else
        echo -e "${RED}❌ Memos 部署失败！${NC}"
    fi
    echo -e "\n${GREEN}按任意键返回主菜单 ...${NC}"; read -n 1 -s
}

install_qbittorrent() {
    ensure_docker_installed || return; check_npm_installed || return
    clear; echo -e "${BLUE}--- “qBittorrent 下载器”部署计划启动！ ---${NC}"
    mkdir -p /root/qbittorrent_data /mnt/Downloads
    cat > /root/qbittorrent_data/docker-compose.yml <<'EOF'
services:
  qbittorrent:
    image: lscr.io/linuxserver/qbittorrent:latest
    container_name: qbittorrent_app
    restart: unless-stopped
    environment: ['PUID=1000', 'PGID=1000', 'TZ=Asia/Shanghai', 'WEBUI_PORT=8080']
    volumes: ['./config:/config', '/mnt/Downloads:/downloads']
    networks: [- npm_network]
networks:
  npm_network: { name: npm_data_default, external: true }
EOF
    if (cd /root/qbittorrent_data && sudo docker-compose up -d); then
        echo -e "${GREEN}✅ qBittorrent 已启动！${NC}\n${CYAN}下一步: 可选进入服务控制中心(23)为qB关联您的云盘下载目录。${NC}"
    else
        echo -e "${RED}❌ qBittorrent 部署失败！${NC}"
    fi
    echo -e "\n${GREEN}按任意键返回主菜单 ...${NC}"; read -n 1 -s
}

install_jdownloader() {
    ensure_docker_installed || return; check_npm_installed || return
    clear; echo -e "${BLUE}--- “JDownloader 下载器”部署计划启动！ ---${NC}"
    JDOWNLOADER_PASS="VNC-Pass-$(head /dev/urandom|tr -dc A-Za-z0-9|head -c 8)"
    mkdir -p /root/jdownloader_data /mnt/Downloads
    cat > /root/jdownloader_data/docker-compose.yml <<EOF
services:
  jdownloader-2:
    image: jlesage/jdownloader-2
    container_name: jdownloader_app
    restart: unless-stopped
    environment: ['USER_ID=1000', 'GROUP_ID=1000', 'TZ=Asia/Shanghai', 'VNC_PASSWORD=${JDOWNLOADER_PASS}']
    volumes: ['./config:/config', '/mnt/Downloads:/output']
    networks: [- npm_network]
networks:
  npm_network: { name: npm_data_default, external: true }
EOF
    if (cd /root/jdownloader_data && sudo docker-compose up -d); then
        echo "JDOWNLOADER_VNC_PASSWORD=${JDOWNLOADER_PASS}" >> ${STATE_FILE}
        echo -e "${GREEN}✅ JDownloader 已启动！VNC 密码 ${JDOWNLOADER_PASS} 已保存。${NC}"
    else
        echo -e "${RED}❌ JDownloader 部署失败！${NC}"
    fi
    echo -e "\n${GREEN}按任意键返回主菜单 ...${NC}"; read -n 1 -s
}

install_ytdlp() {
    ensure_docker_installed || return; check_npm_installed || return
    read -p "请输入您为 yt-dlp 规划的子域名 (例 ytdl.zhangcaiduo.com): " YTDL_DOMAIN
    if [ -z "$YTDL_DOMAIN" ]; then echo -e "${RED}域名不能为空，安装取消。${NC}"; sleep 2; return; fi
    clear; echo -e "${BLUE}--- “yt-dlp 视频下载器”部署计划启动！ ---${NC}"
    mkdir -p /root/ytdlp_data /mnt/Downloads
    cat > /root/ytdlp_data/docker-compose.yml <<EOF
services:
  ytdlp-ui:
    image: tzahi12345/youtubedl-material:latest
    container_name: ytdlp_app
    restart: unless-stopped
    environment: ['BACKEND_URL=https://${YTDL_DOMAIN}']
    volumes: ['/mnt/Downloads:/app/downloads', './config:/app/config']
    networks: [- npm_network]
networks:
  npm_network: { name: npm_data_default, external: true }
EOF
    if (cd /root/ytdlp_data && sudo docker-compose up -d); then
        echo "YTDL_DOMAIN=${YTDL_DOMAIN}" >> ${STATE_FILE}
        echo -e "${GREEN}✅ yt-dlp 已启动！请配置NPM反代到 ytdlp_app:8080 ${NC}"
    else
        echo -e "${RED}❌ yt-dlp 部署失败！${NC}"
    fi
    echo -e "\n${GREEN}按任意键返回主菜单 ...${NC}"; read -n 1 -s
}

install_fail2ban() {
    clear; echo -e "${BLUE}--- “全屋安防系统”部署计划启动！ ---${NC}"
    sudo apt-get install -y fail2ban
    sudo tee /etc/fail2ban/jail.local > /dev/null <<'EOF'
[DEFAULT]
bantime = 2h; findtime = 10m; maxretry = 5; backend = systemd
[sshd]
enabled = true
[nginx-http-auth]
enabled = true; logpath = /root/npm_data/data/logs/*.log
[nginx-badbots]
enabled = true; logpath = /root/npm_data/data/logs/*.log
[nextcloud]
enabled = true; logpath = /root/nextcloud_data/html/data/nextcloud.log
[recidive]
enabled = true; logpath = /var/log/fail2ban.log; bantime = 1w; findtime = 1d; maxretry = 5
EOF
    sudo systemctl restart fail2ban; sudo systemctl enable fail2ban
    echo -e "${GREEN}✅ 安防规则配置完毕并已激活！${NC}"; echo -e "\n${GREEN}按任意键返回主菜单 ...${NC}"; read -n 1 -s
}

install_desktop_env() {
    clear; echo -e "${BLUE}--- “远程工作台”建造计划启动！ ---${NC}";
    export DEBIAN_FRONTEND=noninteractive
    sudo apt-get update; sudo apt-get install -y xfce4 xfce4-goodies xrdp
    sudo sed -i 's/AllowRootLogin=true/AllowRootLogin=false/g' /etc/xrdp/sesman.ini
    sudo systemctl enable --now xrdp; echo xfce4-session > ~/.xsession; sudo adduser xrdp ssl-cert; sudo systemctl restart xrdp
    read -p "请输入您想创建的新用户名 (例如 zhangcaiduo): " NEW_USER
    if [ -z "$NEW_USER" ]; then echo -e "${RED}用户名不能为空，操作取消。${NC}"; sleep 2; return; fi
    sudo adduser --gecos "" "$NEW_USER"; echo "DESKTOP_USER=${NEW_USER}" >> ${STATE_FILE}
    echo -e "${YELLOW}请为新账户 '$NEW_USER' 设置登录密码...${NC}"; sudo passwd "$NEW_USER"
    echo -e "\n${GREEN}✅ 远程工作台建造完毕！请用【${NEW_USER}】及新密码登录远程桌面。${NC}"; echo -e "\n${GREEN}按任意键返回 ...${NC}"; read -n 1 -s
}

install_mail_reporter() {
    clear; echo -e "${BLUE}--- “服务器每日管家”安装程序 ---${NC}"
    DEBIAN_FRONTEND=noninteractive sudo apt-get install -y --no-install-recommends s-nail msmtp cron vnstat
    read -p "请输入您的邮箱地址 (例: yourname@qq.com): " mail_user
    read -sp "请输入邮箱的“应用密码”或“授权码”(可粘贴): " mail_pass; echo
    read -p "请输入邮箱的 SMTP 服务器地址 (例: smtp.qq.com): " mail_server
    read -p "请输入接收报告的邮箱地址 (可同上): " to_email
    sudo tee /etc/msmtprc > /dev/null <<EOF
defaults; auth on; tls on; tls_starttls on; tls_trust_file /etc/ssl/certs/ca-certificates.crt
account default; host ${mail_server}; port 587; from ${mail_user}; user ${mail_user}; password ${mail_pass}
EOF
    sudo chmod 600 /etc/msmtprc; echo "set mta=/usr/bin/msmtp" | sudo tee /etc/s-nail.rc > /dev/null
    REPORT_SCRIPT_PATH="/usr/local/bin/daily_server_report.sh"
    sudo tee $REPORT_SCRIPT_PATH > /dev/null <<'EOF'
#!/bin/bash
HOSTNAME=$(hostname); CURRENT_TIME=$(date "+%Y-%m-%d %H:%M:%S"); UPTIME=$(uptime -p)
TRAFFIC_INFO=$(vnstat -d 1); FAILED_LOGINS=$(grep -c "Failed password" /var/log/auth.log || echo "0")
SUBJECT="【服务器管家报告】来自 \$HOSTNAME - $(date "+%Y-%m-%d")"
HTML_BODY="<html><body><h2>服务器每日管家报告</h2><p><b>主机名:</b> \$HOSTNAME</p><p><b>报告时间:</b> \$CURRENT_TIME</p><hr><h3>核心状态:</h3><ul><li><b>已持续运行:</b> \$UPTIME</li><li><b>SSH登录失败次数(今日):</b><strong style='color:red;'>\$FAILED_LOGINS 次</strong></li></ul><hr><h3>今日网络流量:</h3><pre style='background-color:#f5f5f5; padding:10px;'>\$TRAFFIC_INFO</pre></body></html>"
echo "\$HTML_BODY" | s-nail -s "\$SUBJECT" -a "Content-Type: text/html" "$to_email"
EOF
    sudo chmod +x $REPORT_SCRIPT_PATH
    (crontab -l 2>/dev/null | grep -v "$REPORT_SCRIPT_PATH" ; echo "30 23 * * * $REPORT_SCRIPT_PATH") | crontab -
    echo "这是一封来自【服务器每日管家】的安装成功测试邮件！" | s-nail -s "【服务器管家】安装成功测试" "$to_email"
    echo -e "\n${GREEN}✅ 邮件管家部署完成！已发送测试邮件。${NC}"; echo -e "\n${GREEN}按任意键返回 ...${NC}"; read -n 1 -s
}

configure_rclone_remote() {
    clear; echo -e "${BLUE}--- “Rclone 云盘连接”配置向导 ---${NC}"
    echo -e "${YELLOW}此功能只负责完成 Rclone 与云盘的连接认证。${NC}"
    echo -e "${YELLOW}具体的文件夹同步/挂载，请到“服务控制中心(23)”内，针对具体应用进行关联。${NC}"; sleep 4
    if ! command -v rclone &> /dev/null; then
        echo -e "\n${YELLOW}🚀 正在为您安装 Rclone...${NC}"
        curl https://rclone.org/install.sh | sudo bash; sudo apt-get install -y fuse3
        echo -e "${GREEN}✅ Rclone 已安装完毕！${NC}"; sleep 2
    fi
    if [ -f "${RCLONE_CONFIG_FILE}" ]; then
        echo -e "\n${YELLOW}检测到已存在 Rclone 配置文件。${NC}"
        read -p "您要重新配置吗? (y/n): " reconfig
        if [[ "$reconfig" != "y" && "$reconfig" != "Y" ]]; then echo -e "${GREEN}操作取消。${NC}"; sleep 2; return; fi
    fi
    echo -e "\n${CYAN}即将启动 Rclone 官方交互式配置工具...${NC}"
    echo -e "${YELLOW} - 新建 remote 时, 名字建议设为: onedrive (或其他您能记住的名字)${NC}"
    echo -e "${YELLOW} - 若在SSH中, 必须对 'Use auto config?' 选 'n', 然后复制链接到浏览器完成授权。${NC}"
    read -p "准备好后，请按任意键继续..." -n 1 -s; echo
    rclone config
    if [ ! -f "${RCLONE_CONFIG_FILE}" ]; then echo -e "\n${RED}错误：配置未成功保存。${NC}"; else echo -e "\n${GREEN}✅ Rclone 配置文件已成功创建/更新！${NC}"; fi
    echo -e "\n${GREEN}按任意键返回 ...${NC}"; read -n 1 -s
}

link_media_to_service() {
    local service_type="$1"
    if [ ! -f "${RCLONE_CONFIG_FILE}" ]; then
        echo -e "${RED}错误: 未找到 Rclone 配置文件!${NC}"
        echo -e "${YELLOW}请先在主菜单选择“配置 Rclone 云盘连接”(18)完成设置。${NC}"; sleep 4; return
    fi
    
    local paths=(); case "$service_type" in
        navidrome) paths=("/mnt/Music" "请输入您在云盘上的【音乐】文件夹路径" "Music" "rclone-music" "navidrome_app");;
        jellyfin_music) paths=("/mnt/Music" "请输入您在云盘上的【音乐】文件夹路径" "Music" "rclone-music" "jellyfin_app");;
        jellyfin_movies) paths=("/mnt/Movies" "请输入您在云盘上的【电影】文件夹路径" "Movies" "rclone-movies" "jellyfin_app");;
        jellyfin_tv) paths=("/mnt/TVShows" "请输入您在云盘上的【剧集】文件夹路径" "TVShows" "rclone-tvshows" "jellyfin_app");;
        qbittorrent) paths=("/mnt/Downloads" "请输入您在云盘上的【下载】文件夹路径" "Downloads" "rclone-downloads" "qbittorrent_app");;
        *) echo -e "${RED}内部错误: 未知的服务类型。${NC}"; sleep 2; return;;
    esac
    local local_path="${paths[0]}"; local remote_path_prompt="${paths[1]}"; local default_remote_path="${paths[2]}"
    local rclone_service_name="${paths[3]}"; local docker_container_name="${paths[4]}"

    clear; echo -e "${BLUE}--- 正在为 ${docker_container_name} 关联媒体库 ---${NC}"
    echo -e "${YELLOW}${remote_path_prompt}${NC}"; read -p "留空将使用默认值 [${default_remote_path}]: " onedrive_path
    onedrive_path=${onedrive_path:-$default_remote_path}

    echo -e "\n${CYAN}即将把云盘的 onedrive:${onedrive_path} 挂载到本地的 ${local_path} ...${NC}"; sleep 3
    sudo mkdir -p "${local_path}"
    
    sudo tee "/etc/systemd/system/${rclone_service_name}.service" > /dev/null <<EOF
[Unit]
Description=Rclone Mount for ${onedrive_path} to ${local_path}
Wants=network-online.target
After=network-online.target
[Service]
Type=simple; User=root; Group=root; RestartSec=10; Restart=on-failure
ExecStart=/usr/bin/rclone mount onedrive:${onedrive_path} ${local_path} \\
--config ${RCLONE_CONFIG_FILE} --uid 1000 --gid 1000 --allow-other --allow-non-empty \\
--vfs-cache-mode writes --vfs-cache-max-size 5G --log-level INFO --log-file ${RCLONE_LOG_FILE}
ExecStop=/bin/fusermount -u ${local_path}
[Install]
WantedBy=default.target
EOF

    sudo systemctl daemon-reload; sudo systemctl enable --now "${rclone_service_name}.service"; sleep 2
    if systemctl is-active --quiet "${rclone_service_name}.service"; then
        echo -e "${GREEN}✅ 同步通道 ${onedrive_path} -> ${local_path} 已成功激活！${NC}"
        echo -e "${YELLOW}🚀 正在重启 ${docker_container_name} 以应用新的媒体库...${NC}"
        sudo docker restart "${docker_container_name}"
        echo -e "${GREEN}✅ 重启完成！现在您的应用应该能看到云盘文件了。${NC}"
    else
        echo -e "${RED}❌ 同步通道启动失败！请检查日志。${NC}"
        echo -e "${YELLOW}显示最近的 10 行日志 (${RCLONE_LOG_FILE}):${NC}"; sudo tail -n 10 ${RCLONE_LOG_FILE}
    fi
    echo -e "\n${GREEN}按任意键返回 ...${NC}"; read -n 1 -s
}

show_service_control_panel() {
    ensure_docker_installed || return
    while true; do
        clear; echo -e "${BLUE}--- 服务控制中心 ---${NC}"; echo "请选择要操作的服务:"
        declare -a services=("Nextcloud:/root/nextcloud_data" "NPM:/root/npm_data" "OnlyOffice:/root/onlyoffice_data" "WordPress:/root/wordpress_data" "AI大脑:/root/ai_stack" "Jellyfin:/root/jellyfin_data" "Navidrome:/root/navidrome_data" "Alist:/root/alist_data" "Gitea:/root/gitea_data" "Memos:/root/memos_data" "qBittorrent:/root/qbittorrent_data" "JDownloader:/root/jdownloader_data" "yt-dlp:/root/ytdlp_data")
        local i=1; declare -a active_services=();
        for service_entry in "${services[@]}"; do
            local name=$(echo $service_entry | cut -d':' -f1); local path=$(echo $service_entry | cut -d':' -f2)
            if [ -f "${path}/docker-compose.yml" ]; then
                if sudo docker-compose -f ${path}/docker-compose.yml ps -q 2>/dev/null | grep -q .; then status="${GREEN}[ 运行中 ]${NC}"; else status="${RED}[ 已停止 ]${NC}"; fi
                printf "  %2d) %-25s %s\n" "$i" "$name" "$status"; active_services+=("$name:$path"); i=$((i+1));
            fi
        done
        echo "------------------------------------"; echo "  b) 返回主菜单"; read -p "请输入数字选择服务, 或 'b' 返回: " service_choice
        if [[ "$service_choice" == "b" || "$service_choice" == "B" ]]; then break; fi
        local index=$((service_choice-1))
        if [[ $index -ge 0 && $index -lt ${#active_services[@]} ]]; then
            local selected_service=${active_services[$index]}; local s_name=$(echo $selected_service | cut -d':' -f1); local s_path=$(echo $selected_service | cut -d':' -f2)
            while true; do
                clear; echo -e "正在操作服务: ${CYAN}${s_name}${NC}"
                echo "1) 启动"; echo "2) 停止"; echo "3) 重启"; echo "4) 查看日志 (Ctrl+C 退出)"
                local has_media_option=false
                if [[ "$s_name" == "Navidrome" || "$s_name" == "Jellyfin" || "$s_name" == "qBittorrent" ]]; then
                    echo -e "5) ${YELLOW}关联媒体库 (连接至 OneDrive)${NC}"; has_media_option=true
                fi
                echo "b) 返回上级菜单"; read -p "请选择操作: " action_choice
                case $action_choice in
                    1) (cd $s_path && sudo docker-compose up -d); echo -e "${GREEN}${s_name} 已启动!${NC}"; sleep 2;;
                    2) (cd $s_path && sudo docker-compose stop); echo -e "${YELLOW}${s_name} 已停止!${NC}"; sleep 2;;
                    3) (cd $s_path && sudo docker-compose restart); echo -e "${CYAN}${s_name} 已重启!${NC}"; sleep 2;;
                    4) sudo docker-compose -f ${s_path}/docker-compose.yml logs -f --tail 50;;
                    5) if $has_media_option; then
                            if [[ "$s_name" == "Navidrome" ]]; then link_media_to_service "navidrome"
                            elif [[ "$s_name" == "qBittorrent" ]]; then link_media_to_service "qbittorrent"
                            elif [[ "$s_name" == "Jellyfin" ]]; then
                                clear; echo -e "为 Jellyfin 关联哪个媒体库?"; echo "1) 音乐库"; echo "2) 电影库"; echo "3) 剧集库"; echo "b) 返回"
                                read -p "请选择: " jellyfin_choice
                                case $jellyfin_choice in
                                    1) link_media_to_service "jellyfin_music";; 2) link_media_to_service "jellyfin_movies";;
                                    3) link_media_to_service "jellyfin_tv";; *) continue;;
                                esac
                            fi
                        else echo -e "${RED}无效操作!${NC}"; sleep 2; fi;;
                    b) break;; *) echo -e "${RED}无效操作!${NC}"; sleep 2;;
                esac
            done
        else echo -e "${RED}无效选择!${NC}"; sleep 2; fi
    done
}

# --- 其他高级函数 (为节省篇幅，省略未改动部分) ---
# install_ai_model, run_nextcloud_optimization, show_credentials, etc.
# install_science_tools, uninstall_everything

# --- 主循环 ---
while true; do
    show_main_menu
    read -p "    请输入您的选择 (u, m, s, 1-25, 99, q): " choice
    case $choice in
        u|U) update_system ;; m|M) run_unminimize ;; s|S) manage_swap ;;
        1) [ -d "/root/npm_data" ] && { echo -e "\n${YELLOW}NPM 已安装。${NC}"; sleep 2; } || install_npm ;;
        2) [ -d "/root/nextcloud_data" ] && { echo -e "\n${YELLOW}Nextcloud 已安装。${NC}"; sleep 2; } || install_nextcloud_suite ;;
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
        18) configure_rclone_remote ;;
        21) install_ai_model ;; 22) run_nextcloud_optimization ;;
        23) show_service_control_panel ;; 24) show_credentials ;;
        25) install_science_tools ;; 99) uninstall_everything ;;
        q|Q) echo -e "${BLUE}装修愉快，房主再见！${NC}"; exit 0 ;;
        *) echo -e "${RED}无效的选项，请重新输入。${NC}"; sleep 2 ;;
    esac
done
