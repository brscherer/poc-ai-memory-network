# Every AWS service used here is pointed at floci. Against real AWS this
# whole block collapses to `provider "aws" { region = var.region }`.
provider "aws" {
  region     = var.region
  access_key = "test"
  secret_key = "test"

  skip_credentials_validation = true
  skip_metadata_api_check     = true
  skip_requesting_account_id  = true
  s3_use_path_style           = true

  endpoints {
    ec2            = var.aws_endpoint
    ecr            = var.aws_endpoint
    eks            = var.aws_endpoint
    iam            = var.aws_endpoint
    s3             = var.aws_endpoint
    secretsmanager = var.aws_endpoint
    sts            = var.aws_endpoint
  }

  default_tags {
    tags = {
      Project = "ai-memory-poc"
      Managed = "opentofu"
    }
  }
}
