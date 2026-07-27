
# SASL/PLAIN tokens for Gateway LOCAL service accounts. Already baked into
# client_plain.properties; exposed here so you can read or rotate them:
#   terraform output -json gateway_service_account_tokens
output "gateway_service_account_tokens" {
  description = "Gateway-issued SASL/PLAIN token per LOCAL service account"
  value       = module.gw-service-accounts.tokens
  sensitive   = true
}
