terraform {
  required_version = "<= 1.9.5"
}

module "homelab" {
  source = "./linux-k8s-host"

  ssh_host    = "homelab.lan"
  harbor_host = "harbor.lab.lan"

  registry_mirrors = {
    "docker.io" = {
      upstream_server = "https://registry-1.docker.io"
      harbor_project  = "proxy-docker"
    }
    "ghcr.io" = {
      upstream_server = "https://ghcr.io"
      harbor_project  = "proxy-ghcr"
    }
    "quay.io" = {
      upstream_server = "https://quay.io"
      harbor_project  = "proxy-quay"
    }
    "registry.k8s.io" = {
      upstream_server = "https://registry.k8s.io"
      harbor_project  = "proxy-k8s"
    }
    "gcr.io" = {
      upstream_server = "https://gcr.io"
      harbor_project  = "proxy-gcr"
    }
    "eu.gcr.io" = {
      upstream_server = "https://eu.gcr.io"
      harbor_project  = "proxy-gcr"
    }
  }
}
