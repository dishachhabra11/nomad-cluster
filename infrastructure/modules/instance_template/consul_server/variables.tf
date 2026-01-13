variable "name_prefix" {
  description = "Prefix used for naming Consul server resources"
  type        = string
}

variable "machine_type" {
  description = "GCE machine type for Consul servers"
  type        = string
}

variable "region" {
  description = "GCP region where Consul servers will be deployed"
  type        = string
}

variable "image" {
  description = "Source image for the Consul server VM"
  type        = string
}

variable "tags" {
  description = "Network tags to attach to Consul server instances"
  type        = list(string)
}
