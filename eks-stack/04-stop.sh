#!/usr/bin/env sh

set -e

SCRIPT_DIR=$(cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )
TERRAFORM_DIR="${SCRIPT_DIR}/provisioning"
. "${SCRIPT_DIR}/kubernetes_utils.sh"

loadConfig
checkKubeContext

echo "Tearing down EKS stack..."

echo
echo "Uninstalling Conduktor platform..."
helm uninstall conduktor-console -n conduktor 2>/dev/null || true
helm uninstall conduktor-gateway -n conduktor 2>/dev/null || true

echo
echo "Removing ALB Ingress resources..."
kubectl delete ingress console-alb-ingress -n conduktor 2>/dev/null || true
kubectl delete ingress gateway-admin-alb-ingress -n conduktor 2>/dev/null || true
kubectl delete ingress keycloak-alb-ingress -n cdk-deps 2>/dev/null || true

echo
echo "Removing Keycloak..."
envsubst '$OIDC_DOMAIN $CONSOLE_DOMAIN' < ${SCRIPT_DIR}/manifests/02-keycloak.yaml | kubectl delete -f - 2>/dev/null || true

echo
echo "Removing Schema Registry..."
kubectl delete -f ${SCRIPT_DIR}/manifests/03-schema-registry.yaml 2>/dev/null || true

echo
echo "Removing Grafana CRDs..."
kubectl delete -f ${SCRIPT_DIR}/manifests/04-grafana-crds.yaml 2>/dev/null || true

echo
echo "Removing CoreDNS rewrite rules..."
CURRENT_COREFILE=$(kubectl get configmap coredns -n kube-system -o jsonpath='{.data.Corefile}' 2>/dev/null || true)
if echo "$CURRENT_COREFILE" | grep -q "conduktor-gateway"; then
  UPDATED_COREFILE=$(echo "$CURRENT_COREFILE" | grep -v "conduktor-gateway\|keycloak\.cdk-deps")
  kubectl get configmap coredns -n kube-system -o json | \
    jq --arg corefile "$UPDATED_COREFILE" '.data.Corefile = $corefile' | \
    kubectl apply -f - 2>/dev/null || true
  kubectl -n kube-system delete pod -l k8s-app=kube-dns 2>/dev/null || true
fi

echo
echo "Uninstalling Helm releases..."
helm uninstall kafka -n cdk-deps 2>/dev/null || true
helm uninstall main-postgresql -n cdk-deps 2>/dev/null || true
helm uninstall sql-postgresql -n cdk-deps 2>/dev/null || true
helm uninstall vault -n cdk-deps 2>/dev/null || true
helm uninstall prometheus -n monitoring 2>/dev/null || true
helm uninstall grafana-operator -n monitoring 2>/dev/null || true

echo
echo "Removing cert-manager CRDs..."
envsubst '$CONSOLE_DOMAIN $GATEWAY_DOMAIN $OIDC_DOMAIN' < ${SCRIPT_DIR}/manifests/01-cert-manager-crds.yaml | kubectl delete -f - 2>/dev/null || true

echo
echo "Uninstalling infrastructure Helm releases..."
helm uninstall aws-load-balancer-controller -n kube-system 2>/dev/null || true
helm uninstall trust-manager -n cert-manager 2>/dev/null || true
helm uninstall cert-manager -n cert-manager 2>/dev/null || true

echo
echo "Removing gp3 StorageClass..."
kubectl delete storageclass gp3 2>/dev/null || true

echo
echo "Removing namespaces..."
kubectl delete -f ${SCRIPT_DIR}/manifests/00-namespaces.yaml 2>/dev/null || true

echo
echo "Cleaning Terraform state..."
rm -rf ${TERRAFORM_DIR}/.terraform ${TERRAFORM_DIR}/.terraform.lock.hcl ${TERRAFORM_DIR}/terraform.tfstate*

echo
echo "EKS stack teardown complete!"
