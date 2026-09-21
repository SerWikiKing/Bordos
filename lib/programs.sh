# shellcheck shell=bash
# ============================================================
# PROGRAMS: додаткові програми всередині Debian
# ============================================================

programs_mark() {
    # programs_mark <command> <label>
    if debian_has "$1"; then
        echo "[✓] $2"
    else
        echo "[ ] $2"
    fi
}

programs() {

    install_debian || return 1

    while true; do

        clear

        echo "========== PROGRAMS =========="

        echo "[1] $(programs_mark firefox-esr "Firefox ESR")"
        echo "[2] $(programs_mark chromium "Chromium")"
        echo "[3] $(programs_mark vlc "VLC")"
        echo "[4] $(programs_mark thunar "Thunar")"

        echo
        echo "[0] Back"

        printf "> "
        read -r choice

        case "$choice" in
            1) debian apt-get install -y firefox-esr ;;
            2) debian apt-get install -y chromium ;;
            3) debian apt-get install -y vlc ;;
            4) debian apt-get install -y thunar ;;
            0) return ;;
            *) warn "Unknown option." ;;
        esac

        pause

    done
}
