#!/usr/bin/env bash
set -e

# Initialize container SSH directory
mkdir -p /root/.ssh
chmod 700 /root/.ssh

# If host SSH directory is mounted to /root/.host_ssh, copy and enforce strict permissions
if [ -d /root/.host_ssh ]; then
    cp -a /root/.host_ssh/. /root/.ssh/ 2>/dev/null || true
    chmod 700 /root/.ssh
    chmod 600 /root/.ssh/* 2>/dev/null || true
    [ -f /root/.ssh/known_hosts ] && chmod 644 /root/.ssh/known_hosts 2>/dev/null || true
    for pub in /root/.ssh/*.pub; do
        [ -f "$pub" ] && chmod 644 "$pub" 2>/dev/null || true
    done
fi

# If SSHPASS is defined, wrap command with sshpass
SSH_RUNNER=()
if [ -n "${SSHPASS}" ] && command -v sshpass >/dev/null 2>&1; then
    SSH_RUNNER=("sshpass" "-e")
fi

case "$1" in
    ssh)
        shift
        exec "${SSH_RUNNER[@]}" ssh "$@"
        ;;
    scp)
        shift
        exec "${SSH_RUNNER[@]}" scp "$@"
        ;;
    sftp)
        shift
        exec "${SSH_RUNNER[@]}" sftp "$@"
        ;;
    ssh-keyscan|ssh-copy-id)
        CMD="$1"
        shift
        exec "${CMD}" "$@"
        ;;
    sh|bash|/bin/sh|/bin/bash)
        exec "$@"
        ;;
    -V|--version)
        exec ssh -V
        ;;
    *)
        exec "${SSH_RUNNER[@]}" ssh "$@"
        ;;
esac
