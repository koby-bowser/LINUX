#!/usr/bin/env bash
# Hook de nettoyage DNS-01 pour certbot --manual — backend PowerDNS (th2-dnsp-mst1).
# Appelé par certbot après la validation (succès ou échec) pour retirer le TXT.
set -euo pipefail

: "${CERTBOT_DOMAIN:?CERTBOT_DOMAIN non défini}"

if [[ "${CERTBOT_DOMAIN}" =~ outremer-telecom\.fr$ ]]; then
  ZONE="outremer-telecom.fr"
elif [[ "${CERTBOT_DOMAIN}" =~ redcaraibe\.fr$ ]]; then
  ZONE="redcaraibe.fr"
elif [[ "${CERTBOT_DOMAIN}" =~ sfrcaraibe\.fr$ ]]; then
  ZONE="sfrcaraibe.fr"
elif [[ "${CERTBOT_DOMAIN}" =~ only\.fr$ ]]; then
  ZONE="only.fr"
else
  ZONE="${CERTBOT_DOMAIN}"
fi

if [ "${CERTBOT_DOMAIN}" = "${ZONE}" ]; then
  LABEL="_acme-challenge"
else
  RELATIVE="${CERTBOT_DOMAIN%.${ZONE}}"
  LABEL="_acme-challenge.${RELATIVE%.}"
fi

PDNS_HOST="${PDNS_DNS_HOST:-172.30.198.162}"
SSH_USER="superuser"
SSH_PORT="30"

ssh -p "${SSH_PORT}" -o BatchMode=yes -o StrictHostKeyChecking=accept-new "${SSH_USER}@${PDNS_HOST}" \
  "sudo pdnsutil delete-rrset '${ZONE}' '${LABEL}' TXT && sudo pdnsutil increase-serial '${ZONE}'" 2>/dev/null || true
