# shellcheck shell=bash
# ============================================================
# BOX64 / BOX86 (x86_64 / x86 емуляція всередині Debian)
# Wine (wine.sh) запускається саме через них.
#
# Пакет box64/box86 з репозиторіїв Debian trixie сильно відстає від
# ptitSeb/box64 і не вміє запускати нові збірки Wine (10.x/11.x, які
# повністю перейшли на новий WoW64 без preloader): одразу після
# "Warning, Symbol wine_main_preload_info not found" Wine Desktop
# падає. Тому перед встановленням додаємо репозиторії
# ryanfortner/box64-debs і ryanfortner/box86-debs (свіжі збірки з
# master раз на добу).
#
# У кожному з цих репозиторіїв є декілька збірок під конкретне
# залізо (generic / Raspberry Pi / Rockchip / Tegra / Snapdragon...) —
# вони не сумісні одна з одною (conflicts), але всі дають ту саму
# команду box64 / box86. Це два повністю окремі вибори:
# BOX64_VARIANT (64-біт, для запуску x86_64 Wine) і BOX86_VARIANT
# (32-біт, для x86 Wine / 32-бітних застосунків) — версія (дата
# збірки) у них спільна лише тому, що обидва репозиторії оновлюються
# щодня з відповідного апстріму, а не бо це один пакет.
# ============================================================

BOX64_DEBS_URL="https://ryanfortner.github.io/box64-debs"
BOX86_DEBS_URL="https://ryanfortner.github.io/box86-debs"

# "значення (опис)" — так само, як WINE_TYPE / WINE_ARCH у wine.sh.
BOX64_VARIANTS=(
    "box64 (Generic ARM64 — default, works almost everywhere)"
    "box64-rpi3arm64 (Raspberry Pi 3, ARM64)"
    "box64-rpi4arm64 (Raspberry Pi 4 / 5, ARM64)"
    "box64-rk3399 (Rockchip RK3399)"
    "box64-rk3588 (Rockchip RK3588)"
    "box64-tegrax1 (Nvidia Tegra X1)"
    "box64-android (Generic ARM64, built with BAD_SIGNAL — try this if the default crashes on your phone)"
)

BOX86_VARIANTS=(
    "box86-generic-arm (Generic ARM — default, works almost everywhere)"
    "box86-rpi3arm64 (Raspberry Pi 3)"
    "box86-rpi4arm64 (Raspberry Pi 4 / 5)"
    "box86-rk3399 (Rockchip RK3399)"
    "box86-rk3588 (Rockchip RK3588)"
    "box86-tegrax1 (Nvidia Tegra X1)"
    "box86-sd845 (Snapdragon 845)"
    "box86-sd888 (Snapdragon 888)"
    "box86-android (Generic ARM, built with BAD_SIGNAL — try this if the default crashes on your phone)"
)

box64_variant() {
    cfg_get BOX64_VARIANT box64
}

box86_variant() {
    # Плаский пакет "box86" — це лише віртуальний пакет без кандидата
    # для встановлення; потрібен конкретний target-пакет.
    cfg_get BOX86_VARIANT box86-generic-arm
}

box64_choose_variant() {
    menu_pick "BOX64 BUILD (now: $(box64_variant))" "${BOX64_VARIANTS[@]}" ||
        return 0

    cfg_set BOX64_VARIANT "${PICKED%% *}"

    ok "Box64 build: $(box64_variant)"
}

box86_choose_variant() {
    menu_pick "BOX86 BUILD (now: $(box86_variant))" "${BOX86_VARIANTS[@]}" ||
        return 0

    cfg_set BOX86_VARIANT "${PICKED%% *}"

    ok "Box86 build: $(box86_variant)"
}

box64_add_repo() {
    debian bash -s <<REPO
set -e
command -v gpg >/dev/null 2>&1 || apt-get install -y gnupg
mkdir -p /etc/apt/trusted.gpg.d
curl -fsSL "$BOX64_DEBS_URL/box64.list" -o /etc/apt/sources.list.d/box64.list
curl -fsSL "$BOX64_DEBS_URL/KEY.gpg" |
    gpg --dearmor -o /etc/apt/trusted.gpg.d/box64-debs-archive-keyring.gpg
REPO
}

box86_add_repo() {
    debian bash -s <<REPO
set -e
command -v gpg >/dev/null 2>&1 || apt-get install -y gnupg
mkdir -p /etc/apt/trusted.gpg.d
curl -fsSL "$BOX86_DEBS_URL/box86.list" -o /etc/apt/sources.list.d/box86.list
curl -fsSL "$BOX86_DEBS_URL/KEY.gpg" |
    gpg --dearmor -o /etc/apt/trusted.gpg.d/box86-debs-archive-keyring.gpg
REPO
}

install_box64() {

    local pkg
    pkg="$(box64_variant)"

    info "Installing Box64 ($pkg)..."

    debian apt-get install -y "$pkg" ||
        true

    if debian_has box64; then
        debian box64 --version ||
            true
    else
        warn "Box64 is not available from the current Debian repository."
    fi
}

install_box86() {

    local pkg
    pkg="$(box86_variant)"

    info "Installing Box86 ($pkg)..."

    debian apt-get install -y "$pkg" ||
        true

    if debian_has box86; then
        debian box86 --version ||
            true
    else
        warn "Box86 is not available from the current Debian repository."
    fi
}

install_box() {

    install_debian || return 1

    echo
    echo "Installing Box64 / Box86..."

    box64_add_repo ||
        warn "Could not add the box64-debs repository, falling back to the Debian package."
    box86_add_repo ||
        warn "Could not add the box86-debs repository, falling back to the Debian package."

    debian apt-get update

    install_box64
    install_box86
}

box_test() {

    install_debian || return 1

    echo "========== BOX TEST =========="

    echo "Box64 build (config): $(box64_variant)"
    if debian_has box64; then
        debian box64 --version
    else
        echo "Box64: not installed."
    fi

    echo
    echo "Box86 build (config): $(box86_variant)"
    if debian_has box86; then
        debian box86 --version
    else
        echo "Box86: not installed."
    fi

    echo "=============================="
}

run_box() {

    install_debian || return 1

    menu_pick "EMULATOR" "box64 (x86_64)" "box86 (x86)" || return 0

    local emu="${PICKED%% *}"
    local program

    printf "Path to program inside Debian: "
    read -r program

    [ -n "$program" ] ||
        return 0

    debian bash -lc \
        '. /etc/profile.d/linux-manager-gpu.sh 2>/dev/null || true; exec "$1" "$2"' \
        bash \
        "$emu" \
        "$program"
}

# ------------------------------------------------------------
# BOX MENU
# ------------------------------------------------------------

box_menu() {

    while true; do

        clear

        echo "========== BOX =========="
        echo "Box64 build: $(box64_variant)"
        echo "Box86 build: $(box86_variant)"
        echo
        echo "[1] Install BOX (Box64 + Box86)"
        echo "[2] Reinstall / Update BOX"
        echo "[3] Test BOX"
        echo "[4] Run a program through BOX"
        echo "[5] Choose Box64 build (target hardware)"
        echo "[6] Choose Box86 build (target hardware)"
        echo "[0] Back"

        printf "> "
        read -r choice

        case "$choice" in
            1|2) install_box ;;
            3)   box_test ;;
            4)   run_box ;;
            5)   box64_choose_variant ;;
            6)   box86_choose_variant ;;
            0)   return ;;
            *)   warn "Unknown option." ;;
        esac

        pause

    done
}
