#!/bin/sh
ARCH=$(uname -m)
case "$ARCH" in
    x86_64) ARCH="amd64" ;;
    aarch64) ARCH="arm64" ;;
    armv7l) ARCH="armv7" ;;
    *) echo "Unsupported arch: $ARCH"; exit 1 ;;
esac

VER=$(wget -qO- --timeout=5 https://api.github.com/repos/fatedier/frp/releases/latest | grep '"tag_name"' | head -1 | sed -E 's/.*"([^"]+)".*/\1/')
[ -z "$VER" ] && VER="v0.58.0"
VER_NO=${VER#v}
URL="https://github.com/fatedier/frp/releases/download/${VER}/frp_${VER_NO}_linux_${ARCH}.tar.gz"

TMP=$(mktemp -d)
INSTALL="/opt/frp"
CONF="/etc/frp/frps.ini"

apk add --no-cache wget tar

adduser -D -h /var/lib/frp -s /sbin/nologin frp 2>/dev/null || true

cd "$TMP"
wget -q "$URL" -O frp.tar.gz
tar -xzf frp.tar.gz
EXTRACT=$(find "$TMP" -maxdepth 1 -type d -name "frp_*" | head -1)
mkdir -p "$INSTALL" "$(dirname "$CONF")"
cp -f "$EXTRACT/frps" "$INSTALL/frps"
chmod +x "$INSTALL/frps"

if [ ! -f "$CONF" ]; then
    cat > "$CONF" <<EOF
[common]
bind_port = 8500
bind_addr = 0.0.0.0
token = 1234567890
EOF
fi

chown -R frp:frp "$INSTALL" "$(dirname "$CONF")"
chmod 750 "$(dirname "$CONF")"
chmod 640 "$CONF"

cat > /etc/init.d/frps <<EOF
#!/sbin/openrc-run
name="frps"
command="$INSTALL/frps"
command_args="-c $CONF"
command_user="frp"
pidfile="/run/\${RC_SVCNAME}.pid"
command_background=true
depend() { need net; }
EOF
chmod +x /etc/init.d/frps

rc-update add frps default 2>/dev/null || true
rc-service frps start

rm -rf "$TMP"
