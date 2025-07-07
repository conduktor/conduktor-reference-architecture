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
  service_account_names = ["console-sa", "client-sa"]
  token_lifetime_seconds = var.gateway_token_lifetime_seconds

  # provider configuration
  providers = {
    conduktor = conduktor.gateway
  }
}

module "clusters" {
  source = "./modules/03-clusters"

  # input variables
  clusters = [
    {
      name        = "gateway-cluster"
      displayName = "Gateway Cluster"
      description = "Conduktor Gateway Cluster"
      kafka = {
        bootstrapServers = var.bootstrap_servers
        saslUsername     = module.gw-service-accounts.service_accounts["console-sa"].username
        saslPassword     = module.gw-service-accounts.service_accounts["console-sa"].token
        securityProtocol = "SASL_SSL"
        saslMechanism    = "PLAIN"
      }
      schemaRegistry = {
        url      = var.schema_registry_url
        username = var.schema_registry_user
        password = var.schema_registry_password
      }
      gateway = {
        baseUrl       = var.gateway_base_url
        adminUser     = var.gateway_admin_user
        adminPassword = var.gateway_admin_password
      }
    },
    {
      name        = "gateway-client-cluster"
      displayName = "Gateway Client Cluster"
      description = "Conduktor Gateway Cluster using client-sa service account"
      kafka = {
        bootstrapServers = var.bootstrap_servers
        saslUsername     = module.gw-service-accounts.service_accounts["client-sa"].username
        saslPassword     = module.gw-service-accounts.service_accounts["client-sa"].token
        securityProtocol = "SASL_SSL"
        saslMechanism    = "PLAIN"
      }
      schemaRegistry = {
        url      = var.schema_registry_url
        username = var.schema_registry_user
        password = var.schema_registry_password
      }
      gateway = {
        baseUrl       = var.gateway_base_url
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
        "data-criticality" = "C2",
        "environment"      = "dev"
        "team"             = "website-analytics"
      }
      partitions  = 3
      replication = 1
      config = {
        "retention.ms"   = "604800000",
        "cleanup.policy" = "delete"
      }
    },

    {
      name    = "website-analytics.events.json"
      cluster = module.clusters.clusters["gateway-cluster"].name
      labels = {
        "data-criticality" = "C0",
        "environment"      = "prod"
        "team"             = "website-analytics"
      }
      partitions  = 3
      replication = 1
      config = {
        "retention.ms"   = "604800000",
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
        "data-criticality" = "C0",
        "environment"      = "prod"
        "team"             = "sales"
      }
      partitions  = 3
      replication = 1
      config = {
        "retention.ms"   = "604800000",
        "cleanup.policy" = "delete"
      }
    }
  ]


  # provider configuration
  providers = {
    conduktor = conduktor.console
  }
}