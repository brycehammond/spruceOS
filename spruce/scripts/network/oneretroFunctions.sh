#!/bin/sh
# 1Retro cloud save sync (https://1retro.com): the paths, the client install
# and the background watcher, shared by App/1RetroSync/launch.sh,
# networkservices.sh and networkServiceToggle.sh.
#
# The client is 1Retro's own OnionOS build. Onion keeps ROMs in Roms/<SYSTEM>/
# and RetroArch's per-core saves in Saves/CurrentProfile/saves/<core>/, which
# is spruce's layout (Roms/<SYSTEM>/, Saves/saves/<core>/) one folder deeper,
# so the client is pointed at a root of symlinks that makes this card look
# like an Onion card. It is a static 32-bit ARM binary: native on the armhf
# devices, and on the aarch64 ones it needs the kernel's 32-bit support, the
# same thing RetroArch32 relies on.
#
# The binary is fetched on first use rather than shipped in the repo: 1Retro
# distributes it for use with a 1Retro account, through its own download
# service, which also keeps us on their latest release.
. /mnt/SDCARD/spruce/scripts/helperFunctions.sh

# Login, sync state and logs live here, so they survive a spruce update.
ONERETRO_DIR="/mnt/SDCARD/Saves/spruce/1retro"
ONERETRO_BIN="$ONERETRO_DIR/bin/1retro-onionos"
# shellcheck disable=SC2034  # read by App/1RetroSync/launch.sh and bin/infoPanel
ONERETRO_LAST_MESSAGE="$ONERETRO_DIR/last_message"
ONERETRO_ROOT="/tmp/1retro-root"
ONERETRO_URL="https://api.1retro.com/v1/downloads/latest/1retro-onionos/1RetroSync.zip"
# The watcher's command line, as pgrep -f sees it. A foreground sync from the
# app runs the same binary without --watch, so this never matches that.
ONERETRO_WATCH_PATTERN="1retro-onionos .*--watch"

oneretro_client_ready() {
    [ -x "$ONERETRO_BIN" ]
}

# The symlink root goes on tmpfs because the SD card's FAT filesystem cannot
# hold symlinks. Rebuilt on every use: /tmp does not survive a reboot.
oneretro_prepare_root() {
    mkdir -p "$ONERETRO_ROOT/Saves/CurrentProfile"
    ln -sfn /mnt/SDCARD/Roms "$ONERETRO_ROOT/Roms"
    ln -sfn /mnt/SDCARD/Saves/saves "$ONERETRO_ROOT/Saves/CurrentProfile/saves"
}

# Downloads 1Retro's OnionOS package and keeps its binary. Needs a network.
oneretro_install_client() {
    tmp="$ONERETRO_DIR/tmp"
    rm -rf "$tmp"
    mkdir -p "$tmp" "$ONERETRO_DIR/bin"

    if ! download_url_to_file "$ONERETRO_URL" "$tmp/1RetroSync.zip"; then
        log_message "1Retro: could not download the client from $ONERETRO_URL"
        rm -rf "$tmp"
        return 1
    fi

    # The zip holds Onion's App/1RetroSync/ folder; its launcher, icon and
    # config.json are Onion's, and only the binary is wanted here.
    if ! "$(get_python_path)" -m zipfile -e "$tmp/1RetroSync.zip" "$tmp" \
        || [ ! -f "$tmp/App/1RetroSync/1retro-onionos" ]; then
        log_message "1Retro: downloaded package did not unpack to App/1RetroSync/1retro-onionos"
        rm -rf "$tmp"
        return 1
    fi

    mv -f "$tmp/App/1RetroSync/1retro-onionos" "$ONERETRO_BIN"
    chmod +x "$ONERETRO_BIN"
    rm -rf "$tmp"
    sync
    log_message "1Retro: client installed at $ONERETRO_BIN"
    return 0
}

oneretro_watcher_running() {
    pgrep -f "$ONERETRO_WATCH_PATTERN" >/dev/null
}

# Background sync: uploads a save as RetroArch writes it and pulls down saves
# made on other devices. Only worth running on WiFi, which is why it is a
# network service. It has no screen of its own; a device that has not been
# paired yet just logs that and exits.
start_oneretro_process() {
    if ! oneretro_client_ready; then
        log_message "1Retro: client not installed; open the 1Retro Sync app once to set it up"
        return 1
    fi
    if oneretro_watcher_running; then
        return 0
    fi
    oneretro_prepare_root
    # Saves are picked up the moment they are written; the interval is only
    # the safety sweep, so it can be long for the battery's sake.
    "$ONERETRO_BIN" --root "$ONERETRO_ROOT" --state-dir "$ONERETRO_DIR" \
        --watch --watch-interval 300 >"$ONERETRO_DIR/watch.log" 2>&1 &
    log_message "1Retro: background watcher started"
}

stop_oneretro_process() {
    if oneretro_watcher_running; then
        pkill -f "$ONERETRO_WATCH_PATTERN"
        log_message "1Retro: background watcher stopped"
    fi
}
