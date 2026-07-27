# This file contains sensitive credentials and would of course be excluded from
#   version control in a real-world scenario.
console_base_url       = "https://console.conduktor.localhost"
console_admin_user     = "admin@demo.dev"
console_admin_password = "adminP4ss!"

gateway_base_url       = "https://gateway.conduktor.localhost"
gateway_admin_user     = "admin"
gateway_admin_password = "adminP4ss!"


gateway_bootstrap_servers = "conduktor-gateway-internal.conduktor.svc.cluster.local:9093"
gateway_api_url = "https://conduktor-gateway-internal.conduktor.svc.cluster.local:8888"

schema_registry_url      = "https://schemaregistry.cdk-deps.svc.cluster.local:8081"
schema_registry_user     = "sc-user"
schema_registry_password = "sr-password"

# Used by the gateway interceptor to talk to Schema Registry.
# SR is signed by kafka-stack-ca → use the kafka-stack-trust mount.
gateway_truststore_location = "/etc/conduktor/tls/kafka-trust/truststore.jks"
gateway_truststore_password = "conduktor"

kafka_password = "kafka-admin-password"

# Paths mounted by console-values.yaml extraVolumes (cert-manager
# console-sa-client-crt-secret / client-sa-client-crt-secret). The certificate
# CN is the principal Gateway authenticates on the mTLS internal listener.
console_sa_keystore_location    = "/opt/conduktor/ssl/client/console-sa/keystore.jks"
client_sa_keystore_location     = "/opt/conduktor/ssl/client/client-sa/keystore.jks"
console_kafka_keystore_password = "conduktor"