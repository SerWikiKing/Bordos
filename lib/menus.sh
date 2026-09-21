# shellcheck shell=bash
# ============================================================
# MENUS: START / INSTALLATION / SETTINGS / MAIN
# (меню GPU, BOX, WINE, PROGRAMS живуть у своїх модулях)
# ============================================================

settings() {

    while true; do

        clear

        echo "========== SETTINGS =========="
        echo "[1] GPU / Renderer"
        echo "[2] BOX"
        echo "[3] WINE"
        echo "[4] Scale"
        echo "[5] Show Environment"
        echo "[6] Programs"
        echo "[7] Clear GPU Environment"
        echo "[8] Fix / Repair"
        echo "[0] Back"

        printf "> "
        read -r choice

        case "$choice" in
            1) gpu_menu ;;
            2) box_menu ;;
            3) wine_menu ;;
            4)
                echo
                echo "XFCE scale:"
                echo "Settings Manager -> Appearance -> Fonts -> Custom DPI"
                ;;
            5) show_env ;;
            6) programs ;;
            7) clear_gpu ;;
            8) repair ;;
            0) return ;;
            *) warn "Unknown option." ;;
        esac

        pause

    done
}

start_menu() {

    while true; do

        clear

        echo "========== START =========="
        echo "[1] Install Debian + XFCE4"
        echo "[2] Start XFCE4"
        echo "[3] Start Termux:X11"
        echo "[4] Start PulseAudio"
        echo "[5] Start Terminal"
        echo "[6] Restart XFCE4"
        echo "[0] Back"

        printf "> "
        read -r choice

        case "$choice" in
            1) install_debian ;;
            2) start_xfce ;;
            3) start_x11 ;;
            4) start_pulse ;;
            5) start_terminal ;;
            6) restart_xfce ;;
            0) return ;;
            *) warn "Unknown option." ;;
        esac

        pause

    done
}

installation() {

    while true; do

        clear

        echo "========== INSTALLATION =========="
        echo "[1] Debian + XFCE4"
        echo "[2] Mesa + Vulkan"
        echo "[3] BOX"
        echo "[4] PulseAudio"
        echo "[5] Termux:X11"
        echo "[6] XFCE4 Additional Components"
        echo "[7] WINE"
        echo "[0] Back"

        printf "> "
        read -r choice

        case "$choice" in
            1) install_debian ;;
            2) install_termux ;;
            3) box_menu ;;
            4) pkg install -y pulseaudio ;;
            5) pkg install -y termux-x11-nightly ;;
            6) install_debian ;;
            7) wine_menu ;;
            0) return ;;
            *) warn "Unknown option." ;;
        esac

        pause

    done
}

main() {

    while true; do

        clear

        echo "========== $APP =========="
        echo "[1] START"
        echo "[2] INSTALLATION"
        echo "[3] SETTINGS"
        echo "[4] INSTALLED COMPONENTS"
        echo "[5] GPU / VULKAN TEST"
        echo "[0] EXIT"

        printf "> "
        read -r choice

        case "$choice" in
            1) start_menu ;;
            2) installation ;;
            3) settings ;;
            4)
                components
                pause
                ;;
            5)
                renderer_test
                pause
                ;;
            0) exit 0 ;;
            *)
                warn "Unknown option."
                pause
                ;;
        esac

    done
}
