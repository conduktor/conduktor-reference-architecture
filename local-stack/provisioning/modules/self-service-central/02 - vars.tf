variable "applications" {
  description = "List of self-service applications to create"
  type = list(object({
    name        = string
    title       = string
    description = string
    owner       = string
    instances = set(object({
      name           = string
      cluster        = string
      resourcePrefix = string
    }))
  }))
}