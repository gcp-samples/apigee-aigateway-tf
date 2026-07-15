# Apigee AI Gateway Terraform Template
This is a basic Apigee AI Gateway Terraform template that can be easily tested and customized. This is not mean for production deployments, but rather just for sandbox, lab or test deployments.

## Resources created
* Apigee org and instance in the chosen GCP project and region.
* HTTPS load balancer with nip.io cert for testing.
* PSC northbound from load balancer to Apigee instance.
* Apigee data collectors for token analytics.
* Apigee custom reports for token & AI analytics.

## Deploy
Run these commands to initialize and apply the terraform template in your sandbox project.

```sh
# Initialize and set variables
source ./sh/initialize.sh
source ./sh/tfclean.sh
cd tf
terraform init
terraform apply -var "project_id=$GOOGLE_CLOUD_PROJECT" -var "region=$GOOGLE_CLOUD_LOCATION" --var "apigee_type=$APIGEE_TYPE"
cd ..
```
