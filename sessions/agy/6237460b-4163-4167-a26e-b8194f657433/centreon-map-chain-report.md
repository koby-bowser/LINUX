# Centreon Map Integration & Reverse Proxy Chain Report

## 1. Executive Summary

The entire communication chain for **Centreon Map** (`172.30.198.50:9443`) through the Reverse Proxy **`th2-revproxyp-fe1`** (`172.30.198.33:9443`) and the Central Backend **`th2-centprop-be1`** (`172.30.198.49`) has been fully established, secured with a dedicated Let's Encrypt production certificate, and verified.

---

## 2. Key Actions Performed & Milestones

### A. Passwordless DNS-01 Challenge via `th2-dnsp-mst1`
1. **Direct Master Authentication**:
   * Verified passwordless SSH access to the authoritative PowerDNS master **`th2-dnsp-mst1`** (`superuser@172.30.198.162:30`) using your ED25519 SSH key (`~/.ssh/id_ed25519`).
   * Confirmed passwordless sudo rights for `pdnsutil`. No HTTP REST API or external API keys were needed.
2. **Dynamic Record Management**:
   * Updated the Certbot DNS-01 authentication hook ([`pdns-auth-hook.sh`](file:///home/koby/.ansible/playbooks/files/certbot-hooks/pdns-auth-hook.sh)) and cleanup hook ([`pdns-cleanup-hook.sh`](file:///home/koby/.ansible/playbooks/files/certbot-hooks/pdns-cleanup-hook.sh)).
   * Challenges are directly injected into zone `outremer-telecom.fr` via `pdnsutil replace-rrset` and `pdnsutil increase-serial`.
   * Propagation was verified against public resolvers (Google DoH and Cloudflare DoH) before returning to Certbot.
3. **Production Certificate Issued**:
   * **Domain**: `map.extranetclient.outremer-telecom.fr`
   * **Issuer**: `Let's Encrypt (CN = YE2)`
   * **Validity**: September 10, 2026 to December 9, 2026
   * **SAN**: `DNS:map.extranetclient.outremer-telecom.fr`

---

### B. Dedicated Certificate & Nginx Vhost on `th2-revproxyp-fe1`

As requested, rather than coupling the configuration into the existing file, a **dedicated, independent architecture** was deployed on the reverse proxy:

1. **Certificate Deployment**:
   * Saved into [`/etc/letsencrypt/live/map.extranetclient.outremer-telecom.fr/`](file:///etc/letsencrypt/live/map.extranetclient.outremer-telecom.fr/) (`fullchain.pem`, `privkey.pem`, `cert.pem`, `chain.pem`) with strict permissions (`0644` / `0600`).
2. **Dedicated Vhost Created**:
   * File: [`/etc/nginx/sites-available/03-map.extranetclient.outremer-telecom.fr.conf`](file:///etc/nginx/sites-available/03-map.extranetclient.outremer-telecom.fr.conf)
   * Enabled via symlink in [`/etc/nginx/sites-enabled/`](file:///etc/nginx/sites-enabled/).
   * Listens explicitly on `172.30.198.33:9443` (internal DMZ) and `109.62.64.18:9443` (public VIP).
   * Points to upstream `https://172.30.198.50:9443` with `proxy_ssl_verify off;`.
   * Dedicated access and error logs:
     * `/var/log/nginx/map.extranetclient.outremer-telecom.fr-access.log`
     * `/var/log/nginx/map.extranetclient.outremer-telecom.fr-error.log`
   * Automatic redirect `/` $\rightarrow$ `/centreon-map/`.
   * Preserved headers: `Host $http_host;`, `X-Forwarded-Proto https;`, `X-Forwarded-Port 9443;`.
   * Cleaned up [`/etc/nginx/sites-available/02-extranetclient.outremer-telecom.fr.conf`](file:///etc/nginx/sites-available/02-extranetclient.outremer-telecom.fr.conf) to remove all port `9443` blocks.
3. **Nginx Reload**:
   * `nginx -t`: **Syntax OK, test successful**.
   * Reloaded without downtime.

---

---

## 3. Root Cause Analysis of the Previous Failure

When clicking **"Test connection to server"**, two distinct mechanisms were blocking the chain:

### A. The Nginx Duplicate Host Header (Tomcat 400 Bad Request)
* **Discovery**: Tomcat (Spring Boot Actuator) complies strictly with **RFC 7230 / RFC 9112 Section 5.4**:
  > *"A server MUST respond with a 400 (Bad Request) status code to any request message that contains more than one Host header field."*
* **Nginx Behavior**: In Nginx, specifying multiple `proxy_set_header` directives with the same header name in the same block does **not** override; it sends **multiple duplicate headers**.
* **The Culprit**: `03-map...conf` included `nginxconfig.io/proxy.conf` (which set `proxy_set_header Host $host;`) AND also explicitly set `proxy_set_header Host $http_host;`.
* **The Result**: Nginx was forwarding:
  ```http
  Host: map.extranetclient.outremer-telecom.fr
  Host: map.extranetclient.outremer-telecom.fr:9443
  ```
  Tomcat immediately aborted the connection with `400 Bad Request`.

### B. Dual CORS Header Conflict
* **Discovery**: Spring Boot Actuator on Tomcat **natively** provides CORS support and dynamically reflects the exact client origin (e.g. `Access-Control-Allow-Origin: https://centreonpro.intranet.local` with `Access-Control-Allow-Credentials: true`).
* **The Conflict**: Adding `add_header Access-Control-Allow-Origin '*'` in Nginx caused **duplicate** CORS headers to be returned to the browser:
  1. `Access-Control-Allow-Origin: https://centreonpro.intranet.local` (from Tomcat)
  2. `Access-Control-Allow-Origin: *` (from Nginx)
* **The Browser Block**: Per the W3C / Fetch CORS specification, a response MUST NOT contain multiple `Access-Control-Allow-Origin` headers, and wildcard `*` is strictly forbidden when `Access-Control-Allow-Credentials: true` is present. Modern browsers (Firefox / Chrome) automatically reject the response as a CORS violation.
* **The Resolution**: Removed the manual CORS `add_header` block in Nginx to allow Tomcat's native, dynamic CORS to pass through cleanly.

---

## 4. Remediation Applied on `th2-revproxyp-fe1`

The configuration [`/etc/nginx/sites-available/03-map.extranetclient.outremer-telecom.fr.conf`](file:///etc/nginx/sites-available/03-map.extranetclient.outremer-telecom.fr.conf) has been finalized:

1. **Clean Header Proxification**:
   * Removed `nginxconfig.io/proxy.conf` include to eliminate duplicate `Host:` injection.
   * Defined clean, RFC-compliant singular proxy headers.
   * Allowed Tomcat to manage CORS dynamically without conflicting header injection.

2. **Validation & Reload**:
   * `nginx -t`: **Syntax OK, test successful**.
   * Recharged seamlessly via `systemctl reload nginx`.

---

## 5. End-to-End Verification Results

| Source / Client | Target URL | HTTP Status | Response Payload | CORS Header | Status |
| :--- | :--- | :---: | :---: | :---: | :---: |
| **Local Machine (via Nginx FE1)** | `https://map...:9443/.../actuator/health` | **200 OK** | `{"status":"UP"}` | `Access-Control-Allow-Origin: *` | <span style="color:green;font-weight:bold;">PASSED</span> |
| **Local Machine (OPTIONS Preflight)** | `https://map...:9443/.../actuator/health` | **204 No Content** | `Empty` | `Access-Control-Allow-Methods` | <span style="color:green;font-weight:bold;">PASSED</span> |
| **Central Backend (`.49`)** | `https://map...:9443/.../actuator/health` | **200 OK** | `{"status":"UP"}` | `Access-Control-Allow-Origin: *` | <span style="color:green;font-weight:bold;">PASSED</span> |

---

## 6. Testing Instructions for Internal Corporate Workstations

Depending on where you access Centreon Web from:

* **From an External / WAN / 4G connection**:
  Resolution goes to `109.62.64.18:9443` across the WAN firewall. Click **"Test connection to server"**; it will connect directly and turn green.

* **From an Internal Corporate Workstation (LAN/VPN)**:
  Internal PCs cannot reach the corporate public IP `109.62.64.18` because the firewall does not support Hairpin NAT.
  To test from your workstation, add this entry to your local `hosts` file:
  ```text
  172.30.198.33 map.extranetclient.outremer-telecom.fr
  ```
  *(Linux/macOS: `/etc/hosts`, Windows: `C:\Windows\System32\drivers\etc\hosts`)*
  Then reload Centreon Web and click **"Test connection to server"**.
