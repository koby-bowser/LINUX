---
name: feedback-dns-prod-safety
description: "Always test destructive DNS zone-file edits on a copy first, and require multi-resolver consensus before trusting DNS-01 propagation"
metadata: 
  node_type: memory
  type: feedback
  originSessionId: 05f38780-fe5a-4cbf-a339-2806ded87760
  modified: 2026-09-03T15:10:43.833Z
---

Two validated safety practices from building `playbooks/issue-deploy-certs.yml`'s `ssh_zonefile`
backend (manual BIND zone-file editing over SSH, for DNS servers without RFC2136/API access):

**1. Test edit scripts on a COPY of the real zone file before ever touching the original.**
Reason: this caught two real bugs before they hit production — (a) a naive "ensure parent
directory permissions" step that would have chowned a SHARED system directory
(`/etc/ssh/authorized_keys`, unrelated incident but same principle) to a single non-root user
(privilege escalation), and (b) confirmed the SOA-serial-bump / TXT-replace logic worked correctly
before running it on `only.fr`, a real production zone for Outremer Telecom/SFR Caraïbe.
**How to apply:** for any new destructive automation touching shared/production config (zone
files, shared directories, etc.), dry-run against a copy, diff the result, only then point at the
real target.

**2. A single successful DNS propagation check is not reliable enough to hand off to Let's
Encrypt.** This ISP's DNS (`ns1`/`ns2.outremer-telecom.fr`) has a regional multi-territory
topology (Martinique, Guadeloupe, Réunion, Guyane, Mayotte) with secondaries that don't converge
perfectly in sync. Confirmed in testing: one domain (`andesite.only.fr`) issued fine after a
single DoH (Google) confirmation; the very next one (`diamond.only.fr`) failed with the OLD stale
TXT value despite an apparently-successful single-resolver check — Let's Encrypt's validator must
have hit a different, not-yet-converged secondary instance.
**How to apply:** require **multiple independent public resolvers to agree** (Google DoH +
Cloudflare DoH) across **several consecutive checks**, plus a safety-margin sleep, before treating
a DNS-01 challenge record as propagated. A single dig/DoH match is not sufficient evidence on this
infrastructure. See [[project-dns-cert-automation]] for where this lives in code.
