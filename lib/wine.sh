# shellcheck shell=bash
# ============================================================
# WINE
#
# Збірки беруться з https://github.com/Kron4ek/Wine-Builds
# і ставляться всередину Debian:
#
#   /opt/wine/<назва збірки>/      кожна версія окремо
#   /opt/wine/current              symlink на активну версію
#   /usr/local/bin/wine ...        обгортки, що запускають wine через Box64/Box86
#
# Налаштування в config.conf:
#   WINE_TYPE    vanilla | staging | staging-tkg | proton
#   WINE_ARCH    amd64 | amd64-wow64 | x86
#   WINE_ACTIVE  назва активної збірки
# ============================================================

WINE_REPO="Kron4ek/Wine-Builds"
WINE_ROOT="/opt/wine"
WINE_RUN_ENV=(DISPLAY=:0 XDG_RUNTIME_DIR=/tmp PULSE_SERVER=127.0.0.1)

# ------------------------------------------------------------
# Налаштування
# ------------------------------------------------------------

wine_type() {
    cfg_get WINE_TYPE vanilla
}

wine_arch() {
    cfg_get WINE_ARCH amd64
}

wine_active_name() {
    cfg_get WINE_ACTIVE none
}

# amd64 / amd64-wow64 -> Box64, x86 -> Box86
wine_emu() {
    case "$1" in
        x86) echo "box86" ;;
        *)   echo "box64" ;;
    esac
}

# Версія іде в URL і в шлях — приймаємо лише безпечні символи.
wine_valid_version() {
    [[ "$1" =~ ^[0-9A-Za-z._-]+$ ]]
}

# ------------------------------------------------------------
# Імена та URL збірок Kron4ek
#   vanilla      wine-11.18-amd64.tar.xz
#   staging      wine-11.18-staging-amd64.tar.xz
#   staging-tkg  wine-11.18-staging-tkg-amd64.tar.xz
#   proton       wine-proton-11.0-2-amd64.tar.xz   (tag: proton-11.0-2)
#   arch: amd64 | amd64-wow64 | x86
# ------------------------------------------------------------

wine_build_name() {
    local ver="$1" type="$2" arch="$3"

    case "$type" in
        proton)      echo "wine-proton-${ver}-${arch}" ;;
        staging)     echo "wine-${ver}-staging-${arch}" ;;
        staging-tkg) echo "wine-${ver}-staging-tkg-${arch}" ;;
        *)           echo "wine-${ver}-${arch}" ;;
    esac
}

wine_release_tag() {
    local ver="$1" type="$2"

    if [ "$type" = "proton" ]; then
        echo "proton-${ver}"
    else
        echo "${ver}"
    fi
}

# ------------------------------------------------------------
# Список доступних версій (GitHub API, запасний варіант — atom feed)
# ------------------------------------------------------------

wine_list_versions() {
    local type="$1"
    local tags="" chunk page

    for page in 1 2 3 4; do
        chunk="$(
            curl -fsSL --max-time 20 \
                "https://api.github.com/repos/${WINE_REPO}/releases?per_page=100&page=${page}" \
                2>/dev/null |
                grep -o '"tag_name": *"[^"]*"' |
                sed 's/.*: *"//; s/"$//'
        )"

        [ -n "$chunk" ] || break

        tags="${tags}${chunk}"$'\n'
    done

    # Запасний варіант, якщо API недоступний / ліміт запитів (лише останні ~10).
    if [ -z "$tags" ]; then
        tags="$(
            curl -fsSL --max-time 20 \
                "https://github.com/${WINE_REPO}/releases.atom" \
                2>/dev/null |
                grep -o 'releases/tag/[^"]*"' |
                sed 's|releases/tag/||; s/"$//'
        )"
    fi

    if [ "$type" = "proton" ]; then
        printf '%s\n' "$tags" | sed -n 's/^proton-//p'
    else
        printf '%s\n' "$tags" | grep -E '^[0-9]+\.[0-9]+(\.[0-9]+)?$'
    fi | sort -Vru
}

# ------------------------------------------------------------
# Вибір версії (по сторінках). Результат: WINE_PICKED
# ------------------------------------------------------------

wine_pick_version() {
    local type
    type="$(wine_type)"

    WINE_PICKED=""

    info "Fetching Wine versions ($type)..."

    have curl || pkg install -y curl || return 1

    local versions=()
    mapfile -t versions < <(wine_list_versions "$type")

    local total="${#versions[@]}"
    local page=0 per=10
    local start end i choice v

    if [ "$total" -eq 0 ]; then
        warn "Could not fetch the version list. Enter the version manually."
    fi

    while true; do

        clear

        echo "========== WINE VERSION ($type) =========="

        start=$((page * per))
        end=$((start + per))

        [ "$end" -gt "$total" ] && end="$total"

        i="$start"

        while [ "$i" -lt "$end" ]; do
            printf "[%d] %s\n" "$((i - start + 1))" "${versions[$i]}"
            i=$((i + 1))
        done

        echo

        [ "$end" -lt "$total" ] && echo "[n] Next page"
        [ "$page" -gt 0 ] && echo "[p] Previous page"

        echo "[m] Enter version manually (e.g. 9.0)"
        echo "[0] Cancel"

        printf "> "
        read -r choice

        case "$choice" in

            0)
                return 1
                ;;

            n|N)
                [ "$end" -lt "$total" ] && page=$((page + 1))
                ;;

            p|P)
                [ "$page" -gt 0 ] && page=$((page - 1))
                ;;

            m|M)
                printf "Version: "
                read -r v

                if wine_valid_version "$v"; then
                    WINE_PICKED="$v"
                    return 0
                fi

                warn "Invalid version."
                sleep 1
                ;;

            *)
                if [[ "$choice" =~ ^[0-9]+$ ]] &&
                   [ "$choice" -ge 1 ] &&
                   [ "$choice" -le "$((end - start))" ]; then
                    WINE_PICKED="${versions[$((start + choice - 1))]}"
                    return 0
                fi

                warn "Unknown option."
                sleep 1
                ;;

        esac

    done
}

# ------------------------------------------------------------
# Встановлені збірки
# ------------------------------------------------------------

wine_installed_list() {

    debian bash -s <<'LIST'
for d in /opt/wine/*/; do
    [ -d "$d" ] || continue
    n="$(basename "$d")"
    [ "$n" = "current" ] && continue
    echo "$n"
done
LIST
}

wine_is_installed() {
    debian test -d "$WINE_ROOT/$1"
}

# ------------------------------------------------------------
# Обгортки wine / wineserver / winecfg ... (один раз, всередині Debian)
# Яка збірка активна і чим її запускати (box64/box86) — береться під час запуску
# з /opt/wine/current, тому перемикання версії не потребує переписування.
# ------------------------------------------------------------

wine_write_wrappers() {

    debian bash -s <<'WRAPPERS'
set -e

mkdir -p /opt/wine /usr/local/bin

cat > /usr/local/bin/ldm-wine-run <<'RUN'
#!/bin/bash
# Linux Desktop Manager: запуск Wine через Box64/Box86
W=/opt/wine/current
prog="$1"
shift

if [ ! -d "$W" ]; then
    echo "No active Wine build. Choose one in Settings -> Wine." >&2
    exit 1
fi

[ -f /etc/profile.d/linux-manager-gpu.sh ] && . /etc/profile.d/linux-manager-gpu.sh

export WINEPREFIX="${WINEPREFIX:-$HOME/.wine}"
export WINEDEBUG="${WINEDEBUG:--all}"

EMU="$(cat "$W/.ldm-emu" 2>/dev/null || echo box64)"

if ! command -v "$EMU" >/dev/null 2>&1; then
    echo "$EMU is not installed. Install it in Settings -> BOX." >&2
    exit 1
fi

case "$prog" in
    wineserver)
        bin="$W/bin/wineserver"
        ;;
    *)
        if [ -x "$W/bin/wine64" ]; then
            bin="$W/bin/wine64"
        else
            bin="$W/bin/wine"
        fi
        ;;
esac

exec "$EMU" "$bin" "$@"
RUN

chmod +x /usr/local/bin/ldm-wine-run

mk() {
    printf '#!/bin/bash\nexec /usr/local/bin/ldm-wine-run %s "$@"\n' "$2" \
        > "/usr/local/bin/$1"
    chmod +x "/usr/local/bin/$1"
}

mk wine       "wine"
mk wine64     "wine"
mk wineserver "wineserver"
mk winecfg    "wine winecfg"
mk wineboot   "wine wineboot"
mk regedit    "wine regedit"
WRAPPERS

}

# ------------------------------------------------------------
# Активна версія
# ------------------------------------------------------------

wine_activate() {
    local name="$1"

    if ! wine_is_installed "$name"; then
        bad "Wine build is not installed: $name"
        return 1
    fi

    debian ln -sfn "$WINE_ROOT/$name" "$WINE_ROOT/current" || {
        bad "Could not switch the active Wine build."
        return 1
    }

    wine_write_wrappers || {
        bad "Could not write Wine launchers."
        return 1
    }

    cfg_set WINE_ACTIVE "$name"

    ok "Active Wine: $name"
}

# ------------------------------------------------------------
# Завантаження і встановлення
# ------------------------------------------------------------

wine_install() {
    local ver="$1" type="$2" arch="$3"

    local name tag base url emu

    name="$(wine_build_name "$ver" "$type" "$arch")"
    tag="$(wine_release_tag "$ver" "$type")"
    base="https://github.com/${WINE_REPO}/releases/download/${tag}"
    url="${base}/${name}.tar.xz"
    emu="$(wine_emu "$arch")"

    install_debian || return 1

    if wine_is_installed "$name"; then
        ok "$name is already installed."
        wine_activate "$name"
        return $?
    fi

    have curl || pkg install -y curl || return 1

    info "Checking: $name"

    # Не для кожної версії є кожен тип / архітектура.
    if ! curl -fsIL --max-time 20 "$url" >/dev/null 2>&1; then
        bad "This build does not exist: $name"
        info "Try another build type / architecture, or another version."
        return 1
    fi

    if ! debian_has "$emu"; then
        warn "$emu is not installed in Debian. Wine will not run until you install it (Settings -> BOX)."
    fi

    info "Downloading and unpacking $name (this can take a while)..."

    debian env \
        WINE_URL="$url" \
        WINE_SUMS="${base}/sha256sums.txt" \
        WINE_NAME="$name" \
        WINE_EMU="$emu" \
        bash -s <<'WINE_INSTALL'

set -e
export DEBIAN_FRONTEND=noninteractive

need=""

command -v curl >/dev/null 2>&1 || need="$need curl"
command -v xz   >/dev/null 2>&1 || need="$need xz-utils"
[ -d /etc/ssl/certs ]           || need="$need ca-certificates"

if [ -n "$need" ]; then
    apt-get update
    # shellcheck disable=SC2086
    apt-get install -y $need
fi

mkdir -p /opt/wine

tmp="$(mktemp -d /opt/wine/.dl.XXXXXX)"
trap 'rm -rf "$tmp"' EXIT

echo "Downloading $WINE_NAME ..."

curl -fL --retry 3 -o "$tmp/wine.tar.xz" "$WINE_URL"

# Перевірка контрольної суми (якщо sha256sums.txt доступний).
if curl -fsSL --retry 2 -o "$tmp/sums.txt" "$WINE_SUMS"; then

    want="$(
        awk -v f="$WINE_NAME.tar.xz" \
            '$2 == f || $2 == "*" f { print $1; exit }' \
            "$tmp/sums.txt"
    )"

    have_sum="$(sha256sum "$tmp/wine.tar.xz" | awk '{ print $1 }')"

    if [ -z "$want" ]; then
        echo "No checksum found for this file, skipping verification."
    elif [ "$want" = "$have_sum" ]; then
        echo "Checksum OK."
    else
        echo "ERROR: checksum mismatch."
        exit 20
    fi

else
    echo "sha256sums.txt is unavailable, skipping verification."
fi

echo "Unpacking..."

mkdir "$tmp/x"

tar -xJf "$tmp/wine.tar.xz" -C "$tmp/x"

top="$(ls -1 "$tmp/x" | head -n 1)"

if [ -z "$top" ]; then
    echo "ERROR: archive is empty."
    exit 21
fi

rm -rf "/opt/wine/$WINE_NAME"

mv "$tmp/x/$top" "/opt/wine/$WINE_NAME"

echo "$WINE_EMU" > "/opt/wine/$WINE_NAME/.ldm-emu"

echo "Unpacked to /opt/wine/$WINE_NAME"

WINE_INSTALL

    local result=$?

    if [ "$result" -ne 0 ]; then
        bad "Wine installation failed."
        return 1
    fi

    ok "Wine installed: $name"

    wine_activate "$name"
}

# Меню: вибрати версію і встановити з поточним типом / архітектурою.
wine_download() {
    local type arch

    type="$(wine_type)"
    arch="$(wine_arch)"

    wine_pick_version || return 0

    echo
    info "Type: $type | Architecture: $arch | Version: $WINE_PICKED"

    wine_install "$WINE_PICKED" "$type" "$arch"
}

# ------------------------------------------------------------
# Перемикання / видалення
# ------------------------------------------------------------

wine_switch() {
    install_debian || return 1

    local list=()
    mapfile -t list < <(wine_installed_list)

    if [ "${#list[@]}" -eq 0 ]; then
        warn "No Wine builds installed yet."
        return 0
    fi

    menu_pick "INSTALLED WINE (active: $(wine_active_name))" "${list[@]}" || return 0

    wine_activate "$PICKED"
}

wine_remove() {
    install_debian || return 1

    local list=()
    mapfile -t list < <(wine_installed_list)

    if [ "${#list[@]}" -eq 0 ]; then
        warn "No Wine builds installed yet."
        return 0
    fi

    menu_pick "REMOVE WINE" "${list[@]}" || return 0

    local name="$PICKED" answer

    printf "Remove %s? [y/N] " "$name"
    read -r answer

    case "$answer" in
        y|Y) ;;
        *) return 0 ;;
    esac

    debian rm -rf "${WINE_ROOT:?}/$name" || {
        bad "Could not remove $name."
        return 1
    }

    if [ "$(cfg_get WINE_ACTIVE)" = "$name" ]; then
        debian rm -f "$WINE_ROOT/current" >/dev/null 2>&1 || true
        cfg_set WINE_ACTIVE ""
        warn "The active build was removed. Choose another one."
    fi

    ok "Removed: $name"
}

# ------------------------------------------------------------
# Тип збірки / архітектура
# ------------------------------------------------------------

wine_choose_type() {
    menu_pick "WINE BUILD TYPE (now: $(wine_type))" \
        "vanilla (official Wine)" \
        "staging (Wine + Staging patches)" \
        "staging-tkg (Staging + TKG patches)" \
        "proton (Valve's Wine)" \
        || return 0

    cfg_set WINE_TYPE "${PICKED%% *}"

    ok "Build type: $(wine_type)"
}

wine_choose_arch() {
    menu_pick "WINE ARCHITECTURE (now: $(wine_arch))" \
        "amd64 (64-bit, Box64)" \
        "amd64-wow64 (64-bit + 32-bit apps, Box64)" \
        "x86 (32-bit, Box86)" \
        || return 0

    cfg_set WINE_ARCH "${PICKED%% *}"

    ok "Architecture: $(wine_arch) ($(wine_emu "$(wine_arch)"))"
}

# ------------------------------------------------------------
# Бібліотеки, тест, запуск
# ------------------------------------------------------------

wine_install_libs() {

    install_debian || return 1

    info "Installing common libraries for Wine (best effort)..."

    debian bash -s <<'WINE_LIBS'
export DEBIAN_FRONTEND=noninteractive

apt-get update

for p in \
    libasound2 libpulse0 libx11-6 libxext6 libxrender1 libxi6 \
    libxcursor1 libxrandr2 libxinerama1 libxcomposite1 \
    libfreetype6 libfontconfig1 libgnutls30 libglu1-mesa \
    libsdl2-2.0-0 libvulkan1
do
    if apt-get install -y "$p" >/dev/null 2>&1; then
        echo "  ok:      $p"
    else
        echo "  skipped: $p"
    fi
done
WINE_LIBS

    ok "Done."
}

wine_test() {

    install_debian || return 1

    echo
    echo "========== WINE TEST =========="

    echo "Active: $(wine_active_name)"

    local e

    for e in box64 box86; do
        if debian_has "$e"; then
            echo "$e: installed"
        else
            echo "$e: not installed"
        fi
    done

    echo

    if debian test -d "$WINE_ROOT/current"; then
        echo "Wine version:"
        debian env "${WINE_RUN_ENV[@]}" /usr/local/bin/wine --version 2>&1 |
            head -n 5
    else
        echo "No active Wine build."
    fi

    echo "==============================="
}

wine_run_exe() {

    install_debian || return 1

    local program

    printf "Path to .exe inside Debian: "
    read -r program

    [ -n "$program" ] ||
        return 0

    debian env "${WINE_RUN_ENV[@]}" /usr/local/bin/wine "$program"
}

# ------------------------------------------------------------
# WINE MENU
# ------------------------------------------------------------

wine_menu() {

    while true; do

        clear

        echo "========== WINE =========="
        echo "Active:       $(wine_active_name)"
        echo "Build type:   $(wine_type)"
        echo "Architecture: $(wine_arch) ($(wine_emu "$(wine_arch)"))"
        echo
        echo "[1] Download / install Wine (choose version)"
        echo "[2] Installed versions (switch active)"
        echo "[3] Remove a version"
        echo "[4] Change build type"
        echo "[5] Change architecture"
        echo "[6] Install Wine libraries"
        echo "[7] Test Wine"
        echo "[8] Run a Windows program (.exe)"
        echo "[0] Back"

        printf "> "
        read -r choice

        case "$choice" in
            1) wine_download ;;
            2) wine_switch ;;
            3) wine_remove ;;
            4) wine_choose_type ;;
            5) wine_choose_arch ;;
            6) wine_install_libs ;;
            7) wine_test ;;
            8) wine_run_exe ;;
            0) return ;;
            *) warn "Unknown option." ;;
        esac

        pause

    done
}
