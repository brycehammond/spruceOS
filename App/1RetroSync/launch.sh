#!/bin/sh
# 1Retro Sync: syncs RetroArch in-game saves with the 1retro.com cloud.
#
# Spruce's Apps menu runs this through principal.sh after PyUI exits; PyUI
# restarts when it returns. The sync itself is 1Retro's OnionOS client, run
# against a root that makes this card look like an Onion card (see
# oneretroFunctions.sh). Onion's client draws through Onion's infoPanel
# helper, and bin/infoPanel is a stand-in that forwards to spruce's display.
#
# First launch shows a QR code, a device ID and a 4-character code: scan the
# code, or open 1retro.com/device in a browser and enter the device ID, then
# approve on the 1Retro account. Every launch after that syncs straight away.
# Syncing in the background is a separate switch, under Network Settings.

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh
. /mnt/SDCARD/spruce/scripts/network/oneretroFunctions.sh

APP_DIR="$(cd "$(dirname "$0")" && pwd)"
ICON="$APP_DIR/icon.png"

show() {
    display_image_and_text "$ICON" 20 20 "$1" 55
}

trap 'rm -f /tmp/stay_awake' EXIT INT TERM
echo 1 > /tmp/stay_awake
start_pyui_message_writer

if ! check_and_connect_wifi; then
    show "1Retro Sync needs a WiFi connection.\nTurn WiFi on in Network Settings and try again.\n\nPress A to go back."
    acknowledge
    exit 1
fi

if ! oneretro_client_ready; then
    show "Downloading the 1Retro client..."
    if ! oneretro_install_client; then
        show "Could not download the 1Retro client.\nCheck the connection and try again.\n\nPress A to go back."
        acknowledge
        exit 1
    fi
fi

oneretro_prepare_root

# A background watcher and a foreground sync would both be writing the same
# sync state, so the watcher sits this one out.
resume_watcher=0
if oneretro_watcher_running; then
    resume_watcher=1
    stop_oneretro_process
fi

rm -f "$ONERETRO_LAST_MESSAGE"
show "Syncing saves with 1Retro..."

log_message "1Retro Sync: starting foreground sync"
PATH="$APP_DIR/bin:$PATH" "$ONERETRO_BIN" --root "$ONERETRO_ROOT" --state-dir "$ONERETRO_DIR" \
    >"$ONERETRO_DIR/sync.log" 2>&1
rc=$?
log_message "1Retro Sync: client exited with status $rc"

# The client's own closing message, if infoPanel saw one; the status otherwise.
# Its "Press any button to exit." was for Onion's infoPanel, which waited for
# the button; the prompt below is the one that applies here.
final="$(sed -e '/^Press any button to exit\.$/d' "$ONERETRO_LAST_MESSAGE" 2>/dev/null | sed -e :a -e '/^\n*$/{$d;N;ba' -e '}')"
if [ -z "$final" ]; then
    if [ "$rc" -eq 0 ]; then
        final="Sync complete."
    else
        final="Sync failed. The log is in Saves/spruce/1retro/sync.log."
    fi
fi
show "$final\n\nPress A to go back."
acknowledge

[ "$resume_watcher" -eq 1 ] && start_oneretro_process
exit 0
