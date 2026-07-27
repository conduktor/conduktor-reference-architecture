
# Kafka ACLs for service accounts, applied through Console. On a Gateway-backed
# cluster Console writes them to the Gateway virtual cluster, so they govern
# clients connecting on any Gateway listener.
#
# ACLs only take effect for principals absent from GATEWAY_SUPER_USERS —
# superusers bypass authorization entirely.
resource "conduktor_console_service_account_v1" "sa" {
  for_each = var.service_accounts
  name     = each.key
  cluster  = each.value.cluster
  labels   = each.value.labels
  spec = {
    authorization = {
      kafka = {
        acls = [
          for acl in each.value.acls : {
            name         = acl.name
            type         = acl.type
            pattern_type = acl.pattern_type
            operations   = acl.operations
            permission   = acl.permission
          }
        ]
      }
    }
  }
}
