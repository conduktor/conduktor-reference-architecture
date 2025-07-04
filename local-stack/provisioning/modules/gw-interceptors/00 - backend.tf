
terraform {
  required_version = ">= v1.10.4"
  required_providers {
    conduktor = {
      source                = "terraform.local/conduktor/conduktor"
      version               = "0.5.0-local2"
      configuration_aliases = [conduktor.gateway]
    }
  }
}

provider "conduktor" {
  alias = "gateway"
  mode  = "gateway"
}

