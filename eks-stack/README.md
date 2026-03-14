# Conduktor Platform on AWS EKS

Deploy the Conduktor platform (Console + Gateway) and all dependencies to an AWS EKS cluster.

This stack mirrors the `local-stack/` deployment but replaces local-only components:

- **AWS ALB** instead of Nginx Ingress (HTTPS for Console, Gateway admin, Keycloak)
- **AWS NLB** for Kafka TCP traffic (Gateway SNI routing on port 9092)
- **AWS S3** instead of MinIO for Cortex monitoring storage
- **IRSA** for S3 access (no static credentials)

All other components (Kafka, PostgreSQL, Keycloak, Vault, Schema Registry, Prometheus, Grafana) run self-hosted on EKS.

## Prerequisites

- An existing EKS cluster with `kubectl` access configured
- AWS CLI configured with appropriate permissions
- The following IAM roles created with IRSA trust policies:
  - **AWS Load Balancer Controller role** — permissions to manage ALB/NLB resources
  - **Cortex S3 role** — `s3:PutObject`, `s3:GetObject`, `s3:ListBucket`, `s3:DeleteObject` on your monitoring bucket
- An ACM certificate covering your domains (`console.example.com`, `gateway.example.com`, `oidc.example.com`)
- An S3 bucket for Cortex monitoring data
- DNS records (Route 53 or external) pointing your domains to the ALB/NLB once created
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

export CONSOLE_DOMAIN=console.conduktor.example.com
export GATEWAY_DOMAIN=gateway.conduktor.example.com
export OIDC_DOMAIN=oidc.example.com

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

### 6. Set up DNS

After deployment, retrieve the ALB and NLB addresses:

```bash
# ALB address (for Console, Gateway admin, Keycloak)
kubectl get ingress -A

# NLB address (for Gateway Kafka proxy)
kubectl get svc conduktor-gateway-external -n conduktor
```

Create DNS records pointing:
- `console.conduktor.example.com` → ALB address
- `gateway.conduktor.example.com` → ALB address (HTTPS admin) AND NLB address (TCP port 9092)
- `oidc.example.com` → ALB address
- `*.gateway.conduktor.example.com` → NLB address (for SNI broker routing)

### 7. Verify

- Console: `https://console.conduktor.example.com` (admin@demo.dev / adminP4ss!)
- Gateway admin API: `https://gateway.conduktor.example.com`
- Kafka proxy: `gateway.conduktor.example.com:9092`
- Keycloak admin: `https://oidc.example.com/admin` (admin / conduktor)

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

The Gateway uses host-based SNI routing for Kafka broker connections. Each broker gets a subdomain like `brokermain0.gateway.conduktor.example.com`. Ensure your DNS wildcard record (`*.gateway.conduktor.example.com`) points to the NLB.

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
