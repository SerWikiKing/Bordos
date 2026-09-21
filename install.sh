#!/data/data/com.termux/files/usr/bin/bash
# ============================================================
# Установка з GitHub + команда `bordos`
#
#   curl -fsSL https://raw.githubusercontent.com/USER/REPO/main/install.sh | bash
#
# Після цього:
#   bordos             запустити менеджер
#   bordos update      оновити з GitHub
#   bordos uninstall   видалити програму і команду
#
# Змінні (необов'язково):
#   BORDOS_REPO=user/repo   BORDOS_BRANCH=main   BORDOS_DIR=~/.bordos
# ============================================================
set -eu

# ↓↓↓ ВПИШИ СВІЙ РЕПОЗИТОРІЙ (user/repo) ↓↓↓
DEFAULT_REPO="YOUR_USER/YOUR_REPO"
DEFAULT_BRANCH="main"
# ↑↑↑

APP_DIR="${BORDOS_DIR:-$HOME/.bordos}"
PREFIX_DIR="${PREFIX:-/data/data/com.termux/files/usr}"
BIN="$PREFIX_DIR/bin/bordos"
SAVED="$APP_DIR/.source"
tmp=""

die() {
    printf '[✗] %s\n' "$*" >&2
    exit 1
}

say() {
    printf '[i] %s\n' "$*"
}

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
