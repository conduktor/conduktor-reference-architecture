#!/usr/bin/env sh

set -E

SCRIPT_DIR=$(cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )
TERRAFORM_DIR=${SCRIPT_DIR}/provisioning

. "${SCRIPT_DIR}/kubernetes_utils.sh"

checkKubeContext
pushd "${TERRAFORM_DIR}"
  echo "Initializing conduktor-platform"
  terraform init --upgrade

  # Check if admin already in state or not
  if terraform state list | grep -q "conduktor_console_group_v2.admin"; then
    echo "Admin group already exists in state"
  else
    echo "Admin group does not exist in state"
    # import already existing admin group
    terraform apply -var-file=terraform.tfvars -target=conduktor_console_group_v2.admin -auto-approve
  fi

  terraform apply -var-file=terraform.tfvars -auto-approve
popd