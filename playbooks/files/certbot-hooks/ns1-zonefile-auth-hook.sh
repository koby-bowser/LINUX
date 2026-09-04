#!/usr/bin/env bash
# Hook d'authentification DNS-01 pour certbot --manual — backend ns1/BIND,
# édition directe du fichier de zone via SSH (pas de RFC2136 disponible).
#
# Certbot appelle ce script avec CERTBOT_DOMAIN et CERTBOT_VALIDATION.
# Variables d'environnement attendues (jamais écrites en fichier) :
#   NS1_SSH_ALIAS   : alias SSH (voir ~/.ssh/config, ex. "ns1")
#   NS1_DNS_HOST    : IP/hostname DNS de ns1 pour les requêtes dig (ex. 172.16.75.250)
#   NS1_SUDO_PASS   : mot de passe sudo de l'utilisateur SSH sur ns1
#   NS1_ZONE_FILE   : chemin du fichier de zone, ex. /var/named/only.fr
#   NS1_ZONE_NAME   : nom de la zone, ex. only.fr
set -euo pipefail

: "${NS1_SSH_ALIAS:?NS1_SSH_ALIAS non défini}"
: "${NS1_DNS_HOST:?NS1_DNS_HOST non défini}"
: "${NS1_SUDO_PASS:?NS1_SUDO_PASS non défini}"
: "${NS1_ZONE_FILE:?NS1_ZONE_FILE non défini}"
: "${NS1_ZONE_NAME:?NS1_ZONE_NAME non défini}"
: "${CERTBOT_DOMAIN:?CERTBOT_DOMAIN non défini}"
: "${CERTBOT_VALIDATION:?CERTBOT_VALIDATION non défini}"

if [ "${CERTBOT_DOMAIN}" = "${NS1_ZONE_NAME}" ]; then
  label="_acme-challenge"
else
  relative="${CERTBOT_DOMAIN%.${NS1_ZONE_NAME}}"
  label="_acme-challenge.${relative}"
fi

printf '%s\n' "${NS1_SUDO_PASS}" | ssh "${NS1_SSH_ALIAS}" \
  "sudo -S ${NS1_ADMIN_HOME:-/home/admin}/acme-zone-update.sh add '${label}' '${NS1_ZONE_FILE}' '${NS1_ZONE_NAME}' '${CERTBOT_VALIDATION}'" \
  2>/dev/null

# Attendre la propagation. NE PAS se contenter d'interroger le maître
# interne (NS1_DNS_HOST) : il a la donnée immédiatement par définition
# (c'est la source), ça ne prouve rien sur ce que voit Let's Encrypt, qui
# interroge les secondaires PUBLICS (ns1/ns2.outremer-telecom.fr). Le port
# 53 public n'est pas joignable depuis ce réseau d'entreprise (pare-feu) —
# on vérifie donc via DNS-over-HTTPS (HTTPS classique, port 443).
#
# Un seul résolveur qui répond correctement UNE fois ne suffit pas : cet
# ISP a une infra régionale multi-territoires (Martinique, Guadeloupe,
# Réunion, Guyane, Mayotte...), probablement plusieurs instances physiques
# derrière ns1/ns2 dont la convergence n'est pas parfaitement synchrone —
# constaté en test réel (un domaine validé correctement, un autre juste
# après a échoué avec l'ancienne valeur résiduelle malgré une confirmation
# DoH positive). On exige donc : deux résolveurs publics indépendants
# d'accord (Google + Cloudflare), sur plusieurs passages consécutifs, plus
# une marge de sécurité avant de rendre la main à certbot.
check_both_resolvers() {
  g="$(curl -s "https://dns.google/resolve?name=${label}.${NS1_ZONE_NAME}.&type=TXT" \
    | jq -r '.Answer[]?.data // empty' | tr -d '"')"
  c="$(curl -s -H 'accept: application/dns-json' \
    "https://cloudflare-dns.com/dns-query?name=${label}.${NS1_ZONE_NAME}.&type=TXT" \
    | jq -r '.Answer[]?.data // empty' | tr -d '"')"
  [ "${g}" = "${CERTBOT_VALIDATION}" ] && [ "${c}" = "${CERTBOT_VALIDATION}" ]
}

required_consecutive=3
consecutive_ok=0
for i in $(seq 1 40); do
  if check_both_resolvers; then
    consecutive_ok=$((consecutive_ok + 1))
    if [ "${consecutive_ok}" -ge "${required_consecutive}" ]; then
      # Marge supplémentaire pour laisser converger d'éventuels nœuds
      # secondaires additionnels que ni Google ni Cloudflare n'ont interrogés.
      sleep 15
      exit 0
    fi
  else
    consecutive_ok=0
  fi
  sleep 5
done

echo "Timeout en attendant la propagation publique convergente (DoH, double résolveur) du TXT ${label}.${NS1_ZONE_NAME}." >&2
exit 1
