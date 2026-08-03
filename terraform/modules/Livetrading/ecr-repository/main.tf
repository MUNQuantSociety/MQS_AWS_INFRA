###############################################################################
# The image repository predates this Terraform config, so it is adopted rather
# than created: creating it would fail with RepositoryAlreadyExistsException.
#
# Consequence of using a data source: Terraform does NOT manage the repository's
# own settings (scan_on_push, encryption, tag mutability). Those stay whatever
# they were set to out-of-band. Only the lifecycle policy below is managed here.
#
# To bring the repository fully under Terraform instead, replace this with the
# original `resource "aws_ecr_repository" "this"` and run:
#   terraform import module.ecr_repository.aws_ecr_repository.this <repo-name>
###############################################################################

data "aws_ecr_repository" "this" {
  name = var.repository_name
}

# Additive: the repository carried no lifecycle policy before this config, so
# applying it expires nothing that exists today (3 images vs a retention of 10).
resource "aws_ecr_lifecycle_policy" "this" {
  repository = data.aws_ecr_repository.this.name

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
