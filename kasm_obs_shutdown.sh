#!/usr/bin/env bash
# Called from cleanup() in /dockerstartup/vnc_startup.sh when the container is stopped.
# Kasm's cleanup() exits right away, which kills OBS mid-recording. This lets OBS save and
# finish its outputs first. OBS handles SIGTERM by saving everything and quitting.

OBS_STOP_TIMEOUT=${OBS_STOP_TIMEOUT:-20}

# Stop the restart loop first, otherwise it starts OBS again as soon as it exits
pkill -TERM -f /dockerstartup/custom_startup.sh

if pgrep -x obs > /dev/null; then
    echo "kasm-obs: stopping OBS (up to ${OBS_STOP_TIMEOUT}s)"
    pkill -TERM -x obs
    for _ in $(seq 1 "$OBS_STOP_TIMEOUT"); do
        if ! pgrep -x obs > /dev/null; then
            echo "kasm-obs: OBS stopped"
            exit 0
        fi
        sleep 1
    done
    echo "kasm-obs: OBS did not stop within ${OBS_STOP_TIMEOUT}s" >&2
fi
exit 0
