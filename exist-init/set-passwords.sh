# Sets the eXist-db admin password (and the tei password, if EXIST_TEI_PASSWORD
# is set) when the admin password is still empty. A volume that already has an
# admin password is left unchanged.
# Sourced by entrypoint.sh; running this file directly performs the check once.

BUSY=${EXIST_INIT_BUSYBOX:-/exist-init/bin/busybox}
REST=${EXIST_REST_URL:-http://127.0.0.1:8080/exist/rest/db}
PROBE="${REST}?_query=sm:id()"
PENDING=${EXIST_INIT_PENDING:-/exist/data/.password-init-pending}
EXISTS_QUERY=/tmp/exist-init-exists.xml
PASSWD_QUERY=/tmp/exist-init-passwd.xml

log() {
    printf '%s\n' "[exist-init] $*" >&2
}

log_wait() {
    wait_logs=$((${wait_logs:-0} + 1))
    if [ "$wait_logs" -eq 1 ] || [ $((wait_logs % 12)) -eq 0 ]; then
        log "$1"
    fi
}

cleanup_queries() {
    "$BUSY" rm -f "$PASSWD_QUERY" /tmp/exist-init.body /tmp/exist-init.hdr
}

http_code() {
    user=$1
    pass=$2
    url=$3
    post=${4:-}
    auth=$(printf '%s:%s' "$user" "$pass" | "$BUSY" base64 | "$BUSY" tr -d '\n')
    "$BUSY" rm -f /tmp/exist-init.body /tmp/exist-init.hdr
    if [ -n "$post" ]; then
        "$BUSY" wget -S -O /tmp/exist-init.body -T 15 \
            --header="Authorization: Basic ${auth}" \
            --header="Content-Type: application/xml" \
            --post-file="$post" \
            "$url" >/tmp/exist-init.hdr 2>&1 || true
    else
        "$BUSY" wget -S -O /tmp/exist-init.body -T 15 \
            --header="Authorization: Basic ${auth}" \
            "$url" >/tmp/exist-init.hdr 2>&1 || true
    fi
    code=$("$BUSY" sed -n 's/.*HTTP\/[0-9.][0-9.]* \([0-9][0-9][0-9]\).*/\1/p' /tmp/exist-init.hdr | "$BUSY" tail -n 1)
    if [ -z "$code" ]; then
        printf '%s\n' "000"
    else
        printf '%s\n' "$code"
    fi
}

body_has() {
    "$BUSY" grep -q ">$1<" /tmp/exist-init.body
}

# 0 when the configured passwords are usable, 2 when retrying cannot help.
# EXIST_TEI_PASSWORD is optional: without it only the admin password is set.
passwords_configured() {
    if [ -z "${EXIST_ADMIN_PASSWORD:-}" ]; then
        log "admin password is empty, but EXIST_ADMIN_PASSWORD is unset; not changing accounts"
        return 2
    fi
    for value in "$EXIST_ADMIN_PASSWORD" "${EXIST_TEI_PASSWORD:-}"; do
        if printf '%s' "$value" | "$BUSY" grep -q '[[:cntrl:]]'; then
            log "configured passwords must be one line without control characters; not changing accounts"
            return 2
        fi
        case "$value" in
            *']]>'*)
                log "configured passwords must not contain ]]>; not changing accounts"
                return 2
                ;;
        esac
    done
    return 0
}

xq_escape() {
    printf '%s' "$1" | "$BUSY" sed "s/'/''/g"
}

write_exists_query() {
    if [ -f "$EXISTS_QUERY" ]; then
        return 0
    fi
    umask 077
    printf '%s\n' \
        '<query xmlns="http://exist.sourceforge.net/NS/exist">' \
        '  <text><![CDATA[sm:user-exists("tei")]]></text>' \
        '</query>' >"$EXISTS_QUERY"
}

write_passwd_query() {
    mode=$1
    admin_lit=$(xq_escape "$EXIST_ADMIN_PASSWORD")
    tei_lit=$(xq_escape "$EXIST_TEI_PASSWORD")
    umask 077
    {
        printf '%s\n' '<query xmlns="http://exist.sourceforge.net/NS/exist">'
        printf '%s\n' '  <text><![CDATA['
        if [ "$mode" = "both" ]; then
            printf '%s\n' "    sm:passwd(\"admin\", '${admin_lit}'),"
            printf '%s\n' "    sm:passwd(\"tei\", '${tei_lit}')"
        elif [ "$mode" = "admin" ]; then
            printf '%s\n' "    sm:passwd(\"admin\", '${admin_lit}')"
        else
            printf '%s\n' "    sm:passwd(\"tei\", '${tei_lit}')"
        fi
        printf '%s\n' '  ]]></text>'
        printf '%s\n' '</query>'
    } >"$PASSWD_QUERY"
}

login_ok() {
    code=$(http_code "$1" "$2" "$PROBE")
    [ "$code" = "200" ] && body_has "$1"
}

tei_user_exists() {
    write_exists_query
    code=$(http_code "$1" "$2" "$REST" "$EXISTS_QUERY")
    [ "$code" = "200" ] && body_has "true"
}

mark_pending() {
    umask 077
    printf '%s\n' "tei" >"$PENDING"
}

clear_pending() {
    "$BUSY" rm -f "$PENDING"
}

finish_tei() {
    user=$1
    pass=$2
    if ! tei_user_exists "$user" "$pass"; then
        log_wait "waiting for the tei user to be created"
        return 1
    fi
    write_passwd_query tei
    code=$(http_code "$user" "$pass" "$REST" "$PASSWD_QUERY")
    cleanup_queries
    if [ "$code" = "200" ] && login_ok tei "$EXIST_TEI_PASSWORD"; then
        clear_pending
        log "set the tei password"
        return 0
    fi
    log "failed to set the tei password (HTTP ${code})"
    return 1
}

# 0 done, 1 retry, 2 configuration error.
init_once() {
    if [ -f "$PENDING" ]; then
        passwords_configured || return $?
        if [ -z "${EXIST_TEI_PASSWORD:-}" ]; then
            clear_pending
            log "EXIST_TEI_PASSWORD is unset; not setting the tei password"
            return 0
        fi
        if login_ok tei "$EXIST_TEI_PASSWORD"; then
            clear_pending
            log "tei password is already set"
            return 0
        fi
        if ! login_ok admin "$EXIST_ADMIN_PASSWORD"; then
            log_wait "waiting to log in as admin before setting the tei password"
            return 1
        fi
        finish_tei admin "$EXIST_ADMIN_PASSWORD"
        return $?
    fi

    code=$(http_code admin "" "$PROBE")
    if [ "$code" = "401" ]; then
        log "admin password is already set; leaving accounts unchanged"
        return 0
    fi
    if [ "$code" != "200" ] || ! body_has admin; then
        log_wait "waiting for eXist-db (admin probe HTTP ${code})"
        return 1
    fi

    passwords_configured || return $?

    if [ -z "${EXIST_TEI_PASSWORD:-}" ]; then
        write_passwd_query admin
        code=$(http_code admin "" "$REST" "$PASSWD_QUERY")
        cleanup_queries
        if [ "$code" = "200" ] && login_ok admin "$EXIST_ADMIN_PASSWORD"; then
            log "set the admin password; EXIST_TEI_PASSWORD is unset, leaving tei unchanged"
            return 0
        fi
        log "failed to set the admin password (HTTP ${code})"
        return 1
    fi

    if tei_user_exists admin ""; then
        write_passwd_query both
        code=$(http_code admin "" "$REST" "$PASSWD_QUERY")
        cleanup_queries
        if [ "$code" = "200" ] && login_ok admin "$EXIST_ADMIN_PASSWORD" && login_ok tei "$EXIST_TEI_PASSWORD"; then
            clear_pending
            log "set the admin and tei passwords"
            return 0
        fi
        if login_ok admin "$EXIST_ADMIN_PASSWORD"; then
            mark_pending
            log "set the admin password; will set the tei password next"
            finish_tei admin "$EXIST_ADMIN_PASSWORD"
            return $?
        fi
        log "failed to set the admin password (HTTP ${code})"
        return 1
    fi

    write_passwd_query admin
    code=$(http_code admin "" "$REST" "$PASSWD_QUERY")
    cleanup_queries
    if [ "$code" != "200" ] || ! login_ok admin "$EXIST_ADMIN_PASSWORD"; then
        log "failed to set the admin password (HTTP ${code})"
        return 1
    fi
    mark_pending
    log "set the admin password; waiting for the tei user"
    return 1
}

init_passwords() {
    while true; do
        if [ "${EXIST_INIT_STOP:-0}" = "1" ]; then
            return 1
        fi
        if [ -n "${java_pid:-}" ] && ! "$BUSY" kill -0 "$java_pid" 2>/dev/null; then
            log "eXist-db exited before password initialization finished"
            return 1
        fi
        init_once
        status=$?
        cleanup_queries
        if [ "$status" -eq 0 ]; then
            "$BUSY" rm -f "$EXISTS_QUERY"
            return 0
        fi
        if [ "$status" -eq 2 ]; then
            return 1
        fi
        "$BUSY" sleep 5
    done
}

case "${0##*/}" in
    set-passwords.sh)
        init_passwords
        exit $?
        ;;
esac
