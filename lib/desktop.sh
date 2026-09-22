# shellcheck shell=bash
# ============================================================
# DESKTOP: XFCE4 + термінал
# ============================================================

start_xfce() {

    install_debian || return 1

    start_x11 || return 1

    start_pulse || true

    case "$(gpu_mode)" in
        turnip) install_freedreno || return 1 ;;
        virgl)  start_virgl || return 1 ;;
    esac

    write_profile || return 1

    rm -f "$XFCE_LOG"

    info "Starting XFCE4 with $(gpu_name)..."

    proot-distro login debian \
        --shared-tmp \
        -- \
        env \
        DISPLAY=:0 \
        XDG_RUNTIME_DIR=/tmp \
        PULSE_SERVER=127.0.0.1 \
        XKB_CONFIG_ROOT=/usr/share/X11/xkb \
        GPU_MODE_NAME="$(gpu_name)" \
        bash -s \
        >"$XFCE_LOG" 2>&1 <<'XFCE_SCRIPT' &

. /etc/profile.d/linux-manager-gpu.sh

# Zink+Turnip з увімкненим композитингом XFCE (xfwm4) дають чорний
# екран з самим лише курсором — відома проблема поєднання
# Zink/Turnip + compositing + XFCE на Termux:X11. Вимикаємо
# композитинг один раз при першому запуску; якщо потім увімкнеш
# його вручну в Window Manager Tweaks, цей запис більше не чіпається.
XFWM_CFG="$HOME/.config/xfce4/xfconf/xfce-perchannel-xml/xfwm4.xml"

if [ ! -f "$XFWM_CFG" ]; then

    mkdir -p "$(dirname "$XFWM_CFG")"

    cat > "$XFWM_CFG" <<'XFWM4'
<?xml version="1.0" encoding="UTF-8"?>

<channel name="xfwm4" version="1.0">
  <property name="general" type="empty">
    <property name="use_compositing" type="bool" value="false"/>
  </property>
</channel>
XFWM4

fi

printf 'DISPLAY=%s\n' "$DISPLAY"

printf 'XDG_RUNTIME_DIR=%s\n' "$XDG_RUNTIME_DIR"

printf 'GPU_MODE=%s\n' "$GPU_MODE_NAME"

echo "Checking X11..."

if ! command -v xdpyinfo >/dev/null 2>&1; then
    echo "ERROR: xdpyinfo is missing."
    exit 10
fi

if ! xdpyinfo >/dev/null 2>&1; then
    echo "ERROR: Cannot connect to DISPLAY=$DISPLAY"
    exit 11
fi

echo "X11 connection OK."

echo "Starting XFCE4..."

exec dbus-launch \
    --exit-with-session \
    xfce4-session

XFCE_SCRIPT

    local pid=$!

    sleep 4

    echo
    echo "========== XFCE START =========="

    cat "$XFCE_LOG" 2>/dev/null || true

    echo "================================="

    if kill -0 "$pid" >/dev/null 2>&1; then
        ok "XFCE4 process started."
    else
        bad "XFCE4 process stopped."
        echo
        echo "Full XFCE log:"
        cat "$XFCE_LOG" 2>/dev/null || true
        return 1
    fi
}

restart_xfce() {

    pkill -x xfce4-session \
        >/dev/null 2>&1 || true

    pkill -x xfdesktop \
        >/dev/null 2>&1 || true

    sleep 1

    start_xfce
}

start_terminal() {

    install_debian || return 1

    write_profile || return 1

    debian bash -s <<'TERMINAL'

. /etc/profile.d/linux-manager-gpu.sh

exec xfce4-terminal

TERMINAL
}
