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
WINEGE_REPO="GloriousEggroll/wine-ge-custom"
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

wine_is_ge() {
    [ "$(wine_type)" = "wine-ge" ]
}

wine_type_label() {
    case "${1:-$(wine_type)}" in
        wine-ge) echo "wine-ge (GloriousEggroll, DXVK+VKD3D+FAudio built in)" ;;
        proton)  echo "proton" ;;
        *)       echo "${1:-$(wine_type)}" ;;
    esac
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
        wine-ge)     echo "wine-lutris-${ver}-x86_64" ;;
        proton)      echo "wine-proton-${ver}-${arch}" ;;
        staging)     echo "wine-${ver}-staging-${arch}" ;;
        staging-tkg) echo "wine-${ver}-staging-tkg-${arch}" ;;
        *)           echo "wine-${ver}-${arch}" ;;
    esac
}

wine_release_tag() {
    local ver="$1" type="$2"

    case "$type" in
        # У GloriousEggroll версія й тег релізу — те саме (напр. GE-Proton8-26).
        wine-ge) echo "$ver" ;;
        proton)  echo "proton-${ver}" ;;
        *)       echo "$ver" ;;
    esac
}

wine_repo_for_type() {
    if [ "${1:-$(wine_type)}" = "wine-ge" ]; then
        echo "$WINEGE_REPO"
    else
        echo "$WINE_REPO"
    fi
}

# ------------------------------------------------------------
# Список доступних версій (GitHub API, запасний варіант — atom feed)
# ------------------------------------------------------------

wine_list_versions() {
    local type="$1"
    local repo tags="" chunk page

    repo="$(wine_repo_for_type "$type")"

    for page in 1 2 3 4; do
        chunk="$(
            curl -fsSL --max-time 20 \
                "https://api.github.com/repos/${repo}/releases?per_page=100&page=${page}" \
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
                "https://github.com/${repo}/releases.atom" \
                2>/dev/null |
                grep -o 'releases/tag/[^"]*"' |
                sed 's|releases/tag/||; s/"$//'
        )"
    fi

    case "$type" in

        wine-ge)
            # Пропускаємо варіанти під конкретні гри (-LoL і т.п.);
            # їх завжди можна ввести вручну через [m].
            printf '%s\n' "$tags" |
                grep -E '^GE-Proton[0-9]+-[0-9]+$' |
                sort -t- -k2 -k3 -Vr
            ;;

        proton)
            printf '%s\n' "$tags" | sed -n 's/^proton-//p' | sort -Vru
            ;;

        *)
            printf '%s\n' "$tags" |
                grep -E '^[0-9]+\.[0-9]+(\.[0-9]+)?$' |
                sort -Vru
            ;;

    esac
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

# Без цього при створенні префікса Wine показує діалоги "Install Wine
# Mono / Gecko?" (збірки Kron4ek їх не містять) і чекає на натискання —
# на Termux:X11 без оболонки це виглядає як чорний екран, що "висить".
export WINEDLLOVERRIDES="${WINEDLLOVERRIDES:-mscoree,mshtml=}"

# Диск D: -> внутрішня пам'ять Android (/storage/emulated/0).
[ "$prog" = "wineserver" ] || /usr/local/bin/ldm-map-drives >&2 || true

# "-all" ховає навіть рядок, яким Wine пояснює, чому він щойно вийшов
# (саме це і сталося: box64/box32 відпрацювали чисто, а "wine exited
# with code 1" лишився без жодного пояснення). err+all показує тільки
# власні err-повідомлення Wine, без "fixme"-шуму.
export WINEDEBUG="${WINEDEBUG:-err+all}"

# Дає видно причину падіння (SIGSEGV/SIGILL/...) замість тихого виходу
# без жодного логу — саме так, як зараз, без цих змінних, box64 мовчки
# зникає, коли щось іде не так.
export BOX64_LOG="${BOX64_LOG:-1}"
export BOX64_SHOWSEGV="${BOX64_SHOWSEGV:-1}"

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

# D: -> /storage/emulated/0 (створює symlink у dosdevices префікса).
cat > /usr/local/bin/ldm-map-drives <<'MAP'
#!/bin/bash
P="${WINEPREFIX:-$HOME/.wine}"
T="${LDM_STORAGE:-/storage/emulated/0}"
L="$P/dosdevices/d:"

# Префікс ще не створений — dosdevices з'явиться після першого wineboot.
[ -d "$P/dosdevices" ] || exit 0

if [ ! -d "$T" ]; then
    echo "[ldm] $T is not visible inside Debian - drive D: not created." >&2
    echo "[ldm] Give Termux storage permission (termux-setup-storage) and restart." >&2
    exit 0
fi

if [ -L "$L" ]; then
    [ "$(readlink "$L")" = "$T" ] && exit 0
    rm -f "$L"
elif [ -e "$L" ]; then
    # d: вже є як звичайний каталог/файл — не чіпаємо.
    exit 0
fi

ln -s "$T" "$L" && echo "[ldm] Drive D: -> $T"
MAP

chmod +x /usr/local/bin/ldm-map-drives

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

    local name tag repo base url emu sums_url sums_algo

    name="$(wine_build_name "$ver" "$type" "$arch")"
    tag="$(wine_release_tag "$ver" "$type")"
    repo="$(wine_repo_for_type "$type")"
    base="https://github.com/${repo}/releases/download/${tag}"
    url="${base}/${name}.tar.xz"

    if [ "$type" = "wine-ge" ]; then
        # Один готовий x86_64-білд (з wow64 для 32-бітних застосунків) — завжди Box64.
        sums_url="${base}/${name}.sha512sum"
        sums_algo="sha512sum"
        emu="box64"
    else
        sums_url="${base}/sha256sums.txt"
        sums_algo="sha256sum"
        emu="$(wine_emu "$arch")"
    fi

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
        WINE_SUMS="$sums_url" \
        WINE_SUMS_ALGO="$sums_algo" \
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

    have_sum="$("$WINE_SUMS_ALGO" "$tmp/wine.tar.xz" | awk '{ print $1 }')"

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
    info "Type: $(wine_type_label "$type") | Architecture: $(wine_arch_display) | Version: $WINE_PICKED"

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
        "wine-ge (GloriousEggroll, ready for games)" \
        || return 0

    cfg_set WINE_TYPE "${PICKED%% *}"

    ok "Build type: $(wine_type_label)"
}

wine_arch_display() {
    if wine_is_ge; then
        echo "x86_64 (fixed, Box64)"
    else
        echo "$(wine_arch) ($(wine_emu "$(wine_arch)"))"
    fi
}

wine_choose_arch() {

    if wine_is_ge; then
        warn "wine-ge ships one x86_64 build (with built-in wow64); there is nothing to choose."
        return 0
    fi

    menu_pick "WINE ARCHITECTURE (now: $(wine_arch))" \
        "amd64 (64-bit, Box64)" \
        "amd64-wow64 (64-bit + 32-bit apps, Box64)" \
        "x86 (32-bit, Box86)" \
        || return 0

    cfg_set WINE_ARCH "${PICKED%% *}"

    ok "Architecture: $(wine_arch_display)"
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

# Ці ставимо як звичайні arm64-пакети: Box64 підмінює їх власними
# ARM64-обгортками (X11, GL/Vulkan, PulseAudio, звук тощо), тому arm64-
# версія якраз потрібна.
for p in \
    libasound2 libpulse0 libx11-6 libxext6 libxrender1 libxi6 \
    libxcursor1 libxrandr2 libxinerama1 libxcomposite1 \
    libxfixes3 libxxf86vm1 libxdamage1 libxkbcommon0 \
    libegl1 libgl1 libdbus-1-3 \
    libfreetype6 libfontconfig1 libgnutls30 libglu1-mesa \
    libsdl2-2.0-0 libvulkan1
do
    if apt-get install -y "$p" >/dev/null 2>&1; then
        echo "  ok:      $p"
    else
        echo "  skipped: $p"
    fi
done

# libunwind Wine потрібен по-справжньому у вигляді x86_64-файлу — Box64
# його не підміняє своєю ARM64-версією. У Debian пакет box64 (dfsg)
# власного x86_64 libunwind не несе, тому додаємо amd64 як другу
# архітектуру й ставимо саме amd64-пакет (це лише файл бібліотеки,
# запускати його не потрібно, apt/dpkg просто розпакують потрібні .so).
if ! dpkg --print-foreign-architectures 2>/dev/null | grep -qx amd64; then
    echo "Enabling amd64 as a second architecture (for x86_64 libunwind)..."
    dpkg --add-architecture amd64
    apt-get update
fi

if apt-get install -y libunwind8:amd64 >/dev/null 2>&1; then
    echo "  ok:      libunwind8:amd64"
else
    echo "  skipped: libunwind8:amd64"
fi

# Маркер: бібліотеки вже ставились (щоб Wine Desktop не ставив їх щоразу).
mkdir -p /opt/wine
touch /opt/wine/.ldm-libs-v2
WINE_LIBS

    ok "Done."
}

# Без x86_64-обгорток X11/GL Wine не може завантажити winex11.drv і
# запускається "у нікуди" (чорний екран) — тому при першому запуску
# Wine Desktop бібліотеки ставляться автоматично.
wine_ensure_libs() {

    if debian test -f /opt/wine/.ldm-libs-v2; then
        return 0
    fi

    info "First Wine Desktop launch: installing required libraries..."

    wine_install_libs
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

wine_reset_prefix() {

    install_debian || return 1

    echo
    echo "This deletes the Wine prefix (~/.wine inside Debian) — any"
    echo "installed Windows programs, settings and shortcuts in it"
    echo "are lost. A fresh, empty one is created on the next launch."
    echo "Useful when Wine exits immediately with no error (a prefix"
    echo "half-built by an earlier failed/interrupted run)."
    printf "Type YES to continue: "
    read -r confirm

    if [ "$confirm" != "YES" ]; then
        warn "Cancelled."
        return 0
    fi

    debian bash -lc 'rm -rf "$HOME/.wine"'

    ok "Wine prefix removed."
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
# WINE DESKTOP — окрема "Windows-подібна" сесія замість XFCE4:
# Wine показує на весь екран свій explorer.exe (робочий стіл,
# ярлики, меню "Пуск"), і саме тут відкриваються запущені
# програми — окремої DE поверх нема, XFCE4 не потрібен.
# ------------------------------------------------------------

wine_desktop_res() {
    cfg_get WINE_DESKTOP_RES "1280x720"
}

wine_choose_desktop_res() {

    menu_pick "WINE DESKTOP RESOLUTION (now: $(wine_desktop_res))" \
        "auto (fill the whole Termux:X11 screen)" \
        "1280x720" \
        "1366x768" \
        "1920x1080" \
        "Custom" \
        || return 0

    case "$PICKED" in

        auto*)
            PICKED="auto"
            ;;

        Custom)
            local res

            printf "Resolution (e.g. 1600x900): "
            read -r res

            [[ "$res" =~ ^[0-9]+x[0-9]+$ ]] || {
                warn "Invalid resolution."
                return 1
            }

            PICKED="$res"
            ;;

    esac

    cfg_set WINE_DESKTOP_RES "$PICKED"

    ok "Wine Desktop resolution: $(wine_desktop_res)"
}

# Диск D: зараз (без запуску робочого столу).
wine_map_drive_now() {

    install_debian || return 1

    ensure_storage || return 1

    wine_write_wrappers || return 1

    if ! debian test -d "/root/.wine/dosdevices"; then
        warn "The Wine prefix does not exist yet."
        info "Start Wine Desktop once - it creates the prefix and maps D: automatically."
        return 0
    fi

    debian /usr/local/bin/ldm-map-drives

    ok "Drive D: -> $STORAGE_HOST (restart Wine Desktop to see it)."
}

start_wine_desktop() {

    if [ "$(wine_active_name)" = "none" ]; then
        warn "No active Wine build. Install one first: Settings -> WINE -> Download / install Wine."
        return 1
    fi

    install_debian || return 1

    # Диск D: -> /storage/emulated/0 (потрібен дозвіл Android на файли).
    ensure_storage ||
        warn "Drive D: will not exist until Termux gets storage access."

    wine_ensure_libs ||
        warn "Could not install Wine libraries - Wine may not open any window."

    # Оновлюємо обгортки (диск D:, WINEDLLOVERRIDES) без повторної активації збірки.
    wine_write_wrappers || return 1

    start_x11 || return 1

    start_pulse || true

    case "$(gpu_mode)" in
        turnip) install_freedreno || return 1 ;;
        virgl)  start_virgl || return 1 ;;
    esac

    write_profile || return 1

    local res
    res="$(wine_desktop_res)"

    rm -f "$WINE_DESKTOP_LOG"

    debian_refresh_binds

    info "Starting Wine Desktop ($res, $(wine_active_name)) with $(gpu_name)..."

    proot-distro login debian \
        --shared-tmp \
        "${DEBIAN_BINDS[@]}" \
        -- \
        env \
        DISPLAY=:0 \
        XDG_RUNTIME_DIR=/tmp \
        PULSE_SERVER=127.0.0.1 \
        XKB_CONFIG_ROOT=/usr/share/X11/xkb \
        WINE_DESKTOP_RES="$res" \
        bash -s \
        >"$WINE_DESKTOP_LOG" 2>&1 <<'WINE_DESKTOP_SCRIPT' &

. /etc/profile.d/linux-manager-gpu.sh

export WINEPREFIX="${WINEPREFIX:-$HOME/.wine}"

echo "DISPLAY=$DISPLAY"
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

RES="$WINE_DESKTOP_RES"

if [ "$RES" = "auto" ]; then
    RES="$(xdpyinfo 2>/dev/null | awk '/dimensions:/ { print $2; exit }')"
    RES="${RES:-1280x720}"
fi

# Старий wineserver (із попереднього запуску) тримає стару конфігурацію
# й dosdevices — завжди починаємо з чистого.
echo "Stopping old Wine processes..."
/usr/local/bin/wineserver -k >/dev/null 2>&1 || true
sleep 1

# Перший запуск: спершу створюємо префікс окремо. Саме ця фаза на Box64
# триває 1-3 хвилини — весь цей час екран Termux:X11 чорний, це нормально.
if [ ! -f "$WINEPREFIX/system.reg" ]; then
    echo "First launch: creating the Wine prefix (1-3 minutes, black screen is normal)..."
    /usr/local/bin/wine wineboot -u
    echo "wineboot exit code: $?"
    timeout 90 /usr/local/bin/wineserver -w || true
fi

# D: -> /storage/emulated/0 (до старту wineserver, щоб він одразу побачив диск).
/usr/local/bin/ldm-map-drives

# Синій фон замість чорного — одразу видно, що робочий стіл Wine працює.
# Ставиться один раз; змінити колір можна в regedit
# (HKCU\Control Panel\Colors\Background).
if [ ! -f "$WINEPREFIX/.ldm-bg-done" ]; then
    /usr/local/bin/wine reg add 'HKCU\Control Panel\Colors' \
        /v Background /t REG_SZ /d '0 78 152' /f >/dev/null 2>&1 || true
    timeout 60 /usr/local/bin/wineserver -w || true
    touch "$WINEPREFIX/.ldm-bg-done"
fi

echo "LDM: launching explorer ($RES)"

# Назва "shell" вмикає панель задач, меню Пуск і ярлики на столі.
/usr/local/bin/wine explorer "/desktop=shell,${RES}"
rc=$?

echo "wine exited with code $rc"

exit "$rc"

WINE_DESKTOP_SCRIPT

    local pid=$!
    local waited=0

    # Чекаємо, поки скрипт дійде до запуску explorer (на першому запуску
    # створення префікса займає час), але не довше 4 хвилин.
    info "Waiting for Wine (the first launch can take a few minutes)..."

    while kill -0 "$pid" >/dev/null 2>&1 &&
          ! grep -q 'LDM: launching explorer' "$WINE_DESKTOP_LOG" 2>/dev/null &&
          [ "$waited" -lt 240 ]; do
        sleep 2
        waited=$((waited + 2))
        printf '.'
    done

    echo

    sleep 5

    echo
    echo "========== WINE DESKTOP START =========="

    tail -n 60 "$WINE_DESKTOP_LOG" 2>/dev/null || true

    echo "=========================================="
    echo "Full log: $WINE_DESKTOP_LOG"
    echo "(open it in [5] Start Terminal with: less \"$WINE_DESKTOP_LOG\")"

    if kill -0 "$pid" >/dev/null 2>&1; then
        ok "Wine Desktop started. Switch to the Termux:X11 window."
        info "Drive D: = $STORAGE_HOST (see 'This PC' / My Computer in Wine)."
    else
        bad "Wine Desktop stopped."
        echo
        echo "Last 60 lines:"
        tail -n 60 "$WINE_DESKTOP_LOG" 2>/dev/null || true
        return 1
    fi
}

restart_wine_desktop() {

    pkill -f 'wine.*explorer' \
        >/dev/null 2>&1 || true

    pkill -f 'box64.*wineserver' \
        >/dev/null 2>&1 || true

    sleep 1

    start_wine_desktop
}

# ------------------------------------------------------------
# WINE MENU
# ------------------------------------------------------------

wine_menu() {

    while true; do

        clear

        echo "========== WINE =========="
        echo "Active:       $(wine_active_name)"
        echo "Build type:   $(wine_type_label)"
        echo "Architecture: $(wine_arch_display)"
        echo
        echo "[1] Download / install Wine (choose version)"
        echo "[2] Installed versions (switch active)"
        echo "[3] Remove a version"
        echo "[4] Change build type"
        echo "[5] Change architecture"
        echo "[6] Install Wine libraries"
        echo "[7] Test Wine"
        echo "[8] Run a Windows program (.exe)"
        echo "[9] Wine Desktop resolution (now: $(wine_desktop_res))"
        echo "[10] Reset Wine prefix (fixes a silent 'exited with code 1')"
        echo "[11] Map drive D: -> $STORAGE_HOST"
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
            9) wine_choose_desktop_res ;;
            10) wine_reset_prefix ;;
            11) wine_map_drive_now ;;
            0) return ;;
            *) warn "Unknown option." ;;
        esac

        pause

    done
}
