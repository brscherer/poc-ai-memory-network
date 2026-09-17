# Mirror of the upstream image. 30-images.sh pushes into it; pods pull the
# mirrored name, never docker.io.
resource "aws_ecr_repository" "ai_memory" {
  name                 = "mirror/ai-memory"
  image_tag_mutability = "IMMUTABLE"
  force_delete         = true

  image_scanning_configuration {
    scan_on_push = true
  }
}
