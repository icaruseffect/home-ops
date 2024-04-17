terraform {
  required_version = "<= 1.8.0"
  required_providers {
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "4.30.0"
    }
    http = {
      source  = "hashicorp/http"
      version = "3.4.2"
    }
    sops = {
      source  = "carlpett/sops"
      version = "1.0.0"
    }
  }
}

module "cloudflare" {
  source = "./cloudflare"
}
