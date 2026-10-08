# Conduktor recommended architecture

This repository goal is to provide a **recommended architecture** for deploying Conduktor platform (Console and Gateway) in production ready environment that will match most of the needs.

## Start assumptions
- Target is Kubernetes using Helm (directly or through CD like FluxCD/ArgoCD)
- Kafka and Kubernetes are already setup and secured. 
  - Kubernetes components : Ingress controller / Load balancer / Storage class / Secret manager / cert-manager / ...
- Available object storage for Conduktor Console Cortex
- Available Postgres 13+ database for Conduktor Console
- Basic knowledge in networking/docker/kubernetes/certificates/kafka
- Need for maximum security
- Need for High Availability
- Sizing: see [sizing](./sizing.md)

## Out of scope 
How to deploy/configure :
- Kafka cluster
- Kubernetes clusters with its components (ingress controller / load balancer / storage class / secret manager / ...) for production
- Object storage
- Postgres server and databases


## General Recommended Architecture

Following diagram shows the general architecture of Conduktor platform and the required and optional components needed to deploy it in a production ready environment.
![Conduktor platform reference architecture](./architecture.svg)

### Recommended/target production environment

The primary deployment target for the Conduktor platform is **Kubernetes** using **Helm**. For a production environment, the following recommendations and requirements should be followed to ensure high availability, security, and performance.

#### High Availability

Gateway and Console don't fail the same way. Gateway sits on the data path: when it's down, every application behind it loses Kafka. When Console is down, users lose the UI and the API, but Kafka traffic keeps flowing. Plan Gateway availability like Kafka's, not like a web application's.

- **Gateway**: Run at least 3 instances and scale horizontally if needed. The chart prefers to place pods on different nodes but doesn't enforce it: set `topologySpreadConstraints` to spread them across availability zones. The chart doesn't create a PodDisruptionBudget, so add one with `extraDeploy` if your cluster drains nodes. Keep enough headroom to lose one instance at peak throughput. If you have librdkafka clients, set `GATEWAY_SHUTDOWN_DELAY_BETWEEN_BROKERS_MS` to `1000` or higher so rolling restarts don't crash them. See [Gateway on Kubernetes](https://docs.conduktor.io/guide/conduktor-in-production/deploy-artifacts/deploy-gateway/kubernetes).
- **Console**: Run at least 2 instances. Instances share the same PostgreSQL database and one of them is elected leader for indexing. Scale horizontally if needed.
- **Console Cortex**: `conduktor-console-cortex` only supports a single instance. Losing it leaves a gap in Console metrics and alerts; it doesn't affect Kafka traffic. If you already run Prometheus, Mimir or Cortex, Console 1.38+ can use it [instead of Console Cortex](https://docs.conduktor.io/guide/conduktor-in-production/deploy-artifacts/deploy-external-monitoring), which removes the only single-instance component.
- **Redundancy**: Ensure redundancy for critical components such as databases and storage.

#### Persistence

- **Storage**: 
  - Conduktor **Console** is stateless: its state lives in PostgreSQL. Ephemeral storage is enough, with at least 5 GB (10 GB recommended). See [system requirements](https://docs.conduktor.io/guide/conduktor-in-production/system-requirements).
  - Conduktor **Gateway** doesn't use local storage itself, but some interceptors do. [Large message handling](https://docs.conduktor.io/guide/use-cases/manage-large-messages#local-disk-cache) offloads payloads to S3 or Azure Blob and keeps a local disk cache with no size limit: mount a persistent volume sized for the expected payload volume. The caching interceptor also writes to local disk. Large batch handling was removed in Gateway 3.21.
  - Conduktor **Console Cortex** uses a local volume as a working area before offloading metric blocks to **object storage**. Without object storage, all metrics are lost when the container restarts. Use a `ReadWriteOnce` persistent volume with `updateStrategy: Recreate`, never `ReadWriteMany`. See [Cortex deployment](https://docs.conduktor.io/guide/conduktor-in-production/deploy-artifacts/deploy-cortex).
- **Database**: Use a managed PostgreSQL database with high availability and backups. For self-hosted databases, use a PostgreSQL cluster with replication and backups.
  - Size the Console database with the [PostgreSQL sizing guide](https://docs.conduktor.io/guide/conduktor-in-production/deploy-artifacts/deploy-console/postgres-sizing). 10 GB only fits a proof of concept; production starts at 50 GB and grows with users, Kafka clusters, topics and consumer groups.

#### Security

- **TLS/SSL**: All Conduktor components should be exposed securely using TLS. The Console should be accessible via `https`, and the Gateway should use `https` for the admin API and `SASL_SSL` for Kafka clients. Certificates can be managed by [**cert-manager**](https://cert-manager.io/docs/).
  - Terminate TLS on Console itself, not only on the ingress. Otherwise traffic between the ingress and Console is plain text, and SSO redirects built by Console can be rejected as insecure. See [Console on Kubernetes](https://docs.conduktor.io/guide/conduktor-in-production/deploy-artifacts/deploy-console/kubernetes).
- **Kubernetes Secrets**: Store all sensitive data (passwords, API tokens, access keys) using Kubernetes Secrets, ideally managed by a secret manager like Vault.
- **SSO**: Create a root account on the Console with a strong password and use Single Sign-On (SSO) for user management. This reference recommends **OIDC** with discovery over **LDAP**.
- **Kafka Authentication and Authorization**: Use `SASL_SSL` for Kafka authentication with mechanisms like `PLAIN`, `SCRAM-SHA-256`/`SCRAM-SHA-512`, `OAUTHBEARER`, `GSSAPI` (Kerberos) or `AWS_MSK_IAM`. For authorization, use ACLs with dedicated users for Conduktor Gateway and for Conduktor Console.
- **Conduktor Gateway Authentication and Authorization**: For extra layer of security use Gateway managed mode security with Gateway ACLs and service accounts. Give each Gateway [listener](https://docs.conduktor.io/guide/tutorials/multi-listener) a single authentication method, for example `SSL` with `sslClientAuth: REQUIRE` (mTLS) on an internal listener and `SASL_SSL` on an external one, rather than requiring clients to present both a certificate and a SASL credential on the same endpoint. All SASL listeners share the same set of SASL mechanisms: you can't restrict one listener to `OAUTHBEARER` only.
- **Gateway as the only path to Kafka**: Gateway ACLs and interceptors only apply to traffic that goes through Gateway. Restrict network access to the brokers and grant Kafka ACLs only to the Gateway and Console users, so applications can't connect to Kafka directly and skip the policies.
- **One security mode per Gateway**: `GATEWAY_SECURITY_MODE` applies to all listeners of a Gateway deployment. You can't mix `GATEWAY_MANAGED` and `KAFKA_MANAGED`; if you need both, deploy separate Gateways.
- **Gateway secrets**: Provide `GATEWAY_LICENSE_KEY` and `GATEWAY_USER_POOL_SECRET_KEY` (signs the credentials of local service accounts) from your secret manager. Replace the default admin API credentials (`admin`/`conduktor` in `GATEWAY_ADMIN_API_USERS`). See [Gateway environment variables](https://docs.conduktor.io/guide/conduktor-in-production/deploy-artifacts/deploy-gateway/environment-variables).
- **Pod/Container Security Context**: Run container with a non-root user, in non-privileged mode and use read-only filesystems where possible.

#### Monitoring and Logging

- **Prometheus and Grafana**: Use Prometheus for monitoring and Grafana for visualization. Use built-in dashboards for Conduktor components in Helm charts.
- **Alerting**: Set up alerting rules in Prometheus for critical Pods metrics (e.g., CPU, memory, disk usage, error rates). The Gateway Helm chart ships default `PrometheusRule` alerts (`metrics.alerts.enable`, off by default). The Console chart doesn't ship alerts yet.
- **Structured Logging**: Enable JSON structured logging for all components to enable easy parsing and analysis. See [Console](https://docs.conduktor.io/guide/conduktor-in-production/deploy-artifacts/deploy-console/sample-configuration#json-structured-logging) and [Gateway](https://docs.conduktor.io/guide/conduktor-in-production/deploy-artifacts/deploy-gateway/environment-variables#logging) documentation.
- **Log Management**: Implement centralized logging using tools like ELK stack (Elasticsearch, Logstash, Kibana) or Fluentd or Splunk.
- **Audit Logs**: Configure audit logs export to Kafka topics for all components to track user activity and changes. See [Console](https://docs.conduktor.io/guide/tutorials/configure-audit-log-topic) and [Gateway](https://docs.conduktor.io/guide/conduktor-in-production/deploy-artifacts/deploy-gateway/environment-variables#audit) documentation.

#### Backup and Recovery

- **Database Backups**: Back up the Console PostgreSQL database regularly and before an upgrade.
  - We recommend using managed PostgreSQL backups for production environments. Or automate backups using tools like `pg_dump` or `pg_basebackup`.
- **Gateway configuration**: Gateway stores its interceptors, service accounts, ACLs and virtual clusters in compacted internal topics (`_conduktor_<GATEWAY_CLUSTER_ID>_*`) on the Kafka cluster it proxies. They aren't backed up anywhere else. Keep the Terraform or CLI definitions in Git as the source of truth, so you can re-apply them to a new cluster.
- **Encryption keys**: If you use Gateway encryption, encrypted data stays readable only as long as its keys exist. Back up the KMS and never delete a key version that encrypted data you still keep. With the Gateway KMS (`gateway-kms://`), encrypted data keys are stored in `_conduktor_<GATEWAY_CLUSTER_ID>_encryption_keys`: losing that topic makes the data unreadable.
- **Storage Backups**: The Cortex object storage bucket only holds metrics history. Back it up if you need that history, for example before upgrading Console.

#### Upgrades

- **Version policy**: Conduktor [supports each release for one calendar year](https://docs.conduktor.io/guide/support/supported-version-policy) and recommends [upgrading no more than two versions at a time](https://docs.conduktor.io/guide/support/upgrade-guide).
- **Order**: Back up the Console database before upgrading Console. Upgrade Gateway with a rolling restart, one instance at a time.

#### Performance and Scalability

- **Resource Requests and Limits**: Define resource requests and limits for all components to ensure proper resource allocation and prevent resource contention. See [sizing](./sizing.md) for more details.
- **Database Sizing**: Size the Console PostgreSQL database based on the expected data volume and usage (numbers of users/groups, Kafka clusters, topics and consumer group). See [sizing](./sizing.md) for more details.

#### Networking

- **Ingress Controller**: Use an Ingress controller (e.g., NGINX) for HTTP traffic: the Console UI and API, and the Gateway admin API.
- **Load Balancer**: Kafka clients reach Gateway through a layer 4 (TCP) load balancer, not an HTTP ingress. With SNI routing, the load balancer must pass TLS through to Gateway, which reads the hostname during the TLS handshake. See [Gateway load balancing](https://docs.conduktor.io/guide/conduktor-in-production/deploy-artifacts/deploy-gateway/load-balancing).
- **Client IP**: Behind a load balancer, Gateway audit logs and errors show the load balancer IP. Enable the HAProxy protocol (`GATEWAY_FEATURE_FLAGS_HAPROXY_PROTOCOL`) or set `externalTrafficPolicy: Local` on a `LoadBalancer` Service to [keep the client IP](https://docs.conduktor.io/guide/conduktor-in-production/deploy-artifacts/deploy-gateway/load-balancing#capturing-the-client-ip-address).
- [**SNI Routing**](https://docs.conduktor.io/guide/tutorials/sni-routing#set-up-sni-routing): Use SNI routing for Gateway to route traffic based on the hostname.

#### Provisioning

- [**Terraform**](https://github.com/conduktor/terraform-provider-conduktor) and [**Conduktor CLI**](https://github.com/conduktor/ctl): Until Terraform provider is feature complete, use a mix of Terraform and Conduktor CLI to provision the platform.
- **Authentication**: Use [API keys](https://docs.conduktor.io/guide/conduktor-in-production/automate/terraform-automation) with the Terraform provider and Conduktor CLI: an application API key for self-service resources, scoped to its application instance, and an admin API key only for admin resources.

#### Dependencies

- **PostgreSQL**: Use PostgreSQL 13+ (14.8+ or 15.3+ on AWS RDS and Aurora) as the database for Conduktor Console with **TLS**, **HA** and backup in place.
- **Object Storage**: Use object storage for Conduktor Console Cortex: AWS S3 or S3-compatible (e.g., MinIO), GCS, Azure Blob Storage or Swift.
- **Kafka**: Use Kafka 2.7.0+ and ensure that it is configured and secured with the necessary authentication and authorization mechanisms. Create a dedicated user for Conduktor Gateway with the [ACLs it needs](https://docs.conduktor.io/guide/conduktor-in-production/deploy-artifacts/deploy-gateway/connect-to-kafka) on its internal topics, consumer group and the topics it proxies. Create another one for Conduktor Console with the [required Kafka permissions](https://docs.conduktor.io/guide/conduktor-in-production/admin/configure-clusters#required-kafka-permissions).
- **OIDC Provider**: Use an OIDC provider for Single Sign-On (SSO) with Conduktor Console.
- **KMS**: Use a Key Management Service (HashiCorp Vault, AWS KMS, Azure Key Vault, GCP KMS or Fortanix) for [Gateway encryption and decryption](https://docs.conduktor.io/guide/reference/data-security#kms-configuration) of Kafka messages. The in-memory KMS is for testing only.

### Examples
- [**Local Stack**](local-stack/README.md): Local stack for Conduktor platform with all components deployed in a K3D cluster.
