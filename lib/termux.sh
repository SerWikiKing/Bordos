# shellcheck shell=bash
# ============================================================
# TERMUX: пакети, Termux:X11, PulseAudio
# ============================================================

install_termux() {
    info "Updating Termux..."

    pkg update -y || return 1

    info "Installing required Termux packages..."

    pkg install -y \
        proot-distro \
        termux-x11-nightly \
        pulseaudio \
        curl \
        unzip \
        || return 1

    # Termux-частина GPU (mesa, vulkan) живе в gpu.sh
    gpu_install_termux_pkgs || return 1

    ok "Termux packages are ready."
}

# ------------------------------------------------------------
# Termux:X11
# ------------------------------------------------------------

start_x11() {
    if ! have termux-x11; then
        pkg install -y termux-x11-nightly || return 1
    fi

    info "Starting Termux:X11..."

    XDG_RUNTIME_DIR="$TMPDIR" \
        termux-x11 :0 \
        >/dev/null 2>&1 &

    sleep 2

    info "Opening Termux:X11 Android window..."

    am start \
        --user 0 \
        -n com.termux.x11/com.termux.x11.MainActivity \
        >/dev/null 2>&1 || true

    sleep 2

    ok "Termux:X11 window opened."
}

# ------------------------------------------------------------
# PulseAudio
# ------------------------------------------------------------

start_pulse() {
    if ! have pulseaudio; then
        pkg install -y pulseaudio || return 1
    fi

    pulseaudio --kill \
        >/dev/null 2>&1 || true

    sleep 1

    pulseaudio \
        --start \
        --exit-idle-time=-1 \
        --load="module-native-protocol-tcp auth-ip-acl=127.0.0.1 auth-anonymous=1" \
        >/dev/null 2>&1 || true

    ok "PulseAudio started."
}
