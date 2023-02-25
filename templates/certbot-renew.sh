#!/bin/sh
cd $(dirname "$0")
CERTFILE=./certbot/conf/live/{{domain}}/cert.pem
MAXDAYS=10

# if cert expires in 10 days or less, run docker action
if ! openssl x509 -in $CERTFILE -checkend $(( MAXDAYS * 86400 )) >/dev/null
then
    docker compose run --rm certbot renew
    docker compose restart frontend
else
    echo "Certificate still valid"
fi
