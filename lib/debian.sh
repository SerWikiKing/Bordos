# shellcheck shell=bash
# ============================================================
# DEBIAN (proot-distro) + XFCE4
# ============================================================

# Дуже важливо:
# якщо Debian вже існує — ця команда повертає 0.
# Тому proot-distro install debian повторно НЕ запускається.
debian_exists() {
    proot-distro login debian -- true >/dev/null 2>&1
}

# Виконати команду всередині Debian.
debian() {
    proot-distro login debian --shared-tmp -- "$@"
}

# Чи є команда всередині Debian (command — builtin, тому через bash -c).
debian_has() {
    debian bash -c 'command -v "$1" >/dev/null 2>&1' _ "$1"
}

install_debian() {

    # --------------------------------------------------------
    # НЕ ПЕРЕВСТАНОВЛЮЄМО ІСНУЮЧИЙ DEBIAN
    # --------------------------------------------------------

    if debian_exists; then
        ok "Debian container already exists."
    else
        info "Debian container not found."
        info "Installing Debian..."

        proot-distro install debian || {
            bad "Debian installation failed."
            return 1
        }

        if ! debian_exists; then
            bad "Debian was installed but cannot be opened."
            return 1
        fi

        ok "Debian installed."
    fi

    # --------------------------------------------------------
    # APT
    # --------------------------------------------------------

    info "Updating Debian repositories..."

    debian bash -s <<'DEBIAN_APT'

set -e

# Вимикаємо старий проблемний Box86 repository.
for f in /etc/apt/sources.list.d/*.list; do

    [ -e "$f" ] || continue

    if grep -q 'pi-apps-coders/box86-debs' "$f" 2>/dev/null; then

        sed -i \
            '/pi-apps-coders\/box86-debs/s/^/# disabled by Linux Desktop Manager: /' \
            "$f"

    fi

done


apt-get update


apt-get install -y \
    dbus-x11 \
    x11-utils \
    mesa-utils \
    mesa-utils-extra \
    libgl1 \
    libgl1-mesa-dri \
    libvulkan1 \
    vulkan-tools \
    xfce4 \
    xfce4-terminal \
    thunar

DEBIAN_APT

    local result=$?

    if [ "$result" -eq 0 ]; then
        ok "Debian + XFCE4 is ready."
    else
        bad "Debian package installation failed."
    fi

    return "$result"
}
