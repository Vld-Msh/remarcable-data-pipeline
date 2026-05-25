variable "name_prefix" {
  description = "Prefix applied to all bucket names (e.g. remarcable-dev)."
  type        = string
}

variable "environment" {
  description = "Deployment environment for tagging."
  type        = string
}

variable "force_destroy" {
  description = "Allow Terraform to destroy non-empty buckets."
  type        = bool
  default     = false
}
