# Sourced by /dockerstartup/vnc_startup.sh before KasmVNC starts.
# Turns SSL_ENABLED, HTTP_USER and HTTP_PASSWORD into KasmVNC options:
#   KASMVNC_SECURITY_OPTS - extra vncserver flags (-sslOnly, -disableBasicAuth)
#   VNC_USER / VNC_PW     - login written to ~/.kasmpasswd

KASMVNC_SECURITY_OPTS=""
VNC_USER=kasm_user

case "${SSL_ENABLED,,}" in
    true|1|yes)
        KASMVNC_SECURITY_OPTS="-sslOnly"
        echo "kasm-obs: SSL enabled (self-signed certificate)"
        ;;
    *)
        echo "kasm-obs: SSL disabled"
        ;;
esac

if [[ -n "$HTTP_USER" && -n "$HTTP_PASSWORD" ]]; then
    if [[ "$HTTP_USER" == *:* ]]; then
        echo "kasm-obs: HTTP_USER must not contain ':'" >&2
        exit 1
    fi
    VNC_USER=$HTTP_USER
    VNC_PW=$HTTP_PASSWORD
    echo "kasm-obs: HTTP auth enabled for user '$VNC_USER'"
else
    if [[ -n "$HTTP_USER" || -n "$HTTP_PASSWORD" ]]; then
        echo "kasm-obs: WARNING: HTTP_USER and HTTP_PASSWORD must both be set, HTTP auth stays disabled" >&2
    fi
    KASMVNC_SECURITY_OPTS="$KASMVNC_SECURITY_OPTS -disableBasicAuth"
    echo "kasm-obs: HTTP auth disabled"
fi

# Keep the password out of the environment of OBS and other child processes
unset HTTP_PASSWORD
