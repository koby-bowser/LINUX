#!/usr/bin/env bash
# ==============================================================================
# Script: copy-to-remote.sh
# Purpose: Ensures 'koby-bowser-ansible' user exists on remote host with
#          passwordless SSH (Debian Trixie ed25519 pubkey) and passwordless sudo,
#          honoring host sshd configuration (AllowGroups, AuthorizedKeysFile),
#          then runs playbooks/copy-to-tmp.yml to copy specified file to /tmp.
# Workspace: ~/.ansible
# ==============================================================================

set -eo pipefail

# ANSI Colors (Ubuntu terminal standard)
C_RESET=$'\033[0m'
C_RED=$'\033[0;31m'
C_GREEN=$'\033[0;32m'
C_YELLOW=$'\033[0;33m'
C_BLUE=$'\033[0;34m'
C_BOLD=$'\033[1m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ANSIBLE_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
PLAYBOOK="${ANSIBLE_DIR}/playbooks/copy-to-tmp.yml"

TARGET_USER="koby-bowser-ansible"
PUBKEY_PATH="${HOME}/.ssh/id_ed25519.pub"
PRIVKEY_PATH="${HOME}/.ssh/id_ed25519"
SSH_PORT="22"
ADMIN_USER="root"
ASK_PASS=false

usage() {
    cat << USAGE
${C_BOLD}Usage:${C_RESET}
    $(basename "$0") [OPTIONS] <REMOTE_HOST> <FILE_PATH>

${C_BOLD}Description:${C_RESET}
    1. Checks if '${TARGET_USER}' is present on <REMOTE_HOST> with passwordless SSH.
    2. If missing, connects via admin user to create '${TARGET_USER}', dynamically
       respects sshd AllowGroups & AuthorizedKeysFile, installs your Debian Trixie
       ed25519 pubkey, and configures passwordless sudo.
    3. Executes '${PLAYBOOK}' to copy <FILE_PATH> to /tmp on <REMOTE_HOST>.

${C_BOLD}Arguments:${C_RESET}
    <REMOTE_HOST>          Target hostname or IP address
    <FILE_PATH>            Local file to copy into remote /tmp

${C_BOLD}Options:${C_RESET}
    -p, --port <PORT>      SSH port (default: ${SSH_PORT})
    -a, --admin <USER>     Admin/bootstrap user if '${TARGET_USER}' needs creation (default: ${ADMIN_USER})
    -k, --pubkey <PATH>    Path to SSH public key (default: ${PUBKEY_PATH})
    -i, --privkey <PATH>   Path to SSH private key (default: ${PRIVKEY_PATH})
    -K, --ask-pass         Prompt for administrative SSH/sudo password during bootstrap
    -h, --help             Show this help message

${C_BOLD}Examples:${C_RESET}
    $(basename "$0") 192.168.1.50 /home/koby/sample.txt
    $(basename "$0") -p 30 -a superuser -K 172.30.231.17 /home/koby/sample.txt
USAGE
    exit 0
}

# Parse options
POSITIONAL_ARGS=()
while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)
            usage
            ;;
        -p|--port)
            SSH_PORT="$2"
            shift 2
            ;;
        -a|--admin)
            ADMIN_USER="$2"
            shift 2
            ;;
        -k|--pubkey)
            PUBKEY_PATH="$2"
            shift 2
            ;;
        -i|--privkey)
            PRIVKEY_PATH="$2"
            shift 2
            ;;
        -K|--ask-pass)
            ASK_PASS=true
            shift
            ;;
        -*)
            echo -e "${C_RED}[ERROR] Unknown option: $1${C_RESET}" >&2
            usage
            ;;
        *)
            POSITIONAL_ARGS+=("$1")
            shift
            ;;
    esac
done

if [[ ${#POSITIONAL_ARGS[@]} -lt 2 ]]; then
    echo -e "${C_RED}[ERROR] Missing required arguments: <REMOTE_HOST> and <FILE_PATH>${C_RESET}\n" >&2
    usage
fi

REMOTE_HOST="${POSITIONAL_ARGS[0]}"
FILE_PATH="${POSITIONAL_ARGS[1]}"

# 1. Pre-flight local validation
echo -e "${C_BOLD}=== [Pre-flight Diagnostics] ===${C_RESET}"

if [[ ! -f "$FILE_PATH" ]]; then
    echo -e "${C_RED}[ERROR] Local source file does not exist: ${FILE_PATH}${C_RESET}" >&2
    exit 1
fi
FILE_SIZE=$(stat -c%s "${FILE_PATH}")
echo -e "  Source File  : ${C_GREEN}${FILE_PATH}${C_RESET} (${FILE_SIZE} bytes)"

if [[ ! -f "$PUBKEY_PATH" ]]; then
    echo -e "${C_RED}[ERROR] SSH public key not found: ${PUBKEY_PATH}${C_RESET}" >&2
    exit 1
fi
PUBKEY_CONTENT="$(cat "${PUBKEY_PATH}")"
PUBKEY_LABEL="$(echo "${PUBKEY_CONTENT}" | awk '{print $NF}')"
echo -e "  Public Key   : ${C_GREEN}${PUBKEY_PATH}${C_RESET} (${PUBKEY_LABEL})"
echo -e "  Target Host  : ${C_BOLD}${REMOTE_HOST}${C_RESET} (Port: ${SSH_PORT})"
echo -e "  Target User  : ${C_BOLD}${TARGET_USER}${C_RESET}"

# 2. Check passwordless login for koby-bowser-ansible
echo -e "\n${C_BOLD}=== [Step 1: Check Target User '${TARGET_USER}'] ===${C_RESET}"

SSH_TEST_OPTS=(
    -o "BatchMode=yes"
    -o "ConnectTimeout=5"
    -o "StrictHostKeyChecking=accept-new"
    -p "${SSH_PORT}"
    -i "${PRIVKEY_PATH}"
)

if ssh "${SSH_TEST_OPTS[@]}" "${TARGET_USER}@${REMOTE_HOST}" "id -u ${TARGET_USER}" >/dev/null 2>&1; then
    echo -e "${C_GREEN}[OK] User '${TARGET_USER}' is present with active passwordless SSH login.${C_RESET}"
else
    echo -e "${C_YELLOW}[INFO] User '${TARGET_USER}' is NOT accessible via passwordless SSH.${C_RESET}"
    echo -e "${C_YELLOW}[INFO] Initiating bootstrap via administrative account '${ADMIN_USER}'...${C_RESET}"

    ADMIN_PASS=""
    if [ "$ASK_PASS" = true ]; then
        read -s -p "Enter password for ${ADMIN_USER}@${REMOTE_HOST}:${SSH_PORT}: " ADMIN_PASS
        echo ""
    fi

    BOOTSTRAP_PAYLOAD=$(cat << REMOTE_SCRIPT
set -e
TARGET="${TARGET_USER}"
PUB="${PUBKEY_CONTENT}"
ADMIN_P="${ADMIN_PASS}"

run_sudo() {
    if [ "\$(id -u)" -eq 0 ]; then
        "\$@"
    elif [ -n "\$ADMIN_P" ]; then
        echo "\$ADMIN_P" | sudo -S -p "" "\$@"
    else
        sudo "\$@"
    fi
}

# 1. Inspect effective sshd configuration
SSHD_CONFIG="\$(run_sudo sshd -T 2>/dev/null || true)"
AUTH_KEY_PATTERN=\$(echo "\$SSHD_CONFIG" | grep -i '^authorizedkeysfile ' | awk '{print \$2}' | head -n 1)
ALLOW_GROUPS=\$(echo "\$SSHD_CONFIG" | grep -i '^allowgroups ' | cut -d' ' -f2-)

# 2. Create user if not present
if ! id -u "\$TARGET" >/dev/null 2>&1; then
    echo "Creating system user '\$TARGET'..."
    run_sudo useradd -m -s /bin/bash -c "Ansible Automation User" "\$TARGET"
else
    echo "User '\$TARGET' already exists."
fi

# 3. Handle groups (including AllowGroups compliance if configured)
if getent group sudo >/dev/null 2>&1; then
    run_sudo usermod -aG sudo "\$TARGET"
fi
if [ -n "\$ALLOW_GROUPS" ]; then
    for grp in \$ALLOW_GROUPS; do
        if getent group "\$grp" >/dev/null 2>&1; then
            echo "Adding '\$TARGET' to required SSH AllowGroup '\$grp'..."
            run_sudo usermod -aG "\$grp" "\$TARGET"
        fi
    done
fi

TARGET_HOME=\$(getent passwd "\$TARGET" | cut -d: -f6)
TARGET_GID=\$(getent passwd "\$TARGET" | cut -d: -f4)

# 4. Configure passwordless sudo
echo "Configuring passwordless sudo in /etc/sudoers.d/\$TARGET..."
echo "\$TARGET ALL=(ALL) NOPASSWD:ALL" | run_sudo tee "/etc/sudoers.d/\$TARGET" >/dev/null
run_sudo chmod 0440 "/etc/sudoers.d/\$TARGET"

# 5. Deploy public key to resolved authorized_keys destination
run_sudo mkdir -p "\$TARGET_HOME/.ssh"
run_sudo chmod 700 "\$TARGET_HOME/.ssh"
if ! run_sudo grep -qF "\$PUB" "\$TARGET_HOME/.ssh/authorized_keys" 2>/dev/null; then
    echo "\$PUB" | run_sudo tee -a "\$TARGET_HOME/.ssh/authorized_keys" >/dev/null
fi
run_sudo chmod 600 "\$TARGET_HOME/.ssh/authorized_keys"
run_sudo chown -R "\$TARGET:\$TARGET_GID" "\$TARGET_HOME/.ssh"

# Centralized location if sshd uses non-standard pattern like /etc/ssh/authorized_keys/%u
if [ -n "\$AUTH_KEY_PATTERN" ] && [[ "\$AUTH_KEY_PATTERN" =~ %u ]]; then
    RESOLVED_PATH="\${AUTH_KEY_PATTERN//%u/\$TARGET}"
    RESOLVED_PATH="\${RESOLVED_PATH//%h/\$TARGET_HOME}"
    echo "Centralized AuthorizedKeysFile detected: \$RESOLVED_PATH"
    run_sudo mkdir -p "\$(dirname "\$RESOLVED_PATH")"
    if ! run_sudo grep -qF "\$PUB" "\$RESOLVED_PATH" 2>/dev/null; then
        echo "\$PUB" | run_sudo tee -a "\$RESOLVED_PATH" >/dev/null
    fi
    run_sudo chmod 600 "\$RESOLVED_PATH"
    run_sudo chown "\$TARGET:\$TARGET_GID" "\$RESOLVED_PATH" 2>/dev/null || run_sudo chown root:root "\$RESOLVED_PATH"
fi

echo "Remote bootstrap completed successfully."
REMOTE_SCRIPT
    )

    if [ -n "$ADMIN_PASS" ]; then
        sshpass -p "$ADMIN_PASS" ssh -p "${SSH_PORT}" -o "StrictHostKeyChecking=accept-new" "${ADMIN_USER}@${REMOTE_HOST}" "bash -s" <<< "${BOOTSTRAP_PAYLOAD}"
        unset ADMIN_PASS
    else
        ssh -p "${SSH_PORT}" -o "StrictHostKeyChecking=accept-new" "${ADMIN_USER}@${REMOTE_HOST}" "bash -s" <<< "${BOOTSTRAP_PAYLOAD}"
    fi

    # Re-verify passwordless connectivity
    echo -e "\n${C_BOLD}=== [Verifying Passwordless SSH Connection] ===${C_RESET}"
    if ssh "${SSH_TEST_OPTS[@]}" "${TARGET_USER}@${REMOTE_HOST}" "id -u ${TARGET_USER}" >/dev/null 2>&1; then
        echo -e "${C_GREEN}[OK] Verified! Passwordless SSH login successful as '${TARGET_USER}'.${C_RESET}"
    else
        echo -e "${C_RED}[ERROR] Failed to establish passwordless SSH connection as '${TARGET_USER}'. Check remote sshd logs.${C_RESET}" >&2
        exit 1
    fi
fi

# 3. Execute Ansible Playbook
echo -e "\n${C_BOLD}=== [Step 2: Executing Ansible Playbook] ===${C_RESET}"
echo -e "Running: ${C_BLUE}ansible-playbook -i \"${REMOTE_HOST},\" playbooks/copy-to-tmp.yml -u ${TARGET_USER} -e \"src_file=${FILE_PATH}\"${C_RESET}\n"

cd "${ANSIBLE_DIR}"
ansible-playbook \
    -i "${REMOTE_HOST}," \
    "${PLAYBOOK}" \
    -u "${TARGET_USER}" \
    --private-key "${PRIVKEY_PATH}" \
    -e "ansible_port=${SSH_PORT}" \
    -e "src_file=${FILE_PATH}"

echo -e "\n${C_GREEN}${C_BOLD}[SUCCESS] Transfer completed successfully to /tmp on ${REMOTE_HOST}!${C_RESET}"
