provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project   = var.name
      ManagedBy = "terraform"
      Tier      = "three-tier"
    }
  }
}

# CloudFront 用 WAF は us-east-1 にしか作れない
provider "aws" {
  alias  = "useast1"
  region = "us-east-1"

  default_tags {
    tags = {
      Project   = var.name
      ManagedBy = "terraform"
      Tier      = "three-tier"
    }
  }
}
