# OBS in your browser

Run OBS Studio in a container and control its desktop interface through your browser using KasmVNC. Intended for server-side streaming with remote feeds, browser sources, overlays, and media files.

## Attribution

This project is based on the original **kasm-obs** container setup by **[cdrage](https://github.com/cdrage)**, from [cdrage/containerfiles](https://github.com/cdrage/containerfiles/tree/master/kasm-obs).

Credit for the original container implementation belongs to cdrage. This repository carries that setup forward with its own builds and container publishing. It is independently maintained and is not an official OBS Studio or Kasm project.

Additional thanks to [OBS Studio](https://obsproject.com/) and [KasmVNC](https://github.com/kasmtech/KasmVNC).

## Container image

```text
ghcr.io/kgregor98/kasm-obs:latest
```

| Tag | Meaning |
| --- | --- |
| `latest` | Newest build of `main`. Rebuilt weekly to pick up OBS and base image updates. |
| `obs-32.2.0` | Newest build that contains that OBS version. |
| `obs-32.2.0-2026.10.07` | The build from that day; pin this for a fixed image. |
| `1.2.3`, `1.2` | Builds of git tags `v1.2.3`, for named releases. |

Every image is smoke-tested (starts, becomes healthy, login works, plugins load, stops cleanly) before it is published.

## Quick start with Compose

Use the [`compose.yaml`](compose.yaml) from this repository (it also lists the optional settings as comments):

```bash
curl -O https://raw.githubusercontent.com/kgregor98/kasm-obs/main/compose.yaml
```

Or create one with the minimal setup:

```yaml
services:
  obs:
    image: ghcr.io/kgregor98/kasm-obs:latest
    container_name: kasm-obs
    restart: unless-stopped
    shm_size: "2gb"
    stop_grace_period: 30s
    ports:
      - "6901:6901"
    volumes:
      - obs-config:/mnt/obs-config
      - obs-media:/media:ro
      - obs-recordings:/recordings

volumes:
  obs-config:
  obs-media:
  obs-recordings:
```

Start OBS:

```bash
docker compose up -d
```

## Run without Compose

```bash
docker run -d \
  --name kasm-obs \
  --restart unless-stopped \
  --shm-size=2g \
  --stop-timeout 30 \
  -p 6901:6901 \
  -v obs-config:/mnt/obs-config \
  -v obs-media:/media:ro \
  -v obs-recordings:/recordings \
  ghcr.io/kgregor98/kasm-obs:latest
```

Docker creates the named volumes automatically. Choose either Compose or `docker run`.

The repository's `compose.yaml` turns the login on by default with user **admin** and password **password**. Change them before exposing the container (see [Security settings](#security-settings)). The `docker run` example and the minimal compose example above have no login.

Open **http://YOUR_SERVER_IP:6901** (or **http://localhost:6901** on the Docker host).

Port 6901 is published on all host interfaces. By default there is no login and no SSL; see [Security settings](#security-settings) to turn them on. For public access, use a reverse proxy with HTTPS, authentication, and WebSocket support.

## Security settings

SSL and the browser login are off by default and are chosen at container start with environment variables:

| Variable | Default | Effect |
| --- | --- | --- |
| `SSL_ENABLED` | unset | `true` (also `1` or `yes`, any case) serves HTTPS only. Any other value or unset serves plain HTTP. |
| `HTTP_USER` | unset | Login username. Must not contain `:`. |
| `HTTP_PASSWORD` | unset | Login password. |

The login is enabled only when both `HTTP_USER` and `HTTP_PASSWORD` are set and non-empty. If only one is set, the login stays off and a warning is written to the container log.

The repository's `compose.yaml` already passes these through from the shell, a `.env` file next to it, or Portainer stack variables. Unset variables become empty, which means off, except the login, which defaults to `admin` / `password`; set `HTTP_USER` to an empty value to turn it off. In a `.env` file, Compose treats `$` as the start of a variable, so `HTTP_PASSWORD=pa$word` arrives as `pa`. Write it as `HTTP_PASSWORD='pa$word'` (single quotes) or `HTTP_PASSWORD=pa$$word`. Values exported in the shell are passed unchanged. If a password with `$` doesn't work in Portainer, use `$$` there too. If you write your own compose file, add an `environment` block to the `obs` service:

```yaml
    environment:
      SSL_ENABLED: "true"
      HTTP_USER: "obs"
      HTTP_PASSWORD: "change-me"
```

With `docker run`, add `-e SSL_ENABLED=true -e HTTP_USER=obs -e HTTP_PASSWORD=change-me`.

- With SSL on, open **https://YOUR_SERVER_IP:6901**. The certificate is self-signed and regenerated at every container start, so the browser shows a warning each time.
- With the login on but SSL off, the browser sends the password unencrypted. Use it only behind a reverse proxy that provides HTTPS.
- If a reverse proxy sits in front and SSL is on, the proxy must connect to the container over HTTPS and accept the self-signed certificate.

## OBS startup options

`OBS_ARGS` passes extra command-line options to OBS every time it starts, including automatic restarts after a crash. Quote values that contain spaces:

```yaml
    environment:
      OBS_ARGS: '--startstreaming --profile "Live" --collection "Main" --scene "Starting Soon"'
```

Useful options: `--startstreaming`, `--startrecording`, `--startreplaybuffer`, `--startvirtualcam`, `--profile`, `--collection`, `--scene`, `--studio-mode`, `--minimize-to-tray`, `--verbose`. If the value can't be parsed (for example an unclosed quote), OBS starts without it and the error is written to the container log.

## Persistent data

| Container path | Purpose |
| --- | --- |
| `/mnt/obs-config` | The whole OBS configuration: profiles, scene collections, app settings, plugin settings (such as obs-websocket), and logs |
| `/media` | Images, videos, and audio used by sources; read-only in this example |
| `/recordings` | Recording output (also replay buffer and screenshots); OBS profiles are pointed here automatically |

`/mnt/obs-config` holds OBS's entire configuration folder (`~/.config/obs-studio`). Volumes from older versions of this image, which held only profiles and scene collections, are moved into `/mnt/obs-config/basic` automatically on first start. Media and recordings require their own mounts. Use stable container paths when configuring sources.

OBS normally records into the home folder, which is not on a volume, so before each OBS start the image sets the recording path of every profile to `/recordings` when it is unset or still the home folder. A path you choose yourself, for example under `/media`, is left alone. A profile created in OBS during a session records to the home folder until OBS restarts, so set its path to `/recordings` when you create it.

Named volumes live on the Docker host under `/var/lib/docker/volumes/<volume name>/_data`; copy media in and recordings out there, or replace a named volume with a host folder (for example `./media:/media:ro`).

Plugins copied into `/mnt/obs-config/plugins` persist, but system packages installed manually in a running container do not. Plugins that need extra packages belong in the image.

The container runs as UID 1000. The image makes `/mnt/obs-config` and `/recordings` writable for that user, so new named volumes work as is; with bind mounts, the host directories must be writable by UID 1000. Back up the configuration volume and any media you need. Stream credentials may be stored in OBS configuration; keep backups private.

`docker compose down` retains the named volumes. **`docker compose down -v` deletes all three volumes.** Compose normally prefixes volume names with the project name; the `docker run` example uses the names directly.

## Operational notes

- OBS runs inside the container on your server. A browser session does not automatically forward your laptop's camera, microphone, or desktop to OBS.
- Stopping the container lets OBS save its settings and finish any recording before it exits (up to 20 seconds, set with `OBS_STOP_TIMEOUT`). Keep Docker's stop timeout above that: `stop_grace_period: 30s` in Compose or `--stop-timeout 30` with `docker run`; Docker's default of 10 seconds can cut a recording short. For this reason the image turns off OBS's "outputs are still active" exit confirmation, which would otherwise block the shutdown.
- Closing the browser leaves the running container intact. Restarting the container interrupts OBS; to resume streaming automatically, set `OBS_ARGS=--startstreaming` (see [OBS startup options](#obs-startup-options)).
- After a crash or container restart, OBS starts normally instead of asking whether to launch in Safe Mode, so it comes back unattended.
- The container uses UTC by default, which affects OBS log times and recording file names. Set `TZ` (for example `TZ=Europe/Warsaw`) to use your local time zone.
- Hardware encoding is not enabled by these examples. See [NVIDIA hardware encoding](#nvidia-hardware-encoding).
- Set OBS sources, encoder, stream destination, and recording paths before starting a broadcast.
- The image has a healthcheck: the container shows as `healthy` in `docker ps` when OBS is running and the web UI port is listening. Docker does not restart unhealthy containers on its own; OBS itself is restarted automatically inside the container if it exits.

## NVIDIA hardware encoding

NVENC needs an NVIDIA GPU and driver on the host and the [NVIDIA Container Toolkit](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/install-guide.html). The toolkit mounts the driver's encode libraries into the container; the image already sets `NVIDIA_DRIVER_CAPABILITIES=compute,video,utility`.

With `docker run`, add `--gpus all`. With Compose, add to the `obs` service:

```yaml
    deploy:
      resources:
        reservations:
          devices:
            - driver: nvidia
              count: all
              capabilities: [gpu]
```

Then select an NVENC encoder in OBS under **Settings → Output**. Without a GPU, OBS logs a harmless `libnvidia-encode.so.1` load error and offers only software encoders.

## License

Released under the MIT License. See [LICENSE](LICENSE).
