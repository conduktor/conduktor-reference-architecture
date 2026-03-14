terraform {
  required_providers {
    conduktor = {
      source  = "conduktor/conduktor"
      version = ">= 0.5.0"
    }
  }
}

provider "conduktor" {
  alias          = "console"
  mode           = "console"
  base_url       = var.console_base_url
  admin_user     = var.console_admin_user
  admin_password = var.console_admin_password
  insecure       = true
}

provider "conduktor" {
  alias          = "gateway"
  mode           = "gateway"
  base_url       = var.gateway_base_url
  admin_user     = var.gateway_admin_user
  admin_password = var.gateway_admin_password
  insecure       = true
}
