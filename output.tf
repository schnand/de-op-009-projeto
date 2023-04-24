output "bucket_name" {
  value = aws_s3_bucket.b.bucket
}

output "database_host" {
  value = aws_db_instance.rds-postgres.address
}

output "database_username" {
  value = aws_db_instance.rds-postgres.username
}

output "database_password" {
  sensitive = true
  value = aws_db_instance.rds-postgres.password
}

output "database_name" {
  value = aws_db_instance.rds-postgres.db_name
}

output "database_port" {
  value = aws_db_instance.rds-postgres.port
}