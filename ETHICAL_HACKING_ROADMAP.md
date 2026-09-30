# Ethical Hacking & Penetration Testing Roadmap

A comprehensive, structured roadmap for learning ethical hacking, penetration testing, and defensive security.

---

## 0. Ethical Foundations & Legal Boundaries

> **Golden Rule**: Never test, scan, or exploit any system, network, or application without explicit, written authorization from the owner.

* **Rules of Engagement (RoE)**: Clearly defined testing scope, allowed IP ranges/domains, testing windows, and prohibited actions (e.g., DoS, data exfiltration).
* **Non-Disclosure Agreements (NDAs)**: Protecting sensitive organizational findings and data discovered during assessments.
* **Responsible Disclosure**: Standardized reporting channels for submitting vulnerabilities safely (e.g. `security.txt`, bug bounty platforms).

---

## 1. Foundational Knowledge (Prerequisites)

You cannot assess or secure systems without understanding how they operate normally.

### A. Networking & Protocols
* **Models**: OSI 7-Layer model and TCP/IP stack.
* **Core Protocols**:
  * Transport & Network: IP, ICMP, TCP (3-way handshake, flags), UDP.
  * Application: DNS, HTTP/HTTPS, DHCP, SSH, FTP, SMTP, SMB, SNMP, LDAP.
* **Subnetting & Routing**: CIDR notation, VLANs, NAT, routing tables, public vs. private address spaces.
* **Network Analysis**:
  * Packet capture and inspection using `Wireshark` and `tcpdump`.
  * Network discovery and port scanning fundamentals with `nmap`.

### B. Operating Systems
* **Linux**:
  * CLI fluency, standard POSIX utilities, core filesystem hierarchy (`/etc`, `/var`, `/proc`, `/sys`).
  * User/group management, permissions (`chmod`, `chown`, SUID/SGID, sticky bits, ACLs).
  * Process management, system services (`systemd`, `journalctl`), and cron jobs.
  * Kernel architecture basics, modules, and networking stack.
* **Windows & Active Directory**:
  * Windows architecture, Registry, NTFS permissions, Services, and Event Viewer.
  * Enterprise Active Directory: Domain Controllers, Forests, Trees, OUs, Trust relationships.
  * Authentication mechanisms: NTLM, Kerberos (tickets, SPNs), LDAP.
  * Group Policy Objects (GPOs) and access control lists (DACLs/SACLs).

### C. Programming & Scripting
* **Python**: Writing network sockets, HTTP request scripts, automation, payload generation, log parsing.
* **Bash**: Automating Linux reconnaissance, chain pipelines, and environment setup.
* **PowerShell**: Querying Windows WMI/CIM, Active Directory modules, and endpoint scripting.
* **Web Languages**: HTML, CSS, JavaScript, PHP, and SQL.

---

## 2. Security Assessment & Vulnerability Analysis

### A. Web Application Security
* **OWASP Top 10**:
  * Broken Access Control (IDOR, privilege escalation).
  * Cryptographic Failures.
  * Injection flaws (SQLi, Command Injection, LDAP injection).
  * Insecure Design & Security Misconfiguration.
  * Vulnerable and Outdated Components.
  * Identification & Authentication Failures.
  * Server-Side Request Forgery (SSRF) & Cross-Site Scripting (XSS).
* **API Security**: REST and GraphQL security, authentication headers, JWT structure and validation flaws.
* **Testing Toolkit**:
  * Interception proxies: **Burp Suite** (Community/Pro), **OWASP ZAP**.
  * Fuzzing & directory discovery: `ffuf`, `gobuster`, `feroxbuster`.
  * Specialized tools: `sqlmap`.

### B. Network & Infrastructure Assessment
* **Reconnaissance & OSINT**: Whois, DNS enumeration (`dig`, `dnsenum`), certificate transparency logs, Shodan.
* **Vulnerability Scanning**: OpenVAS / Greenbone, Nessus (evaluation/lab).
* **Enumeration**: Service fingerprinting, SMB shares (`smbclient`, `crackmapexec` / `netexec`), SNMP walking.
* **Pivoting & Port Forwarding**: Tunneling traffic through compromised hosts via SSH dynamic forwarding (`-D`), `chisel`, `socat`, and `proxychains`.

### C. Active Directory Security
* **AD Reconnaissance**: Enumerating objects, groups, and permissions with BloodHound and SharpHound.
* **Common Attack Vectors**:
  * Kerberoasting (requesting TGS tickets for accounts with SPNs to crack hashes offline).
  * AS-REP Roasting (targeting accounts with Kerberos pre-authentication disabled).
  * Password spraying and credential dumping (LSASS, SAM, NTDS.dit).
  * Abuse of excessive privileges and vulnerable GPOs / ACLs.

### D. Standards & Frameworks
* **MITRE ATT&CK**: Knowledge base of real-world adversary tactics, techniques, and procedures (TTPs).
* **PTES (Penetration Testing Execution Standard)**: Pre-engagement, Intelligence Gathering, Threat Modeling, Vulnerability Analysis, Exploitation, Post Exploitation, and Reporting.

---

## 3. Hands-On Practice Labs & Sandboxes

Never practice on unauthorized systems. Use legal, structured sandbox environments:

| Platform | Difficulty | Focus |
|---|---|---|
| **[OverTheWire (Bandit)](https://overthewire.org/)** | Beginner | Linux terminal mechanics and basics |
| **[PortSwigger Web Security Academy](https://portswigger.net/web-security)** | Beginner to Advanced | Free, gold-standard interactive web security training |
| **[TryHackMe](https://tryhackme.com/)** | Beginner to Intermediate | Guided learning paths (Pre-Security, Jr Pentester, Web Fundamentals) |
| **[Hack The Box (HTB)](https://www.hackthebox.com/)** | Intermediate to Advanced | Realistic standalone machines, Pro Labs (Active Directory networks) |
| **[VulnHub](https://www.vulnhub.com/)** | All levels | Offline downloadable vulnerable virtual machines |
| **Self-Hosted Labs** | All levels | Local Docker containers: OWASP Juice Shop, DVWA, WebGoat |

---

## 4. Professional Certifications Path

Certifications serve as milestones to structure learning and validate skills:

```
[Foundational]
      │
      ▼
CompTIA Security+  ──►  Theoretical foundation, terminology, and governance
      │
      ▼
[Junior Practical]
      │
      ├─► eJPT (eLearnSecurity Junior Pentester) ──► Guided practical assessment
      │
      └─► PNPT (TCM Security) ───────────────────► OSINT, network, AD, and report writing
      │
      ▼
[Industry Benchmark]
      │
      ▼
OSCP (Offensive Security Certified Professional) ──► 24-hr independent practical exam
      │
      ▼
[Specializations]
      │
      ├─► OSWE / Burp Suite Certified Practitioner ──► Advanced Web Applications
      │
      ├─► CRTP / CRTE (Altered Security) ────────────► Active Directory Penetration Testing
      │
      └─► OSEP (OffSec Experienced Pentester) ────────► Evasion techniques & breach operations
```

---

## 5. Professional Reporting & Bug Bounties

### Technical Report Writing
A penetration test is only as valuable as the report delivered. High-quality reports include:
1. **Executive Summary**: High-level risk overview and business impact tailored for non-technical leadership.
2. **Methodology & Scope**: What was tested, when, and from what vantage point.
3. **Findings & Vulnerability Details**:
   * Severity rating (CVSS score).
   * Detailed description and affected assets.
   * Step-by-step Proof of Concept (PoC) to reproduce safely.
   * Actionable remediation and mitigation guidance.

### Bug Bounty Programs
Once comfortable with web application security and legal testing:
* **Platforms**: HackerOne, Bugcrowd, Intigriti, YesWeHack.
* **Approach**: Always adhere strictly to the target's program policy, scope, and rate limits. Focus on deep business logic flaws rather than shallow automated scans.
