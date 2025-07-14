# Local example with K3D

The goal of this example is to provide an examples of values/secrets needed to deploy Conduktor platform in a "production like" environment with all security constraints and high availability.

![Local example architecture](./.excalidraw.svg)

This local example will deploy a local kubernetes cluster using K3D and install components that mimic the production environment.
Components installed :

- Kubernetes components :
  - **Nginx ingress controller** for ingress management
  - **Cert-manager** to manage certificates with a self-signed CA issuer
  - Monitoring stack with **Prometheus operator** and **Grafana operator**
- Conduktor dependencies components :
  - 2 **Postgresql** database
    - Main database for Conduktor Console data
    - Optional SQL database for Conduktor Console SQL feature
  - **Kafka** cluster with 3 brokers
  - **Hashicorp Vault** to provide a KMS service
  - **Keycloak** OIDC server for SSO authentication
- Conduktor platform :
  - **Conduktor Console** in HA (2 instances) with Cortex sidecar
  - **Conduktor Gateway** in HA (2 instances)

## Prerequisites

- Docker
- [K3D](https://k3d.io/stable/#releases)
- Terraform
- [Yq](https://mikefarah.gitbook.io/yq) v4.x
- Conduktor License in `LICENSE` environment variable set.
- Kafka CLI commands (e.g. `brew install kafka`)

### Hardware requirements

- Minimum 4 CPUs available
- Minimum 10GB of RAM available
- Minimum 15GB of disk space available

## Create DNS entries

Add the following lines to your `/etc/hosts` file in order to resolve hostnames:

```properties
127.0.0.1 console.conduktor.localhost
127.0.0.1 oidc.localhost
127.0.0.1 gateway.conduktor.localhost brokermain.gateway.conduktor.localhost brokermain0.gateway.conduktor.localhost brokermain1.gateway.conduktor.localhost brokermain2.gateway.conduktor.localhost
```

k3d will pick up data from localhost (127.0.0.1) on ports 443 and 9092. The Ingresses we deploy will route to services based on these hostnames.

## Create cluster with base components

To create and start the local environment, run the following commands :

```bash
make start-local-stack
```

It will create a K3d cluster named k3d-conduktor-platform-p75 and install base components (Ingress controller, Cert-manager, Monitoring stack, Postgresql databases, Kafka cluster, Vault).
Kubectl context should be created. To use it, run

```bash
kubectl config use-context k3d-conduktor-platform-p75
```

## Deploy Conduktor platform

Then, to install Conduktor Console and Gateway, run the following commands :

```bash
make install-conduktor-platform
```

It will deploy [`console-secrets`](local-stack/console-secrets.yaml) and [`gateway-secrets`](local-stack/gateway-secrets.yaml) into `conduktor` namespace and
then install both Conduktor Console and Gateway latest helm charts using [`console-values`](local-stack/console-values.yaml) and [`gateway-values`](local-stack/console-values.yaml) files.

## Provision Conduktor platform using terraform

To provision the Conduktor platform using terraform, run the following commands :

```bash
make init-conduktor-platform
```

Provisioning create resources inside Conduktor Console and Gateway.

### Conduktor Console

You can then access Conduktor Console at [https://console.conduktor.localhost](https://console.conduktor.localhost) 

You can then login using the following credentials :

| Account Type   | Username                                     | Password   | Groups    |
|----------------|----------------------------------------------|------------|-----------|
| local          | admin@demo.dev                               | adminP4ss! | admin     |
| sso (keycloak) | conduktor-admin / conduktor-admin@company.io | conduktor  | admin     |
| sso (keycloak) | alice / alice@company.io                     | alice      | project-a |
| sso (keycloak) | bob / alice@company.io                       | bob        | project-b |

You will be able to create topics and otherwise interact with both Kafka Cluster and Conduktor Gateway.

The connection to Conduktor Gateway uses SASL PLAIN with a credential generated earlier in the previous step.

### Conduktor Gateway

You can reach the Conduktor Gateway Admin API at [https://gateway.conduktor.localhost](https://gateway.conduktor.localhost).

```bash
curl -k -u admin:adminP4ss! \
    'https://gateway.conduktor.localhost/gateway/v2/interceptor'
```

You can reach Kafka through Gateway using SASL OAuthbearer (see client.properties file). Here we assume `kafka-topics` is installed locally.

```bash
# Need to set truststore at the JVM level to authenticate with OIDC
export KAFKA_OPTS="-Djava.security.manager=allow \
-Djavax.net.ssl.trustStore=./truststore.jks \
-Djavax.net.ssl.trustStorePassword=conduktor \
-Djavax.net.ssl.trustStoreType=JKS"
```

```bash
kafka-topics --list \
    --bootstrap-server gateway.conduktor.localhost:9092 \
    --command-config client.properties
```

### Identity Provider

You can also manage OIDC keycloak server at [https://oidc.localhost](https://oidc.localhost) with the following credentials `admin` / `conduktor`.

### Grafana Dashboards

Port forward grafana to take a look at the dashboards.

```bash
kubectl port-forward svc/grafana-service -n monitoring 3000:3000
```

Go to [http://localhost:3000](http://localhost:3000) and log in with `admin` and `admin` for username, password to explore the dashboards that ship with the Conduktor helm charts.

Press `Ctrl+C` to kill the port forward.

## Destroy Conduktor platform local stack

To destroy the Conduktor platform, run the following command:

```bash
make stop-local-stack
```
