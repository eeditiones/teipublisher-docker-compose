# Starts eXist-db, then sets the admin and tei passwords when admin is still empty.
# The image is distroless, so this script runs with the mounted static busybox.

BUSY=/exist-init/bin/busybox

if [ "$#" -eq 0 ]; then
    set -- jetty
fi

(
    unset EXIST_ADMIN_PASSWORD EXIST_TEI_PASSWORD
    exec java org.exist.start.Main "$@"
) &
java_pid=$!

term() {
    EXIST_INIT_STOP=1
    kill -TERM "$java_pid" 2>/dev/null || true
}
trap term TERM INT

# shellcheck disable=SC1091
. /exist-init/set-passwords.sh
init_passwords || printf '%s\n' "[exist-init] password initialization did not complete; eXist-db is still running" >&2

status=0
while "$BUSY" kill -0 "$java_pid" 2>/dev/null; do
    wait "$java_pid" || status=$?
done
exit "$status"
