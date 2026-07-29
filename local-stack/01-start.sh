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
# trust-manager Bundles distribute the per-domain truststores to labeled namespaces.
# kafka-stack-trust is consumed by SR (cdk-deps) and Gateway (conduktor);
# console-trust covers everything Console needs.
waitSecretCreated cdk-deps kafka-stack-trust
waitSecretCreated conduktor console-trust
# Client certificates Console mounts to authenticate on the Gateway internal
# listener (mTLS only). Console cannot start without them.
waitSecretCreated conduktor console-sa-client-crt-secret
waitSecretCreated conduktor client-sa-client-crt-secret

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

kubectl apply -f ${STACK_DIR}/03-components/schema-registry.yaml

echo
echo "04 - Installing dependencies CRDs"
kubectl apply -f ${STACK_DIR}/04-components-crds.yaml

echo
echo "05 - Update KubeDNS config"
kubectl apply -f ${STACK_DIR}/05-coredns-custom.yaml
kubectl -n kube-system delete pod -l k8s-app=kube-dns

# Extract the truststore for local CLI examples (README). The Gateway external
# listener uses one-way TLS, so a local client only needs trust. Reuse
# console-trust: it covers conduktor-ca (for the Gateway server cert) and
# ext-services-ca (for the OIDC token-fetch HTTPS call).
kubectl get secret console-trust -n conduktor -o jsonpath='{.data.truststore\.jks}' | base64 --decode > $SCRIPT_DIR/truststore.jks