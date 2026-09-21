# shellcheck shell=bash
# ============================================================
# GPU: Turnip + Zink, VirGL, LLVMpipe, Auto
# ============================================================

gpu_mode() {
    cfg_get GPU_MODE turnip
}

gpu_name() {
    case "$(gpu_mode)" in
        turnip) echo "Turnip + Zink" ;;
        virgl)  echo "VirGL" ;;
        llvm)   echo "LLVMpipe" ;;
        *)      echo "Auto" ;;
    esac
}

# Termux-частина: mesa + vulkan (викликається з install_termux)
gpu_install_termux_pkgs() {
    pkg install -y \
        mesa \
        mesa-vulkan-icd-freedreno \
        mesa-vulkan-icd-swrast \
        vulkan-loader-generic \
        vulkan-tools
}

# ------------------------------------------------------------
# DEBIAN TURNIP / FREEDRENO
# ------------------------------------------------------------

freedreno_ok() {

    debian bash -s >/dev/null 2>&1 <<'CHECK'

test -f \
/opt/mesa-freedreno/share/vulkan/icd.d/freedreno_icd.aarch64.json

test -f \
/opt/mesa-freedreno/lib/aarch64-linux-gnu/libvulkan_freedreno.so

test -f \
/opt/mesa-freedreno/lib/aarch64-linux-gnu/dri/zink_dri.so

CHECK

}

install_freedreno() {

    install_debian || return 1

    if freedreno_ok; then
        ok "Debian Turnip/Freedreno already installed."
        return 0
    fi

    local version="26.3.0-devel-20260824"
    local url="https://github.com/sabamdarif/termux-desktop/releases/download/mesa-freedreno-${version}/mesa-freedreno-${version}-aarch64.zip"
    local zip="$HOME/mesa-freedreno-${version}.zip"

    info "Installing Debian-side Turnip/Freedreno..."

    have curl || pkg install -y curl || return 1
    have unzip || pkg install -y unzip || return 1

    rm -f "$zip"

    curl \
        -fL \
        --retry 3 \
        -o "$zip" \
        "$url" || {
        bad "Could not download Debian-side Mesa Freedreno."
        return 1
    }

    debian bash -s <<EOF

set -e

apt-get install -y \
    xdg-desktop-portal \
    libgl1 \
    libgl1-mesa-dri \
    libvulkan1 \
    mesa-vulkan-drivers \
    unzip

unzip -o '$zip' -d /

ldconfig || true

EOF

    local result=$?

    rm -f "$zip"

    if [ "$result" -ne 0 ]; then
        bad "Turnip/Freedreno installation failed."
        return 1
    fi

    if ! freedreno_ok; then
        bad "Turnip/Freedreno files were not found."
        return 1
    fi

    ok "Debian Turnip/Freedreno installed."
}

# ------------------------------------------------------------
# VIRGL
# ------------------------------------------------------------

start_virgl() {

    if ! have virgl_test_server_android; then
        info "Installing VirGL..."
        pkg install -y virglrenderer-android || return 1
    fi

    pkill -x virgl_test_server_android \
        >/dev/null 2>&1 || true

    rm -f "$PREFIX/tmp/.virgl_test" \
        >/dev/null 2>&1 || true

    info "Starting VirGL server..."

    VTEST_SOCK="$PREFIX/tmp/.virgl_test" \
        virgl_test_server_android \
        >/dev/null 2>&1 &

    sleep 2

    if [ -S "$PREFIX/tmp/.virgl_test" ] ||
       pgrep -x virgl_test_server_android >/dev/null 2>&1; then
        ok "VirGL server started."
        return 0
    fi

    bad "VirGL server failed to start."
    return 1
}

# ------------------------------------------------------------
# GPU PROFILE (/etc/profile.d/linux-manager-gpu.sh всередині Debian)
# ------------------------------------------------------------

write_profile() {

    local mode
    mode="$(gpu_mode)"

    local tmp="$BASE/gpu-profile.tmp"

    case "$mode" in

        turnip)

            cat > "$tmp" <<'PROFILE'

# Linux Desktop Manager
# Turnip + Zink

export VK_ICD_FILENAMES=/opt/mesa-freedreno/share/vulkan/icd.d/freedreno_icd.aarch64.json

export LD_LIBRARY_PATH=/opt/mesa-freedreno/lib/aarch64-linux-gnu${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}

export LIBGL_DRIVERS_PATH=/opt/mesa-freedreno/lib/aarch64-linux-gnu/dri

export MESA_LOADER_DRIVER_OVERRIDE=zink

export TU_DEBUG=noconform

unset GALLIUM_DRIVER
unset VTEST_SOCK
unset MESA_NO_ERROR
unset MESA_GL_VERSION_OVERRIDE
unset MESA_GLES_VERSION_OVERRIDE
unset LIBGL_DRI3_DISABLE
unset LIBGL_ALWAYS_SOFTWARE

PROFILE

            ;;

        virgl)

            cat > "$tmp" <<'PROFILE'

# Linux Desktop Manager
# VirGL

export GALLIUM_DRIVER=virpipe

export VTEST_SOCK=/tmp/.virgl_test

export MESA_NO_ERROR=1

export MESA_GL_VERSION_OVERRIDE=4.3COMPAT

export MESA_GLES_VERSION_OVERRIDE=3.2

export LIBGL_DRI3_DISABLE=1

unset VK_ICD_FILENAMES
unset MESA_LOADER_DRIVER_OVERRIDE
unset TU_DEBUG
unset LD_LIBRARY_PATH
unset LIBGL_DRIVERS_PATH
unset LIBGL_ALWAYS_SOFTWARE

PROFILE

            ;;

        llvm)

            cat > "$tmp" <<'PROFILE'

# Linux Desktop Manager
# LLVMpipe

export LIBGL_ALWAYS_SOFTWARE=1

export MESA_LOADER_DRIVER_OVERRIDE=llvmpipe

export GALLIUM_DRIVER=llvmpipe

unset VK_ICD_FILENAMES
unset LD_LIBRARY_PATH
unset LIBGL_DRIVERS_PATH
unset TU_DEBUG
unset VTEST_SOCK

PROFILE

            ;;

        *)

            cat > "$tmp" <<'PROFILE'

# Linux Desktop Manager
# Auto

unset VK_ICD_FILENAMES
unset LD_LIBRARY_PATH
unset LIBGL_DRIVERS_PATH
unset MESA_LOADER_DRIVER_OVERRIDE
unset TU_DEBUG
unset GALLIUM_DRIVER
unset VTEST_SOCK
unset MESA_NO_ERROR
unset MESA_GL_VERSION_OVERRIDE
unset MESA_GLES_VERSION_OVERRIDE
unset LIBGL_DRI3_DISABLE
unset LIBGL_ALWAYS_SOFTWARE

PROFILE

            ;;

    esac

    local content

    content="$(cat "$tmp")"

    debian bash -s <<EOF

cat > /etc/profile.d/linux-manager-gpu.sh <<'PROFILE'
$content
PROFILE

chmod 644 /etc/profile.d/linux-manager-gpu.sh

EOF

    local result=$?

    rm -f "$tmp"

    if [ "$result" -ne 0 ]; then
        bad "Could not write GPU profile."
        return 1
    fi

    # Захист від старої помилки \nexport
    if debian grep -q '\\nexport' \
        /etc/profile.d/linux-manager-gpu.sh \
        2>/dev/null; then
        bad "GPU profile is corrupted."
        return 1
    fi

    ok "GPU profile: $(gpu_name)"
}

# ------------------------------------------------------------
# SET GPU
# ------------------------------------------------------------

set_gpu() {

    local new="$1"
    local old

    old="$(gpu_mode)"

    cfg_set GPU_MODE "$new"

    case "$new" in

        turnip)
            install_freedreno || {
                cfg_set GPU_MODE "$old"
                write_profile >/dev/null 2>&1 || true
                return 1
            }
            ;;

        virgl)
            start_virgl || {
                cfg_set GPU_MODE "$old"
                write_profile >/dev/null 2>&1 || true
                return 1
            }
            ;;

    esac

    write_profile || {
        cfg_set GPU_MODE "$old"
        write_profile >/dev/null 2>&1 || true
        bad "GPU setup failed. Previous mode restored."
        return 1
    }

    ok "GPU mode: $(gpu_name)"
}

# ------------------------------------------------------------
# CLEAR GPU
# ------------------------------------------------------------

clear_gpu() {

    debian rm \
        -f \
        /etc/profile.d/linux-manager-gpu.sh \
        >/dev/null 2>&1 ||
        true

    cfg_set GPU_MODE auto

    ok "GPU environment cleared."
}

# ------------------------------------------------------------
# GPU TEST
# ------------------------------------------------------------

renderer_test() {

    install_debian || return 1

    write_profile || return 1

    echo
    echo "========== GPU / RENDERER TEST =========="

    debian bash -s <<'TEST'

. /etc/profile.d/linux-manager-gpu.sh


echo "GPU environment:"

env |
    grep -E \
    '^(VK_ICD|LD_LIBRARY_PATH|LIBGL_DRIVERS_PATH|MESA_|GALLIUM_DRIVER|VTEST_SOCK)' |
    sort ||
    true


echo

echo "OpenGL:"


if command -v glmark2 >/dev/null 2>&1; then

    timeout 15 \
        glmark2 --off-screen 2>&1 |
        grep -E \
        'GL_RENDERER|GL_VERSION|GL_VENDOR|Error|failed' ||
        true

else

    glxinfo -B 2>&1 |
        grep -E \
        'OpenGL vendor|OpenGL renderer|OpenGL version|Error|failed' ||
        true

fi


echo

echo "Vulkan:"


if command -v vulkaninfo >/dev/null 2>&1; then

    timeout 15 \
        vulkaninfo --summary 2>&1 |
        grep -E \
        'GPU[0-9]|deviceName|driverName|driverInfo|ERROR|error' |
        head -30 ||
        true

else

    echo "vulkaninfo is not installed."

fi

TEST

    echo
    echo "=========================================="
}

freedreno_version() {

    echo
    echo "========== FREEDRENO =========="

    debian bash -s <<'VERSION'

if [ -f \
/opt/mesa-freedreno/lib/aarch64-linux-gnu/libvulkan_freedreno.so ]; then

    strings \
        /opt/mesa-freedreno/lib/aarch64-linux-gnu/libvulkan_freedreno.so \
        2>/dev/null |
        grep -m1 -E 'Mesa|26\.[0-9]' ||
        true


    echo

    echo "ICD:"

    echo "/opt/mesa-freedreno/share/vulkan/icd.d/freedreno_icd.aarch64.json"


    echo

    echo "Zink:"

    echo "/opt/mesa-freedreno/lib/aarch64-linux-gnu/dri/zink_dri.so"

else

    echo "Debian-side Freedreno is not installed."

fi

VERSION

    echo "================================"
}

# ------------------------------------------------------------
# GPU MENU
# ------------------------------------------------------------

gpu_menu() {

    while true; do

        clear

        echo "========== GPU / VULKAN =========="
        echo "Current: $(gpu_name)"
        echo
        echo "[1] Turnip + Zink"
        echo "[2] VirGL"
        echo "[3] LLVMpipe"
        echo "[4] Auto"
        echo "[5] Test Renderer"
        echo "[6] Freedreno Version"
        echo "[0] Back"

        printf "> "
        read -r choice

        case "$choice" in
            1) set_gpu turnip ;;
            2) set_gpu virgl ;;
            3) set_gpu llvm ;;
            4) set_gpu auto ;;
            5) renderer_test ;;
            6) freedreno_version ;;
            0) return ;;
            *) warn "Unknown option." ;;
        esac

        pause

    done
}
