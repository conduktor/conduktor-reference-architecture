
variable "service_accounts" {
  description = <<-EOT
    Kafka ACLs to attach to a service account, keyed by service account name.
    The account must already exist on the cluster; this only manages its ACLs.

    cluster  Console Kafka cluster the ACLs are written to. For a Gateway-backed
             cluster they land in the Gateway virtual cluster behind it.
    labels   Optional metadata shown in Console.
    acls     Kafka ACL entries. `operations` accepts the Kafka operation names
             (Read, Write, Describe, Create, Delete, Alter, All, ...) and
             `pattern_type` is LITERAL or PREFIXED.
  EOT
  type = map(object({
    cluster = string
    labels  = optional(map(string), {})
    acls = set(object({
      name         = string
      type         = string
      pattern_type = string
      operations   = set(string)
      permission   = optional(string, "Allow")
    }))
  }))

  validation {
    condition = alltrue([
      for sa in var.service_accounts : alltrue([
        for acl in sa.acls : contains(["LITERAL", "PREFIXED"], acl.pattern_type)
      ])
    ])
    error_message = "acls pattern_type must be LITERAL or PREFIXED."
  }
}
