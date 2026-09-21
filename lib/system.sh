# shellcheck shell=bash
# ============================================================
# SYSTEM: repair, environment, installed components
# ============================================================

repair() {

    echo "========== REPAIR =========="

    echo "Step 1/7: Termux packages..."

    install_termux || true

    echo "Step 2/7: Debian..."

    install_debian || return 1

    echo "Step 3/7: GPU..."

    case "$(gpu_mode)" in
        turnip) install_freedreno || true ;;
        virgl)  start_virgl || true ;;
    esac

    echo "Step 4/7: GPU profile..."

    write_profile || true

    echo "Step 5/7: X11..."

    start_x11 || true

    echo "Step 6/7: Wine launchers..."

    if [ "$(cfg_get WINE_ACTIVE)" != "" ]; then
        wine_write_wrappers || true
    else
        info "No active Wine build, skipping."
    fi

    echo "Step 7/7: Renderer test..."

    renderer_test
}

show_env() {

    clear

    echo "========== ENVIRONMENT =========="

    echo

    echo "GPU mode: $(gpu_name)"

    echo "Wine: $(wine_active_name) ($(wine_type), $(wine_arch))"

    echo "Config: $CFG"

    echo

    debian bash -s <<'ENV'

if [ -f /etc/profile.d/linux-manager-gpu.sh ]; then

    cat /etc/profile.d/linux-manager-gpu.sh

else

    echo "No GPU profile installed."

fi

ENV
}

components() {

    clear

    echo "========== INSTALLED COMPONENTS =========="

    if debian_exists; then
        ok "Debian"
    else
        bad "Debian"
    fi

    if have termux-x11; then
        ok "Termux:X11"
    else
        bad "Termux:X11"
    fi

    if have pulseaudio; then
        ok "PulseAudio"
    else
        bad "PulseAudio"
    fi

    if have vulkaninfo; then
        ok "Vulkan tools"
    else
        bad "Vulkan tools"
    fi

    if have virgl_test_server_android; then
        ok "VirGL"
    else
        info "VirGL: not installed"
    fi

    if freedreno_ok; then
        ok "Debian Turnip/Freedreno"
    else
        info "Debian Turnip/Freedreno: not installed"
    fi

    if debian_exists; then

        if debian_has box64; then
            ok "Box64"
        else
            info "Box64: not installed"
        fi

        if debian_has box86; then
            ok "Box86"
        else
            info "Box86: not installed"
        fi

    fi

    if [ "$(cfg_get WINE_ACTIVE)" != "" ]; then
        ok "Wine: $(wine_active_name)"
    else
        info "Wine: not installed"
    fi

    echo

    echo "GPU mode: $(gpu_name)"
}
