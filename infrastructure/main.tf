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
  region        = "us-central1"

  disk {
    source_image = "projects/ubuntu-os-cloud/global/images/family/ubuntu-2204-lts"
    auto_delete  = true
    boot         = true
  }

  network_interface {
    network = "default"
    access_config {

    }  # Gives external IP (ephemeral)
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

telemetry {
  collection_interval        = "10s"
  prometheus_metrics         = true
  publish_allocation_metrics = true
  publish_node_metrics       = true
}

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
 resource "google_compute_instance_group_manager" "nomad_mig" {
  name               = "nomad-mig"
  zone               = "us-central1-a"
  base_instance_name = "nomad"
  target_size        = 1

  version {
    instance_template = google_compute_instance_template.nomad_server.self_link
  }

  named_port {
    name = "nomad-ui"
    port = 4646
  }
}


## ------------- health ceck for load balancer 

resource "google_compute_health_check" "nomad_http" {
  name = "nomad-hc"

  http_health_check {
    port         = 4646
    request_path = "/ui/"
  }
}


## --------------backend service





###--------------------------


## ----------------------------- firewall

resource "google_compute_firewall" "allow_lb_to_nomad" {
  name    = "allow-lb-nomad"
  network = "default"

  allow {
    protocol = "tcp"
    ports    = ["4646"]
  }

  source_ranges = [
    "0.0.0.0/0"
  ]
}

##----------  greptime job 

resource "nomad_job" "greptime" {
  jobspec = file("${path.module}/jobs/greptime.nomad.hcl")
}

## ------------ nomad client instance_template

resource "google_compute_instance_template" nomad-client-instance-template {

  name_prefix = "nomad-client"
  machine_type  = "e2-medium"
  region        = "us-central1"

  disk{
   source = "google_compute_disk.greptime_disk.self_link"
   auto_delete = false
  }
  network_interface {
    network= "default"
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

    cat <<EOT > /etc/nomad.d/client.hcl
client {
  enabled = true
  # Join the server
  server_join {
    retry_join = ["10.128.0.11/4646"] 
    # replace with server private IP or DNS
  }
}

bind_addr = "0.0.0.0"
data_dir  = "/opt/nomad/data"
EOT

    mkdir -p /opt/nomad/data
    chmod 777 /opt/nomad/data

    cat <<EOT > /etc/systemd/system/nomad.service
[Unit]
Description=Nomad Client
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



## ------------ greptime db volume 


resource "google_compute_disk" "greptime_disk" {
  name  = "greptime-data-disk"
  type  = "pd-standard"
  zone  = "us-central1-a"
  size  = 100  # GB
}




