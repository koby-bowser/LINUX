---
name: project-outremer-telecom-mailserver
description: "État et historique des travaux sur le serveur mail cible Debian d'Outremer Telecom (Postfix/Dovecot/Roundcube) et migration depuis 3 clusters qmail-ldap sources (Guyane/Martinique/Guadeloupe)"
metadata: 
  node_type: memory
  type: project
  originSessionId: 31e2d855-d15f-4e24-b4f0-c7bf43f8304d
  modified: 2026-09-28T15:06:16.646Z
---

## Architecture réelle (comprise le 2026-08-31, corrige toutes les hypothèses précédentes)
Ce n'est PAS 3 clusters qmail-ldap indépendants. C'est **une seule couche de stockage mail physique partagée** (4 hôtes : `quartz.ool.fr`, `emerald.ool.fr`, `diamond.ool.fr`, `andesite.ool.fr` — ce dernier = `smtp-guy-1` lui-même, confirmé par DNS identique depuis guy/gua/mtq : `217.175.160.164` pour quartz), avec **3 annuaires LDAP régionaux distincts** (guy/gua/mtq) qui assignent chacun leurs comptes sur ce même pool via l'attribut `mailHost`. guy et gua ont un LDAP identique (clone figé, mêmes 500 `entryUUID`/répartition mailHost), mtq a sa propre population de 500 comptes distincts mais sur le même pool physique, avec une répartition différente (quartz 132/emerald 196/diamond 107/andesite 51, 486/500 — 14 comptes sans mailHost à creuser). Chaque site utilisateur (Martinique/Guadeloupe/Guyane) a ses "propres" utilisateurs au niveau LDAP/identité, mais le stockage physique est mutualisé. **Implication migration** : l'extraction des Maildirs doit cibler les 4 hôtes de stockage directement, pas guy/gua/mtq comme silos séparés. Risque à vérifier : collision de chemin si un même `uid` existe à la fois dans guy et mtq sur le même mailHost (vérification `comm -12` sur les listes d'uid en cours).

mtq a aussi une petite duplication LDAP interne : 11 `uid` apparaissent deux fois dans des conteneurs différents (`ou=C9`/`ou=C5` etc., ex: `abdouali.mlanao`) avec le même `mailHost` — probablement un doublon d'annuaire cosmétique (même Maildir cible), pas un vrai split. Conteneurs mtq sous `ou=acc,o=ool` : C1,C2,C3,C4,C5,C9 (numérotation trouée, C6-C8 absents), `xts`, `only-entreprise`, `only-entreprises` (typo singulier/pluriel, source de doublon potentielle à vérifier), `only`.

## Cible : mtq-mailsrvp-01
`mtq-mailsrvp-01` (IP 172.30.39.153, SSH port 30, Debian 13.6 trixie) est la **nouvelle plateforme unifiée** Postfix/Dovecot/Roundcube qui doit remplacer 3 clusters qmail legacy. User SSH `superuser`, mot de passe **jamais stocké**, à redemander à chaque session.

**Travaux effectués sur la cible (au 2026-08-14) :** Dovecot corrigé pour authentifier les boîtes virtuelles, mbox→maildir, remise Postfix→Dovecot en LMTP, HTTPS Roundcube (webmail accessible sur `https://postfix.outremer-telecom.fr/`), comptes placeholder `test@`/`koby@` créés pour 5 domaines (only.fr, ool.fr, only-entreprise.fr, box.only.fr, business.ool.fr) — toujours présents au 2026-08-24, fichier `/etc/dovecot/users` (`root:dovecot 640`), format `user:hash:5000:5000:gecos:home:shell:`.

**Tentative de reset des mdp placeholder (2026-08-24) :** BLOQUÉE par le classificateur — `doveadm pw -s SHA512-CRYPT -p '<mdp>'` en SSH direct est refusé systématiquement (action = créer/changer des identifiants de messagerie sur serveur de prod), même en commande unique non-bundlée. L'utilisateur a préféré le faire lui-même (guide fourni : backup fichier, `doveadm pw` par compte, édition manuelle du 2e champ `:` dans `/etc/dovecot/users`, pas de restart dovecot nécessaire — passwd-file relu à chaque auth).

## Sources qmail-ldap : 3 sites indépendants, PAS un seul cluster
Correction majeure du 2026-08-24 (l'hypothèse initiale d'un cluster unique était fausse) :

| Site | Hostname | IP | Comptes | Domaines (répartition) |
|---|---|---|---|---|
| Guyane ("guy") | `smtp-guy-1` (alias `andesite.ool.fr`) | 172.30.33.105:22 | 500 | ool.fr 298, only.fr 162, canalconnect.com 21, only-entreprise.fr 11, business.ool.fr 6, sfrcaraibe.fr 2 |
| Martinique ("mtq") | `smtp-mtq-1` | inconnue | 500 | only.fr 326, sfrcaraibe.fr 117, canalconnect.com 29, only-entreprise.fr 27, business.ool.fr 1 |
| Guadeloupe ("gua") | `smtp-gua-1` | inconnue | 500 (486 active, 14 enabled) | ool.fr 298, only.fr 162, canalconnect.com 21, only-entreprise.fr 11, business.ool.fr 6, sfrcaraibe.fr 2 |

**Chaque site a son propre annuaire LDAP local** (`slapd` sur `localhost:389`, base `ou=acc,o=ool`, **bind anonyme en lecture autorisé** — expose aussi `userPassword` en hash, faille de sécu à corriger indépendamment sur chaque site). Site Guyane (`smtp-guy-1`) éclate en plus ses comptes sur 4 hôtes physiques via l'attribut `mailHost` : quartz.ool.fr (215), emerald.ool.fr (160), diamond.ool.fr (98), andesite.ool.fr = smtp-guy-1 lui-même (27). Pas encore vérifié si mtq/gua font pareil (mailHost multi-hôtes).

**⚠️ Risque critique identifié, pas encore vérifié :** les domaines `only.fr`, `business.ool.fr`, `canalconnect.com`, `only-entreprise.fr`, `sfrcaraibe.fr` existent **à la fois** sur le site Guyane et le site Martinique. Sur la plateforme cible unifiée, une même adresse ne peut exister qu'une fois → il faut comparer les listes d'adresses exactes (`mail`) des 3 sites pour détecter des doublons avant de créer quoi que ce soit côté cible. Pas encore fait faute d'accès complet aux 3 sites.

**✅ Anomalie guy/gua élucidée (2026-08-26) :** confirmation à 100% que `smtp-guy-1` et `smtp-gua-1` partagent le **même jeu de 500 comptes**, pas deux sites indépendants qui coïncident. Preuve : `md5sum` du listing trié des 500 `entryUUID` identique sur les deux hôtes (`3470028dd67309b61a64a4a8969097d3`), mêmes `createTimestamp` (remontant à 2008). Mécanisme exact non déterminé — pas de `syncrepl` dans `/etc/openldap/slapd.d/` sur aucun des deux hôtes, pas de montage NFS/DRBD partagé visible (`mount | grep -i ldap/drbd/nfs` ne montre que le `rpc_pipefs` générique) — donc probablement un clone à froid (VM dupliquée ou restauration `slapcat`/`slapadd` depuis un backup de guy) plutôt qu'une réplication applicative ou stockage live.

**⚠️ Confirmé le 2026-08-31 par l'utilisateur : les 3 sites (`smtp-mtq-1`, `smtp-gua-1`, `smtp-guy-1`) sont TOUS en production**, pas de site dormant/DR. Chaque SMTP sert un département distinct — Martinique (mtq), Guadeloupe (gua), Guyane (guy) — avec ses propres utilisateurs respectifs, selon l'utilisateur.

**⚠️ Point à réconcilier, pas encore fait** : cette affirmation ("chacun a ses propres utilisateurs") semble contredire la preuve technique du 2026-08-26 comparant guy et gua — `md5sum` identique des 500 `entryUUID` triés, mêmes `createTimestamp` (2008), et **même répartition de domaines identique au compte près** (ool.fr 298, only.fr 162, canalconnect.com 21, only-entreprise.fr 11, business.ool.fr 6, sfrcaraibe.fr 2 — sur les deux sites). Si Guyane et Guadeloupe ont vraiment des populations d'utilisateurs distinctes (départements différents), on s'attendrait à des `entryUUID`/répartitions différents, pas identiques au bit près. Deux explications possibles à vérifier, pas encore tranchées :
1. Le LDAP de gua est un clone figé (template initial ou backup) de guy qui n'a jamais été mis à jour avec les vrais utilisateurs de Guadeloupe — la couche LDAP ne reflète pas l'usage réel, seul le contenu des Maildirs le dira.
2. La distinction "par département" est organisationnelle/administrative (quel site gère quoi) mais les données actuelles n'ont pas encore divergé ou n'ont pas été vérifiées à ce niveau.
- Pour trancher : comparer le contenu réel des Maildirs (pas seulement le LDAP) entre guy et gua, et vérifier via `dig +short MX` si le routage DNS distingue bien les deux sites par domaine/département.

**Impact sur le périmètre** : le total réel n'est **pas** ~1500 (3×500) mais **guy(=gua) 500 comptes + mtq 500 comptes indépendants ≈ 1000 comptes** avant dédoublonnage. Martinique (`smtp-mtq-1`) est confirmé indépendant : répartition domaines différente (326 only.fr, 117 sfrcaraibe.fr, 29 canalconnect.com, 27 only-entreprise.fr, 1 business.ool.fr, **pas de ool.fr**), et `accountStatus` 500/500 active (vs 486 active/14 enabled sur guy/gua) — donc pas le même dataset.

**Domaines communs entre guy(=gua) et mtq** (risque de doublons d'adresses à vérifier) : only.fr, business.ool.fr, canalconnect.com, only-entreprise.fr, sfrcaraibe.fr — tous présents des deux côtés. Seul ool.fr est propre à guy/gua (absent de mtq).

**Accès SSH source :** OpenSSH client moderne (10.x) ne supporte plus les clés hôte `ssh-dss` ni le KEX `diffie-hellman-group1-sha1` qu'imposent ces vieux serveurs RHEL5. Solution : venv Python + `paramiko==2.11.0` (versions ≥3 de paramiko ont aussi supprimé DSS/group1). `sysop` sur smtp-guy-1 n'a PAS sudo — accès root/`vmail` nécessaire pour lire les Maildirs réels (`/m/maildirs`, `drwx------ vmail:vmail`), toujours pas obtenu à cette date pour ce site. (Note : l'utilisateur a montré un prompt `root@smtp-guy-1` dans une commande ultérieure — à clarifier comment le root a été obtenu, et si c'est reproductible sur mtq/gua.)

## Pending — prochaine session
1. ~~IP + identifiants SSH pour `smtp-mtq-1`~~ — obtenu, accès root confirmé le 2026-08-26.
2. ~~Élucider l'anomalie guy/gua~~ — résolu 2026-08-26 : même dataset (voir ci-dessus).
3. Vérifier les doublons d'adresses exactes entre guy(=gua) et mtq sur les 5 domaines communs (only.fr, business.ool.fr, canalconnect.com, only-entreprise.fr, sfrcaraibe.fr) — pas encore fait, comparer les `mail` exacts pas juste les comptes par domaine.
4. Vérifier la répartition `mailHost` sur mtq (multi-hôtes comme guy ? — sans objet pour gua puisque c'est le même dataset que guy).
5. Accès root/vmail sur les 3 sites pour lire les Maildirs réels (root LDAP obtenu sur les 3, mais accès Maildir `vmail` pas encore confirmé).
6. Décider du périmètre final : ~1000 comptes (guy/gua fusionnés + mtq), moins doublons d'adresses entre guy et mtq — **à réévaluer** si guy/gua s'avèrent split-brain (voir ci-dessus), auquel cas fusionner leurs comptes ne suffira pas, il faudra fusionner leurs Maildirs.
7. Ajouter côté cible les domaines manquants : `canalconnect.com`, `sfrcaraibe.fr` (confirmés sur guy/gua ET mtq).
8. **Nouvelle priorité (2026-08-31)** : confirmé que guy/gua/mtq sont TOUS actifs en prod. Déterminer le mécanisme de répartition du trafic entre guy et gua (même LDAP, tous deux actifs) :
   - **signal le plus décisif** : `dig +short MX ool.fr` / `dig +short MX only.fr` — voir si le DNS public liste guy ET gua, ou un seul des deux avec l'autre en interne/secours
   - Comparer le contenu des Maildirs d'un même compte sur guy vs gua (`find /m/maildirs/<compte> -newer ...` sur les deux) pour détecter une divergence (signe de split-brain)
   - `ss -tlnp | grep ':25\|:587\|:110\|:143'` sur gua pour confirmer l'écoute réseau active
   - `/var/qmail/bin/qmail-qstat` + logs `/var/log/qmail/smtpd/` sur gua pour voir le volume réel de trafic traité

**How to apply:** Ne jamais supposer que les identifiants (source ET cible, SSH/sudo) sont encore connus — les redemander. Revérifier l'état réel avant d'agir. Voir [[feedback_classifier_blocks_bundled_remote_commands]] pour la granularité des commandes SSH root, et son addendum sur les connexions à un hôte jamais vu (session interactive principale, pas d'agent en arrière-plan). Le classificateur bloque aussi spécifiquement la création/modification d'identifiants de messagerie en SSH distant, indépendamment du bundling — voir tentative du 2026-08-24 ci-dessus.

## Plan de migration validé (2026-09-04) : un domaine à la fois

L'utilisateur a validé une stratégie de migration domaine par domaine plutôt qu'un big-bang. Deux prérequis globaux restent à lever avant d'importer quoi que ce soit côté cible (s'appliquent à tous les domaines issus de guy/gua) :
1. Trancher le mécanisme de répartition de trafic guy vs gua (MX DNS, comparaison Maildir, `ss -tlnp` sur gua) — determine quelle source fait foi.
2. Confirmer l'accès `vmail`/Maildir réel (pas seulement LDAP) sur les 3 sites.

**Ordre des domaines retenu** (du plus petit/simple au plus gros/risqué, comptes guy/gua + mtq) :
1. `business.ool.fr` (6+1=7) — **pilote choisi**, en cours
2. `only-entreprise.fr` (11+27=38)
3. `canalconnect.com` (21+29=50)
4. `sfrcaraibe.fr` (2+117=119)
5. `only.fr` (162+326=488)
6. `ool.fr` (298+0, absent de mtq) — en dernier, car entièrement dépendant du prérequis guy/gua non résolu

**Boucle par domaine** : (1) extraire adresses exactes `mail` sur chaque source touchant le domaine, (2) dédupliquer/isoler les collisions guy/gua vs mtq, (3) localiser le `mailHost` physique par compte, (4) extraire les Maildirs, (5) créer les comptes cible dans `/etc/dovecot/users` (mot de passe **manuel**, classificateur bloque `doveadm pw` en SSH direct), (6) importer les Maildirs et vérifier l'intégrité, (7) déclarer le domaine virtuel côté Postfix si absent, (8) tester login Roundcube + envoi/réception sur un échantillon, (9) bascule MX/DNS, (10) période de vigilance côté source avant décommission.

**État actuel (2026-09-04)** : pilote `business.ool.fr` choisi, plan de 6 domaines validé par l'utilisateur. **Prochaine étape immédiate** : `ldapsearch -x -H ldap://localhost -b "ou=acc,o=ool" "(mail=*@business.ool.fr)" mail` à lancer sur smtp-guy-1 (ou smtp-gua-1) et sur smtp-mtq-1, pour comparer les adresses exactes et détecter une collision avant toute création côté cible. Pas encore exécuté, en attente soit que l'utilisateur le lance et rapporte le résultat, soit qu'il donne un accès SSH direct.

### ⚠️ Découverte critique (2026-09-04) : le pilote `business.ool.fr` n'est pas petit, et les données source sont sales

Le ldapsearch ci-dessus exécuté sur `smtp-mtq-1` a remonté **270 entrées** pour `business.ool.fr` (`numEntries: 270`), pas 1 comme estimé initialement (l'ancien chiffre venait d'une autre mesure, probablement la répartition `mailHost`, pas un comptage réel sur `mail` — **ne plus se fier à l'ancien tableau de comptage par domaine pour mtq, il est faux**). `business.ool.fr` sert manifestement de **domaine générique multi-clients/multi-territoires** hébergé sur l'infra mtq (comptes ADAPEI Martinique confirmés par `st: Martinique`, mais aussi de nombreux comptes de type SDIS avec des noms de communes de La Réunion — `chef.cis.tampon`, `salazie`, `cilaos`, `stleu`, etc. — donc pas un domaine propre à un seul département).

**Défaut de données confirmé (pas un artefact de recherche)** : l'attribut `mail` est stocké littéralement avec un double `@` pour les comptes dont le `uid` est déjà une adresse externe complète, ex. entrée complète vérifiée :
```
uid: noe.mas@adapei-972.fr
mail: noe.mas@adapei-972.fr@business.ool.fr   ← invalide RFC5322, tel quel dans LDAP
mailMessageStore: /var/qmail/maildirs/d2/171/noe.mas@adapei-972.fr
mailHost: emerald.ool.fr
st: Martinique
```
→ **Le vrai chemin Maildir à cibler pour l'extraction suit le `uid`** (`mailMessageStore`), jamais l'attribut `mail` qui peut être corrompu. Confirme aussi que **mtq répartit bien ses comptes sur les hôtes physiques partagés** (`mailHost`) comme guy — point #4 des prérequis globaux en partie levé (mtq fait bien du multi-hôtes, reste à quantifier la répartition complète).

**Prochaine étape (reprise lundi)** : relancer sur mtq `ldapsearch -x -H ldap://localhost -b "ou=acc,o=ool" "(mail=*@business.ool.fr)" mail mailHost uid` pour (a) trier les adresses propres (`uid@business.ool.fr`) des malformées (double `@`), et (b) obtenir la distribution `mailHost` de mtq en un seul passage. Pas encore exécuté.

**How to apply :** Ne jamais migrer un compte en se basant sur son attribut `mail` sans le valider (regex `^[^@]+@[^@]+$` minimum) — utiliser `mailMessageStore`/`uid` comme source de vérité pour le chemin réel. Le pilote `business.ool.fr` ne peut plus être considéré comme "petit" : revoir l'ordre des domaines une fois la vraie volumétrie mtq connue sur les autres domaines aussi (les comptages du tableau initial sont suspects sur tout mtq, pas seulement business.ool.fr).

## Mise à jour majeure (2026-09-08 → 2026-09-17) — plusieurs sections ci-dessus sont maintenant obsolètes

**Vrais volumes (obtenus via `slapcat`, pas `ldapsearch` — le bind anonyme/simple plafonne silencieusement à 500 résultats, même paginé) :** mtq=64 492, guy=121 461, gua=121 455. Les anciens chiffres "500 par site" ci-dessus sont faux, gardés seulement pour l'historique du raisonnement. guy/gua restent quasi-identiques mais **pas** de réplication LDAP native (aucun `contextCSN`, aucun `syncrepl`) — probablement double-écriture applicative en amont.

**Pilote changé : `ool.fr` (12 comptes sur mtq), pas `business.ool.fr`.** `business.ool.fr` a un vrai volume de 270 sur mtq (972 sur guy/gua) et contient des entrées corrompues (double `@`) confirmées. `rife.re` (3 comptes) écarté aussi : 100 % `deliveryMode: forwardonly`, aucune vraie boîte. `ool.fr` : données propres, `userPassword` en `{SHA}` (pas `{SSHA}`), `accountStatus` validé exhaustivement sur les 64 492 comptes mtq (`active` 64491 + `enabled` 1 — `an.jean-louis`, seul outlier).

**Découverte systémique : format legacy `sentmail-*`** — 59 486 fichiers sur tout mtq (webmail 2012-2014, hors structure Maildir++ standard), nécessite un vrai script de conversion avant bascule, pas un correctif ponctuel.

**Cible confirmée : `mtq-mailsrvp-01`** (pas `smtp-mtq-1`, qui n'a jamais eu Dovecot installé — Phase 4 a dû être recréée au bon endroit après une erreur d'hôte). Le serveur héberge déjà `auth-system`/`auth-passwdfile` pour d'autres domaines Postfix déjà en prod (`/var/mail/vhosts/<domaine>/<utilisateur>`) — décision : ajouter `auth-ldap` en plus, sans toucher à l'existant (Dovecot empile plusieurs `passdb`/`userdb`).

**Décision architecture (confirmée avec l'utilisateur) :** on ne migre PAS l'annuaire LDAP vers Postfix — `slapd` reste sur `smtp-mtq-1`, Dovecot l'interroge à distance via un compte de service dédié (`cn=dovecot-auth,ou=services,o=ool`, en cours de création, `rootdn` = `cn=admin,o=ool` retrouvé dans `/etc/openldap/slapd.conf`). Ça évite deux copies divergentes de la vérité pendant la transition et permet un rollback simple.

**⚠️ Nouveau fait critique (2026-09-17), confirmé par l'utilisateur : `smtp-mtq-1` sera éteint définitivement** une fois qmail décommissionné. Ça veut dire que la décision ci-dessus n'est valable que pendant la transition — **avant l'extinction de `smtp-mtq-1`, il faudra migrer/relocaliser `slapd` et sa base LDAP vers une machine qui va rester en vie**, sinon Dovecot perd sa source d'authentification. C'est une tâche distincte et différée, pas un blocage pour le travail en cours (créer le compte de service `dovecot-auth` reste utile immédiatement). À demander : ce même sort (extinction) s'applique-t-il aussi à `smtp-guy-1`/`smtp-gua-1` ?

### Découverte d'un 4e serveur LDAP : `172.30.37.225` ("ldap") — c'est la source de guy/gua, PAS de mtq

L'utilisateur pensait initialement que `smtp-mtq-1` recevait "une copie" de sa propre base LDAP depuis `172.30.37.225`. **Infirmé par les données** (2026-09-17) : aucun `syncrepl`/`updateref`/cron/timer trouvé sur `smtp-mtq-1` pointant vers cet hôte, et surtout la répartition par domaine sur `172.30.37.225` (`ool.fr` 47 643, `only.fr` 51 183, `sfrcaraibe.fr` 13 246, `canalconnect.com` 4 427) colle à la signature **guy/gua** (mêmes ordres de grandeur, même dérive de quelques centaines de comptes qu'entre guy et gua eux-mêmes), pas du tout à la signature mtq (`ool.fr`=12, `only.fr`=39 509, `sfrcaraibe.fr`=16 716). Total sur `172.30.37.225` : 121 858 comptes `qmailUser` — bien trop proche de guy/gua seuls (~121 460) pour contenir mtq (64 492) en plus.

**Conclusion : `172.30.37.225` est très probablement la source/maître réelle de `guy` et/ou `gua`, sans rapport avec `mtq`.** Bonus : révèle des domaines absents des vues locales guy/gua/mtq — `asfa.re` (110), `adapei-972.fr` (63, le domaine des comptes corrompus `noe.mas@...`), `sdis974.re` (35), `cimfonie.fr` (28), plus une douzaine de domaines à 1-8 comptes. Mêmes entrées de test corrompues en base64 (`testadap@business.ool.fr`, `test45@adapei-972.fr`, `v.fafard@ool.fr`) que sur guy/gua — même lignée de données.

**How to apply :** Pour le pilote `ool.fr` (sur mtq), `172.30.37.225` n'est pas pertinent — continuer sur la base locale de `smtp-mtq-1` pour la Phase 3. Ce serveur redevient pertinent **quand on attaquera les domaines côté guy/gua** — à vérifier à ce moment-là s'il vaut mieux y brancher Dovecot directement (source plus pérenne) plutôt que sur les copies guy/gua elles-mêmes.

**How to apply :** Avant toute proposition de "fin de projet", vérifier explicitement si `slapd`/LDAP a été relocalisé hors de `smtp-mtq-1` (et des autres sites source si applicable) — ne pas supposer que la migration qmail→Postfix suffit pour permettre l'extinction des serveurs sources.

## ✅ Phase 5 (auth LDAP Dovecot) résolue le 2026-09-24 — après un firewall bloquant et une saga de configuration Dovecot 2.4

**Blocage réseau découvert** : `mtq-mailsrvp-01` ne peut pas joindre `smtp-mtq-1:389` (`nc -zv` → `Connection timed out`, firewall). Décision (utilisateur, données confirmées 100% figées sur `smtp-mtq-1` — plus aucun compte créé) : **relocaliser une copie de travail de l'annuaire directement sur `mtq-mailsrvp-01`**, plutôt que de dépendre d'une règle de pare-feu. Ça satisfait aussi la tâche différée "relocaliser LDAP avant extinction de smtp-mtq-1" (voir plus haut) — au moins pour le pilote `ool.fr`, pas encore pour tout mtq.

**Syntaxe LDAP de Dovecot 2.4.1 — complètement différente des versions précédentes.** L'ancien format (`args = <fichier externe>`) n'existe plus. Le vrai format (trouvé après échec de la doc officielle en ligne, 503 sur `doc.dovecot.org`, et extraction de chaînes depuis les binaires) :
```
ldap_uris = ldap://<host>
ldap_auth_dn = <bind dn>
ldap_auth_dn_password = <mdp>
ldap_base = <base dn>

passdb ldap {
  ldap_filter = (...)   ← PAS "filter", PAS "passdb_ldap_filter" (ce nom existe dans le binaire mais n'est PAS le nom de réglage attendu dans le bloc — piège)
  ldap_bind = no        ← équivalent du vieux "auth_bind = no"
  fields {
    user = %{ldap:mail}
    password = %{ldap:userPassword}
  }
}
userdb ldap {
  ldap_filter = (...)
  fields {
    home = %{ldap:mailMessageStore}
  }
}
```
Le paquet **`dovecot-ldap` doit être installé séparément** (`apt-get install dovecot-ldap`) — pas inclus dans `dovecot-core` sur Debian 13. Son install propose un `auth-ldap.conf.ext` d'exemple qui a été la vraie source de vérité.

**Mise en place d'un `slapd` local sur `mtq-mailsrvp-01` (Debian 13, OpenLDAP 2.6.10)** — obstacles rencontrés dans l'ordre, tous résolus :
1. Le paquet `slapd` crée par défaut une base `cn=config` avec suffixe `dc=prod,dc=intranet,dc=local` — pas `o=ool`.
2. `slaptest -f classic.conf -F /etc/ldap/slapd.d` (conversion classique→dynamique) : `Unrecognized database type (mdb)` → il faut charger `modulepath /usr/lib/ldap` + `moduleload back_mdb.so` (le `.la` charge un "null module" silencieux, symptôme trompeur).
3. Une fois le module chargé, `slaptest` échoue quand même à ouvrir la base (`No such file or directory`) car **`slaptest` ne crée jamais de nouvelle base de données depuis zéro** — ce n'est pas son rôle, contrairement à ce que suggère la doc. `slaptest -u` valide sans erreur mais n'écrit RIEN dans `-F` (piège silencieux).
4. **Solution finale : abandonner complètement `cn=config`, rester en mode `slapd.conf` classique** (comme `smtp-mtq-1`) — `/etc/default/slapd` avec `SLAPD_CONF="/etc/ldap/slapd.conf"`. Le vrai daemon `slapd` (pas `slaptest`) crée la base `mdb` correctement au premier vrai démarrage.
5. Erreurs de permissions rencontrées en chaîne (à surveiller à chaque nouveau fichier créé en root pour ce service) : fichiers schéma et `slapd.conf` créés `root:root 640/644` par défaut via heredoc — `openldap` (l'utilisateur du service) doit pouvoir les lire. `chmod 644` systématique nécessaire.

**Schémas custom nécessaires** (au-delà de `core/cosine/inetorgperson/nis` standards) — copiés depuis `smtp-mtq-1` :
- `qmail.schema` + `qmailControl.schema` (attributs qmail-ldap : `mailMessageStore`, `mailHost`, `deliveryMode`, `accountStatus`, etc.)
- `pureftpd.schema` (attributs `FTPQuotaFiles`, `FTPStatus`, `FTPhomeDirectory`, etc. — ce LDAP sert AUSSI Pure-FTPd, pas que qmail)
- Un objectClass `personalOrganization` (custom, ajouté à la main dans le `core.schema` de `smtp-mtq-1`, `SUP (organizationalPerson $ PureFTPdUser)`) — mis dans un fichier séparé `local-personalorg.schema` plutôt que de toucher au `core.schema` standard de Debian.
- **`nis.schema` de smtp-mtq-1 est une version plus ancienne/permissive** que celle de Debian : son `posixAccount` n'exige que `MUST (cn $ uid)`, alors que le `nis.schema` moderne de Debian exige aussi `uidNumber $ gidNumber $ homeDirectory` — remplacement intégral du fichier nécessaire, sinon `ldap_add: Object class violation` sur presque tous les comptes réels (qui n'ont pas ces attributs).

**Import réalisé** : conteneurs (`o=ool`, `ou=acc`, `ou=C2`, `ou=C4`, `ou=services`) + `cn=dovecot-auth` + les 12 comptes réels `ool.fr` via `ldapadd -c` (mode continu, pour ignorer les "already exists" des conteneurs déjà créés lors d'un essai précédent).

**✅ Validation finale réussie** : `doveadm auth test lucetest@ool.fr <mauvais_mdp>` → `passdb: lucetest@ool.fr auth failed` (rejet propre, pas une erreur de connexion/schéma) — preuve que toute la chaîne (connexion LDAP locale, bind `dovecot-auth`, filtre, récupération du hash, comparaison) fonctionne. Fichier `dovecot-ldap-auth.conf.ext` obsolète (ancien format), remplacé par `auth-ldap.conf.ext` avec le nouveau format ci-dessus.

**How to apply :** Pour étendre cet import au-delà des 12 comptes `ool.fr` (par exemple pour la vraie relocalisation complète de mtq avant décommission), refaire un export `slapcat`/`ldapsearch` plus large depuis `smtp-mtq-1` — le schéma local sur `mtq-mailsrvp-01` gère déjà tous les objectClass rencontrés jusqu'ici (`qmailUser`, `personalOrganization`, `organizationalPerson`, `posixAccount`). Un import à grande échelle (64k comptes) nécessitera un vrai mécanisme de transfert de fichier (SCP/SFTP, à tester — le port 389 est bloqué mais le port 22 n'a pas été testé entre ces deux hôtes), pas un copier-coller par chat.
- **Prochaine étape logique** : Phase 6 (activer le socket SASL Postfix↔Dovecot, actuellement commenté dans `10-master.conf` : `unix_listener /var/spool/postfix/private/auth`), puis Phase 7 (tests avec de vrais identifiants si disponibles, sinon la validation par rejet propre ci-dessus suffit pour avancer).

## ✅ Phase 6 (SASL Postfix↔Dovecot) résolue le 2026-09-24

**Socket activé** dans `/etc/dovecot/conf.d/10-master.conf` (lignes ~110-114, bloc `service auth {}`) : décommenté `unix_listener /var/spool/postfix/private/auth`, durci en `mode 0600, user postfix, group postfix` (au lieu du `mode 0666` par défaut) — même convention que le socket LMTP déjà présent sur cette machine. Côté Postfix, `/etc/postfix/main.cf` ne contenait aucun réglage `smtpd_sasl_*` — ajouté :
```
smtpd_sasl_type = dovecot
smtpd_sasl_path = private/auth
smtpd_sasl_auth_enable = yes
```

**Validation** : `EHLO` via `nc localhost 25` montre `250-AUTH PLAIN` — confirmé que Postfix délègue bien à Dovecot. ⚠️ Piège de test rencontré : envoyer `EHLO` immédiatement dans le pipe (`printf ... | nc ...`) déclenche `554 SMTP protocol synchronization` (protection anti-spam "pregreet" de Postfix qui rejette un client parlant avant la bannière `220`) — il faut un `sleep 1` avant d'envoyer la commande pour laisser le temps à la bannière d'arriver.

## ⚠️ Découverte critique post-Phase 6 : l'authentification fonctionne, mais Roundcube ne montrerait AUCUN mail pour l'instant

Deux problèmes distincts identifiés en réfléchissant à "un vrai utilisateur pourrait-il voir ses mails maintenant ?" :

1. **Bug de chemin corrigé** : le réglage global `mail_path = %{home}` (qui convient aux domaines `passwd-file` existants) ne convenait PAS aux comptes LDAP — le vrai Maildir est un niveau plus bas (`<mailMessageStore>/Maildir/`, pas `<mailMessageStore>` directement, confirmé lors de l'inspection filesystem sur smtp-mtq-1 plus tôt dans le projet). **Corrigé** en ajoutant `mail_path = %{ldap:mailMessageStore}/Maildir` directement dans les `fields{}` du bloc `userdb ldap` (override propre au userdb LDAP, sans toucher au réglage global qui reste correct pour les autres domaines).

2. **⚠️ Toujours vrai, pas encore adressé : aucune donnée Maildir réelle n'a été copiée sur `mtq-mailsrvp-01`.** Le chemin `/var/qmail/maildirs/...` référencé par `mailMessageStore` n'existe que sur le filesystem de `smtp-mtq-1` (machine physique différente). Même avec l'authentification et le mapping de chemin corrects, Dovecot chercherait un dossier qui n'existe pas du tout sur cette machine. **La synchronisation réelle des Maildirs (rsync ou équivalent, cf. étape 6 du plan de migration domaine-par-domaine défini le 2026-09-04) reste entièrement à faire** — c'est la prochaine étape substantielle avant qu'un vrai test de connexion utilisateur ait un sens.

**How to apply :** Ne jamais présenter "l'authentification marche" comme équivalent à "la migration marche" — ce sont deux couches séparées (identité/lookup vs. données réelles). Avant tout test avec un vrai utilisateur, confirmer que son Maildir a été physiquement copié sur `mtq-mailsrvp-01` au bon chemin (`<mailMessageStore>/Maildir`).

## ✅ Données Maildir du pilote `ool.fr` migrées et vérifiées (2026-09-28)

- **uid/gid** : ajouté `uid = vmail` / `gid = vmail` dans les `fields{}` du `userdb ldap` (aucun `mail_uid`/`mail_gid` global sur cette machine ; le userdb `passwd-file` les fixe explicitement, pas le LDAP par défaut).
- **Transfert (SSH serveur→serveur bloqué par le firewall)** : archive `tar -czf` créée sur `smtp-mtq-1` (`/root/ool-pilot-maildirs.tar.gz`, 675 Mo, 8 723 entrées, sha256 `e571d000f02484625c8d15634cc185b66b1e2cdbda5f835e34a87b280ab06b6b`), transférée à la main via le poste de travail (accès à `smtp-mtq-1` uniquement par le jump host `mtq-wremote-01`), hash revérifié côté cible, extraite avec `tar -xzf -C /` sur `mtq-mailsrvp-01` puis `chown -R vmail:vmail /var/qmail`. Les chemins absolus sont identiques à la source (`/var/qmail/maildirs/d1|d2/...`) car `mailMessageStore` n'a pas été modifié dans le LDAP local.
- **8 comptes sur 12 ont des données** : esat.petitmorne (1 391 messages, tous dans `new/`, ~135 Mo), impmornerouge (INBOX vide), imppelletier, imppropelletier, impsaintemarie, valydov, i.lordelot, an.jean-louis. **4 sans Maildir sur smtp-mtq-1** : impmas, d.bonheur, lucetest (jamais de mail reçu, création paresseuse probable) et fab.aubry (`mailHost: andesite.ool.fr` = smtp-guy-1, ses données sont ailleurs).
- **Validation** : `doveadm user impmornerouge@ool.fr` → uid/gid 5000, `home`, `mail_path=.../Maildir` corrects ; `doveadm mailbox status -u esat.petitmorne@ool.fr all INBOX` → `messages=1391`, égal au nombre de fichiers dans `Maildir/new` sur disque ; `find /var/qmail ! -user vmail` → aucun résultat.
- **⚠️ Capacité** : `/var` sur `mtq-mailsrvp-01` ne fait que 5,6 Go (le pilote en occupe 1,4). Le domaine complet ou tout mtq exigera un volume dédié bien plus grand avant montée en charge.
- **Reste à faire** : test de connexion réelle (mot de passe inconnu — piste : mot de passe temporaire sur la copie LDAP locale d'un compte vide comme impmornerouge, avec sauvegarde puis restauration du hash), conversion `sentmail-*` (an.jean-louis en a 19), données de fab.aubry à récupérer sur smtp-guy-1, suppression des archives (contenu client) dans `smtp-mtq-1:/root` et `mtq-mailsrvp-01:/home/superuser`. La demande de règle firewall TCP/22 reste utile pour les volumes au-delà du pilote (rsync incrémental).

## ✅ Répétition complète de bout en bout réussie avec un compte de test (2026-09-28)

- Compte **`zz.migtest@ool.fr`** créé de toutes pièces sur `smtp-mtq-1` (entrée LDAP `uid=zz.migtest,ou=C2,ou=acc,o=ool`, objectClass `organizationalPerson` + `qmailUser` calqué sur an.jean-louis, sans classes Pure-FTPd ; `mailHost: emerald.ool.fr`, `mailMessageStore: /var/qmail/maildirs/d2/130/zz.migtest`, mot de passe de test trivial en `{SHA}`). Un message envoyé avec `/var/qmail/bin/sendmail` a été livré par qmail lui-même : **qmail-ldap crée bien le Maildir tout seul** (`Maildir/{cur,new,tmp}`, `vmail:vmail` 700) — inutile de créer les Maildirs à la main pour de nouveaux comptes.
- Migration : entrée LDAP réimportée par `ldapadd` dans la copie locale de `mtq-mailsrvp-01`, Maildir transféré par `tar` (464 octets) puis `chown -R vmail:vmail`.
- Résultats : `doveadm mailbox status` → `messages=1` ; `doveadm auth test zz.migtest@ool.fr` avec le bon mot de passe → `auth succeeded` (**premier test positif d'authentification LDAP `{SHA}` sur cette machine**, sans aucune réinitialisation de mot de passe) ; connexion Roundcube OK, envoi et réception signalés OK par l'utilisateur.
- **Compte de test `zz.migtest@ool.fr` conservé volontairement à la demande de l'utilisateur** (dans l'annuaire de `smtp-mtq-1` ET dans la copie LDAP locale de `mtq-mailsrvp-01`, avec son Maildir des deux côtés et une ligne temporaire dans `/etc/postfix/vmailbox`). Recommandation de mot de passe fort déclinée par l'utilisateur (compte utilisé pour ses tests) : le mot de passe reste trivial, risque accepté par l'utilisateur. Le SASL SMTP réel a été validé sur ce compte : `235 2.7.0 Authentication successful`.
- **Toujours à supprimer, contenant des données clients ou des hashes réels** : `/root/ool-pilot-maildirs.tar.gz` (smtp-mtq-1) et `/home/superuser/ool-pilot-maildirs.tar.gz` (mtq-mailsrvp-01) ; `/tmp/ool-export.ldif` (smtp-mtq-1) ; `/root/ool-import.ldif` (mtq-mailsrvp-01).

## Inventaire pour la migration complète — smtp-mtq-1 (2026-09-28, `slapcat -b "ou=acc,o=ool"`)

- **Comptes** : 64 493 `qmailUser` (dont le compte de test). `accountStatus` : active 64 492 / enabled 1. `deliveryMode` : normal 64 479, forwardonly 9, **localdelivery 5** (valeur absente du schéma qmail, probablement copie locale + redirection → alias à plusieurs destinataires). `FTPStatus` enabled 5 843 / disabled 58 639.
- **Fonctionnalités qmail rares** : 23 valeurs `mailForwardingAddress`, 2 `mailReplyText` (autorépondeurs → Sieve vacation, `dovecot-sieve` déjà installé), **1 `deliveryProgramPath`** (livraison par programme : à identifier, risque sécurité), **0 `mailQuotaSize`** (aucun quota dans LDAP ; vérifier `/var/qmail/control/ldapdefaultquota`).
- **257 245 valeurs `mailAlternateAddress`** (~4 alias par compte) : chaque alias est une adresse valide côté qmail et doit l'être côté Postfix → table LDAP `postfix-ldap` (`virtual_alias_maps`) plutôt qu'un fichier statique. La liste réelle des domaines à accepter dépasse probablement les 7 vus dans `mail` (les alias n'avaient pas été comptés).
- **1 434 entrées `dNSDomain` + `dcObject`** (+ 23 OU) dans l'arbre : nature à identifier (domaines hébergés ? enregistrements DNS ?). Elles expliquent les ~1 458 entrées non-comptes vues plus tôt.
- **Stockage** : `/var/qmail/maildirs` est un lien vers `/m/maildirs`, disque **local ext3 de 1,5 To, 1,2 To utilisés (81 %)**, 13,8 millions d'inodes ; `/m` contient aussi `ldap_backup` et `list_cur.lst`. Les 4 hôtes de stockage (emerald = smtp-mtq-1, andesite = smtp-guy-1, quartz, diamond) sont des machines indépendantes, pas un stockage réseau partagé. La cible n'a que 5,6 Go dans `/var` : volume multi-To à prévoir, et rsync **par compte/bucket à partir d'un manifeste LDAP**, pas un rsync géant.
- **FTP** : 5 843 comptes FTP activés (`FTPhomeDirectory` sous `/var/pure-ftpd/...`) ; l'extinction de smtp-mtq-1 emporte aussi ce service → à cadrer avec l'équipe (hors périmètre mail mais bloquant pour le décommissionnement).
- **À faire ensuite** : même inventaire sur l'annuaire guy/gua (ou 172.30.37.225) ; accès aux hôtes quartz/diamond/andesite et logiciel POP3/IMAP legacy (UIDL POP3) encore inconnus.

### Domaines, alias et quota (smtp-mtq-1, 2026-09-28) — remet en cause le plan « domaine par domaine »

- **14 domaines** en comptant `mail` + `mailAlternateAddress` : only.fr (63 375), ool.fr (61 316), only-entreprise.fr (49 573), canalconnect.com (48 700), **numericable-outremer.fr (47 762, uniquement en alias)**, sfrcaraibe.fr (44 546), business.ool.fr (5 997), sdis974.re (228), sdis974.fr (228), rife.re (5), rife-caraibe.fr (5), reef.re (1), numericable-caraibes.fr (1), izi.re (1). Le Postfix cible n'accepte que only.fr, ool.fr, only-entreprise.fr, box.only.fr, business.ool.fr (`virtual_mailbox_domains`).
- **Un même Maildir est adressé dans ~5-6 domaines** (ex. esat.petitmorne@ool.fr répond aussi à @only.fr et @business.ool.fr ; an.jean-louis à @ool.fr, @sfrcaraibe.fr, @only.fr). Une bascule MX domaine par domaine couperait la boîte d'une même personne en deux serveurs. **Piste retenue à valider : migrer par boîte (lots) en laissant le MX sur les anciens frontaux jusqu'à la fin, en changeant le `mailHost` de chaque boîte migrée** (c'est déjà le mécanisme qui répartit les boîtes entre emerald/quartz/diamond/andesite) ; retour arrière = remettre l'ancien `mailHost`. Question ouverte : comment le frontal qmail-ldap livre à un hôte non-qmail (QMQP ou SMTP ; Postfix possède un serveur `qmqpd`). Déduit de la conception qmail-ldap, non vérifié.
- **Quota par défaut global** : `/var/qmail/control/ldapdefaultquota` = `25000000S, 1000C` (25 Mo et 1 000 messages par boîte, aucun `mailQuotaSize` individuel). Cohérent avec ~20 Mo de moyenne (1,2 To sur emerald) et borne la volumétrie totale. esat.petitmorne (135 Mo, 1 391 messages) dépasse largement la limite. À décider : reproduire (quota Dovecot) ou non.
- `donotreply@only.fr` : `deliveryProgramPath: /bin/true` = trou noir, à mapper en `discard` Postfix ; sans risque.
- **Correction** : les 1 434 entrées `dNSDomain`+`dcObject` sont des **données DNS** sous `ou=Dns,o=ool` (ex. `dc=web,dc=ool,dc=fr` avec `aRecord: 217.175.160.17`) — cet annuaire est aussi le backend d'un DNS piloté par LDAP (autre dépendance du décommissionnement de smtp-mtq-1, comme les 5 843 comptes FTP). Je les avais crues masquées par une ACL ; en réalité mon `ldapsearch` avait pour base `ou=acc` et ne les voyait pas. Piège : `slapcat -b <suffixe>` choisit une **base**, pas un sous-arbre (l'option sous-arbre est `-s`) → tous les décomptes `slapcat -b "ou=acc,o=ool"` portent sur toute la base `o=ool` (sans effet sur les chiffres de comptes/alias, ça explique exactement les 1 458 entrées non-comptes : 1 434 DNS + 23 OU + racine).
- **MX (`dig`, 2026-09-28)** : `mx1`/`mx2.sfrcaraibe.fr` → only.fr, ool.fr, sfrcaraibe.fr, business.ool.fr, rife.re (et reef.re via mx1 seul) ; `mx1.entreprise.sfrcaraibe.fr` → only-entreprise.fr ; `mx1`/`mx2.outremer-telecom.fr` → numericable-outremer.fr. Pas chez nous : sdis974.fr (Gandi), numericable-caraibes.fr (SFR), sdis974.re (MX propre). **Sans MX** : canalconnect.com (48 700 adresses !), rife-caraibe.fr, izi.re. ⇒ ~8 domaines entrants réels, tous derrière quelques noms de MX ; idée pour la fin : repointer ces quelques noms de MX plutôt que 14 domaines. À vérifier : qui sont réellement ces MX (IP vs smtp-mtq-1 = 217.175.160.104, smtpguy-2_pub .142, smtpgua-2_pub .77), et si canalconnect.com est encore en service.
- **Résidus à supprimer sur l'annuaire de production de smtp-mtq-1** (issus de notre première tentative de Phase 3, avant le pivot vers le LDAP local) : `cn=dovecot-auth,ou=services,o=ool`, `ou=services,o=ool` et `/root/dovecot-auth.ldif`.
- **IP des MX (enregistrements A, 2026-09-28)** : mx1.sfrcaraibe.fr 109.62.64.22 ; mx2.sfrcaraibe.fr 217.175.160.52 ; mx1.entreprise.sfrcaraibe.fr 109.62.64.21 ; mx1.outremer-telecom.fr 109.62.64.20 ; mx2.outremer-telecom.fr 217.175.160.50 ; canalconnect.com (A) 141.193.213.10 et .11. Ce sont d'autres machines que smtp-mtq-1 (217.175.160.104), smtpguy-2_pub (.142) et smtpgua-2_pub (.77) : un étage de frontaux MX dont le propriétaire et la configuration restent à identifier (consultent-ils LDAP ?).
- **DNS et FTP ne tournent PAS sur smtp-mtq-1** (aucun processus named/pdns/nsd/tinydns/pure-ftpd, rien n'écoute sur 21/53) : ils lisent l'annuaire à distance depuis d'autres machines. Avant toute relocalisation ou extinction du LDAP de smtp-mtq-1, **recenser tous ses clients** (connexions sur le port 389) : c'est le vrai périmètre d'impact.
- **Recensement des clients LDAP (échantillon de 2 min, 2026-09-28)** : `smtp-mtq-1` (interfaces : eth0 172.30.32.105/29 privée, eth1 217.175.160.104/27 publique) n'a **qu'un seul client : lui-même via 172.30.32.105** → son LDAP ne sert que son propre qmail (ni DNS, ni FTP, ni MX). Le LDAP central `172.30.37.225` a 4 clients : 172.30.37.35 (96 observations, très actif), 172.30.37.131 (18), 172.30.37.224 (6, voisin immédiat du serveur : réplique ?), 172.30.57.127 (1). Identité de ces 4 IP encore inconnue (DNS inverse / Netbox) ; les consommateurs DNS/FTP lisent probablement ce LDAP central plutôt que celui de smtp-mtq-1. Un échantillon de 2 min peut manquer des clients ponctuels. À vérifier aussi : `.224` est-il un esclave (`replica`/`syncrepl` dans `/etc/openldap/slapd.conf` de .225) ? Les serveurs guy/gua (smtp-guy-1 = 172.30.33.105) ne figurent pas parmi les clients : ils utilisent des copies locales.
- **⚠️ CORRECTION MAJEURE (2026-09-28) : `172.30.37.225` RÉPLIQUE bien vers smtp-mtq-1** (l'utilisateur avait raison, ma conclusion « sans rapport avec mtq » était fausse). Son `/etc/openldap/slapd.conf` déclare 4 réplicas **slurpd** (ancienne réplication `replica`/`replogfile /var/lib/ldap/replog.slave`, d'où l'absence de syncrepl/contextCSN partout) : `172.30.31.105` = smtp-gua-1 (Guadeloupe, confirmé par l'utilisateur) [CENSUS 2026-09-28, comptes par conteneur `ou=acc` : smtp-mtq-1 = 64 493 (C2 24 801, C3 17 182, C5 14 507, C4 7 696, C9 305, only 2, pas de C1) ; master 172.30.37.225 ≈ 121 628 (C2 43 392, C5 40 683, C3 26 067, C4 11 116, C9 347, C1 12, only 3, + 7 DN sans espace après virgule, + 1 DN atypique `uid=direction.generale@only-entreprise.fr@adapei-972.fr`) → mtq ≈ 53 % du master alors que guy/gua sont ~400 en retard seulement : mtq est l'anomalie, réplication vers mtq à vérifier ; à trancher via comptage par `mailHost`], `172.30.32.105` = smtp-mtq-1 (`#MTQ`), `172.30.33.105` = smtp-guy-1 (`#GUY`), `172.30.34.105` = **Réunion** (`#REU`, le commentaire précède le bloc qu'il désigne) — soit 4 sites, pas 5 ; le site Réunion (domaines sdis974.*, `smtpreu.ool.fr`) n'a jamais été inspecté. **Mais ce n'est pas un miroir simple** : mtq a plus d'adresses sfrcaraibe.fr que le maître (16 716 contre 13 246), et guy/gua ont ~400 comptes de moins que le maître (121 461 / 121 455 contre 121 858) → réplication filtrée (`suffix=`/`attr=`) ou en retard/bloquée. À élucider avant de décider quel annuaire fait foi : stanzas `replica` complètes (masquer `credentials=`), slurpd actif ?, état de `replog.slave` et fichiers `.rej`, config esclave de smtp-mtq-1 (`updatedn`/`updateref`). Les 4 clients de .225 (.37.35, .37.131, .37.224, .57.127) n'ont pas de DNS inverse : à identifier via Netbox.
- **Détail de la réplication slurpd (2026-09-28)** : les 4 blocs `replica` n'ont ni `suffix=` ni `attr=` (binddn `cn=admin,o=ool`, bind simple) → réplication complète prévue vers chaque site. `slurpd` tourne (PID 1245, depuis le 8 août) ; `replog.slave` et son `.lock` font 0 octet (dernière modification le 1er sept.), aucun fichier `.rej` : rien en attente ni de rejeté. Pourtant les contenus divergent fortement (mtq 64 k comptes contre 121 k sur le maître ; guy/gua ~400 de moins que le maître) : la réplication n'explique pas le contenu de mtq, qui semble en grande partie indépendant. **Prochaine étape** : comparer les comptes par conteneur (`slapcat ... | grep "^dn: uid=" | awk -F, '{print $(NF-2)}' | sort | uniq -c`) entre maître, mtq, guy, gua (et Réunion) ; confirmer si le site Réunion est dans le périmètre (l'utilisateur ne cite que mtq, gpe et guy).
- **Constat de sécurité à remonter à l'équipe** : le compte `fab.aubry` (ou=C4, Guyane) de l'annuaire `smtp-mtq-1` a un hash `{SHA}` identique à celui choisi pour le compte de test, donc un mot de passe trivial.

## ⚠️ Lacune découverte : Postfix ne connaît pas les comptes LDAP (2026-09-28)

- Un `RCPT TO:<zz.migtest@ool.fr>` non authentifié est **rejeté par Postfix** : `550 5.1.1 Recipient address rejected: User unknown in virtual mailbox table`. Cause : `virtual_mailbox_maps = hash:/etc/postfix/vmailbox` (fichier plat de 6 comptes placeholder, format `adresse domaine/user`), alors que `ool.fr` est déjà dans `virtual_mailbox_domains` (avec only.fr, only-entreprise.fr, box.only.fr, business.ool.fr) et que `virtual_transport = lmtp:unix:private/dovecot-lmtp`. Dovecot (via LDAP) sait livrer, mais Postfix refuse à l'entrée → **avant toute bascule MX, chaque compte migré doit être connu de Postfix**, sinon rebond pour tous les utilisateurs.
- Test validé avec une entrée statique temporaire : ajout de `zz.migtest@ool.fr ool.fr/zz.migtest` dans `/etc/postfix/vmailbox` (sauvegarde `vmailbox.bak-20260928`), `postmap`, `postfix reload` → `RCPT` accepté (250), livraison `lmtp ... Saved`, `doveadm mailbox status` → `messages=2`. **À retirer au nettoyage.**
- **Options pour la vraie solution (à décider)** : (a) générer `vmailbox` depuis LDAP par script (données figées, donc faisable) ; (b) tables LDAP Postfix (paquet `postfix-ldap`) pour `virtual_mailbox_maps` et surtout `virtual_alias_maps` (`mailAlternateAddress` = alias, `mailForwardingAddress` = redirections, ex. les comptes `forwardonly` de rife.re) — plus cohérent avec l'architecture (LDAP = source de vérité).
- `smtpd_recipient_restrictions = permit_mynetworks, reject_unauth_destination`. Roundcube soumet depuis localhost (mynetworks) **sans SASL** (log `client=localhost[127.0.0.1]` sans `sasl_username`) : le SASL des comptes LDAP n'a donc été vérifié que par l'annonce `250-AUTH PLAIN`, pas par une vraie authentification SMTP.
