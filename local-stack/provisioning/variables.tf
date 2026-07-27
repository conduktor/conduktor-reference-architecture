
variable "console_base_url" {
  description = "Base URL for the Conduktor Console"
  type        = string
}

variable "console_admin_user" {
  description = "Admin user for the Conduktor Console"
  type        = string
}

variable "console_admin_password" {
  description = "Admin password for the Conduktor Console"
  type        = string
  sensitive   = true
}

variable "gateway_base_url" {
  description = "Base URL for the Conduktor Gateway"
  type        = string
}

variable "gateway_admin_user" {
  description = "Admin user for the Conduktor Gateway"
  type        = string
}

variable "gateway_admin_password" {
  description = "Admin password for the Conduktor Gateway"
  type        = string
  sensitive   = true
}

variable "gateway_bootstrap_servers" {
  description = "Gateway bootstrap servers"
  type        = string
}

variable "gateway_api_url" {
  description = "Gateway API URL"
  type        = string
}

variable "gateway_token_lifetime_seconds" {
  description = "Lifetime of the SASL/PLAIN tokens issued to Gateway LOCAL service accounts, in seconds"
  type        = number
}

variable "schema_registry_url" {
  description = "URL for the Schema Registry"
  type        = string
}

variable "schema_registry_user" {
  description = "Username for the Schema Registry"
  type        = string
}

variable "schema_registry_password" {
  description = "Password for the Schema Registry"
  type        = string
  sensitive   = true
}

variable "gateway_truststore_location" {
  description = "Location of the Gateway truststore"
  type        = string
  sensitive   = true
}

variable "gateway_truststore_password" {
  description = "Password for the Gateway truststore"
  type        = string
  sensitive   = true
}

variable "kafka_password" {
  description = "Password for the Kafka user"
  type        = string
  sensitive   = true
}

variable "console_sa_keystore_location" {
  description = "Path (inside Console pod) of the JKS keystore holding the console-sa client certificate, used for mTLS on the Gateway internal listener"
  type        = string
}

variable "client_sa_keystore_location" {
  description = "Path (inside Console pod) of the JKS keystore holding the client-sa client certificate, used for mTLS on the Gateway internal listener"
  type        = string
}

variable "console_kafka_keystore_password" {
  description = "Password of the Console Kafka client keystore"
  type        = string
  sensitive   = true
}