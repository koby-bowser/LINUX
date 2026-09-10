#!/usr/bin/env bash
# Hook d'authentification DNS-01 pour certbot --manual — backend PowerDNS (th2-dnsp-mst1).
# Utilise SSH passwordless vers superuser@172.30.198.162:30 et pdnsutil.
set -euo pipefail

: "${CERTBOT_DOMAIN:?CERTBOT_DOMAIN non défini}"
: "${CERTBOT_VALIDATION:?CERTBOT_VALIDATION non défini}"

# Déterminer la zone PowerDNS et le label relatif
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

# 1. Écriture du TXT et bump serial sur le master PowerDNS via pdnsutil
ssh -p "${SSH_PORT}" -o BatchMode=yes -o StrictHostKeyChecking=accept-new "${SSH_USER}@${PDNS_HOST}" \
  "sudo pdnsutil replace-rrset '${ZONE}' '${LABEL}' TXT 60 '\"${CERTBOT_VALIDATION}\"' && sudo pdnsutil increase-serial '${ZONE}'"

# 2. Vérification de la propagation
FULL_RECORD="${LABEL}.${ZONE}"

check_both_resolvers() {
  local g c
  g="$(curl -s "https://dns.google/resolve?name=${FULL_RECORD}.&type=TXT" \
    | jq -r '.Answer[]?.data // empty' 2>/dev/null | tr -d '"')"
  c="$(curl -s -H 'accept: application/dns-json' \
    "https://cloudflare-dns.com/dns-query?name=${FULL_RECORD}.&type=TXT" \
    | jq -r '.Answer[]?.data // empty' 2>/dev/null | tr -d '"')"
  [ "${g}" = "${CERTBOT_VALIDATION}" ] && [ "${c}" = "${CERTBOT_VALIDATION}" ]
}

required_consecutive=2
consecutive_ok=0
for i in $(seq 1 30); do
  if check_both_resolvers; then
    consecutive_ok=$((consecutive_ok + 1))
    if [ "${consecutive_ok}" -ge "${required_consecutive}" ]; then
      sleep 5
      exit 0
    fi
  else
    consecutive_ok=0
  fi
  sleep 4
done

# Repli : vérification directe sur le master autoritaire
local_found="$(dig +short TXT "${FULL_RECORD}" @"${PDNS_HOST}" 2>/dev/null | tr -d '"')"
if [ "${local_found}" = "${CERTBOT_VALIDATION}" ]; then
  sleep 20
  exit 0
fi

echo "Timeout en attendant la propagation du TXT ${FULL_RECORD}" >&2
exit 1
