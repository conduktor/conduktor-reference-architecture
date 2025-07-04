
output "users_list" {
  value = { for user in conduktor_console_user_v2.users : user.name => user }
}

output "group_list" {
  value = { for group in conduktor_console_group_v2.group : group.name => group }
}

output "group_users_map" {
  value = local.group_users_map
}