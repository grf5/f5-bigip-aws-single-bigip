#!/bin/bash
# Enable logging to file
export TF_LOG=debug
export TF_LOG_PATH=terraform.log
# init to ensure we have proper providers
terraform -chdir=terraform init
# run the plan to ensure we have proper configuration
terraform -chdir=terraform plan -input=false -var-file=../admin.auto.tfvars -out tfplan
EXITCODE=$?
# apply the plan if the planning operation was successful
test $EXITCODE -eq 0 && terraform -chdir=terraform apply -input=false --auto-approve tfplan || echo "An error occurred while creating the Terraform plan"; 
printf "$0 completed at $(date)"
# Mac notification after a certain amount of time to remind us the environment is ready
if [[ "$OSTYPE" == "darwin"* ]]; then sleep 300; osascript -e 'display notification "Your BIG-IP environment in AWS should be ready at this time."';  fi &
