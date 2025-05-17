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