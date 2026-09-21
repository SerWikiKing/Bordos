# shellcheck shell=bash
# ============================================================
# BOX64 / BOX86 (x86_64 / x86 емуляція всередині Debian)
# Wine (wine.sh) запускається саме через них.
# ============================================================

install_box64() {

    info "Installing Box64..."

    debian apt-get install -y box64 ||
        true

    if debian_has box64; then
        debian box64 --version ||
            true
    else
        warn "Box64 is not available from the current Debian repository."
    fi
}

install_box86() {

    info "Installing Box86..."

    debian apt-get install -y box86 ||
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

    debian apt-get update

    install_box64
    install_box86
}

box_test() {

    install_debian || return 1

    echo "========== BOX TEST =========="

    if debian_has box64; then
        debian box64 --version
    else
        echo "Box64: not installed."
    fi

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
        echo "[1] Install BOX (Box64 + Box86)"
        echo "[2] Reinstall / Update BOX"
        echo "[3] Test BOX"
        echo "[4] Run a program through BOX"
        echo "[0] Back"

        printf "> "
        read -r choice

        case "$choice" in
            1|2) install_box ;;
            3)   box_test ;;
            4)   run_box ;;
            0)   return ;;
            *)   warn "Unknown option." ;;
        esac

        pause

    done
}
