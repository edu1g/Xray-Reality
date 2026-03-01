### ⚠️ 免责与风险声明 (Disclaimer & Risk Warning)

1. **环境差异**：以下参数基于特定硬件与网络环境（1核 CPU，1GB 内存，1Gbps 带宽，140ms 延迟，冗余系数 3）草拟。不同服务器的硬件配置、网络架构及业务负载各不相同。**吾之蜜糖，汝之砒霜**，切勿盲目照搬。
2. **潜在风险**：修改系统内核网络参数（sysctl）属于高风险操作。本配置为了满足高 BDP（带宽延迟乘积）极大地提升了单连接缓冲区大小（约 52.5MB），在 1GB 内存的机器上并发连接数稍高
（尤其是内存限制相关的 `rmem` 和 `wmem`）可能导致服务器内存溢出（OOM）、网络连接中断或系统内核崩溃。
3. **责任自负**：本示例仅供学习和参考。作者不对使用上述配置所产生的任何直接或间接后果（包括但不限于服务器宕机、服务中断、数据丢失）承担任何责任。
4. **强烈建议**：在生产环境应用任何更改之前，请务必：
   - 充分理解每一行参数的实际含义。
   - 备份当前的系统配置。
   - 先在测试环境中进行压力测试和全面验证。

### 示例（仅供参考）：

```bash
cat > /etc/sysctl.d/99-custom-network.conf <<EOF
# 启用 BBR 拥塞控制算法与 FQ 队列调度
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr

# 提升系统文件描述符与端口范围，适应高并发
fs.file-max = 1000000
net.ipv4.ip_local_port_range = 1024 65535

# 基础 TCP 特性优化：MTU 探测、Fast Open 与窗口缩放 (高带宽延迟环境必备)
net.ipv4.tcp_mtu_probing = 1
net.ipv4.tcp_fastopen = 3
net.ipv4.tcp_window_scaling = 1

# TIME_WAIT 状态回收与超时优化，防止端口耗尽
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_fin_timeout = 15
net.ipv4.tcp_max_tw_buckets = 10240

# TCP Keepalive (保活) 优化：提前并加速检测死连接
net.ipv4.tcp_keepalive_time = 600
net.ipv4.tcp_keepalive_intvl = 30
net.ipv4.tcp_keepalive_probes = 3

# 单连接缓冲区优化：基于 1Gbps 带宽、140ms 延迟与系数 3 计算得出的 BDP 上限 (约 52.5MB)
net.core.rmem_max = 55050240
net.core.wmem_max = 55050240
net.ipv4.tcp_rmem = 4096 131072 55050240
net.ipv4.tcp_wmem = 4096 131072 55050240

# 全局 TCP 内存限制：保护 1GB 系统内存的最后防线 (单位为 Page/4KB，上限约 204MB)
net.ipv4.tcp_mem = 26214 39321 52428

# 连接队列优化：应对中等规模突发连接请求（多用户时应适度增加）
net.core.somaxconn = 2048
net.ipv4.tcp_max_syn_backlog = 2048
net.core.netdev_max_backlog = 2048
EOF

# 立即应用配置
sysctl -p /etc/sysctl.d/99-custom-network.conf

```
