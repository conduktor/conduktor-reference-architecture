locals {
  apps_map = {for app in var.applications : app.name => app}

  app_instances = flatten([
    for app in var.applications : [
      for inst in app.instances : {
        name           = inst.name
        application    = app.name
        cluster        = inst.cluster
        resourcePrefix = inst.resourcePrefix
      }
    ]
  ])
  app_instance_map = {for app_inst in local.app_instances : app_inst.name => app_inst}

  owner_apps_map = { for app in var.applications : app.owner => app }
}

resource "conduktor_console_topic_policy_v1" "generic-topic-policy" {
  name = "generic-topic-policy"
  spec = {
    policies = {
      "spec.configs.retention.ms" = {
        range = {
          optional = false
          max      = 604800000
          min      = 3600000
        }
      },
      "spec.configs" = {
        allowed_keys = {
          keys = [
            "retention.ms",
            "cleanup.policy"
          ]
        }
      }
    }
  }
}

resource "conduktor_console_resource_policy_v1" "generic-topic-resource-policy" {
  name = "generic-topic-resource-policy"
  spec = {
    target_kind = "Topic"
    description = "A policy to check some basic rule for a topic"
    rules = [
      {
        condition     = "metadata.name.matches(\"^[a-z0-9-.]+.(avro|json)$\")"
        error_message = "topic name should match ^(?<event>[a-z0-9-.]+).(avro|json)$"
      },
      {
        condition     = "metadata.labels[\"data-criticality\"] in [\"C0\", \"C1\", \"C2\"]"
        error_message = "data-criticality should be one of C0, C1, C2"
      }
    ]
  }
}

resource "conduktor_console_application_v1" "apps" {
  for_each = local.apps_map
  name     = each.key
  spec = {
    title       = each.value.title
    description = each.value.description
    owner       = each.value.owner
  }
}


resource "conduktor_console_application_instance_v1" "app-instances" {
  for_each    = local.app_instance_map
  name        = each.key
  application = conduktor_console_application_v1.apps[each.value.application].name
  spec = {
    cluster = each.value.cluster
    resources = [
      {
        type         = "TOPIC"
        name         = each.value.resourcePrefix
        pattern_type = "PREFIXED"
      },
      {
        type         = "SUBJECT"
        name         = each.value.resourcePrefix
        pattern_type = "PREFIXED"
      },
      {
        type         = "CONSUMER_GROUP"
        name         = each.value.resourcePrefix
        pattern_type = "PREFIXED"
      }
    ]
    topic_policy_ref = [
      conduktor_console_topic_policy_v1.generic-topic-policy.name
    ]
    policy_ref = [
      conduktor_console_resource_policy_v1.generic-topic-resource-policy.name
    ]
    application_managed_service_account = false
  }
}


