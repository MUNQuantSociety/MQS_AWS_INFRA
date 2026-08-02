###############################################################################
# Image repository for the visualizer backend.
#
# Unlike MQS_AWS_INFRA's ecr-repository module -- which adopts the pre-existing
# `livetradingbot` repository through a data source -- this one CREATES the
# repository, because the visualizer has never been built or pushed.
#
# If a repository of this name already exists in the account, the first apply
# fails with RepositoryAlreadyExistsException. In that case either pick a
# different repository_name or import it:
#   terraform import module.ecr_repository.aws_ecr_repository.this <repo-name>
###############################################################################

resource "aws_ecr_repository" "this" {
  name = var.repository_name

  # MUTABLE so CI can move a floating tag; the root module still deploys a
  # pinned tag rather than "latest".
  image_tag_mutability = var.image_tag_mutability

  image_scanning_configuration {
    scan_on_push = var.scan_on_push
  }

  encryption_configuration {
    encryption_type = "AES256"
  }
}

resource "aws_ecr_lifecycle_policy" "this" {
  repository = aws_ecr_repository.this.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Keep last ${var.tagged_image_retention_count} tagged images"
        selection = {
          tagStatus      = "tagged"
          tagPatternList = ["*"]
          countType      = "imageCountMoreThan"
          countNumber    = var.tagged_image_retention_count
        }
        action = { type = "expire" }
      },
      {
        rulePriority = 2
        description  = "Expire untagged images after ${var.untagged_image_retention_days} days"
        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = var.untagged_image_retention_days
        }
        action = { type = "expire" }
      }
    ]
  })
}
