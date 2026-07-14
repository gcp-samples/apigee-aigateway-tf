# Apigee AI Gateway Terraform Template
This is a basic Apigee AI Gateway Terraform template that can be easily used and customized.

```sh
# Initialize and set variables
source ./sh/initialize.sh
source ./sh/tfclean.sh
cd tf
terraform init
terraform apply -var "project_id=$GOOGLE_CLOUD_PROJECT" -var "region=$GOOGLE_CLOUD_LOCATION" --var "apigee_type=$APIGEE_TYPE"
cd ..
```
