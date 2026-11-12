# Starts eXist-db, then sets the admin and tei passwords when admin is still empty.
# The image is distroless, so this script runs with the mounted static busybox.

BUSY=/exist-init/bin/busybox
WEB_XML=${EXIST_WEB_XML:-/exist/etc/webapp/WEB-INF/web.xml}

if [ "$#" -eq 0 ]; then
    set -- jetty
fi

# Every path below /exist/apps/ that an app does not handle itself ends up in
# eXist's REST servlet, which by default runs XQuery sent by anyone, including
# guest (?_query=, ?_xpath=, POSTed <query> documents). Turn query and XUpdate
# submission off before eXist-db starts. Stored XQuery modules of apps are not
# affected. EXIST_REST_SUBMISSION: disabled (default), authenticated or enabled.
# authenticated still lets anyone in who sends valid credentials, including the
# guest account (guest:guest by default).
restrict_rest() {
    mode=${EXIST_REST_SUBMISSION:-disabled}
    case "$mode" in
        enabled|disabled|authenticated) ;;
        *)
            printf '%s\n' "[exist-init] invalid EXIST_REST_SUBMISSION '$mode'; using disabled" >&2
            mode=disabled
            ;;
    esac
    if [ ! -w "$WEB_XML" ]; then
        printf '%s\n' "[exist-init] cannot write $WEB_XML; REST query submission left unchanged" >&2
        return
    fi
    for param in xquery-submission xupdate-submission; do
        "$BUSY" sed -i "/<param-name>${param}<\/param-name>/{n;s|<param-value>[^<]*</param-value>|<param-value>${mode}</param-value>|}" "$WEB_XML"
    done
    printf '%s\n' "[exist-init] REST query and XUpdate submission: $mode" >&2
}
restrict_rest

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
