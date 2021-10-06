#!/bin/bash
# init to ensure we have proper providers
terraform -chdir=terraform init
# run the plan to ensure we have proper configuration
terraform -chdir=terraform plan -input=false -var-file=../admin.auto.tfvars -out tfplan
EXITCODE=$?
test $EXITCODE -eq 0 && terraform -chdir=terraform apply -input=false --auto-approve tfplan || echo "something bad happened"; 
# apply
