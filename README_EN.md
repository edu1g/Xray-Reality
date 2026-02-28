<div align="center">

[🇨🇳 中文](README.md) | [🇺🇸 English](README_EN.md)

</div>

# 🚀 Xray-Reality Installer

**Fully Automated, Modular Xray Deployment Script**

[![Powered by Xray](https://img.shields.io/badge/Powered%20by-Xray--core-blue.svg?style=flat-square)](https://github.com/XTLS/Xray-core) [![404 Not Found](https://img.shields.io/badge/Censorship-404%20Not%20Found-red.svg?style=flat-square)](https://github.com/uxswl/Xray-Reality) [![网络不是法外之地](https://img.shields.io/badge/警告-网络不是法外之地-ea4335?style=flat-square)](https://github.com/uxswl/Xray-Reality) [![Sponsor](https://img.shields.io/badge/Sponsor-%E2%9D%A4-ff69b4?style=flat-square)](https://github.com/uxswl/Xray-Reality#sponsor)

[![GitHub release](https://img.shields.io/github/v/release/uxswl/Xray-Reality?style=flat-square)](https://github.com/uxswl/Xray-Reality/releases/latest) [![Downloads](https://img.shields.io/github/downloads/uxswl/Xray-Reality/total?style=flat-square)](https://github.com/uxswl/Xray-Reality/releases) [![Last Commit](https://img.shields.io/github/last-commit/uxswl/Xray-Reality?style=flat-square)](https://github.com/uxswl/Xray-Reality/commits/main) [![GitHub stars](https://img.shields.io/github/stars/uxswl/Xray-Reality?style=flat-square)](https://github.com/uxswl/Xray-Reality/stargazers) 

[![OS](https://img.shields.io/badge/OS-Debian%20%7C%20Ubuntu-blue?style=flat-square&logo=linux&logoColor=white)](https://github.com/uxswl/Xray-Reality) [![Shell](https://img.shields.io/badge/Language-Shell-89E051?style=flat-square&logo=gnu-bash&logoColor=white)](https://github.com/uxswl/Xray-Reality/search?l=Shell) [![License](https://img.shields.io/github/license/uxswl/Xray-Reality?style=flat-square)](https://github.com/uxswl/Xray-Reality/blob/main/LICENSE)

This project is a highly modular Shell script designed for the rapid deployment of proxy services based on the **Xray** core on Linux servers. It supports the latest **Vision** and **XHTTP** protocols and integrates SNI masking technology powered by Reality.


---

## ✨ Features

* **📦 Modular Design**: The code is logically organized into three main modules: Core, Lib, and Tools.
* **🔒 Latest Protocols**: Supports Vision and XHTTP protocols with integrated Reality masking.
* **🛡️ Security Hardening**: Automatically configures Fail2ban and the Firewall.
* **🛠️ Rich Toolbox**: Built-in tools for WARP, BBR, port management, SNI optimization, and more.


## 📋 Requirements

* **OS**: Debian 10+, Ubuntu 20.04+ (Debian 11/12 recommended)
* **Architecture**: amd64, arm64
* **Permissions**: `root` access required
* **Ports**: Uses high random ports by default (for Vision and XHTTP).
* **Client**: Ensure your client supports these protocols (e.g., Shadowrocket, v2rayN, etc.)


## 📥 Quick Start

### 🚀 Recommended: One-Click Installation (Bootstrap)

Run the following command as the `root` user. The bootstrap script will automatically install Git, clone the repository, and start the installer.

```bash
bash <(curl -sL https://raw.githubusercontent.com/uxswl/Xray-Reality/main/bootstrap.sh)

```

### 🛠️ Alternative: Manual Installation
If you cannot connect to GitHub Raw, you can try cloning manually:

```bash
# 1. Install Git
apt update && apt install -y git

# 2. Clone the repository
git clone https://github.com/uxswl/Xray-Reality.git xray-install

# 3. Run the script
cd xray-install
chmod +x install.sh
./install.sh

```


## 🗑️ Uninstall

If you want to completely remove Xray and its related configurations, run the following (or type remove in the server terminal):

```bash
bash <(curl -sL https://raw.githubusercontent.com/uxswl/Xray-Reality/main/tools/remove.sh)

```

## 🎮 Usage Guide

After installation, the management tools are registered to the system path. You can enter the following commands directly in the terminal:

| Command | Function | Description |
| :--- | :--- | :--- |
| `info` | **Admin Dashboard** | View node links, QR codes, service status, and the shortcut menu. |
| `user` | **User Management** | Query, add, or delete users. |
| `ports` | **Port Management** | Modify SSH, Vision, or XHTTP ports and automatically update firewall rules. |
| `net` | **Network Policy** | Switch IPv4/IPv6 priority or force single-stack mode. |
| `xw` | **WARP Manager** | Install Cloudflare WARP for Netflix/ChatGPT routing. |
| `bbr` | **Kernel Optimization** | Enable/Disable BBR acceleration, adjust queue algorithms (FQ/FQ_CODEL). |
| `sni` | **SNI Management** | Automatically test and select optimal SNI domains, or specify manually. |
| `bt` | **Audit Management** | One-click toggle for blocking BitTorrent downloads and private IP access. |
| `swap` | **Memory Management** | Add/Remove Swap partitions and adjust Swappiness. |
| `f2b` | **Fail2ban** | View banned IPs, unban IPs, and adjust banning policies. |
| `backup` | **Backup & Restore** | Query, backup, and restore configurations. |
| `sniff` | **Traffic Sniffing** | Enable/Disable traffic sniffing and logging. |
| `zone` | **Timezone Manager** | Configure timezone and system time. |
| `update` | **Updata** | Updata Xray core and Geodata。 |
| `remove` | **Uninstall** | Remove Xray and all installed components. |


### 📝 Client Configuration Reference

| Parameter | Value (Example) | Description |
| :--- | :--- | :--- |
| **Address** | `1.2.3.4` or `[2001::1]` | Server IP |
| **Port** | `443` | Port set during installation |
| **UUID** | `de305d54-...` | Type `info` to retrieve |
| **Flow** | `xtls-rprx-vision` | **Required for Vision nodes only** |
| **Network**| `tcp` or `xhttp` | Select TCP for Vision, xhttp for XHTTP |
| **SNI** | `www.microsoft.com` | Type `info` to retrieve |
| **Fingerprint**| `chrome` | Recommended fingerprint |
| **Public Key** | `B9s...` | Type `info` to retrieve |
| **ShortId** | `a1b2...` | Type `info` to retrieve |
| **Path** | `/8d39f310` | **Required for XHTTP nodes only** |


## 📂 Project Structure

This project uses a modular architecture with the following directory structure:

```text
.
├── bootstrap.sh       # One-click bootstrap script (Download, verify, start)
├── install.sh         # Main installation entry (Orchestration, lock mechanism)
├── lib/
│   └── utils.sh       # Common function library (UI, Logs, Colors, Task executor)
├── core/              # Core installation process
│   ├── 1_env.sh       # Environment check and initialization
│   ├── 2_install.sh   # Dependency and Xray core installation
│   ├── 3_system.sh    # System configuration (Firewall, Kernel)
│   └── 4_config.sh    # Configuration generation and service startup
└── tools/             # Standalone tools (Deployed to /usr/local/bin after install)
    ├── info.sh
    ├── ports.sh
    ├── net.sh
    ├── ...
```


## 🔄 How to Keep Your Fork Updated

If you have forked this repository, you can keep it synced with the upstream repository using one of the following two methods:

### Method 1: Manual Sync (Recommended to preserve your own changes)
1. Go to your forked repository's homepage on GitHub.
2. Find and click the **"Sync fork"** button located under the green "Code" button.
3. Click **"Update branch"** to pull the latest changes from the upstream repository.

### Method 2: Auto Sync (Via GitHub Actions - WARNING: Overwrites local changes)
This repository includes a built-in GitHub Actions workflow that automatically forces synchronization every day. **⚠️ PLEASE NOTE: Enabling this feature will force-overwrite any independent modifications you have made on the default branch with upstream updates. If you plan to do your own development, please create a new branch.**
1. Go to the **"Actions"** tab of your forked repository.
2. Click **"I understand my workflows, go ahead and enable them"** to activate GitHub Actions.
3. Once enabled, the `Auto Sync Upstream` workflow will run automatically on schedule (you can also find it in the left sidebar to trigger it manually).


## 💖 Sponsor & Support

This project is completely free and open-source. If you find this script helpful, if it saves you time, and you'd like to support ongoing development and server maintenance, consider using my aff! Your support is my greatest motivation.

### 🌐 VPS Purchasing Recommendations

To ensure the best proxy experience, please consider the following points when selecting a VPS:

* **Routing Quality**:
    * **China Telecom Users**: Priority should be given to **CN2 GIA** lines.
    * **China Unicom Users**: Priority should be given to **AS9929** or **AS4837** lines.
    * **China Mobile Users**: Priority should be given to **CMIN2** lines.
* **IP Purity**: Choose **Native IPs** or data centers with low abuse rates. While Reality protocols mask traffic, blacklisted IPs will still fail to unlock streaming services like Netflix or Disney+.
* **Virtualization Architecture**: **KVM** is strongly recommended. OpenVZ (OVZ) does not support BBR acceleration, which severely limits speeds during peak hours.

### 📝 DMIT Purchasing Guide

Founded in 2017, DMIT is known for high-stability, high-bandwidth VPS solutions with deep optimization for Asian routing.

| Network Type | Routing | Best Use Case |
| :--- | :--- | :--- |
| **Premium (Pro)** | IPv4: CN2 GIA (3-ISP) / IPv6: 9929 + CMIN2 | All scenarios (Best for Proxy) |
| **Eyeball (Eb)** | AS9929 + CMIN2 | All scenarios (Best for Proxy) |
| **Tier1 (T1)** | International Routing (No China Optimization) | International access / Web hosting|

#### I. DMIT EyeBall (Eb) Packages

| Name | CPU | RAM | Disk | Traffic | Speed | Price | Buy | Remark |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| LAX.AN4.EB.Intro | 1vCPU | 1GB | 10GB SSD | 500GB/mo | 1Gbps | 29.9$/yr | [Buy](https://www.dmit.io/aff.php?aff=13908&pid=231) | US West |
| LAX.AN4.EB.WEE | 1vCPU | 1GB | 20GB SSD | 1000GB/mo | 1Gbps | 39.9$/yr | [Buy](https://www.dmit.io/aff.php?aff=13908&pid=188) | US West |
| LAX.AN4.EB.CORONA | 1vCPU | 1GB | 20GB SSD | 2000GB/mo | 2Gbps | 49.9$/yr | [Buy](https://www.dmit.io/aff.php?aff=13908&pid=218) | US West |
| LAX.AN4.EB.FONTANA | 2vCPU | 2GB | 40GB SSD | 4000GB/mo | 4Gbps | 100$/yr | [Buy](https://www.dmit.io/aff.php?aff=13908&pid=219) | US West |
| HKG.AN4.EB.WEEv2 | 1vCPU | 1GB | 20GB SSD | 450GB/mo | 500Mbps | 179.9$/yr | [Buy](https://www.dmit.io/aff.php?aff=13908&pid=209) | Hong Kong |
| TYO.AN4.EB.WEE | 1vCPU | 1GB | 20GB SSD | 450GB/mo | 500Mbps | 154.9$/yr | [Buy](https://www.dmit.io/aff.php?aff=13908&pid=220) | Tokyo |
| LAX.AN5.EB.TINY | 1vCPU | 2GB | 20GB SSD | 1500GB/mo | 2Gbps | 88.88$/yr | [Buy](https://www.dmit.io/aff.php?aff=13908&pid=189) | US West |


#### II. DMIT Premium (Pro) Packages

| Name | CPU | RAM | Disk | Traffic | Speed | Price | Buy | Remark |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| LAX.AN4.Pro.Wee | 1vCPU | 1GB | 10GB SSD | 500GB/mo | 500Mbps | 39.9$/yr | [Buy](https://www.dmit.io/aff.php?aff=13908&pid=183) | US West |
| LAX.AN4.Pro.MALIBU | 1vCPU | 1GB | 20GB SSD | 1000GB/mo | 1Gbps | 49.9$/yr | [Buy](https://www.dmit.io/aff.php?aff=13908&pid=186) | US West |
| LAX.AN4.PRO.PalmSpring  | 2vCPU | 2GB | 40GB SSD | 2000GB/mo | 2Gbps | 100$/yr | [Buy](https://www.dmit.io/aff.php?aff=13908&pid=182) | US West |
| HKG.AN4.PRO.Victoria | 1vCPU | 2GB | 60GB SSD | 500GB/mo | 500Mbps | 298.88$/yr | [Buy](https://www.dmit.io/aff.php?aff=13908&a=add&pid=178) | Hong Kong |
| TYO.AN4.PRO.Shinagawa | 1vCPU | 2GB | 60GB SSD | 500GB/mo | 500Mbps | 199$/yr | [Buy](https://www.dmit.io/aff.php?aff=13908&pid=179) | Tokyo |
| LAX.AN5.Pro.TINY | 1vCPU | 2GB | 20GB SSD | 1500GB/mo | 2Gbps | 88.88$/yr | [Buy](https://www.dmit.io/aff.php?aff=13908&a=add&pid=100) | US West |
| LAX.AN5.Pro.Pocket | 2vCPU | 2GB | 40GB SSD | 1500GB/mo | 4Gbps | 14.90$/mo | [Buy](https://www.dmit.io/aff.php?aff=13908&a=add&pid=137) | US West |
| LAX.AN5.Pro.STARTER | 2vCPU | 2GB | 80GB SSD | 3000GB/mo | 10Gbps | 29.90$/mo | [Buy](https://www.dmit.io/aff.php?aff=13908&a=add&pid=56) | US West |
| LAX.AN5.Pro.MINI | 4vCPU | 4GB | 80GB SSD | 5000GB/mo | 10Gbps | 58.88$/mo | [Buy](https://www.dmit.io/aff.php?aff=13908&a=add&pid=58) | US West |
| HKG.AS3.Pro.TINY | 1vCPU | 1GB | 20GB SSD | 500GB/mo | 1Gbps | 39.90$/mo | [Buy](https://www.dmit.io/aff.php?aff=13908&a=add&pid=123) | Hong Kong |
| HKG.AS3.Pro.STARTER | 1vCPU | 2GB | 40GB SSD | 1000GB/mo | 1Gbps | 79.90$/mo | [Buy](https://www.dmit.io/aff.php?aff=13908&a=add&pid=124) | Hong Kong |
| HKG.AS3.Pro.MINI | 2vCPU | 2GB | 60GB SSD | 1500GB/mo | 1Gbps | 119.90$/mo | [Buy](https://www.dmit.io/aff.php?aff=13908&a=add&pid=125) | Hong Kong |
| HKG.AS3.Pro.MICRO | 4vCPU | 4GB | 80GB SSD | 2000GB/mo | 1Gbps | 159.90$/mo | [Buy](https://www.dmit.io/aff.php?aff=13908&a=add&pid=126) | Hong Kong |
| TYO.AS3.Pro.TINY | 1vCPU | 1GB | 20GB SSD | 500GB/mo | 1Gbps | 21.90$/mo | [Buy](https://www.dmit.io/aff.php?aff=13908&a=add&pid=138) | Tokyo |
| TYO.AS3.Pro.STARTER | 1vCPU | 2GB | 40GB SSD | 1000GB/mo | 1Gbps | 39.90$/mo | [Buy](https://www.dmit.io/aff.php?aff=13908&a=add&pid=139) | Tokyo |
| TYO.AS3.Pro.MINI | 2vCPU | 2GB | 60GB SSD | 2000GB/mo | 1Gbps | 79.90$/mo | [Buy](https://www.dmit.io/aff.php?aff=13908&a=add&pid=140) | Tokyo |
| TYO.AS3.Pro.MINI | 4vCPU | 4GB | 80GB SSD | 4000GB/mo | 1Gbps | 159.90$/mo | [Buy](https://www.dmit.io/aff.php?aff=13908&a=add&pid=141) | Tokyo |


## ⚖️ Legal Disclaimer
**The internet is not a lawless place.**
1. **Educational & Research Purposes Only:** This project (Xray-Reality scripts and configurations) is intended solely for network technology research, academic exchange, and system testing. Do not use this script for any purposes that violate national laws and regulations.
2. **Legal Compliance:** When using this script, you must strictly comply with the laws and regulations of your country/region and the jurisdiction where your server is located. It is strictly forbidden to use this project to distribute illegal content, including but not limited to politics, religion, pornography, or fraud. The user bears full responsibility for any legal consequences and joint liabilities arising from illegal use or abuse. The author of this project assumes no responsibility whatsoever.
3. **No Warranty (AS IS):** This software is provided "AS IS", without warranty of any kind, express or implied. The author is not liable for any direct or indirect damages caused by the use of this script (including but not limited to data loss, system crashes, IP blocking, or server suspension/termination by hosting providers).
4. **Third-Party Components:** This script integrates third-party open-source programs (such as `Xray-core`). Their copyrights and liabilities belong to their respective original authors. The author of this script makes no guarantees regarding the security, compliance, or stability of these third-party programs.
5. **License:** This project is licensed under the GNU General Public License v3.0 (GPL-3.0). Please refer to the `LICENSE` file in the repository for detailed terms. By downloading, installing, or using this project, you acknowledge that you have read and fully agreed to all terms of this disclaimer and the open-source license.


*Copyright © uxswl. Dedicated to the purest network routing experience.*
