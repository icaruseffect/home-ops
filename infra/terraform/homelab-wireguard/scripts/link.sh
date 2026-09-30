#!/usr/bin/env bash
# Install/remove the wg0 systemd-networkd units on the homelab host.
# Uses `networkctl reload` only -- never restarts systemd-networkd (the node runs the cluster).
# `reload` does not delete an existing netdev, so removal deletes the link explicitly.
set -euo pipefail
: "${WG_HOST:?}"

case "${1:-}" in
  apply)
    : "${WG_NETDEV_B64:?}" "${WG_NETWORK_B64:?}"
    ssh "$WG_HOST" "set -eu
      d=/etc/systemd/network
      # a changed .netdev is not re-applied to an existing link: drop it first
      ip link del wg0 2>/dev/null || true
      echo '$WG_NETDEV_B64'  | base64 -d > \$d/40-wg0.netdev
      echo '$WG_NETWORK_B64' | base64 -d > \$d/40-wg0.network
      chown root:systemd-network \$d/40-wg0.netdev \$d/40-wg0.network
      chmod 0640 \$d/40-wg0.netdev
      chmod 0644 \$d/40-wg0.network
      networkctl reload
      sleep 2
      networkctl status wg0 --no-pager | head -12"
    ;;
  remove)
    ssh "$WG_HOST" 'set -u
      d=/etc/systemd/network
      ip link del wg0 2>/dev/null || true
      rm -f $d/40-wg0.netdev $d/40-wg0.network
      networkctl reload'
    ;;
  *) echo "usage: $0 apply|remove" >&2; exit 2 ;;
esac
