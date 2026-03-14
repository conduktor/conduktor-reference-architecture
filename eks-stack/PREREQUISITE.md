# EKS Stack Prerequisites — Step-by-Step Setup

This guide walks you through every AWS resource and local tool you need before deploying the Conduktor platform on EKS. It assumes you are starting from scratch with an AWS account.

> **Cost warning**: Running an EKS cluster with worker nodes, load balancers, and S3 storage will incur AWS charges. Tear everything down when you are done to avoid unexpected costs.

## Table of Contents

1. [Install Local Tools](#1-install-local-tools)
2. [Configure the AWS CLI](#2-configure-the-aws-cli)
3. [Create a VPC (or Use an Existing One)](#3-create-a-vpc-or-use-an-existing-one)
4. [Create an EKS Cluster](#4-create-an-eks-cluster)
5. [Connect kubectl to the Cluster](#5-connect-kubectl-to-the-cluster)
6. [Create an S3 Bucket for Monitoring](#6-create-an-s3-bucket-for-monitoring)
7. [Enable OIDC Provider on EKS (for IRSA)](#7-enable-oidc-provider-on-eks-for-irsa)
8. [Create the IAM Role for AWS Load Balancer Controller](#8-create-the-iam-role-for-aws-load-balancer-controller)
9. [Create the IAM Role for Cortex S3 Access](#9-create-the-iam-role-for-cortex-s3-access)
10. [Set Up Domain Names in AWS (Route 53)](#10-set-up-domain-names-in-aws-route-53)
11. [Request an ACM Certificate](#11-request-an-acm-certificate)
12. [Prepare DNS Records](#12-prepare-dns-records)
13. [Obtain a Conduktor License](#13-obtain-a-conduktor-license)
14. [Fill in config.env](#14-fill-in-configenv)
15. [Checklist](#15-checklist)

---

## 1. Install Local Tools

Install the following tools on your machine. The instructions below are for macOS with Homebrew — adjust for your OS.

```bash
# AWS CLI — interact with AWS services
brew install awscli

# kubectl — interact with Kubernetes clusters
brew install kubectl

# Helm — Kubernetes package manager
brew install helm

# Terraform — infrastructure as code for provisioning Conduktor resources
brew install terraform

# yq — YAML processor (used to inject license into secrets)
brew install yq

# envsubst — substitute environment variables in templates (part of gettext)
brew install gettext

# Java keytool and openssl — for generating JKS truststores
# keytool comes with any JDK installation
brew install openjdk openssl

# eksctl (optional but recommended) — simplifies EKS cluster creation
brew install eksctl
```

Verify everything is installed:

```bash
aws --version
kubectl version --client
helm version
terraform version
yq --version
envsubst --version
keytool -help 2>&1 | head -1
openssl version
```

---

## 2. Configure the AWS CLI

If you have never configured the AWS CLI before, run:

```bash
aws configure
```

It will prompt you for:

| Prompt | What to enter |
|---|---|
| AWS Access Key ID | Your IAM user access key (from the AWS Console under IAM > Users > Security credentials) |
| AWS Secret Access Key | The corresponding secret key |
| Default region name | The region where you want to deploy, e.g. `us-east-1` |
| Default output format | `json` |

Verify your identity:

```bash
aws sts get-caller-identity
```

You should see your AWS account ID and IAM user/role ARN. Note down your **Account ID** — you will need it in later steps.

> **Tip**: If your organization uses AWS SSO, configure a named profile instead:
> ```bash
> aws configure sso --profile conduktor
> export AWS_PROFILE=conduktor
> ```

---

## 3. Create a VPC (or Use an Existing One)

EKS requires a VPC with at least 2 subnets in different Availability Zones. If you already have a VPC, skip to retrieving its ID.

### Option A: Use eksctl (creates VPC automatically)

If you use `eksctl` in Step 4 to create the cluster, it will create a VPC for you automatically. Skip to Step 4.

### Option B: Create a VPC manually

```bash
# Create a VPC with a /16 CIDR block
aws ec2 create-vpc \
  --cidr-block 10.0.0.0/16 \
  --tag-specifications 'ResourceType=vpc,Tags=[{Key=Name,Value=conduktor-vpc}]'
```

Note the `VpcId` from the output (e.g. `vpc-0abc123def456`).

Enable DNS hostnames (required for EKS):

```bash
aws ec2 modify-vpc-attribute --vpc-id vpc-0abc123def456 --enable-dns-hostnames
```

Create subnets in at least 2 Availability Zones:

```bash
# Public subnet in AZ a
aws ec2 create-subnet \
  --vpc-id vpc-0abc123def456 \
  --cidr-block 10.0.1.0/24 \
  --availability-zone us-east-1a \
  --tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=conduktor-public-a},{Key=kubernetes.io/role/elb,Value=1}]'

# Public subnet in AZ b
aws ec2 create-subnet \
  --vpc-id vpc-0abc123def456 \
  --cidr-block 10.0.2.0/24 \
  --availability-zone us-east-1b \
  --tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=conduktor-public-b},{Key=kubernetes.io/role/elb,Value=1}]'
```

Create an Internet Gateway and attach it:

```bash
aws ec2 create-internet-gateway \
  --tag-specifications 'ResourceType=internet-gateway,Tags=[{Key=Name,Value=conduktor-igw}]'

# Note the InternetGatewayId, then attach it
aws ec2 attach-internet-gateway \
  --internet-gateway-id igw-xxxxxxxxx \
  --vpc-id vpc-0abc123def456
```

Create a route table and add a route to the internet:

```bash
aws ec2 create-route-table --vpc-id vpc-0abc123def456
# Note the RouteTableId

aws ec2 create-route \
  --route-table-id rtb-xxxxxxxxx \
  --destination-cidr-block 0.0.0.0/0 \
  --gateway-id igw-xxxxxxxxx

# Associate both subnets with the route table
aws ec2 associate-route-table --route-table-id rtb-xxxxxxxxx --subnet-id subnet-aaaa
aws ec2 associate-route-table --route-table-id rtb-xxxxxxxxx --subnet-id subnet-bbbb
```

> **Important**: For the ALB to work, your subnets must be tagged:
> - Public subnets: `kubernetes.io/role/elb = 1`
> - Private subnets (if used): `kubernetes.io/role/internal-elb = 1`

### Retrieve your VPC ID

```bash
aws ec2 describe-vpcs --filters "Name=tag:Name,Values=conduktor-vpc" \
  --query "Vpcs[0].VpcId" --output text
```

Save this value — it goes into `VPC_ID` in `config.env`.

---

## 4. Create an EKS Cluster

### Option A: Using eksctl (recommended for beginners)

```bash
eksctl create cluster \
  --name conduktor-eks \
  --region us-east-1 \
  --version 1.31 \
  --nodegroup-name conduktor-workers \
  --node-type m5.xlarge \
  --nodes 3 \
  --nodes-min 2 \
  --nodes-max 5 \
  --managed
```

This creates the cluster, a managed node group, a VPC, subnets, and configures `kubectl` automatically. It takes about 15-20 minutes.

> **Node sizing**: `m5.xlarge` (4 vCPU, 16 GB RAM) is a reasonable starting point. The stack runs Kafka, 2x PostgreSQL, Vault, Prometheus, Grafana, Schema Registry, Keycloak, Console, and Gateway. For production, consider `m5.2xlarge` or larger.

### Option B: Using the AWS Console

1. Go to **EKS** in the AWS Console
2. Click **Create cluster**
3. Enter name: `conduktor-eks`
4. Select your VPC and subnets
5. Keep defaults for the rest and create
6. After the cluster is active, add a **Node Group**:
   - Instance type: `m5.xlarge`
   - Desired: 3, Min: 2, Max: 5

### Option C: Using the AWS CLI

```bash
# Create the cluster (requires an existing IAM role for EKS)
aws eks create-cluster \
  --name conduktor-eks \
  --region us-east-1 \
  --kubernetes-version 1.31 \
  --role-arn arn:aws:iam::ACCOUNT:role/eks-cluster-role \
  --resources-vpc-config subnetIds=subnet-aaaa,subnet-bbbb
```

After creating the cluster, add a managed node group from the Console or CLI.

---

## 5. Connect kubectl to the Cluster

Update your kubeconfig to point to the new cluster:

```bash
aws eks update-kubeconfig \
  --region us-east-1 \
  --name conduktor-eks
```

Verify the connection:

```bash
kubectl get nodes
```

You should see your worker nodes listed with status `Ready`.

Find your kube context (you will need this for `config.env`):

```bash
kubectl config current-context
```

This will output something like:

```
arn:aws:eks:us-east-1:123456789012:cluster/conduktor-eks
```

Save this value for `KUBE_CONTEXT` in `config.env`.

---

## 6. Create an S3 Bucket for Monitoring

Cortex (the monitoring component of Console) stores metrics data in S3.

```bash
aws s3 mb s3://conduktor-monitoring --region us-east-1
```

> **Naming**: S3 bucket names are globally unique. If `conduktor-monitoring` is taken, choose another name like `mycompany-conduktor-monitoring`.

Verify:

```bash
aws s3 ls | grep conduktor-monitoring
```

Save the bucket name for `S3_BUCKET_NAME` in `config.env`.

---

## 7. Enable OIDC Provider on EKS (for IRSA)

IRSA (IAM Roles for Service Accounts) lets Kubernetes pods assume IAM roles without static credentials. It requires an OIDC provider associated with your EKS cluster.

### What is IRSA?

Normally, to access AWS services (like S3) from inside a pod, you would need to store AWS access keys as Kubernetes secrets. IRSA eliminates this by letting you annotate a Kubernetes service account with an IAM role ARN. Pods using that service account automatically receive temporary AWS credentials.

### Enable the OIDC provider

```bash
# Check if already enabled
aws eks describe-cluster --name conduktor-eks \
  --query "cluster.identity.oidc.issuer" --output text
```

If it returns a URL like `https://oidc.eks.us-east-1.amazonaws.com/id/XXXX`, the OIDC issuer is configured. Now associate it with IAM:

```bash
eksctl utils associate-iam-oidc-provider \
  --region us-east-1 \
  --cluster conduktor-eks \
  --approve
```

If you are not using `eksctl`, you can do this manually via the AWS Console:

1. Go to **IAM > Identity providers > Add provider**
2. Choose **OpenID Connect**
3. Provider URL: paste the OIDC issuer URL from the command above
4. Audience: `sts.amazonaws.com`
5. Click **Add provider**

Retrieve the OIDC provider ID (needed for trust policies below):

```bash
OIDC_ID=$(aws eks describe-cluster --name conduktor-eks \
  --query "cluster.identity.oidc.issuer" --output text | sed 's|https://||')
echo $OIDC_ID
```

---

## 8. Create the IAM Role for AWS Load Balancer Controller

The AWS Load Balancer Controller runs inside EKS and creates ALBs/NLBs. It needs an IAM role with permissions to manage Elastic Load Balancing resources.

### Step 8a: Download the IAM policy

```bash
curl -o alb-ingress-policy.json \
  https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/v2.7.1/docs/install/iam_policy.json
```

### Step 8b: Create the IAM policy

```bash
aws iam create-policy \
  --policy-name AWSLoadBalancerControllerIAMPolicy \
  --policy-document file://alb-ingress-policy.json
```

Note the **Policy ARN** from the output.

### Step 8c: Create the IAM role with a trust policy for IRSA

Replace `ACCOUNT_ID` and `OIDC_ID` with your values:

```bash
ACCOUNT_ID=$(aws sts get-caller-identity --query "Account" --output text)

cat > alb-trust-policy.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::${ACCOUNT_ID}:oidc-provider/${OIDC_ID}"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "${OIDC_ID}:aud": "sts.amazonaws.com",
          "${OIDC_ID}:sub": "system:serviceaccount:kube-system:aws-load-balancer-controller"
        }
      }
    }
  ]
}
EOF

aws iam create-role \
  --role-name aws-load-balancer-controller \
  --assume-role-policy-document file://alb-trust-policy.json

aws iam attach-role-policy \
  --role-name aws-load-balancer-controller \
  --policy-arn arn:aws:iam::${ACCOUNT_ID}:policy/AWSLoadBalancerControllerIAMPolicy
```

### Step 8d: Get the role ARN

```bash
aws iam get-role --role-name aws-load-balancer-controller \
  --query "Role.Arn" --output text
```

Save this for `AWS_LB_CONTROLLER_IRSA_ROLE_ARN` in `config.env`.

Clean up the temporary files:

```bash
rm alb-ingress-policy.json alb-trust-policy.json
```

---

## 9. Create the IAM Role for Cortex S3 Access

Cortex (inside the Console pod) needs to read/write metrics to S3.

### Step 9a: Create the IAM policy

Replace `conduktor-monitoring` with your bucket name:

```bash
cat > cortex-s3-policy.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "s3:PutObject",
        "s3:GetObject",
        "s3:DeleteObject",
        "s3:ListBucket"
      ],
      "Resource": [
        "arn:aws:s3:::conduktor-monitoring",
        "arn:aws:s3:::conduktor-monitoring/*"
      ]
    }
  ]
}
EOF

aws iam create-policy \
  --policy-name ConduktorCortexS3Policy \
  --policy-document file://cortex-s3-policy.json
```

Note the **Policy ARN**.

### Step 9b: Create the IAM role with a trust policy for IRSA

The Console pod runs in the `conduktor` namespace with a service account created by the Helm chart (typically named `conduktor-console`):

```bash
ACCOUNT_ID=$(aws sts get-caller-identity --query "Account" --output text)

cat > cortex-trust-policy.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::${ACCOUNT_ID}:oidc-provider/${OIDC_ID}"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringLike": {
          "${OIDC_ID}:sub": "system:serviceaccount:conduktor:*"
        },
        "StringEquals": {
          "${OIDC_ID}:aud": "sts.amazonaws.com"
        }
      }
    }
  ]
}
EOF

aws iam create-role \
  --role-name conduktor-cortex-s3 \
  --assume-role-policy-document file://cortex-trust-policy.json

aws iam attach-role-policy \
  --role-name conduktor-cortex-s3 \
  --policy-arn arn:aws:iam::${ACCOUNT_ID}:policy/ConduktorCortexS3Policy
```

### Step 9c: Get the role ARN

```bash
aws iam get-role --role-name conduktor-cortex-s3 \
  --query "Role.Arn" --output text
```

Save this for `CORTEX_IRSA_ROLE_ARN` in `config.env`.

Clean up:

```bash
rm cortex-s3-policy.json cortex-trust-policy.json
```

---

## 10. Set Up Domain Names in AWS (Route 53)

Before requesting an ACM certificate, you need domain names that you control. This section explains how domains and DNS work on AWS, and walks you through setting up Route 53 as your DNS provider.

### What is DNS and why do you need it?

DNS (Domain Name System) translates human-readable names like `console.conduktor.example.com` into IP addresses that computers use. When you deploy the Conduktor stack, the load balancers get auto-generated AWS hostnames like `k8s-condukt-consolea-abc123-456789.us-east-1.elb.amazonaws.com`. DNS lets you map your clean domain names to those load balancer addresses.

### What is Route 53?

Route 53 is Amazon's DNS service. It lets you:
- **Register** new domain names (e.g. `example.com`)
- **Host** DNS records for domains you own (even if registered elsewhere)
- Create **ALIAS** records that point directly to AWS resources like ALBs (more efficient than CNAME)

### Choose your domain names

You need three domain names (they can be subdomains of one parent domain):

| Service | Example Domain | Purpose |
|---|---|---|
| Console | `console.conduktor.example.com` | Web UI for managing Kafka |
| Gateway | `gateway.conduktor.example.com` | Admin API + Kafka proxy |
| Keycloak | `oidc.example.com` | Identity provider for SSO |

You also need a wildcard for Gateway SNI routing: `*.gateway.conduktor.example.com`.

### Option A: Register a new domain in Route 53

If you do not own a domain yet, you can register one directly in AWS:

1. Go to **Route 53** in the AWS Console
2. Click **Registered domains** > **Register domains**
3. Search for a domain name and choose one (e.g. `conduktor-demo.com`)
4. Complete the registration (prices vary, `.com` domains cost ~$13/year)
5. AWS automatically creates a **hosted zone** for the domain

Verify the hosted zone was created:

```bash
aws route53 list-hosted-zones --query "HostedZones[*].[Id,Name]" --output table
```

### Option B: Use an existing domain registered elsewhere

If you already own a domain (e.g. from GoDaddy, Namecheap, Cloudflare), you can either:

**B1. Create a hosted zone in Route 53 and delegate to it:**

```bash
# Create a hosted zone for your domain
aws route53 create-hosted-zone \
  --name example.com \
  --caller-reference "conduktor-$(date +%s)"
```

This returns a set of NS (name server) records. Copy them:

```bash
aws route53 get-hosted-zone --id /hostedzone/Z1234567890 \
  --query "DelegationSet.NameServers" --output text
```

Then go to your domain registrar (GoDaddy, Namecheap, etc.) and replace the existing name servers with the Route 53 name servers. This tells the internet that Route 53 is now responsible for DNS for your domain.

> **Note**: Name server changes can take up to 48 hours to propagate globally, though it usually takes minutes to a few hours.

**B2. Use a subdomain hosted zone (if you do not want to move your entire domain):**

You can create a hosted zone just for a subdomain like `conduktor.example.com`:

```bash
aws route53 create-hosted-zone \
  --name conduktor.example.com \
  --caller-reference "conduktor-sub-$(date +%s)"
```

Then in your registrar's DNS settings, create NS records for `conduktor.example.com` pointing to the Route 53 name servers from the command above. This delegates only that subdomain to Route 53 while everything else stays with your current DNS provider.

**B3. Skip Route 53 entirely:**

You can manage DNS records directly in your existing DNS provider. After deployment, you will create CNAME records pointing your domains to the ALB/NLB hostnames. Skip the rest of this section and proceed to Step 11.

### Verify your hosted zone

Regardless of which option you chose, confirm that Route 53 has a hosted zone for your domain:

```bash
aws route53 list-hosted-zones --query "HostedZones[*].[Id,Name]" --output table
```

Note the **Hosted Zone ID** (e.g. `Z1234567890`) — you will need it when creating DNS records after deployment.

Test that DNS resolution works for your zone (the NS query should return Route 53 name servers):

```bash
dig NS example.com +short
```

If the name servers match the Route 53 ones, your domain is correctly delegated.

---

## 11. Request an ACM Certificate

The ALB uses an AWS Certificate Manager (ACM) certificate for HTTPS termination. You need a single certificate covering all three domains.

### Step 11a: Request the certificate

```bash
aws acm request-certificate \
  --domain-name console.conduktor.example.com \
  --subject-alternative-names gateway.conduktor.example.com oidc.example.com \
  --validation-method DNS \
  --region us-east-1
```

Note the **CertificateArn** from the output.

> **Important**: The certificate must be in the **same region** as your EKS cluster.

### Step 11b: Validate the certificate

ACM needs to verify that you own the domains. For DNS validation, it gives you CNAME records to create.

```bash
aws acm describe-certificate \
  --certificate-arn arn:aws:acm:us-east-1:123456789012:certificate/abcd-1234 \
  --query "Certificate.DomainValidationOptions"
```

For each domain, create a CNAME record in your DNS provider:

| Record Name | Record Value |
|---|---|
| `_xxxx.console.conduktor.example.com` | `_yyyy.acm-validations.aws.` |
| `_xxxx.gateway.conduktor.example.com` | `_yyyy.acm-validations.aws.` |
| `_xxxx.oidc.example.com` | `_yyyy.acm-validations.aws.` |

If you use Route 53 (set up in Step 10), you can automate this:

```bash
# The ACM console has a "Create record in Route 53" button that does this automatically
# Or use the CLI — first get the validation CNAME details, then create Route 53 records
```

Wait for the certificate status to become `ISSUED` (usually takes a few minutes):

```bash
aws acm describe-certificate \
  --certificate-arn arn:aws:acm:us-east-1:123456789012:certificate/abcd-1234 \
  --query "Certificate.Status" --output text
```

Save the certificate ARN for `ACM_CERTIFICATE_ARN` in `config.env`.

---

## 12. Prepare DNS Records

You will need DNS records for three domains. **These records will point to the load balancers created during deployment**, so you cannot fully set them up yet. However, you should decide on domain names now and ensure you have control over the DNS zone.

### Domains you need

| Domain | Purpose | Load Balancer Type |
|---|---|---|
| `console.conduktor.example.com` | Console web UI | ALB (HTTPS :443) |
| `gateway.conduktor.example.com` | Gateway admin API | ALB (HTTPS :443) |
| `*.gateway.conduktor.example.com` | Gateway Kafka broker SNI routing | NLB (TCP :9092) |
| `oidc.example.com` | Keycloak OIDC provider | ALB (HTTPS :443) |

### If using Route 53

After deployment, you will create ALIAS records pointing to the ALB and NLB DNS names. See the **Set up DNS** section in [README.md](./README.md).

### If using an external DNS provider

After deployment, you will create CNAME records pointing to the ALB and NLB DNS names.

---

## 13. Obtain a Conduktor License

You need a valid Conduktor license key. If you do not have one, request a trial at [conduktor.io](https://www.conduktor.io/).

Set it as an environment variable:

```bash
export LICENSE="your-license-key-here"
```

Or save it in a `.env` file inside the `eks-stack/` directory:

```bash
echo "LICENSE=your-license-key-here" > eks-stack/.env
```

---

## 14. Fill in config.env

Now that you have all the prerequisite resources, copy the config template and fill in every value:

```bash
cd eks-stack
cp config.env.example config.env
```

Edit `config.env`:

```bash
# Your AWS region
export AWS_REGION=us-east-1

# The EKS cluster name from Step 4
export EKS_CLUSTER_NAME=conduktor-eks

# The kubectl context from Step 5
export KUBE_CONTEXT="arn:aws:eks:us-east-1:123456789012:cluster/conduktor-eks"

# Your chosen domain names
export CONSOLE_DOMAIN=console.conduktor.example.com
export GATEWAY_DOMAIN=gateway.conduktor.example.com
export OIDC_DOMAIN=oidc.example.com

# The ACM certificate ARN from Step 11
export ACM_CERTIFICATE_ARN=arn:aws:acm:us-east-1:123456789012:certificate/abcd-1234

# The S3 bucket name from Step 6
export S3_BUCKET_NAME=conduktor-monitoring
export S3_REGION=${AWS_REGION}

# The Cortex IRSA role ARN from Step 9
export CORTEX_IRSA_ROLE_ARN=arn:aws:iam::123456789012:role/conduktor-cortex-s3

# The VPC ID from Step 3
export VPC_ID=vpc-0abc123def456

# The ALB controller IRSA role ARN from Step 8
export AWS_LB_CONTROLLER_IRSA_ROLE_ARN=arn:aws:iam::123456789012:role/aws-load-balancer-controller
```

Also update `provisioning/terraform.tfvars` to match your domain names:

```hcl
console_base_url  = "https://console.conduktor.example.com"
gateway_base_url  = "https://gateway.conduktor.example.com"
bootstrap_servers = "gateway.conduktor.example.com:9092"
```

---

## 15. Checklist

Verify everything before proceeding to deployment:

- [ ] **AWS CLI** configured and `aws sts get-caller-identity` works
- [ ] **kubectl** installed and `kubectl get nodes` returns your EKS worker nodes
- [ ] **helm**, **terraform**, **yq**, **envsubst**, **keytool**, **openssl** installed
- [ ] **EKS cluster** created and running with at least 3 worker nodes (`m5.xlarge` or bigger)
- [ ] **OIDC provider** associated with the EKS cluster (Step 7)
- [ ] **S3 bucket** created for monitoring data
- [ ] **IAM role for ALB controller** created with IRSA trust policy (Step 8)
- [ ] **IAM role for Cortex S3** created with IRSA trust policy (Step 9)
- [ ] **Domain names** configured in Route 53 (or external DNS provider) (Step 10)
- [ ] **ACM certificate** issued and status is `ISSUED` (Step 11)
- [ ] **DNS zone** ready — you have control over the domains you chose
- [ ] **Conduktor license** set as `LICENSE` env var or in `.env` file
- [ ] **config.env** filled in with all values
- [ ] **terraform.tfvars** updated with your domain names

Once everything is checked, proceed to deploy:

```bash
make start-eks-stack
make install-conduktor-platform
make init-conduktor-platform
```

See [README.md](./README.md) for full deployment instructions and tuning.
