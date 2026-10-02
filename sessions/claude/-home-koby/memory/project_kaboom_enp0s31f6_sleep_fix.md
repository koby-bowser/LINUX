---
name: project-kaboom-enp0s31f6-sleep-fix
description: "PC Debian Trixie \"Kaboom\" perd enp0s31f6 (carte Intel I219-LM/e1000e) après un réveil de veille prolongée ; hook systemd-sleep déployé et fonctionnel"
metadata: 
  node_type: memory
  type: project
  originSessionId: d7900472-ed21-4d51-9adc-847c0eee4f7e
  modified: 2026-08-26T09:31:34.320Z
---

Le PC Debian Trixie de l'utilisateur ("Kaboom") perd la liaison réseau sur `enp0s31f6` (Intel I219-LM, driver `e1000e`, PCI `0000:00:1f.6`) après un réveil de mise en veille prolongée — auparavant nécessitait un reboot complet pour la retrouver.

**Fix en place** : hook systemd-sleep à `/usr/lib/systemd/system-sleep/enp0s31f6-fix`, exécuté automatiquement au resume. Il fait un unbind/bind du driver `e1000e` sur le device PCI (un simple `ip link set up` ne suffit pas), puis `ip link set up` + `nmcli device connect`. Loggue via `logger -t enp0s31f6-fix` (consultable avec `journalctl -t enp0s31f6-fix`).

Vérifié fonctionnel le 2026-08-25 : hook déclenché au resume, l'interface est repassée UP en ~1min30 (le temps que le driver se réinitialise), DHCP/gateway/DNS/HTTPS tous OK ensuite. Point d'attention : un `ping` vers une IP externe (8.8.8.8, google.com) peut sembler échouer alors que le réseau fonctionne — c'est l'ICMP sortant qui est filtré par le firewall corp, pas un signe de panne. Toujours valider avec `curl -sI https://...` ou en pingant la passerelle locale plutôt que l'extérieur.

**Why** : régression matérielle connue de la carte Intel I219-LM sous e1000e après suspend prolongé ; corrigée par un rebind PCI plutôt qu'un simple toggle du lien.

**How to apply** : si le réseau manque après un réveil, vérifier d'abord `journalctl -t enp0s31f6-fix` avant de suspecter autre chose. Il existe un sous-agent dédié `drybowser-enp0s31f6` pour diagnostiquer une régression sur ce hook ou l'adapter si le matériel change.

**Régression constatée le 2026-08-25 (soir)** : le hook s'est déclenché au réveil mais le `sleep 1`/`sleep 2` entre unbind et bind est insuffisant — l'interface est restée `DOWN/NO-CARRIER` après le bind (renégociation du lien I219-LM pas encore terminée), forçant un reboot complet.

**Patch v2 déployé le 2026-08-26** (installé en root, `-rwxr-xr-x root:root`, vérifié sur disque) : le `sleep` fixe post-bind est remplacé par une fonction `wait_for_carrier()` qui poll `/sys/class/net/enp0s31f6/carrier` toutes les secondes (max 10s), loggée. Si toujours pas de carrier après 10s, fallback automatique `modprobe -r e1000e && sleep 2 && modprobe e1000e` puis un second polling (max 10s). Si le carrier reste absent même après ce fallback, log `ATTENTION` explicite (intervention manuelle probable). Logging détaillé à chaque étape via `logger -t enp0s31f6-fix`. Pire cas ~25-27s avant que `nmcli device connect` ne soit tenté (borné, contre un blocage définitif nécessitant reboot auparavant).

**Non encore validé** : ce patch v2 n'a pas été testé sur un vrai cycle suspend/resume (relecture + vérification syntaxique `bash -n`/`sh -n` seulement, faites par le sous-agent `drybowser-enp0s31f6`). À confirmer à la prochaine veille prolongée réelle — vérifier `journalctl -t enp0s31f6-fix` après réveil pour voir si le polling/fallback s'est comporté comme prévu.

**Échec du patch v2 constaté le 2026-08-31** : au réveil (~13:05), le hook v2 s'est déclenché normalement (unbind/bind, polling 10s, fallback modprobe -r/modprobe, second polling 10s) mais le carrier n'est JAMAIS revenu — `nmcli device connect` a échoué avec "device has no carrier" à chaque étape. L'utilisateur a reproduit la même séquence manuellement en root (unbind/bind, modprobe -r/modprobe) sans plus de succès. Seul un reboot complet a restauré le réseau.

**Diagnostic root cause (sous-agent `drybowser-enp0s31f6`, 2026-08-31)** : les logs kernel ne montrent jamais de "NIC Link is Up" après resume, quelle que soit l'action tentée côté driver. Le mode de veille actif sur Kaboom est confirmé `deep` (vrai S3 ACPI, pas s2idle — `cat /sys/power/mem_sleep`). Le unbind/bind et le modprobe reload réinitialisent bien le driver/MAC (toujours en D0) mais **ne touchent pas le domaine d'alimentation du PHY géré par le PCH/firmware** — seul un reboot complet (POST BIOS, vrai power-cycle du PCH) le restaure. C'est un problème documenté et non résolu en amont pour I219-LM/e1000e après S3 (Gentoo Forums, RedHat KB #5015431, Launchpad #660302, thread LKML e1000e regressions v6.10-rc7) — **aucune solution purement logicielle côté OS (unbind/bind, modprobe, ni même un reset PCI `.../reset`) ne peut le corriger**, car pour un LOM intégré au PCH ce n'est généralement pas supporté en FLR et ça reste en D0 de toute façon.

**Pistes à explorer avant toute v3 du hook** (non appliquées, nécessitent accès physique ou test coupant le réseau) :
1. **BIOS/UEFI** : désactiver **ErP/EuP "Ready"** si présent (coupe l'alim 5V standby du port LAN pendant S3 ; bug de reséquençage documenté à la sortie). Vérifier aussi le réglage Wake-on-LAN / "Resume using PCI-E device" (combo lien Gigabit + WoL activé + link down avant suspend cité comme déclencheur possible, cf. bug upstream #216926).
2. **Test ciblé avant suspend** : `ethtool -s enp0s31f6 wol d` (désactiver WoL) et/ou forcer un lien 100 Mb/s (`ethtool -s enp0s31f6 speed 100 duplex full autoneg off`) avant mise en veille, pour voir si ça change le comportement au réveil.
3. **v3 du hook (proposée, pas déployée)** : ajouter un niveau de diagnostic (pas de correctif) en cas d'échec final — dumper `ethtool`, `ethtool -d`, et `power/runtime_status` du device PCI dans `/var/log/enp0s31f6-fix-debug.log` pour alimenter un futur rapport de bug upstream.
4. Un reboot automatique en dernier recours a été envisagé mais jugé dangereux (perte de session) — à ne considérer qu'avec confirmation explicite.

**Conclusion actuelle** : le problème dépasse ce qu'un hook systemd-sleep peut corriger de façon fiable — la vraie cause est probablement matérielle/firmware (BIOS ErP/EuP ou séquencement PHY par le PCH), pas le driver e1000e lui-même.

**Machine identifiée (2026-08-31)** : FUJITSU CELSIUS W5010, carte mère D3817-A1 (`S26361-D3817-A13`), BIOS Fujitsu V5.0.0.17 R1.51.0 (05/16/2022), firmware Aptio (touche F2 au boot). Fujitsu n'utilise pas le libellé "ErP Ready" — par analogie avec d'autres cartes Fujitsu de la même génération (D3375, ESPRIMO Q558), le réglage équivalent est probablement **Power (ou Power Management) → Wake-Up Resources → LAN** (à désactiver, ou l'inverse selon libellé exact — à vérifier physiquement, non confirmé sur ce firmware précis). PME# PCI déjà actif : `/sys/bus/pci/devices/0000:00:1f.6/power/wakeup` = `enabled`.

**Test WoL préparé mais non exécuté (2026-08-31)** — le sous-agent n'a pas de sudo fonctionnel dans son environnement, donc l'utilisateur doit lancer lui-même :
```
sudo ethtool -s enp0s31f6 wol d
nmcli connection modify koby-bowser-link 802-3-ethernet.wake-on-lan none
```
Le profil NetworkManager de la connexion s'appelle `koby-bowser-link`, actuellement en `802-3-ethernet.wake-on-lan: default` (le pilote e1000e applique son défaut au boot, probablement `g`/magic packet activé sur I219). Sans le `nmcli connection modify ... none`, un `ethtool wol d` à chaud ne survit pas à un reboot complet. Ce test ne pourra être validé qu'au prochain vrai cycle de veille prolongée S3 (vérifier `journalctl -b 0 -t enp0s31f6-fix` + `ip -brief link show enp0s31f6` après réveil).

**Confirmé le 2026-08-31** : `sudo ethtool enp0s31f6 | grep -i wake` → `Supports Wake-on: pumbg` / `Wake-on: g` (magic packet activé). Correspond exactement à l'hypothèse du bug upstream #216926 (lien Gigabit + WoL actif + link down avant suspend comme déclencheur).

**WoL désactivé le 2026-08-31 13:38-13:46** : `sudo ethtool -s enp0s31f6 wol d` exécuté → `Wake-on: d` confirmé. `nmcli connection modify koby-bowser-link 802-3-ethernet.wake-on-lan none` exécuté sans erreur ; `nmcli connection show koby-bowser-link` affiche `802-3-ethernet.wake-on-lan: --` (vide, cohérent avec "none" pour ce champ bitmask — nmcli n'affiche pas le mot "none" littéralement pour valeur 0). **Persistance après reboot non encore vérifiée** — à confirmer avec `sudo ethtool enp0s31f6 | grep -i wake` après un prochain redémarrage complet (doit encore afficher `Wake-on: d`).

**Prochaine étape** : tester au prochain vrai cycle de veille prolongée (S3) si l'interface revient UP normalement. Vérifier `journalctl -b 0 -t enp0s31f6-fix` et `ip -brief link show enp0s31f6` après le réveil. Piste BIOS ErP/EuP (Power → Wake-Up Resources → LAN sur ce Fujitsu D3817-A1) reste à essayer si le test WoL ne suffit pas.
