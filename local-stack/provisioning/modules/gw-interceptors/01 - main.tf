
resource "conduktor_gateway_interceptor_v2" "interceptor_data_quality_avro" {
  name     = "interceptor_data_quality_avro"
  scope = {
    vcluster = "passthrough"
  }
  spec = {
    plugin_class = "io.conduktor.gateway.interceptor.safeguard.SchemaPayloadValidationPolicyPlugin"
    priority     = 100
    config = jsonencode({
      schemaRegistryConfig = {
        host = var.schema_registry_url
        additionalConfigs = {
          "basic.auth.credentials.source" = "USER_INFO"
          "basic.auth.user.info"          = "${var.schema_registry_user}:${var.schema_registry_password}"
          "schema.registry.ssl.truststore.location"       = var.gateway_truststore_location
          "schema.registry.ssl.truststore.type"           = "JKS"
          "schema.registry.ssl.truststore.password"       = var.gateway_truststore_password
        }
      }
      topic = "adult-customers-avro"
      schemaIdRequired = true
      validateSchema = true
      action = "BLOCK"
    })
  }
}
