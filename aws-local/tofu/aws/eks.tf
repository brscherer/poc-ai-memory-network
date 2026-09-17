# A minimal VPC so the cluster and hosts look like the real thing.
resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  tags                 = { Name = "ai-platform" }
}

resource "aws_subnet" "private" {
  for_each          = { a = "10.0.1.0/24", b = "10.0.2.0/24" }
  vpc_id            = aws_vpc.main.id
  cidr_block        = each.value
  availability_zone = "${var.region}${each.key}"
  tags              = { Name = "ai-platform-${each.key}" }
}

resource "aws_eks_cluster" "main" {
  name     = var.cluster_name
  role_arn = aws_iam_role.eks_cluster.arn

  vpc_config {
    subnet_ids = [for s in aws_subnet.private : s.id]
  }

  depends_on = [aws_iam_role.eks_cluster]
}
