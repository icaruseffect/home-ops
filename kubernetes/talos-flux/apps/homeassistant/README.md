# Home Assistant on `ha.${SECRET_DOMAIN}` (homelab -> talos-flux gateway)

Home Assistant runs on the homelab cluster. talos-flux's `cilium-gateway` proxies to it over the
WireGuard link (`infra/terraform/homelab-wireguard`), behind Authelia (`two_factor`).

```text
client -> cilium-gateway (talos-flux) -> Authelia ext-authz
       -> wg0 172.30.99.2:30804 (homelab cilium-ingress NodePort, Host: hass.lab.lan) -> home-assistant
```

Files here: `namespace.yaml`, `backend.yaml` (selectorless Service + EndpointSlice),
`certificate.yaml`, `referencegrants.yaml`, `httproute.yaml`. Apply with `${SECRET_DOMAIN}` substituted
(kustomize-controller is off): `SECRET_DOMAIN=klingel.cloud envsubst < file | kubectl apply -f -`.

## Live changes that are NOT in files you own (add them to your WIP files)

These were applied live with `kubectl patch` because their source files are uncommitted work in the
main checkout. Until they are added there, a re-apply of those files will drop them.

1. **Gateway listener** (`kubernetes/talos-flux/apps/kube-system/cilium/gateway/gateway.yaml`):

   ```yaml
   - name: https-ha.${SECRET_DOMAIN}
     hostname: ha.${SECRET_DOMAIN}
     protocol: HTTPS
     port: 443
     allowedRoutes:
       namespaces:
         from: All
     tls:
       mode: Terminate
       certificateRefs:
         - name: gw-ha.${SECRET_DOMAIN}-tls
   ```

2. **Authelia rule** (HelmRelease values `configMap.access_control.rules`):

   ```yaml
   - domain: ha.${SECRET_DOMAIN}
     policy: two_factor
   ```

3. **ClusterIssuer `letsencrypt-production`**: extra solver. The existing Ingress solver cannot work
   any more (no Cilium Ingress controller on this cluster), so **all `gw-*` certificates will fail to
   renew from 2026-11-15**. Only `ha.${SECRET_DOMAIN}` was given a working solver:

   ```yaml
   - selector:
       dnsNames: [ha.${SECRET_DOMAIN}]
     http01:
       gatewayHTTPRoute:
         parentRefs:
           - group: gateway.networking.k8s.io
             kind: Gateway
             name: cilium-gateway
             namespace: kube-system
             sectionName: http
   ```

   Recommended follow-up: switch the default solver to `gatewayHTTPRoute` for the whole zone.

4. **homelab Cilium** `devices: [enp0s25, wg0]` (`kubernetes/homelab/apps/kube-system/cilium/app/helm-values.yaml`).
   Needed so NodePorts answer on `wg0`.

## Behaviour / caveats

- Bypassed paths (no Authelia, Home Assistant's own auth; CrowdSec still enforced): `/api/webhook/*`,
  `/api/companion/*`, `/auth/token`, `/api/websocket`.
- Cilium honours only **one** `ExternalAuth` filter per rule, so on the gated `/` rule CrowdSec is
  **not** enforced for this host (Authelia is).
- The Companion app also loads `/` and `/auth/authorize` in a webview, which stay behind Authelia;
  expect the app's login flow to need a browser session or additional bypass paths.
- Optional: add `172.30.99.1/32` to Home Assistant's `http.trusted_proxies` so logs show real client IPs
  (needs an HA restart). No IP-ban threshold is configured, so the shared source IP cannot lock anyone out.
- The Service targets the ingress NodePort (`30804`); if `cilium-ingress` is recreated the port can change.

## Rollback (reverse order)

```bash
kubectl --context klingel.cloud delete -f kubernetes/talos-flux/apps/homeassistant/httproute.yaml   # stop serving
kubectl --context klingel.cloud -n kube-system patch gateway cilium-gateway --type=json \
  -p='[{"op":"remove","path":"/spec/listeners/<index of https-ha.*>"}]'
# Authelia: remove the ha.* rule from HelmRelease values; ClusterIssuer: remove the ha.* solver
kubectl --context klingel.cloud delete -f kubernetes/talos-flux/apps/homeassistant/   # rest
# homelab Cilium: set devices back to enp0s25 (agent restarts; see incident note below)
```

## Incident note (2026-09-30)

Adding `wg0` to homelab Cilium `devices` made the agent restart and fail to restore its IPv6 router
address (`fd70:cf5e:a47b:1::510` "owned by node-ip", because the host has no global IPv6), so it
allocated `::d049`. Pods created before then keep a dead IPv6 default gateway, and dual-stack backends
behind the LAN ingress time out about half the time. Restarted so far: home-assistant, zigbee2mqtt,
adguard-home. The other ingress backends (harbor, grafana, prometheus, alertmanager, karma, paperless,
frigate, localai, music-assistant, hubble-ui) and ~40 more pods still need a restart, or the
underlying cause fixed (give the host a global IPv6 address so cilium_host's IP is not the node IP).
