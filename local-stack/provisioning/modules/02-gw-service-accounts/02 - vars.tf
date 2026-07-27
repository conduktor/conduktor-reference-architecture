
variable "service_accounts" {
  description = <<-EOT
    Gateway service accounts to create, keyed by service account name. The value
    is the set of external identities that resolve to it: the client certificate
    CN for mTLS clients, or the OIDC claim configured in
    GATEWAY_OAUTH_SUB_CLAIM_NAME for OAuth clients.
  EOT
  type        = map(set(string))
}
