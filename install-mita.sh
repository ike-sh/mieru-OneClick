#!/usr/bin/env bash
# mieru / mita 服务端一键安装脚本
# 基于 https://github.com/enfein/mieru
set -euo pipefail

SCRIPT_VERSION="1.1.2"
UPSTREAM_REPO="enfein/mieru"
GITHUB_API="https://api.github.com/repos/${UPSTREAM_REPO}/releases/latest"
GITHUB_DL="https://github.com/${UPSTREAM_REPO}/releases/download"
MITA_BIN="/usr/local/bin/mita"
MITA_MARKER="/etc/mita/.mieru-oneclick"
MITA_STATE="/etc/mita/install-state.env"
INSTALL_SCRIPT_PATH="/usr/local/bin/install-mita"
SCRIPT_REPO_RAW="https://raw.githubusercontent.com/ike-sh/mieru-OneClick/v${SCRIPT_VERSION}/install-mita.sh"
OPENRC_SVC="/etc/init.d/mita"
SYSTEMD_SVC="/etc/systemd/system/mita.service"

ACTION=""
YES=0
DRY_RUN=0
LANG_ZH=1
ENABLE_BBR=0
STAGE="初始化"

PORT=""
PORT_RANGE=""
PROTOCOL="TCP"
USERNAME=""
PASSWORD=""
OP_USER=""

if [ -z "${BASH_VERSION:-}" ]; then
  echo "[错误] 请使用 bash 运行此脚本，例如: curl ... | sudo bash" >&2
  exit 1
fi

on_error() {
  msg "[错误] 步骤失败: ${STAGE}" >&2
  exit 1
}
trap on_error ERR

usage() {
  cat <<EOF
用法：install-mita.sh [选项]

mieru mita 服务端一键安装 ${SCRIPT_VERSION}
上游项目：https://github.com/${UPSTREAM_REPO}
支持系统：Debian/Ubuntu、RHEL/CentOS/Rocky、Alpine Linux

无参数时显示交互菜单；非交互请指定动作：
  --install           安装并配置 mita
  --upgrade           升级 mita 至最新版
  --uninstall         卸载 mita
  --status            查看运行状态与配置摘要
  --client-config     根据当前服务端配置生成客户端 JSON

安装选项：
  --yes, -y           跳过确认
  --port PORT         监听端口（1025-65535）
  --port-range RANGE  监听端口段，如 9000-9010
  --protocol TCP|UDP  传输协议（默认 TCP）
  --user NAME         代理用户名
  --password PASS     代理密码
  --op-user USER      加入 mita 用户组的 Linux 用户
  --enable-bbr        安装后启用 TCP BBR
  --lang en           使用英文提示

其它：
  --dry-run           仅预览，不执行
  --help, -h          显示帮助
  --version           显示版本

一键安装（交互式）：
  curl -fsSL https://raw.githubusercontent.com/ike-sh/mieru-OneClick/main/install-mita.sh | sudo bash

非交互示例：
  curl -fsSL .../install-mita.sh | sudo bash -s -- --install -y --port 2088 --user alice --password 'secret'
EOF
}

msg() { printf '%s\n' "$*"; }
info() { msg "==> $*"; }
warn() { msg "[警告] $*"; }
die() { msg "[错误] $*" >&2; exit 1; }

t() {
  local zh="$1"
  local en="$2"
  if [ "$LANG_ZH" -eq 1 ]; then
    msg "$zh"
  else
    msg "$en"
  fi
}

while [ $# -gt 0 ]; do
  case "$1" in
    --install) ACTION=install ;;
    --upgrade) ACTION=upgrade ;;
    --uninstall) ACTION=uninstall ;;
    --status) ACTION=status ;;
    --client-config) ACTION=client-config ;;
    --menu) ACTION=menu ;;
    --yes|-y) YES=1 ;;
    --dry-run) DRY_RUN=1 ;;
    --port)
      PORT="${2:-}"
      [ -n "$PORT" ] || die "--port 需要端口号"
      shift
      ;;
    --port-range)
      PORT_RANGE="${2:-}"
      [ -n "$PORT_RANGE" ] || die "--port-range 需要端口段"
      shift
      ;;
    --protocol)
      PROTOCOL="${2:-}"
      shift
      ;;
    --user)
      USERNAME="${2:-}"
      shift
      ;;
    --password)
      PASSWORD="${2:-}"
      shift
      ;;
    --op-user)
      OP_USER="${2:-}"
      shift
      ;;
    --enable-bbr) ENABLE_BBR=1 ;;
    --lang)
      case "${2:-}" in
        en) LANG_ZH=0 ;;
        zh|*) LANG_ZH=1 ;;
      esac
      shift
      ;;
    --help|-h) usage; exit 0 ;;
    --version) echo "mieru-OneClick install-mita.sh ${SCRIPT_VERSION}"; exit 0 ;;
    *) die "未知参数：$1（使用 --help 查看帮助）" ;;
  esac
  shift
done

run() {
  if [ "$DRY_RUN" -eq 1 ]; then
    msg "[dry-run] $*"
  else
    "$@"
  fi
}

read_tty() {
  local _var="$1"
  local _prompt="${2:-}"
  local _line=""
  if [ -n "$_prompt" ]; then
    if [ -t 0 ]; then
      read -r -p "$_prompt" _line || _line=""
    elif [ -r /dev/tty ]; then
      read -r -p "$_prompt" _line </dev/tty || _line=""
    else
      return 1
    fi
  else
    if [ -t 0 ]; then
      read -r _line || _line=""
    elif [ -r /dev/tty ]; then
      read -r _line </dev/tty || _line=""
    else
      return 1
    fi
  fi
  printf -v "$_var" '%s' "$_line"
}

confirm() {
  local prompt_zh="$1"
  local prompt_en="$2"
  local default="${3:-y}"
  if [ "$YES" -eq 1 ]; then
    return 0
  fi
  local prompt
  if [ "$LANG_ZH" -eq 1 ]; then
    prompt="$prompt_zh"
  else
    prompt="$prompt_en"
  fi
  local ans=""
  read_tty ans "$prompt" || return 1
  ans="${ans:-$default}"
  case "$ans" in
    y|Y|yes|YES) return 0 ;;
    *) return 1 ;;
  esac
}

require_root() {
  STAGE="权限检查"
  [ "$(id -u)" -eq 0 ] || die "$(t '需要 root 权限，请使用 sudo 运行' 'Root privileges required; run with sudo')"
}

require_linux() {
  STAGE="系统检查"
  case "$(uname -s)" in
    Linux) ;;
    *) die "$(t '仅支持 Linux 系统' 'Linux only')" ;;
  esac
}

require_cmd() {
  local c="$1"
  command -v "$c" >/dev/null 2>&1 || die "$(t "缺少命令：${c}" "Missing command: ${c}")"
}

detect_pkg_manager() {
  STAGE="检测包管理器"
  if [ -f /etc/alpine-release ] && command -v apk >/dev/null 2>&1; then
    echo alpine
    return
  fi
  if command -v dpkg >/dev/null 2>&1 && dpkg -l >/dev/null 2>&1; then
    echo deb
    return
  fi
  if command -v rpm >/dev/null 2>&1 && rpm -qa >/dev/null 2>&1; then
    echo rpm
    return
  fi
  die "$(t '未检测到 deb、rpm 或 apk 包管理器' 'No deb, rpm, or apk package manager detected')"
}

_has_group() {
  getent group "$1" >/dev/null 2>&1 || grep -q "^$1:" /etc/group 2>/dev/null
}

_has_user() {
  getent passwd "$1" >/dev/null 2>&1 || grep -q "^$1:" /etc/passwd 2>/dev/null
}

proto_lower() {
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]'
}

save_install_state() {
  STAGE="保存安装状态"
  run mkdir -p /etc/mita
  cat >"$MITA_STATE" <<EOF
PORT=${PORT}
PORT_RANGE=${PORT_RANGE}
PROTOCOL=${PROTOCOL}
INSTALL_SCRIPT=${INSTALL_SCRIPT_PATH}
EOF
}

load_install_state() {
  PORT=""
  PORT_RANGE=""
  PROTOCOL="TCP"
  [ -f "$MITA_STATE" ] || return 0
  # shellcheck disable=SC1090
  source "$MITA_STATE" 2>/dev/null || true
}

install_self_script() {
  STAGE="安装管理脚本"
  if [ -n "${BASH_SOURCE[0]:-}" ] && [ -f "${BASH_SOURCE[0]}" ]; then
    run install -m 0755 "${BASH_SOURCE[0]}" "$INSTALL_SCRIPT_PATH"
  else
    run curl -fsSL "$SCRIPT_REPO_RAW" -o "$INSTALL_SCRIPT_PATH"
    run chmod 0755 "$INSTALL_SCRIPT_PATH"
  fi
}

remove_self_script() {
  if [ -f "$INSTALL_SCRIPT_PATH" ]; then
    run rm -f "$INSTALL_SCRIPT_PATH"
    t "已删除管理脚本 ${INSTALL_SCRIPT_PATH}" "Removed manager script ${INSTALL_SCRIPT_PATH}"
  fi
  if [ -f "$MITA_STATE" ]; then
    run rm -f "$MITA_STATE"
  fi
}

service_manager() {
  if [ -d /run/systemd/system ] && command -v systemctl >/dev/null 2>&1; then
    echo systemd
  elif command -v rc-service >/dev/null 2>&1; then
    echo openrc
  else
    echo none
  fi
}

arch_tar_suffix() {
  local arch="$1"
  case "$arch" in
    amd64) echo linux_amd64 ;;
    arm64) echo linux_arm64 ;;
    *) die "$(t 'Alpine 不支持该架构' 'Unsupported arch for Alpine tarball')" ;;
  esac
}

detect_arch() {
  STAGE="检测 CPU 架构"
  local m
  m="$(uname -m)"
  case "$m" in
    x86_64|amd64) echo amd64 ;;
    aarch64|arm64) echo arm64 ;;
    *) die "$(t "不支持的架构：${m}（仅 amd64/arm64）" "Unsupported arch: ${m} (amd64/arm64 only)")" ;;
  esac
}

query_latest_version() {
  STAGE="查询最新版本"
  require_cmd curl
  local body tag
  body="$(curl -fsSL --connect-timeout 15 --max-time 30 "$GITHUB_API")" \
    || die "$(t '无法从 GitHub 获取最新版本' 'Failed to fetch latest release from GitHub')"
  tag="$(printf '%s' "$body" | sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n1)"
  tag="${tag#v}"
  [ -n "$tag" ] || die "$(t '解析版本号失败' 'Failed to parse release version')"
  printf '%s' "$tag"
}

mita_installed() {
  if command -v dpkg >/dev/null 2>&1 && dpkg -l mita 2>/dev/null | grep -q '^ii'; then
    return 0
  fi
  if command -v rpm >/dev/null 2>&1 && rpm -q mita >/dev/null 2>&1; then
    return 0
  fi
  [ -x "$MITA_BIN" ] && [ -f "$MITA_MARKER" ] && return 0
  command -v mita >/dev/null 2>&1
}

mita_bin() {
  if [ -x "$MITA_BIN" ]; then
    printf '%s' "$MITA_BIN"
  elif command -v mita >/dev/null 2>&1; then
    command -v mita
  else
    printf '%s' "$MITA_BIN"
  fi
}

installed_version() {
  if mita_installed; then
    "$(mita_bin)" version 2>/dev/null | sed -n '1p' | tr -d 'v'
  fi
}

package_url() {
  local ver="$1"
  local pm="$2"
  local arch="$3"
  case "${pm}:${arch}" in
    deb:amd64) echo "${GITHUB_DL}/v${ver}/mita_${ver}_amd64.deb" ;;
    deb:arm64) echo "${GITHUB_DL}/v${ver}/mita_${ver}_arm64.deb" ;;
    rpm:amd64) echo "${GITHUB_DL}/v${ver}/mita-${ver}-1.x86_64.rpm" ;;
    rpm:arm64) echo "${GITHUB_DL}/v${ver}/mita-${ver}-1.aarch64.rpm" ;;
    alpine:amd64|alpine:arm64)
      echo "${GITHUB_DL}/v${ver}/mita_${ver}_$(arch_tar_suffix "$arch").tar.gz"
      ;;
    *) die "$(t '无法构造下载链接' 'Cannot build download URL')" ;;
  esac
}

download_package() {
  local url="$1"
  local dest="$2"
  STAGE="下载安装包"
  info "$(t "下载 ${url}" "Downloading ${url}")"
  run curl -fL --connect-timeout 30 --retry 3 --retry-delay 2 -o "$dest" "$url"
  [ -s "$dest" ] || die "$(t '下载文件为空' 'Downloaded file is empty')"
}

install_alpine_deps() {
  STAGE="安装 Alpine 依赖"
  run apk add --no-cache bash curl tar ca-certificates iptables
  if [ "$(service_manager)" = openrc ]; then
    run apk add --no-cache openrc 2>/dev/null || true
  fi
}

ensure_mita_account() {
  STAGE="创建 mita 用户"
  if ! _has_group mita; then
    if command -v groupadd >/dev/null 2>&1; then
      run groupadd --system mita
    else
      run addgroup -S mita
    fi
  fi
  if ! _has_user mita; then
    if command -v useradd >/dev/null 2>&1; then
      run useradd --system -g mita -s /sbin/nologin -d /var/lib/mita mita
    else
      run adduser -S -G mita -s /sbin/nologin -h /var/lib/mita mita
    fi
  fi
  run mkdir -p /etc/mita /var/lib/mita /var/run/mita
  run chown -R mita:mita /var/lib/mita /var/run/mita 2>/dev/null || true
}

install_mita_systemd() {
  STAGE="安装 systemd 服务"
  local bin
  bin="$(mita_bin)"
  cat >"$SYSTEMD_SVC" <<EOF
[Unit]
Description=Mieru proxy server
After=network-online.target
Wants=network-online.target

[Service]
Type=exec
User=mita
Group=mita
ExecStart=${bin} run
Restart=on-failure
RestartSec=2

[Install]
WantedBy=multi-user.target
EOF
  run systemctl daemon-reload
}

install_mita_openrc() {
  STAGE="安装 OpenRC 服务"
  local bin
  bin="$(mita_bin)"
  cat >"$OPENRC_SVC" <<EOF
#!/sbin/openrc-run

name="mita"
description="Mieru proxy server"
command="${bin}"
command_args="run"
command_user="mita"
command_background="yes"
pidfile="/run/\${RC_SVCNAME}.pid"
output_log="/var/log/mita.log"
error_log="/var/log/mita.err"

depend() {
    need net
    after firewall
}
EOF
  run chmod 0755 "$OPENRC_SVC"
}

install_mita_service() {
  case "$(service_manager)" in
    systemd) install_mita_systemd ;;
    openrc) install_mita_openrc ;;
    *)
      warn "$(t '未检测到 systemd/OpenRC，将仅安装二进制' 'No systemd/OpenRC; binary only')"
      ;;
  esac
}

extract_mita_tarball() {
  local tarball="$1"
  STAGE="解压 mita 二进制"
  local tmpdir bin
  tmpdir="$(mktemp -d /tmp/mita_extract_XXXXXX)"
  run tar -xzf "$tarball" -C "$tmpdir"
  bin="$(find "$tmpdir" -type f -name mita | head -n1)"
  [ -n "$bin" ] || die "$(t '压缩包中未找到 mita 二进制' 'mita binary not found in archive')"
  run install -m 0755 "$bin" "$MITA_BIN"
  run ln -sf "$MITA_BIN" /usr/bin/mita 2>/dev/null || true
  rm -rf "$tmpdir"
  run touch "$MITA_MARKER"
}

install_package() {
  local path="$1"
  local pm="$2"
  STAGE="安装软件包"
  case "$pm" in
    deb) run dpkg -i "$path" ;;
    rpm) run rpm -Uvh --force "$path" ;;
    alpine)
      install_alpine_deps
      ensure_mita_account
      extract_mita_tarball "$path"
      install_mita_service
      ;;
    *) die "$(t '未知包管理器' 'Unknown package manager')" ;;
  esac
}

random_token() {
  if command -v openssl >/dev/null 2>&1; then
    openssl rand -base64 12 | tr -dc 'a-zA-Z0-9' | head -c 10
  else
    date +%s | sha256sum | head -c 10
  fi
}

random_port() {
  local p
  if command -v shuf >/dev/null 2>&1; then
    p="$(shuf -i 1025-65535 -n 1)"
  elif command -v awk >/dev/null 2>&1; then
    p="$(awk 'BEGIN{srand(); print int(1025 + rand() * (65535 - 1025 + 1))}')"
  else
    p=$((1025 + RANDOM % (65535 - 1025 + 1)))
  fi
  printf '%s' "$p"
}

valid_port() {
  local p="$1"
  [[ "$p" =~ ^[0-9]+$ ]] || return 1
  [ "$p" -ge 1025 ] && [ "$p" -le 65535 ]
}

valid_port_range() {
  [[ "$1" =~ ^[0-9]+-[0-9]+$ ]] || return 1
  local start end
  start="${1%-*}"
  end="${1#*-}"
  valid_port "$start" && valid_port "$end" && [ "$start" -le "$end" ]
}

collect_config_interactive() {
  STAGE="交互配置"
  [ -n "$USERNAME" ] || USERNAME="$(random_token)"
  [ -n "$PASSWORD" ] || PASSWORD="$(random_token)"
  msg ""
  t '已自动生成代理凭据（安装完成后会再次显示）:' \
    'Proxy credentials auto-generated (shown again after install):'
  t "  用户名: ${USERNAME}" "  Username: ${USERNAME}"
  t "  密码:   ${PASSWORD}" "  Password: ${PASSWORD}"
  msg ""

  if [ -z "$PORT" ] && [ -z "$PORT_RANGE" ]; then
    local default_port input=""
    default_port="$(random_port)"
    read_tty input "$(t "监听端口 [${default_port}]: " "Listen port [${default_port}]: ")" || input=""
    PORT="${input:-$default_port}"
    valid_port "$PORT" || die "$(t '非法端口' 'Invalid port')"
  fi

  if [ "$PROTOCOL" != "TCP" ] && [ "$PROTOCOL" != "UDP" ]; then
    read_tty PROTOCOL "$(t '协议 TCP/UDP [TCP]: ' 'Protocol TCP/UDP [TCP]: ')" || PROTOCOL="TCP"
    PROTOCOL="${PROTOCOL:-TCP}"
    PROTOCOL="$(printf '%s' "$PROTOCOL" | tr '[:lower:]' '[:upper:]')"
  fi
}

ensure_config_noninteractive() {
  STAGE="参数校验"
  [ -n "$USERNAME" ] || USERNAME="$(random_token)"
  [ -n "$PASSWORD" ] || PASSWORD="$(random_token)"
  if [ -z "$PORT" ] && [ -z "$PORT_RANGE" ]; then
    PORT="$(random_port)"
  fi
  if [ -n "$PORT" ]; then
    valid_port "$PORT" || die "$(t '非法端口' 'Invalid port')"
  fi
  if [ -n "$PORT_RANGE" ]; then
    valid_port_range "$PORT_RANGE" || die "$(t '非法端口段' 'Invalid port range')"
  fi
  PROTOCOL="$(printf '%s' "$PROTOCOL" | tr '[:lower:]' '[:upper:]')"
  [ "$PROTOCOL" = "TCP" ] || [ "$PROTOCOL" = "UDP" ] || die "$(t '协议必须是 TCP 或 UDP' 'Protocol must be TCP or UDP')"
}

write_server_config() {
  local cfg
  cfg="$(mktemp /tmp/mita_cfg_XXXXXX.json)"
  if [ -n "$PORT" ]; then
    cat >"$cfg" <<EOF
{
  "portBindings": [
    {
      "port": ${PORT},
      "protocol": "${PROTOCOL}"
    }
  ],
  "users": [
    {
      "name": "${USERNAME}",
      "password": "${PASSWORD}"
    }
  ],
  "loggingLevel": "INFO",
  "mtu": 1400
}
EOF
  else
    cat >"$cfg" <<EOF
{
  "portBindings": [
    {
      "portRange": "${PORT_RANGE}",
      "protocol": "${PROTOCOL}"
    }
  ],
  "users": [
    {
      "name": "${USERNAME}",
      "password": "${PASSWORD}"
    }
  ],
  "loggingLevel": "INFO",
  "mtu": 1400
}
EOF
  fi
  printf '%s' "$cfg"
}

apply_config() {
  local cfg="$1"
  STAGE="应用配置"
  run "$(mita_bin)" apply config "$cfg"
  rm -f "$cfg"
}

collect_ports_from_mita() {
  local desc bin
  bin="$(mita_bin)"
  desc="$("$bin" describe config 2>/dev/null || true)"
  if [ -z "$desc" ]; then
    load_install_state
    return 0
  fi
  PORT="$(printf '%s' "$desc" | sed -n 's/.*"port"[[:space:]]*:[[:space:]]*\([0-9][0-9]*\).*/\1/p' | head -n1)"
  PORT_RANGE="$(printf '%s' "$desc" | sed -n 's/.*"portRange"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n1)"
  PROTOCOL="$(printf '%s' "$desc" | sed -n 's/.*"protocol"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n1)"
  PROTOCOL="${PROTOCOL:-TCP}"
}

open_firewall() {
  STAGE="配置防火墙"
  local ports=() proto
  proto="$(proto_lower "$PROTOCOL")"
  if [ -n "$PORT" ]; then
    ports+=("$PORT")
  elif [ -n "$PORT_RANGE" ]; then
    ports+=("$PORT_RANGE")
  fi

  if command -v ufw >/dev/null 2>&1 && ufw status 2>/dev/null | grep -q 'Status: active'; then
    for p in "${ports[@]}"; do
      run ufw allow "${p}/${proto}" || true
    done
    return
  fi

  if command -v firewall-cmd >/dev/null 2>&1 && firewall-cmd --state >/dev/null 2>&1; then
    for p in "${ports[@]}"; do
      run firewall-cmd --permanent --add-port="${p}/${proto}" || true
    done
    run firewall-cmd --reload || true
    return
  fi

  if [ -f /etc/alpine-release ] && command -v iptables >/dev/null 2>&1; then
    for p in "${ports[@]}"; do
      if [[ "$p" == *-* ]]; then
        local start end port
        start="${p%-*}"
        end="${p#*-}"
        port="$start"
        while [ "$port" -le "$end" ]; do
          run iptables -C INPUT -p "$proto" --dport "$port" -j ACCEPT 2>/dev/null \
            || run iptables -I INPUT -p "$proto" --dport "$port" -j ACCEPT || true
          port=$((port + 1))
        done
      else
        run iptables -C INPUT -p "$proto" --dport "$p" -j ACCEPT 2>/dev/null \
          || run iptables -I INPUT -p "$proto" --dport "$p" -j ACCEPT || true
      fi
    done
    if [ -d /etc/iptables ]; then
      run mkdir -p /etc/iptables
      run iptables-save > /etc/iptables/rules.v4 2>/dev/null || true
    fi
  fi
}

close_firewall() {
  STAGE="清理防火墙规则"
  collect_ports_from_mita
  local ports=() proto
  proto="$(proto_lower "$PROTOCOL")"
  if [ -n "$PORT" ]; then
    ports+=("$PORT")
  elif [ -n "$PORT_RANGE" ]; then
    ports+=("$PORT_RANGE")
  fi
  [ "${#ports[@]}" -gt 0 ] || return 0

  if command -v ufw >/dev/null 2>&1 && ufw status 2>/dev/null | grep -q 'Status: active'; then
    for p in "${ports[@]}"; do
      run ufw delete allow "${p}/${proto}" 2>/dev/null || true
    done
    return
  fi

  if command -v firewall-cmd >/dev/null 2>&1 && firewall-cmd --state >/dev/null 2>&1; then
    for p in "${ports[@]}"; do
      run firewall-cmd --permanent --remove-port="${p}/${proto}" 2>/dev/null || true
    done
    run firewall-cmd --reload 2>/dev/null || true
    return
  fi

  if command -v iptables >/dev/null 2>&1; then
    for p in "${ports[@]}"; do
      if [[ "$p" == *-* ]]; then
        local start end port
        start="${p%-*}"
        end="${p#*-}"
        port="$start"
        while [ "$port" -le "$end" ]; do
          run iptables -D INPUT -p "$proto" --dport "$port" -j ACCEPT 2>/dev/null || true
          port=$((port + 1))
        done
      else
        run iptables -D INPUT -p "$proto" --dport "$p" -j ACCEPT 2>/dev/null || true
      fi
    done
    if [ -d /etc/iptables ]; then
      run iptables-save > /etc/iptables/rules.v4 2>/dev/null || true
    fi
  fi
}

public_ip() {
  curl -fsSL --connect-timeout 5 --max-time 10 https://checkip.amazonaws.com 2>/dev/null \
    || curl -fsSL --connect-timeout 5 --max-time 10 https://api.ip.sb/ip 2>/dev/null \
    || hostname -I 2>/dev/null | awk '{print $1}'
}

start_mita() {
  STAGE="启动服务"
  local sm bin
  sm="$(service_manager)"
  bin="$(mita_bin)"
  run "$bin" stop 2>/dev/null || true
  sleep 1
  case "$sm" in
    systemd)
      run systemctl enable mita 2>/dev/null || true
      run systemctl restart mita 2>/dev/null || run "$bin" start
      ;;
    openrc)
      run rc-update add mita default 2>/dev/null || true
      run rc-service mita restart 2>/dev/null || run "$bin" start
      ;;
    *)
      run "$bin" start
      ;;
  esac
}

verify_mita_running() {
  STAGE="验证服务状态"
  local bin status_out
  bin="$(mita_bin)"
  sleep 2
  status_out="$("$bin" status 2>/dev/null || true)"
  if printf '%s' "$status_out" | grep -q 'RUNNING'; then
    t 'mita 服务运行正常' 'mita service is running'
    return 0
  fi
  warn "$(t 'mita 可能未处于 RUNNING 状态，请执行: mita status' \
    'mita may not be RUNNING; check: mita status')"
  msg "$status_out"
}

add_op_user() {
  local u="$1"
  [ -n "$u" ] || return 0
  STAGE="添加操作用户"
  if id "$u" >/dev/null 2>&1; then
    if command -v usermod >/dev/null 2>&1; then
      run usermod -a -G mita "$u"
    else
      run addgroup "$u" mita 2>/dev/null || true
    fi
    t "已将 ${u} 加入 mita 组（需重新登录生效）" "Added ${u} to mita group (re-login required)"
  else
    warn "$(t "用户 ${u} 不存在，已跳过" "User ${u} not found, skipped")"
  fi
}

enable_tcp_bbr() {
  STAGE="启用 TCP BBR"
  local url="https://raw.githubusercontent.com/${UPSTREAM_REPO}/refs/heads/main/tools/enable_tcp_bbr.py"
  local tmp
  tmp="$(mktemp /tmp/enable_bbr_XXXXXX.py)"
  curl -fsSL -o "$tmp" "$url"
  chmod +x "$tmp"
  if command -v python3 >/dev/null 2>&1; then
    run python3 "$tmp"
  else
    warn "$(t '未找到 python3，跳过 BBR 配置' 'python3 not found, skipping BBR')"
  fi
  rm -f "$tmp"
}

generate_share_link() {
  local ip="$1"
  local query="profile=default&mtu=1400&handshake-mode=HANDSHAKE_STANDARD"
  if [ -n "$PORT" ]; then
    query="${query}&port=${PORT}&protocol=${PROTOCOL}"
  else
    query="${query}&port=${PORT_RANGE}&protocol=${PROTOCOL}"
  fi
  printf 'mierus://%s:%s@%s?%s' "$USERNAME" "$PASSWORD" "$ip" "$query"
}

build_client_json() {
  local ip="$1"
  local port_json
  if [ -n "$PORT" ]; then
    port_json="\"port\": ${PORT}"
  else
    port_json="\"portRange\": \"${PORT_RANGE}\""
  fi
  cat <<EOF
{
  "profiles": [
    {
      "profileName": "default",
      "user": {
        "name": "${USERNAME}",
        "password": "${PASSWORD}"
      },
      "servers": [
        {
          "ipAddress": "${ip}",
          "portBindings": [
            {
              ${port_json},
              "protocol": "${PROTOCOL}"
            }
          ]
        }
      ],
      "handshakeMode": "HANDSHAKE_STANDARD"
    }
  ],
  "activeProfile": "default",
  "rpcPort": 8964,
  "socks5Port": 1080,
  "loggingLevel": "INFO",
  "httpProxyPort": 8080
}
EOF
}

print_summary() {
  local ip link cfg_path
  ip="$(public_ip || true)"
  msg ""
  t '========== 安装完成 ==========' '========== Installation complete =========='
  if [ -n "$ip" ]; then
    link="$(generate_share_link "$ip")"
    msg ""
    t '【节点链接】' '[Share link]'
    msg "$link"
    cfg_path="/root/mieru_client_$(date +%Y%m%d_%H%M%S).json"
    if [ "$DRY_RUN" -ne 1 ]; then
      build_client_json "$ip" >"$cfg_path"
    fi
    msg ""
    t '【客户端 JSON 配置】' '[Client JSON config]'
    if [ "$DRY_RUN" -ne 1 ]; then
      t "  已保存: ${cfg_path}" "  Saved:  ${cfg_path}"
    fi
    msg ""
    build_client_json "$ip"
  else
    warn "$(t '未能获取公网 IP，请手动将下方连接信息填入客户端' \
      'Could not detect public IP; use connection info below manually')"
  fi
  msg ""
  t '【连接信息】' '[Connection info]'
  t "  服务器: ${ip:-<未知>}" "  Server:   ${ip:-<unknown>}"
  t "  用户名: ${USERNAME}" "  Username: ${USERNAME}"
  t "  密码:   ${PASSWORD}" "  Password: ${PASSWORD}"
  t "  协议:   ${PROTOCOL}" "  Protocol: ${PROTOCOL}"
  if [ -n "$PORT" ]; then
    t "  端口:   ${PORT}" "  Port:     ${PORT}"
  else
    t "  端口段: ${PORT_RANGE}" "  Port range: ${PORT_RANGE}"
  fi
  msg ""
  t '导入方式:' 'Import options:'
  msg '  mieru import config "<节点链接>"'
  msg '  mieru apply config /root/mieru_client_*.json'
}

generate_client_config() {
  local ip cfg_path
  ip="$(public_ip || echo 'YOUR_SERVER_IP')"
  cfg_path="/root/mieru_client_$(date +%Y%m%d_%H%M%S).json"
  build_client_json "$ip" >"$cfg_path"
  t "客户端配置已保存: ${cfg_path}" "Client config saved: ${cfg_path}"
  local link
  link="$(generate_share_link "$ip")"
  msg ""
  t '节点链接:' 'Share link:'
  msg "$link"
  msg ""
  cat "$cfg_path"
}

do_install() {
  require_root
  require_linux
  require_cmd curl

  local pm arch ver url pkg tmp cfg
  pm="$(detect_pkg_manager)"
  arch="$(detect_arch)"

  if mita_installed; then
    local cur
    cur="$(installed_version || true)"
    t "检测到已安装 mita ${cur:-未知版本}" "mita already installed (${cur:-unknown})"
    if ! confirm '继续将重新配置并尝试升级？[y/N]: ' 'Continue to reconfigure/upgrade? [y/N]: ' n; then
      exit 0
    fi
  fi

  if [ "$YES" -eq 1 ]; then
    ensure_config_noninteractive
  else
    collect_config_interactive
  fi

  ver="$(query_latest_version)"
  url="$(package_url "$ver" "$pm" "$arch")"
  tmp="$(mktemp "/tmp/mita_pkg_XXXXXX.${url##*.}")"
  download_package "$url" "$tmp"
  install_package "$tmp" "$pm"
  rm -f "$tmp"

  add_op_user "$OP_USER"
  cfg="$(write_server_config)"
  apply_config "$cfg"
  open_firewall
  start_mita
  verify_mita_running
  install_self_script
  save_install_state

  if [ "$ENABLE_BBR" -eq 1 ]; then
    enable_tcp_bbr
  elif confirm '是否启用 TCP BBR？[y/N]: ' 'Enable TCP BBR? [y/N]: ' n; then
    enable_tcp_bbr
  fi

  print_summary
}

do_upgrade() {
  require_root
  require_linux
  require_cmd curl
  local pm arch ver url tmp
  pm="$(detect_pkg_manager)"
  arch="$(detect_arch)"
  ver="$(query_latest_version)"
  local cur
  cur="$(installed_version || true)"
  if [ -n "$cur" ] && [ "$cur" = "$ver" ]; then
    t "已是最新版本 ${ver}" "Already on latest version ${ver}"
    exit 0
  fi
  url="$(package_url "$ver" "$pm" "$arch")"
  tmp="$(mktemp "/tmp/mita_pkg_XXXXXX.${url##*.}")"
  download_package "$url" "$tmp"
  install_package "$tmp" "$pm"
  rm -f "$tmp"
  install_self_script
  run "$(mita_bin)" reload 2>/dev/null || start_mita
  verify_mita_running
  t "已升级至 ${ver}" "Upgraded to ${ver}"
}

remove_mita_common() {
  local bin
  bin="$(mita_bin)"
  run "$bin" stop 2>/dev/null || true
  case "$(service_manager)" in
    systemd)
      run systemctl stop mita 2>/dev/null || true
      run systemctl disable mita 2>/dev/null || true
      ;;
    openrc)
      run rc-service mita stop 2>/dev/null || true
      run rc-update del mita default 2>/dev/null || true
      ;;
  esac
  run rm -f /var/log/mita.log /var/log/mita.err
  run rm -f /root/mieru_client_*.json 2>/dev/null || true
  run rm -rf /etc/mita /var/lib/mita /var/run/mita /var/run/mita.sock
  run rm -f "$MITA_BIN" /usr/bin/mita "$MITA_MARKER" "$OPENRC_SVC"
  run rm -f /lib/systemd/system/mita.service /usr/lib/systemd/system/mita.service "$SYSTEMD_SVC"
  run rm -f /etc/sysctl.d/mieru_tcp_bbr.conf
  run systemctl daemon-reload 2>/dev/null || true
  remove_self_script
  if _has_user mita; then
    run deluser mita 2>/dev/null || run userdel mita 2>/dev/null || true
  fi
  if _has_group mita; then
    run delgroup mita 2>/dev/null || run groupdel mita 2>/dev/null || true
  fi
}

do_uninstall() {
  require_root
  mita_installed || die "$(t 'mita 未安装' 'mita is not installed')"
  confirm '确认卸载 mita、管理脚本及全部配置？[y/N]: ' \
    'Uninstall mita, manager script, and all config? [y/N]: ' n || exit 0
  local pm
  pm="$(detect_pkg_manager)"
  close_firewall
  case "$pm" in
    deb) run dpkg -P mita 2>/dev/null || true ;;
    rpm) run rpm -e mita 2>/dev/null || true ;;
    alpine) ;;
  esac
  remove_mita_common
  t 'mita 及安装脚本已完全卸载' 'mita and install script fully removed'
}

do_status() {
  local bin
  bin="$(mita_bin)"
  if ! mita_installed; then
    t 'mita 未安装' 'mita is not installed'
    exit 1
  fi
  msg ""
  "$bin" version 2>/dev/null || true
  systemctl status mita --no-pager 2>/dev/null || rc-service mita status 2>/dev/null || true
  msg ""
  "$bin" status 2>/dev/null || true
  msg ""
  "$bin" describe config 2>/dev/null || true
}

do_client_config() {
  require_root
  mita_installed || die "$(t 'mita 未安装' 'mita is not installed')"
  local desc bin
  bin="$(mita_bin)"
  desc="$("$bin" describe config 2>/dev/null || true)"
  [ -n "$desc" ] || die "$(t '无法读取服务端配置' 'Cannot read server config')"

  USERNAME="$(printf '%s' "$desc" | sed -n 's/.*"name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n1)"
  PASSWORD="$(printf '%s' "$desc" | sed -n 's/.*"password"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n1)"
  PROTOCOL="$(printf '%s' "$desc" | sed -n 's/.*"protocol"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n1)"
  PORT="$(printf '%s' "$desc" | sed -n 's/.*"port"[[:space:]]*:[[:space:]]*\([0-9][0-9]*\).*/\1/p' | head -n1)"
  PORT_RANGE="$(printf '%s' "$desc" | sed -n 's/.*"portRange"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n1)"
  [ -n "$USERNAME" ] && [ -n "$PASSWORD" ] || die "$(t '配置中缺少用户信息' 'Missing user info in config')"
  generate_client_config
}

show_menu() {
  msg ""
  t 'mieru mita 服务端一键安装' 'mieru mita server one-click installer'
  msg "  1) 安装 / 配置"
  msg "  2) 升级"
  msg "  3) 卸载"
  msg "  4) 状态"
  msg "  5) 生成客户端配置"
  msg "  6) 退出"
  msg ""
  local choice=""
  read_tty choice "$(t '请选择 [1-6]: ' 'Choose [1-6]: ')" || die "$(t '无法读取输入' 'Cannot read input')"
  case "$choice" in
    1) ACTION=install ;;
    2) ACTION=upgrade ;;
    3) ACTION=uninstall ;;
    4) ACTION=status ;;
    5) ACTION=client-config ;;
    6) exit 0 ;;
    *) die "$(t '无效选择' 'Invalid choice')" ;;
  esac
}

main() {
  if [ -z "$ACTION" ]; then
    show_menu
  fi
  case "$ACTION" in
    install) do_install ;;
    upgrade) do_upgrade ;;
    uninstall) do_uninstall ;;
    status) do_status ;;
    client-config) do_client_config ;;
    *) usage; exit 1 ;;
  esac
}

main
