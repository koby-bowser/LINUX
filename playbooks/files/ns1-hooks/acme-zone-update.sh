#!/bin/sh
# Ajoute ou retire un enregistrement _acme-challenge dans une zone BIND
# éditée à la main, bascule le serial SOA (format YYYYMMDDNN) et recharge.
#
# Usage : acme-zone-update.sh add|delete <label> <zone_file> <zone_name> [value]
#   label     : nom relatif exact du RR, ex. "_acme-challenge.andesite"
#   zone_file : chemin du fichier de zone, ex. /var/named/only.fr
#   zone_name : nom de la zone tel que connu de named, ex. only.fr
#   value     : (add uniquement) contenu du TXT, ex. la valeur CERTBOT_VALIDATION
#
# Doit être exécuté en root (sudo) : le fichier de zone n'est pas lisible
# par un utilisateur normal sur ns1.
#
# GARDE-FOUS DE FORMAT : ce script suppose (1) un serial SOA purement
# numérique avec un commentaire "; serial" sur la même ligne, et (2) des
# enregistrements TXT sur une seule ligne. Ces hypothèses sont validées
# ci-dessous — sur une zone jamais testée dont le format diffère, le script
# s'arrête AVANT toute modification plutôt que de risquer de corrompre le
# fichier réel.
set -e

action="$1"
label="$2"
zonefile="$3"
zonename="$4"
value="$5"

if [ -z "$action" ] || [ -z "$label" ] || [ -z "$zonefile" ] || [ -z "$zonename" ]; then
  echo "Usage: $0 add|delete <label> <zone_file> <zone_name> [value]" >&2
  exit 2
fi

if [ ! -r "$zonefile" ]; then
  echo "GARDE-FOU : fichier de zone illisible : $zonefile" >&2
  exit 1
fi

# --- Garde-fou 1 : le serial SOA doit être trouvé et purement numérique ---
current_serial=$(awk '/;[[:space:]]*serial/ {print $1; exit}' "$zonefile")
case "$current_serial" in
  '')
    echo "GARDE-FOU : aucune ligne de serial SOA avec commentaire '; serial' trouvée dans $zonefile — format non reconnu, abandon avant toute modification." >&2
    exit 1
    ;;
  *[!0-9]*)
    echo "GARDE-FOU : le serial détecté ('$current_serial') n'est pas purement numérique — format non reconnu, abandon avant toute modification." >&2
    exit 1
    ;;
esac

# --- Garde-fou 2 : sauvegarde automatique avant toute modification ---
backup="${zonefile}.bak.$(date +%Y%m%d%H%M%S)"
cp "$zonefile" "$backup"

tmpfile="${zonefile}.acme.tmp.$$"

# Retirer toute ligne existante dont le premier champ correspond exactement
# au label (évite les doublons/résidus d'une précédente émission).
awk -v label="$label" '$1 != label' "$zonefile" > "$tmpfile"

if [ "$action" = "add" ]; then
  if [ -z "$value" ]; then
    echo "add nécessite une valeur" >&2
    rm -f "$tmpfile"
    exit 2
  fi
  printf '%s\tTXT\t"%s"\n' "$label" "$value" >> "$tmpfile"
fi

# Faire avancer le serial SOA (format YYYYMMDDNN observé dans ce fichier).
today=$(date +%Y%m%d)
case "$current_serial" in
  "${today}"*)
    rev=$(echo "$current_serial" | cut -c9-10)
    new_rev=$(printf '%02d' $((10#$rev + 1)))
    new_serial="${today}${new_rev}"
    ;;
  *)
    new_serial="${today}01"
    ;;
esac
sed -i "s/^\([[:space:]]*\)${current_serial}\([[:space:]]*;[[:space:]]*serial\)/\1${new_serial}\2/" "$tmpfile"

# --- Garde-fou 3 : vérifier que le serial a réellement été remplacé ---
if ! grep -q "${new_serial}[[:space:]]*;[[:space:]]*serial" "$tmpfile"; then
  echo "GARDE-FOU : le remplacement du serial SOA a échoué (aucune occurrence de '${new_serial} ; serial' après sed) — abandon, rien n'est écrasé." >&2
  rm -f "$tmpfile"
  exit 1
fi

# --- Garde-fou 4 (déjà présent) : valider la zone avant d'écraser le réel ---
if command -v named-checkzone >/dev/null 2>&1; then
  if ! named-checkzone "$zonename" "$tmpfile" >/tmp/acme-zone-check.$$ 2>&1; then
    echo "GARDE-FOU : named-checkzone a rejeté le nouveau fichier — abandon, rien n'est écrasé :" >&2
    cat /tmp/acme-zone-check.$$ >&2
    rm -f "$tmpfile" /tmp/acme-zone-check.$$
    exit 1
  fi
  rm -f /tmp/acme-zone-check.$$
else
  echo "AVERTISSEMENT : named-checkzone absent — la nouvelle zone n'est PAS validée avant écrasement." >&2
fi

mv "$tmpfile" "$zonefile"
rndc reload "$zonename" >/dev/null

# Garder seulement les 20 sauvegardes les plus récentes par zone, pour ne
# pas accumuler indéfiniment.
ls -t "${zonefile}.bak."* 2>/dev/null | tail -n +21 | xargs -r rm -f
