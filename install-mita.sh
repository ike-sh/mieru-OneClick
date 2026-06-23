#!/usr/bin/env bash
# mieru / mita 服务端一键安装脚本
# 作者: ike · https://github.com/ike-sh/mieru-OneClick
# 基于 https://github.com/enfein/mieru
set -euo pipefail

SCRIPT_VERSION="1.2.19"
SCRIPT_AUTHOR="ike"
SCRIPT_REPO="ike-sh/mieru-OneClick"
UPSTREAM_REPO="enfein/mieru"
GITHUB_API="https://api.github.com/repos/${UPSTREAM_REPO}/releases/latest"
GITHUB_DL="https://github.com/${UPSTREAM_REPO}/releases/download"
MITA_BIN="/usr/local/bin/mita"
MITA_REAL_BIN="/usr/local/bin/mita-real"
MITA_MARKER="/etc/mita/.mieru-oneclick"
MITA_STATE="/etc/mita/install-state.env"
INSTALL_SCRIPT_PATH="/usr/local/bin/install-mita"
MITA_MENU_PATH="/usr/local/bin/mita-menu"
MITA_PROFILE_D="/etc/profile.d/mita-oneclick.sh"
SCRIPT_REPO_RAW="https://raw.githubusercontent.com/ike-sh/mieru-OneClick/v${SCRIPT_VERSION}/install-mita.sh"
OPENRC_SVC="/etc/init.d/mita"
SYSTEMD_SVC="/etc/systemd/system/mita.service"

ACTION=""
MENU_MODE=0
MENU_SCRIPTS_READY=0
YES=0
DRY_RUN=0
LANG_ZH=1
ENABLE_BBR=0
STAGE="初始化"

PORT=""
PORT_RANGE=""
PROTOCOL="TCP"
PROTOCOL_CLI=0
USERNAME=""
PASSWORD=""
OP_USER=""
MTU=1400
MULTIPLEXING="MULTIPLEXING_LOW"
CLIENT_RPC_PORT=8964
CLIENT_SOCKS5_PORT=1080
CLIENT_HTTP_PORT=8080

if [ -z "${BASH_VERSION:-}" ]; then
  echo "[错误] 请使用 bash 运行此脚本" >&2
  if [ -f /etc/alpine-release ]; then
    echo "Alpine 默认无 bash，请先安装后执行（root 无需 sudo）：" >&2
    echo "  apk add --no-cache bash curl" >&2
    echo "  curl -fsSL https://raw.githubusercontent.com/ike-sh/mieru-OneClick/main/install-mita.sh | bash" >&2
  else
    echo "  curl -fsSL .../install-mita.sh | sudo bash" >&2
  fi
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
  --install           新装 mita（已安装时建议用 --reconfigure）
  --reconfigure       修改端口 / 密码 / 协议（不重装二进制）
  --upgrade           升级 mita 至最新版
  --uninstall         卸载 mita
  --status            查看运行状态与配置摘要
  --client-config     查看节点链接并生成客户端 JSON（同 --show）

安装选项：
  --yes, -y           跳过确认
  --port PORT         监听端口（1025-65535）
  --port-range RANGE  监听端口段，如 9000-9010
  --protocol TCP|UDP|BOTH  传输协议（默认 TCP；BOTH 时 UDP 使用 PORT+1）
  --user NAME         代理用户名
  --password PASS     代理密码
  --op-user USER      加入 mita 用户组的 Linux 用户
  --enable-bbr        安装后启用 TCP BBR
  --lang en           使用英文提示

其它：
  --dry-run           仅预览，不执行
  --help, -h          显示帮助
  --version           显示版本

快捷命令（子命令不区分大小写）：
  install-mita                    打开菜单
  install-mita status             查看状态
  install-mita reconfigure        重新配置
  install-mita show               查看节点链接
  mita-menu                       同上（安装后可用）
  登录 shell 下输入 mita          管理子命令不区分大小写；mita start 等仍走官方二进制

一键安装（交互式，Debian/Ubuntu/CentOS 等）：
  curl -fsSL https://raw.githubusercontent.com/ike-sh/mieru-OneClick/main/install-mita.sh | sudo bash

Alpine Linux（无 sudo，需先装 bash）：
  apk add --no-cache bash curl
  curl -fsSL https://raw.githubusercontent.com/ike-sh/mieru-OneClick/main/install-mita.sh | bash

Alpine 一行命令：
  apk add --no-cache bash curl && curl -fsSL https://raw.githubusercontent.com/ike-sh/mieru-OneClick/main/install-mita.sh | bash

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

print_banner() {
  msg ""
  t "mieru mita 服务端一键安装  v${SCRIPT_VERSION}" \
    "mieru mita server one-click installer  v${SCRIPT_VERSION}"
  t "作者: ${SCRIPT_AUTHOR} · https://github.com/${SCRIPT_REPO}" \
    "Author: ${SCRIPT_AUTHOR} · https://github.com/${SCRIPT_REPO}"
}

while [ $# -gt 0 ]; do
  _arg_lc="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')"
  case "$_arg_lc" in
    --install) ACTION=install ;;
    --reconfigure) ACTION=reconfigure ;;
    --upgrade) ACTION=upgrade ;;
    --uninstall) ACTION=uninstall ;;
    --status) ACTION=status ;;
    --client-config|--show) ACTION=client-config ;;
    install|upgrade|uninstall|status|reconfigure|client-config|show|menu|配置|节点)
      [ -z "$ACTION" ] && ACTION="$_arg_lc"
      [ "$_arg_lc" = show ] && ACTION=client-config
      [ "$_arg_lc" = menu ] && ACTION=""
      [ "$_arg_lc" = 配置 ] && ACTION=client-config
      [ "$_arg_lc" = 节点 ] && ACTION=client-config
      ;;
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
      PROTOCOL_CLI=1
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
    --version) echo "mieru-OneClick install-mita.sh ${SCRIPT_VERSION} by ${SCRIPT_AUTHOR}"; exit 0 ;;
    *)
      if [[ "$1" == --* ]]; then
        die "未知参数：$1（使用 --help 查看帮助）"
      fi
      ;;
  esac
  shift
done
unset _arg_lc

run() {
  if [ "$DRY_RUN" -eq 1 ]; then
    msg "[dry-run] $*"
  else
    "$@"
  fi
}

# BusyBox mktemp（Alpine）要求 XXXXXX 在模板末尾；GNU 允许中间占位
mktemp_file() {
  local suffix="${1:-}"
  local f
  f="$(mktemp /tmp/mita.XXXXXX 2>/dev/null)" || f="/tmp/mita_$$_${RANDOM}"
  [ -n "$suffix" ] || { printf '%s' "$f"; return; }
  local out="${f}${suffix}"
  if [ "$f" != "$out" ]; then
    mv "$f" "$out" 2>/dev/null || { : >"$out"; rm -f "$f"; }
  fi
  printf '%s' "$out"
}

mktemp_dir() {
  local d
  d="$(mktemp -d /tmp/mita.XXXXXX 2>/dev/null)" \
    || d="$(mktemp -d 2>/dev/null)" \
    || { d="/tmp/mita_$$_${RANDOM}"; mkdir -p "$d"; }
  printf '%s' "$d"
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
  if [ "$(id -u)" -eq 0 ]; then
    return 0
  fi
  if [ -f /etc/alpine-release ]; then
    die "$(t '需要 root 权限；Alpine 请 su - 或 docker exec -u root 后直接 bash 运行（无 sudo）' \
      'Root required; on Alpine use su - or docker exec -u root, then run with bash (no sudo)')"
  fi
  die "$(t '需要 root 权限，请使用 sudo 运行' 'Root privileges required; run with sudo')"
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

normalize_protocol() {
  local v
  v="$(printf '%s' "$1" | tr '[:lower:]' '[:upper:]')"
  case "$v" in
    TCP|UDP|BOTH) printf '%s' "$v" ;;
    DUAL|ALL|双协议) printf '%s' BOTH ;;
    *) return 1 ;;
  esac
}

protocols_for_mode() {
  case "$PROTOCOL" in
    BOTH) printf '%s\n' TCP UDP ;;
    *) printf '%s\n' "$PROTOCOL" ;;
  esac
}

protocol_label() {
  case "$PROTOCOL" in
    BOTH)
      if [ -n "$PORT" ]; then
        if [ "$LANG_ZH" -eq 1 ]; then
          printf '%s' "TCP(${PORT}) + UDP($((PORT + 1)))"
        else
          printf '%s' "TCP(${PORT}) + UDP($((PORT + 1)))"
        fi
      else
        if [ "$LANG_ZH" -eq 1 ]; then
          printf '%s' 'TCP + UDP（同端口段）'
        else
          printf '%s' 'TCP + UDP (same port range)'
        fi
      fi
      ;;
    *) printf '%s' "$PROTOCOL" ;;
  esac
}

port_for_protocol() {
  local proto="$1"
  if [ -n "$PORT" ]; then
    if [ "$PROTOCOL" = "BOTH" ] && [ "$proto" = "UDP" ]; then
      printf '%s' "$((PORT + 1))"
    else
      printf '%s' "$PORT"
    fi
  else
    printf '%s' "$PORT_RANGE"
  fi
}

port_protocol_pairs() {
  local proto p
  while IFS= read -r proto; do
    p="$(port_for_protocol "$proto")"
    if [ -n "$PORT" ]; then
      valid_port "$p" || die "$(t "双协议需要 ${PORT} 与 $((PORT + 1)) 均在 1025-65535" \
        "Dual protocol requires ports ${PORT} and $((PORT + 1)) in 1025-65535")"
    fi
    printf '%s|%s\n' "$proto" "$p"
  done < <(protocols_for_mode)
}

save_install_state() {
  STAGE="保存安装状态"
  run mkdir -p /etc/mita
  cat >"$MITA_STATE" <<EOF
PORT=${PORT}
PORT_RANGE=${PORT_RANGE}
PROTOCOL=${PROTOCOL}
USERNAME=${USERNAME}
PASSWORD=${PASSWORD}
INSTALL_SCRIPT=${INSTALL_SCRIPT_PATH}
INSTALL_METHOD=oneclick
EOF
  run chmod 0600 "$MITA_STATE" 2>/dev/null || true
  run touch "$MITA_MARKER"
}

mark_oneclick_install() {
  run mkdir -p /etc/mita
  run touch "$MITA_MARKER"
}

installed_by_oneclick() {
  [ -f "$MITA_MARKER" ]
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
  local main_url="https://raw.githubusercontent.com/ike-sh/mieru-OneClick/main/install-mita.sh"
  if curl -fsSL --connect-timeout 15 --max-time 60 "$main_url" -o "$INSTALL_SCRIPT_PATH" 2>/dev/null; then
    run chmod 0755 "$INSTALL_SCRIPT_PATH"
  elif [ -n "${BASH_SOURCE[0]:-}" ] && [ -f "${BASH_SOURCE[0]}" ]; then
    local src_real dest_real
    src_real="$(readlink -f "${BASH_SOURCE[0]}" 2>/dev/null || realpath "${BASH_SOURCE[0]}" 2>/dev/null || printf '%s' "${BASH_SOURCE[0]}")"
    dest_real="$(readlink -f "$INSTALL_SCRIPT_PATH" 2>/dev/null || realpath "$INSTALL_SCRIPT_PATH" 2>/dev/null || printf '%s' "$INSTALL_SCRIPT_PATH")"
    if [ "$src_real" != "$dest_real" ]; then
      run install -m 0755 "${BASH_SOURCE[0]}" "$INSTALL_SCRIPT_PATH"
    fi
  else
    run curl -fsSL "$SCRIPT_REPO_RAW" -o "$INSTALL_SCRIPT_PATH"
    run chmod 0755 "$INSTALL_SCRIPT_PATH"
  fi
  install_mita_wrapper_force
  migrate_mita_binary_layout
  install_mita_shortcuts
}

install_mita_wrapper_force() {
  if is_mita_wrapper "$MITA_BIN"; then
    return 0
  fi
  if mita_installed || [ -f "$MITA_MARKER" ] || [ -x "$INSTALL_SCRIPT_PATH" ]; then
    install_mita_wrapper
  fi
}

ensure_management_scripts() {
  STAGE="更新管理脚本"
  install_self_script
  repair_mita_binary_paths
}

install_mita_wrapper() {
  STAGE="安装 mita 快捷入口"
  cat >"$MITA_BIN" <<'EOF'
#!/usr/bin/env bash
# mieru-OneClick mita wrapper — 无参数打开菜单；管理子命令不区分大小写
INSTALL_MITA="/usr/local/bin/install-mita"

find_mita_real() {
  local c
  for c in /usr/local/bin/mita-real /usr/bin/mita; do
    [ -x "$c" ] || continue
    [ "$(head -c 4 "$c" 2>/dev/null || true)" = $'\x7fELF' ] || continue
    printf '%s' "$c"
    return 0
  done
  return 1
}

MITA_REAL="$(find_mita_real || true)"

if [ $# -eq 0 ]; then
  if [ -x "$INSTALL_MITA" ]; then
    exec "$INSTALL_MITA"
  fi
  echo "[错误] 未找到 install-mita，请先运行一键安装脚本" >&2
  echo "  curl -fsSL https://raw.githubusercontent.com/ike-sh/mieru-OneClick/main/install-mita.sh | bash" >&2
  exit 1
fi

if [ $# -gt 0 ] && [ -x "$INSTALL_MITA" ]; then
  cmd="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')"
  case "$cmd" in
    menu|install|upgrade|uninstall|status|reconfigure|client-config|show|配置|节点|help)
      shift
      exec "$INSTALL_MITA" "$cmd" "$@"
      ;;
  esac
fi

if [ -z "$MITA_REAL" ]; then
  echo "[错误] 未找到 mita 二进制；Debian 可执行: apt install --reinstall mita" >&2
  exit 127
fi
exec "$MITA_REAL" "$@"
EOF
  run chmod 0755 "$MITA_BIN"
  hash -r 2>/dev/null || true
}

repair_mita_binary_paths() {
  STAGE="修复 mita 二进制路径"
  local deb_bin=""
  if command -v dpkg >/dev/null 2>&1 && dpkg -l mita 2>/dev/null | grep -q '^ii'; then
    deb_bin="$(dpkg -L mita 2>/dev/null | grep '/bin/mita$' | head -n1)"
    if [ -n "$deb_bin" ] && [ -x "$deb_bin" ]; then
      if [ ! -e /usr/bin/mita ]; then
        run ln -sf "$deb_bin" /usr/bin/mita 2>/dev/null || true
      fi
    fi
  fi
  install_mita_wrapper_force
  hash -r 2>/dev/null || true
}

migrate_mita_binary_layout() {
  STAGE="迁移 mita 二进制布局"
  if [ -f "$MITA_REAL_BIN" ] && ! is_mita_elf_binary "$MITA_REAL_BIN"; then
    run rm -f "$MITA_REAL_BIN"
  fi
  if [ -f "$MITA_BIN" ] && [ ! -f "$MITA_REAL_BIN" ] && is_mita_elf_binary "$MITA_BIN"; then
    run mv "$MITA_BIN" "$MITA_REAL_BIN"
    if [ -L /usr/bin/mita ] && [ "$(readlink -f /usr/bin/mita 2>/dev/null || true)" = "$(readlink -f "$MITA_REAL_BIN" 2>/dev/null || true)" ]; then
      run rm -f /usr/bin/mita
    fi
    run ln -sf "$MITA_REAL_BIN" /usr/bin/mita-real 2>/dev/null || true
    if [ -f "$OPENRC_SVC" ]; then
      install_mita_openrc
    elif [ -f "$SYSTEMD_SVC" ]; then
      install_mita_systemd
    fi
  fi
  install_mita_wrapper_force
}

install_mita_shortcuts() {
  STAGE="安装快捷命令"
  cat >"$MITA_MENU_PATH" <<'EOF'
#!/usr/bin/env bash
# mieru-OneClick 管理快捷入口（子命令不区分大小写）
IM="/usr/local/bin/install-mita"
if [ ! -x "$IM" ]; then
  echo "[错误] 未找到 install-mita，请先完成安装" >&2
  exit 1
fi
if [ $# -eq 0 ]; then
  exec "$IM"
fi
cmd="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')"
case "$cmd" in
  install|upgrade|uninstall|status|reconfigure|client-config|show|menu|配置|节点)
    set -- "$cmd" "${@:2}"
    ;;
esac
exec "$IM" "$@"
EOF
  run chmod 0755 "$MITA_MENU_PATH"
  cat >"$MITA_PROFILE_D" <<'EOF'
# mieru-OneClick：登录 shell 下 mita 管理子命令不区分大小写
mita() {
  local im="/usr/local/bin/install-mita"
  local real="" c
  for c in /usr/local/bin/mita-real /usr/bin/mita; do
    if [ -x "$c" ] && [ "$(head -c 4 "$c" 2>/dev/null || true)" = $'\x7fELF' ]; then
      real="$c"
      break
    fi
  done
  if [ ! -x "$im" ]; then
    [ -n "$real" ] && command "$real" "$@"
    return $?
  fi
  if [ $# -eq 0 ]; then
    "$im"
    return $?
  fi
  local cmd
  cmd="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')"
  case "$cmd" in
    menu|install|upgrade|uninstall|status|reconfigure|client-config|show|配置|节点|help)
      shift
      "$im" "$cmd" "$@"
      ;;
    *)
      [ -n "$real" ] && command "$real" "$@"
      ;;
  esac
}
EOF
  run chmod 0644 "$MITA_PROFILE_D"
}

remove_mita_shortcuts() {
  run rm -f "$MITA_MENU_PATH" "$MITA_PROFILE_D"
}

remove_self_script() {
  remove_mita_shortcuts
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

mita_restart_hint() {
  case "$(service_manager)" in
    systemd) printf '%s' 'systemctl restart mita' ;;
    openrc) printf '%s' 'rc-service mita zap && rc-service mita start' ;;
    *) printf '%s' "$(mita_bin) run &" ;;
  esac
}

mita_log_hint() {
  case "$(service_manager)" in
    systemd) printf '%s' 'journalctl -e -u mita --no-pager' ;;
    openrc) printf '%s' 'tail -n 30 /var/log/mita.err /var/log/mita.log' ;;
    *) printf '%s' 'tail -n 30 /var/log/mita.err /var/log/mita.log' ;;
  esac
}

openrc_mita_status_line() {
  rc-service mita status 2>/dev/null || true
}

openrc_mita_is_crashed() {
  openrc_mita_status_line | grep -qi crashed
}

openrc_mita_is_started() {
  openrc_mita_status_line | grep -qE 'started|running'
}

openrc_mita_recover() {
  if openrc_mita_is_crashed || ! openrc_mita_is_started; then
    run rc-service mita zap 2>/dev/null || true
  fi
  run rc-service mita start 2>/dev/null || run rc-service mita restart 2>/dev/null || true
  sleep 2
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
  [ -x "$MITA_REAL_BIN" ] && [ -f "$MITA_MARKER" ] && return 0
  [ -x "$MITA_BIN" ] && [ -f "$MITA_MARKER" ] && return 0
  command -v mita >/dev/null 2>&1
}

is_mita_wrapper() {
  [ -f "$1" ] || return 1
  head -c 320 "$1" 2>/dev/null | grep -q 'mieru-OneClick mita wrapper'
}

is_mita_elf_binary() {
  [ -f "$1" ] || return 1
  [ "$(head -c 4 "$1" 2>/dev/null || true)" = $'\x7fELF' ]
}

mita_real_bin() {
  if [ -x "$MITA_REAL_BIN" ] && is_mita_elf_binary "$MITA_REAL_BIN"; then
    printf '%s' "$MITA_REAL_BIN"
  elif [ -x /usr/bin/mita ] && is_mita_elf_binary /usr/bin/mita; then
    printf '%s' /usr/bin/mita
  elif [ -x "$MITA_BIN" ] && is_mita_elf_binary "$MITA_BIN"; then
    printf '%s' "$MITA_BIN"
  elif command -v mita-real >/dev/null 2>&1 && is_mita_elf_binary "$(command -v mita-real)"; then
    command -v mita-real
  else
    printf '%s' "$MITA_REAL_BIN"
  fi
}

mita_bin() {
  mita_real_bin
}

installed_version() {
  if mita_installed; then
    "$(mita_bin)" version 2>/dev/null | sed -n '1p' | tr -d 'v'
  fi
}

version_is_current() {
  local current="$1"
  local available="$2"
  [ -n "$current" ] || return 1
  [ "$(printf '%s\n%s' "$current" "$available" | sort -V | tail -n1)" = "$current" ]
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
  verify_package_sha256 "$dest" "${url}.sha256.txt"
}

verify_package_sha256() {
  local file="$1"
  local sha_url="$2"
  [ "$DRY_RUN" -eq 1 ] && return 0
  STAGE="校验安装包 SHA256"
  local sha_file expected actual
  sha_file="$(mktemp_file .txt)"
  if ! curl -fsSL --connect-timeout 15 --max-time 30 "$sha_url" -o "$sha_file" 2>/dev/null; then
    warn "$(t "无法下载校验文件，已跳过: ${sha_url}" "Checksum file unavailable, skipped: ${sha_url}")"
    rm -f "$sha_file"
    return 0
  fi
  expected="$(awk '{print $1}' "$sha_file" | head -n1)"
  [ -n "$expected" ] || die "$(t '校验文件格式无效' 'Invalid checksum file')"
  if command -v sha256sum >/dev/null 2>&1; then
    actual="$(sha256sum "$file" | awk '{print $1}')"
  elif command -v shasum >/dev/null 2>&1; then
    actual="$(shasum -a 256 "$file" | awk '{print $1}')"
  else
    warn "$(t '未找到 sha256sum/shasum，跳过完整性校验' 'sha256sum/shasum not found, skipping verify')"
    rm -f "$sha_file"
    return 0
  fi
  rm -f "$sha_file"
  [ "$expected" = "$actual" ] || die "$(t '安装包 SHA256 校验失败' 'Package SHA256 verification failed')"
  t '安装包 SHA256 校验通过' 'Package SHA256 verified'
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
  run mkdir -p /etc/mita /var/lib/mita /var/run/mita /run/mita
  run chown -R mita:mita /etc/mita /var/lib/mita /var/run/mita /run/mita 2>/dev/null || true
  run chmod 0750 /etc/mita
  run chmod 0755 /var/lib/mita /var/run/mita /run/mita
}

install_mita_systemd() {
  STAGE="安装 systemd 服务"
  local bin
  bin="$(mita_real_bin)"
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
  bin="$(mita_real_bin)"
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
directory="/var/lib/mita"
respawn
respawn_delay 5
respawn_max 0

depend() {
    need net localmount
    after firewall
}

start_pre() {
    checkpath --directory --owner mita:mita --mode 0750 /etc/mita
    checkpath --directory --owner mita:mita --mode 0755 /var/lib/mita /var/run/mita /run/mita
    checkpath --file --owner mita:mita --mode 0644 /var/log/mita.log /var/log/mita.err
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
  tmpdir="$(mktemp_dir)"
  run tar -xzf "$tarball" -C "$tmpdir"
  bin="$(find "$tmpdir" -type f -name mita | head -n1)"
  [ -n "$bin" ] || die "$(t '压缩包中未找到 mita 二进制' 'mita binary not found in archive')"
  run install -m 0755 "$bin" "$MITA_REAL_BIN"
  run rm -f /usr/bin/mita /usr/bin/mita-real
  run ln -sf "$MITA_REAL_BIN" /usr/bin/mita-real 2>/dev/null || true
  install_mita_wrapper
  rm -rf "$tmpdir"
  run touch "$MITA_MARKER"
}

install_package() {
  local path="$1"
  local pm="$2"
  STAGE="安装软件包"
  case "$pm" in
    deb)
      run dpkg -i "$path" || run apt-get install -f -y
      mark_oneclick_install
      ;;
    rpm)
      run rpm -Uvh --force "$path"
      mark_oneclick_install
      ;;
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

choose_protocol_interactive() {
  msg ""
  t '传输协议:' 'Transport protocol:'
  t '  1) TCP（推荐；Clash 设 udp: true 即可）' \
    '  1) TCP (recommended; Clash udp: true is enough)'
  t '  2) UDP' '  2) UDP'
  t '  3) TCP + UDP 双协议（UDP 端口 = TCP 端口 + 1）' \
    '  3) TCP + UDP dual (UDP port = TCP port + 1)'
  msg ""
  local choice=""
  read_tty choice "$(t '请选择协议 [1-3，默认 1]: ' 'Choose protocol [1-3, default 1]: ')" || choice="1"
  choice="${choice:-1}"
  case "$choice" in
    1|TCP|tcp) PROTOCOL="TCP" ;;
    2|UDP|udp) PROTOCOL="UDP" ;;
    3|BOTH|both|双协议) PROTOCOL="BOTH" ;;
    *)
      warn "$(t "无效选择「${choice}」，使用默认 TCP" "Invalid choice \"${choice}\", using TCP")"
      PROTOCOL="TCP"
      ;;
  esac
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

  if [ "$PROTOCOL_CLI" -eq 0 ]; then
    choose_protocol_interactive
  fi

  msg ""
  if [ -z "$PORT" ] && [ -z "$PORT_RANGE" ]; then
    local default_port input=""
    default_port="$(random_port)"
    if [ "$PROTOCOL" = "BOTH" ] && [ "$default_port" -ge 65535 ]; then
      default_port=65534
    fi
    read_tty input "$(t "监听端口 [${default_port}]: " "Listen port [${default_port}]: ")" || input=""
    PORT="${input:-$default_port}"
    valid_port "$PORT" || die "$(t '非法端口' 'Invalid port')"
  elif [ -n "$PORT" ] && [ -n "$PORT_RANGE" ]; then
    die "$(t '不能同时指定端口与端口段' 'Cannot set both port and port range')"
  fi

  if [ "$PROTOCOL" = "BOTH" ] && [ -n "$PORT" ] && [ "$PORT" -ge 65535 ]; then
    die "$(t '双协议需要主端口 ≤65534（UDP 使用主端口+1）' \
      'Dual protocol needs main port ≤65534 (UDP uses main port + 1)')"
  fi
  msg ""
  t "已选协议: $(protocol_label)" "Selected protocol: $(protocol_label)"
}

load_config_from_mita() {
  local desc bin bindings
  bin="$(mita_bin)"
  desc="$("$bin" describe config 2>/dev/null || true)"
  [ -n "$desc" ] || die "$(t '无法读取服务端配置' 'Cannot read server config')"

  parse_user_from_describe "$desc" || true
  if [ -z "$USERNAME" ] || [ -z "$PASSWORD" ]; then
    load_credentials_fallback
  fi
  if [ -z "$USERNAME" ]; then
    die "$(t '配置中缺少用户名' 'Missing username in config')"
  fi
  if [ -z "$PASSWORD" ]; then
    die "$(t '密码已哈希存储，无法生成节点链接。请选「重新配置」设置新密码，或查看 /root/mieru_client_*.json' \
      'Password is hashed; cannot build share link. Use Reconfigure to set a new password, or check /root/mieru_client_*.json')"
  fi

  bindings="$(extract_bindings_from_describe "$desc")"
  PORT=""
  PORT_RANGE=""
  if [ -n "$bindings" ]; then
    local pp proto p has_tcp=0 has_udp=0 tcp_port=""
    while IFS= read -r pp; do
      [ -n "$pp" ] || continue
      proto="${pp%%|*}"
      p="${pp#*|}"
      case "$proto" in
        TCP)
          has_tcp=1
          if [[ "$p" =~ ^[0-9]+$ ]]; then
            tcp_port="$p"
          elif [[ "$p" == *-* ]]; then
            PORT_RANGE="$p"
          fi
          ;;
        UDP) has_udp=1 ;;
      esac
    done <<< "$bindings"
    [ -n "$tcp_port" ] && PORT="$tcp_port"
    if [ "$has_tcp" -gt 0 ] && [ "$has_udp" -gt 0 ]; then
      PROTOCOL="BOTH"
    elif [ "$has_udp" -gt 0 ]; then
      PROTOCOL="UDP"
    else
      PROTOCOL="TCP"
    fi
  fi
  load_install_state
}

parse_user_from_describe() {
  local desc="$1" line
  [ -n "$desc" ] || return 1
  if command -v python3 >/dev/null 2>&1; then
    line="$(printf '%s' "$desc" | python3 -c '
import json, sys
try:
    data = json.load(sys.stdin)
except Exception:
    sys.exit(1)
users = data.get("users") or []
if not users:
    sys.exit(1)
u = users[0]
name = u.get("name", "") or ""
pwd = u.get("password", "") or ""
print(f"{name}\t{pwd}")
' 2>/dev/null)" || return 1
    USERNAME="${line%%$'\t'*}"
    PASSWORD="${line#*$'\t'}"
    [ -n "$USERNAME" ] && return 0
    return 1
  fi
  USERNAME="$(printf '%s' "$desc" | sed -n 's/.*"name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n1)"
  PASSWORD="$(printf '%s' "$desc" | sed -n 's/.*"password"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n1)"
  [ -n "$USERNAME" ] && [ -n "$PASSWORD" ]
}

load_credentials_fallback() {
  load_install_state
  [ -n "$USERNAME" ] && [ -n "$PASSWORD" ] && return 0
  local f line
  if ! command -v python3 >/dev/null 2>&1; then
    return 1
  fi
  for f in /root/mieru_client_*.json /root/mieru_client_tcp_*.json /root/mieru_client_udp_*.json; do
    [ -f "$f" ] || continue
    line="$(python3 -c "
import json, sys
try:
    d = json.load(open(sys.argv[1]))
except Exception:
    sys.exit(1)
if 'profiles' in d:
    p = d['profiles'][0]
    u = p.get('user') or {}
    print(f\"{u.get('name','')}\t{u.get('password','')}\")
    sys.exit(0)
users = d.get('users') or []
if users:
    u = users[0]
    print(f\"{u.get('name','')}\t{u.get('password','')}\")
" "$f" 2>/dev/null)" || continue
    [ -z "$USERNAME" ] && USERNAME="${line%%$'\t'*}"
    [ -z "$PASSWORD" ] && PASSWORD="${line#*$'\t'}"
    [ -n "$USERNAME" ] && [ -n "$PASSWORD" ] && return 0
  done
  return 1
}

collect_reconfigure_interactive() {
  STAGE="重新配置"
  load_config_from_mita
  msg ""
  t '【当前配置】' '[Current config]'
  t "  用户名: ${USERNAME}" "  Username: ${USERNAME}"
  t "  密码:   ${PASSWORD}" "  Password: ${PASSWORD}"
  t "  协议:   $(protocol_label)" "  Protocol: $(protocol_label)"
  if [ -n "$PORT" ]; then
    t "  端口:   ${PORT}" "  Port:     ${PORT}"
  else
    t "  端口段: ${PORT_RANGE}" "  Port range: ${PORT_RANGE}"
  fi
  msg ""
  t '留空则保持当前值' 'Press Enter to keep current value'

  local input=""
  read_tty input "$(t "新用户名 [${USERNAME}]: " "New username [${USERNAME}]: ")" || input=""
  [ -n "$input" ] && USERNAME="$input"

  input=""
  read_tty input "$(t "新密码 [${PASSWORD}]: " "New password [${PASSWORD}]: ")" || input=""
  [ -n "$input" ] && PASSWORD="$input"

  if [ "$PROTOCOL_CLI" -eq 0 ]; then
    msg ""
    t '是否更改传输协议？' 'Change transport protocol?'
    t '  1) 保持当前' '  1) Keep current'
    t '  2) 重新选择' '  2) Choose again'
    input=""
    read_tty input "$(t '请选择 [1-2，默认 1]: ' 'Choose [1-2, default 1]: ')" || input="1"
    input="${input:-1}"
    if [ "$input" = "2" ]; then
      choose_protocol_interactive
    fi
  fi

  if [ -z "$PORT_RANGE" ]; then
    msg ""
    input=""
    read_tty input "$(t "新监听端口 [${PORT}]: " "New listen port [${PORT}]: ")" || input=""
    if [ -n "$input" ]; then
      PORT="$input"
      valid_port "$PORT" || die "$(t '非法端口' 'Invalid port')"
    fi
  fi

  if [ "$PROTOCOL" = "BOTH" ] && [ -n "$PORT" ] && [ "$PORT" -ge 65535 ]; then
    die "$(t '双协议需要主端口 ≤65534' 'Dual protocol needs main port ≤65534')"
  fi
  msg ""
  t "将应用协议: $(protocol_label)" "Will apply protocol: $(protocol_label)"
}

ensure_config_noninteractive() {
  STAGE="参数校验"
  [ -n "$PORT" ] && [ -n "$PORT_RANGE" ] && \
    die "$(t '--port 与 --port-range 不能同时使用' 'Cannot use --port and --port-range together')"
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
  if normalize_protocol "$PROTOCOL" >/dev/null 2>&1; then
    PROTOCOL="$(normalize_protocol "$PROTOCOL")"
  else
    PROTOCOL="TCP"
  fi
  if [ "$PROTOCOL" = "BOTH" ] && [ -n "$PORT" ] && [ "$PORT" -ge 65535 ]; then
    die "$(t '双协议需要主端口 ≤65534' 'Dual protocol needs main port ≤65534')"
  fi
}

write_server_config() {
  local cfg bindings="" proto pp
  cfg="$(mktemp_file .json)"
  while IFS= read -r pp; do
    proto="${pp%%|*}"
    local p="${pp#*|}"
    local binding
    if [ -n "$PORT" ]; then
      binding=$(cat <<EOB
    {
      "port": ${p},
      "protocol": "${proto}"
    }
EOB
)
    else
      binding=$(cat <<EOB
    {
      "portRange": "${p}",
      "protocol": "${proto}"
    }
EOB
)
    fi
    if [ -n "$bindings" ]; then
      bindings="${bindings},
${binding}"
    else
      bindings="${binding}"
    fi
  done < <(port_protocol_pairs)
  cat >"$cfg" <<EOF
{
  "portBindings": [
${bindings}
  ],
  "users": [
    {
      "name": "${USERNAME}",
      "password": "${PASSWORD}"
    }
  ],
  "loggingLevel": "INFO",
  "mtu": ${MTU}
}
EOF
  printf '%s' "$cfg"
}

mita_socket_paths() {
  printf '%s\n' /var/run/mita/mita.sock /run/mita/mita.sock /var/run/mita.sock
}

mita_log_tail() {
  local f
  for f in /var/log/mita.err /var/log/mita.log; do
    if [ -s "$f" ]; then
      warn "$(t "mita 日志 (${f}):" "mita log (${f}):")"
      tail -n 8 "$f" 2>/dev/null | while IFS= read -r line; do
        msg "  $line"
      done
    fi
  done
}

wait_mita_socket() {
  local timeout="${1:-45}" i=0 sock
  while [ "$i" -lt "$timeout" ]; do
    while IFS= read -r sock; do
      [ -S "$sock" ] 2>/dev/null && return 0
    done < <(mita_socket_paths)
    sleep 1
    i=$((i + 1))
  done
  return 1
}

ensure_mita_daemon() {
  local sm
  sm="$(service_manager)"
  case "$sm" in
    systemd)
      run systemctl enable mita 2>/dev/null || true
      run systemctl start mita 2>/dev/null || run systemctl restart mita 2>/dev/null || true
      ;;
    openrc)
      run rc-update add mita default 2>/dev/null || true
      openrc_mita_recover
      if ! openrc_mita_is_started; then
        mita_log_tail
      fi
      ;;
    *)
      run "$(mita_bin)" run >/dev/null 2>&1 &
      ;;
  esac
}

apply_config() {
  local cfg="$1"
  STAGE="应用配置"
  local bin attempt
  bin="$(mita_bin)"
  ensure_mita_daemon
  if ! wait_mita_socket 45; then
    warn "$(t 'mita 管理进程未就绪，正在重试 apply config...' \
      'mita management daemon not ready, retrying apply config...')"
    mita_log_tail
  fi
  for attempt in 1 2 3 4 5; do
    if "$bin" apply config "$cfg" 2>/dev/null; then
      rm -f "$cfg"
      return 0
    fi
    ensure_mita_daemon
    wait_mita_socket 10 || true
    sleep 2
  done
  "$bin" apply config "$cfg" || die "$(t '应用配置失败' 'Failed to apply config')"
  rm -f "$cfg"
}

collect_ports_from_mita() {
  local saved_protocol="" saved_port="" saved_port_range=""
  if [ -f "$MITA_STATE" ]; then
    # shellcheck disable=SC1090
    source "$MITA_STATE" 2>/dev/null || true
    saved_protocol="$PROTOCOL"
    saved_port="$PORT"
    saved_port_range="$PORT_RANGE"
  else
    PORT=""
    PORT_RANGE=""
    PROTOCOL="TCP"
  fi

  local desc bin
  bin="$(mita_bin)"
  desc="$("$bin" describe config 2>/dev/null || true)"
  if [ -z "$desc" ]; then
    if [ -n "$saved_protocol" ]; then
      PROTOCOL="$saved_protocol"
      PORT="$saved_port"
      PORT_RANGE="$saved_port_range"
    fi
    return 0
  fi

  PORT="$(printf '%s' "$desc" | sed -n 's/.*"port"[[:space:]]*:[[:space:]]*\([0-9][0-9]*\).*/\1/p' | head -n1)"
  PORT_RANGE="$(printf '%s' "$desc" | sed -n 's/.*"portRange"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n1)"
  local tcp_count udp_count
  tcp_count="$(printf '%s' "$desc" | grep -c '"protocol"[[:space:]]*:[[:space:]]*"TCP"' || true)"
  udp_count="$(printf '%s' "$desc" | grep -c '"protocol"[[:space:]]*:[[:space:]]*"UDP"' || true)"
  if [ -n "$saved_protocol" ]; then
    PROTOCOL="$saved_protocol"
  elif [ "$tcp_count" -gt 0 ] && [ "$udp_count" -gt 0 ]; then
    PROTOCOL="BOTH"
  elif [ "$udp_count" -gt 0 ]; then
    PROTOCOL="UDP"
  else
    PROTOCOL="TCP"
  fi
}

# 从 mita describe config 输出解析 portBindings，每行 proto|port_or_range
extract_bindings_from_describe() {
  local desc="$1"
  [ -n "$desc" ] || return 0
  if command -v python3 >/dev/null 2>&1; then
    printf '%s' "$desc" | python3 -c '
import json, sys
try:
    data = json.load(sys.stdin)
except Exception:
    sys.exit(0)
for binding in data.get("portBindings", []):
    proto = binding.get("protocol", "TCP")
    if "port" in binding:
        print(f"{proto}|{binding['port']}")
    elif binding.get("portRange"):
        print(f"{proto}|{binding['portRange']}")
' 2>/dev/null || true
    return 0
  fi
  local line proto p
  while IFS= read -r line; do
    proto="$(printf '%s' "$line" | sed -n 's/.*"protocol"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')"
    p="$(printf '%s' "$line" | sed -n 's/.*"port"[[:space:]]*:[[:space:]]*\([0-9][0-9]*\).*/\1/p')"
    [ -z "$p" ] && p="$(printf '%s' "$line" | sed -n 's/.*"portRange"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')"
    [ -n "$proto" ] && [ -n "$p" ] && printf '%s|%s\n' "$proto" "$p"
  done < <(printf '%s' "$desc" | grep -E '"port"|"portRange"|"protocol"')
}

close_firewall_for_bindings() {
  local bindings="$1"
  local fw="" pp proto p proto_lc
  [ -n "$bindings" ] || return 0

  if command -v ufw >/dev/null 2>&1 && ufw status 2>/dev/null | grep -q 'Status: active'; then
    fw=ufw
  elif command -v firewall-cmd >/dev/null 2>&1 && firewall-cmd --state >/dev/null 2>&1; then
    fw=firewalld
  elif command -v iptables >/dev/null 2>&1; then
    fw=iptables
  else
    return 0
  fi

  while IFS= read -r pp; do
    [ -n "$pp" ] || continue
    proto="${pp%%|*}"
    p="${pp#*|}"
    proto_lc="$(proto_lower "$proto")"
    case "$fw" in
      ufw) run ufw delete allow "$(ufw_rule_spec "$p" "$proto_lc")" 2>/dev/null || true ;;
      firewalld) run firewall-cmd --permanent --remove-port="${p}/${proto_lc}" 2>/dev/null || true ;;
      iptables) iptables_accept_port "$p" "$proto_lc" del ;;
    esac
  done <<< "$bindings"

  case "$fw" in
    firewalld) run firewall-cmd --reload 2>/dev/null || true ;;
    iptables) persist_iptables_rules ;;
  esac
}

ufw_rule_spec() {
  local p="$1"
  local proto="$2"
  if [[ "$p" == *-* ]]; then
    local start="${p%-*}"
    local end="${p#*-}"
    printf '%s:%s/%s' "$start" "$end" "$proto"
  else
    printf '%s/%s' "$p" "$proto"
  fi
}

iptables_accept_port() {
  local p="$1"
  local proto="$2"
  local action="${3:-add}"
  if [[ "$p" == *-* ]]; then
    local start end port
    start="${p%-*}"
    end="${p#*-}"
    port="$start"
    while [ "$port" -le "$end" ]; do
      if [ "$action" = add ]; then
        run iptables -C INPUT -p "$proto" --dport "$port" -j ACCEPT 2>/dev/null \
          || run iptables -I INPUT -p "$proto" --dport "$port" -j ACCEPT || true
      else
        run iptables -D INPUT -p "$proto" --dport "$port" -j ACCEPT 2>/dev/null || true
      fi
      port=$((port + 1))
    done
  else
    if [ "$action" = add ]; then
      run iptables -C INPUT -p "$proto" --dport "$p" -j ACCEPT 2>/dev/null \
        || run iptables -I INPUT -p "$proto" --dport "$p" -j ACCEPT || true
    else
      run iptables -D INPUT -p "$proto" --dport "$p" -j ACCEPT 2>/dev/null || true
    fi
  fi
}

persist_iptables_rules() {
  if [ -d /etc/iptables ] || [ -f /etc/alpine-release ]; then
    run mkdir -p /etc/iptables
    run iptables-save > /etc/iptables/rules.v4 2>/dev/null || true
  fi
}

open_firewall() {
  STAGE="配置防火墙"
  local pp proto p proto_lc fw=""
  if ! pp="$(port_protocol_pairs | head -n1)" || [ -z "$pp" ]; then
    return 0
  fi

  if command -v ufw >/dev/null 2>&1 && ufw status 2>/dev/null | grep -q 'Status: active'; then
    fw=ufw
  elif command -v firewall-cmd >/dev/null 2>&1 && firewall-cmd --state >/dev/null 2>&1; then
    fw=firewalld
  elif command -v iptables >/dev/null 2>&1; then
    fw=iptables
  else
    warn "$(t '未检测到本地防火墙工具，请仅在云安全组放行端口' \
      'No local firewall tool found; open ports in cloud security group')"
    return 0
  fi

  while IFS= read -r pp; do
    proto="${pp%%|*}"
    p="${pp#*|}"
    proto_lc="$(proto_lower "$proto")"
    case "$fw" in
      ufw) run ufw allow "$(ufw_rule_spec "$p" "$proto_lc")" || true ;;
      firewalld) run firewall-cmd --permanent --add-port="${p}/${proto_lc}" || true ;;
      iptables) iptables_accept_port "$p" "$proto_lc" add ;;
    esac
  done < <(port_protocol_pairs)

  case "$fw" in
    firewalld) run firewall-cmd --reload || true ;;
    iptables) persist_iptables_rules ;;
  esac
}

close_firewall() {
  STAGE="清理防火墙规则"
  local desc bindings bin
  bin="$(mita_bin)"
  desc="$("$bin" describe config 2>/dev/null || true)"
  bindings="$(extract_bindings_from_describe "$desc")"
  if [ -n "$bindings" ]; then
    close_firewall_for_bindings "$bindings"
    return 0
  fi
  collect_ports_from_mita
  local pp proto p proto_lc fw=""
  if ! pp="$(port_protocol_pairs | head -n1)" || [ -z "$pp" ]; then
    return 0
  fi

  if command -v ufw >/dev/null 2>&1 && ufw status 2>/dev/null | grep -q 'Status: active'; then
    fw=ufw
  elif command -v firewall-cmd >/dev/null 2>&1 && firewall-cmd --state >/dev/null 2>&1; then
    fw=firewalld
  elif command -v iptables >/dev/null 2>&1; then
    fw=iptables
  else
    return 0
  fi

  while IFS= read -r pp; do
    proto="${pp%%|*}"
    p="${pp#*|}"
    proto_lc="$(proto_lower "$proto")"
    case "$fw" in
      ufw) run ufw delete allow "$(ufw_rule_spec "$p" "$proto_lc")" 2>/dev/null || true ;;
      firewalld) run firewall-cmd --permanent --remove-port="${p}/${proto_lc}" 2>/dev/null || true ;;
      iptables) iptables_accept_port "$p" "$proto_lc" del ;;
    esac
  done < <(port_protocol_pairs)

  case "$fw" in
    firewalld) run firewall-cmd --reload 2>/dev/null || true ;;
    iptables) persist_iptables_rules ;;
  esac
}

cloud_firewall_hint() {
  local specs=() pp proto p
  while IFS= read -r pp; do
    proto="${pp%%|*}"
    p="${pp#*|}"
    specs+=("${p}/${proto}")
  done < <(port_protocol_pairs)
  [ "${#specs[@]}" -gt 0 ] || return 0
  local spec
  spec="$(IFS=','; printf '%s' "${specs[*]}")"
  msg ""
  t "【云安全组提醒】请在 VPS/云控制台安全组放行: ${spec}" \
    "[Cloud SG] Allow in provider firewall: ${spec}"
}

public_ip() {
  curl -fsSL --connect-timeout 5 --max-time 10 https://checkip.amazonaws.com 2>/dev/null \
    || curl -fsSL --connect-timeout 5 --max-time 10 https://api.ip.sb/ip 2>/dev/null \
    || hostname -I 2>/dev/null | awk '{print $1}'
}

start_mita() {
  STAGE="启动服务"
  local sm bin attempt
  sm="$(service_manager)"
  bin="$(mita_bin)"
  if wait_mita_socket 1; then
    "$bin" stop 2>/dev/null || true
    sleep 1
  fi
  ensure_mita_daemon
  if ! wait_mita_socket 45; then
    warn "$(t 'mita 管理套接字未就绪，继续尝试 start...' \
      'mita management socket not ready, retrying start...')"
    mita_log_tail
  fi
  for attempt in 1 2 3 4 5; do
    if "$bin" start 2>/dev/null; then
      sleep 1
      return 0
    fi
    ensure_mita_daemon
    wait_mita_socket 10 || true
    sleep 2
  done
  warn "$(t "mita start 未成功，请手动执行: $(mita_restart_hint) && mita start" \
    "mita start failed; run: $(mita_restart_hint) && mita start")"
}

verify_mita_running() {
  STAGE="验证服务状态"
  local bin status_out attempt
  bin="$(mita_bin)"
  for attempt in 1 2 3 4 5; do
    sleep 2
    status_out="$("$bin" status 2>/dev/null || true)"
    if printf '%s' "$status_out" | grep -q 'status is "RUNNING"'; then
      t 'mita 服务运行正常' 'mita service is running'
      return 0
    fi
    ensure_mita_daemon
    wait_mita_socket 10 || true
    "$bin" start 2>/dev/null || true
  done
  warn "$(t "mita 未处于 RUNNING 状态，请执行: $(mita_restart_hint) && mita status && mita start" \
    "mita is not RUNNING; run: $(mita_restart_hint) && mita status && mita start")"
  [ -n "$status_out" ] && msg "$status_out"
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
  if [ -f /etc/alpine-release ] && ! command -v python3 >/dev/null 2>&1; then
    run apk add --no-cache python3 2>/dev/null || true
  fi
  local url="https://raw.githubusercontent.com/${UPSTREAM_REPO}/refs/heads/main/tools/enable_tcp_bbr.py"
  local tmp
  tmp="$(mktemp_file .py)"
  curl -fsSL -o "$tmp" "$url"
  chmod +x "$tmp"
  if command -v python3 >/dev/null 2>&1; then
    run python3 "$tmp"
  else
    warn "$(t '未找到 python3，跳过 BBR 配置' 'python3 not found, skipping BBR')"
  fi
  rm -f "$tmp"
}

urlencode() {
  local value="$1"
  if command -v python3 >/dev/null 2>&1; then
    python3 -c 'import sys, urllib.parse; print(urllib.parse.quote(sys.argv[1], safe=""))' "$value"
    return 0
  fi
  if [[ "$value" =~ ^[a-zA-Z0-9._~-]+$ ]]; then
    printf '%s' "$value"
    return 0
  fi
  die "$(t '密码含特殊字符时需要 python3 以生成节点链接' \
    'python3 required to encode special characters in share link')"
}

generate_share_link_for() {
  local ip="$1"
  local proto="$2"
  local enc_user enc_pass p host query
  enc_user="$(urlencode "$USERNAME")"
  enc_pass="$(urlencode "$PASSWORD")"
  p="$(port_for_protocol "$proto")"
  query="handshake-mode=HANDSHAKE_STANDARD&mtu=${MTU}&multiplexing=${MULTIPLEXING}&port=${p}&profile=default&protocol=${proto}"
  if [ -n "$PORT" ]; then
    host="${ip}:${p}"
  else
    host="$ip"
  fi
  printf 'mierus://%s:%s@%s?%s' "$enc_user" "$enc_pass" "$host" "$query"
}

build_client_json_for() {
  local ip="$1"
  local proto="$2"
  local p binding
  p="$(port_for_protocol "$proto")"
  if [ -n "$PORT" ]; then
    binding=$(cat <<EOB
            {
              "port": ${p},
              "protocol": "${proto}"
            }
EOB
)
  else
    binding=$(cat <<EOB
            {
              "portRange": "${p}",
              "protocol": "${proto}"
            }
EOB
)
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
          "domainName": "",
          "portBindings": [
${binding}
          ]
        }
      ],
      "mtu": ${MTU},
      "multiplexing": {
        "level": "${MULTIPLEXING}"
      },
      "handshakeMode": "HANDSHAKE_STANDARD"
    }
  ],
  "activeProfile": "default",
  "rpcPort": ${CLIENT_RPC_PORT},
  "socks5Port": ${CLIENT_SOCKS5_PORT},
  "loggingLevel": "INFO",
  "socks5ListenLAN": false,
  "httpProxyPort": ${CLIENT_HTTP_PORT},
  "httpProxyListenLAN": false
}
EOF
}

build_clash_yaml_entry() {
  local ip="$1"
  local proto="$2"
  local p port_lines name_suffix
  p="$(port_for_protocol "$proto")"
  name_suffix="$(proto_lower "$proto")"
  if [ -n "$PORT" ]; then
    port_lines="    port: ${p}"
  else
    port_lines="    port-range: ${p}"
  fi
  cat <<EOF
  - name: mieru-mita-${name_suffix}
    type: mieru
    server: ${ip}
${port_lines}
    transport: ${proto}
    udp: true
    username: ${USERNAME}
    password: ${PASSWORD}
    multiplexing: ${MULTIPLEXING}
EOF
}

build_clash_yaml() {
  local ip="$1"
  local proto
  while IFS= read -r proto; do
    build_clash_yaml_entry "$ip" "$proto"
  done < <(protocols_for_mode)
}

build_clash_yaml_header() {
  printf '%s\n' 'proxies:'
}

build_clash_yaml_full() {
  local ip="$1"
  build_clash_yaml_header
  build_clash_yaml "$ip"
}

protocol_output_count() {
  local n=0 proto
  while IFS= read -r proto; do
    [ -n "$proto" ] || continue
    n=$((n + 1))
  done < <(protocols_for_mode)
  printf '%s' "$n"
}

print_protocol_outputs() {
  local ip="$1"
  local proto link cfg_path ts suffix multi=0 count
  ts="$(date +%Y%m%d_%H%M%S)"
  count="$(protocol_output_count)"
  if [ "$count" -gt 1 ]; then
    multi=1
  fi
  while IFS= read -r proto; do
    [ -n "$proto" ] || continue
    suffix="$(proto_lower "$proto")"
    msg ""
    if [ "$multi" -eq 1 ]; then
      t "【${proto} 节点链接】" "[${proto} share link]"
    else
      t '【节点链接】' '[Share link]'
    fi
    link="$(generate_share_link_for "$ip" "$proto")"
    msg "$link"
    if [ "$multi" -eq 1 ]; then
      cfg_path="/root/mieru_client_${suffix}_${ts}.json"
    else
      cfg_path="/root/mieru_client_${ts}.json"
    fi
    msg ""
    if [ "$multi" -eq 1 ]; then
      t "【${proto} 客户端 JSON】（供 mieru 客户端使用，勿在服务器 mita apply）" \
        "[${proto} client JSON] (for mieru client only — do NOT mita apply on server)"
    else
      t '【客户端 JSON 配置】（供 mieru 客户端使用，勿在服务器 mita apply）' \
        '[Client JSON] (for mieru client only — do NOT mita apply on server)'
    fi
    if [ "$DRY_RUN" -ne 1 ]; then
      build_client_json_for "$ip" "$proto" >"$cfg_path"
      t "  已保存: ${cfg_path}" "  Saved:  ${cfg_path}"
    fi
    msg ""
    build_client_json_for "$ip" "$proto"
  done < <(protocols_for_mode)
}

print_summary() {
  local ip
  ip="$(public_ip || true)"
  msg ""
  t '========== 安装完成 ==========' '========== Installation complete =========='
  if [ -n "$ip" ]; then
    print_protocol_outputs "$ip"
  else
    warn "$(t '未能获取公网 IP，请手动将下方连接信息填入客户端' \
      'Could not detect public IP; use connection info below manually')"
  fi
  msg ""
  t '【连接信息】' '[Connection info]'
  t "  服务器: ${ip:-<未知>}" "  Server:   ${ip:-<unknown>}"
  t "  用户名: ${USERNAME}" "  Username: ${USERNAME}"
  t "  密码:   ${PASSWORD}" "  Password: ${PASSWORD}"
  t "  协议:   $(protocol_label)" "  Protocol: $(protocol_label)"
  if [ -n "$PORT" ]; then
    if [ "$PROTOCOL" = "BOTH" ]; then
      t "  端口:   TCP ${PORT} / UDP $((PORT + 1))" "  Ports:    TCP ${PORT} / UDP $((PORT + 1))"
    else
      t "  端口:   ${PORT}" "  Port:     ${PORT}"
    fi
  else
    t "  端口段: ${PORT_RANGE}" "  Port range: ${PORT_RANGE}"
  fi
  msg ""
  t '导入方式:' 'Import options:'
  if [ "$PROTOCOL" = "BOTH" ]; then
    msg '  mieru import config "<TCP 节点链接>"   # 或分别导入 TCP / UDP 链接'
    msg '  mieru apply config /root/mieru_client_tcp_*.json'
    msg '  mieru apply config /root/mieru_client_udp_*.json'
  else
    msg '  mieru import config "<节点链接>"   # 简单链接不含 socks5Port，全新设备建议用 JSON'
    msg '  mieru apply config /root/mieru_client_*.json'
  fi
  if [ "$PROTOCOL" = "BOTH" ]; then
    msg ''
    t '【客户端提示】双协议已分开输出：TCP 与 UDP 各用对应链接/JSON；' \
      '[Client tip] Dual protocol outputs are split: use matching TCP or UDP link/JSON.'
    t '  v2rayN 导入后传输协议选 **tcp** 或 **udp**（勿选「两个都」）。' \
      '  In v2rayN pick transport **tcp** or **udp** (not "both").'
  fi
  if [ -n "$ip" ]; then
    msg ""
    t '【Clash / mihomo 配置片段】' '[Clash / mihomo snippet]'
    build_clash_yaml_full "$ip"
  fi
  cloud_firewall_hint
}

generate_client_config() {
  local ip
  ip="$(public_ip || echo 'YOUR_SERVER_IP')"
  msg ""
  t '========== 节点链接与客户端配置 ==========' \
    '========== Share links & client config =========='
  print_protocol_outputs "$ip"
  msg ""
  t '【导入方式】' '[How to import]'
  if [ "$PROTOCOL" = "BOTH" ]; then
    msg '  mieru import config "<TCP 节点链接>"   # TCP / UDP 各用对应链接'
    msg '  mieru apply config /root/mieru_client_tcp_*.json'
    msg '  mieru apply config /root/mieru_client_udp_*.json'
  else
    msg '  mieru import config "<节点链接>"   # 一键导入（简单链接）'
    msg '  mieru apply config /root/mieru_client_*.json   # 完整 JSON（含 socks5 端口）'
  fi
  msg ""
  t '说明: 上方 mierus:// 为分享链接；JSON 为 mieru **客户端**配置（在电脑/手机导入，勿在服务器 mita apply）' \
    'Note: mierus:// is the share link; JSON is for mieru **client** on your device — do NOT mita apply on server'
  msg ""
  t '【Clash / mihomo 配置片段】' '[Clash / mihomo snippet]'
  build_clash_yaml_full "$ip"
  cloud_firewall_hint
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
    t '如需改端口/密码/协议，请选菜单「重新配置」或执行: install-mita reconfigure' \
      'To change port/password/protocol, use menu Reconfigure or: install-mita reconfigure'
    if ! confirm '继续将重新下载安装包并覆盖配置？[y/N]: ' \
      'Continue full reinstall (re-download package)? [y/N]: ' n; then
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
  tmp="$(mktemp_file)"
  download_package "$url" "$tmp"
  install_package "$tmp" "$pm"
  rm -f "$tmp"
  ensure_mita_daemon
  wait_mita_socket 30 || true

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

do_reconfigure() {
  require_root
  require_linux
  mita_installed || die "$(t 'mita 未安装，请先执行安装' 'mita is not installed; run install first')"

  local old_bindings desc bin cfg
  bin="$(mita_bin)"
  desc="$("$bin" describe config 2>/dev/null || true)"
  old_bindings="$(extract_bindings_from_describe "$desc")"

  if [ "$YES" -eq 1 ]; then
    load_config_from_mita
    ensure_config_noninteractive
  else
    collect_reconfigure_interactive
  fi

  ensure_mita_daemon
  wait_mita_socket 30 || true
  close_firewall_for_bindings "$old_bindings"
  cfg="$(write_server_config)"
  apply_config "$cfg"
  open_firewall
  start_mita
  verify_mita_running
  save_install_state
  msg ""
  t '========== 重新配置完成 ==========' '========== Reconfigure complete =========='
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
  if version_is_current "$cur" "$ver"; then
    install_self_script
    t "管理脚本已更新至 v${SCRIPT_VERSION}（mita 二进制 ${cur} 已是最新）" \
      "Manager script updated to v${SCRIPT_VERSION} (mita binary ${cur} is already latest)"
    [ "${MENU_MODE:-0}" -eq 1 ] && return 0
    exit 0
  fi
  url="$(package_url "$ver" "$pm" "$arch")"
  tmp="$(mktemp_file)"
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
  run rm -f /root/mieru_client_*.json /root/mieru_client_tcp_*.json /root/mieru_client_udp_*.json 2>/dev/null || true
  run rm -rf /etc/mita /var/lib/mita /var/run/mita /var/run/mita.sock
  run rm -f "$MITA_BIN" "$MITA_REAL_BIN" /usr/bin/mita-real "$MITA_MARKER" "$OPENRC_SVC"
  if ! command -v dpkg >/dev/null 2>&1 || ! dpkg -l mita 2>/dev/null | grep -q '^ii'; then
    run rm -f /usr/bin/mita
  fi
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
  if ! installed_by_oneclick; then
    warn "$(t '未检测到本脚本安装标记；若仅使用官方 deb/rpm，卸载范围可能不同' \
      'OneClick install marker not found; official package uninstall may differ')"
    confirm '仍要继续卸载？[y/N]: ' 'Continue uninstall anyway? [y/N]: ' n || exit 0
  fi
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
  local bin sm status_out recovered=0
  bin="$(mita_bin)"
  sm="$(service_manager)"
  if ! mita_installed; then
    t 'mita 未安装' 'mita is not installed'
    exit 1
  fi
  msg ""
  "$bin" version 2>/dev/null || true
  msg ""
  case "$sm" in
    systemd) systemctl status mita --no-pager 2>/dev/null || true ;;
    openrc)
      openrc_mita_status_line
      if openrc_mita_is_crashed; then
        warn "$(t 'mita 处于 crashed 状态，正在自动恢复...' 'mita is crashed; auto-recovering...')"
        openrc_mita_recover
        recovered=1
        openrc_mita_status_line
      elif ! openrc_mita_is_started; then
        warn "$(t 'mita 未运行，正在尝试启动...' 'mita is not running; trying to start...')"
        openrc_mita_recover
        recovered=1
        openrc_mita_status_line
      fi
      ;;
    *) true ;;
  esac
  msg ""
  if ! wait_mita_socket 3; then
    if [ "$recovered" -eq 0 ]; then
      ensure_mita_daemon
    fi
    if ! wait_mita_socket 10; then
      warn "$(t "mita 守护进程未就绪，请执行: $(mita_restart_hint)" \
        "mita daemon not ready; run: $(mita_restart_hint)")"
      warn "$(t "查看日志: $(mita_log_hint)" "Check logs: $(mita_log_hint)")"
      mita_log_tail
    fi
  fi
  status_out="$("$bin" status 2>/dev/null || true)"
  if [ -n "$status_out" ]; then
    msg "$status_out"
  fi
  if printf '%s' "$status_out" | grep -qi 'daemon is not running'; then
    warn "$(t "请执行: $(mita_restart_hint)" "Run: $(mita_restart_hint)")"
    warn "$(t "查看日志: $(mita_log_hint)" "Check logs: $(mita_log_hint)")"
  fi
  msg ""
  "$bin" describe config 2>/dev/null || true
}

do_client_config() {
  require_root
  mita_installed || die "$(t 'mita 未安装' 'mita is not installed')"
  ensure_mita_daemon
  wait_mita_socket 20 || warn "$(t 'mita 守护进程未就绪，正在尝试继续...' 'mita daemon not ready, trying anyway...')"
  load_config_from_mita
  generate_client_config
}

menu_run_action() {
  local rc=0
  case "$ACTION" in
    install) do_install || rc=1 ;;
    reconfigure) do_reconfigure || rc=1 ;;
    upgrade) do_upgrade || rc=1 ;;
    uninstall) do_uninstall; return 2 ;;
    status) do_status || rc=1 ;;
    client-config) do_client_config || rc=1 ;;
    *) warn "$(t '未知操作' 'Unknown action')"; return 1 ;;
  esac
  return "$rc"
}

menu_loop() {
  MENU_MODE=1
  if mita_installed; then
    ensure_management_scripts
    MENU_SCRIPTS_READY=1
  fi
  while true; do
    ACTION=""
    show_menu
    local sm_rc=$?
    if [ "$sm_rc" -eq 2 ]; then
      break
    fi
    if [ "$sm_rc" -ne 0 ]; then
      continue
    fi
    if menu_run_action; then
      :
    else
      local rc=$?
      if [ "$rc" -eq 2 ]; then
        break
      fi
      warn "$(t '操作未完成，请重试或选 5) 状态 排查' 'Action failed; retry or use 5) Status')"
    fi
  done
}

show_menu() {
  if [ "${MENU_SCRIPTS_READY:-0}" -eq 0 ] && mita_installed; then
    ensure_management_scripts
    MENU_SCRIPTS_READY=1
  fi
  print_banner
  msg "  1) 新装安装"
  msg "  2) 重新配置（端口 / 密码 / 协议）"
  msg "  3) 升级"
  msg "  4) 卸载"
  msg "  5) 状态"
  msg "  6) 查看节点链接 / 客户端配置"
  msg "  7) 退出"
  msg ""
  t '快捷命令: 直接输入 mita 打开菜单（不区分大小写）' \
    'Quick command: type mita to open menu (case-insensitive)'
  msg ""
  local choice=""
  read_tty choice "$(t '请选择 [1-7]: ' 'Choose [1-7]: ')" || choice=""
  choice="$(printf '%s' "$choice" | tr -d '[:space:]')"
  if [ -z "$choice" ]; then
    warn "$(t '请输入 1-7' 'Enter 1-7')"
    return 1
  fi
  case "$choice" in
    1) ACTION=install ;;
    2) ACTION=reconfigure ;;
    3) ACTION=upgrade ;;
    4) ACTION=uninstall ;;
    5) ACTION=status ;;
    6) ACTION=client-config ;;
    7) return 2 ;;
    *)
      warn "$(t '无效选择，请输入 1-7' 'Invalid choice, enter 1-7')"
      return 1
      ;;
  esac
  return 0
}

main() {
  if [ -z "$ACTION" ]; then
    menu_loop
    exit 0
  fi
  if [ "$(id -u 2>/dev/null || echo 1)" -eq 0 ] && mita_installed; then
    repair_mita_binary_paths 2>/dev/null || true
  fi
  if [ "$ACTION" != "menu" ]; then
    print_banner
  fi
  case "$ACTION" in
    install) do_install ;;
    reconfigure) do_reconfigure ;;
    upgrade) do_upgrade ;;
    uninstall) do_uninstall ;;
    status) do_status ;;
    client-config|show) do_client_config ;;
    menu)
      menu_loop
      ;;
    *) usage; exit 1 ;;
  esac
}

main
