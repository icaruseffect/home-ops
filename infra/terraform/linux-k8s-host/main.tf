locals {
  hosts_toml = {
    for name, cfg in var.registry_mirrors : name => templatefile("${path.module}/templates/hosts.toml.tpl", {
      upstream_server = cfg.upstream_server
      harbor_url      = "https://${var.harbor_host}/v2/${cfg.harbor_project}"
    })
  }

  kubelet_dropin = templatefile("${path.module}/templates/kubelet-network-online.conf.tpl", {})
}

# One containerd certs.d/<registry>/hosts.toml per entry in var.registry_mirrors,
# preferring the matching Harbor proxy-cache project and falling back to the
# real upstream registry. containerd reads these per-pull, no restart needed.
resource "terraform_data" "containerd_registry_mirror" {
  for_each = var.registry_mirrors

  triggers_replace = {
    content = local.hosts_toml[each.key]
  }

  connection {
    type  = "ssh"
    host  = var.ssh_host
    user  = var.ssh_user
    port  = var.ssh_port
    agent = true
  }

  provisioner "remote-exec" {
    inline = ["mkdir -p /etc/containerd/certs.d/${each.key}"]
  }

  provisioner "file" {
    content     = local.hosts_toml[each.key]
    destination = "/etc/containerd/certs.d/${each.key}/hosts.toml"
  }
}

# Makes kubelet.service wait for network-online.target instead of racing
# ahead of DHCP/link-up on boot (see incident 2026-09-27: enp0s25 had no
# carrier for ~90s at boot, kubelet started anyway and failed to reach its
# own API server with "network is unreachable"). Only takes effect on the
# next kubelet restart/reboot - daemon-reload does not restart the service.
resource "terraform_data" "kubelet_network_online_fix" {
  count = var.configure_kubelet_network_online_fix ? 1 : 0

  triggers_replace = {
    content = local.kubelet_dropin
  }

  connection {
    type  = "ssh"
    host  = var.ssh_host
    user  = var.ssh_user
    port  = var.ssh_port
    agent = true
  }

  provisioner "remote-exec" {
    inline = ["mkdir -p /etc/systemd/system/kubelet.service.d"]
  }

  provisioner "file" {
    content     = local.kubelet_dropin
    destination = "/etc/systemd/system/kubelet.service.d/10-network-online.conf"
  }

  provisioner "remote-exec" {
    inline = ["systemctl daemon-reload"]
  }
}
