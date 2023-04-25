pip install --platform manylinux2014_x86_64 --target=lambda_function --implementation cp --python 3.9 --only-binary=:all: --upgrade psycopg2-binary
pip install --platform manylinux2014_x86_64 --target=lambda_function --implementation cp --python 3.9 --only-binary=:all: --upgrade pandas

terraform init
terraform apply -auto-approve

BUCKET_NAME=$(terraform output -raw bucket_name)

aws s3 cp train.csv s3://$BUCKET_NAME --profile default

