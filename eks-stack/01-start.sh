#!/usr/bin/env sh

set -E

SCRIPT_DIR=$(cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )
. "${SCRIPT_DIR}/kubernetes_utils.sh"

echo "Loading EKS configuration..."
loadConfig
checkKubeContext

echo
echo "00 - Creating namespaces and storage class"
kubectl apply -f ${SCRIPT_DIR}/manifests/00-namespaces.yaml

# Create gp3 StorageClass using EBS CSI driver (EKS does not provide a default StorageClass)
kubectl apply -f - <<'EOF'
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: gp3
  annotations:
    storageclass.kubernetes.io/is-default-class: "true"
provisioner: ebs.csi.aws.com
parameters:
  type: gp3
volumeBindingMode: WaitForFirstConsumer
reclaimPolicy: Delete
allowVolumeExpansion: true
EOF

echo
echo "01 - Adding Helm repositories"
helm repo add jetstack https://charts.jetstack.io
helm repo add bitnami https://charts.bitnami.com/bitnami
helm repo add hashicorp https://helm.releases.hashicorp.com
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo add eks https://aws.github.io/eks-charts
helm repo update

echo
echo "02 - Installing cert-manager"
helm upgrade --install cert-manager jetstack/cert-manager \
  --namespace cert-manager \
  --version v1.17.0 \
  -f ${SCRIPT_DIR}/helm-values/cert-manager.yaml \
  --wait

echo
echo "03 - Installing trust-manager"
helm upgrade --install trust-manager jetstack/trust-manager \
  --namespace cert-manager \
  --version v0.16.0 \
  -f ${SCRIPT_DIR}/helm-values/trust-manager.yaml \
  --wait

echo
echo "04 - Installing AWS Load Balancer Controller"
helm upgrade --install aws-load-balancer-controller eks/aws-load-balancer-controller \
  --namespace kube-system \
  --set clusterName="${EKS_CLUSTER_NAME}" \
  --set vpcId="${VPC_ID}" \
  --set serviceAccount.create=true \
  --set serviceAccount.name=aws-load-balancer-controller \
  --set serviceAccount.annotations."eks\.amazonaws\.com/role-arn"="${AWS_LB_CONTROLLER_IRSA_ROLE_ARN}" \
  --wait

echo
echo "Waiting for base components to be ready"
waitAvailable cert-manager deployment/cert-manager
waitAvailable cert-manager deployment/trust-manager
waitAvailable kube-system deployment/aws-load-balancer-controller

echo
echo "05 - Installing cert-manager CRDs (certificates and issuers)"
envsubst '$CONSOLE_DOMAIN $GATEWAY_DOMAIN $OIDC_DOMAIN' < ${SCRIPT_DIR}/manifests/01-cert-manager-crds.yaml | kubectl apply -f -

echo
echo "Waiting for certificate secrets to be created"
waitSecretCreated cdk-deps pg-main-crt-secret
waitSecretCreated cdk-deps pg-sql-crt-secret

echo
echo "06 - Installing Conduktor dependencies"

echo "Installing main-postgresql..."
helm upgrade --install main-postgresql bitnami/postgresql \
  --namespace cdk-deps \
  --version 16.6.0 \
  -f ${SCRIPT_DIR}/helm-values/postgresql-main.yaml

echo "Installing sql-postgresql..."
helm upgrade --install sql-postgresql bitnami/postgresql \
  --namespace cdk-deps \
  --version 16.6.0 \
  -f ${SCRIPT_DIR}/helm-values/postgresql-sql.yaml

echo "Installing kafka..."
helm upgrade --install kafka bitnami/kafka \
  --namespace cdk-deps \
  --version 32.1.2 \
  -f ${SCRIPT_DIR}/helm-values/kafka.yaml

echo "Installing vault..."
helm upgrade --install vault hashicorp/vault \
  --namespace cdk-deps \
  --version 0.30.0 \
  -f ${SCRIPT_DIR}/helm-values/vault.yaml

echo "Installing prometheus..."
helm upgrade --install prometheus prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --version 70.3.0 \
  -f ${SCRIPT_DIR}/helm-values/prometheus.yaml

echo "Installing grafana-operator..."
helm upgrade --install grafana-operator bitnami/grafana-operator \
  --namespace monitoring \
  --version 4.9.0 \
  -f ${SCRIPT_DIR}/helm-values/grafana-operator.yaml

echo
echo "Waiting for dependencies to be ready"
waitRollout cdk-deps sts/main-postgresql
waitRollout cdk-deps sts/kafka-controller

# generate truststore for Schema registry using Kafka certificates
echo
echo "07 - Setting up Schema Registry"
generate_schema_registry_jks_truststore
kubectl apply -f ${SCRIPT_DIR}/manifests/03-schema-registry.yaml

echo
echo "08 - Installing Keycloak"
# Use explicit variable list to avoid clobbering Keycloak's own ${role_default-roles} and ${profileScopeConsentText}
envsubst '$OIDC_DOMAIN $CONSOLE_DOMAIN' < ${SCRIPT_DIR}/manifests/02-keycloak.yaml | kubectl apply -f -

echo
echo "09 - Installing Grafana CRDs"
kubectl apply -f ${SCRIPT_DIR}/manifests/04-grafana-crds.yaml

echo
echo "10 - Update CoreDNS config for Gateway SNI routing"
# EKS CoreDNS does not support coredns-custom ConfigMap — patch the Corefile directly
CURRENT_COREFILE=$(kubectl get configmap coredns -n kube-system -o jsonpath='{.data.Corefile}')
if echo "$CURRENT_COREFILE" | grep -q "conduktor-gateway"; then
  echo "CoreDNS rewrite rules already present, skipping..."
else
  # Insert rewrite rules after the "ready" line in the Corefile
  REWRITE_RULES="    rewrite name regex .*${GATEWAY_DOMAIN_ESCAPED} conduktor-gateway-external.conduktor.svc.cluster.local answer auto\n    rewrite name regex ${OIDC_DOMAIN_ESCAPED} keycloak.cdk-deps.svc.cluster.local answer auto"
  UPDATED_COREFILE=$(echo "$CURRENT_COREFILE" | sed "/^[[:space:]]*ready$/a\\
${REWRITE_RULES}")
  kubectl get configmap coredns -n kube-system -o json | \
    jq --arg corefile "$UPDATED_COREFILE" '.data.Corefile = $corefile' | \
    kubectl apply -f -
  echo "CoreDNS rewrite rules added"
fi
# Restart CoreDNS pods to pick up configuration changes
kubectl -n kube-system delete pod -l k8s-app=kube-dns

echo
echo "11 - Generating JKS truststore"
# Extract and package all certificates into a JKS truststore for Conduktor Gateway and Conduktor Console
generate_jks_truststore

# Download the truststore to the local machine
kubectl get secret bundle-truststore -n conduktor -o jsonpath='{.data.truststore\.jks}' | base64 --decode > $SCRIPT_DIR/truststore.jks
kubectl get secret root-ca-secret -n cert-manager -o jsonpath='{.data.ca\.crt}' | base64 --decode > $SCRIPT_DIR/ca.crt

echo
echo "12 - Creating ALB Ingress resources"

# ALB Ingress for Console
# Uses group.name to merge all three ingresses into a single ALB
envsubst '$CONSOLE_DOMAIN $ACM_CERTIFICATE_ARN' <<'INGRESS_EOF' | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: console-alb-ingress
  namespace: conduktor
  annotations:
    kubernetes.io/ingress.class: alb
    alb.ingress.kubernetes.io/group.name: conduktor-alb
    alb.ingress.kubernetes.io/scheme: internet-facing
    alb.ingress.kubernetes.io/target-type: ip
    alb.ingress.kubernetes.io/listen-ports: '[{"HTTPS":443}]'
    alb.ingress.kubernetes.io/certificate-arn: ${ACM_CERTIFICATE_ARN}
    alb.ingress.kubernetes.io/backend-protocol: HTTPS
    alb.ingress.kubernetes.io/healthcheck-protocol: HTTPS
    alb.ingress.kubernetes.io/healthcheck-path: /
spec:
  rules:
    - host: ${CONSOLE_DOMAIN}
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: conduktor-console
                port:
                  number: 80
INGRESS_EOF

# ALB Ingress for Gateway admin API
envsubst '$GATEWAY_DOMAIN $ACM_CERTIFICATE_ARN' <<'INGRESS_EOF' | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: gateway-admin-alb-ingress
  namespace: conduktor
  annotations:
    kubernetes.io/ingress.class: alb
    alb.ingress.kubernetes.io/group.name: conduktor-alb
    alb.ingress.kubernetes.io/scheme: internet-facing
    alb.ingress.kubernetes.io/target-type: ip
    alb.ingress.kubernetes.io/listen-ports: '[{"HTTPS":443}]'
    alb.ingress.kubernetes.io/certificate-arn: ${ACM_CERTIFICATE_ARN}
    alb.ingress.kubernetes.io/backend-protocol: HTTPS
    alb.ingress.kubernetes.io/healthcheck-protocol: HTTPS
    alb.ingress.kubernetes.io/healthcheck-path: /
spec:
  rules:
    - host: ${GATEWAY_DOMAIN}
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: conduktor-gateway-external
                port:
                  number: 8888
INGRESS_EOF

# ALB Ingress for Keycloak
envsubst '$OIDC_DOMAIN $ACM_CERTIFICATE_ARN' <<'INGRESS_EOF' | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: keycloak-alb-ingress
  namespace: cdk-deps
  annotations:
    kubernetes.io/ingress.class: alb
    alb.ingress.kubernetes.io/group.name: conduktor-alb
    alb.ingress.kubernetes.io/scheme: internet-facing
    alb.ingress.kubernetes.io/target-type: ip
    alb.ingress.kubernetes.io/listen-ports: '[{"HTTPS":443}]'
    alb.ingress.kubernetes.io/certificate-arn: ${ACM_CERTIFICATE_ARN}
    alb.ingress.kubernetes.io/backend-protocol: HTTPS
    alb.ingress.kubernetes.io/healthcheck-protocol: HTTPS
    alb.ingress.kubernetes.io/healthcheck-path: /
spec:
  rules:
    - host: ${OIDC_DOMAIN}
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: keycloak
                port:
                  name: https
INGRESS_EOF

cat <<EOF

EKS stack deployment complete!

Next steps:
  1. make install-conduktor-platform

  2. Copy the output of the following command into /etc/hosts
     ./get-hosts.sh

  3. make init-conduktor-platform

  4. Have fun with Console and Gateway!!
EOF
