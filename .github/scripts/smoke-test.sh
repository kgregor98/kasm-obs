#!/usr/bin/env bash
# Smoke test for a freshly built image, run by the publish workflow before anything is pushed.
# Usage: smoke-test.sh <image>
set -euo pipefail

IMAGE=${1:?usage: smoke-test.sh <image>}
NAME=kasm-obs-smoke
PORT=16901
LOGIN_USER=smoke
PASS='smoke$pass word'

fail() {
    echo "::error::$*"
    echo "---- container log ----"
    docker logs "$NAME" 2>&1 | tail -100 || true
    echo "---- OBS log ----"
    docker exec "$NAME" bash -c 'tail -60 "$(ls -t ~/.config/obs-studio/logs/*.txt | head -1)"' 2>&1 || true
    exit 1
}
cleanup() { docker rm -f "$NAME" > /dev/null 2>&1 || true; }
trap cleanup EXIT

docker run -d --name "$NAME" --shm-size=2g --stop-timeout 30 -p "$PORT:6901" \
    -e HTTP_USER="$LOGIN_USER" -e HTTP_PASSWORD="$PASS" "$IMAGE" > /dev/null

echo "Waiting for the container to become healthy"
for _ in $(seq 1 60); do
    status=$(docker inspect -f '{{.State.Health.Status}}' "$NAME" 2>/dev/null || echo missing)
    case "$status" in
        healthy) break ;;
        unhealthy|missing) fail "container is $status" ;;
    esac
    [ "$(docker inspect -f '{{.State.Running}}' "$NAME")" = true ] || fail "container exited"
    sleep 5
done
[ "$status" = healthy ] || fail "container not healthy after 5 minutes (status: $status)"
echo "OK: healthy"

code=$(curl -s -o /dev/null -w '%{http_code}' "http://localhost:$PORT/")
[ "$code" = 401 ] || fail "web UI without login returned $code, expected 401"
code=$(curl -s -o /dev/null -w '%{http_code}' -u "$LOGIN_USER:$PASS" "http://localhost:$PORT/")
[ "$code" = 200 ] || fail "web UI with login returned $code, expected 200"
echo "OK: login required, credentials accepted"

obs_log=$(docker exec "$NAME" bash -c 'cat "$(ls -t ~/.config/obs-studio/logs/*.txt | head -1)"')
grep -q '\[droidcam-obs\] module loaded' <<< "$obs_log" || fail "DroidCam plugin not loaded"
grep -q 'VLC video source enabled' <<< "$obs_log" || fail "VLC video source not enabled"
echo "OK: DroidCam and VLC loaded"

docker exec "$NAME" grep -qx 'FilePath=/recordings' /mnt/obs-config/basic/profiles/Untitled/basic.ini \
    || fail "recording path not set to /recordings"
echo "OK: recordings go to /recordings"

if docker logs "$NAME" 2>&1 | grep -q 'Restarting Audio Out'; then
    fail "Kasm audio service is restarting"
fi
echo "OK: no audio service restarts"

docker stop "$NAME" > /dev/null
docker logs "$NAME" 2>&1 | grep -q 'kasm-obs: OBS stopped' || fail "OBS did not stop cleanly on docker stop"
echo "OK: clean shutdown"

echo "Smoke test passed"
