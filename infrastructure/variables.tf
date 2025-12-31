variable "project_id" {
  description = "The GCP project ID to deploy resources into"
  type        = string
  default    = "
}

variable "restic_password" {
  type      = string
  sensitive = true
}

variable "aws_access_key" {
  type      = string
  sensitive = true
}

variable "aws_secret_key" {
  type      = string
  sensitive = true
}

variable "restic_repository" {
  type    = string
  default = "s3:s3.amazonaws.com/your-bucket-name"  # optional default
}
