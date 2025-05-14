terraform {
  required_providers {
    conduktor = {
      source  = "conduktor/conduktor"
      version = "0.4.1"
    }
  }
}

provider "conduktor" {
  alias          = "console"
  mode           = "console"
  base_url       = var.console_base_url
  admin_user     = var.console_admin_user
  admin_password = var.console_admin_password
  insecure       = true
}

provider "conduktor" {
  alias          = "gateway"
  mode           = "gateway"
  base_url       = var.gateway_base_url
  admin_user     = var.gateway_admin_user
  admin_password = var.gateway_admin_password
  insecure       = true
}

# Admin group should be imported as it already exists in Console
resource "conduktor_console_group_v2" "admin" {
  provider = conduktor.console
  name     = "admin"
  spec = {
    display_name = "admin"
    description  = "Built-in group with admin level access"
    external_groups = ["conduktor-admin"]
    members : ["admin@company.io"]
  }

  lifecycle {
    prevent_destroy = true
  }
}

resource "conduktor_console_group_v2" "project-a" {
  provider = conduktor.console
  name     = "project-a"
  spec = {
    display_name = "Project A"
    external_groups = ["project-a"]
  }
}

resource "conduktor_console_group_v2" "project-b" {
  provider = conduktor.console
  name     = "project-b"
  spec = {
    display_name = "Project B"
    external_groups = ["project-b"]
  }
}

resource "conduktor_gateway_service_account_v2" "console_sa" {
  provider = conduktor.gateway
  name     = "console-sa"
  vcluster = "passthrough"
  spec = {
    type = "LOCAL"
  }
}

resource "conduktor_gateway_token_v2" "console_sa_token" {
  provider         = conduktor.gateway
  vcluster         = conduktor_gateway_service_account_v2.console_sa.vcluster
  username         = conduktor_gateway_service_account_v2.console_sa.name
  lifetime_seconds = var.gateway_token_lifetime_seconds
}

resource "conduktor_console_kafka_cluster_v2" "gateway" {
  provider = conduktor.console
  name     = "gateway-cluster"
  labels = {
    "env" = "prod"
  }
  spec = {
    display_name      = "Gateway Cluster"
    bootstrap_servers = var.bootstrap_servers
    properties = {
      "sasl.jaas.config"  = "org.apache.kafka.common.security.plain.PlainLoginModule required username='console-sa' password='${conduktor_gateway_token_v2.console_sa_token.token}';"
      "security.protocol" = "SASL_SSL"
      "sasl.mechanism"    = "PLAIN"
    }
    kafka_flavor = {
      gateway = {
        url                          = "https://conduktor-gateway-external.conduktor.svc.cluster.local:8888"
        user                         = var.gateway_admin_user
        password                     = var.gateway_admin_password
        virtual_cluster              = "passthrough"
        # ignore_untrusted_certificate = true
      }
    }
    schema_registry = {
      confluent_like = {
        url                          = var.schema_registry_url
        ignore_untrusted_certificate = false
        security = {
          basic_auth = {
            username = var.schema_registry_user
            password = var.schema_registry_password
          }
        }
      }
    }
  }
}

resource "conduktor_console_kafka_cluster_v2" "kafka" {
  provider = conduktor.console
  name     = "kafka-cluster"
  labels = {
    "env" = "prod"
  }
  spec = {
    display_name      = "Kafka Cluster"
    bootstrap_servers = "kafka-controller-0.kafka-controller-headless.cdk-deps.svc.cluster.local:9092"
    properties = {
      "sasl.jaas.config"  = "org.apache.kafka.common.security.plain.PlainLoginModule required username='kafka-admin' password='kafka-admin-password';"
      "security.protocol" = "SASL_SSL"
      "sasl.mechanism"    = "PLAIN"
    }
    schema_registry = {
      confluent_like = {
        url                          = var.schema_registry_url
        ignore_untrusted_certificate = false
        security = {
          basic_auth = {
            username = var.schema_registry_user
            password = var.schema_registry_password
          }
        }
      }
    }
  }
}

resource "conduktor_gateway_interceptor_v2" "interceptor_data_quality_avro" {
  provider = conduktor.gateway
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
