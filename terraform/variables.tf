variable "name" {
  type        = string
  description = "リソース名の接頭辞"
  default     = "midsize"
}

variable "region" {
  type        = string
  description = "ワークロードのリージョン"
  default     = "ap-northeast-1"
}

variable "web_instance_type" {
  type    = string
  default = "t3.medium"
}

variable "app_instance_type" {
  type    = string
  default = "t3.medium"
}

variable "db_instance_class" {
  type    = string
  default = "db.t3.small"
}

variable "domain_name" {
  type        = string
  description = "空なら Route 53 レコードを作らない"
  default     = ""
}

variable "hosted_zone_id" {
  type        = string
  description = "空なら Route 53 レコードを作らない"
  default     = ""
}

variable "github_repository" {
  type        = string
  description = "CodePipeline の Source。GitHub の owner/repo"
}

variable "github_branch" {
  type        = string
  description = "追跡するブランチ"
  default     = "main"
}
