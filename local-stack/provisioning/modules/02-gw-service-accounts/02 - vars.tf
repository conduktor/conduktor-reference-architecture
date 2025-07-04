
variable "service_account_names" {
  description = "Names of the service accounts to create"
  type        = set(string)
}

variable "token_lifetime_seconds" {
  description = "Lifetime of the Gateway token in seconds"
  type        = number
}