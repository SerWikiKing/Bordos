#!/data/data/com.termux/files/usr/bin/bash
# Linux Desktop Manager — точка входу.
#
# Модулі (lib/):
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

for module in core termux debian gpu desktop box wine programs system menus; do
    file="$LDM_ROOT/lib/$module.sh"

    if [ ! -f "$file" ]; then
        echo "Missing module: $file" >&2
        exit 1
    fi

    # shellcheck source=/dev/null
    . "$file"
done

main
