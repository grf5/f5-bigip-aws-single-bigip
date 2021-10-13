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
