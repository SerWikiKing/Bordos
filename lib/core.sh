# shellcheck shell=bash
# ============================================================
# CORE: шляхи, кольори, повідомлення, config
# ============================================================

APP="Linux Desktop Manager"
BASE="$HOME/.linux-desktop-manager"
CFG="$BASE/config.conf"
LOG="$BASE/logs"
XFCE_LOG="$LOG/xfce.log"
WINE_DESKTOP_LOG="$LOG/wine-desktop.log"

# Внутрішня пам'ять Android — те, що стане диском D: у Wine.
STORAGE_HOST="/storage/emulated/0"

mkdir -p "$BASE" "$LOG"

# Міграція старого config, якщо це був саме файл.
# Стару директорію config НЕ видаляємо.
# (Робиться ДО touch, інакше умова ніколи не спрацює.)
if [ -f "$BASE/config" ] && [ ! -e "$CFG" ]; then
    cp "$BASE/config" "$CFG" 2>/dev/null || true
fi

touch "$CFG"

GREEN='\033[1;32m'
RED='\033[1;31m'
YELLOW='\033[1;33m'
CYAN='\033[1;36m'
RESET='\033[0m'

ok() {
    printf "%b[✓]%b %s\n" "$GREEN" "$RESET" "$*"
}

bad() {
    printf "%b[✗]%b %s\n" "$RED" "$RESET" "$*"
}

info() {
    printf "%b[i]%b %s\n" "$CYAN" "$RESET" "$*"
}

warn() {
    printf "%b[!]%b %s\n" "$YELLOW" "$RESET" "$*"
}

pause() {
    printf "\nPress Enter to continue... "
    read -r _
}

have() {
    command -v "$1" >/dev/null 2>&1
}

# ------------------------------------------------------------
# config.conf (KEY=VALUE)
# ------------------------------------------------------------

cfg_get() {
    local key="$1"
    local default="${2:-}"
    local value

    value="$(
        awk -F= -v k="$key" '
            $1 == k {
                sub(/^[^=]*=/, "")
                print
                exit
            }
        ' "$CFG" 2>/dev/null || true
    )"

    printf '%s' "${value:-$default}"
}

cfg_set() {
    local key="$1"
    local value="$2"
    local tmp="$CFG.tmp"

    awk -F= -v k="$key" -v v="$value" '
        BEGIN {
            found = 0
        }

        $1 == k {
            print k "=" v
            found = 1
            next
        }

        {
            print
        }

        END {
            if (!found)
                print k "=" v
        }
    ' "$CFG" > "$tmp" && mv "$tmp" "$CFG"
}

# ------------------------------------------------------------
# Універсальний вибір зі списку.
# Використання: menu_pick "TITLE" item1 item2 ...
# Результат:    змінна PICKED (порожня, якщо скасовано; return 1)
# ------------------------------------------------------------

menu_pick() {
    local title="$1"
    shift

    local items=("$@")
    local i choice

    PICKED=""

    if [ "${#items[@]}" -eq 0 ]; then
        return 1
    fi

    while true; do
        clear

        echo "========== $title =========="

        for i in "${!items[@]}"; do
            printf "[%d] %s\n" "$((i + 1))" "${items[$i]}"
        done

        echo
        echo "[0] Cancel"

        printf "> "
        read -r choice

        if [ "$choice" = "0" ]; then
            return 1
        fi

        if [[ "$choice" =~ ^[0-9]+$ ]] &&
           [ "$choice" -ge 1 ] &&
           [ "$choice" -le "${#items[@]}" ]; then
            PICKED="${items[$((choice - 1))]}"
            return 0
        fi

        warn "Unknown option."
        sleep 1
    done
}
