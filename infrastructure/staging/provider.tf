provider "aws" {
  region = var.aws_region

  # Service=team-tools on everything: core's tools-role lets this repository
  # create and change only what carries it.
  default_tags {
    tags = {
      Project     = var.project_name
      Environment = "staging"
      Service     = "team-tools"
      ManagedBy   = "terraform"
    }
  }
}
