#!/bin/sh
# Alpine Linux frps 一键安装脚本 (基于 v0.65.0)

set -e

# ========== 配置变量 ==========
FRP_VERSION="0.65.0"
INSTALL_DIR="/usr/local/frp"
CONFIG_FILE="${INSTALL_DIR}/frps.toml"
SERVICE_NAME="frps"
INIT_SCRIPT="/etc/init.d/${SERVICE_NAME}"

# ========== 检测系统架构 ==========
ARCH=$(uname -m)
case "$ARCH" in
    x86_64)  ARCH="amd64" ;;
    aarch64) ARCH="arm64" ;;
    armv7l)  ARCH="arm" ;;
    *)       echo "不支持的架构: $ARCH"; exit 1 ;;
esac

# ========== 安装依赖 ==========
apk add --no-cache wget tar

# ========== 下载并解压 ==========
cd /tmp
DOWNLOAD_URL="https://github.com/fatedier/frp/releases/download/v${FRP_VERSION}/frp_${FRP_VERSION}_linux_${ARCH}.tar.gz"
echo "正在下载 $DOWNLOAD_URL ..."
wget -q "$DOWNLOAD_URL" -O frp.tar.gz
tar -xzf frp.tar.gz
cd "frp_${FRP_VERSION}_linux_${ARCH}"

# ========== 安装 frps ==========
mkdir -p "$INSTALL_DIR"
mv frps "$INSTALL_DIR/"
chmod +x "$INSTALL_DIR/frps"

# ========== 创建配置文件 ==========
cat > "$CONFIG_FILE" <<EOF
bindPort = 8500
auth.token = "1234567890"
EOF

# ========== 创建 OpenRC 服务 ==========
cat > "$INIT_SCRIPT" <<EOF
#!/sbin/openrc-run

name="frps"
description="frp reverse proxy server"
pidfile="/var/run/\${RC_SVCNAME}.pid"
command="${INSTALL_DIR}/frps"
command_args="-c ${CONFIG_FILE}"

depend() {
    need net
    want localmount
    after firewall
}

start() {
    ebegin "Starting \$name"
    start-stop-daemon \\
        --start \\
        --pidfile "\$pidfile" \\
        --exec "\$command" \\
        --background \\
        --make-pidfile \\
        -- \$command_args
    eend \$?
}

stop() {
    ebegin "Stopping \$name"
    start-stop-daemon \\
        --stop \\
        --pidfile "\$pidfile" \\
        --retry 30/TERM/5/KILL
    eend \$?
}

status() {
    status_of_proc -p "\$pidfile" "\$command" "\$name"
}
EOF

# ========== 设置权限并启用服务 ==========
chmod +x "$INIT_SCRIPT"
rc-update add "$SERVICE_NAME" default

# ========== 启动服务 ==========
rc-service "$SERVICE_NAME" start

# ========== 清理临时文件 ==========
cd /tmp
rm -rf "frp_${FRP_VERSION}_linux_${ARCH}" frp.tar.gz

echo ""
echo "========================================="
echo "frps 安装完成！"
echo "安装目录: $INSTALL_DIR"
echo "配置文件: $CONFIG_FILE"
echo ""
echo "请修改配置文件中的 token 和端口后重启服务："
echo "  vi $CONFIG_FILE"
echo "  rc-service $SERVICE_NAME restart"
echo "========================================="
