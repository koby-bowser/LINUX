---
name: project-dns-cert-automation
description: "Ansible Let's Encrypt DNS-01 cert-issuance project — current state, what's working, what's next (dnsp-mst1/PowerDNS backend planned)"
metadata: 
  node_type: memory
  type: project
  originSessionId: 05f38780-fe5a-4cbf-a339-2806ded87760
  modified: 2026-09-03T15:11:26.278Z
---

Building `playbooks/issue-deploy-certs.yml` in `~/.ansible` (the koby-bowser-ansible control
node repo) to issue/renew Let's Encrypt certs via DNS-01 and deploy them to the web servers that
host each domain, for Koby's ISP group (Outremer Telecom / SFR Caraïbe — see [[user-role]]).

**Three DNS backends supported, one per domain:**
- `rfc2136` — official `certbot-dns-rfc2136` plugin, for a BIND server with TSIG dynamic-update
  configured. Scaffolded but **not yet tested** — no domain currently uses it in
  `certificates.yml`.
- `ssh_zonefile` — for `ns1` (BIND, IP `172.16.75.250` internal / `217.175.160.55` public, an old
  RHEL/CentOS box with only Python 2, legacy SSH crypto), which has **no** RFC2136/API — edits the
  zone file directly over SSH via a deployed script (`acme-zone-update.sh`), bumps the SOA serial,
  reloads BIND. **Working and tested end-to-end** (staging certs issued successfully for
  `andesite.only.fr` and `diamond.only.fr`). Has a hardened set of safety guards (format detection,
  automatic backup, post-write verification — see [[feedback-dns-prod-safety]]) and an ad-hoc mode
  (`-e cert_domain=X` discovers the owning zone automatically via `named.conf`, no need to
  pre-register the domain in `certificates.yml`).
- `powerdns` — for `dnsp-mst` (PowerDNS), via direct REST API calls in `certbot --manual` hooks
  (no reliable official plugin exists for PowerDNS). **Built but never actually tested** — no real
  PowerDNS credentials have been used yet, this path is unverified.

**Deploy phase** (copy `fullchain.pem`/`privkey.pem` to the domain's actual web server, reload
nginx/apache — only when the issued cert's serial actually changed) is implemented but also
**never exercised for real** — every test so far used `certs_filter`/`cert_domain` with
`--tags issue` only, and `target_host` stayed at the `CHANGEME` placeholder.

**Next planned session (the day after this one — check current date):** build and test a similar
ad-hoc-capable playbook flow for domains hosted on `dnsp-mst1` (the PowerDNS server) — i.e.
actually exercise and validate the `powerdns` backend for the first time, likely following the
same "test on a copy first, verify propagation with multi-resolver consensus" discipline used for
`ns1`. Confirm whether "dnsp-mst1" is the same host as `vault_powerdns_dns_host` in
`playbooks/group_vars/all/vault.yml` (named `dnsp-mst` there — verify the exact hostname/IP before
assuming it's identical).
