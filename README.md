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

## Quick start with Compose

Create a `compose.yaml`:

```yaml
services:
  obs:
    image: ghcr.io/kgregor98/kasm-obs:latest
    container_name: kasm-obs
    restart: unless-stopped
    shm_size: "2gb"
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
  -p 6901:6901 \
  -v obs-config:/mnt/obs-config \
  -v obs-media:/media:ro \
  -v obs-recordings:/recordings \
  ghcr.io/kgregor98/kasm-obs:latest
```

Docker creates the named volumes automatically. Choose either Compose or `docker run`.

Open **http://YOUR_SERVER_IP:6901** (or **http://localhost:6901** on the Docker host).

Port 6901 is published on all host interfaces. The inherited setup has no authentication or TLS; for public access, use a reverse proxy with HTTPS, authentication, and WebSocket support.

## Persistent data

| Container path | Purpose |
| --- | --- |
| `/mnt/obs-config` | OBS profiles, scene collections, and settings |
| `/media` | Images, videos, and audio used by sources; read-only in this example |
| `/recordings` | Recording output; select this directory in OBS |

The upstream setup redirects OBS configuration to `/mnt/obs-config`. Media and recordings require their own mounts. Use stable container paths when configuring sources.

Install additional plugins and their dependencies in the image so they survive container replacement. Do not rely on packages installed manually in a running container.

Ensure the container user can write to the configuration and recordings locations. Back up the configuration volume and any media you need. Stream credentials may be stored in OBS configuration; keep backups private.

`docker compose down` retains the named volumes. **`docker compose down -v` deletes all three volumes.** Compose normally prefixes volume names with the project name; the `docker run` example uses the names directly.


## Operational notes

- OBS runs on the Docker host. A browser session does not automatically forward your laptop's camera, microphone, or desktop to OBS.
- Closing the browser leaves the running container intact. Restarting the container interrupts OBS; automatic streaming after a restart requires additional configuration.
- Hardware encoding requires compatible host hardware, drivers, container device access, and OBS support. It is not enabled by these examples.
- Set OBS sources, encoder, stream destination, and recording paths before starting a broadcast.



## License

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:
The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.
THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.