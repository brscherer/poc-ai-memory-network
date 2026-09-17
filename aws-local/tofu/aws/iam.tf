# A named admin identity: floci's EKS token webhook rejects the shared
# test/test keys, and every later step authenticates as this user.
resource "aws_iam_user" "admin" {
  name          = "poc-admin"
  force_destroy = true
}

resource "aws_iam_user_policy_attachment" "admin" {
  user       = aws_iam_user.admin.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

resource "aws_iam_access_key" "admin" {
  user = aws_iam_user.admin.name
}

resource "aws_iam_role" "eks_cluster" {
  name = "eks-cluster"
  assume_role_policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [{ Effect = "Allow", Principal = { Service = "eks.amazonaws.com" }, Action = "sts:AssumeRole" }]
  })
}

# EC2 hosts may read only their own credentials and the release artifacts.
resource "aws_iam_role" "ai_host" {
  name = "ai-host"
  assume_role_policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [{ Effect = "Allow", Principal = { Service = "ec2.amazonaws.com" }, Action = "sts:AssumeRole" }]
  })
}

resource "aws_iam_role_policy" "ai_host" {
  name = "read-own-secrets-and-artifacts"
  role = aws_iam_role.ai_host.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = "secretsmanager:GetSecretValue"
        Resource = ["arn:aws:secretsmanager:*:*:secret:ai-gateway/hosts/*", "arn:aws:secretsmanager:*:*:secret:ai-memory/hosts/*"]
      },
      {
        Effect   = "Allow"
        Action   = "s3:GetObject"
        Resource = "${aws_s3_bucket.artifacts.arn}/ai-memory/*"
      },
    ]
  })
}

resource "aws_iam_instance_profile" "ai_host" {
  name = "ai-host"
  role = aws_iam_role.ai_host.name
}
