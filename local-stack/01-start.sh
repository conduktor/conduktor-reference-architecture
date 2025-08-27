#!/usr/bin/env sh

set -E

SCRIPT_DIR=$(cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )
STACK_DIR=$(cd "${SCRIPT_DIR}/k3d-stack" && pwd)
. "${SCRIPT_DIR}/kubernetes_utils.sh"

echo "Creating k3d cluster"
createK3dCluster
checkKubeContext

echo
echo "01 - Installing infra base components"
kubectl apply -f ${STACK_DIR}/00-namespaces.yaml
kubectl apply -f ${STACK_DIR}/01-infra.yaml

echo
echo "Waiting for base components to be ready"
waitAvailable cert-manager deployment/cert-manager
waitAvailable cert-manager deployment/trust-manager
waitAvailable ingress-nginx deployment/ingress-nginx-controller

echo
echo "02 - Installing infra CRDs"
kubectl apply -f ${STACK_DIR}/02-infra-crds.yaml

echo
echo "Waiting for certificates secrets to be created"
waitSecretCreated cdk-deps pg-main-crt-secret
waitSecretCreated cdk-deps pg-sql-crt-secret
waitSecretCreated cdk-deps s3-crt-secret

echo
echo "03 - Installing Conduktor dependencies components"
kubectl apply -f ${STACK_DIR}/03-components/postgresql.yaml
kubectl apply -f ${STACK_DIR}/03-components/s3-minio.yaml
kubectl apply -f ${STACK_DIR}/03-components/kafka.yaml
kubectl apply -f ${STACK_DIR}/03-components/monitoring.yaml
kubectl apply -f ${STACK_DIR}/03-components/vault.yaml
#kubectl apply -f ${STACK_DIR}/03-components/dex.yaml
kubectl apply -f ${STACK_DIR}/03-components/keycloak.yaml

echo
echo "Waiting for dependencies to be ready"
waitRollout cdk-deps sts/main-postgresql
#waitAvailable cdk-deps deployment/s3-minio
waitRollout cdk-deps sts/kafka-controller

# generate truststore for Schema registry using Kafka certificates
generate_schema_registry_jks_truststore
kubectl apply -f ${STACK_DIR}/03-components/schema-registry.yaml

echo
echo "04 - Installing dependencies CRDs"
kubectl apply -f ${STACK_DIR}/04-components-crds.yaml

echo
echo "05 - Update KubeDNS config for Gateway SNI routing"
# restart kube-dns to make sure it picks up custom coreDNS configuration
kubectl apply -f ${STACK_DIR}/05-coredns-custom.yaml
kubectl -n kube-system delete pod -l k8s-app=kube-dns

# Extract and package all certificates into a JKS truststore for Conduktor Gateway and Conduktor Console
generate_jks_truststore

# Download the truststore to the local machine
kubectl get secret bundle-truststore -n conduktor -o jsonpath='{.data.truststore\.jks}' | base64 --decode > $SCRIPT_DIR/truststore.jks