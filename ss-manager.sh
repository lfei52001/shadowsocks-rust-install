#!/usr/bin/env bash
# shadowsocks-rust 一键管理脚本（安装/卸载/更新/退出）
# 适用于 Debian / Ubuntu x86_64 系统
# 最后更新检查时间: 2026年2月

set -e

# ==================== 配置区 ====================
CONFIG_DIR="/etc/shadowsocks-rust"
CONFIG_FILE="$CONFIG_DIR/config.json"
SERVICE_NAME="shadowsocks-rust"
DEFAULT_PORT=443
DEFAULT_METHOD="2022-blake3-aes-256-gcm"
# ===============================================

clear
echo ""
echo "========================================"
echo "  shadowsocks-rust 管理脚本 (x86_64)"
echo "  默认端口: $DEFAULT_PORT"
echo "========================================"
echo ""

# 检查是否 root
if [ "$EUID" -ne 0 ]; then
  echo "请使用 root 或 sudo 运行此脚本"
  exit 1
fi

# 检查架构
ARCH=$(uname -m)
if [ "$ARCH" != "x86_64" ]; then
  echo "本脚本仅支持 x86_64 (amd64) 系统"
  echo "当前架构: $ARCH"
  exit 1
fi

# ==================== 函数定义 ====================

function install_ss_rust() {
  echo ""
  echo "[安装 shadowsocks-rust]"

  # 选择加密方式
  echo ""
  echo "请选择加密方式（主流选项）："
  echo "  1. 2022-blake3-aes-256-gcm (推荐，高安全性)"
  echo "  2. 2022-blake3-aes-128-gcm (速度更快)"
  echo "  3. 2022-blake3-chacha20-poly1305 (兼容性好)"
  echo "  4. aes-256-gcm (主流经典)"
  echo "  5. chacha20-ietf-poly1305 (速度优先)"
  echo "  6. aes-128-gcm (极致速度)"
  echo "  其他: 输入自定义加密方式"
  echo -n "请输入选项 (1-6 或自定义): "
  read -r method_choice

  case $method_choice in
    1) METHOD="2022-blake3-aes-256-gcm" ;;
    2) METHOD="2022-blake3-aes-128-gcm" ;;
    3) METHOD="2022-blake3-chacha20-poly1305" ;;
    4) METHOD="aes-256-gcm" ;;
    5) METHOD="chacha20-ietf-poly1305" ;;
    6) METHOD="aes-128-gcm" ;;
    *)
      echo -n "请输入自定义加密方式 (e.g., aes-192-gcm): "
      read -r METHOD
      if [ -z "$METHOD" ]; then
        echo "错误：加密方式不能为空，使用默认 $DEFAULT_METHOD"
        METHOD=$DEFAULT_METHOD
      fi
      ;;
  esac

  echo "选定的加密方式: $METHOD"

  # 让用户输入端口
  echo -n "请输入监听端口 (推荐 443，范围 1025-65535，默认 $DEFAULT_PORT): "
  read -r INPUT_PORT

  if [ -z "$INPUT_PORT" ]; then
    PORT=$DEFAULT_PORT
  else
    if ! [[ "$INPUT_PORT" =~ ^[0-9]+$ ]] || [ "$INPUT_PORT" -lt 1025 ] || [ "$INPUT_PORT" -gt 65535 ]; then
      echo "错误：端口必须是 1025-65535 之间的数字"
      return 1
    fi
    PORT=$INPUT_PORT
  fi

  # 安装工具
  apt update -qq
  apt install -y wget tar xz-utils openssl >/dev/null 2>&1

  # 获取最新版本
  echo "获取最新版本号..."
  LATEST_TAG=$(wget -qO- "https://api.github.com/repos/shadowsocks/shadowsocks-rust/releases/latest" | grep '"tag_name":' | sed -E 's/.*"tag_name": "([^"]+)".*/\1/')

  if [ -z "$LATEST_TAG" ]; then
    echo "无法获取最新版本，使用默认 v1.24.0"
    LATEST_TAG="v1.24.0"
  else
    echo "最新版本: $LATEST_TAG"
  fi

  FILE_NAME="shadowsocks-${LATEST_TAG}.x86_64-unknown-linux-musl.tar.xz"
  DOWNLOAD_URL="https://github.com/shadowsocks/shadowsocks-rust/releases/download/${LATEST_TAG}/${FILE_NAME}"

  echo "下载: $DOWNLOAD_URL"
  cd /tmp
  rm -f shadowsocks-*.tar.xz 2>/dev/null
  wget -O "$FILE_NAME" "$DOWNLOAD_URL"

  echo "解压并安装..."
  tar -xvf "$FILE_NAME"
  sudo mv ssserver sslocal ssmanager ssservice ssurl /usr/local/bin/ 2>/dev/null || true
  sudo chmod +x /usr/local/bin/ssserver /usr/local/bin/sslocal /usr/local/bin/ssmanager /usr/local/bin/ssservice /usr/local/bin/ssurl

  rm -f "$FILE_NAME" ssserver sslocal ssmanager ssservice ssurl *.tar.xz 2>/dev/null

  # 生成密码 & 配置
  mkdir -p "$CONFIG_DIR"
  chmod 700 "$CONFIG_DIR"
  PASSWORD=$(openssl rand -base64 32)

  cat > "$CONFIG_FILE" << EOF
{
  "server": "0.0.0.0",
  "server_port": $PORT,
  "password": "$PASSWORD",
  "method": "$METHOD",
  "mode": "tcp_and_udp",
  "fast_open": true,
  "timeout": 300
}
EOF
  chmod 600 "$CONFIG_FILE"

  # systemd 服务
  cat > "/etc/systemd/system/${SERVICE_NAME}.service" << EOF
[Unit]
Description=Shadowsocks Rust Server
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/ssserver -c $CONFIG_FILE
Restart=always
RestartSec=5
LimitNOFILE=65535
User=root

[Install]
WantedBy=multi-user.target
EOF

  systemctl daemon-reload
  systemctl enable "$SERVICE_NAME" >/dev/null 2>&1
  systemctl restart "$SERVICE_NAME"

  sleep 3

  clear
  echo ""
  echo "安装完成！"
  echo ""
  systemctl is-active --quiet "$SERVICE_NAME" && echo "服务状态：运行中 ✓" || echo "服务启动失败，请检查 journalctl -u $SERVICE_NAME -e"
  echo ""
  echo "连接信息："
  echo "  服务器：你的 VPS IP 或域名"
  echo "  端口：$PORT"
  echo "  密码：$PASSWORD"
  echo "  加密：$METHOD"
  echo ""
  echo "配置文件：$CONFIG_FILE"
  echo "防火墙建议：ufw allow $PORT/tcp && ufw allow $PORT/udp"
  echo ""
}

function uninstall_ss_rust() {
  echo ""
  echo "[卸载 shadowsocks-rust]"
  echo "这将停止服务、删除二进制、配置文件和服务文件。"
  echo -n "确认卸载？(y/N): "
  read -r confirm
  if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
    echo "已取消"
    return 0
  fi

  systemctl stop "$SERVICE_NAME" 2>/dev/null || true
  systemctl disable "$SERVICE_NAME" 2>/dev/null || true

  rm -f /etc/systemd/system/${SERVICE_NAME}.service
  systemctl daemon-reload
  systemctl reset-failed 2>/dev/null || true

  rm -f /usr/local/bin/ssserver /usr/local/bin/sslocal /usr/local/bin/ssmanager /usr/local/bin/ssservice /usr/local/bin/ssurl

  rm -rf "$CONFIG_DIR"

  pkill -f ssserver 2>/dev/null || true

  echo ""
  echo "卸载完成。"
  echo "已删除的服务、配置文件和二进制文件。"
  echo "如需彻底清理日志，可运行：journalctl --vacuum-time=2weeks"
  echo ""
}

function update_ss_rust() {
  echo ""
  echo "[更新 shadowsocks-rust 到最新版本]"

  if [ ! -f /usr/local/bin/ssserver ]; then
    echo "未检测到已安装的 shadowsocks-rust，无法更新。"
    echo "请先运行安装功能。"
    return 1
  fi

  echo "获取最新版本号..."
  LATEST_TAG=$(wget -qO- "https://api.github.com/repos/shadowsocks/shadowsocks-rust/releases/latest" | grep '"tag_name":' | sed -E 's/.*"tag_name": "([^"]+)".*/\1/')

  if [ -z "$LATEST_TAG" ]; then
    echo "无法获取最新版本，跳过更新。"
    return 1
  fi

  echo "最新版本: $LATEST_TAG"

  FILE_NAME="shadowsocks-${LATEST_TAG}.x86_64-unknown-linux-musl.tar.xz"
  DOWNLOAD_URL="https://github.com/shadowsocks/shadowsocks-rust/releases/download/${LATEST_TAG}/${FILE_NAME}"

  cd /tmp
  rm -f shadowsocks-*.tar.xz 2>/dev/null
  wget -O "$FILE_NAME" "$DOWNLOAD_URL"

  echo "解压并替换二进制..."
  tar -xvf "$FILE_NAME"
  sudo mv ssserver sslocal ssmanager ssservice ssurl /usr/local/bin/ 2>/dev/null || true
  sudo chmod +x /usr/local/bin/ssserver /usr/local/bin/sslocal /usr/local/bin/ssmanager /usr/local/bin/ssservice /usr/local/bin/ssurl

  rm -f "$FILE_NAME" ssserver sslocal ssmanager ssservice ssurl *.tar.xz 2>/dev/null

  systemctl restart "$SERVICE_NAME" 2>/dev/null || true

  echo ""
  echo "更新完成！已替换为 $LATEST_TAG 版本。"
  echo "服务已重启（如果之前在运行）。"
  echo ""
}

# ==================== 主菜单 ====================

while true; do
  clear
  echo ""
  echo "========================================"
  echo "  shadowsocks-rust 管理菜单"
  echo "========================================"
  echo "  1. 安装 shadowsocks-rust"
  echo "  2. 卸载 shadowsocks-rust"
  echo "  3. 更新到最新版本"
  echo "  4. 退出"
  echo ""
  echo -n "请输入选项 (1-4): "
  read -r choice

  case $choice in
    1)
      install_ss_rust
      ;;
    2)
      uninstall_ss_rust
      ;;
    3)
      update_ss_rust
      ;;
    4)
      echo ""
      echo "已退出脚本。"
      exit 0
      ;;
    *)
      echo "无效选项，请输入 1-4"
      sleep 2
      ;;
  esac

  echo ""
  echo "按 Enter 键返回主菜单..."
  read -r dummy
done
