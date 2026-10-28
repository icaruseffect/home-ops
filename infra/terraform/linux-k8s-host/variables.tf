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

variable "disable_leader_election" {
  description = <<-EOT
    Set --leader-elect=false on kube-scheduler and kube-controller-manager's
    static pod manifests. Only meaningful on a genuinely single-replica
    control plane: client-go's leader-election self-terminates the process
    on a lease-renewal timeout (by design, so an HA standby can take over),
    but with no second replica to fail over to, that's just "crash and
    restart" for zero HA benefit. On homelab this was firing every time an
    etcd/apiserver latency spike exceeded the ~5s per-call lease-renewal
    timeout - see incident notes 2026-09-29; restart counts were 1546
    (scheduler) / 1549 (controller-manager) before this fix.
  EOT
  type        = bool
  default     = true
}
