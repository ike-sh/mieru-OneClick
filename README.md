# mieru-OneClick

基于 [enfein/mieru](https://github.com/enfein/mieru) 的 **mita 服务端**一键安装脚本，支持：

- **Debian / Ubuntu**（deb）
- **CentOS / RHEL / Rocky**（rpm）
- **Alpine Linux**（官方 tar.gz + OpenRC/systemd）

## 一键安装

**Debian / Ubuntu / CentOS / RHEL 等**（需 sudo）：

```sh
curl -fsSL https://raw.githubusercontent.com/ike-sh/mieru-OneClick/main/install-mita.sh | sudo bash
```

**Alpine Linux**（默认无 `sudo`，且需先安装 `bash`）：

```sh
apk add --no-cache bash curl && \
  curl -fsSL https://raw.githubusercontent.com/ike-sh/mieru-OneClick/main/install-mita.sh | bash
```

> Alpine 容器内通常已是 root，**不要**加 `sudo`；脚本本身会 `apk add` 其余依赖（tar、iptables 等）。

运行后按菜单选择「安装 / 配置」，脚本将：

1. 从 GitHub Releases 下载最新 `mita` 安装包
2. 自动生成随机用户名、密码；询问端口时默认随机端口（回车即用）
3. 应用配置并启动服务
4. 尝试放行防火墙（ufw / firewalld / Alpine iptables）
5. 安装完成**同时输出** `mierus://` 节点链接、客户端 JSON、**Clash/mihomo 片段**及连接信息摘要
6. 下载包 **SHA256 校验**；提示云安全组放行端口

### v1.2.16 增强

- 「查看节点链接」输出增加分区标题与说明：标注 `mierus://` 为分享链接、JSON 为客户端配置及导入方式

### v1.2.15 修复

- **`mita` 快捷命令**：`/usr/local/bin/mita` 改为管理入口（无参数打开菜单）；真实二进制迁至 `mita-real`，OpenRC/systemd 直连真实二进制
- 打开菜单时自动安装/更新 wrapper（升级提示「已是最新」时也会更新管理脚本）
- 修复「查看节点链接」失败：`describe config` 密码哈希时从 `install-state.env` 或 `/root/mieru_client_*.json` 回退读取凭据
- 安装状态文件保存用户名/密码（`chmod 600`）

### v1.2.14 增强

- 新增 **重新配置**（菜单 2 / `--reconfigure`）：部署后可改端口、密码、协议，无需重装
- 菜单 **6) 查看节点链接 / 客户端配置**：随时重新展示 `mierus://` 链接、JSON、Clash 片段
- **快捷命令不区分大小写**：`install-mita STATUS`、`mita-menu`、`mita reconfigure` 等均可用
- 登录 shell 安装 `mita()` 函数：`mita` 打开菜单，管理子命令不区分大小写；`mita start` 等仍走官方二进制

### v1.2.13 修复

- OpenRC `crashed` 状态自动 `zap` + 重启（修复 `rc-service mita start` 提示 already started 无法恢复）
- OpenRC 服务增加 `respawn` 自动拉起守护进程
- `--status` / 菜单「状态」按平台显示正确命令（Alpine 不再误导为 systemctl）
- 状态检查时自动尝试恢复守护进程并输出 `/var/log/mita.err` 日志

### v1.2.12 修复

- Alpine/OpenRC：`/etc/mita` 授权 `mita:mita`（守护进程需写入 `server.conf.pb`，否则启动即退出）
- OpenRC 服务增加 `start_pre` + `checkpath`，确保运行时目录存在
- 套接字等待失败时输出 `/var/log/mita.err` 日志尾部

### v1.2.11 修复

- 修复 Alpine/BusyBox `mktemp: Invalid argument`（`XXXXXX` 必须在模板末尾）
- 新增 `mktemp_file` / `mktemp_dir` 兼容 GNU 与 BusyBox

### v1.2.10 增强

- 文档与 `--help` 补充 **Alpine 一键命令**（`apk add bash curl` + `| bash`，无需 sudo）
- 非 bash / 非 root 时给出 Alpine 专用提示

### v1.2.9 修复

- 修复 deb 安装后 `mita.sock` 未就绪导致 `mita start` 失败、脚本中断（`set -e`）
- 新增 `wait_mita_socket` / `ensure_mita_daemon`：先启 systemd 守护进程，等待 RPC 套接字后再 `apply` / `start`
- `mita start` 改为重试 + 警告，不再因单次失败退出安装

### v1.2.8 增强

- 交互菜单顶部显示 **版本号 v1.2.8** 与 **作者 ike**
- 移除未使用的 `build_client_json` 聚合函数（孤立代码）
- 卸载时显式清理 `mieru_client_tcp_*.json` / `mieru_client_udp_*.json`

### v1.2.7 修复

- 交互安装增加 **编号菜单** 选择传输协议（1=TCP / 2=UDP / 3=双协议），置于端口询问之前
- 修复 v1.2.4 默认 TCP 时跳过协议询问的 BUG

### v1.2.6 增强

- **分协议输出**：双协议（BOTH）时分别输出 TCP / UDP 节点链接与 JSON（`mieru_client_tcp_*.json`、`mieru_client_udp_*.json`）
- 单协议（TCP 或 UDP）时仅输出对应链接与配置
- Clash 片段：双协议输出 tcp / udp 两条独立代理（不再聚合为单条）

### v1.2.5 修复

- 修复双协议（BOTH）被误判为 TCP，导致卸载时 UDP 防火墙规则未清理
- 修复交互安装时无法选择 UDP/双协议（默认 TCP 跳过协议询问）
- `--client-config` / 卸载防火墙：从 `mita describe config` 精确解析 portBindings
- 移除未使用的 `--menu` 参数

### v1.2.4 修复

- **默认改回 TCP**（官方推荐；多数场景 Clash `udp: true` 即够用）
- **双协议 BOTH**：TCP 用主端口，UDP 用 **主端口+1**（对齐官方示例，避免同端口双绑定）
- 修复 `mita start` 未显式调用导致 IDLE 的问题
- 客户端提示：v2rayN 等请选 **tcp**，勿选「两个都」

### v1.2.3 增强

- **默认双协议**：同端口同时监听 TCP + UDP（`--protocol BOTH`，可改为 `TCP` / `UDP`）
- **节点链接**：对齐官方 `mierus://` 格式（`port`/`protocol` 成对出现；单端口时地址含 `:port`）
- **Clash**：双协议时输出 TCP/UDP 两条代理配置
- 防火墙 / 云安全组提示同步覆盖 TCP 与 UDP

### v1.2.0 增强

- 安装包 SHA256 完整性校验
- 节点链接 URL 编码（支持特殊字符密码）
- Clash / mihomo YAML 片段输出
- deb/rpm 系统 iptables 回退放行
- ufw 端口段语法 `9000:9010/tcp`
- Alpine 启用 BBR 时自动安装 python3
- 本脚本安装标记，卸载前识别官方包

### Alpine 说明

Alpine 使用官方 `mita_*_linux_{amd64,arm64}.tar.gz`，自动安装 OpenRC 或 systemd 服务，并通过 iptables 放行端口。架构：amd64 / arm64。

常见报错与处理：

| 报错 | 原因 | 处理 |
|------|------|------|
| `sudo: not found` | Alpine 默认无 sudo | 去掉 `sudo`，直接 `\| bash`（root 环境） |
| `请使用 bash 运行` | 默认 shell 为 ash | 先 `apk add --no-cache bash curl` |
| `curl: (23) Failure writing` | 管道下游命令失败 | 同上，确保 `bash` 已安装 |
| `mktemp: Invalid argument` | BusyBox 要求 `XXXXXX` 在末尾 | v1.2.11+ 已修复，请拉最新 main |
| `status: crashed` | 守护进程异常退出，OpenRC 进入 crashed | `rc-service mita zap && rc-service mita start`，或 v1.2.13+ 菜单「状态」自动恢复 |
| `daemon is not running` + systemctl 提示 | mita 二进制默认提示 systemd | Alpine 用 `rc-service mita zap && rc-service mita start`；v1.2.13+ 脚本已适配 |

## 非交互安装

```sh
curl -fsSL https://raw.githubusercontent.com/ike-sh/mieru-OneClick/main/install-mita.sh | \
  sudo bash -s -- --install -y \
    --port 2088 \
    --protocol TCP \
    --user myuser \
    --password 'my-secret' \
    --enable-bbr
```

## 其它命令

| 命令 | 说明 |
|------|------|
| `--reconfigure` | 修改端口/密码/协议（不重装二进制） |
| `--upgrade` | 升级至最新版 |
| `--uninstall` | 卸载 mita、管理脚本、防火墙规则、客户端配置与日志 |
| `--status` | 查看服务与配置 |
| `--client-config` / `--show` | 查看节点链接并生成客户端 JSON |

快捷命令（子命令不区分大小写）：

```sh
install-mita                  # 打开菜单
install-mita reconfigure      # 重新配置
install-mita show             # 查看节点链接
mita-menu status              # 同上
mita status                   # 登录 shell 下（需已安装 profile.d）
```

卸载后再次管理请重新执行一键安装，或运行 `install-mita --help`（安装后位于 `/usr/local/bin/install-mita`）。

## 与官方脚本的关系

上游官方提供 Python 安装器：

```sh
curl -fSsLO https://raw.githubusercontent.com/enfein/mieru/refs/heads/main/tools/setup.py
sudo python3 setup.py
```

本仓库的 Bash 脚本在官方能力之上补充了：

- 纯 Bash 入口，`curl \| bash` 即可
- 非交互参数（`--port` / `--user` / `--password` / `-y`）
- 防火墙自动放行
- 安装摘要与客户端配置一键导出

## 客户端

安装完成后，将服务器 IP、端口、用户名、密码填入 [mieru 客户端](https://github.com/enfein/mieru/blob/main/docs/client-install.md) 或 Clash Verge Rev 等兼容客户端。

## 许可

安装脚本 MIT；mita/mieru 软件遵循上游 GPL-3.0。
