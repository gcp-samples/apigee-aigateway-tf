if [ -f ".env" ]; then
  source .env
fi

if [ -z "$APIGEE_TYPE" ]; then
  APIGEE_TYPE=EVALUATION
fi

if [ -z "$GOOGLE_CLOUD_LOCATION" ]; then
  GOOGLE_CLOUD_LOCATION=europe-west1
fi

if [ -z "$UNIQUE_NAME" ]; then
  UNIQUE_NAME=$USER
fi

read -e -i "$GOOGLE_CLOUD_PROJECT" -p "Enter your Google Cloud Project Id: " project_id
read -e -i "$GOOGLE_CLOUD_LOCATION" -p "Enter your Google Cloud Region: " region
read -e -i "$APIGEE_TYPE" -p "Enter your Apigee deployment type (EVALUATION, PAYG, SUBSCRIPTION): " apigee_type

echo "export GOOGLE_CLOUD_PROJECT=$project_id" > .env
echo "export GOOGLE_CLOUD_LOCATION=$region" >> .env
echo "export APIGEE_TYPE=$apigee_type" >> .env
echo >> .env;
echo "# Optional Variables" >> .env;
echo "export UNIQUE_NAME=\$UNIQUE_NAME" >> .env
echo "export APIGEE_VPC_NAME=" >> .env
echo "export APIGEE_SUBNET_NAME=" >> .env
echo "export APIGEE_DRZ_LOCATION=" >> .env

source .env
