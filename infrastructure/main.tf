terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "7.13.0"
    }
  }
}

provider "google" {
  project = "alfred-chainlake-staging"
  region  = "us-central1"
}

## --------------------------------------------------------------------------------------------------
## 2. Nomad Instance Template (for MIG)\

resource "google_compute_instance_template" "nomad_server" {
  name_prefix   = "nomad-server-template"
  machine_type  = "e2-medium"
  region              = "us-central1" 

  disk {
    source      = google_compute_region_disk.data_disk.self_link
    auto_delete  = false
    device_name = "data-disk-1" 
    boot         = true
  }

  network_interface {
    network = "default"
    access_config {

    }  
  }

  

  metadata_startup_script = <<-EOF
    #!/bin/bash
    apt update -y && apt upgrade -y
    apt install -y unzip curl

    curl -O https://releases.hashicorp.com/nomad/1.7.6/nomad_1.7.6_linux_amd64.zip
    unzip nomad_1.7.6_linux_amd64.zip
    mv nomad /usr/local/bin/
    chmod +x /usr/local/bin/nomad

    mkdir -p /etc/nomad.d
    chmod 777 /etc/nomad.d

    cat <<EOT > /etc/nomad.d/server.hcl
server {
  enabled          = true
  bootstrap_expect = 1
}

ui {
  enabled = true
}

bind_addr = "0.0.0.0"
data_dir = "/opt/nomad/data"
EOT

    mkdir -p /opt/nomad/data
    chmod 777 /opt/nomad/data

    cat <<EOT > /etc/systemd/system/nomad.service
[Unit]
Description=Nomad Server
After=network.target

[Service]
ExecStart=/usr/local/bin/nomad agent -config=/etc/nomad.d
Restart=always

[Install]
WantedBy=multi-user.target
EOT

    systemctl daemon-reload
    systemctl enable nomad
    systemctl start nomad
  EOF
}


## --------------------------------------------------------------------------------------------------
## 3. Managed Instance Group (MIG)
## --------------------------------------------------------------------------------------------------


 resource "google_compute_region_instance_group_manager" "nomad_mig" {
  name               = "nomad-mig"
  region             = "us-central1"
  version {
    instance_template = google_compute_instance_template.nomad_server.self_link
  }
  base_instance_name = "nomad"
  target_size        = 1
  auto_healing_policies {
    health_check      = google_compute_health_check.nomad_http.self_link
    initial_delay_sec = 300
  }
  named_port {
    name = "nomad-ui"
    port = 4646
  }

  stateful_disk {
    device_name = "data-disk-1"
  }

  stateful_external_ip {
    interface_name = "nic0"
  }
  update_policy {
  instance_redistribution_type = "NONE"
  type                        = "OPPORTUNISTIC"
}


 }


resource "google_compute_health_check" "nomad_http" {
  name               = "nomad-http-hc"
  check_interval_sec = 10
  timeout_sec        = 5
  healthy_threshold  = 1
  unhealthy_threshold= 3

  http_health_check {
    port = 4646
    request_path = "/v1/agent/self"
  }
}


## --------------backend service

resource "google_compute_backend_service" "nomad_backend" {
  name                  = "nomad-backend-test"
  protocol              = "HTTP"
  timeout_sec           = 10
  enable_cdn            = false
  port_name             = "nomad-ui"
  depends_on = [
    google_compute_health_check.nomad_http
  ]
  health_checks         = [google_compute_health_check.nomad_http.id]
  backend {
    group = google_compute_region_instance_group_manager.nomad_mig.instance_group
  }


}

## ---------------------- https load balancer


resource "google_compute_url_map" "nomad_lb_urlmap" {
  name            = "nomad-lb-urlmap"
  default_service = google_compute_backend_service.nomad_backend.self_link
   depends_on = [
    google_compute_backend_service.nomad_backend
  ]
}

resource "google_compute_target_http_proxy" "nomad_lb_proxy" {
  name    = "nomad-lb-proxy"
  url_map = google_compute_url_map.nomad_lb_urlmap.self_link
    depends_on = [
     google_compute_url_map.nomad_lb_urlmap
  ]
}

resource "google_compute_global_forwarding_rule" "nomad_lb_forwarding" {
  name       = "nomad-lb-forwarding"
  port_range = "80"
  target     = google_compute_target_http_proxy.nomad_lb_proxy.self_link
}


## ----------------------------- firewall

resource "google_compute_firewall" "nomad_lb_fw" {
  name    = "nomad-lb-fw"
  network = "default"

  allow {
    protocol = "tcp"
    ports    = ["4646"]
  }

## should be load balancer ip 

  source_ranges = ["0.0.0.0/0"]
}


## -------------------- disk
resource "google_compute_region_disk" "data_disk" {
  name   = "data-disk-1"
  region = "us-central1"
  size   = 50
  type   = "pd-balanced"

   replica_zones = [
    "us-central1-a",
    "us-central1-b"
  ]
}





