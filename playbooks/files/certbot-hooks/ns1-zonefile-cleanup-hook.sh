#!/usr/bin/env bash
# Hook de nettoyage DNS-01 pour certbot --manual — backend ns1/BIND (zonefile).
# Appelé par certbot après validation (succès ou échec) pour retirer le TXT.
set -euo pipefail

: "${NS1_SSH_ALIAS:?NS1_SSH_ALIAS non défini}"
: "${NS1_SUDO_PASS:?NS1_SUDO_PASS non défini}"
: "${NS1_ZONE_FILE:?NS1_ZONE_FILE non défini}"
: "${NS1_ZONE_NAME:?NS1_ZONE_NAME non défini}"
: "${CERTBOT_DOMAIN:?CERTBOT_DOMAIN non défini}"

if [ "${CERTBOT_DOMAIN}" = "${NS1_ZONE_NAME}" ]; then
  label="_acme-challenge"
else
  relative="${CERTBOT_DOMAIN%.${NS1_ZONE_NAME}}"
  label="_acme-challenge.${relative}"
fi

# Ne doit jamais faire échouer le nettoyage.
printf '%s\n' "${NS1_SUDO_PASS}" | ssh "${NS1_SSH_ALIAS}" \
  "sudo -S ${NS1_ADMIN_HOME:-/home/admin}/acme-zone-update.sh delete '${label}' '${NS1_ZONE_FILE}' '${NS1_ZONE_NAME}'" \
  2>/dev/null || true
