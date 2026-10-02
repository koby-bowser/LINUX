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

## Daily AI tool updates

`playbooks/ai-tool-updates/schedule-ai-tool-updates.yml` installs and enables a systemd timer
for **07:00 every day in the machine's local timezone** (Indian/Mauritius on
this workstation). `Persistent=true` catches up once after a missed run when
the machine next boots/resumes. It does not wake a powered-off machine.

Install or refresh the schedule from this repository:

```bash
cd ~/LINUX
sudo ansible-playbook -i localhost, playbooks/ai-tool-updates/schedule-ai-tool-updates.yml -e ai_updates_user=koby
```

To change the morning schedule, run the same playbook with an extra variable:

```bash
sudo ansible-playbook -i localhost, playbooks/ai-tool-updates/schedule-ai-tool-updates.yml \
  -e ai_updates_user=koby -e 'ai_updates_calendar="*-*-* 08:00:00 Indian/Mauritius"'
```

The timer executes a root-owned copy of `playbooks/ai-tool-updates/update-ai-tools.yml` under
`/usr/local/lib/ai-tool-updates`, independently of the checkout, inventory,
and vault password. Rerun the scheduling playbook after editing runtime files.
It targets localhost only and requires Debian/Ubuntu, systemd, Ansible,
`runuser`, `timeout`, and `flock`.

| Tool | Expected installation | Daily update |
| --- | --- | --- |
| Antigravity CLI | `~/.local/bin/agy` | `agy update` |
| Claude Code | `~/.local/bin/claude` native installation | `claude update` |
| Codex CLI | `~/.local/bin/codex` standalone installation | `codex update` |
| OpenCode | `~/.opencode/bin/opencode` curl installation | `opencode upgrade --method curl` |

The CLI commands run as `ai_updates_user` with that user's home and PATH,
without loading interactive shell startup files. Missing
installations and failed updates are reported as failures; they do not stop
the other tools from being attempted. Each CLI command has a 15-minute
timeout. The service has a 90-minute overall timeout and a lock prevents
overlapping service runs. Logs include before/after CLI versions and updater
output. Existing release-channel settings are respected.

The playbook updates existing installations; it does not bootstrap missing
applications or add package repositories. Antigravity uses the installed
`agy` CLI's `update` subcommand. The other update commands are documented by
[Claude Code](https://code.claude.com/docs/en/setup#update-manually),
[Codex CLI](https://learn.chatgpt.com/docs/developer-commands?surface=cli), and
[OpenCode](https://opencode.ai/docs/cli/#upgrade).

Inspect the schedule, run an update now, or read the latest logs:

```bash
systemctl list-timers ai-tool-updates.timer
sudo systemctl start ai-tool-updates.service
journalctl -u ai-tool-updates.service -n 150 --no-pager
```

Disable the schedule with `sudo systemctl disable --now ai-tool-updates.timer`.
This does not interrupt an update already running. Use `--check --diff` on the
scheduling playbook for a dry run. The update playbook's `--check` validates
installations without executing CLI updaters.

Run all four updates directly as the installation owner, without sudo:

```bash
ansible-playbook -i localhost, playbooks/ai-tool-updates/update-ai-tools.yml -e ai_updates_user=koby
```

Only installing or refreshing the system-wide timer requires sudo.

Validation:

```bash
ansible-playbook -i localhost, playbooks/ai-tool-updates/schedule-ai-tool-updates.yml --syntax-check
ansible-playbook -i localhost, playbooks/ai-tool-updates/update-ai-tools.yml --syntax-check
python3 tests/test_ai_tool_updates.py
```

## Synchronisation des sessions IA (Antigravity, Claude Code, Codex)

`sync-ai-sessions.yml` (et `playbooks/sync-ai-sessions.yml`) synchronise et archive les sessions de travail des trois assistants IA CLI dans le répertoire `sessions/` (avec un lien symbolique `ai-sessions -> sessions` à la racine) et publie les nouveautés sur GitHub :

| Outil IA | Source locale | Destination dans le dépôt | Contenu |
| --- | --- | --- | --- |
| **Antigravity CLI (`agy`)** | `~/.gemini/antigravity-cli/brain/` | `sessions/agy/` | Transcriptions complètes (`transcript.jsonl`), scratchpads, artefacts et index des threads (`session_index.jsonl`) |
| **Claude Code** | `~/.claude/projects/` | `sessions/claude/` | Sessions par projet (`*.jsonl`), sous-agents, tool-results et mémoire |
| **Codex CLI** | `~/.codex/sessions/` | `sessions/codex/` | Transcriptions chronologiques (`YYYY/MM/DD/rollout-*.jsonl`) et index `session_index.jsonl` |

### Exécution manuelle

Le playbook s'exécute directement en tant qu'utilisateur de la station de travail, sans `sudo` ni `-K` :

```bash
cd ~/LINUX
ansible-playbook sync-ai-sessions.yml
```

### Options utiles

- Synchroniser et commiter localement sans pousser sur GitHub :
  ```bash
  ansible-playbook sync-ai-sessions.yml -e git_push=false
  ```
- Synchroniser les fichiers sur disque sans créer de commit git :
  ```bash
  ansible-playbook sync-ai-sessions.yml -e git_commit=false
  ```
- Simulation en mode lecture seule (`--check`) :
  ```bash
  ansible-playbook sync-ai-sessions.yml --check
  ```

### Sécurité et garde-fous

- **Protection des secrets** : Exclusion stricte des jetons d'authentification (`auth.json`), clés privées (`*.key`, `*.pem`), certificats et identifiants.
- **Exclusion des artefacts temporaires** : Les sockets système (`*.sock`), verrous (`*.lock`, `*.pid`) et fichiers journaux SQLite (`*.db-shm`, `*.db-wal`) sont ignorés.
- **Plafond de taille GitHub** : Seuil maximal fixé à 50 Mo par fichier (`max_file_size: "50m"`) pour garantir le respect de la limite de 100 Mo imposée par GitHub.
- **Détection intelligente** : Découverte automatique de la branche git active et création de commit uniquement si des modifications réelles sont constatées.

### Validation

```bash
ansible-playbook sync-ai-sessions.yml --syntax-check
python3 tests/test_sync_ai_sessions.py
```

