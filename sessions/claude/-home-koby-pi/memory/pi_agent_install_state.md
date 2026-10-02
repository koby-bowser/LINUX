---
name: pi-agent-install-state
description: Pi coding agent CLI is installed in /home/koby/pi env but not yet authenticated (/login pending)
metadata: 
  node_type: memory
  type: project
  originSessionId: 9a806463-0a72-413c-b095-a36d42dda13a
  modified: 2026-08-20T15:12:18.554Z
---

Pi coding agent (`@earendil-works/pi-coding-agent` v0.84.2) is installed globally for this user, but `/login` (provider authentication) had not been run yet as of 2026-08-20.

**Why:** System Node.js was v20.19.2 (Debian trixie apt package), but pi requires Node >=22.19.0. Worked around without sudo by installing a standalone Node 22.23.2 to `~/.local/share/pi-node/` (checksum-verified download from nodejs.org) and prepending its `bin/` to PATH in both `~/.config/fish/config.fish` (user's default shell) and `~/.bashrc`. `pi`'s launcher uses `#!/usr/bin/env node`, so PATH order determines which Node it runs — this standalone Node must stay ahead of system node in PATH for pi to keep working.

Also hit `SELF_SIGNED_CERT_IN_CHAIN` from npm during install: this machine sits behind a corporate proxy (`172.16.75.9:3128`, credentials in `~/.npmrc` in plaintext) doing TLS interception with an "OMT" root CA. curl/OpenSSL already trusts it via the system CA store, but Node/npm has its own bundled CA list and doesn't by default. Fixed by setting `NODE_EXTRA_CA_CERTS=/etc/ssl/certs/ca-certificates.crt` for the npm install. Future npm/node network operations from this env (e.g. `pi update`) may need the same env var if they hit the same error.

**How to apply:** When resuming pi setup, the next step is running `pi` then `/login` interactively in a real terminal (not through Claude Code's Bash tool — that command is a full-screen interactive TUI and involves entering credentials, so it shouldn't be piped through an agent). After login, a good smoke test is `pi -p "hello"` (non-interactive, safe to run via Bash tool). If `pi` isn't found in a fresh shell, the PATH edits may not have loaded yet, or `NODE_EXTRA_CA_CERTS` may be needed again for any command that hits the network through the corporate proxy.
