## Architecture change suggestions
- should use consistent login credentials to cs playground
- host separator should be "-" like the default since this is what customers will do
- should use oathbearer for client -> gw since this is what customers will do
- should use gateway provider for kafkacluster if we are going to use console to connect to gateway at all
- should also include a kafkacluster that bypasses gateway

retrieve truststore for local kafka client
```
kubectl get secret bundle-truststore -n conduktor -o jsonpath='{.data.truststore\.jks}' | base64 --decode > truststore.jks
```

```
export KAFKA_OPTS="-Djava.security.manager=allow"
```

create client properties
```
security.protocol=SASL_SSL
sasl.mechanism=PLAIN
sasl.jaas.config=org.apache.kafka.common.security.plain.PlainLoginModule required username='console-sa' password='<token>';
ssl.truststore.location=./truststore.jks
ssl.truststore.password=conduktor
```

Run kafka client from outside world
```
kafka-broker-api-versions \
    --bootstrap-server gateway.conduktor.localhost:9092 \
    --command-config client.properties | grep 9092
```

Port forward grafana to take a look at the dashboards, or alternatively expose with ingress

```
kubectl port-forward svc/grafana-service -n monitoring 3000:3000
```
Log in with `admin` and `admin` for username, password.

## installation issues

- need kubectl 1.33+
- need helm repo update on `make install-conduktor-platform`
- timeouts not long enough

## console tls issues
```
Error: execution error at (console/templates/console/ingress.yaml:58:14): Ingress TLS enabled require one of : 
- ingress.selfSigned 
- ingress.secrets with existing TLS secret or one to create 
- ingress.annotations for cert-manager
```

I decided to disable TLS passthrough for Console since this is likely what customers will do

## terraform issues

```
make init-conduktor-platform
```

│ Error: Client Error
│ 
│   with conduktor_console_group_v2.admin,
│   on main.tf line 29, in resource "conduktor_console_group_v2" "admin":
│   29: resource "conduktor_console_group_v2" "admin" {
│ 
│ Unable to create group, got error: Invalid token.

I had to `unset CDK_API_KEY` since I had that variable set from a different demo.
Would be useful to tell the user to try this if they are having authentication issues since env vars supercede tfvars.

## Kafka issues

- k3d doesn't map 9092
- ingress doesn't have routing rule for 9092
- gateway advertised host is incorrect if you want to serve traffic from outside of kubernetes

Now all fixed in this branch.

## OAuthbearer issues

for some reason, I need to explicitly set truststore in kafka opts even though it's already in client.properties. Or else I get cert chain path error.
```
export KAFKA_OPTS="-Djava.security.manager=allow \
-Djavax.net.ssl.trustStore=./truststore.jks \
-Djavax.net.ssl.trustStorePassword=conduktor \
-Djavax.net.ssl.trustStoreType=JKS"
```

On Gateway, I also had to enable a bunch of truststores so GW would trust oidc provider. Not sure which were necessary or unnecessary.

Run kafka client.
```
kafka-broker-api-versions --bootstrap-server gateway.conduktor.localhost:9092 --command-config client.properties
```

Error:
```
Exception in thread "main" org.apache.kafka.common.errors.SaslAuthenticationException: {"status":"invalid_token"}
```

On the gw side:

```
k logs -f -n conduktor services/conduktor-gateway-external | grep -i sasl | grep -i oauth | jq
```

Error:

```
JWT processing failed. Additional details: [[17] Unexpected exception encountered while processing JOSE object (java.lang.NullPointerException: Cannot invoke \"java.util.Collection.iterator()\" because \"jsonWebKeys\" is null)
```

If I get a token myself with curl
```
curl -X POST https://oidc.localhost/realms/conduktor-realm/protocol/openid-connect/token \  -d "grant_type=client_credentials" \
  -d "client_id=app-1" \
  -d "client_secret=app-1-secret" \
  -d "scope=email" -k | jq
```

I get back a token that looks like this:

```json
{
  "exp": 1747476546,
  "iat": 1747476246,
  "jti": "trrtcc:f202323d-6ee0-4028-b581-53cb8a27ddd6",
  "iss": "https://oidc.localhost/realms/conduktor-realm",
  "aud": "account",
  "sub": "2e7bf75a-9e2f-4074-bdd9-15f0f242ef73",
  "typ": "Bearer",
  "azp": "app-1",
  "acr": "1",
  "realm_access": {
    "roles": [
      "offline_access",
      "default-roles-conduktor-realm",
      "uma_authorization",
      "blah"
    ]
  },
  "resource_access": {
    "account": {
      "roles": [
        "manage-account",
        "manage-account-links",
        "view-profile"
      ]
    }
  },
  "scope": "microprofile-jwt email groups profile",
  "upn": "service-account-app-1",
  "email_verified": false,
  "clientHost": "10.42.0.14",
  "groups": [
    "offline_access",
    "default-roles-conduktor-realm",
    "uma_authorization",
    "blah"
  ],
  "preferred_username": "service-account-app-1",
  "clientAddress": "10.42.0.14",
  "client_id": "app-1"
}
```

The claims all look good to me. Why is Jose giving me a null pointer exception?

Keycloak debug logs:

```
2025-05-17 16:19:34,226 DEBUG [org.keycloak.transaction.JtaTransactionWrapper] (executor-thread-1) JtaTransactionWrapper end. Request Context: HTTP POST /realms/conduktor-realm/protocol/openid-connect/token
2025-05-17 16:19:34,226 DEBUG [org.keycloak.events] (executor-thread-1) type="CLIENT_LOGIN", realmId="ce670a60-7052-4beb-af09-90582e3893bc", realmName="conduktor-realm", clientId="app-1", userId="6144464d-bc04-4231-99e7-bc0b700311b8", ipAddress="10.42.0.14", token_id="trrtcc:7efd5479-258c-4e44-8f02-69dfcda52bbc", grant_type="client_credentials", scope="email groups profile", client_auth_method="client-secret", username="service-account-app-1", authSessionParentId="66d2db47-0912-4722-a7ae-0707200264fb", authSessionTabId="Mh8sytBFanA"
```

Curl to oidc.localhost from within the gateway pod fails, but to `keycloak.cdk-deps.svc.cluster.local` succeeds. The CoreDNS rewrite is supposed to do this.

```
kubectl exec -it -n conduktor deploy/conduktor-gateway -- curl -k "https://keycloak.cdk-deps.svc.cluster.local/realms/conduktor-realm/protocol/openid-connect/certs"
```
Need the `-k`, so maybe Gateway truststore is the culprit?

Yep, needed to supply truststore at JVM level with JAVA_TOOL_OPTIONS.