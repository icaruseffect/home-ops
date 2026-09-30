# Home Assistant on `ha.${SECRET_DOMAIN}` (homelab -> talos-flux gateway)

Home Assistant runs on the homelab cluster. talos-flux's `cilium-gateway` proxies to it over the
WireGuard link (`infra/terraform/homelab-wireguard`). CrowdSec enforces bans at the gateway; login is
Home Assistant's own, using Authelia as OpenID Connect provider.

```text
client -> cilium-gateway (talos-flux) -> CrowdSec ext_authz
       -> wg0 172.30.99.2:30804 (homelab cilium-ingress NodePort, Host: hass.lab.lan) -> home-assistant
```

Files here: `namespace.yaml`, `backend.yaml` (selectorless Service + EndpointSlice),
`certificate.yaml`, `referencegrants.yaml`, `httproute.yaml`. Apply with `${SECRET_DOMAIN}` substituted
(kustomize-controller is off): `SECRET_DOMAIN=klingel.cloud envsubst < file | kubectl apply -f -`.

## Design decisions

- Cilium honours only **one** `ExternalAuth` filter per rule (with two it disables the first). CrowdSec
  has priority, so the route carries only the CrowdSec filter. There is deliberately no Authelia
  forward-auth gate: the whole site, including the mobile app's paths, is reachable, and
  authentication is Home Assistant's login.
- Authelia OIDC client "Home Assistant" (values `configMap.identity_providers.oidc.clients`) has
  redirect URIs `https://hass.lab.lan/auth/openid/callback` and
  `https://ha.${SECRET_DOMAIN}/auth/openid/callback`. Its `authorization_policy` is `one_factor`;
  set it to `two_factor` to require 2FA for OIDC logins. Home Assistant's local password login stays
  available unless disabled in its auth providers.
- The route attaches only to the HTTPS listener (tokens must not travel in cleartext); `http://` gets 404.
- `172.30.99.1/32` (the gateway's tunnel address) is in Home Assistant's `http.trusted_proxies`
  (`/config/configuration.yaml` on the PVC, backup `configuration.yaml.bak-20260930-wg`; not managed by git).
- The Service targets the ingress NodePort (`30804`); if `cilium-ingress` is recreated the port can change.

## Live changes that are NOT in files you own (add them to your WIP files)

Applied with `kubectl patch` because their source files are uncommitted work in the main checkout.
Until added there, re-applying those files will drop them.

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

2. **Authelia** (HelmRelease values `configMap.identity_providers.oidc.clients[Home Assistant].redirect_uris`):
   add `https://ha.${SECRET_DOMAIN}/auth/openid/callback`. (A `two_factor` access-control rule for
   `ha.${SECRET_DOMAIN}` was also added earlier; it is unused now and can be removed.)

3. **ClusterIssuer `letsencrypt-production`**: the Ingress solver cannot work on this cluster (no
   Cilium Ingress controller), which would have broken all `gw-*` renewals from 2026-11-15. The
   `solvers` list was replaced with a single zone-wide Gateway solver (verified with a throwaway
   certificate):

   ```yaml
   solvers:
     - selector:
         dnsZones: [klingel.cloud]
       http01:
         gatewayHTTPRoute:
           parentRefs:
             - group: gateway.networking.k8s.io
               kind: Gateway
               name: cilium-gateway
               namespace: kube-system
               sectionName: http
   ```

   Previous solvers (rollback): the `ingress` solver with `ingressClassName: cilium` for zone `klingel.cloud`.

4. **homelab Cilium** `devices: [enp0s25, wg0]` (`kubernetes/homelab/apps/kube-system/cilium/app/helm-values.yaml`).
   Needed so NodePorts answer on `wg0`.

## Rollback (reverse order)

```bash
kubectl --context klingel.cloud delete -f kubernetes/talos-flux/apps/homeassistant/httproute.yaml   # stop serving
kubectl --context klingel.cloud -n kube-system patch gateway cilium-gateway --type=json \
  -p='[{"op":"remove","path":"/spec/listeners/<index of https-ha.*>"}]'
# Authelia: remove the ha.* redirect URI / rule from HelmRelease values; ClusterIssuer: restore ingress solver
kubectl --context klingel.cloud delete -f kubernetes/talos-flux/apps/homeassistant/   # rest
# homelab Cilium: set devices back to enp0s25 (agent restarts; see incident note below)
```

## Incident note (2026-09-30)

Adding `wg0` to homelab Cilium `devices` made the agent restart and fail to restore its IPv6 router
address (`fd70:cf5e:a47b:1::510` "owned by node-ip", because the host has no global IPv6), so it
allocated `::d049`. Pods created before then kept a dead IPv6 default gateway and dual-stack backends
behind the LAN ingress timed out about half the time. All 47 affected dual-stack pods were restarted
afterwards. Root cause remains: give the host a global IPv6 address so cilium_host's IP is not the
node IP, otherwise any future agent restart can repeat this.
