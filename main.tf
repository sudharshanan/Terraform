provider "aws" {
  region = "us-east-1"
}

# ECR Repository
resource "aws_ecr_repository" "app_repo" {
  name = "my-app-repo"
}

# IAM Role for Lambda
resource "aws_iam_role" "lambda_exec_role" {
  name = "lambda-ecr-deploy-role"
  assume_role_policy = jsonencode({
    "Version": "2012-10-17",
    "Statement": [
      {
        "Action": "sts:AssumeRole",
        "Effect": "Allow",
        "Principal": {
          "Service": "lambda.amazonaws.com"
        }
      }
    ]
  })
}

# Attach policies to the Lambda role
resource "aws_iam_role_policy_attachment" "attach_basic_exec" {
  role       = aws_iam_role.lambda_exec_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy_attachment" "attach_ecr_permissions" {
  role       = aws_iam_role.lambda_exec_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

# Create an EC2 instance
resource "aws_instance" "app_server" {
  ami           = "ami-0c55b159cbfafe1f0" # Example Amazon Linux 2 AMI
  instance_type = "t2.micro"
  key_name      = var.ec2_key_pair

  tags = {
    Name = "AppServer"
  }
}

# Create Lambda function
resource "aws_lambda_function" "ecr_deploy_lambda" {
  filename         = "lambda_deploy.zip"
  function_name    = "ECRDeployLambda"
  role             = aws_iam_role.lambda_exec_role.arn
  handler          = "lambda_function.lambda_handler"
  runtime          = "python3.9"
  timeout          = 30

  environment {
    variables = {
      EC2_INSTANCE_ID = aws_instance.app_server.id
    }
  }
}

# ECR Event Rule
resource "aws_cloudwatch_event_rule" "ecr_push_event" {
  event_pattern = jsonencode({
    "source": ["aws.ecr"],
    "detail-type": ["ECR Image Action"],
    "detail": {
      "action-type": ["PUSH"]
    }
  })
}

# Lambda Permission for Event Rule
resource "aws_lambda_permission" "allow_cloudwatch" {
  statement_id  = "AllowExecutionFromCloudWatch"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.ecr_deploy_lambda.arn
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.ecr_push_event.arn
}

# Target the Lambda function with the CloudWatch rule
resource "aws_cloudwatch_event_target" "lambda_target" {
  rule      = aws_cloudwatch_event_rule.ecr_push_event.name
  target_id = "ECRDeployLambda"
  arn       = aws_lambda_function.ecr_deploy_lambda.arn
}
