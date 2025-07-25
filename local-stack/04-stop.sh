#!/usr/bin/env sh

set -e

SCRIPT_DIR=$(cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )
TERRAFORM_DIR="${SCRIPT_DIR}/provisioning"
STACK_DIR=$(cd "${SCRIPT_DIR}/k3d-stack" && pwd)
. "${SCRIPT_DIR}/kubernetes_utils.sh"

checkKubeContext
echo "Deleting k3d cluster"
k3d cluster delete --config ${SCRIPT_DIR}/k3d-stack/k3d-config.yaml || true

rm -rf ${TERRAFORM_DIR}/.terraform ${TERRAFORM_DIR}/.terraform.lock.hcl ${TERRAFORM_DIR}/terraform.tfstate*
