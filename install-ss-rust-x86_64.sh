#!/usr/bin/env bash
# 一键手动安装最新版 shadowsocks-rust (仅限 x86_64 系统)
# 适用于 Debian / Ubuntu amd64 / x86_64 系统
# 特点：端口手动输入、自动生成 32 字节强随机密码
# 使用方法: wget -O install-ss-rust.sh https://... && chmod +x install-ss-rust.sh && sudo ./install-ss-rust.sh

set -e

# ==================== 配置区 ====================
CONFIG_DIR="/etc/shadowsocks-rust"
CONFIG_FILE="$CONFIG_DIR/config.json"
SERVICE_NAME="shadowsocks-rust"
DEFAULT_PORT=443
METHOD="2022-blake3-aes-256-gcm"   # 可自行修改为 2022-blake3-chacha20-poly1305 等
# ===============================================

clear
echo ""
echo "========================================"
echo "  shadowsocks-rust 一键安装脚本"
echo "  仅支持 x86_64 (amd64) 系统"
echo "  加密方式: $METHOD"
echo "  端口: 将由你手动输入（默认 $DEFAULT_PORT）"
echo "========================================"
echo ""

# 检查权限
if [ "$EUID" -ne 0 ]; then
  echo "请使用 root 或 sudo 运行此脚本"
  exit 1
fi

# 检查架构（只允许 x86_64）
ARCH=$(uname -m)
if [ "$ARCH" != "x86_64" ]; then
  echo "本脚本仅支持 x86_64 (amd64) 系统"
  echo "当前检测到架构: $ARCH"
  echo "如需 arm64/aarch64 支持，请使用其他版本"
  exit 1
fi

# 1. 让用户输入端口
echo -n "请输入监听端口 (推荐 443，范围 1025-65535，默认 $DEFAULT_PORT): "
read -r INPUT_PORT

if [ -z "$INPUT_PORT" ]; then
  PORT=$DEFAULT_PORT
else
  if ! [[ "$INPUT_PORT" =~ ^[0-9]+$ ]] || [ "$INPUT_PORT" -lt 1025 ] || [ "$INPUT_PORT" -gt 65535 ]; then
    echo "错误：端口必须是 1025-65535 之间的数字"
    exit 1
  fi
  PORT=$INPUT_PORT
fi

# 2. 安装必要工具
echo ""
echo "[1/6] 安装 wget、tar、xz-utils、openssl ..."
apt update -qq
apt install -y wget tar xz-utils openssl >/dev/null 2>&1

# 3. 获取最新版本号
echo "[2/6] 获取最新 shadowsocks-rust 版本号..."
LATEST_TAG=$(wget -qO- "https://api.github.com/repos/shadowsocks/shadowsocks-rust/releases/latest" | grep '"tag_name":' | sed -E 's/.*"tag_name": "([^"]+)".*/\1/')

if [ -z "$LATEST_TAG" ]; then
  echo "无法获取最新版本，使用默认 v1.24.0"
  LATEST_TAG="v1.24.0"
else
  echo "检测到最新版本: $LATEST_TAG"
fi

# 4. 下载二进制（仅 x86_64-musl 静态版）
FILE_NAME="shadowsocks-${LATEST_TAG}.x86_64-unknown-linux-musl.tar.xz"
DOWNLOAD_URL="https://github.com/shadowsocks/shadowsocks-rust/releases/download/${LATEST_TAG}/${FILE_NAME}"

echo "[3/6] 下载: $DOWNLOAD_URL"
cd /tmp
rm -f shadowsocks-*.tar.xz 2>/dev/null
wget -O "$FILE_NAME" "$DOWNLOAD_URL"

# 5. 解压并安装
echo "[4/6] 解压并安装二进制文件..."
tar -xvf "$FILE_NAME"
sudo mv ssserver sslocal ssmanager ssservice ssurl /usr/local/bin/ 2>/dev/null || true
sudo chmod +x /usr/local/bin/ssserver /usr/local/bin/sslocal /usr/local/bin/ssmanager /usr/local/bin/ssservice /usr/local/bin/ssurl

# 清理
rm -f "$FILE_NAME" ssserver sslocal ssmanager ssservice ssurl *.tar.xz 2>/dev/null

# 6. 生成强密码并创建配置文件
echo "[5/6] 生成强随机密码并创建配置文件..."

mkdir -p "$CONFIG_DIR"
chmod 700 "$CONFIG_DIR"

# 生成 32 字节 Base64 密码
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

# 7. 创建 systemd 服务
echo "[6/6] 创建并启动 systemd 服务..."

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

# 最终输出
clear
echo ""
echo "========================================"
echo "  安装完成！"
echo "========================================"
echo ""

if systemctl is-active --quiet "$SERVICE_NAME"; then
  echo "服务状态：运行中 ✓"
else
  echo "服务启动失败！请检查日志："
  echo "  journalctl -u $SERVICE_NAME -e"
fi

echo ""
echo "连接信息（请复制保存）："
echo "  服务器地址：你的 VPS IP 或域名"
echo "  端口：$PORT"
echo "  密码：$PASSWORD"
echo "  加密方式：$METHOD"
echo ""
echo "配置文件位置：$CONFIG_FILE"
echo ""
echo "防火墙放行命令（ufw 示例）："
echo "  sudo ufw allow $PORT/tcp"
echo "  sudo ufw allow $PORT/udp"
echo "  sudo ufw reload"
echo ""
echo "查看服务日志："
echo "  journalctl -u $SERVICE_NAME -f"
echo ""
echo "祝使用愉快！"
echo ""