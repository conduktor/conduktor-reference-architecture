#!/usr/bin/env sh
set -e

SCRIPT_DIR=$(cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )
. "${SCRIPT_DIR}/kubernetes_utils.sh"

loadConfig

ALB_HOST=$(kubectl get ingress console-alb-ingress -n conduktor -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null)
NLB_HOST=$(kubectl get svc conduktor-gateway-external -n conduktor -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null)

if [ -z "$ALB_HOST" ] || [ -z "$NLB_HOST" ]; then
  echo "ALB or NLB not ready yet. Please re-run this script later."
  [ -z "$ALB_HOST" ] && echo "  - ALB: not provisioned (check 'kubectl get ingress -n conduktor')"
  [ -z "$NLB_HOST" ] && echo "  - NLB: not provisioned (check 'kubectl get svc -n conduktor')"
  exit 1
fi

ALB_IP=$(dig +short "$ALB_HOST" | head -1)
NLB_IP=$(dig +short "$NLB_HOST" | head -1)

# Import ALB certificate into local truststore
openssl s_client -connect "${ALB_HOST}:443" -servername "${CONSOLE_DOMAIN}" </dev/null 2>/dev/null | \
  openssl x509 -outform PEM > "$SCRIPT_DIR/alb-cert.crt"
keytool -importcert -noprompt \
  -alias alb-self-signed \
  -file "$SCRIPT_DIR/alb-cert.crt" \
  -keystore "$SCRIPT_DIR/truststore.jks" \
  -storepass conduktor 2>/dev/null || true
rm -f "$SCRIPT_DIR/alb-cert.crt"
echo "ALB certificate imported into truststore.jks"

echo
echo "Add the following lines to /etc/hosts:"
echo
echo "$ALB_IP  ${CONSOLE_DOMAIN} ${OIDC_DOMAIN}"
echo "$NLB_IP  ${GATEWAY_DOMAIN} brokermain0.${GATEWAY_DOMAIN} brokermain1.${GATEWAY_DOMAIN} brokermain2.${GATEWAY_DOMAIN} brokermain3.${GATEWAY_DOMAIN}"
