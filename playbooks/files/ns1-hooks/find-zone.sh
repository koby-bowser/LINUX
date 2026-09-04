#!/bin/sh
# Trouve, dans named.conf, la zone la plus spécifique qui héberge un domaine
# donné, et le chemin absolu de son fichier de zone.
#
# Usage : find-zone.sh <domaine>
# Sortie (stdout, si trouvé) : "<zone>\t<chemin_absolu_du_fichier>"
# Doit être exécuté en root (sudo) : named.conf n'est pas lisible par un
# utilisateur normal sur ns1.
set -e

domain="$1"
conf="/etc/named.conf"

if [ -z "$domain" ]; then
  echo "Usage: $0 <domaine>" >&2
  exit 2
fi

directory=$(awk -F'"' '/^[[:space:]]*directory[[:space:]]+"/ {print $2; exit}' "$conf")
[ -z "$directory" ] && directory="/var/named"

candidate="$domain"
while [ -n "$candidate" ]; do
  line=$(grep -n "zone[[:space:]]\+\"${candidate}\"" "$conf" | head -n1 | cut -d: -f1)
  if [ -n "$line" ]; then
    filerel=$(sed -n "${line},$((line + 15))p" "$conf" | awk -F'"' '/file[[:space:]]+"/ {print $2; exit}')
    if [ -n "$filerel" ]; then
      case "$filerel" in
        /*) filepath="$filerel" ;;
        *) filepath="${directory}/${filerel}" ;;
      esac
      printf '%s\t%s\n' "$candidate" "$filepath"
      exit 0
    fi
  fi
  case "$candidate" in
    *.*) candidate="${candidate#*.}" ;;
    *) candidate="" ;;
  esac
done

echo "Aucune zone trouvée pour $domain dans $conf" >&2
exit 1
