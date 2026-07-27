# Admin group should be imported as it already exists in Console
resource "conduktor_console_group_v2" "admin" {
  provider = conduktor.console
  name     = "admin"
  spec = {
    display_name = "admin"
    description  = "Built-in group with admin level access"
    external_groups = ["conduktor-admin"]
    # Adding external group for admin access for SSO admin user with external group mapping
    members : [var.console_admin_user]
  }

  lifecycle {
    prevent_destroy = true # Prevent accidental deletion of the admin group
  }
}

module "iam" {
  source = "./modules/01-iam"

  # input variables
  users = yamldecode(file("./data/users.yaml"))
  groups = yamldecode(file("./data/groups.yaml"))

  # provider configuration
  providers = {
    conduktor = conduktor.console
  }
}

module "gw-service-accounts" {
  source = "./modules/02-gw-service-accounts"

  # input variables
  service_accounts = {
    # Internal listener, mTLS: the external name is the client certificate CN.
    # Certificates are issued by cert-manager, see k3d-stack/02-infra-crds.yaml.
    "console-sa" = { type = "EXTERNAL", external_names = ["console-sa"] }
    "client-sa"  = { type = "EXTERNAL", external_names = ["client-sa"] }
    # External listener, SASL/OAUTHBEARER: the external name is the value of the
    # claim named by GATEWAY_OAUTH_SUB_CLAIM_NAME (azp = the Keycloak client id).
    "app-1" = { type = "EXTERNAL", external_names = ["app-1"] }
    # External listener, SASL/PLAIN: Gateway issues the token itself, so the app
    # needs no IdP client. Credentials land in client_plain.properties below.
    "app-2" = { type = "LOCAL" }
  }
  token_lifetime_seconds = var.gateway_token_lifetime_seconds

  # provider configuration
  providers = {
    conduktor = conduktor.gateway
  }
}

# Render a ready-to-use client config for the SASL/PLAIN service account. The
# token is generated at apply time, so this file cannot be committed — it is
# gitignored and removed by 04-stop.sh.
resource "local_sensitive_file" "client_plain_properties" {
  filename        = "${path.module}/../client_plain.properties"
  file_permission = "0600"
  content = templatefile("${path.module}/templates/client_plain.properties.tftpl", {
    username = "app-2"
    token    = module.gw-service-accounts.tokens["app-2"]
  })
}

module "clusters" {
  source = "./modules/03-clusters"

  # input variables
  clusters = [
    {
      name        = "gateway-cluster"
      displayName = "Gateway Cluster"
      description = "Conduktor Gateway Cluster"
      # Gateway internal listener is mTLS only: the client certificate is the
      # credential, and its CN (console-sa) is the authenticated principal.
      kafka = {
        bootstrapServers    = var.gateway_bootstrap_servers
        securityProtocol    = "SSL"
        sslKeystoreLocation = var.console_sa_keystore_location
        sslKeystorePassword = var.console_kafka_keystore_password
      }
      schemaRegistry = {
        url      = var.schema_registry_url
        username = var.schema_registry_user
        password = var.schema_registry_password
      }
      gateway = {
        baseUrl       = var.gateway_api_url
        adminUser     = var.gateway_admin_user
        adminPassword = var.gateway_admin_password
      }
    },
    {
      name        = "gateway-client-cluster"
      displayName = "Gateway Client Cluster"
      description = "Conduktor Gateway Cluster using client-sa service account"
      kafka = {
        bootstrapServers    = var.gateway_bootstrap_servers
        securityProtocol    = "SSL"
        sslKeystoreLocation = var.client_sa_keystore_location
        sslKeystorePassword = var.console_kafka_keystore_password
      }
      schemaRegistry = {
        url      = var.schema_registry_url
        username = var.schema_registry_user
        password = var.schema_registry_password
      }
      gateway = {
        baseUrl       = var.gateway_api_url
        adminUser     = var.gateway_admin_user
        adminPassword = var.gateway_admin_password
      }
    },
    {
      name        = "kafka-cluster"
      displayName = "Kafka Cluster"
      description = "Backend Kafka Cluster"
      kafka = {
        bootstrapServers = "kafka-controller-0.kafka-controller-headless.cdk-deps.svc.cluster.local:9092"
        saslUsername     = "kafka-admin"
        saslPassword     = var.kafka_password
        securityProtocol = "SASL_SSL"
        saslMechanism    = "PLAIN"
      }
      schemaRegistry = {
        url      = var.schema_registry_url
        username = var.schema_registry_user
        password = var.schema_registry_password
      }
    }
  ]

  # provider configuration
  providers = {
    conduktor = conduktor.console
  }
}

###
# ACLs for the SASL/PLAIN service account.
#
# app-2 is deliberately absent from GATEWAY_SUPER_USERS, so Gateway authorizes
# every request it makes against the ACLs below. It can work with the
# website-analytics topics and nothing else — `kafka-topics --list` will not
# even show sales.events.avro, because metadata is filtered by Describe.
#
# Keying off the Gateway service account name keeps the two in sync and orders
# the apply: the account exists before Console writes ACLs for it.
###
module "console-service-accounts" {
  source = "./modules/04-console-service-accounts"

  # input variables
  service_accounts = {
    (module.gw-service-accounts.service_accounts["app-2"].name) = {
      cluster = module.clusters.clusters["gateway-cluster"].name
      labels = {
        "team" = "website-analytics"
      }
      acls = [
        {
          name         = "website-analytics."
          type         = "TOPIC"
          pattern_type = "PREFIXED"
          operations   = ["Describe", "Read", "Write"]
        },
        {
          name         = "app-2."
          type         = "CONSUMER_GROUP"
          pattern_type = "PREFIXED"
          operations   = ["Describe", "Read"]
        }
      ]
    }
  }

  # provider configuration
  providers = {
    conduktor = conduktor.console
  }
}

module "interceptors" {
  source = "./modules/gw-interceptors"

  # input variables
  schema_registry_url         = var.schema_registry_url
  schema_registry_user        = var.schema_registry_user
  schema_registry_password    = var.schema_registry_password
  gateway_truststore_location = var.gateway_truststore_location
  gateway_truststore_password = var.gateway_truststore_password

  # provider configuration
  providers = {
    conduktor = conduktor.gateway
  }
}

module "self-service-central" {
  source = "./modules/self-service-central"

  # input variables
  applications = [
    {
      name        = "website-analytics"
      title       = "Website Analytics"
      description = "Application for streaming web analytics"
      owner       = module.iam.group_list["website-analytics-team"].name
      instances = [
        {
          name           = "website-analytics-dev"
          cluster        = module.clusters.clusters["gateway-client-cluster"].name
          resourcePrefix = "website-analytics."
        },
        {
          name           = "website-analytics-prod"
          cluster        = module.clusters.clusters["gateway-cluster"].name
          resourcePrefix = "website-analytics."
        }
      ]
    },
    {
      name        = "ecommerce-sales"
      title       = "E-commerce Sales"
      description = "Application for streaming e-commerce sales data"
      owner       = module.iam.group_list["ecommerce-team"].name
      instances = [
        {
          name           = "ecommerce-event-dev"
          cluster        = module.clusters.clusters["gateway-client-cluster"].name
          resourcePrefix = "sales."
        },
        {
          name           = "ecommerce-event-prod"
          cluster        = module.clusters.clusters["gateway-cluster"].name
          resourcePrefix = "sales."
        }
      ]
    }
  ]

  # provider configuration
  providers = {
    conduktor = conduktor.console
  }
}

###
# Self-Service Teams for Website Analytics and E-commerce
###
locals {
  web_analytics_team = module.iam.group_list["website-analytics-team"]
  web_analytics_applications = { for app in module.self-service-central.applications: app.name => app if app.spec.owner == local.web_analytics_team.name }
  web_analytics_applications_instances = { for inst in module.self-service-central.applications_instances: inst.name => inst if contains(keys(local.web_analytics_applications), inst.application ) }
}

module "self-service-team-website-analytics" {
  source = "./modules/self-service-team"

  # input variables
  owner                 = local.web_analytics_team.name
  applications          = local.web_analytics_applications
  application_instances = local.web_analytics_applications_instances
  permissions = []
  groups = [
    {
      name                 = "website-analytics-dev-support"
      displayName          = "Website Analytics Dev Support"
      description          = "Group for Support Team on Website Analytics Dev instance"
      application          = local.web_analytics_applications["website-analytics"].name
      application_instance = local.web_analytics_applications_instances["website-analytics-dev"].name
      members = [module.iam.users_list["alice@company.io"].name]
    }
  ]

  topics = [
    {
      name    = "website-analytics.dev.events.json"
      cluster = module.clusters.clusters["gateway-client-cluster"].name
      labels = {
        "data-criticality" = "C2"
        "environment"      = "dev"
        "team"             = "website-analytics"
      }
      partitions  = 3
      replication = 1
      config = {
        "retention.ms"   = "604800000"
        "cleanup.policy" = "delete"
      }
    },

    {
      name    = "website-analytics.events.json"
      cluster = module.clusters.clusters["gateway-cluster"].name
      labels = {
        "data-criticality" = "C0"
        "environment"      = "prod"
        "team"             = "website-analytics"
      }
      partitions  = 3
      replication = 1
      config = {
        "retention.ms"   = "604800000"
        "cleanup.policy" = "delete"
      }
    }
  ]


  # provider configuration
  providers = {
    conduktor = conduktor.console
  }
}

locals {
  ecommerce_team = module.iam.group_list["ecommerce-team"]
  ecommerce_applications = { for app in module.self-service-central.applications: app.name => app if app.spec.owner == local.ecommerce_team.name }
  ecommerce_applications_instances = { for inst in module.self-service-central.applications_instances: inst.name => inst if contains(keys(local.ecommerce_applications), inst.application ) }
}

module "self-service-team-ecommerce" {
  source = "./modules/self-service-team"

  # input variables
  owner                 = local.ecommerce_team.name
  applications          = local.ecommerce_applications
  application_instances = local.ecommerce_applications_instances

  permissions = [
    {
      name                  = "ecommerce-event-dev-permission"
      application           = local.ecommerce_applications["ecommerce-sales"].name
      application_instance  = local.ecommerce_applications_instances["ecommerce-event-dev"].name
      resource_type         = "TOPIC"
      resource_name         = "sales."
      resource_pattern_type = "PREFIXED"
      user_permission       = "READ"
      granted_to            = module.self-service-central.applications_instances["website-analytics-dev"].name
    }
  ]

  groups = [
    {
      name                 = "ecommerce-event-dev-support"
      displayName          = "E-commerce Event Dev Support"
      description          = "Group for Support Team on E-commerce Event dev instance"
      application          = local.ecommerce_applications["ecommerce-sales"].name
      application_instance = local.ecommerce_applications_instances["ecommerce-event-dev"].name
      members = [module.iam.users_list["alice@company.io"].name]
    }
  ]


  topics = [
    {
      name    = "sales.events.avro"
      cluster = module.clusters.clusters["gateway-cluster"].name
      labels = {
        "data-criticality" = "C0"
        "environment"      = "prod"
        "team"             = "sales"
      }
      partitions  = 3
      replication = 1
      config = {
        "retention.ms"   = "604800000"
        "cleanup.policy" = "delete"
      }
    }
  ]


  # provider configuration
  providers = {
    conduktor = conduktor.console
  }
}