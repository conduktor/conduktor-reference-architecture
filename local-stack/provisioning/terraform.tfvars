# This file contains sensitive credentials and would of course be excluded from
#   version control in a real-world scenario.
console_base_url       = "https://console.conduktor.localhost"
console_admin_user     = "admin@demo.dev"
console_admin_password = "adminP4ss!"

gateway_base_url       = "https://gateway.conduktor.localhost"
gateway_admin_user     = "admin"
gateway_admin_password = "adminP4ss!"

bootstrap_servers = "gateway.conduktor.localhost:9092"

gateway_token_lifetime_seconds = 2630000  # 1 month

schema_registry_url      = "https://schemaregistry.cdk-deps.svc.cluster.local:8081"
schema_registry_user     = "sc-user"
schema_registry_password = "sr-password"

gateway_truststore_location = "/etc/conduktor/tls/truststore/truststore.jks"
gateway_truststore_password = "conduktor"

kafka_password = "kafka-admin-password"