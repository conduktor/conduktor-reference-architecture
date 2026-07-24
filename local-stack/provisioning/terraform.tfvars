# This file contains sensitive credentials and would of course be excluded from
#   version control in a real-world scenario.
console_base_url       = "https://console.conduktor.localhost"
console_admin_user     = "admin@demo.dev"
console_admin_password = "adminP4ss!"

# Gateway admin API, as reached from OUTSIDE the cluster: terraform runs on the host, so it goes
# through the nginx ingress on 443 (gateway.conduktor.localhost is mapped to 127.0.0.1 in /etc/hosts).
gateway_external_base_url = "https://gateway.conduktor.localhost"

# Gateway admin API, as reached from INSIDE the cluster. This value is stored in Console's cluster
# configuration and resolved by Console, not by terraform, so it uses the internal service name and
# the admin-http port directly.
gateway_internal_base_url = "https://conduktor-gateway-internal.conduktor.svc.cluster.local:8888"

gateway_admin_user     = "admin"
gateway_admin_password = "adminP4ss!"

# Console reaches Kafka through the Gateway's internal listener, which uses port-based routing
bootstrap_servers = "conduktor-gateway-internal.conduktor.svc.cluster.local:9080"

gateway_token_lifetime_seconds = 2630000  # 1 month

schema_registry_url      = "https://schemaregistry.cdk-deps.svc.cluster.local:8081"
schema_registry_user     = "sc-user"
schema_registry_password = "sr-password"

# Path to the truststore *inside the Gateway container* - the Gateway uses it to reach Schema
# Registry. This is the cert-manager-generated truststore mounted by tls.certManager.truststore.
gateway_truststore_location = "/etc/gateway/tls/truststore.jks"
gateway_truststore_password = "conduktor"

kafka_password = "kafka-admin-password"
