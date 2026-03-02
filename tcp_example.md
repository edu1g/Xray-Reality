### ⚠️ 免责与风险声明 (Disclaimer & Risk Warning)

1. **环境差异**：以下参数基于特定硬件与网络环境草拟。不同服务器的硬件配置、网络架构及业务负载各不相同。**吾之蜜糖，汝之砒霜**，切勿盲目照搬。
2. **潜在风险**：修改系统内核网络参数（sysctl）属于高风险操作。（尤其是内存限制相关的 `rmem` 和 `wmem`）可能导致服务器内存溢出（OOM）、网络连接中断或系统内核崩溃。
3. **责任自负**：本示例仅供学习和参考。作者不对使用上述配置所产生的任何直接或间接后果（包括但不限于服务器宕机、服务中断、数据丢失）承担任何责任。
4. **强烈建议**：在生产环境应用任何更改之前，请务必：
   - 充分理解每一行参数的实际含义。
   - 备份当前的系统配置。
   - 先在测试环境中进行压力测试和全面验证。
```bash
【重要】：请在填写前仔细阅读以下说明，参数质量直接影响服务器稳定性   

 ① 物理内存 (RAM)                                          [高风险]
    决定 TCP 全局内存池上限 (tcp_mem)。
    填写过大 → TCP 内存池挤占系统内存 → 触发 OOM，进程被强杀。
    填写过小 → 缓冲区受限，高并发时丢包、吞吐下降。
    建议填写:  (MB，当前实际内存)

 ② CPU 核心数                                              [低风险]
    决定连接队列大小 (somaxconn / syn_backlog)。
    填写过大 → 队列占用内核内存略增，影响不大。
    填写过小 → 高并发时连接排队，新请求被丢弃。
    建议填写:  (当前逻辑核心数)

 ③ 最大带宽 (Mbps)                                         [中风险]
    与延迟共同计算 BDP，决定读写缓冲区大小 (rmem/wmem)。
    填写过大 → 单连接缓冲区过大，内存被少数连接独占。
    填写过小 → 带宽跑不满，高延迟链路吞吐严重受限。
    建议填写: 购买套餐的标称带宽上限。

 ④ 网络延迟 (ms)                                           [中风险]
    与带宽共同计算 BDP，延迟越高所需缓冲区越大。
    填写过大 → 缓冲区虚高，内存浪费，OOM 风险上升。
    填写过小 → 缓冲区不足，高延迟链路频繁等待，吞吐骤降。
    建议填写: ping 目标用户群的实测平均延迟。

 ⑤ 缓冲区冗余系数                                          [中风险]
    BDP 的放大倍数，应对网络抖动和突发流量。
    填写过大 → 缓冲区膨胀，与带宽和网络延迟参数叠加后 OOM 风险显著升高。
    填写过小 → 抗抖动能力弱，丢包率上升。
    建议填写: 稳定内网填 2，跨国恶劣线路填 3，极端情况不超过 4。
```

### 示例（仅供参考）：

```bash
cat > /etc/sysctl.d/99-custom-network.conf <<EOF

# 启用 BBR 拥塞控制算法与 FQ 队列调度
net.core.default_qdisc = fq                # 默认队列调度算法，fq（公平队列）配合 BBR 使用
net.ipv4.tcp_congestion_control = bbr      # TCP 拥塞控制算法，BBR 基于带宽和延迟，比 cubic 更高效

# 提升系统文件描述符与端口范围，适应高并发
fs.file-max = 1000000                      # 系统级最大文件描述符数量，影响并发连接上限
net.ipv4.ip_local_port_range = 1024 65535  # 本地端口范围，扩大可用端口数以支持更多出站连接

# 基础 TCP 特性优化：MTU 探测、Fast Open 与窗口缩放 (高带宽延迟环境必备)
net.ipv4.tcp_mtu_probing = 1               # 启用 MTU 探测，避免 PMTUD 黑洞问题
net.ipv4.tcp_fastopen = 3                  # 启用 TCP Fast Open（客户端+服务端），减少握手延迟
net.ipv4.tcp_window_scaling = 1            # 启用窗口缩放，允许 TCP 窗口超过 64KB，提升高带宽利用率

# TIME_WAIT 状态回收与超时优化，防止端口耗尽
net.ipv4.tcp_tw_reuse = 1                  # 允许将 TIME_WAIT 状态的连接复用于新连接（仅出站）
net.ipv4.tcp_fin_timeout = 15              # FIN_WAIT_2 超时时间（秒），缩短可加快释放连接资源
net.ipv4.tcp_max_tw_buckets = 32768        # TIME_WAIT 连接最大数量，超出后直接关闭连接

# TCP Keepalive (保活) 优化：提前并加速检测死连接
net.ipv4.tcp_keepalive_time = 600          # 连接空闲多少秒后开始发送 keepalive 探测包
net.ipv4.tcp_keepalive_intvl = 30          # 每次 keepalive 探测包的发送间隔（秒）
net.ipv4.tcp_keepalive_probes = 3          # 连续几次探测无响应后判定连接断开

# 单连接缓冲区优化：基于带宽、延迟与冗余系数计算得出的 BDP 上限
net.core.rmem_max = 36700160               # Socket 接收缓冲区最大值（字节），约 35MB
net.core.wmem_max = 36700160               # Socket 发送缓冲区最大值（字节），约 35MB
net.ipv4.tcp_rmem = 4096 131072 36700160   # TCP 接收缓冲区：最小值 / 默认值 / 最大值（字节）
net.ipv4.tcp_wmem = 4096 131072 36700160   # TCP 发送缓冲区：最小值 / 默认值 / 最大值（字节）

# 全局 TCP 内存限制：保护系统内存的最后防线 (单位为 Page/4KB)
net.ipv4.tcp_mem = 18393 27590 36787       # TCP 内存使用阈值（页）：正常 / 进入压力 / 最大上限

# 连接队列优化：应对中等规模突发连接请求（多用户时应适度增加）
net.core.somaxconn = 2048                  # listen() 调用的全连接队列（accept queue）最大长度
net.ipv4.tcp_max_syn_backlog = 2048        # 半连接队列（SYN 队列）最大长度，防范 SYN Flood
net.core.netdev_max_backlog = 2048         # 网卡收包后内核处理队列的最大长度，避免高负载丢包
EOF

# 立即应用配置
sysctl -p /etc/sysctl.d/99-custom-network.conf

```
