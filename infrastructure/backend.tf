terraform {
  backend "gcs" {
    bucket  = "my-nomad-tf-bucket"
  }
}