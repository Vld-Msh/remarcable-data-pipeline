variable "name_prefix" { type = string }
variable "admin_username" {
  type      = string
  sensitive = true
}
variable "admin_password" {
  type      = string
  sensitive = true
}
variable "base_capacity" {
  type    = number
  default = 8
}
variable "subnet_ids" { type = list(string) }
variable "security_group_ids" { type = list(string) }
variable "redshift_role_arn" { type = string }
variable "curated_bucket_arn" { type = string }
