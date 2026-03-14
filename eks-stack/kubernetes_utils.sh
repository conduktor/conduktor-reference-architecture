#!/usr/bin/env sh

SCRIPT_DIR=$(cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )

loadConfig() {
  if [ ! -f "${SCRIPT_DIR}/config.env" ]; then
    echo "config.env not found. Copy config.env.example to config.env and fill in your values."
    exit 1
  fi
  . "${SCRIPT_DIR}/config.env"

  # Validate required variables
  local required_vars="AWS_REGION EKS_CLUSTER_NAME KUBE_CONTEXT CONSOLE_DOMAIN GATEWAY_DOMAIN OIDC_DOMAIN ACM_CERTIFICATE_ARN S3_BUCKET_NAME S3_REGION CORTEX_IRSA_ROLE_ARN VPC_ID AWS_LB_CONTROLLER_IRSA_ROLE_ARN"
  for var in $required_vars; do
    eval val=\$$var
    if [ -z "$val" ]; then
      echo "Error: Required variable $var is not set in config.env"
      exit 1
    fi
  done

  # Pre-compute escaped domain versions for CoreDNS regex
  export GATEWAY_DOMAIN_ESCAPED=$(echo "${GATEWAY_DOMAIN}" | sed 's/\./\\./g')
  export OIDC_DOMAIN_ESCAPED=$(echo "${OIDC_DOMAIN}" | sed 's/\./\\./g')
}

checkKubeContext() {
  if [ "$(kubectl config current-context)" != "${KUBE_CONTEXT}" ]; then
    echo "Current context is not ${KUBE_CONTEXT}. Switching context..."
    kubectl config use-context "${KUBE_CONTEXT}" || {
      echo "Failed to switch context. Please check your kubectl configuration."
      exit 1
    }
  fi
}

waitSecretCreated() {
  namespace=$1
  resource=$2
  timeout=180
  interval=5
  start=$(date +%s)
  end=$((start + timeout))
  while true; do
    kubectl wait --for=create --timeout=${timeout}s -n ${namespace} secret ${resource} && break
    if [ $(date +%s) -ge $end ]; then
      echo "Timeout waiting for resource ${resource} in namespace ${namespace}"
      exit 1
    fi
    sleep 5
  done
}

# wait and retry until the deployment is ready with a timeout
waitAvailable() {
  namespace=$1
  resource=$2
  timeout=180
  interval=5
  start=$(date +%s)
  end=$((start + timeout))
  while true; do
    kubectl wait --for condition=Available=True --timeout=${timeout}s -n ${namespace} ${resource} && break
    if [ $(date +%s) -ge $end ]; then
      echo "Timeout waiting for resource ${resource} in namespace ${namespace}"
      exit 1
    fi
    sleep 5
  done
}

waitRollout() {
  namespace=$1
  resource=$2
  timeout=180
  interval=5
  start=$(date +%s)
  end=$((start + timeout))
  while true; do
    kubectl rollout status --watch --timeout=${timeout}s -n ${namespace} ${resource} && break
    if [ $(date +%s) -ge $end ]; then
      echo "Timeout waiting for resource ${resource} in namespace ${namespace}"
      exit 1
    fi
    sleep 5
  done
}

generate_schema_registry_jks_truststore() {
  local jks_password="conduktor"

  # Temporary directory to store the certificates and JKS file
  temp_dir=$(mktemp -d)
  echo "Temporary directory created at $temp_dir"

  echo "Retrieving certificates..."
  # Retrieve the CA
  waitSecretCreated cert-manager root-ca-secret
  kubectl get secret root-ca-secret -n cert-manager -o jsonpath="{.data['ca\.crt']}" | base64 --decode > "$temp_dir/root.ca.crt"

  # Retrieve the Kafka TLS secret
  waitSecretCreated cdk-deps kafka-tls
  kubectl get secret kafka-tls -n cdk-deps -o jsonpath="{.data['tls\.crt']}" | base64 --decode > "$temp_dir/kafka.tls.crt"
  kubectl get secret kafka-tls -n cdk-deps -o jsonpath="{.data['tls\.key']}" | base64 --decode > "$temp_dir/kafka.tls.key"

  echo "Certificates retrieved successfully."
  ls -al "$temp_dir"
  echo "Creating JKS truststore..."
  # Generate the JKS truststore
  for cert in "$temp_dir"/*.crt; do
    keytool -importcert -noprompt \
      -alias "$(basename "$cert" .crt)" \
      -file "$cert" \
      -keystore "$temp_dir/truststore.jks" \
      -storepass "$jks_password" -noprompt
  done

  # Generate kafka Keystore
  openssl pkcs12 -export \
    -inkey "$temp_dir/kafka.tls.key" \
    -in "$temp_dir/kafka.tls.crt" \
    -out "$temp_dir/kafka.tls.p12" \
    -name kafka \
    -CAfile "$temp_dir/root.ca.crt" \
    -caname local-selfsigned-ca \
    -passout pass:conduktor \
    -passin pass:conduktor
  keytool -v -importkeystore \
    -srckeystore "$temp_dir/kafka.tls.p12" \
    -srcstoretype PKCS12 \
    -destkeystore "$temp_dir/keystore.jks" \
    -deststoretype JKS \
    -deststorepass conduktor \
    -destkeypass conduktor \
    -srcstorepass conduktor \
    -srcalias kafka \
    -destalias kafka

  # Create a new secret with the JKS truststore
  kubectl delete secret sr-bundle-truststore -n cdk-deps --ignore-not-found
  kubectl create secret generic sr-bundle-truststore \
    --from-file=ssl.truststore.jks="$temp_dir/truststore.jks" -n cdk-deps

  kubectl delete secret sr-kafka-bundle-truststore -n cdk-deps --ignore-not-found
  kubectl create secret generic sr-kafka-bundle-truststore \
    --from-file=kafka.truststore.jks="$temp_dir/truststore.jks"  \
    --from-file=kafka.keystore.jks="$temp_dir/keystore.jks" -n cdk-deps

  # Clean up
  rm -rf "${temp_dir:?Missing temp dir}"
}

generate_jks_truststore() {
  local jks_password="conduktor"

  # Temporary directory to store the certificates and JKS file
  temp_dir=$(mktemp -d)
  echo "Temporary directory created at $temp_dir"

  echo "Retrieving certificates..."
  # Retrieve the CA
  waitSecretCreated cert-manager root-ca-secret
  kubectl get secret root-ca-secret -n cert-manager -o jsonpath="{.data['ca\.crt']}" | base64 --decode > "$temp_dir/root.ca.crt"

  # Retrieve Postgresql TLS secret
  waitSecretCreated cdk-deps pg-main-crt-secret
  waitSecretCreated cdk-deps pg-sql-crt-secret
  kubectl get secret pg-main-crt-secret -n cdk-deps -o jsonpath="{.data['tls\.crt']}" | base64 --decode > "$temp_dir/main-postgresql.tls.crt"
  kubectl get secret pg-sql-crt-secret  -n cdk-deps -o jsonpath="{.data['tls\.crt']}" | base64 --decode > "$temp_dir/sql-postgresql.tls.crt"

  # Retrieve the Kafka TLS secret
  waitSecretCreated cdk-deps kafka-tls
  kubectl get secret kafka-tls -n cdk-deps -o jsonpath="{.data['tls\.crt']}" | base64 --decode > "$temp_dir/kafka.tls.crt"

  # Retrieve the Schema Registry TLS secret
  waitSecretCreated cdk-deps sr-crt-secret
  kubectl get secret sr-crt-secret -n cdk-deps -o jsonpath="{.data['tls\.crt']}" | base64 --decode > "$temp_dir/sr.tls.crt"

  # Retrieve the OIDC TLS secret
  kubectl get secret keycloak-crt-secret -n cdk-deps -o jsonpath="{.data['tls\.crt']}" | base64 --decode > "$temp_dir/oidc.tls.crt"

  echo "Certificates retrieved successfully."
  ls -al "$temp_dir"
  echo "Creating JKS truststore..."
  # Generate the JKS truststore
  for cert in "$temp_dir"/*.crt; do
    keytool -importcert -noprompt \
      -alias "$(basename "$cert" .crt)" \
      -file "$cert" \
      -keystore "$temp_dir/truststore.jks" \
      -storepass "$jks_password" -noprompt
  done

  kubectl delete secret bundle-truststore -n conduktor --ignore-not-found
  kubectl create secret generic bundle-truststore \
    --from-file=truststore.jks="$temp_dir/truststore.jks" \
    -n conduktor

  # Clean up
  rm -rf "${temp_dir:?Missing temp dir}"
}

# Allows to call a function based on arguments passed to the script
$*
