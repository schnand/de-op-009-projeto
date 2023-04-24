resource "aws_vpc" "dev-vpc" {
  cidr_block = "172.16.1.0/25" # o /25 indica a quantidade de IPs disponíveis para máquinas na rede

  tags = {
    Name = "VPC 1 - DE-OP-009"
  }
}

# Cria uma subnet que pertence àquela rede privada 
resource "aws_subnet" "private-subnet" {
  count             = var.subnet_count
  vpc_id            = aws_vpc.dev-vpc.id
  cidr_block        = var.subnet_cidr_block[count.index] # "172.16.1.0/25" 172.16.1.48 até 172.16.1.64 
  availability_zone = var.subnet_availability_zone[count.index]

  tags = {
    Name = "Subnet ${count.index + 1} - DE-OP-009"
  }
}

# Cria atrelando as subnets as subnets groups do banco de dados 
resource "aws_db_subnet_group" "db-subnet" {
  name       = "db_subnet_group"
  subnet_ids = [for s in aws_subnet.private-subnet: s.id]
}


resource "aws_security_group" "lambda" {
  vpc_id = aws_vpc.dev-vpc.id

  egress {
    from_port = 0
    to_port = 65535
    protocol = "tcp"
    cidr_blocks = [aws_vpc.dev-vpc.cidr_block]
  }
}


# Cria um grupo de segurança contendo regras de entrada e saída de rede. 
# Idealmente, apenas abra o que for necessário e preciso.
resource "aws_security_group" "allow_db" {
  name        = "permite_conexao_rds"
  description = "Grupo de seguranca para permitir conexao ao db"
  vpc_id      = aws_vpc.dev-vpc.id

 ingress {
    description = "Porta de conexao ao Postgres"
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = [aws_vpc.dev-vpc.cidr_block] # aws_vpc.dev-vpc.cidr_blocks
    security_groups = [aws_security_group.lambda.id]
  }
  tags = {
    Name = "DE-OP-009"
  }
}

##
resource "random_password" "password" {
  length = 32
  special = false
}


# Cria uma instância de RDS
resource "aws_db_instance" "rds-postgres" {
  allocated_storage = 10
  identifier = "meu-banco"
  db_name           = "mydb"
  engine            = "postgres"
  engine_version    = "12.9"
  instance_class    = "db.t3.micro"
  username          = "postgres" # Nome do usuário "master"
  password          = random_password.password.result # Senha do usuário master
  port              = 5432
  # Parâmetro que indica se o DB vai ser acessível publicamente ou não.
  # Se quiser adicionar isso, preciso de um internet gateway na minha subnet. Em outras palavras, preciso permitir acesso "de fora" da aws.
  # publicly_accessible    = true

  # Parâmetro que indica se queremos ter um cluster RDS que seja multi az. 
  # Lembrando, paga-se a mais por isso, mas para ambientes produtivos é essencial.
  # multi_az               = true
  skip_final_snapshot    = true
  db_subnet_group_name   = aws_db_subnet_group.db-subnet.name
  vpc_security_group_ids = [aws_security_group.allow_db.id]
}


# Criaum bucket S3.
resource "aws_s3_bucket" "b" {
  bucket = "de-op-009-bucket-grupo-4-lambda"  # CRIAR VARIAVEL
  force_destroy = true

  tags = {
    Name  = "Meu bucket grupo 4 com lambda"
  }
}

# Cria um documento para política do "lambda ser um lambda", assumir uma role.
# Pode ser utilizado também um objeto do tipo aws_s3_bucket_policy, como temos no 2 - s3 com website. 
# São duas formas de "fazer a mesma coisa". 

data "aws_iam_policy_document" "assume_role" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"] 
  }
}

# Crio uma role para o lambda. 
# Lembrando: uma role é um conjunto de permissões.
resource "aws_iam_role" "iam_for_lambda" {
  name               = "iam_para_o_lambda"
  assume_role_policy = data.aws_iam_policy_document.assume_role.json
}

resource "aws_iam_role_policy_attachment" "AWSLambdaVPCAccessExecutionRole" {
    role       = aws_iam_role.iam_for_lambda.id
    policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

data "archive_file" "lambda" {
  type        = "zip"
  source_file = "lambda_function.py" # Para pastas, usar: source_dir CRIAR VARIAVEL
  # source_file = "${path.module}/lambda_function.py"
  output_path = "lambda_function_payload.zip"
}

resource "aws_lambda_function" "test_lambda" {
  function_name = var.nome_lambda
  filename      = "lambda_function_payload.zip"
  role          = aws_iam_role.iam_for_lambda.arn
  handler       = "lambda_function.lambda_metodo"

  source_code_hash = "${data.archive_file.lambda.output_base64sha256}"

  runtime = var.versao_python

  vpc_config {
    security_group_ids = [aws_security_group.lambda.id]
    subnet_ids = [for s in aws_subnet.private-subnet: s.id]
  } 

  environment {
    variables = {
      #JDBC_DATABASE_URL = "jdbc:postgresql://${aws_db_instance.rds.address}:${aws_db_instance.rds.port}/${aws_db_instance.rds.identifier}"
      DATABASE_HOST = aws_db_instance.rds-postgres.address
      DATABASE_USERNAME = aws_db_instance.rds-postgres.username
      DATABASE_PASSWORD = aws_db_instance.rds-postgres.password
      DATABASE_NAME = aws_db_instance.rds-postgres.db_name
      DATABASE_PORT = aws_db_instance.rds-postgres.port
    }
  }

  depends_on = [aws_iam_role_policy_attachment.AWSLambdaVPCAccessExecutionRole]
}


# Adiciono a funcionalidade do bucket s3 enviar notificações à minha função lambda.
# Os eventos que serão notificados são: Objetos criados (upload) e objetos removidos (delete).
resource "aws_s3_bucket_notification" "aws_lambda_trigger" {
  bucket = aws_s3_bucket.b.id
  lambda_function {
    lambda_function_arn = aws_lambda_function.test_lambda.arn
    events              = var.eventos_lambda_s3
  }

  # O depends_on aqui garante que esse recurso "aws_s3_bucket_notification" só será criado APÓS  "aws_lambda_permission" "test", que é um "pré requisito"
  depends_on = [aws_lambda_permission.invoke_function] 

}

# Aqui eu crio um log group no cloudwatch... um log group pode ser considerado uma "pastinha" para armazenar todos os logs de uma determinada função
resource "aws_cloudwatch_log_group" "function_log_group" {
  name              = "/aws/lambda/${aws_lambda_function.test_lambda.function_name}"
  retention_in_days = var.retencao_logs
  lifecycle {
    prevent_destroy = false
  }
}

# Adiciono permissões ao meu bucket s3 para invocar (fazer trigger) à minha função lambda.
resource "aws_lambda_permission" "invoke_function" {
  statement_id  = "AllowS3Invoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.test_lambda.function_name
  principal     = "s3.amazonaws.com"
  source_arn    = "arn:aws:s3:::${aws_s3_bucket.b.id}"

  depends_on = [aws_db_instance.rds-postgres]
}
