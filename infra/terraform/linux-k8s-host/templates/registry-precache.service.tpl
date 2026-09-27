[Unit]
Description=Re-pull images currently running in the cluster to refresh the Harbor registry-mirror cache
After=network-online.target kubelet.service
Wants=network-online.target

[Service]
Type=oneshot
Environment=KUBECONFIG=/etc/kubernetes/admin.conf
ExecStart=/usr/local/bin/registry-precache.sh
