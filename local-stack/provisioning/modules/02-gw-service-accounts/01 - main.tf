
locals {
  vcluster = "passthrough"
}

# EXTERNAL service accounts: the credential lives outside Gateway — a client
# certificate on the internal listener, an OIDC token on the external one.
# Gateway resolves the authenticated principal against `external_names` and
# maps it to this service account, which is what ACLs and GATEWAY_SUPER_USERS
# refer to.
resource "conduktor_gateway_service_account_v2" "sa" {
  for_each = var.service_accounts
  name     = each.key
  vcluster = local.vcluster
  spec = {
    type           = "EXTERNAL"
    external_names = each.value
  }
}
