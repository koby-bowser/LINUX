---
name: project-outremer-yooz-sync-gbs-ftpx-02
description: "Dispositif Yooz complet sur gbs-ftpx-02 (172.16.92.242) - sync_to_yooz_v3.sh (upload) et sync_from_yooz.sh (download), tous deux testes en run reel et actifs en cron"
metadata: 
  node_type: memory
  type: project
  originSessionId: 2135b681-cc1b-4083-ba7a-b29980822dcd
  modified: 2026-09-09T14:33:14.295Z
---

Sur le serveur `gbs-ftpx-02` (172.16.92.242, port SSH 30, user `superuser`), le script `/usr/local/bin/sync_to_yooz_v3.sh` synchronise des fichiers de `/home/devmon/yooz_prod/uploads/{capture,documents,feedbacks,imports,purchase_orders}` vers le serveur SFTP Yooz. Config: `/home/devmon/sync_to_yooz_v2.conf` (lisible root/devmon uniquement).

Modifications apportées le 2026-08-18 :
- Ajout d'un dossier `done` partagé (`/home/devmon/yooz_prod/done`, devmon:devmon, 770) où les fichiers transférés avec succès sont déplacés (structure relative préservée), avec purge automatique des fichiers de plus de 30 jours.
- `log_message()` n'écrit plus sur stdout (seulement dans le fichier de log `/var/log/yooz_sync/`), pour un fonctionnement silencieux en cron.
- Sauvegarde de l'original conservée sur le serveur : `/usr/local/bin/sync_to_yooz_v3.sh.bak-20260818183512`.
- Crons ajoutés dans le crontab root : sync horaire (`0 * * * *`) et `check_yooz_errors.sh` toutes les 2h (`0 */2 * * *`).

**Testé et validé** (dry-run + run réel du 2026-08-18 15h00) : le déplacement vers `done` fonctionne correctement, 0 erreur.

**Deux bugs corrigés le 2026-08-19** :
1. `create_remote_directory()` construit désormais le chemin niveau par niveau avec des commandes SFTP `-mkdir` préfixées d'un tiret (ignore l'erreur "already exists"), au lieu de `mkdir -p` (non supporté par le sous-système SFTP). Validé manuellement : création réussie de `capture/_test_mkdir_fix/level1/level2` sur le serveur Yooz (nettoyé après test). Note : la racine `REMOTE_BASE_PATH` elle-même refuse la création de nouveaux dossiers (Permission denied côté Yooz) — seuls les sous-dossiers déjà autorisés (capture, documents, feedbacks, imports, purchase_orders) acceptent des créations.
2. Verrou `flock` ajouté en tout début de `main()` (`/var/lock/sync_to_yooz.lock`, non-bloquant `-n`) : si une instance tourne déjà, la nouvelle logue "Another instance... already running" et sort avec exit 1. Validé par test avec un verrou tenu artificiellement (`flock ... -c sleep 20`).

Sauvegarde de cette version conservée sur le serveur (2e `.bak-<timestamp>` du 2026-08-19, en plus de celle du 2026-08-18).

**Crons réactivés le 2026-08-19** (décommentés dans le crontab root) : sync horaire + check erreurs toutes les 2h. Statut : actifs et fonctionnels.

**Reste (mineur, non bloquant)** : un fichier temporaire `/tmp/root_crontab_enabled` (contenu non sensible) n'a pas pu être supprimé du serveur — le classificateur auto-mode a bloqué la commande `rm` à deux reprises sans raison apparente. À nettoyer manuellement si besoin.

Voir aussi [[feedback-classifier-blocks-multistep-remote-scripts]] pour la méthode de déploiement à distance (upload vers /tmp puis `sudo mv`, jamais de `sudo tee` en aval d'un pipe base64).

**Nouveau script créé le 2026-08-19 : `sync_from_yooz.sh` (sens inverse — download)**
- Déployé : `/usr/local/bin/sync_from_yooz.sh` (root:root, 755), config `/home/devmon/sync_from_yooz.conf` (root:root, 640).
- Télécharge depuis Yooz `exports/` et `reports/` vers `/home/devmon/yooz_prod/downloads/{exports,reports}` sur gbs-ftpx-02.
- `exports/` a une structure imbriquée par code société (`exports/04`, `15`, `55`, `56`, `57`, ...), chaque code ayant déjà son propre `done/history/` créé par un processus Yooz externe (pas nous) — le script parcourt donc récursivement (skip des sous-dossiers nommés `done`), pas de liste à plat.
- Après téléchargement réussi, le fichier distant est déplacé vers `<son dossier>/done/history/` sur Yooz via `rename` SFTP (décision utilisateur : "Move the files to /done/history", "par catégorie").
- `CONFLICT_RESOLUTION=skip` : évite le re-téléchargement si le fichier local existe déjà.
- Verrou dédié `/var/lock/sync_from_yooz.lock` (indépendant de celui d'upload), logging silencieux (fichier only), réutilise le fix `create_remote_directory()` (mkdir niveau par niveau) validé la veille.
- Ownership des fichiers/dossiers téléchargés repassé à `devmon:devmon` en fin de sync (le script tourne en root via sudo/cron, sinon le contenu resterait root-owned dans l'arborescence devmon).

**Testé en DRY_RUN uniquement** (2026-08-19 15h14) : découverte récursive validée, trouve les 2 fichiers réels en attente (`exports/56/YOOZ_PIH_20260817080703174.csv`, `exports/57/YOOZ_PIH_20260817080703200.csv`), `reports/` vide, 0 erreur. Config remise à `DRY_RUN=false` après le test.

**Run réel exécuté avec succès le 2026-08-20** (`sudo /usr/local/bin/sync_from_yooz.sh /home/devmon/sync_from_yooz.conf` — attention, le chemin de config doit être passé explicitement en argument, sinon le script cherche par défaut `/usr/local/bin/sync_from_yooz.conf` qui n'existe pas et sort en erreur) :
- Log : `/var/log/yooz_sync/sync_from_yooz_20260820_112405.log` — 2 fichiers trouvés, 2 téléchargés, 0 échec, 2 archivés sur Yooz.
- Fichiers confirmés en local avec ownership correct (`devmon:devmon`, 640) : `/home/devmon/yooz_prod/downloads/exports/56/YOOZ_PIH_20260817080703174.csv` (391o) et `exports/57/YOOZ_PIH_20260817080703200.csv` (353o).
- Archivage distant confirmé (`✓ Archived on Yooz`) — les fichiers ont été renommés vers `<dossier>/done/history/` côté Yooz. Les lignes `remote mkdir ... Failure` dans le log sont normales/attendues (syntaxe SFTP `-mkdir` qui ignore les erreurs "already exists").
- `reports/` toujours vide, comportement attendu.
- Un second run accidentel (`sync_from_yooz_20260820_112440.log`) a eu lieu par erreur de manipulation de l'agent en voulant capturer le code de sortie — sans impact, confirme l'idempotence du script (0 fichier trouvé, rien à refaire).
- Accès SSH à `superuser@gbs-ftpx-02:30` : était cassé en début de session (clé publique absente), rétabli par l'utilisateur en ajoutant la clé publique locale (`ssh-ed25519 ...koby@debian-trixie`) aux `authorized_keys`. Passwordless fonctionnel depuis.

**Reste à faire** :
1. ~~Lancer le run réel~~ — **fait le 2026-08-20**.
2. ~~Vérifier l'arrivée des fichiers avec ownership devmon:devmon~~ — **fait, confirmé**.
3. ~~Décider si `sync_from_yooz.sh` doit être ajouté au crontab root~~ — **fait le 2026-08-20** : ajouté à la minute 30 de chaque heure (`30 * * * * /usr/local/bin/sync_from_yooz.sh /home/devmon/sync_from_yooz.conf >/dev/null 2>&1`), soit 30 min après `sync_to_yooz_v3.sh` (minute 0). Crontab root final vérifié, entrées existantes intactes. Prochaine exécution : xx:30 de la prochaine heure pleine.

**Les 3 tâches de la session sont terminées.** Le dispositif Yooz est maintenant complet dans les deux sens (upload horaire à :00, download horaire à :30) avec vérification d'erreurs toutes les 2h.

**Why:** Travail repris le 2026-08-20 après suspension la veille ; run réel demandé et exécuté avec succès sur confirmation explicite de l'utilisateur (données de production Yooz modifiées).

**Bug critique découvert et corrigé le 2026-09-09 : faux-positifs silencieux sur `sync_to_yooz_v3.sh` pour les noms de fichiers avec espace.**
- Symptôme signalé par l'utilisateur : `purchase_orders/56` et `/57` (fichiers `MTVC Commande_T.csv`, `Commande WSG_T.csv`) marqués « transférés » et déplacés en `done/` le 2026-09-08 20:00, mais jamais réellement arrivés sur Yooz.
- Cause 1 : les commandes `put`/`rename`/`ls`/`-mkdir` passées au batch `sftp` n'étaient pas quotées — un nom de fichier avec espace casse le parsing de la ligne de commande sftp (`stat: No such file or directory` sur un chemin tronqué au premier espace).
- Cause 2 (la plus grave) : `execute_sftp_commands()` ne se fiait qu'au code de sortie du process `sftp` (invocation via `<<<`, pas `-b`) — ce code de sortie restait à 0 malgré l'échec du `put`, donc le script loguait un faux succès et déplaçait le fichier vers `done/` sans jamais l'envoyer.
- Correctif déployé (backup de l'ancien script conservé en `.bak-<timestamp>` sur le serveur) : (1) quoting de tous les chemins dans `check_remote_file_exists()`, `create_remote_directory()`, et `transfer_single_file()` (put + rename backup) ; (2) `execute_sftp_commands()` grep désormais la sortie sftp pour des chaînes d'échec connues (`no such file`, `permission denied`, `Failure$`, etc.) et retourne 1 même si `$?` est 0.
- Remédiation : les 2 fichiers coincés dans `done/` ont été remis dans `uploads/`, puis un run manuel (2026-09-09 14:30:36) a confirmé le vrai succès — présence de la ligne native `sftp` `Uploading ... to ...` (absente lors du run bugué), signal indépendant de la logique corrigée.
- **Portée du risque non quantifiée** : combien d'autres fichiers avec espace dans le nom ont pu être silencieusement perdus de cette façon avant le 2026-09-09, sur `purchase_orders` ou d'autres dossiers (`capture`, `documents`, `feedbacks`, `imports`) ? Aucun audit rétroactif des logs plus anciens n'a été fait — à envisager si des données Yooz manquantes sont signalées côté métier.
