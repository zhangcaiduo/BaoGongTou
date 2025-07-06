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

# ---     安装函数 (省略部分未改动的函数以节省篇幅) ---
# ... (install_npm, install_nextcloud_suite, etc. 保持不变) ...
# 为了让您看清核心改动，这里只列出被修改和新增的函数
# 您在替换时，请使用包含了所有函数的完整版本

# ---     应用安装函数 (仅作示例，实际脚本中是完整的) ---
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
    environment:
      - 'PUID=1000'
      - 'PGID=1000'
      - 'ND_LOGLEVEL=info'
      - 'TZ=Asia/Shanghai'
    volumes:
      - './data:/data'
      - '/mnt/Music:/music'
    networks:
      - npm_network
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
  npm_network: { name: npm_data_default, external: true }
EOF
    if (cd /root/qbittorrent_data && sudo docker-compose up -d); then
        echo -e "${GREEN}✅ qBittorrent 已在后台启动！${NC}\n${CYAN}下一步: 可选进入服务控制中心(23)为qBittorrent关联您的云盘下载目录。${NC}"
    else
        echo -e "${RED}❌ qBittorrent 部署失败！请检查 Docker 是否正常运行。${NC}"
    fi
    echo -e "\n${GREEN}按任意键返回主菜单 ...${NC}"; read -n 1 -s
}


# 18. Rclone     云盘连接 (v7.2.0 简化)
configure_rclone_remote() {
    clear
    echo -e "${BLUE}--- “Rclone 云盘连接”配置向导 ---${NC}"
    echo -e "${YELLOW}此功能只负责完成 Rclone 与云盘的连接认证。${NC}"
    echo -e "${YELLOW}具体的文件夹同步/挂载，请到“服务控制中心(23)”内，针对具体应用进行关联。${NC}"
    sleep 4

    if ! command -v rclone &> /dev/null; then
        echo -e "\n${YELLOW}🚀 正在为您安装 Rclone 主程序...${NC}"
        curl https://rclone.org/install.sh | sudo bash
        sudo apt-get install -y fuse3
        echo -e "${GREEN}✅ Rclone 已安装完毕！${NC}"; sleep 2
    fi

    if [ -f "${RCLONE_CONFIG_FILE}" ]; then
        echo -e "\n${YELLOW}检测到已存在 Rclone 配置文件。${NC}"
        read -p "您要重新配置吗? (y/n): " reconfig
        if [[ "$reconfig" != "y" && "$reconfig" != "Y" ]]; then
            echo -e "${GREEN}操作取消。${NC}"; sleep 2; return
        fi
    fi
    
    echo -e "\n${CYAN}即将启动 Rclone 官方交互式配置工具...${NC}"
    echo "----------------------------------------------------------"
    echo -e " - ${YELLOW}新建 remote 时, 名字建议设为: onedrive (或其他您能记住的名字)${NC}"
    echo -e " - ${YELLOW}当询问 'Use auto config?' 时, 若您在SSH中, 必须选 'n' (no)${NC}"
    echo -e " - ${YELLOW}然后将显示的链接复制到您本地电脑的浏览器中打开，完成授权，再将获得的 token 粘贴回来。${NC}"
    echo "----------------------------------------------------------"
    read -p "准备好后，请按任意键继续..." -n 1 -s; echo
    
    rclone config
    
    if [ ! -f "${RCLONE_CONFIG_FILE}" ]; then
        echo -e "\n${RED}错误：配置似乎未成功保存。请重新尝试。${NC}"
    else
        echo -e "\n${GREEN}✅ Rclone 配置文件已成功创建/更新！${NC}"
    fi
    echo -e "\n${GREEN}按任意键返回主菜单 ...${NC}"; read -n 1 -s
}


# --- 新增函数: 关联媒体库 (v7.2.0 核心) ---
link_media_to_service() {
    local service_type="$1"
    local local_path=""
    local remote_path_prompt=""
    local default_remote_path=""
    local rclone_service_name=""
    local docker_container_name=""

    if [ ! -f "${RCLONE_CONFIG_FILE}" ]; then
        echo -e "${RED}错误: 未找到 Rclone 配置文件!${NC}"
        echo -e "${YELLOW}请先在主菜单选择“配置 Rclone 云盘连接”(18)完成设置。${NC}"; sleep 4; return
    fi
    
    # 根据服务类型设置不同的参数
    case "$service_type" in
        navidrome)
            local_path="/mnt/Music"
            remote_path_prompt="请输入您在云盘上的【音乐】文件夹路径 (例如 'Music' 或 'MyData/Music')"
            default_remote_path="Music"
            rclone_service_name="rclone-music"
            docker_container_name="navidrome_app"
            ;;
        jellyfin_music)
            local_path="/mnt/Music"
            remote_path_prompt="请输入您在云盘上的【音乐】文件夹路径"
            default_remote_path="Music"
            rclone_service_name="rclone-music"
            docker_container_name="jellyfin_app"
            ;;
        jellyfin_movies)
            local_path="/mnt/Movies"
            remote_path_prompt="请输入您在云盘上的【电影】文件夹路径"
            default_remote_path="Movies"
            rclone_service_name="rclone-movies"
            docker_container_name="jellyfin_app"
            ;;
        jellyfin_tv)
            local_path="/mnt/TVShows"
            remote_path_prompt="请输入您在云盘上的【剧集】文件夹路径"
            default_remote_path="TVShows"
            rclone_service_name="rclone-tvshows"
            docker_container_name="jellyfin_app"
            ;;
        qbittorrent)
            local_path="/mnt/Downloads"
            remote_path_prompt="请输入您在云盘上的【下载】文件夹路径"
            default_remote_path="Downloads"
            rclone_service_name="rclone-downloads"
            docker_container_name="qbittorrent_app"
            ;;
        *)
            echo -e "${RED}内部错误: 未知的服务类型。${NC}"; sleep 2; return
            ;;
    esac

    clear
    echo -e "${BLUE}--- 正在为 ${docker_container_name} 关联媒体库 ---${NC}"
    echo -e "${YELLOW}${remote_path_prompt}${NC}"
    read -p "留空将使用默认值 [${default_remote_path}]: " onedrive_path
    onedrive_path=${onedrive_path:-$default_remote_path}

    echo -e "\n${CYAN}即将把云盘的 onedrive:${onedrive_path} 挂载到本地的 ${local_path} ...${NC}"
    sleep 3

    sudo mkdir -p "${local_path}"
    
    # 创建 systemd 服务文件
    sudo tee "/etc/systemd/system/${rclone_service_name}.service" > /dev/null <<EOF
[Unit]
Description=Rclone Mount for ${onedrive_path} to ${local_path}
Wants=network-online.target
After=network-online.target
[Service]
Type=simple
User=root
Group=root
RestartSec=10
Restart=on-failure
ExecStart=/usr/bin/rclone mount onedrive:${onedrive_path} ${local_path} \\
--config ${RCLONE_CONFIG_FILE} \\
--uid 1000 \\
--gid 1000 \\
--allow-other \\
--allow-non-empty \\
--vfs-cache-mode writes \\
--vfs-cache-max-size 5G \\
--log-level INFO \\
--log-file ${RCLONE_LOG_FILE}
ExecStop=/bin/fusermount -u ${local_path}
[Install]
WantedBy=default.target
EOF

    sudo systemctl daemon-reload
    sudo systemctl enable --now "${rclone_service_name}.service"
    sleep 2

    if systemctl is-active --quiet "${rclone_service_name}.service"; then
        echo -e "${GREEN}✅ 同步通道 ${onedrive_path} -> ${local_path} 已成功激活！${NC}"
        echo -e "${YELLOW}🚀 正在重启 ${docker_container_name} 以应用新的媒体库...${NC}"
        sudo docker restart "${docker_container_name}"
        echo -e "${GREEN}✅ 重启完成！现在您的应用应该能看到云盘文件了。${NC}"
    else
        echo -e "${RED}❌ 同步通道启动失败！请检查日志。${NC}"
        echo -e "${YELLOW}显示最近的 10 行日志 (${RCLONE_LOG_FILE}):${NC}"
        sudo tail -n 10 ${RCLONE_LOG_FILE}
    fi
    echo -e "\n${GREEN}按任意键返回 ...${NC}"; read -n 1 -s
}

# 23.     服务控制中心 (v7.2.0 重构)
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
            
            # --- 服务特定操作 ---
            while true; do
                clear; echo -e "正在操作服务: ${CYAN}${s_name}${NC}"
                echo "1) 启动"; echo "2) 停止"; echo "3) 重启"; echo "4) 查看日志 (Ctrl+C 退出)"
                # 为特定服务显示关联选项
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
                    5) 
                        if $has_media_option; then
                            if [[ "$s_name" == "Navidrome" ]]; then
                                link_media_to_service "navidrome"
                            elif [[ "$s_name" == "qBittorrent" ]]; then
                                link_media_to_service "qbittorrent"
                            elif [[ "$s_name" == "Jellyfin" ]]; then
                                # Jellyfin 可能有多个库，提供子菜单
                                clear; echo -e "为 Jellyfin 关联哪个媒体库?"
                                echo "1) 音乐库 (/mnt/Music)"; echo "2) 电影库 (/mnt/Movies)"; echo "3) 剧集库 (/mnt/TVShows)"; echo "b) 返回"
                                read -p "请选择: " jellyfin_choice
                                case $jellyfin_choice in
                                    1) link_media_to_service "jellyfin_music";;
                                    2) link_media_to_service "jellyfin_movies";;
                                    3) link_media_to_service "jellyfin_tv";;
                                    *) continue;;
                                esac
                            fi
                        else
                            echo -e "${RED}无效操作!${NC}"; sleep 2;
                        fi
                        ;;
                    b) break;;
                    *) echo -e "${RED}无效操作!${NC}"; sleep 2;;
                esac
            done
        else
            echo -e "${RED}无效选择!${NC}"; sleep 2
        fi
    done
}


# ---     主循环     ---
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
        18) configure_rclone_remote ;; # 改为调用新函数
        21) install_ai_model ;; 22) run_nextcloud_optimization ;;
        23) show_service_control_panel ;; 24) show_credentials ;;
        25) install_science_tools ;; 99) uninstall_everything ;;
        q|Q) echo -e "${BLUE}装修愉快，房主再见！${NC}"; exit 0 ;;
        *) echo -e "${RED}无效的选项，请重新输入。${NC}"; sleep 2 ;;
    esac
done
