resource "random_id" "mig_suffix" {
  byte_length = 4
}

resource "google_compute_region_instance_group_manager" "consul-server-mig" {
  project             = var.project_id
  name                = "consul-server-mig-${random_id.mig_suffix.hex}"
  region              = var.region
  base_instance_name  = var.name_prefix
  version {
    instance_template = var.instance_template_id
  }
  target_size = var.target_size

  lifecycle {
    create_before_destroy = true
  }


  # Optional autoscaling block can be added later
}
