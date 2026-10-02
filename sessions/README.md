# AI CLI Sessions Archive

Ce dossier archive de manière structurée l'ensemble des sessions de travail issues des assistants d'ingénierie IA en ligne de commande :

- **`agy/`** : Sessions d'Antigravity CLI issues de `~/.gemini/antigravity-cli/brain/`. Contient les journaux complets de conversation (`transcript.jsonl`), scratchpads, artefacts produits, ainsi qu'un index des conversations (`session_index.jsonl`).
- **`claude/`** : Sessions de Claude Code issues de `~/.claude/projects/`, organisées par projet (`-home-koby`, etc.) avec les transcriptions JSONL et artefacts associés.
- **`codex/`** : Sessions de Codex CLI issues de `~/.codex/sessions/`, ordonnées chronologiquement (`YYYY/MM/DD/`), avec le fichier d'index `session_index.jsonl`.

### Mise à jour manuelle

Pour synchroniser les sessions locales et pousser les modifications sur GitHub :

```bash
cd ~/LINUX
ansible-playbook sync-ai-sessions.yml
```
