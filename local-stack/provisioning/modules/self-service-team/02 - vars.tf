variable "owner" {
    description = "Owner of the self-service team"
    type        = string
}

variable "applications" {
  description = "List of existing self-service applications"
  type = map(object({
    name        = string
    spec = object({
      title       = string
      description = string
      owner       = string
    })
  }))
}

variable "application_instances" {
    description = "List of existing application instances"
    type = map(object({
        name           = string
        application    = string
        spec = object({
         cluster        = string
        })
    }))
}

variable "permissions" {
    description = "List of permissions to create for application instances"
    type = list(object({
        name                  = string
        application           = string
        application_instance  = string
        resource_type         = string
        resource_name         = string
        resource_pattern_type = string
        user_permission       = string
        granted_to            = string
    }))
}

variable "groups" {
    description = "List of groups to create for self-service applications"
    type = list(object({
        name        = string
        application = string
        application_instance = string
        displayName = string
        description = string
        members     = optional(set(string))
    }))
}

variable "topics" {
  description = "List of topics to create for self-service applications"
  type = list(object({
    name        = string
    cluster     = string
    labels     = map(string)
    partitions  = number
    replication = number
    config = map(string)
  }))
}