
locals {
  vcluster = "passthrough"

  # Only LOCAL accounts get a Gateway-issued token; EXTERNAL ones already have a
  # credential from cert-manager or Keycloak.
  local_service_accounts = {
    for name, sa in var.service_accounts : name => sa if sa.type == "LOCAL"
  }
}

# LOCAL accounts authenticate with SASL/PLAIN using a token Gateway issues and
# signs with GATEWAY_USER_POOL_SECRET_KEY.
#
# EXTERNAL accounts have their credential issued elsewhere — a client
# certificate on the internal listener, an OIDC token on the external one.
# Gateway resolves the authenticated principal against `external_names` and
# maps it to the service account, which is what ACLs and GATEWAY_SUPER_USERS
# refer to.
resource "conduktor_gateway_service_account_v2" "sa" {
  for_each = var.service_accounts
  name     = each.key
  vcluster = local.vcluster
  spec = {
    type           = each.value.type
    external_names = each.value.type == "EXTERNAL" ? each.value.external_names : null
  }
}

resource "conduktor_gateway_token_v2" "sa_token" {
  for_each         = local.local_service_accounts
  vcluster         = local.vcluster
  username         = conduktor_gateway_service_account_v2.sa[each.key].name
  lifetime_seconds = var.token_lifetime_seconds
}
