#!/usr/bin/env python3
"""
kssh: Smart SSH connector using the KeePass server pool.
Resolves hostname/IP, port, user, key, and password automatically.
"""

import sys
import os
import json
import subprocess

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
REPO_DIR = os.path.abspath(os.path.join(SCRIPT_DIR, ".."))
POOL_JSON = os.path.join(REPO_DIR, "inventory", "server_pool.json")
if not os.path.isfile(POOL_JSON):
    POOL_JSON = os.path.expanduser("~/.ansible/inventory/server_pool.json")
PRIV_KEY = os.path.expanduser("~/.ssh/id_ed25519")

def main():
    args = sys.argv[1:]
    if not args or '-h' in args or '--help' in args:
        print("\033[1mUsage:\033[0m kssh [-u <USER>] <SERVER_NAME_OR_IP> [SSH_OPTIONS / REMOTE_COMMAND]")
        print("Examples: kssh mtq-mailsrvp-01")
        print("          kssh -u superuser trp-wextp-fe1")
        print("          kssh trp-wextp-fe1 uptime")
        print("          kssh 172.30.231.177")
        sys.exit(0)

    if not os.path.isfile(POOL_JSON):
        print(f"\033[0;31m[ERROR] Server pool not found at {POOL_JSON}.\033[0m")
        print("Run: ansible-playbook playbooks/kdbx-pool.yml -e 'action=sync' to build it.")
        sys.exit(1)

    preferred_user = None
    if '-u' in args:
        idx = args.index('-u')
        if idx + 1 < len(args):
            preferred_user = args[idx + 1]
            args = args[:idx] + args[idx + 2:]
    elif '--user' in args:
        idx = args.index('--user')
        if idx + 1 < len(args):
            preferred_user = args[idx + 1]
            args = args[:idx] + args[idx + 2:]

    if not args:
        print("[ERROR] Missing server name or IP.")
        sys.exit(1)

    query = args[0].lower().strip()
    extra_args = args[1:]

    with open(POOL_JSON, 'r') as f:
        data = json.load(f)

    servers = data.get('servers', [])
    results = []

    for s in servers:
        haystack = " ".join([
            s.get('title', ''),
            s.get('group', ''),
            " ".join(s.get('ips', [])),
            s.get('username', ''),
            s.get('notes', '')
        ]).lower()
        if query in haystack:
            results.append(s)

    # Filter/rank: exact title match or active servers (exclude Recycle Bin if alternatives exist)
    exact = [s for s in results if s.get('title', '').lower() == query]
    if exact:
        active = [s for s in exact if 'recycle bin' not in s.get('group', '').lower()]
        results = active if active else exact
    else:
        active = [s for s in results if 'recycle bin' not in s.get('group', '').lower()]
        if active:
            results = active

    if preferred_user:
        user_matches = [s for s in results if s.get('username', '').lower() == preferred_user.lower()]
        if user_matches:
            results = user_matches

    if not results:
        print(f"\033[0;33m[WARN] No server found in KeePass pool matching '{query}'.\033[0m")
        sys.exit(1)

    target = None
    if len(results) == 1:
        target = results[0]
    else:
        # If non-interactive, pick superuser or first match automatically
        if not sys.stdin.isatty() or extra_args:
            su_matches = [s for s in results if s.get('username', '').lower() == 'superuser']
            target = su_matches[0] if su_matches else results[0]
            print(f"[kssh] Non-interactive mode: auto-selected {target.get('title')} ({target.get('username')})")
        else:
            print(f"\033[1mMultiple matches found for '{query}':\033[0m")
            for i, s in enumerate(results, 1):
                ip = s.get('primary_ip') or 'No IP'
                port = f":{s.get('port')}" if s.get('port') else ""
                print(f"  [{i}] \033[0;32m{s.get('title')}\033[0m ({ip}{port}) - User: {s.get('username')} [\033[0;34m{s.get('group')}\033[0m]")
            try:
                choice = input(f"Select server [1-{len(results)}]: ")
                idx = int(choice.strip()) - 1
                if 0 <= idx < len(results):
                    target = results[idx]
                else:
                    print("Invalid selection.")
                    sys.exit(1)
            except (ValueError, KeyboardInterrupt, EOFError):
                print("\nAborted.")
                sys.exit(1)

    title = target.get('title', 'Unknown')
    ip = target.get('primary_ip')
    port = str(target.get('port') or 22)
    user = target.get('username') or 'superuser'
    password = target.get('password', '')

    if not ip:
        print(f"\033[0;31m[ERROR] No IP address associated with '{title}'.\033[0m")
        sys.exit(1)

    print(f"\033[0;32m[kssh]\033[0m Connecting to \033[1m{title}\033[0m (\033[0;33m{user}@{ip}:{port}\033[0m)...")

    def test_key_login(login_user):
        cmd = [
            'ssh', '-o', 'BatchMode=yes', '-o', 'ConnectTimeout=2',
            '-o', 'StrictHostKeyChecking=accept-new',
            '-p', port, '-i', PRIV_KEY,
            f"{login_user}@{ip}", "true"
        ]
        res = subprocess.run(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        return res.returncode == 0

    # 1. Try koby-bowser-ansible with Ed25519 key
    if os.path.isfile(PRIV_KEY) and test_key_login('koby-bowser-ansible'):
        os.execvp('ssh', ['ssh', '-p', port, '-i', PRIV_KEY, f"koby-bowser-ansible@{ip}"] + extra_args)

    # 2. Try target user with Ed25519 key
    if os.path.isfile(PRIV_KEY) and test_key_login(user):
        os.execvp('ssh', ['ssh', '-p', port, '-i', PRIV_KEY, f"{user}@{ip}"] + extra_args)

    # 3. If password exists and sshpass is available, use sshpass
    if password:
        sshpass_bin = subprocess.run(['which', 'sshpass'], capture_output=True, text=True).stdout.strip()
        if sshpass_bin:
            os.environ['SSHPASS'] = password
            os.execvp('sshpass', ['sshpass', '-e', 'ssh', '-p', port, '-o', 'StrictHostKeyChecking=accept-new', f"{user}@{ip}"] + extra_args)

    # 4. Fallback to standard interactive SSH
    os.execvp('ssh', ['ssh', '-p', port, '-o', 'StrictHostKeyChecking=accept-new', f"{user}@{ip}"] + extra_args)

if __name__ == '__main__':
    main()
