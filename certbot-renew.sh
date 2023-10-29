#!/bin/sh

# renew at this many days left before a cert will expire
MAXDAYS=30

# comment out for mostly silent behavior
#VERBOSE=yes

BASEDIR=./certbot/conf/live


num_found=0
num_renew=0
maxsecs=$(( MAXDAYS * 86400 ))

cd $(dirname "$0")

checkcert() {
    local _dnsname=$1
    local _file=${BASEDIR}/${_dnsname}/cert.pem

    [ -n $VERBOSE ] && echo "Checking cert $_dnsname (file $_file) ..."
    if ! openssl x509 -in $_file -checkend $maxsecs >/dev/null
    then
	num_renew=$((num_renew + 1))
	echo "Certificate for $_dnsname is near expiry date!"
    else
	[ -n $VERBOSE ] && echo "Certificate $_dnsname still valid."
    fi
    num_found=$((num_found + 1))
}

for d in $BASEDIR/*; do
    [ -d $d ] && [ -f $d/cert.pem ] && checkcert ${d#${BASEDIR}/}
done

# warn and exit if no certs found
if [ $num_found -eq 0 ]
then
    echo "WARNING: no certificates found for renewal check!"
    exit 1
fi

# if any cert expires in $MAXDAYS days or less, run certbot renew action
if [ $num_renew -gt 0 ]
then
    echo "Renewing $num_renew certificates ..."
    docker compose run --rm certbot renew
    docker compose restart frontend
    chmod +x ${BASEDIR}
    chmod +x ${BASEDIR}/../archive/
    chmod -R +r ${BASEDIR}/../archive/
else
    [ -n $VERBOSE ] && echo "Certificate(s) still valid"
fi
