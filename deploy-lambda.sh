#terraform init
#terraform apply -auto-approve

BUCKET_NAME=$(terraform output -raw bucket_name)

aws s3 cp train.csv s3://$BUCKET_NAME --profile default

