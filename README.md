# ansible

Projet Ansible personnel pour l'administration, le dépannage et le
durcissement sécurité de plusieurs serveurs.

## Utilisation

`ansible.cfg` n'est chargé que si les commandes sont lancées **depuis ce
dossier** (ou avec `ANSIBLE_CONFIG=~/ansible/ansible.cfg` exporté).

**Contre `localhost` sur cette machine, ne pas utiliser `-K`** (voir
"sudo-rs" ci-dessous) — lancer tout le process déjà en root :

```bash
cd ~/ansible
sudo ansible-playbook playbooks/check-nginx.yml
```

Contre un hôte **distant** (SSH), `-K` fonctionne normalement (sauf si cet
hôte utilise aussi sudo-rs — voir ci-dessous) :

```bash
ansible-playbook playbooks/check-nginx.yml -K --limit web01
```

### Piège connu : sudo-rs sur cette machine casse `-K`/become en local

Cette machine fait pointer `/usr/bin/sudo` vers **sudo-rs** (réimplémentation
Rust de sudo, choisie par défaut sur Ubuntu "resolute") plutôt que le sudo
classique. sudo-rs enveloppe le prompt personnalisé qu'Ansible génère
(`[sudo via ansible, key=...] password:`) dans son propre format
(`[sudo: ...] Password:`) au lieu de l'afficher tel quel. Le plugin become
d'Ansible attend une correspondance exacte en début de ligne pour savoir
quand envoyer le mot de passe — avec sudo-rs, elle n'arrive jamais, et la
tâche échoue au bout du timeout (`Timed out waiting for become success or
become password prompt`), même avec le bon mot de passe saisi via `-K`.

C'est pour ça que le contournement ci-dessus (`sudo ansible-playbook ...`
sans `-K`) fonctionne : le process entier tourne déjà en root, donc `become`
n'a plus besoin de prompt du tout (sudo en tant que root ne redemande pas de
mot de passe).

Pour régler ça une fois pour toutes au niveau système (pas fait par défaut ici
— changement qui affecte tout `sudo` sur la machine, pas seulement Ansible) :
`sudo update-alternatives --config sudo`, puis choisir `/usr/bin/sudo.ws`
(le sudo classique, déjà installé en parallèle).

## Inventaire

`inventory.yml` contient un groupe `webservers`. `localhost` (en
`ansible_connection: local`) y est déjà présent comme hôte réel — ajoutez vos
serveurs distants à côté (voir le commentaire dans le fichier).

## Vérification des clés SSH

Contrairement à beaucoup de configs Ansible qui désactivent
`host_key_checking`, ce projet le laisse activé (comportement par défaut)
puisqu'un des objectifs est le durcissement sécurité — désactiver la
vérification des clés d'hôte affaiblirait la protection contre le
détournement de connexion. Avant d'ajouter un nouveau serveur distant,
connectez-vous-y une première fois en SSH manuellement (ou `ssh-keyscan`)
pour accepter sa clé.

## Playbooks

- `playbooks/check-nginx.yml` — lecture seule : statut du service, validité
  de la config (`nginx -t`), liens cassés dans `sites-enabled/`, et
  vérification que `sites-enabled/` est bien inclus dans `nginx.conf`.
