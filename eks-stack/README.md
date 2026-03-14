# Conduktor Platform on AWS EKS

Deploy the Conduktor platform (Console + Gateway) and all dependencies to an AWS EKS cluster.

This stack mirrors the `local-stack/` deployment but replaces local-only components:

- **AWS ALB** instead of Nginx Ingress (HTTPS for Console, Gateway admin, Keycloak)
- **AWS NLB** for Kafka TCP traffic (Gateway SNI routing on port 9092)
- **AWS S3** instead of MinIO for Cortex monitoring storage
- **IRSA** for S3 access (no static credentials)

All other components (Kafka, PostgreSQL, Keycloak, Vault, Schema Registry, Prometheus, Grafana) run self-hosted on EKS.

## Prerequisites

See [PREREQUISITE.md](./PREREQUISITE.md) for a detailed step-by-step setup guide. In summary, you need:

- An existing EKS cluster with `kubectl` access configured
- AWS CLI configured with appropriate permissions
- IAM roles created with IRSA trust policies for the AWS Load Balancer Controller and Cortex S3 access
- An ACM certificate (self-signed imported certificate works for testing)
- An S3 bucket for Cortex monitoring data
- Tools installed locally: `helm`, `kubectl`, `terraform`, `yq`, `envsubst`, `keytool`, `openssl`
- A valid Conduktor license key

## Quick Start

### 1. Configure

```bash
cd eks-stack
cp config.env.example config.env
```

Edit `config.env` with your AWS-specific values:

```bash
export AWS_REGION=us-east-1
export EKS_CLUSTER_NAME=conduktor-eks
export KUBE_CONTEXT="arn:aws:eks:us-east-1:123456789012:cluster/conduktor-eks"

export CONSOLE_DOMAIN=console.conduktor.test
export GATEWAY_DOMAIN=gateway.conduktor.test
export OIDC_DOMAIN=oidc.conduktor.test

export ACM_CERTIFICATE_ARN=arn:aws:acm:us-east-1:123456789012:certificate/abcd-1234
export S3_BUCKET_NAME=conduktor-monitoring
export S3_REGION=us-east-1
export CORTEX_IRSA_ROLE_ARN=arn:aws:iam::123456789012:role/conduktor-cortex-s3
export VPC_ID=vpc-0abc123def456
export AWS_LB_CONTROLLER_IRSA_ROLE_ARN=arn:aws:iam::123456789012:role/aws-load-balancer-controller
```

### 2. Set your license

```bash
export LICENSE="your-conduktor-license-key"
```

Or create a `.env` file:

```bash
echo "LICENSE=your-conduktor-license-key" > .env
```

### 3. Deploy infrastructure

```bash
make start-eks-stack
```

This installs cert-manager, trust-manager, AWS Load Balancer Controller, PostgreSQL (x2), Kafka, Vault, Prometheus, Grafana, Schema Registry, and Keycloak. It also creates ALB Ingress resources for Console, Gateway admin, and Keycloak.

### 4. Install Conduktor platform

```bash
make install-conduktor-platform
```

Deploys Conduktor Gateway and Console via Helm.

### 5. Provision platform resources

```bash
make init-conduktor-platform
```

Runs Terraform to create users, groups, clusters, interceptors, and self-service configurations.

### 6. Set up `/etc/hosts`

After deployment, map the local `.test` domains to the ALB/NLB IP addresses:

```bash
# Get the ALB hostname and resolve to IP
ALB_HOST=$(kubectl get ingress console-alb-ingress -n conduktor \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
ALB_IP=$(dig +short $ALB_HOST | head -1)

# Add entries for Console, Gateway admin, and Keycloak
sudo sh -c "echo '$ALB_IP  console.conduktor.test gateway.conduktor.test oidc.conduktor.test' >> /etc/hosts"

# Get the NLB hostname for Gateway Kafka proxy
NLB_HOST=$(kubectl get svc conduktor-gateway-external -n conduktor \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
NLB_IP=$(dig +short $NLB_HOST | head -1)

# Add SNI broker routing entry
sudo sh -c "echo '$NLB_IP  brokermain0.gateway.conduktor.test' >> /etc/hosts"
```

> **Using real domains?** If you own a domain, create DNS records instead: point `console.yourdomain.com`, `gateway.yourdomain.com`, `oidc.yourdomain.com` to the ALB address, and `*.gateway.yourdomain.com` to the NLB address.

### 7. Verify

- Console: `https://console.conduktor.test` (admin@demo.dev / adminP4ss!) — accept the self-signed certificate warning
- Gateway admin API: `https://gateway.conduktor.test`
- Kafka proxy: `gateway.conduktor.test:9092`
- Keycloak admin: `https://oidc.conduktor.test/admin` (admin / conduktor)

## Teardown

```bash
make stop-eks-stack
```

This uninstalls all Helm releases, removes Kubernetes manifests, ALB Ingress resources, and cleans Terraform state. The EKS cluster itself is not deleted.

## Tuning

### Resource Requests and Limits

Default values are set low for demo purposes. For production, increase resources in the relevant files:

**Console** (`console-values.yaml`):
```yaml
platform:
  resources:
    requests:
      cpu: 2000m
      memory: 4Gi
    limits:
      cpu: 4000m
      memory: 8Gi
platformCortex:
  resources:
    requests:
      cpu: 1000m
      memory: 2Gi
```

**Gateway** (`gateway-values.yaml`):
```yaml
gateway:
  replicas: 3       # increase from 2
  resources:
    requests:
      cpu: 2000m
      memory: 4Gi
    limits:
      cpu: 4000m
      memory: 8Gi
```

### Kafka

Edit `helm-values/kafka.yaml`:

```yaml
controller:
  replicaCount: 3              # default, increase for larger clusters
  persistence:
    size: 100Gi                # increase from 10Gi for production
  resources:
    requests:
      cpu: 1000m
      memory: 4Gi
```

### PostgreSQL

Edit `helm-values/postgresql-main.yaml` and `helm-values/postgresql-sql.yaml`:

```yaml
primary:
  persistence:
    size: 50Gi                  # increase from 10Gi
  resources:
    requests:
      cpu: 500m
      memory: 1Gi
```

### Cortex / S3 Storage

Cortex configuration is in `console-values.yaml` under `monitoringConfig.storage.s3`. The S3 bucket, region, and endpoint are set from `config.env`. To tune retention or other Cortex settings, add an override config:

```yaml
platformCortex:
  extraVolumes:
    - name: cortex-config-override
      configMap:
        name: conduktor-console-cortex-config
  extraVolumeMounts:
    - name: cortex-config-override
      subPath: cortex.yaml
      mountPath: /opt/override-configs/cortex.yaml
```

### Load Balancer Annotations

**ALB settings** are configured inline in `01-start.sh` where the Ingress resources are created. Common tuning options:

```yaml
# Enable WAF
alb.ingress.kubernetes.io/wafv2-acl-arn: "arn:aws:wafv2:..."
# Idle timeout
alb.ingress.kubernetes.io/load-balancer-attributes: idle_timeout.timeout_seconds=300
# Access logs
alb.ingress.kubernetes.io/load-balancer-attributes: access_logs.s3.enabled=true,access_logs.s3.bucket=my-logs
```

**NLB settings** for the Gateway Kafka proxy are in `gateway-values.yaml` under `service.external.annotations`:

```yaml
service:
  external:
    annotations:
      # Cross-zone load balancing
      service.beta.kubernetes.io/aws-load-balancer-attributes: load_balancing.cross_zone.enabled=true
      # Proxy protocol v2 (if needed)
      service.beta.kubernetes.io/aws-load-balancer-proxy-protocol: "*"
```

### TLS

The stack uses self-signed certificates internally via cert-manager. External TLS termination is handled by the ALB using your ACM certificate. To use your own internal CA instead of self-signed:

1. Replace the `selfsigned-issuer` and `local-ca-issuer` in `manifests/01-cert-manager-crds.yaml` with your CA issuer
2. Or use cert-manager's ACME issuer with Let's Encrypt for internal certificates

### Gateway SNI Routing

The Gateway uses host-based SNI routing for Kafka broker connections. Each broker gets a subdomain like `brokermain0.gateway.conduktor.test`. If using `/etc/hosts`, add an entry for each broker subdomain pointing to the NLB IP. If using real domains, ensure your DNS wildcard record (`*.gateway.yourdomain.com`) points to the NLB.

To change the SNI separator or port, edit `gateway-values.yaml`:

```yaml
gateway:
  env:
    GATEWAY_SNI_HOST_SEPARATOR: "."
    GATEWAY_ADVERTISED_SNI_PORT: "9092"
```

### Keycloak

Demo users and realm configuration are in `manifests/02-keycloak.yaml`. To add users, modify the `realm.json` ConfigMap. To use an external identity provider instead, update the Console SSO config in `console-values.yaml` and the Gateway OIDC config in `gateway-values.yaml`.

## Architecture

```
                     Internet
                        │
            ┌───────────┼───────────┐
            │           │           │
         ┌──▼──┐    ┌──▼──┐    ┌──▼──┐
         │ ALB │    │ ALB │    │ NLB │
         │:443 │    │:443 │    │:9092│
         └──┬──┘    └──┬──┘    └──┬──┘
            │          │          │
    Console │  Keycloak│  Gateway │ (Kafka proxy)
            │          │          │
      ┌─────▼──┐  ┌───▼────┐ ┌──▼─────┐
      │Console │  │Keycloak│ │Gateway │
      │  +     │  │        │ │(x2)    │
      │Cortex  │  └───┬────┘ └──┬─────┘
      └──┬──┬──┘      │         │
         │  │    ┌─────▼─────────▼────┐
         │  │    │  Kafka (3 brokers) │
         │  │    └────────────────────┘
         │  │
    ┌────▼──▼────┐    ┌──────────┐
    │ PostgreSQL │    │  AWS S3  │
    │ (main+sql) │    │(Cortex)  │
    └────────────┘    └──────────┘
```

## File Reference

| File | Description |
|---|---|
| `config.env.example` | Configuration template — copy to `config.env` |
| `kubernetes_utils.sh` | Shared shell functions (config loading, waits, truststore generation) |
| `01-start.sh` | Deploy all infrastructure and dependencies |
| `02-install-conduktor-platform.sh` | Install Conduktor Console and Gateway |
| `03-init-conduktor-platform.sh` | Terraform provisioning (users, groups, clusters) |
| `04-stop.sh` | Complete teardown |
| `console-values.yaml` | Console Helm values (S3, IRSA, OIDC) |
| `console-secrets.yaml` | Console secrets (empty S3 creds for IRSA) |
| `gateway-values.yaml` | Gateway Helm values (NLB, SNI routing) |
| `gateway-secrets.yaml` | Gateway secrets |
| `helm-values/` | Helm values for all dependencies |
| `manifests/` | Kubernetes manifests (parameterized with envsubst) |
| `provisioning/` | Terraform config (symlinks to local-stack modules) |
