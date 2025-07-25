
variable "users" {
  type = list(object({
    email     = string
    firstname = string
    lastname  = string
    groups    = optional(set(string))
  }))
}

variable "groups" {
  type = list(object({
    name     = string
    displayName = string
    description  = string
    permissions = list(object({
      resource_type = string
      name          = optional(string)
      cluster       = optional(string)
      pattern_type  = optional(string)
      permissions   = list(string)
    }))
  }))
}
