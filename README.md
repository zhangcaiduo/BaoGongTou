# VPS 包工头面板 - 一键装修你的VPS

[![作者](https://img.shields.io/badge/作者-zhangcaiduo-blue.svg)](https://github.com/zhangcaiduo)
[![版本](https://img.shields.io/badge/版本-v6.5.1-brightgreen.svg)](https://github.com/zhangcaiduo/vps-installer-script)
[![适用系统](https://img.shields.io/badge/系统-Ubuntu%20%7C%20Debian-orange.svg)]()

---

### 👋 来自包工头的话

大家好，我是張財多，一个程序小白。

当我第一次接触VPS时，面对着黑漆漆的命令行窗口，感觉就像拿到了一间空空如也的毛坯房，不知从何下手。我踩过很多坑，也走了很多弯路，深深体会到新手的无助与迷茫。

所以，我萌生了一个想法：为什么不能有一个像“装修队”一样的工具，能带领我们这些小白，快速、轻松地把VPS打造成自己想要的样子呢？

这个脚本就是我这个“包工头”，带着大家一起，把咱们的“毛坯房”VPS，装修成一个温馨、强大、功能齐全的家。希望它能帮助你节省时间，点燃你对技术的兴趣，让你也能享受到“拥有”一台全功能服务器的乐趣！

*（我只是程序小白，像大多数朋友一样最初什么是SSH工具都不知道，希望我的踩坑能帮助到小白朋友们，大神们请指点，勿喷！感谢！）*

---

## 🚀 一键开工！

用SSH登录到你的VPS后，只需复制并执行下面这一行命令，即可召唤“包工头面板”：

```bash
wget -O vps_installer.sh 'https://raw.githubusercontent.com/zhangcaiduo/BaoGongTou/refs/heads/main/vps_installer.sh' && sudo bash vps_installer.sh
```

**友情提示**:
1.  首次运行后，脚本会自动创建一个快捷方式。您可以退出SSH重新登录，之后只需输入 `zhangcaiduo` 即可再次打开本面板。
2.  本脚本主要在 **Ubuntu (22.04 LTS)** 和 **Debian (11/12)** 系统上测试通过。

---

## 🛠️ 装修清单 (功能列表)

### 🧱 地基与系统
- [x] **更新系统与软件**: `apt update && upgrade`
- [x] **恢复至标准系统**: (unminimize) 为Ubuntu最小化系统补充组件，解决兼容性问题。

### 🏠 主体精装修
- [x] **网络水电总管 (Nginx Proxy Manager)**: 帮你管理所有网站域名和SSL证书，装修必备！
- [x] **Nextcloud 家庭数据中心**: 搭建属于你自己的私有云盘和在线Office。
- [x] **WordPress 个人博客**: 轻松拥有一个可以记录生活、分享技术的个人网站。
- [x] **Jellyfin 家庭影院**: 管理你的电影、剧集和音乐，打造私人影音库。
- [x] **AI 大脑 (Ollama+WebUI)**: 在自己的VPS上运行和体验各种大语言模型。
- [x] **家装工具箱**: 一次性部署Alist、Gitea、Memos、Navidrome等超实用工具。
- [x] **下载工具集**: 可选安装 qBittorrent, JDownloader, yt-dlp，满足各种下载需求。

### 🛡️ 安防与工具
- [x] **全屋安防系统 (Fail2ban)**: 自动屏蔽恶意IP，保护你的SSH和网站安全。
- [x] **远程工作台 (Xfce + XRDP)**: 为你的VPS安装一个图形化桌面，用远程桌面就能连接。
- [x] **邮件管家 (自动报告)**: 每天定时给你发邮件，报告服务器状态。
- [x] **Rclone 数据同步桥**: 将你的OneDrive等网盘挂载到VPS上，实现文件无缝同步。

### ✨ 高级维护
- [x] **服务控制中心**: 集中管理所有已安装的应用，轻松启停、重启、看日志。
- [x] **凭证保险箱**: 集中查看所有自动生成的密码和重要路径，再也不怕忘记密码。
- [x] **一键还原毛坯**: 如果玩腻了或者想重来，可以一键卸载所有服务，把房子恢复原样。

---

## 🤝 交流与贡献

如果你在使用中遇到任何问题，或有任何好的建议，欢迎来我的GitHub项目主页提 `Issue`。

**[点我前往项目主页提问或交流](https://github.com/zhangcaiduo/vps-installer-script/issues)**

**我的博客是：[zhangcaiduo.com](https://zhangcaiduo.com/)**

**感谢每一位使用和支持本脚本的朋友！**
