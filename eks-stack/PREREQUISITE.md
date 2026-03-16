# EKS Stack Prerequisites — Step-by-Step Setup

This guide walks you through every AWS resource and local tool you need before deploying the Conduktor platform on EKS. It assumes you are starting from scratch with an AWS account.

> **Cost warning**: Running an EKS cluster with worker nodes, load balancers, and S3 storage will incur AWS charges. Tear everything down when you are done to avoid unexpected costs.

## Table of Contents

1. [Install Local Tools](#1-install-local-tools)
2. [Configure the AWS CLI](#2-configure-the-aws-cli)
3. [Create a VPC (or Use an Existing One)](#3-create-a-vpc-or-use-an-existing-one)
4. [Create an EKS Cluster](#4-create-an-eks-cluster)
5. [Connect kubectl to the Cluster](#5-connect-kubectl-to-the-cluster)
6. [Install the Amazon EBS CSI Driver](#6-install-the-amazon-ebs-csi-driver)
7. [Create an S3 Bucket for Monitoring](#7-create-an-s3-bucket-for-monitoring)
8. [Enable OIDC Provider on EKS (for IRSA)](#8-enable-oidc-provider-on-eks-for-irsa)
9. [Create the IAM Role for AWS Load Balancer Controller](#9-create-the-iam-role-for-aws-load-balancer-controller)
10. [Create the IAM Role for Cortex S3 Access](#10-create-the-iam-role-for-cortex-s3-access)
11. [Choose Domain Names](#11-choose-domain-names)
12. [Create an ACM Certificate (Self-Signed)](#12-create-an-acm-certificate-self-signed)
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

### Get the VPC ID

Regardless of which option you used above, retrieve the VPC ID associated with your EKS cluster:

```bash
aws eks describe-cluster --name conduktor-eks \
  --query "cluster.resourcesVpcConfig.vpcId" --output text
```

Save this value for `VPC_ID` in `config.env`. If you created the VPC manually in Step 3, this should match the VPC ID from that step. If you used `eksctl`, it created a new VPC automatically — use the ID returned here.

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

### (Optional) Enable Kubernetes resource view in the AWS Console

By default, the EKS console may not show pods, nodes, or other Kubernetes resources. To enable this, grant your IAM identity cluster admin access.

**If you use a regular IAM user:**

```bash
USER_ARN=$(aws sts get-caller-identity --query "Arn" --output text)

aws eks create-access-entry \
  --cluster-name conduktor-eks \
  --principal-arn "$USER_ARN"

aws eks associate-access-policy \
  --cluster-name conduktor-eks \
  --principal-arn "$USER_ARN" \
  --policy-arn arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy \
  --access-scope type=cluster
```

**If you use AWS SSO (federated login):**

The AWS Console uses your SSO role, not the assumed session. Find your SSO role ARN and grant it access:

```bash
# Find your SSO role ARN (replace the role name filter with your SSO role)
aws iam list-roles \
  --query "Roles[?contains(RoleName, 'AWSReservedSSO')].Arn" --output table

# Use the role ARN from the output above
SSO_ROLE_ARN="arn:aws:iam::ACCOUNT_ID:role/aws-reserved/sso.amazonaws.com/AWSReservedSSO_YourRoleName_xxxxxxxxxxxx"

aws eks create-access-entry \
  --cluster-name conduktor-eks \
  --principal-arn "$SSO_ROLE_ARN"

aws eks associate-access-policy \
  --cluster-name conduktor-eks \
  --principal-arn "$SSO_ROLE_ARN" \
  --policy-arn arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy \
  --access-scope type=cluster
```

After this, refresh the EKS console and you should see pods, nodes, and other resources under the **Resources** tab.

---

## 6. Install the Amazon EBS CSI Driver

EKS does not include a storage provisioner by default. The stack uses PersistentVolumeClaims for Kafka, PostgreSQL, and Vault, which require the **Amazon EBS CSI Driver** to dynamically provision EBS volumes. Without it, pods will fail to schedule with `unbound immediate PersistentVolumeClaims` errors.

### Step 6a: Create the IAM role for the EBS CSI driver

```bash
eksctl create iamserviceaccount \
  --name ebs-csi-controller-sa \
  --namespace kube-system \
  --cluster conduktor-eks \
  --role-name AmazonEKS_EBS_CSI_DriverRole \
  --role-only \
  --attach-policy-arn arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy \
  --approve
```

### Step 6b: Install the EBS CSI addon

```bash
ACCOUNT_ID=$(aws sts get-caller-identity --query "Account" --output text)

aws eks create-addon \
  --cluster-name conduktor-eks \
  --addon-name aws-ebs-csi-driver \
  --service-account-role-arn arn:aws:iam::${ACCOUNT_ID}:role/AmazonEKS_EBS_CSI_DriverRole
```

### Step 6c: Verify the addon is active

```bash
aws eks describe-addon \
  --cluster-name conduktor-eks \
  --addon-name aws-ebs-csi-driver \
  --query "addon.status" --output text
```

The status should be `ACTIVE`. It may take a minute or two to transition from `CREATING`.

> **Not using eksctl?** You can install the EBS CSI driver addon from the AWS Console under **EKS > Clusters > conduktor-eks > Add-ons > Get more add-ons**, then select **Amazon EBS CSI Driver** and assign the IAM role you created.

---

## 7. Create an S3 Bucket for Monitoring

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

## 8. Enable OIDC Provider on EKS (for IRSA)

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

## 9. Create the IAM Role for AWS Load Balancer Controller

The AWS Load Balancer Controller runs inside EKS and creates ALBs/NLBs. It needs an IAM role with permissions to manage Elastic Load Balancing resources.

### Step 9a: Download the IAM policy

```bash
curl -o alb-ingress-policy.json \
  https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/main/docs/install/iam_policy.json
```

### Step 9b: Create the IAM policy

```bash
aws iam create-policy \
  --policy-name AWSLoadBalancerControllerIAMPolicy \
  --policy-document file://alb-ingress-policy.json
```

Note the **Policy ARN** from the output.

### Step 9c: Create the IAM role with a trust policy for IRSA

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

### Step 9d: Get the role ARN

```bash
aws iam get-role --role-name aws-load-balancer-controller \
  --query "Role.Arn" --output text
```

Save this for `AWS_LB_CONTROLLER_IRSA_ROLE_ARN` in `config.env`.

> **Note**: Step 8 (OIDC provider) must be completed before this step, as the trust policy references the OIDC provider ID.

Clean up the temporary files:

```bash
rm alb-ingress-policy.json alb-trust-policy.json
```

---

## 10. Create the IAM Role for Cortex S3 Access

Cortex (inside the Console pod) needs to read/write metrics to S3.

### Step 10a: Create the IAM policy

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

### Step 10b: Create the IAM role with a trust policy for IRSA

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

### Step 10c: Get the role ARN

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

## 11. Choose Domain Names

The Conduktor stack needs three domain names for its externally accessible services. In this guide, we use local-only domains with `/etc/hosts` so you do not need to purchase a domain or set up Route 53.

> **Want to use a real domain instead?** If you own a domain (or want to buy a cheap one like `.click` for ~$3/year), you can register it in Route 53, use real ACM certificates, and set up proper DNS records. Replace the `.conduktor.test` domains below with your real domains and request a DNS-validated ACM certificate in Step 12 instead of a self-signed one.

### Domain names used in this guide

| Service | Domain | Purpose |
|---|---|---|
| Console | `console.conduktor.test` | Web UI for managing Kafka |
| Gateway | `gateway.conduktor.test` | Admin API + Kafka proxy |
| Keycloak | `oidc.conduktor.test` | Identity provider for SSO |

You also need `*.gateway.conduktor.test` for Gateway SNI broker routing (e.g. `brokermain0.gateway.conduktor.test`).

### How it works

These `.test` domains do not exist on the internet. After deployment, you will map them to the ALB's IP address in your `/etc/hosts` file so your machine resolves them locally. The ALB will use a self-signed certificate (created in Step 12) for HTTPS.

### Set up `/etc/hosts` (after deployment)

You cannot complete this step yet — the ALB does not exist until you run `make start-eks-stack`. Come back here after deployment:

```bash
# Get the ALB hostname
ALB_HOST=$(kubectl get ingress console-alb-ingress -n conduktor \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')

# Resolve it to an IP
ALB_IP=$(dig +short $ALB_HOST | head -1)
echo "ALB IP: $ALB_IP"

# Add entries to /etc/hosts
sudo sh -c "echo '$ALB_IP  console.conduktor.test gateway.conduktor.test oidc.conduktor.test' >> /etc/hosts"
```

For Kafka SNI routing, also add an entry for each Gateway broker:

```bash
# Get the NLB hostname (Gateway Kafka proxy)
NLB_HOST=$(kubectl get svc conduktor-gateway-external -n conduktor \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
NLB_IP=$(dig +short $NLB_HOST | head -1)

sudo sh -c "echo '$NLB_IP  brokermain0.gateway.conduktor.test' >> /etc/hosts"
```

> **Limitations of `/etc/hosts`**:
> - Only works on **your machine** — no one else can reach the domains
> - ALB/NLB IPs can **change over time** — you may need to update `/etc/hosts` if the load balancer is recreated
> - You will need to **accept the self-signed certificate warning** in your browser
> - Not suitable for production or shared environments

---

## 12. Create an ACM Certificate (Self-Signed)

The ALB requires an ACM (AWS Certificate Manager) certificate for HTTPS. Since we are using local `.test` domains, we will generate a self-signed certificate and import it into ACM. ACM does not validate imported certificates — it just stores them.

> **Using a real domain?** If you own a real domain, you can request a DNS-validated certificate instead:
> ```bash
> aws acm request-certificate \
>   --domain-name console.yourdomain.com \
>   --subject-alternative-names gateway.yourdomain.com oidc.yourdomain.com \
>   --validation-method DNS --region us-east-1
> ```
> Then create the DNS validation CNAME records in your DNS provider and wait for the status to become `ISSUED`. Skip the self-signed steps below.

### Step 12a: Generate a self-signed certificate

```bash
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout self-signed.key \
  -out self-signed.crt \
  -subj "/CN=*.conduktor.test" \
  -addext "subjectAltName=DNS:*.conduktor.test,DNS:console.conduktor.test,DNS:gateway.conduktor.test,DNS:oidc.conduktor.test"
```

### Step 12b: Import into ACM

```bash
aws acm import-certificate \
  --certificate fileb://self-signed.crt \
  --private-key fileb://self-signed.key \
  --region us-east-1
```

Note the **CertificateArn** from the output.

> **Important**: The certificate must be in the **same region** as your EKS cluster.

### Step 12c: Clean up the local key files

```bash
rm self-signed.key self-signed.crt
```

Save the certificate ARN for `ACM_CERTIFICATE_ARN` in `config.env`.

> **Note**: Imported certificates are not auto-renewed by ACM. If the certificate expires (after 365 days), regenerate and reimport it.

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

# Domain names (matching /etc/hosts from Step 11)
export CONSOLE_DOMAIN=console.conduktor.test
export GATEWAY_DOMAIN=gateway.conduktor.test
export OIDC_DOMAIN=oidc.conduktor.test

# The ACM certificate ARN from Step 12 (self-signed)
export ACM_CERTIFICATE_ARN=arn:aws:acm:us-east-1:123456789012:certificate/abcd-1234

# The S3 bucket name from Step 7
export S3_BUCKET_NAME=conduktor-monitoring
export S3_REGION=${AWS_REGION}

# The Cortex IRSA role ARN from Step 10
export CORTEX_IRSA_ROLE_ARN=arn:aws:iam::123456789012:role/conduktor-cortex-s3

# The VPC ID from Step 4
export VPC_ID=vpc-0abc123def456

# The ALB controller IRSA role ARN from Step 9
export AWS_LB_CONTROLLER_IRSA_ROLE_ARN=arn:aws:iam::123456789012:role/aws-load-balancer-controller
```

Also update `provisioning/terraform.tfvars` to match your domain names:

```hcl
console_base_url  = "https://console.conduktor.test"
gateway_base_url  = "https://gateway.conduktor.test"
bootstrap_servers = "gateway.conduktor.test:9092"
```

---

## 15. Checklist

Verify everything before proceeding to deployment:

- [ ] **AWS CLI** configured and `aws sts get-caller-identity` works
- [ ] **kubectl** installed and `kubectl get nodes` returns your EKS worker nodes
- [ ] **helm**, **terraform**, **yq**, **envsubst**, **keytool**, **openssl** installed
- [ ] **EKS cluster** created and running with at least 3 worker nodes (`m5.xlarge` or bigger)
- [ ] **EBS CSI Driver** installed as an EKS addon (Step 6)
- [ ] **OIDC provider** associated with the EKS cluster (Step 8)
- [ ] **S3 bucket** created for monitoring data (Step 7)
- [ ] **IAM role for ALB controller** created with IRSA trust policy (Step 9)
- [ ] **IAM role for Cortex S3** created with IRSA trust policy (Step 10)
- [ ] **Domain names** chosen (Step 11)
- [ ] **ACM certificate** imported — self-signed certificate ARN noted (Step 12)
- [ ] **Conduktor license** set as `LICENSE` env var or in `.env` file (Step 13)
- [ ] **config.env** filled in with all values (Step 14)
- [ ] **terraform.tfvars** updated with your domain names (Step 14)

Once everything is checked, proceed to deploy:

```bash
make start-eks-stack
make install-conduktor-platform
```

After `install-conduktor-platform` completes, **set up `/etc/hosts`** as described in Step 11 before continuing:

```bash
ALB_HOST=$(kubectl get ingress console-alb-ingress -n conduktor \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
ALB_IP=$(dig +short $ALB_HOST | head -1)
sudo sh -c "echo '$ALB_IP  console.conduktor.test gateway.conduktor.test oidc.conduktor.test' >> /etc/hosts"
```

Then continue with:

```bash

make init-conduktor-platform
```

Access the Console at `https://console.conduktor.test` (accept the self-signed certificate warning).

See [README.md](./README.md) for full deployment instructions and tuning.
