# shellcheck shell=bash
# ============================================================
# TERMUX: пакети, Termux:X11, PulseAudio
# ============================================================

# ------------------------------------------------------------
# Залежності Termux — ставляться АВТОМАТИЧНО
# формат: "пакет:команда, за якою перевіряємо, чи він є"
# ------------------------------------------------------------

TERMUX_DEPS=(
    "proot-distro:proot-distro"
    "termux-x11-nightly:termux-x11"
    "pulseaudio:pulseaudio"
    "curl:curl"
    "tar:tar"
    "unzip:unzip"
    "procps:pkill"
)

# termux-x11-nightly та virglrenderer живуть у x11-repo.
termux_repos() {
    if have dpkg && dpkg -s x11-repo >/dev/null 2>&1; then
        return 0
    fi

    info "Enabling Termux X11 repository..."

    pkg update -y || true

    pkg install -y x11-repo || return 1

    pkg update -y || true
}

# termux_install pkg1 pkg2 ...
termux_install() {
    termux_repos || return 1

    DEBIAN_FRONTEND=noninteractive pkg install -y "$@"
}

# Перевіряє всі потрібні команди й доставляє те, чого бракує.
ensure_termux_deps() {
    local missing=() entry

    for entry in "${TERMUX_DEPS[@]}"; do
        have "${entry##*:}" || missing+=("${entry%%:*}")
    done

    [ "${#missing[@]}" -eq 0 ] && return 0

    if ! have pkg; then
        bad "pkg not found — this script must be run in Termux."
        return 1
    fi

    info "Installing missing Termux packages: ${missing[*]}"

    if ! termux_install "${missing[@]}"; then
        warn "Retrying after pkg update..."

        pkg update -y >/dev/null 2>&1 || true

        termux_install "${missing[@]}" || {
            bad "Could not install: ${missing[*]}"
            return 1
        }
    fi

    ok "Termux packages are ready."
}

install_termux() {
    info "Updating Termux..."

    pkg update -y || return 1

    ensure_termux_deps || return 1

    # Termux-частина GPU (mesa, vulkan) живе в gpu.sh
    gpu_install_termux_pkgs || return 1

    ok "Termux packages are ready."
}

# ------------------------------------------------------------
# Termux:X11
# ------------------------------------------------------------

start_x11() {
    ensure_termux_deps || return 1

    local sock="${TMPDIR:-$PREFIX/tmp}/.X11-unix/X0"

    if [ -S "$sock" ] && pgrep -f 'CmdEntryPoint' >/dev/null 2>&1; then
        info "Termux:X11 server is already running."
    else
        info "Starting Termux:X11..."

        XDG_RUNTIME_DIR="$TMPDIR" \
            termux-x11 :0 \
            >/dev/null 2>&1 &

        # Чекаємо, поки X-сервер справді створить сокет
        # (фіксований sleep 2 інколи був закороткий -> xdpyinfo не міг підключитись).
        local i

        for i in $(seq 1 20); do
            [ -S "$sock" ] && break
            sleep 1
        done

        [ -S "$sock" ] || warn "X11 socket not found yet, continuing anyway..."
    fi

    info "Opening Termux:X11 Android window..."

    am start \
        --user 0 \
        -n com.termux.x11/com.termux.x11.MainActivity \
        >/dev/null 2>&1 || true

    sleep 2

    ok "Termux:X11 window opened."
}

# ------------------------------------------------------------
# Пам'ять телефону (/storage/emulated/0) -> диск D: у Wine
# ------------------------------------------------------------

# Чи має Termux доступ до внутрішньої пам'яті.
storage_ok() {
    [ -d "$STORAGE_HOST" ] && ls "$STORAGE_HOST" >/dev/null 2>&1
}

# Просить у Android дозвіл на файли (termux-setup-storage), якщо його ще нема.
ensure_storage() {
    storage_ok && return 0

    warn "Termux has no access to $STORAGE_HOST yet."

    if have termux-setup-storage; then
        info "Android will ask for storage permission - tap ALLOW..."

        termux-setup-storage >/dev/null 2>&1 || true

        local i

        for i in $(seq 1 30); do
            if storage_ok; then
                ok "Storage access granted."
                return 0
            fi

            sleep 1
        done
    fi

    bad "No storage access. Enable it manually:"
    bad "Android Settings -> Apps -> Termux -> Permissions -> Files / Storage -> Allow."
    return 1
}

# ------------------------------------------------------------
# PulseAudio
# ------------------------------------------------------------

start_pulse() {
    ensure_termux_deps || return 1

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
