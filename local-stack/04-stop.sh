#!/usr/bin/env sh

set -e

SCRIPT_DIR=$(cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )
TERRAFORM_DIR="${SCRIPT_DIR}/provisioning"

checkKubeContext() {
  if [ "$(kubectl config current-context)" != "k3d-conduktor-platform-p75" ]; then
    echo "Current context is not k3d-k3s-default. Switching context to k3d-conduktor-platform-p75"
    kubectl config use-context k3d-conduktor-platform-p75
  fi
}

checkKubeContext
echo "Deleting k3d cluster"
k3d cluster delete --config ${SCRIPT_DIR}/k3d-stack/k3d-config.yaml || true

rm -rf ${TERRAFORM_DIR}/.terraform ${TERRAFORM_DIR}/.terraform.lock.hcl ${TERRAFORM_DIR}/terraform.tfstate*
