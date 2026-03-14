#!/usr/bin/env sh

set -E

SCRIPT_DIR=$(cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )
. "${SCRIPT_DIR}/kubernetes_utils.sh"

loadConfig

if [[ -f "${SCRIPT_DIR}/.env" ]]; then
  echo "Loading environment variables from .env file"
  export $(grep -v '^#' .env | sed 's/export //')
fi

checkKubeContext

yq --version > /dev/null 2>&1 || { echo >&2 "yq is not installed. Please install yq to continue."; exit 1; }

license=${LICENSE:?Missing LICENSE environment variable with Conduktor license key}

tmp_dir=$(mktemp -d)
echo "Temporary directory created: $tmp_dir"
tmp_gateway_secrets="${tmp_dir}/gateway-secrets.yaml"
tmp_console_secrets="${tmp_dir}/console-secrets.yaml"
tmp_gateway_values="${tmp_dir}/gateway-values.yaml"
tmp_console_values="${tmp_dir}/console-values.yaml"

# Process values files with envsubst for domain parameterization
envsubst '$GATEWAY_DOMAIN $OIDC_DOMAIN' < ${SCRIPT_DIR}/gateway-values.yaml > "$tmp_gateway_values"
envsubst '$CONSOLE_DOMAIN $OIDC_DOMAIN $CORTEX_IRSA_ROLE_ARN $S3_BUCKET_NAME $S3_REGION' < ${SCRIPT_DIR}/console-values.yaml > "$tmp_console_values"

echo "Installing conduktor-platform"
helm repo add conduktor https://helm.conduktor.io

echo
echo "Install Conduktor Gateway"
yq eval -M '.stringData.GATEWAY_LICENSE_KEY = strenv(LICENSE)' ${SCRIPT_DIR}/gateway-secrets.yaml > "$tmp_gateway_secrets"
gateway_secrets_sha256sum=$(sha256sum "$tmp_gateway_secrets" | awk '{print $1}')
kubectl apply -f "$tmp_gateway_secrets"
helm upgrade --install -n conduktor \
  --repo https://helm.conduktor.io/ \
  -f "$tmp_gateway_values" \
  --set gateway.podAnnotations."checksum/secrets"="${gateway_secrets_sha256sum}" \
  conduktor-gateway conduktor-gateway

echo
echo "Install Conduktor Console"
yq eval -M '.stringData.CDK_LICENSE = strenv(LICENSE)' ${SCRIPT_DIR}/console-secrets.yaml > "$tmp_console_secrets"
console_secrets_sha256sum=$(sha256sum "$tmp_console_secrets" | awk '{print $1}')
kubectl apply -f "$tmp_console_secrets"
helm upgrade --install -n conduktor \
  --repo https://helm.conduktor.io/ \
  -f "$tmp_console_values" \
  --set platform.podAnnotations."checksum/secrets"="${console_secrets_sha256sum}" \
  --set cortex.podAnnotations."checksum/secrets"="${console_secrets_sha256sum}" \
  conduktor-console console

echo "Wait for Conduktor platform to be available"
waitAvailable conduktor deployment/conduktor-gateway
waitAvailable conduktor deployment/conduktor-console

rm -rf "${tmp_dir:?Missing tmp dir}"
