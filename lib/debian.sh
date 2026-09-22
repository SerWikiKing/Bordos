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

# ------------------------------------------------------------
# Rootfs Debian: proot-distro за замовчуванням качає з easycli.sh.
# Якщо той сервер недоступний — у логу видно ~43 байти й
# "Integrity checking failed". Тому заздалегідь кладемо той самий файл
# з GitHub Releases у кеш proot-distro; він сам перевірить sha256.
# ------------------------------------------------------------

debian_prefetch_rootfs() {
    local plugin="$PREFIX/etc/proot-distro/debian.sh"
    local cache="$PREFIX/var/lib/proot-distro/dlcache"
    local arch url name ver sha want

    case "$(uname -m)" in
        aarch64|arm64)  arch="aarch64" ;;
        armv7l|armv8l)  arch="arm" ;;
        x86_64)         arch="x86_64" ;;
        i686|i386)      arch="i686" ;;
        *)              return 1 ;;
    esac

    [ -f "$plugin" ] || return 1

    url="$(sed -n "s/^TARBALL_URL\['$arch'\]=\"\(.*\)\"\$/\1/p" "$plugin" | head -n 1)"
    want="$(sed -n "s/^TARBALL_SHA256\['$arch'\]=\"\(.*\)\"\$/\1/p" "$plugin" | head -n 1)"

    [ -n "$url" ] || return 1

    name="${url##*/}"
    ver="$(printf '%s' "$name" | sed -n 's/.*-pd-\(v[0-9.]*\)\.tar\.xz$/\1/p')"

    [ -n "$ver" ] || return 1

    mkdir -p "$cache"

    # Уже завантажений цілий файл — нічого не робимо.
    if [ -f "$cache/$name" ] && [ -n "$want" ]; then
        sha="$(sha256sum "$cache/$name" | awk '{ print $1 }')"
        [ "$sha" = "$want" ] && return 0
    fi

    rm -f "$cache/$name" "$cache/$name.tmp"

    info "Downloading Debian rootfs from GitHub..."

    curl -fL --retry 3 \
        -o "$cache/$name.tmp" \
        "https://github.com/termux/proot-distro/releases/download/${ver}/${name}" || {
        rm -f "$cache/$name.tmp"
        return 1
    }

    if [ -n "$want" ]; then
        sha="$(sha256sum "$cache/$name.tmp" | awk '{ print $1 }')"

        if [ "$sha" != "$want" ]; then
            warn "Checksum of the GitHub file does not match, ignoring it."
            rm -f "$cache/$name.tmp"
            return 1
        fi
    fi

    mv -f "$cache/$name.tmp" "$cache/$name"
}

install_debian() {

    # proot-distro та інші потрібні пакети Termux — автоматично.
    ensure_termux_deps || return 1

    # --------------------------------------------------------
    # НЕ ПЕРЕВСТАНОВЛЮЄМО ІСНУЮЧИЙ DEBIAN
    # --------------------------------------------------------

    if debian_exists; then
        ok "Debian container already exists."
    else
        info "Debian container not found."

        debian_prefetch_rootfs ||
            warn "Could not get the rootfs from GitHub, using the default proot-distro mirror."

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
    ca-certificates \
    curl \
    xz-utils \
    binutils \
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

# ------------------------------------------------------------
# REINSTALL: видаляє контейнер Debian повністю і ставить заново.
# Разом з ним зникають Wine, Box64/Box86 і все встановлене
# всередині — GPU-профіль і встановлені Termux-пакети не чіпаються.
# ------------------------------------------------------------

reinstall_debian() {

    warn "This will DELETE the whole Debian container:"
    warn "Wine builds, Box64/Box86, and everything installed inside Debian."

    printf "Type 'yes' to continue: "
    read -r answer

    if [ "$answer" != "yes" ]; then
        info "Cancelled."
        return 0
    fi

    if debian_exists; then
        info "Removing the existing Debian container..."

        proot-distro remove debian || {
            bad "Could not remove the existing Debian container."
            return 1
        }
    fi

    # Стара активна збірка Wine пропала разом з контейнером.
    cfg_set WINE_ACTIVE ""

    install_debian
}
