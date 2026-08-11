#!/bin/sh
# Alpine Linux 一键搭建 frps 脚本
# 需要 root 权限运行

set -e

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

# 默认配置
FRP_VERSION=""                     # 留空则自动获取最新版
INSTALL_DIR="/opt/frp"
CONFIG_DIR="/etc/frp"
SERVICE_NAME="frps"
FRPS_USER="frp"                    # 运行用户（非特权）
FRPS_BIN="${INSTALL_DIR}/frps"
FRPS_CONFIG="${CONFIG_DIR}/frps.ini"
INIT_SCRIPT="/etc/init.d/${SERVICE_NAME}"

# 检查 root 权限
if [ "$(id -u)" -ne 0 ]; then
    echo -e "${RED}错误：此脚本需要 root 权限运行，请使用 sudo 执行。${NC}"
    exit 1
fi

# 检测系统架构
detect_arch() {
    local arch
    arch=$(uname -m)
    case "$arch" in
        x86_64)  echo "amd64" ;;
        aarch64) echo "arm64" ;;
        armv7l)  echo "armv7" ;;
        armhf)   echo "armv7" ;;
        *)       echo "unsupported" ;;
    esac
}

ARCH=$(detect_arch)
if [ "$ARCH" = "unsupported" ]; then
    echo -e "${RED}不支持的架构: $(uname -m)${NC}"
    exit 1
fi

# 获取最新版本号（如果未指定）
get_latest_version() {
    if [ -n "$FRP_VERSION" ]; then
        echo "$FRP_VERSION"
        return
    fi
    echo -e "${YELLOW}正在获取最新 frp 版本...${NC}"
    # 使用 GitHub API，超时 5 秒
    local ver
    ver=$(wget -qO- --timeout=5 "https://api.github.com/repos/fatedier/frp/releases/latest" \
        | grep '"tag_name"' | head -1 | sed -E 's/.*"([^"]+)".*/\1/')
    if [ -z "$ver" ]; then
        echo -e "${YELLOW}无法获取最新版本，使用默认 v0.58.0${NC}"
        ver="v0.58.0"
    fi
    echo "$ver"
}

FRP_VERSION=$(get_latest_version)
FRP_VERSION_NO_V=${FRP_VERSION#v}
DOWNLOAD_URL="https://github.com/fatedier/frp/releases/download/${FRP_VERSION}/frp_${FRP_VERSION_NO_V}_linux_${ARCH}.tar.gz"
TEMP_DIR=$(mktemp -d)

echo -e "${GREEN}开始搭建 frps (版本: ${FRP_VERSION})${NC}"
echo -e "目标架构: ${ARCH}"
echo -e "下载地址: ${DOWNLOAD_URL}"

# 安装必要工具
echo -e "${YELLOW}安装依赖包...${NC}"
apk add --no-cache wget tar

# 创建运行用户
if ! id "$FRPS_USER" >/dev/null 2>&1; then
    echo -e "${YELLOW}创建用户 ${FRPS_USER}...${NC}"
    adduser -D -h /var/lib/frp -s /sbin/nologin "$FRPS_USER"
fi

# 下载并解压
echo -e "${YELLOW}下载 frp 压缩包...${NC}"
cd "$TEMP_DIR"
if ! wget -q --show-progress "$DOWNLOAD_URL" -O frp.tar.gz; then
    echo -e "${RED}下载失败，请检查网络或版本号。${NC}"
    rm -rf "$TEMP_DIR"
    exit 1
fi

echo -e "${YELLOW}解压到 ${INSTALL_DIR}...${NC}"
mkdir -p "$INSTALL_DIR"
tar -xzf frp.tar.gz -C "$TEMP_DIR"
# 解压后的目录名：frp_${FRP_VERSION_NO_V}_linux_${ARCH}
EXTRACT_DIR=$(find "$TEMP_DIR" -maxdepth 1 -type d -name "frp_*" | head -1)
if [ -z "$EXTRACT_DIR" ]; then
    echo -e "${RED}找不到解压目录。${NC}"
    rm -rf "$TEMP_DIR"
    exit 1
fi

# 复制 frps 和 frps.ini 示例（如果有）
cp -f "${EXTRACT_DIR}/frps" "$FRPS_BIN"
chmod +x "$FRPS_BIN"
# 复制示例配置文件（可选）
if [ -f "${EXTRACT_DIR}/frps.toml" ]; then
    cp -f "${EXTRACT_DIR}/frps.toml" "${CONFIG_DIR}/frps.toml.example"
fi
if [ -f "${EXTRACT_DIR}/frps.ini" ]; then
    cp -f "${EXTRACT_DIR}/frps.ini" "${CONFIG_DIR}/frps.ini.example"
fi

# 清理临时文件
rm -rf "$TEMP_DIR"

# 创建配置文件目录
mkdir -p "$CONFIG_DIR"

# 生成默认配置文件（如果不存在）
if [ ! -f "$FRPS_CONFIG" ]; then
    echo -e "${YELLOW}生成默认配置文件 ${FRPS_CONFIG}...${NC}"
    cat > "$FRPS_CONFIG" <<EOF
# frps 基础配置（INI 格式）
[common]
bind_port = 8500
bind_addr = 0.0.0.0
token = 1234567890

# 面板配置（可选）
# dashboard_port = 7500
# dashboard_user = admin
# dashboard_pwd = admin

# 日志
# log_file = /var/log/frps.log
# log_level = info
# log_max_days = 3
EOF
else
    echo -e "${YELLOW}配置文件已存在，跳过生成。${NC}"
fi

# 设置文件所有权
chown -R "$FRPS_USER":"$FRPS_USER" "$INSTALL_DIR" "$CONFIG_DIR"
# 配置文件可能包含敏感信息，只允许 root 和 frp 用户读写
chmod 750 "$CONFIG_DIR"
chmod 640 "$FRPS_CONFIG"

# 创建 OpenRC 服务脚本
echo -e "${YELLOW}创建 OpenRC 服务脚本 ${INIT_SCRIPT}...${NC}"
cat > "$INIT_SCRIPT" <<EOF
#!/sbin/openrc-run

name="frps"
description="FRP Server"
command="${FRPS_BIN}"
command_args="-c ${FRPS_CONFIG}"
command_user="${FRPS_USER}"
pidfile="/run/\${RC_SVCNAME}.pid"
command_background=true

depend() {
    need net
}

# 可选：使用 start-stop-daemon 的额外参数
start_pre() {
    # 确保 pidfile 目录存在
    mkdir -p /run
    chown "${FRPS_USER}:${FRPS_USER}" /run
}
EOF

chmod +x "$INIT_SCRIPT"

# 添加到开机启动（如果尚未添加）
if ! rc-update show | grep -q "$SERVICE_NAME"; then
    echo -e "${YELLOW}添加 ${SERVICE_NAME} 到默认运行级别...${NC}"
    rc-update add "$SERVICE_NAME" default
fi

# 启动服务
echo -e "${YELLOW}启动 ${SERVICE_NAME} 服务...${NC}"
rc-service "$SERVICE_NAME" start || echo -e "${RED}启动失败，请检查配置文件。${NC}"

# 输出完成信息
echo -e "${GREEN}================================================${NC}"
echo -e "${GREEN}frps 搭建完成！${NC}"
echo -e "安装目录: ${INSTALL_DIR}"
echo -e "配置文件: ${FRPS_CONFIG}"
echo -e "服务名称: ${SERVICE_NAME}"
echo -e "服务状态: rc-service ${SERVICE_NAME} status"
echo -e "启动/停止: rc-service ${SERVICE_NAME} start/stop"
echo -e "开机自启: rc-update show | grep ${SERVICE_NAME}"
echo -e "${YELLOW}请根据需要修改 ${FRPS_CONFIG} 后重启服务。${NC}"
echo -e "${GREEN}================================================${NC}"