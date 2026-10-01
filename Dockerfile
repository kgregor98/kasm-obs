#**Description:**
#
# Using KASM (basically web-based VNC) to run OBS.
# 
# This is NOT meant for using a local camera, etc. I use the solely for remote streaming.
#
# **IMPORTANT:**
# 
# By default there is **NO AUTHENTICATION** and **NO SSL** in this container. This is meant for local use only, or when you have a reverse proxy in front of it.
# Set SSL_ENABLED=true for HTTPS (self-signed certificate), and HTTP_USER + HTTP_PASSWORD for a login. See kasm_obs_auth.sh.
#
# **NOTE:**
# - Any additional plugins (except OBS DroidCam) will be discarded on container restart.. the ONLY persistent data is OBS configuration, which is symlinked to `/mnt/obs-config`.
#
#
# **Running:**
#
# ```sh
# podman run -it --rm \
#  -p 6901:6901 \
#  -v /path/to/obs-config:/mnt/obs-config \
#  --shm-size=2g \
#  ghcr.io/kgregor98/kasm-obs:latest
# ```

#! Noble: the OBS PPA stopped publishing for jammy at OBS 30.2.3
FROM kasmweb/core-ubuntu-noble:1.19.0-rolling-daily

#! Initial setup
USER root
#! NVENC: libnvidia-encode comes from the host driver, mounted by the NVIDIA Container Toolkit when run with --gpus.
#! "video" makes the toolkit include the encode/decode libraries (the default is compute,utility only).
ENV NVIDIA_DRIVER_CAPABILITIES=compute,video,utility
ENV HOME=/home/kasm-default-profile
ENV STARTUPDIR=/dockerstartup
ENV INST_SCRIPTS=$STARTUPDIR/install
WORKDIR $HOME

#! Add OBS Studio PPA and install OBS with minimal dependencies
#! libvlc5 + vlc-plugin-base: needed by OBS's "VLC Video Source"
RUN apt-get update && \
    apt-get install -y software-properties-common && \
    add-apt-repository ppa:obsproject/obs-studio -y && \
    apt-get update && \
    apt-get install -y  \
        zip \
        unzip \
        sudo \
        obs-studio \
        ffmpeg \
        libvlc5 \
        vlc-plugin-base && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

#! ffmpeg in Ubuntu is really old.. so we are going to download ffmpeg 7+
#! and use that instead, including using ln to force it to be used as the default ffmpeg
RUN curl -L https://johnvansickle.com/ffmpeg/releases/ffmpeg-release-amd64-static.tar.xz -o /tmp/ffmpeg.tar.xz && \
    tar -xf /tmp/ffmpeg.tar.xz -C /tmp && \
    cp /tmp/ffmpeg-*/ffmpeg /usr/local/bin/ && \
    cp /tmp/ffmpeg-*/ffprobe /usr/local/bin/ && \
    rm -rf /tmp/ffmpeg* && \
    ln -sf /usr/local/bin/ffmpeg /usr/bin/ffmpeg && \
    ln -sf /usr/local/bin/ffprobe /usr/bin/ffprobe && \
    ffmpeg -version

#! We are going to git clone droidcam-obs-plugin, and built it ourselves. This is because the pre-built version does not work with the latest OBS Studio.
#! Install the build dependencies, build in /tmp, and only keep the plugin .so
#! libsimde-dev: the OBS 32 headers include SIMDe, which the obs-studio package does not pull in
#! --no-as-needed: the plugin Makefile puts -l flags before the sources, so Ubuntu's default --as-needed would drop them
#! and OBS would fail to load the plugin with "undefined symbol"
RUN apt-get update && \
    apt-get install -y \
        build-essential \
        pkg-config \
        libturbojpeg0-dev libusbmuxd-dev libimobiledevice-dev libavcodec-dev libavformat-dev libavutil-dev libswscale-dev \
        libsimde-dev && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/* && \
    git clone https://github.com/dev47apps/droidcam-obs-plugin /tmp/droidcam-obs-plugin && \
    cd /tmp/droidcam-obs-plugin && \
    git checkout tags/2.5.1 && \
    mkdir build && \
    LDD_DIRS="-Wl,--no-as-needed" make && \
    mkdir -p ~/.config/obs-studio/plugins/droidcam-obs/bin/64bit && \
    cp build/droidcam-obs.so ~/.config/obs-studio/plugins/droidcam-obs/bin/64bit/ && \
    cp -r data ~/.config/obs-studio/plugins/droidcam-obs/ && \
    rm -rf /tmp/droidcam-obs-plugin

#! Add to sudo users so we can actually do "sudo" within the container
RUN echo 'kasm-user ALL=(ALL) NOPASSWD: ALL' >> /etc/sudoers

#! Run as a "single" application
#! Set background as just plain black
RUN cp $HOME/.config/xfce4/xfconf/single-application-xfce-perchannel-xml/* $HOME/.config/xfce4/xfconf/xfce-perchannel-xml/
RUN apt-get remove -y xfce4-panel

COPY custom_startup.sh $STARTUPDIR/custom_startup.sh
RUN chmod +x $STARTUPDIR/custom_startup.sh

#! SSL is off by default so that we can access it via HTTP (e.g. behind a reverse proxy + let's encrypt)
#! We do this by changing require_ssl in /usr/share/kasmvnc/kasmvnc_defaults.yaml from require_ssl: true to require_ssl: false
#! SSL_ENABLED=true passes -sslOnly on the command line, which takes precedence over this config value
RUN sed -i -E 's/^([[:space:]]*)require_ssl:[[:space:]]*true/\1require_ssl: false/' /usr/share/kasmvnc/kasmvnc_defaults.yaml
RUN cat /usr/share/kasmvnc/kasmvnc_defaults.yaml

#! SSL and HTTP auth are decided at container start from SSL_ENABLED, HTTP_USER and HTTP_PASSWORD (see kasm_obs_auth.sh)
#! WARNING: with the defaults (nothing set) there is NO SSL and NO login, only use it behind a reverse proxy with its own auth + SSL.
#! vnc_startup.sh is patched to:
#!  - source kasm_obs_auth.sh right after "set -e"
#!  - replace the hard-coded -sslOnly with $KASMVNC_SECURITY_OPTS
#!  - use $VNC_USER instead of the hard-coded kasm_user, and drop the view-only kasm_viewer login
#! The greps fail the build if the upstream script changes and a patch no longer applies.
COPY kasm_obs_auth.sh $STARTUPDIR/kasm_obs_auth.sh
RUN f=$STARTUPDIR/vnc_startup.sh && \
    sed -i \
        -e '0,/^set -e$/s//set -e\nsource \/dockerstartup\/kasm_obs_auth.sh/' \
        -e 's/ -sslOnly / $KASMVNC_SECURITY_OPTS /g' \
        -e 's/"kasm_user:\$VNC_PW"/"$VNC_USER:$VNC_PW"/g' \
        -e '/kasmvncpasswd -u kasm_user -wo/c\printf "%s\\n%s\\n" "$VNC_PW" "$VNC_PW" | kasmvncpasswd -u "$VNC_USER" -wo' \
        -e '/kasmvncpasswd -u kasm_viewer/d' \
        $f && \
    grep -qx 'source /dockerstartup/kasm_obs_auth.sh' $f && \
    [ "$(grep -cF ' $KASMVNC_SECURITY_OPTS ' $f)" -eq 2 ] && \
    [ "$(grep -cF '"$VNC_USER:$VNC_PW"' $f)" -eq 4 ] && \
    grep -qF 'kasmvncpasswd -u "$VNC_USER" -wo' $f && \
    ! grep -qE -- '-sslOnly|kasm_user:|-u kasm_' $f

#! IMPORTANT, the config will be symlinked to: /mnt/obs-config
#! /mnt/obs-config and /recordings are owned by the container user so new named volumes are writable
RUN mkdir -p /home/kasm-user/.config/obs-studio && \
    mkdir -p /mnt/obs-config /recordings && \
    chown 1000:0 /mnt/obs-config /recordings && \
    ln -s /mnt/obs-config /home/kasm-user/.config/obs-studio/basic

#! Default user
RUN chown 1000:0 $HOME
RUN $STARTUPDIR/set_user_permission.sh $HOME

ENV HOME=/home/kasm-user
WORKDIR $HOME
RUN mkdir -p $HOME && chown -R 1000:0 $HOME

USER 1000
