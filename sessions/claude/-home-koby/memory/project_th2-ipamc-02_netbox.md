---
name: project-th2-ipamc-02-netbox
description: Serveur Netbox (IPAM/DCIM) th2-ipamc-02 — coordonnées de connexion et dernier état de santé constaté
metadata: 
  node_type: memory
  type: project
  originSessionId: 86825897-13ee-4941-b3dc-d740daba1fdb
  modified: 2026-08-21T09:58:12.815Z
---

Serveur Debian **th2-ipamc-02** héberge Netbox (IPAM/DCIM) pour Outremer Telecom.

**Connexion :**
- IP : `172.30.217.19` (le nom `th2-ipamc-02` ne résout pas en DNS depuis le poste de l'utilisateur — utiliser l'IP directement)
- Port SSH : `30`
- Utilisateur : `superuser`
- Auth : connexion par clé sans mot de passe déjà configurée

**Dernier état vérifié (2026-08-21 13:57 +04) :** sain. Services systemd `netbox`, `netbox-rq`, `nginx`, `postgresql`, `redis-server` tous actifs ; réponse HTTP locale 301 (redirection HTTP→HTTPS attendue).

**Why:** première vérification demandée par l'utilisateur ; pas de contexte antérieur sur ce serveur en mémoire.

**How to apply:** pour toute future demande de diagnostic sur ce serveur, utiliser directement ces coordonnées de connexion sans redemander à l'utilisateur. Voir aussi [[feedback-classifier-blocks-multistep-remote-scripts]] pour la contrainte : première connexion à un hôte inconnu → exécuter en direct depuis la session principale, pas via un agent en arrière-plan.
