#!/data/data/com.termux/files/usr/bin/bash
# Linux Desktop Manager — точка входу.
#
# Модулі (lib/ або поруч з ldm.sh):
#   core.sh      шляхи, кольори, повідомлення, config, menu_pick
#   termux.sh    пакети Termux, Termux:X11, PulseAudio
#   debian.sh    контейнер Debian (proot-distro) + XFCE4
#   gpu.sh       GPU драйвери: Turnip/Zink, VirGL, LLVMpipe, профіль, тест
#   desktop.sh   запуск / перезапуск XFCE4, термінал
#   box.sh       Box64 / Box86
#   wine.sh      Wine: завантаження, вибір версії, запуск
#   programs.sh  додаткові програми (Firefox, Chromium, VLC...)
#   system.sh    repair, environment, installed components
#   menus.sh     всі меню + main
set -u

LDM_ROOT="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"

# Модулі лежать у lib/ або (плоска структура репозиторію) поруч з ldm.sh.
if [ -d "$LDM_ROOT/lib" ]; then
    LDM_LIB="$LDM_ROOT/lib"
else
    LDM_LIB="$LDM_ROOT"
fi

for module in core termux debian gpu desktop box wine programs system menus; do
    file="$LDM_LIB/$module.sh"

    if [ ! -f "$file" ]; then
        echo "Missing module: $file" >&2
        exit 1
    fi

    # shellcheck source=/dev/null
    . "$file"
done

main
main() {

    # Джерело: змінні > збережене з минулого разу > значення зверху.
    local SRC_REPO="" SRC_BRANCH=""

    # shellcheck source=/dev/null
    [ -f "$SAVED" ] && . "$SAVED"

    local repo="${BORDOS_REPO:-${SRC_REPO:-$DEFAULT_REPO}}"
    local branch="${BORDOS_BRANCH:-${SRC_BRANCH:-$DEFAULT_BRANCH}}"

    if [ "$repo" = "YOUR_USER/YOUR_REPO" ]; then
        die "Repository is not set. Edit DEFAULT_REPO in install.sh or run with BORDOS_REPO=user/repo"
    fi

    [[ "$repo" =~ ^[A-Za-z0-9._-]+/[A-Za-z0-9._-]+$ ]] ||
        die "Invalid repository name: $repo (expected user/repo)"

    [[ "$branch" =~ ^[A-Za-z0-9._/-]+$ ]] ||
        die "Invalid branch name: $branch"

    local url="${BORDOS_URL:-https://github.com/${repo}/archive/${branch}.tar.gz}"

    command -v curl >/dev/null 2>&1 || pkg install -y curl || die "curl is required."
    command -v tar  >/dev/null 2>&1 || pkg install -y tar  || die "tar is required."

    tmp="$(mktemp -d "${TMPDIR:-/tmp}/bordos.XXXXXX")"
    trap 'rm -rf "${tmp:-}"' EXIT

    say "Downloading $repo ($branch)..."

    curl -fL --retry 3 -o "$tmp/src.tar.gz" "$url" ||
        die "Download failed. Check the repository name / branch (the repo must be public)."

    mkdir "$tmp/x"

    tar -xzf "$tmp/src.tar.gz" -C "$tmp/x" ||
        die "Could not unpack the archive."

    # ldm.sh може лежати в корені репозиторію або в підпапці.
    local entry root
    entry="$(find "$tmp/x" -maxdepth 3 -type f -name ldm.sh | head -n 1)"

    [ -n "$entry" ] || die "ldm.sh was not found in the repository."

    root="$(dirname "$entry")"

    [ -f "$root/lib/core.sh" ] || die "lib/ folder was not found next to ldm.sh."

    say "Installing to $APP_DIR..."

    rm -rf "$APP_DIR.new" "$APP_DIR.old"
    mkdir -p "$APP_DIR.new"
    cp -a "$root/." "$APP_DIR.new/"

    [ ! -d "$APP_DIR" ] || mv "$APP_DIR" "$APP_DIR.old"
    mv "$APP_DIR.new" "$APP_DIR"
    rm -rf "$APP_DIR.old"

    chmod +x "$APP_DIR/ldm.sh"
    [ ! -f "$APP_DIR/install.sh" ] || chmod +x "$APP_DIR/install.sh"

    # Запам'ятовуємо джерело для `bordos update`.
    printf 'SRC_REPO=%s\nSRC_BRANCH=%s\n' "$repo" "$branch" > "$SAVED"

    # --------------------------------------------------------
    # Команда bordos
    # --------------------------------------------------------

    mkdir -p "$PREFIX_DIR/bin"

    cat > "$BIN" <<'LAUNCHER'
#!/data/data/com.termux/files/usr/bin/bash
APP_DIR="@APP_DIR@"

case "${1:-}" in

    update)
        if [ ! -f "$APP_DIR/install.sh" ]; then
            echo "install.sh is missing in $APP_DIR (add it to your repository)." >&2
            exit 1
        fi
        exec bash "$APP_DIR/install.sh"
        ;;

    uninstall|remove)
        printf "Remove bordos (%s)? Config and Debian stay untouched. [y/N] " "$APP_DIR"
        read -r answer
        case "$answer" in
            y|Y)
                rm -rf "$APP_DIR"
                rm -f "$0"
                echo "Removed."
                ;;
        esac
        exit 0
        ;;

    help|-h|--help)
        echo "bordos            start the manager"
        echo "bordos update     update from GitHub"
        echo "bordos uninstall  remove bordos"
        exit 0
        ;;

    *)
        exec bash "$APP_DIR/ldm.sh" "$@"
        ;;

esac
LAUNCHER

    sed -i "s|@APP_DIR@|$APP_DIR|" "$BIN"
    chmod +x "$BIN"

    printf '[✓] Installed. Run:  bordos\n'
}

main "$@"
