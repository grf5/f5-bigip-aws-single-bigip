#!/bin/bash
echo "This will destroy your deployment, no going back from here - Press enter to continue"
# pause to make sure!
read -r -p "Are you sure? [y/N] " response
# destroy
if [[ "$response" =~ ^([yY][eE][sS]|[yY])$ ]]
then
    terraform -chdir=terraform destroy -var-file=../admin.auto.tfvars --auto-approve
else
    echo "Cancelled due to user input"
fi