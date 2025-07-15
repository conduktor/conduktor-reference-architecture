
locals {
  users_map = { for user in var.users : user.email => user }
  group_map = { for group in var.groups : group.name => group }

  group_users_map = { for pair in flatten([
    for user in var.users : [
      for group in user.groups : {
        group  = group
        email = user.email
      }
    ]
  ]) : pair.group => pair.email... if pair.group != null }
}

resource "conduktor_console_user_v2" "users" {
  for_each = local.users_map
  name = each.value.email
  spec = {
    firstname = each.value.firstname
    lastname  = each.value.lastname
  }
}

resource "conduktor_console_group_v2" "group" {
  for_each = local.group_map
  name = each.key
  spec = {
    display_name = each.value.displayName
    description  = each.value.description
    members      = local.group_users_map[each.key]
    permissions = [
      for permission in each.value.permissions : {
        resource_type = permission.resource_type
        name          = permission.name
        cluster       = permission.cluster
        pattern_type  = permission.pattern_type
        permissions   = permission.permissions
      }
    ]
  }
  depends_on = [
    conduktor_console_user_v2.users
  ]
}

