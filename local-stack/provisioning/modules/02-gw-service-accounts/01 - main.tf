
locals {
  vcluster = "passthrough"
}

resource "conduktor_gateway_service_account_v2" "sa" {
  for_each = var.service_account_names
  name     = each.value
  vcluster = local.vcluster
  spec = {
    type = "LOCAL"
  }
}

resource "conduktor_gateway_token_v2" "sa_token" {
  for_each = conduktor_gateway_service_account_v2.sa
  vcluster         = each.value.vcluster
  username         = each.value.name
  lifetime_seconds = var.token_lifetime_seconds
}