# OBS in your browser

Run OBS Studio in a container and control its desktop interface through your browser using KasmVNC. Intended for server-side streaming with remote feeds, browser sources, overlays, and media files.

## What's included

- OBS Studio 32 from the official OBS Studio PPA, on Kasm's Ubuntu 24.04 desktop image
- DroidCam plugin 2.5.1, to use a phone as a camera over the network (the phone must be reachable from the server, for example on the same network or a VPN)
- VLC video source
- NVENC hardware encoding when run with an NVIDIA GPU (see [NVIDIA hardware encoding](#nvidia-hardware-encoding))
- Optional browser login and HTTPS
- The whole OBS configuration on a volume, with recordings sent to a volume automatically
- Unattended operation: OBS restarts after a crash without the Safe Mode prompt, can start streaming on startup, and shuts down cleanly on `docker stop`
- A Docker healthcheck

## Limitations

- amd64 only. The OBS PPA publishes no arm64 builds.
- No audio in the browser. KasmVNC on its own does not play sound; that is a Kasm Workspaces feature. Audio in your stream and recordings is not affected.
- A browser session does not forward your computer's camera, microphone, or desktop to OBS.
- NVENC support has not been tested on real NVIDIA hardware yet.

## Attribution

This project is based on the original **kasm-obs** container setup by **[cdrage](https://github.com/cdrage)**, from [cdrage/containerfiles](https://github.com/cdrage/containerfiles/tree/master/kasm-obs).

Credit for the original container implementation belongs to cdrage. This repository carries that setup forward with its own builds and container publishing. It is independently maintained and is not an official OBS Studio or Kasm project.

Additional thanks to [OBS Studio](https://obsproject.com/) and [KasmVNC](https://github.com/kasmtech/KasmVNC).

## Container image

```text
ghcr.io/kgregor98/kasm-obs:latest
```

The same image, with the same tags, is also on Docker Hub as [`camislav/kasm-obs`](https://hub.docker.com/r/camislav/kasm-obs). The examples below use GHCR, which does not rate-limit anonymous pulls the way Docker Hub does; either works.

| Tag | Meaning |
| --- | --- |
| `latest` | Newest build of `main`. Rebuilt weekly to pick up OBS and base image updates. |
| `obs-32.2.0` | Newest build that contains that OBS version. |
| `obs-32.2.0-2026.10.07` | The build from that day; pin this for a fixed image. |
| `1.2.3`, `1.2` | Builds of git tags `v1.2.3`, for named releases. |

Every image is smoke-tested before it is published: it must start and become healthy, require and accept the login, load the DroidCam and VLC plugins, point recordings at `/recordings`, and stop cleanly.

## Quick start with Compose

Download the [`compose.yaml`](compose.yaml) from this repository. It lists all settings, with examples in comments:

```bash
curl -O https://raw.githubusercontent.com/kgregor98/kasm-obs/main/compose.yaml
```

It turns the login on with user **admin** and password **password**. Change them before you start it: set `HTTP_USER` and `HTTP_PASSWORD` in a `.env` file next to `compose.yaml`, in your shell, or as Portainer stack variables (see [Configuration](#configuration)). Then start OBS:

```bash
docker compose up -d
```

A minimal compose file without the login also works:

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

## Run without Compose

```bash
docker run -d \
  --name kasm-obs \
  --restart unless-stopped \
  --shm-size=2g \
  --stop-timeout 30 \
  -p 6901:6901 \
  -e HTTP_USER=admin \
  -e HTTP_PASSWORD=change-me \
  -v obs-config:/mnt/obs-config \
  -v obs-media:/media:ro \
  -v obs-recordings:/recordings \
  ghcr.io/kgregor98/kasm-obs:latest
```

Leave out the two `-e` lines to run without a login. Docker creates the named volumes automatically.

## Accessing OBS

Open **http://YOUR_SERVER_IP:6901** (or **http://localhost:6901** on the Docker host), or **https://** when `SSL_ENABLED` is on.

Port 6901 is published on all host interfaces. The image itself starts with no login and no SSL unless you set them (the repository's `compose.yaml` sets the login). For access from the internet, use a reverse proxy with HTTPS, authentication, and WebSocket support.

## Configuration

All settings are environment variables:

| Variable | Image default | `compose.yaml` default | Effect |
| --- | --- | --- | --- |
| `HTTP_USER` | unset | `admin` | Login username. Must not contain `:`. |
| `HTTP_PASSWORD` | unset | `password` | Login password. |
| `SSL_ENABLED` | unset | unset | `true` (also `1` or `yes`, any case) serves HTTPS only; anything else serves plain HTTP. |
| `OBS_ARGS` | unset | unset | Extra OBS command-line options, see [OBS startup options](#obs-startup-options). |
| `OBS_STOP_TIMEOUT` | `20` | `20` | Seconds OBS gets to save and finish recordings when the container stops. |
| `TZ` | `Etc/UTC` | `Etc/UTC` | Time zone for OBS log times and recording file names, for example `Europe/Warsaw`. |

`compose.yaml` passes these through from the shell, a `.env` file next to it, or Portainer stack variables. Unset variables become empty, which means off; only the login has a default there. To turn the login off with `compose.yaml`, set `HTTP_USER` to an empty value.

In a `.env` file, Compose treats `$` as the start of a variable, so `HTTP_PASSWORD=pa$word` arrives as `pa`. Write it as `HTTP_PASSWORD='pa$word'` (single quotes) or `HTTP_PASSWORD=pa$$word`. Values exported in the shell are passed unchanged. If a password with `$` doesn't work in Portainer, use `$$` there too.

In your own compose file, set them in an `environment` block of the `obs` service:

```yaml
    environment:
      SSL_ENABLED: "true"
      HTTP_USER: "obs"
      HTTP_PASSWORD: "change-me"
```

With `docker run`, use `-e`, for example `-e SSL_ENABLED=true -e HTTP_USER=obs -e HTTP_PASSWORD=change-me`.

### Login and SSL

- The login is enabled only when both `HTTP_USER` and `HTTP_PASSWORD` are set and non-empty. If only one is set, the login stays off and a warning is written to the container log.
- With SSL on, the certificate is self-signed and regenerated at every container start, so the browser shows a warning each time.
- With the login on but SSL off, the browser sends the password unencrypted. Use it only behind a reverse proxy that provides HTTPS.
- If a reverse proxy sits in front and SSL is on, the proxy must connect to the container over HTTPS and accept the self-signed certificate.
- The user inside the container has passwordless `sudo`, so anyone who can use the web UI effectively has root inside the container. Protect access accordingly.

### OBS startup options

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
| `/media` | Images, videos, and audio used by sources; read-only in the examples |
| `/recordings` | Recording output (also replay buffer and screenshots); OBS profiles are pointed here automatically |

`/mnt/obs-config` holds OBS's entire configuration folder (`~/.config/obs-studio`). Volumes from older versions of this image, which held only profiles and scene collections, are moved into `/mnt/obs-config/basic` automatically on first start. Use stable container paths such as `/media/...` when configuring sources.

OBS normally records into the home folder, which is not on a volume. Before each OBS start, the image sets the recording path of every profile to `/recordings` when it is unset or still the home folder. A path you choose yourself, for example under `/media`, is left alone. A profile created in OBS during a session records to the home folder until OBS restarts, so set its path to `/recordings` when you create it.

Named volumes live on the Docker host under `/var/lib/docker/volumes/<volume name>/_data`; copy media in and recordings out there, or replace a named volume with a host folder (for example `./media:/media:ro`).

Plugins copied into `/mnt/obs-config/plugins` persist, but system packages installed manually in a running container do not. Plugins that need extra packages belong in the image.

The container runs as UID 1000. The image makes `/mnt/obs-config` and `/recordings` writable for that user, so new named volumes work as is; with bind mounts, the host directories must be writable by UID 1000. Back up the configuration volume and any media you need. Stream credentials may be stored in OBS configuration; keep backups private.

`docker compose down` retains the named volumes. **`docker compose down -v` deletes all three volumes.** Compose normally prefixes volume names with the project name; the `docker run` example uses the names directly.

## Operational notes

- OBS runs inside the container on your server. Closing the browser leaves it running.
- Stopping the container lets OBS save its settings and finish any recording before it exits, for up to `OBS_STOP_TIMEOUT` seconds (20 by default). Keep Docker's stop timeout above that: `stop_grace_period: 30s` in Compose or `--stop-timeout 30` with `docker run`; Docker's default of 10 seconds can cut a recording short. For this reason the image turns off OBS's "outputs are still active" exit confirmation, which would otherwise block the shutdown.
- If OBS exits or crashes, it is started again automatically, without the "launch in Safe Mode?" prompt. To resume streaming after a restart, set `OBS_ARGS=--startstreaming`.
- The image has a healthcheck: the container shows as `healthy` in `docker ps` when OBS is running and the web UI port is listening. Docker does not restart unhealthy containers on its own.
- Set your sources, encoder, and stream destination before starting a broadcast.

## NVIDIA hardware encoding

NVENC needs an NVIDIA GPU and driver on the host and the [NVIDIA Container Toolkit](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/install-guide.html). The toolkit mounts the driver's encode libraries into the container; the image already sets `NVIDIA_DRIVER_CAPABILITIES=compute,video,utility`.

With `docker run`, add `--gpus all`. With Compose, uncomment the `deploy` block in `compose.yaml`, or add it to your `obs` service:

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

## Updating

```bash
docker compose pull && docker compose up -d
```

With `docker run`, pull the image, then remove and recreate the container with the same command. Your configuration and recordings stay on the volumes.

## Building and testing

```bash
docker build -t kasm-obs:test .
.github/scripts/smoke-test.sh kasm-obs:test
```

The smoke test is the same one the publish workflow runs. It uses port 16901 and a container named `kasm-obs-smoke`, and ends with `Smoke test passed`. Run both commands with `sudo` if your user can't access Docker directly.

## Third-party software

The container image contains software from other projects under their own licenses. The MIT License of this repository does not apply to them.

| Component | License | Source |
| --- | --- | --- |
| [OBS Studio](https://github.com/obsproject/obs-studio) | GPL-2.0-or-later | Installed unmodified from the [OBS Studio PPA](https://launchpad.net/~obsproject/+archive/ubuntu/obs-studio) |
| [DroidCam OBS plugin](https://github.com/dev47apps/droidcam-obs-plugin) | GPL-2.0-or-later | Built unmodified from tag [`2.5.1`](https://github.com/dev47apps/droidcam-obs-plugin/tree/2.5.1), see the [`Dockerfile`](Dockerfile) |
| [KasmVNC](https://github.com/kasmtech/KasmVNC) | GPL-2.0 | Part of the Kasm base image |
| [Kasm core images](https://github.com/kasmtech/workspaces-core-images) | MIT | Base image `kasmweb/core-ubuntu-noble` |
| Ubuntu packages (FFmpeg, VLC libraries, and others) | Various, mostly GPL/LGPL | Installed unmodified from the Ubuntu archive |

License texts for the installed packages are in `/usr/share/doc/<package>/copyright` inside the image. Source code for the Ubuntu and PPA packages is available from Ubuntu and Launchpad. For any component, you can also request the source used for a given image by opening an issue in this repository.

"OBS" and "OBS Studio" are registered trademarks of Wizards of OBS LLC. Kasm and KasmVNC are products of Kasm Technologies. This project is not affiliated with or endorsed by either.

## License

The files in this repository are released under the MIT License. See [LICENSE](LICENSE).
