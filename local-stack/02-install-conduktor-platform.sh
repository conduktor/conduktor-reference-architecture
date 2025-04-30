#!/usr/bin/env sh

set -E

SCRIPT_DIR=$(cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )
. "${SCRIPT_DIR}/kubernetes_utils.sh"

checkKubeContext

yq --version > /dev/null 2>&1 || { echo >&2 "yq is not installed. Please install yq to continue."; exit 1; }

license=${LICENSE:?Missing license environment variable}

tmp_dir=$(mktemp -d)
echo "Temporary directory created: $tmp_dir"
tmp_gateway_secrets="${tmp_dir}/gateway-secrets.yaml"
tmp_console_secrets="${tmp_dir}/console-secrets.yaml"

echo "Installing conduktor-platform"

echo
echo "Install Conduktor Gateway"
yq eval -M '.stringData.GATEWAY_LICENSE_KEY = strenv(LICENSE)' ${SCRIPT_DIR}/gateway-secrets.yaml > "$tmp_gateway_secrets"
gateway_secrets_sha256sum=$(sha256sum "$tmp_gateway_secrets" | awk '{print $1}')
kubectl apply -f "$tmp_gateway_secrets"
helm upgrade --install -n conduktor \
  --repo https://helm.conduktor.io/ \
  -f "${SCRIPT_DIR}/gateway-values.yaml" \
  --set gateway.podAnnotations."checksum/secrets"="${gateway_secrets_sha256sum}" \
  conduktor-gateway conduktor-gateway

echo
echo "Install Conduktor Console"
yq eval -M '.stringData.CDK_LICENSE = strenv(LICENSE)' ${SCRIPT_DIR}/console-secrets.yaml > "$tmp_console_secrets"
console_secrets_sha256sum=$(sha256sum "$tmp_console_secrets" | awk '{print $1}')
kubectl apply -f "$tmp_console_secrets"
helm upgrade --install -n conduktor \
  --repo https://helm.conduktor.io/ \
  -f "${SCRIPT_DIR}/console-values.yaml" \
  --set platform.podAnnotations."checksum/secrets"="${console_secrets_sha256sum}" \
  --set cortex.podAnnotations."checksum/secrets"="${console_secrets_sha256sum}" \
  conduktor-console console

echo "Wait for Conduktor platform to be available"
waitAvailable conduktor deployment/conduktor-gateway
waitAvailable conduktor deployment/conduktor-console

rm -rf "${tmp_dir:?Missing tmp dir}"