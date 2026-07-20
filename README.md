# Apigee AI Gateway Terraform Template
This is a basic Apigee AI Gateway Terraform template that can be easily tested and customized. This is not meant for production deployments, but rather as a sample for customization & learning.

## Resources created
* Apigee org and instance in the chosen GCP project and region.
* HTTPS load balancer with nip.io cert for testing.
* PSC northbound from load balancer to Apigee instance.
* Apigee data collectors for token analytics.
* Apigee custom reports for token & AI analytics.

## Deploy
Run these commands to initialize and apply the terraform template in your sandbox project.

These **optional parameters** can be added to the `apply` command to customize the deployment.
* **--var "drz_location=$APIGEE_DRZ_LOCATION"**
* **--var "apigee_type=$APIGEE_TYPE"**
* **--var "network=$APIGEE_VPC_NAME"**
* **--var "subnet=$APIGEE_SUBNET_NAME"`**

```sh
# Initialize and set variables
source ./sh/initialize.sh
source ./sh/tfclean.sh
cd tf
terraform init
terraform apply -var "project_id=$GOOGLE_CLOUD_PROJECT" -var "region=$GOOGLE_CLOUD_LOCATION" --var "apigee_type=$APIGEE_TYPE"
cd ..
```
