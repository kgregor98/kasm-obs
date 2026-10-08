# kasm-obs: OBS Studio on a KasmVNC desktop, controlled from a web browser.
# Made for streaming from a server (remote feeds, browser sources, media files). It does not pass
# cameras, microphones or capture devices from your computer through to OBS.
#
# Security: out of the box the web UI is plain HTTP with no login. Either put it behind a reverse
# proxy that handles TLS and authentication, or set HTTP_USER + HTTP_PASSWORD and SSL_ENABLED=true
# (self-signed certificate). See kasm_obs_auth.sh.
#
# Data: OBS's whole config directory (~/.config/obs-studio) lives on /mnt/obs-config. Everything
# else changed inside a running container, installed packages included, is lost when it is recreated.
#
# Example:
#   docker run -d -p 6901:6901 --shm-size=2g --stop-timeout 30 \
#     -v obs-config:/mnt/obs-config ghcr.io/kgregor98/kasm-obs:latest

#! Noble: the OBS PPA stopped publishing for jammy at OBS 30.2.3
FROM kasmweb/core-ubuntu-noble:1.19.0-rolling-daily AS base

#! Build steps run as root and write into Kasm's default profile
USER root
#! NVENC: libnvidia-encode comes from the host driver, mounted by the NVIDIA Container Toolkit when run with --gpus.
#! "video" makes the toolkit include the encode/decode libraries (the default is compute,utility only).
ENV NVIDIA_DRIVER_CAPABILITIES=compute,video,utility
ENV HOME=/home/kasm-default-profile
ENV STARTUPDIR=/dockerstartup
ENV INST_SCRIPTS=$STARTUPDIR/install
WORKDIR $HOME

#! OBS comes from the official obsproject PPA; the Kasm base image already ships add-apt-repository
#! libvlc5 + vlc-plugin-base: needed by OBS's "VLC Video Source"
#! libturbojpeg + libimobiledevice6 + libusbmuxd6: runtime libraries of the DroidCam plugin
RUN add-apt-repository ppa:obsproject/obs-studio -y && \
    apt-get update && \
    apt-get install -y  \
        zip \
        unzip \
        sudo \
        obs-studio \
        ffmpeg \
        libvlc5 \
        vlc-plugin-base \
        libturbojpeg \
        libimobiledevice6 \
        libusbmuxd6 && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

#! DroidCam is compiled from its source tag, since the prebuilt plugin does not load in current OBS releases.
#! The compile runs in a separate stage (on top of the same OBS install), so the compilers and -dev packages do not end up in the final image.
#! libsimde-dev: the OBS 32 headers include SIMDe, which the obs-studio package does not pull in
#! --no-as-needed: the plugin Makefile puts -l flags before the sources, so Ubuntu's default --as-needed would drop them
#! and OBS would fail to load the plugin with "undefined symbol"
FROM base AS droidcam-build
RUN apt-get update && \
    apt-get install -y \
        build-essential \
        pkg-config \
        libturbojpeg0-dev libusbmuxd-dev libimobiledevice-dev libavcodec-dev libavformat-dev libavutil-dev libswscale-dev \
        libsimde-dev && \
    git clone --depth 1 --branch 2.5.1 https://github.com/dev47apps/droidcam-obs-plugin /tmp/droidcam-obs-plugin && \
    cd /tmp/droidcam-obs-plugin && \
    mkdir build && \
    LDD_DIRS="-Wl,--no-as-needed" make

FROM base

#! Kasm's browser audio runs "ffmpeg -f pulse", so ffmpeg must support PulseAudio.
#! Ubuntu's ffmpeg does; the static ffmpeg build this image used to install did not, and broke browser audio.
RUN ffmpeg -hide_banner -devices 2>/dev/null | grep -q pulse

#! DroidCam goes into OBS's system plugin folders, so the /mnt/obs-config volume (mounted over ~/.config/obs-studio) does not hide it
#! The ldd check fails the build if a runtime library of the plugin is missing
COPY --from=droidcam-build /tmp/droidcam-obs-plugin/build/droidcam-obs.so /usr/lib/x86_64-linux-gnu/obs-plugins/droidcam-obs.so
COPY --from=droidcam-build /tmp/droidcam-obs-plugin/data /usr/share/obs/obs-plugins/droidcam-obs
RUN ! ldd /usr/lib/x86_64-linux-gnu/obs-plugins/droidcam-obs.so | grep "not found"

#! kasm-user may run sudo without a password inside the container
RUN echo 'kasm-user ALL=(ALL) NOPASSWD: ALL' >> /etc/sudoers

#! Use Kasm's single-application xfce profile (black desktop, OBS is the only window) and drop the panel
RUN cp $HOME/.config/xfce4/xfconf/single-application-xfce-perchannel-xml/* $HOME/.config/xfce4/xfconf/xfce-perchannel-xml/
RUN apt-get remove -y xfce4-panel

COPY custom_startup.sh $STARTUPDIR/custom_startup.sh
RUN chmod +x $STARTUPDIR/custom_startup.sh

#! Plain HTTP is the default, for a reverse proxy that terminates TLS: require_ssl is turned off in the KasmVNC defaults file.
#! With SSL_ENABLED=true the server gets -sslOnly on its command line, which overrides that setting.
RUN sed -i -E 's/^([[:space:]]*)require_ssl:[[:space:]]*true/\1require_ssl: false/' /usr/share/kasmvnc/kasmvnc_defaults.yaml

#! SSL and HTTP auth are decided at container start from SSL_ENABLED, HTTP_USER and HTTP_PASSWORD (see kasm_obs_auth.sh)
#! WARNING: with the defaults (nothing set) there is NO SSL and NO login, only use it behind a reverse proxy with its own auth + SSL.
#! vnc_startup.sh is patched to:
#!  - source kasm_obs_auth.sh right after "set -e"
#!  - replace the hard-coded -sslOnly with $KASMVNC_SECURITY_OPTS
#!  - use $VNC_USER instead of the hard-coded kasm_user, and drop the view-only kasm_viewer login
#!  - run kasm_obs_shutdown.sh at the start of cleanup(), so "docker stop" lets OBS save and finish recordings
#! The greps fail the build if the upstream script changes and a patch no longer applies.
COPY kasm_obs_auth.sh $STARTUPDIR/kasm_obs_auth.sh
COPY kasm_obs_shutdown.sh $STARTUPDIR/kasm_obs_shutdown.sh
RUN chmod +x $STARTUPDIR/kasm_obs_shutdown.sh && \
    f=$STARTUPDIR/vnc_startup.sh && \
    sed -i \
        -e '0,/^set -e$/s//set -e\nsource \/dockerstartup\/kasm_obs_auth.sh/' \
        -e 's/ -sslOnly / $KASMVNC_SECURITY_OPTS /g' \
        -e 's/"kasm_user:\$VNC_PW"/"$VNC_USER:$VNC_PW"/g' \
        -e '/kasmvncpasswd -u kasm_user -wo/c\printf "%s\\n%s\\n" "$VNC_PW" "$VNC_PW" | kasmvncpasswd -u "$VNC_USER" -wo' \
        -e '/kasmvncpasswd -u kasm_viewer/d' \
        -e '/^function cleanup () {$/a\    /dockerstartup/kasm_obs_shutdown.sh' \
        $f && \
    grep -qx 'source /dockerstartup/kasm_obs_auth.sh' $f && \
    [ "$(grep -cF ' $KASMVNC_SECURITY_OPTS ' $f)" -eq 2 ] && \
    [ "$(grep -cF '"$VNC_USER:$VNC_PW"' $f)" -eq 4 ] && \
    grep -qF 'kasmvncpasswd -u "$VNC_USER" -wo' $f && \
    grep -A1 '^function cleanup () {$' $f | grep -qx '    /dockerstartup/kasm_obs_shutdown.sh' && \
    ! grep -qE -- '-sslOnly|kasm_user:|-u kasm_' $f

#! ~/.config/obs-studio is a symlink to /mnt/obs-config, so a volume there keeps every OBS setting
#! Older versions only linked the "basic" folder; custom_startup.sh moves such a layout into /mnt/obs-config/basic
#! /mnt/obs-config and /recordings are owned by the container user so new named volumes are writable
RUN mkdir -p /home/kasm-user/.config && \
    mkdir -p /mnt/obs-config /recordings && \
    chown 1000:0 /mnt/obs-config /recordings && \
    ln -s /mnt/obs-config /home/kasm-user/.config/obs-studio

#! Give the profile to UID 1000 (kasm-user), then switch HOME to that user's home for runtime
RUN chown 1000:0 $HOME
RUN $STARTUPDIR/set_user_permission.sh $HOME

ENV HOME=/home/kasm-user
WORKDIR $HOME
RUN mkdir -p $HOME && chown -R 1000:0 $HOME

#! Healthy when OBS is running and the web UI port is listening.
#! It checks the listening socket instead of making a request, so it does not fill the KasmVNC log
#! with a connection (and a failed-login line when HTTP auth is on) every 30 seconds.
HEALTHCHECK --interval=30s --timeout=10s --start-period=90s --retries=3 \
    CMD pgrep -x obs > /dev/null && \
        ss -Hltn "sport = :${NO_VNC_PORT:-6901}" | grep -q .

USER 1000
