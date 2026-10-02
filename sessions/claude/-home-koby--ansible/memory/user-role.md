---
name: user-role
description: "Koby's role and infrastructure context — sysadmin managing real production DNS/certs for a French overseas-territories ISP group"
metadata: 
  node_type: memory
  type: user
  originSessionId: 05f38780-fe5a-4cbf-a339-2806ded87760
  modified: 2026-09-03T15:10:20.629Z
---

Koby administers real production infrastructure for a telecom group covering French overseas
territories (Outremer Telecom, SFR Caraïbe, and related brands — Martinique, Guadeloupe, Réunion,
Guyane, Mayotte). Domains like `outremer-telecom.fr`, `sfrcaraibe.fr`, `only.fr` are genuine
production zones he manages, not test/lab domains — treat infrastructure work here as production
work by default, even when staged/tested first.

He works methodically and iteratively: build something, test it against a copy/staging first,
run it for real, read the actual error output carefully, and fix forward. He's comfortable
pasting real credentials (passwords, sudo passwords) directly into chat when needed to get
something done quickly — flag the security exposure once when it happens, but don't lecture
repeatedly about it once acknowledged (see [[feedback-dont-over-lecture]]).

Primary machine: Debian Trixie PC "Kaboom" (`koby@Kaboom`), used as the Ansible control node.
Shell: fish (not bash) — commands given to him must be fish-syntax (no heredocs, `set`/`read -s`
instead of bash idioms).
