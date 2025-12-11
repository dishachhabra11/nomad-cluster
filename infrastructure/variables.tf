variable "project_id" {
  description = "The GCP project ID to deploy resources into"
  type        = string
}
variable "nomad_client_secret" {
  description = "oauth2_client_secret"
  type        = string
  sensitive = true
}

