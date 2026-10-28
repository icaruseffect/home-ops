#!/bin/sh
set -u

# Re-requests every image currently running in the cluster via crictl, which
# talks to containerd's CRI image service - the same layer kubelet itself
# pulls through, so it already honors /etc/containerd/certs.d/*/hosts.toml
# and gets routed via the Harbor proxy-cache projects with no mapping of
# our own. This also revalidates floating tags (":latest" etc.) against
# upstream, which is the only thing that keeps them from ever refreshing.
kubectl get pods --all-namespaces \
  --output='jsonpath={range .items[*]}{range .spec.initContainers[*]}{.image}{"\n"}{end}{range .spec.containers[*]}{.image}{"\n"}{end}{end}' \
  | sort -u \
  | while IFS= read -r img; do
      [ -z "$img" ] && continue
      echo "precaching: $img"
      crictl pull "$img" >/dev/null 2>&1 || echo "FAILED: $img"
    done
