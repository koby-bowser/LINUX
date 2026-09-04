#!/usr/bin/env bash
# Hook de nettoyage DNS-01 pour certbot --manual — backend PowerDNS (dnsp-mst).
# Appelé par certbot après la validation (succès ou échec) pour retirer le TXT.
set -euo pipefail

: "${PDNS_API_URL:?PDNS_API_URL non défini}"
: "${PDNS_API_KEY:?PDNS_API_KEY non défini}"
: "${CERTBOT_DOMAIN:?CERTBOT_DOMAIN non défini}"

record_name="_acme-challenge.${CERTBOT_DOMAIN}."
zone="${CERTBOT_DOMAIN}."

# Ne doit jamais faire échouer le nettoyage : certbot doit pouvoir terminer
# proprement même si le enregistrement est déjà absent.
curl -sf -X PATCH \
  -H "X-API-Key: ${PDNS_API_KEY}" \
  -H "Content-Type: application/json" \
  "${PDNS_API_URL}/servers/localhost/zones/${zone}" \
  -d "{\"rrsets\":[{\"name\":\"${record_name}\",\"type\":\"TXT\",\"changetype\":\"DELETE\"}]}" \
  >/dev/null || true
