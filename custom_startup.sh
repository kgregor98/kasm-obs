#!/usr/bin/env bash
set -ex
START_COMMAND="obs"
PGREP="obs"

# Extra OBS command-line options from OBS_ARGS, parsed like a shell command line so quoted
# values with spaces work, e.g. OBS_ARGS='--startstreaming --scene "Main Scene"'
ARGS=()
if [ -n "$OBS_ARGS" ]; then
    if ! eval "ARGS=($OBS_ARGS)"; then
        echo "OBS_ARGS could not be parsed, starting OBS without it: $OBS_ARGS" >&2
        ARGS=()
    fi
fi

options=$(getopt -o gau: -l go,assign,url: -n "$0" -- "$@") || exit
eval set -- "$options"

while [[ $1 != -- ]]; do
    case $1 in
        -g|--go) GO='true'; shift 1;;
        -a|--assign) ASSIGN='true'; shift 1;;
        -u|--url) OPT_URL=$2; shift 2;;
        *) echo "bad option: $1" >&2; exit 1;;
    esac
done
shift

# Process non-option arguments.
for arg; do
    echo "arg! $arg"
done

FORCE=$2

kasm_exec() {
    if [ -n "$OPT_URL" ] ; then
        URL=$OPT_URL
    elif [ -n "$1" ] ; then
        URL=$1
    fi 
    
    # Since we are execing into a container that already has the browser running from startup, 
    #  when we don't have a URL to open we want to do nothing. Otherwise a second browser instance would open. 
    if [ -n "$URL" ] ; then
        /usr/bin/filter_ready
        /usr/bin/desktop_ready
        $START_COMMAND "${ARGS[@]}" $OPT_URL
    else
        echo "No URL specified for exec command. Doing nothing."
    fi
}

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

kasm_startup() {
    if [ -n "$KASM_URL" ] ; then
        URL=$KASM_URL
    elif [ -z "$URL" ] ; then
        URL=$LAUNCH_URL
    fi

    if [ -z "$DISABLE_CUSTOM_STARTUP" ] ||  [ -n "$FORCE" ] ; then

        migrate_obs_config

        echo "Entering process startup loop"
        set +x
        while true
        do
            if ! pgrep -x $PGREP > /dev/null
            then
                /usr/bin/filter_ready
                /usr/bin/desktop_ready
                # OBS leaves a run_* marker here when it crashes or is killed, and then blocks the next
                # start with a "launch in Safe Mode?" dialog. OBS is not running at this point, so clear them.
                rm -f "$HOME"/.config/obs-studio/.sentinel/run_*
                disable_exit_confirmation
                set +e
                $START_COMMAND "${ARGS[@]}" $URL
                set -e
            fi
            sleep 1
        done
        set -x
    
    fi

} 

if [ -n "$GO" ] || [ -n "$ASSIGN" ] ; then
    kasm_exec
else
    kasm_startup
fi
