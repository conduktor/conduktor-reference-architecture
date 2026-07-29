
variable "clusters" {
  description = "List of clusters to create"
  type = list(object({
      name        = string
      displayName = string
      description = string
      kafka       = object({
        bootstrapServers = string
        securityProtocol = string
        # SASL credentials. Omit on listeners that authenticate with mTLS only
        # (e.g. the Gateway internal listener).
        saslMechanism    = optional(string)
        saslUsername     = optional(string)
        saslPassword     = optional(string)
        # Client keystore for listeners that require client auth
        # (sslClientAuth: REQUIRE). Omit when the listener uses one-way TLS.
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