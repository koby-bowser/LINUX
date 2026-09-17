#!/usr/bin/env bash
# ==============================================================================
# Script: search-servers.sh
# Purpose: Instant CLI search across the KeePass server pool.
#          Can also trigger a full sync if the database changed.
# ==============================================================================

set -eo pipefail

REAL_PATH="$(readlink -f "${BASH_SOURCE[0]}")"
SCRIPT_DIR="$(cd "$(dirname "${REAL_PATH}")" && pwd)"
ANSIBLE_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
POOL_JSON="${ANSIBLE_DIR}/inventory/server_pool.json"
PARSER="${SCRIPT_DIR}/build_kdbx_pool.py"

C_RESET=$'\033[0m'
C_BOLD=$'\033[1m'
C_GREEN=$'\033[0;32m'
C_YELLOW=$'\033[0;33m'
C_BLUE=$'\033[0;34m'

usage() {
    cat << USAGE
${C_BOLD}Usage:${C_RESET}
    $(basename "$0") [OPTIONS] <SEARCH_TERM>
    $(basename "$0") --sync [--db <PATH_TO_KDBX>]

${C_BOLD}Description:${C_RESET}
    Searches your KeePass server pool across Hostnames, IPs, Usernames,
    Groups, and Notes in milliseconds. Passwords in notes are masked by default.

${C_BOLD}Options:${C_RESET}
    -r, --reveal           Reveal protected passwords in Notes for matching entries
    --sync                 Prompt for master password and rebuild the server pool
    --db <PATH>            Specify alternative .kdbx path (default: Documents/keePassXC/OMT_PFS.SYSTEME.ALL.kdbx)
    -j, --json             Output raw JSON for scripting/automation
    -h, --help             Show this help message

${C_BOLD}Examples:${C_RESET}
    $(basename "$0") 172.30.231
    $(basename "$0") -r mtq-mailsrvp-01
    $(basename "$0") mail
    $(basename "$0") --sync
USAGE
    exit 0
}

if [[ $# -eq 0 ]]; then
    usage
fi

SYNC=false
JSON_OUT=false
REVEAL=false
DB_PATH=""
SEARCH_TERM=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)
            usage
            ;;
        --sync)
            SYNC=true
            shift
            ;;
        --db)
            DB_PATH="$2"
            shift 2
            ;;
        -j|--json)
            JSON_OUT=true
            shift
            ;;
        -r|--reveal)
            REVEAL=true
            shift
            ;;
        *)
            SEARCH_TERM="$1"
            shift
            ;;
    esac
done

if [ "$SYNC" = true ] || [ ! -f "$POOL_JSON" ]; then
    echo -e "${C_BOLD}=== [Synchronizing Server Pool from KeePass] ===${C_RESET}"
    read -s -p "Enter KeePass Master Password: " MASTER_PASS
    echo ""
    
    EXTRA_ARGS=()
    if [ -n "$DB_PATH" ]; then
        EXTRA_ARGS+=("--db" "$DB_PATH")
    fi
    if [ -n "$SEARCH_TERM" ]; then
        EXTRA_ARGS+=("--search" "$SEARCH_TERM")
    fi
    if [ "$JSON_OUT" = true ]; then
        EXTRA_ARGS+=("--json-output")
    fi
    if [ "$REVEAL" = true ]; then
        EXTRA_ARGS+=("--reveal-secrets")
    fi

    echo "$MASTER_PASS" | "$PARSER" "${EXTRA_ARGS[@]}" --sync
    unset MASTER_PASS
    exit 0
fi

# Fast search using cached pool
CMD=("$PARSER" "--search" "$SEARCH_TERM")
if [ "$JSON_OUT" = true ]; then
    CMD+=("--json-output")
fi
if [ "$REVEAL" = true ]; then
    CMD+=("--reveal-secrets")
fi

"${CMD[@]}"
