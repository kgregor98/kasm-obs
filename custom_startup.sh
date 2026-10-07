#!/usr/bin/env bash
# Started by /dockerstartup/vnc_startup.sh. Keeps OBS running: starts it once the desktop is
# ready, and starts it again whenever it exits or crashes.
set -ex

# Extra OBS command-line options from OBS_ARGS, parsed like a shell command line so quoted
# values with spaces work, e.g. OBS_ARGS='--startstreaming --scene "Main Scene"'
ARGS=()
if [ -n "$OBS_ARGS" ]; then
    if ! eval "ARGS=($OBS_ARGS)"; then
        echo "OBS_ARGS could not be parsed, starting OBS without it: $OBS_ARGS" >&2
        ARGS=()
    fi
fi

# /mnt/obs-config used to hold only OBS's "basic" folder (profiles and scene collections).
# It now holds the whole ~/.config/obs-studio, so move an old layout into basic/ once.
migrate_obs_config() {
    local cfg=/mnt/obs-config
    if [ ! -e "$cfg/basic" ] && { [ -d "$cfg/profiles" ] || [ -d "$cfg/scenes" ]; }; then
        echo "Moving old /mnt/obs-config layout into /mnt/obs-config/basic"
        mkdir -p "$cfg/basic" || return 0
        if [ -d "$cfg/profiles" ]; then mv "$cfg/profiles" "$cfg/basic/" || echo "Could not move $cfg/profiles"; fi
        if [ -d "$cfg/scenes" ]; then mv "$cfg/scenes" "$cfg/basic/" || echo "Could not move $cfg/scenes"; fi
    fi
}

# OBS asks "outputs are still active, exit anyway?" when it is closed while streaming or recording.
# OBS's SIGTERM handling goes through the same close path, so the dialog would block "docker stop"
# until Docker kills OBS. Turn it off in user.ini before each start.
# A missing user.ini is only created when there is no global.ini either: OBS migrates a pre-31
# global.ini into user.ini itself and shows an error if user.ini already exists.
disable_exit_confirmation() {
    local dir=$HOME/.config/obs-studio
    local ini=$dir/user.ini
    if [ ! -f "$ini" ]; then
        [ -f "$dir/global.ini" ] && return 0
        printf '[General]\nConfirmOnExit=false\n' > "$ini" || true
        return 0
    fi
    if grep -q '^ConfirmOnExit=' "$ini"; then
        sed -i 's/^ConfirmOnExit=.*/ConfirmOnExit=false/' "$ini" || true
    elif grep -q '^\[General\]' "$ini"; then
        sed -i '/^\[General\]/a ConfirmOnExit=false' "$ini" || true
    else
        printf '\n[General]\nConfirmOnExit=false\n' >> "$ini" || true
    fi
}

# OBS records to $HOME by default, which is not on a volume, so recordings would be lost when the
# container is recreated. Before each start, point every profile's recording path at /recordings
# when it is unset or still the home folder; paths the user chose are left alone.
# On an empty config, pre-create OBS's default "Untitled" profile so the first session records there too.
RECORDINGS_DIR=/recordings

# Sets key=$RECORDINGS_DIR in [section] of an OBS ini file, unless the key already holds another path
set_ini_path() {
    local ini=$1 section=$2 key=$3 tmp
    tmp=$(mktemp) || return 0
    awk -v sec="[$section]" -v key="$key" -v val="$RECORDINGS_DIR" -v home="$HOME" '
        function emit() { if (insec && !done) { print key "=" val; done = 1 } }
        /^\[/ { emit(); insec = ($0 == sec); if (insec) seen = 1 }
        insec && index($0, key "=") == 1 {
            cur = substr($0, length(key) + 2)
            if (cur == "" || cur == home || cur == home "/") print key "=" val; else print
            done = 1
            next
        }
        { print }
        END { emit(); if (!seen) { print ""; print sec; print key "=" val } }
    ' "$ini" > "$tmp" && cat "$tmp" > "$ini"
    rm -f "$tmp"
}

set_recording_path() {
    local profiles=$HOME/.config/obs-studio/basic/profiles ini
    if ! ls "$profiles"/*/basic.ini > /dev/null 2>&1; then
        # basic/scenes too: OBS treats a basic/ folder without it as a very old layout and logs
        # a failed migration of basic/scenes.json
        mkdir -p "$profiles/Untitled" "$HOME/.config/obs-studio/basic/scenes" || return 0
        printf '[General]\nName=Untitled\n' > "$profiles/Untitled/basic.ini" || return 0
    fi
    for ini in "$profiles"/*/basic.ini; do
        set_ini_path "$ini" SimpleOutput FilePath
        set_ini_path "$ini" AdvOut RecFilePath
        set_ini_path "$ini" AdvOut FFFilePath
    done
}

migrate_obs_config

echo "Entering process startup loop"
set +x
while true
do
    if ! pgrep -x obs > /dev/null
    then
        /usr/bin/filter_ready
        /usr/bin/desktop_ready
        # OBS leaves a run_* marker here when it crashes or is killed, and then blocks the next
        # start with a "launch in Safe Mode?" dialog. OBS is not running at this point, so clear them.
        rm -f "$HOME"/.config/obs-studio/.sentinel/run_*
        disable_exit_confirmation
        set_recording_path
        set +e
        obs "${ARGS[@]}"
        set -e
    fi
    sleep 1
done
