# Bootstrap

## generate manifest

```console
kustomize build kubernetes/talos-flux/bootstrap > kubernetes/talos-flux/flux/flux-manifests/gotk-components.yaml
```

## cilium

```console
kubectl kustomize --enable-helm kubernetes/talos-flux/bootstrap/cilium --helm-command=$(which helm) --helm-kube-version=1.30.3 | kubectl apply -n kube-system -f -
```

## metrics server

```console
kubectl kustomize --enable-helm kubernetes/talos-flux/bootstrap/metrics-server --helm-command=$(which helm) --helm-kube-version=1.30.3 | kubectl apply -n kube-system -f -
```
