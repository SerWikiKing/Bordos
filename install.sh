#!/data/data/com.termux/files/usr/bin/bash
# ============================================================
# Установка з GitHub + команда `bordos`
#
#   curl -fsSL https://raw.githubusercontent.com/SerWikiKing/Bordos/main/install.sh | bash
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

# Репозиторій (user/repo) — має бути публічним.
DEFAULT_REPO="SerWikiKing/Bordos"
DEFAULT_BRANCH="main"

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
