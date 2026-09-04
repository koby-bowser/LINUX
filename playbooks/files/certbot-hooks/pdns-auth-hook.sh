#!/usr/bin/env bash
# Hook d'authentification DNS-01 pour certbot --manual — backend PowerDNS (dnsp-mst).
#
# Certbot appelle ce script avec CERTBOT_DOMAIN et CERTBOT_VALIDATION dans
# l'environnement. PDNS_API_URL, PDNS_API_KEY et PDNS_DNS_HOST doivent être
# fournis dans l'environnement par la tâche Ansible qui invoque certbot
# (jamais écrits en dur dans ce fichier ni dans un fichier de credentials).
set -euo pipefail

: "${PDNS_API_URL:?PDNS_API_URL non défini}"
: "${PDNS_API_KEY:?PDNS_API_KEY non défini}"
: "${PDNS_DNS_HOST:?PDNS_DNS_HOST non défini}"
: "${CERTBOT_DOMAIN:?CERTBOT_DOMAIN non défini}"
: "${CERTBOT_VALIDATION:?CERTBOT_VALIDATION non défini}"

record_name="_acme-challenge.${CERTBOT_DOMAIN}."
zone="${CERTBOT_DOMAIN}."

curl -sf -X PATCH \
  -H "X-API-Key: ${PDNS_API_KEY}" \
  -H "Content-Type: application/json" \
  "${PDNS_API_URL}/servers/localhost/zones/${zone}" \
  -d "{\"rrsets\":[{\"name\":\"${record_name}\",\"type\":\"TXT\",\"ttl\":60,\"changetype\":\"REPLACE\",\"records\":[{\"content\":\"\\\"${CERTBOT_VALIDATION}\\\"\",\"disabled\":false}]}]}" \
  >/dev/null

# Attendre la propagation en interrogeant directement le serveur autoritaire
# (pas un résolveur public, qui pourrait mettre en cache une réponse négative).
for _ in $(seq 1 30); do
  found="$(dig +short TXT "${record_name}" @"${PDNS_DNS_HOST}" | tr -d '"')"
  if [ "${found}" = "${CERTBOT_VALIDATION}" ]; then
    exit 0
  fi
  sleep 2
done

echo "Timeout en attendant la propagation du TXT ${record_name} sur ${PDNS_DNS_HOST}" >&2
exit 1
