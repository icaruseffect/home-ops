# Home Assistant on `ha.${SECRET_DOMAIN}` (homelab -> talos-flux gateway)

Home Assistant runs on the homelab cluster. talos-flux's `cilium-gateway` proxies to it over the
WireGuard link (`infra/terraform/homelab-wireguard`). CrowdSec enforces bans at the gateway; login is
Home Assistant's own, using Authelia as OpenID Connect provider.

```text
client -> cilium-gateway (talos-flux) -> CrowdSec ext_authz
       -> wg0 172.30.99.2:30804 (homelab cilium-ingress NodePort, Host: hass.lab.lan) -> home-assistant
```

Files here: `namespace.yaml`, `backend.yaml` (selectorless Service + EndpointSlice),
`referencegrants.yaml`, `httproute.yaml`. The listener and certificate live with the other gateway
hosts in `kubernetes/talos-flux/apps/kube-system/cilium/gateway/` (`gateway.yaml`, `certificates.yaml`).
Apply with `${SECRET_DOMAIN}` substituted (kustomize-controller is off):
`SECRET_DOMAIN=klingel.cloud envsubst < file | kubectl apply -f -`.

## Design decisions

- Cilium honours only **one** `ExternalAuth` filter per rule (with two it disables the first). CrowdSec
  has priority, so the route carries only the CrowdSec filter. There is deliberately no Authelia
  forward-auth gate: the whole site, including the mobile app's paths, is reachable, and
  authentication is Home Assistant's login.
- Authelia OIDC client "Home Assistant" (values `configMap.identity_providers.oidc.clients`) has
  redirect URIs `https://hass.lab.lan/auth/openid/callback` and
  `https://ha.${SECRET_DOMAIN}/auth/openid/callback`. Its `authorization_policy` is `two_factor`
  (both hosts).
- **Local password login is not blocked** (open item). It cannot be blocked at the HTTPRoute: the
  frontend starts every login with `POST /auth/login_flow` and picks the provider in the JSON body
  (`handler: ["homeassistant", null]` vs `["openid", null]`), and HTTPRoute matches only path, headers,
  query and method. The `openid` custom component (v1.3.0) can do it server-side: with
  `openid: block_login: true` in `/config/configuration.yaml` (currently `false`) it overrides
  `POST /auth/login_flow` and returns an empty form without a flow id, so no local flow can start.
  Keep `trusted_ips` **empty**: the component takes the leftmost `X-Forwarded-For` entry, which a client
  can set itself, so a LAN CIDR in `trusted_ips` could be spoofed from the internet. Consequence: no
  password login on the LAN either; break-glass is setting `block_login: false` via `kubectl exec` and
  restarting Home Assistant. Not applied yet; the mobile app's login through Authelia is untested.
- The route attaches only to the HTTPS listener (tokens must not travel in cleartext); `http://` gets 404.
- `172.30.99.1/32` (the gateway's tunnel address) is in Home Assistant's `http.trusted_proxies`
  (`/config/configuration.yaml` on the PVC, backup `configuration.yaml.bak-20260930-wg`; not managed by git).
- The Service targets the ingress NodePort (`30804`); if `cilium-ingress` is recreated the port can change.

## Live changes that are NOT in files you own (add them to your WIP files)

Applied with `kubectl patch` because their source files are uncommitted work in the main checkout.
Until added there, re-applying those files will drop them.

1. **Gateway listener** `https-ha.${SECRET_DOMAIN}` and **certificate** `gw-ha.${SECRET_DOMAIN}-tls`:
   now tracked in `gateway.yaml` / `certificates.yaml` (gateway dir), no longer live-only.

2. **Authelia** (HelmRelease values `configMap.identity_providers.oidc.clients[Home Assistant].redirect_uris`):
   add `https://ha.${SECRET_DOMAIN}/auth/openid/callback`. (A `two_factor` access-control rule for
   `ha.${SECRET_DOMAIN}` was also added earlier; it is unused now and can be removed.)

3. **ClusterIssuer `letsencrypt-production`**: the Ingress solver cannot work on this cluster (no
   Cilium Ingress controller), which would have broken all `gw-*` renewals from 2026-11-15. The
   `solvers` list is now a single zone-wide Gateway (`gatewayHTTPRoute`) solver, verified with a
   throwaway certificate. Tracked in `cert-manager/cert-manager/issuers/cluster-issuer-production.yaml`.
   The staging issuer still has the Ingress solver. Rollback: restore the `ingress` solver with
   `ingressClassName: cilium` for the zone.

4. **CrowdSec scenario** (`kubernetes/talos-flux/apps/crowdsec/values-crowdsec.yaml`, under `config:`,
   before `parsers:`). Home Assistant answers a failed login with HTTP 200, so hub scenarios miss it;
   this counts login-flow POSTs per source IP from the gateway access logs (verified: 8 POSTs -> ban
   for ~4h, enforced by the bouncer as 403; the test ban was removed):

   <!-- markdownlint-disable MD013 -->

   ```yaml
   scenarios:
     ha-login-bf.yaml: |
       type: leaky
       name: custom/ha-login-bf
       description: "Home Assistant login brute force (login_flow POSTs via the gateway)"
       filter: "evt.Meta.log_type == 'http_access-log' && evt.Parsed.verb == 'POST' && evt.Parsed.request startsWith '/auth/login_flow/' && evt.Meta.gateway_authority == 'hass.lab.lan'"
       groupby: evt.Meta.source_ip
       capacity: 5
       leakspeed: 30s
       blackhole: 1m
       labels:
         service: home-assistant
         type: bruteforce
         remediation: true
   ```

   <!-- markdownlint-enable MD013 -->

   Applied by regenerating the `crowdsec-values` ConfigMap; the chart creates `crowdsec-scenarios`
   and restarts only the agent. Rollback: remove the block and reapply. `evt.Meta.gateway_authority`
   is `hass.lab.lan` because the route rewrites the host. Lift an accidental ban with
   `cscli decisions delete --ip <ip>` in the `crowdsec-lapi` pod.

5. **homelab Cilium** `devices: [enp0s25, wg0]` (`kubernetes/homelab/apps/kube-system/cilium/app/helm-values.yaml`):
   now tracked in git. Needed so NodePorts answer on `wg0`.

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
