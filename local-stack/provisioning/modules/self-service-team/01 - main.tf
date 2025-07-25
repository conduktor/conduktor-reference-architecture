locals {
  instance_permissions_map = {for perm in var.permissions : perm.name => perm}
  app_groups_map = {for group in var.groups : group.name => group}
  topics_map = {for topic in var.topics : format("%s_%s", topic.name, topic.cluster) => topic}
}

resource "conduktor_console_application_instance_permission_v1" "app-instance-permissions" {
  for_each = local.instance_permissions_map

  name         = each.key
  application  = each.value.application
  app_instance = each.value.application_instance
  spec = {
    resource = {
      type         = each.value.resource_type
      name         = each.value.resource_name
      pattern_type = each.value.resource_pattern_type
    }
    user_permission            = each.value.user_permission
    service_account_permission = "NONE"
    granted_to                 = each.value.granted_to
  }
}

resource "conduktor_console_application_group_v1" "groups" {
  for_each = local.app_groups_map

  name        = each.key
  application = each.value.application
  spec = {
    display_name = each.value.displayName
    description  = each.value.description
    permissions = [
      {
        app_instance  = each.value.application_instance
        resource_type = "TOPIC"
        pattern_type  = "LITERAL"
        name          = "*"
        permissions = ["topicViewConfig", "topicConsume"]
      },
      {
        app_instance  = each.value.application_instance
        resource_type = "CONSUMER_GROUP"
        pattern_type  = "LITERAL"
        name          = "*"
        permissions = ["consumerGroupCreate", "consumerGroupReset", "consumerGroupDelete", "consumerGroupView"]
      }
    ]
    members = each.value.members
  }
}


resource "conduktor_console_topic_v2" "topics" {
  for_each = local.topics_map

  name        = each.value.name
  cluster     = each.value.cluster
  labels      = each.value.labels
  description = "${each.key} topic"
  spec = {
    partitions         = each.value.partitions
    replication_factor = each.value.replication
    configs            = each.value.config
  }
}