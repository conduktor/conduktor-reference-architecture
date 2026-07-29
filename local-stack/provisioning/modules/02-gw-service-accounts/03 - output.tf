
output "service_accounts" {
  value = conduktor_gateway_service_account_v2.sa
}

output "tokens" {
  description = "SASL/PLAIN token per LOCAL service account, keyed by name"
  value       = { for name, tok in conduktor_gateway_token_v2.sa_token : name => tok.token }
  sensitive   = true
}
