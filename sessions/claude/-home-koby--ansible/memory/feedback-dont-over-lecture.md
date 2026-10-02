---
name: feedback-dont-over-lecture
description: "Flag secret exposure in chat once clearly, then act — don't repeat the same security lecture every time it happens again"
metadata: 
  node_type: memory
  type: feedback
  originSessionId: 05f38780-fe5a-4cbf-a339-2806ded87760
  modified: 2026-09-03T15:10:31.025Z
---

Koby routinely pastes real credentials (SSH/sudo passwords) directly into chat to get things
moving quickly, across many different hosts in the same session. The first couple of times this
happened, flagging it clearly (exposed in terminal/history, treat as compromised, rotate if
possible) was the right call — especially when it was a genuine accidental exposure (e.g. pasted
into a prompt string instead of a hidden input).

**Why:** after the pattern is established and acknowledged, re-lecturing on every subsequent
password paste becomes noise that slows down real infra work without adding value — he already
knows.

**How to apply:** handle each pasted secret the same secure way every time (ephemeral scratchpad
file, chmod 600, shred after use, never echo back, never write into a persisted file) without
re-explaining the rationale each time. Only re-flag explicitly if something NEW and different goes
wrong (e.g., a secret ends up somewhere it doesn't belong, like a shell history or a `-P` prompt
string by mistake).
