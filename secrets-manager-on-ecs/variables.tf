# variables.tf

variable "aws_region" {
  description = "aws region"
  type        = string
  default     = "ap-northeast-1"
}

variable "project_name" {
  description = "project name"
  type        = string
  default     = "secrets-manager-on-ecs"
}

variable "db_password" {
  description = "rds db pass"
  type        = string
  default     = "password2han2on"
  sensitive   = true
}

variable "db_username" {
  description = "RDS db user"
  type        = string
  default     = "handson"
}

variable "db_name" {
  description = "RDS DB name"
  type        = string
  default     = "handson"
}

variable "db_instance_type" {
  description = "RDS db instance type"
  type        = string
  default     = "db.t3.micro"
}

variable "my_ip" {
  description = "allow my pc access to aws resources"
  type        = string
}
