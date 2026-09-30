# homelab <-> talos-flux WireGuard tunnel

Private link so talos-flux's `cilium-gateway` can reach Home Assistant on homelab
(HTTPRoute + Authelia `ExternalAuth`). Host-level WireGuard on both nodes.

|                           | address          | notes                                                    |
| ------------------------- | ---------------- | -------------------------------------------------------- |
| talos-flux (`86.48.3.75`) | `172.30.99.1/30` | listens on UDP 51820                                     |
| homelab (`homelab-root`)  | `172.30.99.2/30` | dials out, keepalive 25 -> no router port-forward needed |

`172.30.99.0/30` is deliberately outside `10.0.0.0/8` (homelab pod pool) and `10.96.0.0/12` (service CIDR).

## Prerequisite (hoster)

Allow inbound **UDP 51820** to `86.48.3.75` at the hoster firewall. Verified: Talos has no nftables
firewall, and homelab sends a handshake every 5 s that never gets an answer until the port is open.

## homelab (this module, systemd-networkd)

```bash
cd infra/terraform/homelab-wireguard
tofu init && tofu apply     # pushes /etc/systemd/network/40-wg0.{netdev,network}, key stays on the host
ssh homelab-root 'wg show wg0 public-key'   # needed for the Talos peer
```

Rollback: `tofu destroy` (deletes `wg0`, both unit files and the host key; verified to restore the
original file set). Uses `networkctl reload` only; never restarts systemd-networkd.
State is local (gitignored). Destroy from the same checkout you applied from, or remove by hand:
`ssh homelab-root 'ip link del wg0; rm -f /etc/systemd/network/40-wg0.* /etc/systemd/network/wg0.key; networkctl reload'`.

Note: the homelab key is regenerated after a destroy, so update the Talos peer key afterwards.

## talos-flux (not managed here; `infra/talos/contabo` is untracked)

Generate a key (`wg genkey`) and apply a patch, keeping the private key out of git:

```yaml
machine:
  network:
    interfaces:
      - interface: wg0
        mtu: 1420
        addresses: [172.30.99.1/30]
        wireguard:
          privateKey: <talos private key>
          listenPort: 51820
          peers:
            - publicKey: <homelab public key>
              allowedIPs: [172.30.99.2/32]
```

Always `talosctl patch machineconfig --patch @file --dry-run` first (diff must only add `wg0`, leave
`eth0` untouched), then apply with `--mode=try --timeout 5m` (auto-reverts unless re-applied normally).
Rollback: re-apply without the `wg0` interface, or let a `try` apply expire.
Update `talos_public_key` in `variables.tf` to the public key of the key you generate.

## Cilium requirement (homelab)

homelab Cilium only serves NodePorts on its `devices`, so `wg0` must be listed:
`devices: [enp0s25, wg0]` in the Cilium helm values. Changing it restarts the agent; on 2026-09-30 that
also re-allocated the IPv6 router address (see `kubernetes/talos-flux/apps/homeassistant/README.md`,
"Incident note"). Rollback = set `devices` back to `enp0s25` and let the HelmRelease upgrade.

## Verify

`wg show wg0` on both ends shows a recent handshake; `ping 172.30.99.1` from homelab.
Then check whether homelab Cilium serves traffic arriving on `wg0` (its `devices` is `enp0s25`):
`curl -k --resolve hass.lab.lan:31952:172.30.99.2 https://hass.lab.lan:31952` from the Talos side.
