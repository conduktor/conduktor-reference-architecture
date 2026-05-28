
variable "clusters" {
  description = "List of clusters to create"
  type = list(object({
      name        = string
      displayName = string
      description = string
      kafka       = object({
        bootstrapServers = string
        securityProtocol = string
        saslMechanism    = string
        saslUsername     = string
        saslPassword     = string
        # Optional client keystore for mTLS to Kafka listeners that
        # require client auth (e.g. Gateway sslClientAuth: REQUIRE).
        sslKeystoreLocation = optional(string)
        sslKeystorePassword = optional(string)
      })
      schemaRegistry = optional(object({
        url      = string
        username = string
        password = string
      }))
      gateway = optional(object({
        baseUrl                = string
        adminUser             = string
        adminPassword         = string
      }))
  }))
}