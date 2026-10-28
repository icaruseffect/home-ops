variable "host" {
  description = "SSH alias of the homelab Arch host (root)"
  type        = string
  default     = "homelab-root"
}

variable "talos_public_key" {
  description = "WireGuard public key of the talos-flux node (public, not a secret)"
  type        = string
  default     = "4emdvS6Nqb3nhfhXjYNTj+pcDoXykvVNSl/8bFP+Yio="
}

variable "talos_endpoint" {
  description = "talos-flux WireGuard endpoint (public IPv4:port). homelab dials out, so no router port-forward is needed."
  type        = string
  default     = "86.48.3.75:51820"
}

variable "address" {
  description = "Tunnel address of homelab. Must not overlap the 10.0.0.0/8 pod pool or the 10.96.0.0/12 service CIDR."
  type        = string
  default     = "172.30.99.2/30"
}

variable "peer_allowed_ip" {
  description = "Only the Talos tunnel address is accepted from / routed to the peer"
  type        = string
  default     = "172.30.99.1/32"
}

variable "mtu" {
  description = "Path MTU to talos is 1492 (measured); 1420 is the safe WireGuard default"
  type        = number
  default     = 1420
}

variable "keepalive" {
  description = "PersistentKeepalive seconds (keeps the NAT mapping open so talos can reach homelab)"
  type        = number
  default     = 25
}
