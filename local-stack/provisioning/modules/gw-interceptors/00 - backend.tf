
terraform {
  required_version = ">= v1.10.4"
  required_providers {
    conduktor = {
      source                = "conduktor/conduktor"
      version               = ">= 0.5.0"
      configuration_aliases = [conduktor.gateway]
    }
  }
}

provider "conduktor" {
  alias = "gateway"
  mode  = "gateway"
}

