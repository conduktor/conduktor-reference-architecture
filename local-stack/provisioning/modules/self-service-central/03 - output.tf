
output "input_applications" {
  description = "Applications from input variable as a map"
  value = local.apps_map
}

output "per_owner_input_applications" {
  description = "Applications grouped by owner from input variable"
  value = { for app in var.applications : app.owner => app... }
}

output "applications" {
  description = "Applications created by the module"
  value = { for app in conduktor_console_application_v1.apps : app.name => app }
}

output "per_owner_applications" {
  description = "Applications grouped by owner created by the module"
  value = { for app in conduktor_console_application_v1.apps : app.spec.owner => app... }
}

output "applications_instances" {
  description = "Application instances created by the module"
  value = { for inst in conduktor_console_application_instance_v1.app-instances : inst.name => inst }
}

