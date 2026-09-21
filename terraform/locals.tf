locals {
  azs = {
    a = {
      az     = "ap-northeast-1a"
      public = "10.0.0.0/24"
      web    = "10.0.10.0/24"
      app    = "10.0.20.0/24"
      data   = "10.0.30.0/24"
    }
    c = {
      az     = "ap-northeast-1c"
      public = "10.0.1.0/24"
      web    = "10.0.11.0/24"
      app    = "10.0.21.0/24"
      data   = "10.0.31.0/24"
    }
  }

  create_dns = var.domain_name != "" && var.hosted_zone_id != ""
}
