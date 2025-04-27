variable "region" {
  type    = string
  default = "us-east-1"
}

variable "cluster_identifier" {
  type    = string
  default = "aurora-pg-cluster"
}

variable "database_name" {
  type    = string
  default = "mydb"
}

variable "master_username" {
  type    = string
  default = "dbadmin"
}

variable "master_password" {
  type    = string
  default = "VerySecurePass123!"
}

variable "engine_version" {
  type    = string
  default = "15.3"
}

variable "parameter_group_family" {
  type    = string
  default = "aurora-postgresql15"
}

variable "instance_type" {
  type    = string
  default = "db.serverless"
}

variable "deletion_protection_enabled" {
  type    = bool
  default = false
}
