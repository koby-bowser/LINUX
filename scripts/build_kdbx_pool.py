#!/usr/bin/env python3
"""
KeePass (.kdbx) Server Pool Builder & Search Engine
Extracts server entries, IPs, logins, passwords, ports, and metadata from KeePass.
Generates an Ansible inventory (YAML) and search index (JSON) with 0600 permissions.
"""

import sys
import os
import re
import json
import yaml
import subprocess
import argparse
import xml.etree.ElementTree as ET
from datetime import datetime, timezone

IP_REGEX = re.compile(
    r'\b(?:(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\b'
)
PORT_REGEX = re.compile(r'ssh(\d{2,5})://|:(\d{2,5})\b|port\s*[:=]?\s*(\d{2,5})', re.IGNORECASE)

EXCLUDE_IPS = {'0.0.0.0', '255.255.255.255', '255.255.255.0', '255.0.0.0'}


def extract_servers_from_xml(xml_content):
    root = ET.fromstring(xml_content)
    servers = []

    def parse_group(group_elem, current_path=''):
        name_elem = group_elem.find('Name')
        group_name = name_elem.text.strip() if (name_elem is not None and name_elem.text) else 'General'
        group_path = f"{current_path}/{group_name}" if current_path else group_name

        for entry in group_elem.findall('Entry'):
            fields = {}
            for s in entry.findall('String'):
                k = s.find('Key')
                v = s.find('Value')
                if k is not None and k.text:
                    fields[k.text.strip()] = (v.text.strip() if (v is not None and v.text) else '')

            title = fields.get('Title', '').strip()
            username = fields.get('UserName', '').strip()
            password = fields.get('Password', '').strip()
            url = fields.get('URL', '').strip()
            notes = fields.get('Notes', '').strip()

            all_text = " ".join([title, url, notes] + list(fields.values()))
            raw_ips = IP_REGEX.findall(all_text)
            
            ips = []
            for ip in raw_ips:
                if ip not in EXCLUDE_IPS and ip not in ips:
                    ips.append(ip)

            port = None
            port_match = PORT_REGEX.search(f"{url} {notes}")
            if port_match:
                port_str = port_match.group(1) or port_match.group(2) or port_match.group(3)
                try:
                    p = int(port_str)
                    if 1 <= p <= 65535:
                        port = p
                except ValueError:
                    pass

            protocol = 'ssh'
            if 'rdp' in url.lower() or 'rdp' in notes.lower() or port == 3389:
                protocol = 'rdp'
            elif 'https' in url.lower() or port == 443:
                protocol = 'https'
            elif 'http' in url.lower() or port == 80:
                protocol = 'http'

            if title or ips or username:
                servers.append({
                    'title': title or (ips[0] if ips else 'Unnamed'),
                    'group': group_path,
                    'ips': ips,
                    'primary_ip': ips[0] if ips else None,
                    'username': username,
                    'password': password,
                    'port': port,
                    'protocol': protocol,
                    'url': url,
                    'notes': notes,
                    'custom_fields': {k: v for k, v in fields.items() if k not in {'Title', 'UserName', 'Password', 'URL', 'Notes'}}
                })

        for child_group in group_elem.findall('Group'):
            parse_group(child_group, group_path)

    root_group = root.find('Root')
    if root_group is not None:
        for g in root_group.findall('Group'):
            parse_group(g)

    return servers


def generate_ansible_inventory(servers):
    inventory = {
        'all': {
            'children': {
                'kdbx_pool': {
                    'hosts': {}
                }
            }
        }
    }

    seen_hostnames = {}
    for s in servers:
        raw_name = s['title'] or s['primary_ip'] or 'host'
        safe_name = re.sub(r'[^a-zA-Z0-9_.-]', '_', raw_name).strip('_')
        if not safe_name:
            safe_name = f"host_{s['primary_ip'].replace('.', '_')}" if s['primary_ip'] else 'unknown_host'

        if safe_name in seen_hostnames:
            seen_hostnames[safe_name] += 1
            safe_name = f"{safe_name}_{seen_hostnames[safe_name]}"
        else:
            seen_hostnames[safe_name] = 1

        host_entry = {}
        if s['primary_ip']:
            host_entry['ansible_host'] = s['primary_ip']
        if s['username']:
            host_entry['ansible_user'] = s['username']
        if s['password']:
            host_entry['ansible_password'] = s['password']
            host_entry['kdbx_password'] = s['password']
        if s['port']:
            host_entry['ansible_port'] = s['port']
        
        host_entry['kdbx_title'] = s['title']
        host_entry['kdbx_group'] = s['group']
        host_entry['kdbx_ips'] = s['ips']
        host_entry['kdbx_protocol'] = s['protocol']
        if s['notes']:
            host_entry['kdbx_notes'] = s['notes'][:250]

        inventory['all']['children']['kdbx_pool']['hosts'][safe_name] = host_entry

    return inventory


def search_pool(servers, query):
    q = query.lower().strip()
    results = []
    for s in servers:
        haystack = " ".join([
            s.get('title', ''),
            s.get('group', ''),
            " ".join(s.get('ips', [])),
            s.get('username', ''),
            s.get('url', ''),
            s.get('notes', '')
        ]).lower()
        if q in haystack:
            results.append(s)
    return results


def print_search_results(matches, query, use_color=False):
    if not use_color:
        C_RESET = C_GREEN = C_YELLOW = C_BLUE = C_RED = C_BOLD = C_CYAN = ""
    else:
        C_RESET = "\033[0m"
        C_GREEN = "\033[0;32m"
        C_YELLOW = "\033[0;33m"
        C_BLUE = "\033[0;34m"
        C_RED = "\033[0;31m"
        C_BOLD = "\033[1m"
        C_CYAN = "\033[0;36m"

    lines = []
    lines.append(f"{C_BOLD}=== [Search Results for '{query}': {len(matches)} match(es)] ==={C_RESET}")
    lines.append("")

    if not matches:
        lines.append("No matching servers found.")
        print("\n".join(lines))
        return

    for idx, s in enumerate(matches, 1):
        ips_str = ", ".join(s.get('ips', [])) if s.get('ips') else "No IP"
        user_str = s.get('username') or "None"
        pass_str = s.get('password') or "None"
        port_str = f" (Port: {s.get('port')})" if s.get('port') else ""
        proto_str = f"[{s.get('protocol', 'SSH').upper()}]"

        lines.append(f"  {C_BOLD}[{idx}] {C_GREEN}{s.get('title', 'Unnamed')}{C_RESET} {C_CYAN}{proto_str}{C_RESET}")
        lines.append(f"      {C_BOLD}IP(s)    :{C_RESET} {C_YELLOW}{ips_str}{C_RESET}{port_str}")
        lines.append(f"      {C_BOLD}User     :{C_RESET} {user_str}")
        if pass_str != "None":
            lines.append(f"      {C_BOLD}Password :{C_RESET} {C_RED}{pass_str}{C_RESET}")
        lines.append(f"      {C_BOLD}Group    :{C_RESET} {C_BLUE}{s.get('group', 'Unknown')}{C_RESET}")
        if s.get('notes'):
            clean_notes = " ".join(s['notes'].split())
            lines.append(f"      {C_BOLD}Notes    :{C_RESET} {clean_notes}")
        lines.append("")

    print("\n".join(lines))


def main():
    script_dir = os.path.dirname(os.path.abspath(__file__))
    repo_dir = os.path.abspath(os.path.join(script_dir, ".."))
    default_yaml = os.path.join(repo_dir, "inventory", "server_pool.yml")
    default_json = os.path.join(repo_dir, "inventory", "server_pool.json")

    parser = argparse.ArgumentParser(description="KeePass Server Pool Manager")
    parser.add_argument('--db', default=os.path.expanduser('~/Documents/keePassXC/OMT_PFS.SYSTEME.ALL.kdbx'), help='Path to .kdbx file')
    parser.add_argument('--output-yaml', default=default_yaml, help='Output Ansible inventory YAML')
    parser.add_argument('--output-json', default=default_json, help='Output JSON cache')
    parser.add_argument('--search', help='Search query to filter servers')
    parser.add_argument('--json-output', action='store_true', help='Output search results as JSON')
    parser.add_argument('--sync', action='store_true', help='Force sync from KeePass DB')
    parser.add_argument('--color', action='store_true', help='Force colored output')
    parser.add_argument('--no-color', action='store_true', help='Disable colored output')
    args = parser.parse_args()

    # Determine color output: enabled if requested or interactive tty, disabled if --no-color or piping to Ansible
    use_color = False
    if args.color:
        use_color = True
    elif args.no_color:
        use_color = False
    elif sys.stdout.isatty():
        use_color = True

    # Search existing pool
    if args.search and not args.sync and os.path.isfile(args.output_json):
        with open(args.output_json, 'r') as f:
            data = json.load(f)
        servers = data.get('servers', [])
        matches = search_pool(servers, args.search)
        if args.json_output:
            print(json.dumps(matches, indent=2))
        else:
            print_search_results(matches, args.search, use_color=use_color)
        return

    # Sync from KeePass DB
    if not os.path.isfile(args.db):
        fallback = '/home/koby/Downloads/OMT_PFS.SYSTEME.ALL.kdbx'
        if os.path.isfile(fallback):
            args.db = fallback
        else:
            print(f"[ERROR] KeePass database not found at {args.db}", file=sys.stderr)
            sys.exit(1)

    password = sys.stdin.read().rstrip('\r\n')
    if not password:
        print("[ERROR] Master password required via stdin.", file=sys.stderr)
        sys.exit(1)

    cmd = ['keepassxc-cli', 'export', '-q', '-f', 'xml', args.db]
    try:
        proc = subprocess.Popen(cmd, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        stdout, stderr = proc.communicate(input=password)
    except Exception as e:
        print(f"[ERROR] Failed to execute keepassxc-cli: {e}", file=sys.stderr)
        sys.exit(1)

    if proc.returncode != 0:
        print(f"[ERROR] Failed to decrypt KeePass database. Incorrect password or invalid database.", file=sys.stderr)
        if stderr:
            print(stderr.strip(), file=sys.stderr)
        sys.exit(2)

    servers = extract_servers_from_xml(stdout)

    os.makedirs(os.path.dirname(os.path.abspath(args.output_yaml)), exist_ok=True)
    os.makedirs(os.path.dirname(os.path.abspath(args.output_json)), exist_ok=True)

    payload = {
        'metadata': {
            'generated_at': datetime.now(timezone.utc).isoformat(),
            'source_db': args.db,
            'total_servers': len(servers),
            'total_with_ip': sum(1 for s in servers if s['primary_ip'])
        },
        'servers': servers
    }
    with open(args.output_json, 'w') as f:
        json.dump(payload, f, indent=2)
    os.chmod(args.output_json, 0o600)

    inv_data = generate_ansible_inventory(servers)
    with open(args.output_yaml, 'w') as f:
        f.write("# Ansible Inventory generated automatically from KeePass database\n")
        f.write(f"# Source: {args.db}\n")
        f.write(f"# Total Servers: {len(servers)} | Updated: {datetime.now(timezone.utc).isoformat()}\n\n")
        yaml.dump(inv_data, f, default_flow_style=False, sort_keys=False)
    os.chmod(args.output_yaml, 0o600)

    print(f"[OK] Successfully built server pool: {len(servers)} total entries ({payload['metadata']['total_with_ip']} with IP addresses).")
    print(f"     Ansible Inventory : {args.output_yaml} (mode 0600)")
    print(f"     Search Cache      : {args.output_json} (mode 0600)")

    if args.search:
        matches = search_pool(servers, args.search)
        if args.json_output:
            print(json.dumps(matches, indent=2))
        else:
            print_search_results(matches, args.search, use_color=use_color)


if __name__ == '__main__':
    main()
