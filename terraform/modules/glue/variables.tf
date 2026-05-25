variable "name_prefix"         { type = string }
variable "environment"         { type = string }
variable "glue_role_arn"       { type = string }
variable "raw_bucket_name"     { type = string }
variable "staging_bucket_name" { type = string }
variable "glue_scripts_bucket" { type = string }
variable "worker_type"         { type = string; default = "G.1X" }
variable "num_workers"         { type = number; default = 2 }
variable "crawler_schedule"    { type = string; default = "" }
variable "log_group_name"      { type = string }
