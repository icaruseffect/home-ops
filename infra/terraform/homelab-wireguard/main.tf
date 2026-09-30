terraform {
  required_version = ">= 1.6"
}

# Standalone root module (does not belong to ../main.tf). Manages a WireGuard
# link on the homelab Arch host (systemd-networkd) towards the talos-flux node.
# No providers: files are pushed with `ssh <host>` so ~/.ssh/config and the
# agent are honoured.
#
# Rollback: `tofu destroy` (removes wg0, the networkd files and the host key).

locals {
  netdev = templatefile("${path.module}/templates/40-wg0.netdev.tftpl", {
    talos_public_key = var.talos_public_key
    talos_endpoint   = var.talos_endpoint
    peer_allowed_ip  = var.peer_allowed_ip
    mtu              = var.mtu
    keepalive        = var.keepalive
  })
  network = templatefile("${path.module}/templates/40-wg0.network.tftpl", {
    address = var.address
  })
}

# Private key lives only on the host (never in state). Created once, removed on destroy.
resource "terraform_data" "key" {
  input = { host = var.host }

  provisioner "local-exec" {
    command = "${path.module}/scripts/key.sh create"
    environment = {
      WG_HOST = self.input.host
    }
  }

  provisioner "local-exec" {
    when    = destroy
    command = "${path.module}/scripts/key.sh remove"
    environment = {
      WG_HOST = self.input.host
    }
  }
}

resource "terraform_data" "wg0" {
  depends_on       = [terraform_data.key]
  triggers_replace = [local.netdev, local.network]
  input            = { host = var.host }

  provisioner "local-exec" {
    command = "${path.module}/scripts/link.sh apply"
    environment = {
      WG_HOST        = self.input.host
      WG_NETDEV_B64  = base64encode(local.netdev)
      WG_NETWORK_B64 = base64encode(local.network)
    }
  }

  provisioner "local-exec" {
    when    = destroy
    command = "${path.module}/scripts/link.sh remove"
    environment = {
      WG_HOST = self.input.host
    }
  }
}
