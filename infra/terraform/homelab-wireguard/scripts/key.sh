#!/usr/bin/env bash
# Create/remove the host-local WireGuard private key. Never printed, never in state.
set -euo pipefail
: "${WG_HOST:?}"

case "${1:-}" in
  create)
    ssh "$WG_HOST" 'set -eu
      umask 077
      f=/etc/systemd/network/wg0.key
      [ -s "$f" ] || wg genkey > "$f"
      chown root:systemd-network "$f"
      chmod 0640 "$f"'
    ;;
  remove)
    ssh "$WG_HOST" 'rm -f /etc/systemd/network/wg0.key'
    ;;
  *) echo "usage: $0 create|remove" >&2; exit 2 ;;
esac
