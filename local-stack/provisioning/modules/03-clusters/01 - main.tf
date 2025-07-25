
locals {
  cluster_map = { for cluster in var.clusters : cluster.name => cluster }
}


resource "conduktor_console_kafka_cluster_v2" "clusters" {
  for_each = local.cluster_map
  name     = each.value.name
  labels = {
      "env" = "prod"
  }
  spec = {
    display_name      = each.value.displayName
    description       = each.value.description
    bootstrap_servers = each.value.kafka.bootstrapServers
    properties = {
      "sasl.jaas.config"  = "org.apache.kafka.common.security.plain.PlainLoginModule required username='${each.value.kafka.saslUsername}' password='${each.value.kafka.saslPassword}';"
      "security.protocol" = each.value.kafka.securityProtocol
      "sasl.mechanism"    = each.value.kafka.saslMechanism
    }

    schema_registry = each.value.schemaRegistry != null ? {
      confluent_like = {
        url                          = each.value.schemaRegistry.url
        ignore_untrusted_certificate = false
        security = {
          basic_auth = {
            username = each.value.schemaRegistry.username
            password = each.value.schemaRegistry.password
          }
        }
      }
    } : null

    kafka_flavor = each.value.gateway != null ? {
      gateway = {
        url                          = each.value.gateway.baseUrl
        user                         = each.value.gateway.adminUser
        password                     = each.value.gateway.adminPassword
        virtual_cluster              = "passthrough"
      }
    } : null
  }
}