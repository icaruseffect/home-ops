variable "ssh_host" {
  description = "SSH hostname or IP of the target Linux Kubernetes node"
  type        = string
}

variable "ssh_user" {
  description = "SSH user with root access on the target node"
  type        = string
  default     = "root"
}

variable "ssh_port" {
  description = "SSH port on the target node"
  type        = number
  default     = 22
}

variable "harbor_host" {
  description = "Hostname of the Harbor instance that provides registry proxy-cache projects for this node"
  type        = string
}

variable "registry_mirrors" {
  description = <<-EOT
    Upstream registries to mirror through Harbor proxy-cache projects, via
    containerd's certs.d hosts.toml (/etc/containerd/certs.d/<key>/hosts.toml).
    `harbor_project` must already exist as a Proxy Cache project in Harbor
    pointing at the matching upstream - this module only configures the
    node side, it does not create Harbor projects.
  EOT
  type = map(object({
    upstream_server = string
    harbor_project  = string
  }))
  default = {}
}

variable "configure_kubelet_network_online_fix" {
  description = <<-EOT
    Add a systemd drop-in so kubelet.service waits for network-online.target
    before starting, instead of racing ahead of DHCP/link-up on boot. Only
    takes effect on the next kubelet restart/reboot - this does not restart
    kubelet itself.
  EOT
  type    = bool
  default = true
}

variable "configure_registry_precache" {
  description = <<-EOT
    Install a systemd timer that periodically re-pulls (via crictl, against
    the node's own containerd CRI socket) every image currently running in
    the cluster. Since containerd's certs.d mirrors (registry_mirrors above)
    already route the pull through the matching Harbor proxy-cache project,
    this needs no registry-to-Harbor mapping of its own - it just re-requests
    the original reference and lets containerd route it, which also
    revalidates floating tags (e.g. `:latest`) against upstream on a
    schedule instead of leaving them cached forever.
  EOT
  type    = bool
  default = true
}

variable "registry_precache_schedule" {
  description = "systemd OnCalendar expression for how often to re-pull currently-running images"
  type        = string
  default     = "*-*-* 0/6:00:00"
}
