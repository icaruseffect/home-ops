# see https://longhorn.io/docs/1.7.2/snapshots-and-backups/csi-snapshot-support/enable-csi-snapshot-support/
kubectl create -k ./external-snapshotter/client/config/crd
kubectl create -k external-snapshotter/deploy/kubernetes/snapshot-controller -n kube-system
