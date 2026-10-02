---
name: user-samy-amit
description: "Samy Amit (samy.amit@gmail.com) fait de l'administration système réelle sur des serveurs Debian de production pour Outremer Telecom"
metadata: 
  node_type: memory
  type: user
  originSessionId: 31e2d855-d15f-4e24-b4f0-c7bf43f8304d
  modified: 2026-08-14T12:10:46.474Z
---

L'utilisateur fait de l'administration système Linux réelle (pas un labo/exercice) sur des serveurs Debian de production appartenant à l'entreprise Outremer Telecom — confirmé par la bannière SSH de connexion et par un test d'envoi de mail relayé avec succès vers une vraie boîte Microsoft 365 de l'entreprise. Voir [[project-outremer-telecom-mailserver]] pour le détail du travail en cours.

A créé le sous-agent [[koby-debian-sysadmin]] pour ce type de tâches : SSH vers plusieurs serveurs Debian, diagnostic, durcissement sécurité, dépannage.

**How to apply:** Traiter les serveurs mentionnés comme de la vraie production (confirmer avant actions destructrices/service restart, faire des sauvegardes systématiques avant modif de config) — pas comme un environnement de test jetable.
