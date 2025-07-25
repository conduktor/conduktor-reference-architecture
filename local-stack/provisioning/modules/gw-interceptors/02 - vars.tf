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
}

variable "gateway_truststore_password" {
  description = "Password for the Gateway truststore"
  type        = string
  sensitive   = true
}