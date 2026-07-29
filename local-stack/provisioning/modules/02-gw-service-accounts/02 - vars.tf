
variable "service_accounts" {
  description = <<-EOT
    Gateway service accounts to create, keyed by service account name.

    type           LOCAL for accounts that authenticate with a Gateway-issued
                   SASL/PLAIN token, EXTERNAL for accounts whose credential is
                   issued outside Gateway.
    external_names EXTERNAL only: the identities that resolve to this account —
                   the client certificate CN for mTLS clients, or the claim
                   named by GATEWAY_OAUTH_SUB_CLAIM_NAME for OAuth clients.
  EOT
  type = map(object({
    type           = string
    external_names = optional(set(string))
  }))

  validation {
    condition     = alltrue([for sa in var.service_accounts : contains(["LOCAL", "EXTERNAL"], sa.type)])
    error_message = "service_accounts type must be LOCAL or EXTERNAL."
  }

  validation {
    condition = alltrue([
      for sa in var.service_accounts : try(length(sa.external_names), 0) > 0 if sa.type == "EXTERNAL"
    ])
    error_message = "EXTERNAL service accounts require at least one external_names entry."
  }
}

variable "token_lifetime_seconds" {
  description = "Lifetime of the tokens issued to LOCAL service accounts, in seconds"
  type        = number
}
