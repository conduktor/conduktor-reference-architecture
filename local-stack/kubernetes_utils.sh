#!/usr/bin/env sh

SCRIPT_DIR=$(cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )

createK3dCluster() {
  if k3d cluster list | grep -q conduktor-platform-p75; then
    echo "Cluster already exists. Skipping creation."
    return
  fi
  echo "Create the test cluster"
  if grep -q btrfs /proc/mounts; then
    echo "Btrfs filesystem detected. Mounting /dev/mapper. See https://k3d.io/v5.8.3/faq/faq/";
    k3d cluster create --config ${SCRIPT_DIR}/k3d-stack/k3d-config.yaml -v /dev/mapper:/dev/mapper;
  else
    k3d cluster create --config ${SCRIPT_DIR}/k3d-stack/k3d-config.yaml;
  fi
  echo "Current context : $(kubectl config current-context)"
}

checkKubeContext() {
  if [ "$(kubectl config current-context)" != "k3d-conduktor-platform-p75" ]; then
    echo "Current context is not k3d-k3s-default. Switching context to k3d-conduktor-platform-p75"
    kubectl config use-context k3d-conduktor-platform-p75 || {
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

  # Retrieve the S3 TLS secret
  waitSecretCreated cdk-deps s3-crt-secret
  kubectl get secret s3-crt-secret -n cdk-deps -o jsonpath="{.data['tls\.crt']}" | base64 --decode > "$temp_dir/s3.tls.crt"

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