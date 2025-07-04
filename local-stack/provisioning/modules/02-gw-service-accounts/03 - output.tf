
output "service_accounts" {
  value = { for sa in conduktor_gateway_token_v2.sa_token : sa.username => sa }
}
