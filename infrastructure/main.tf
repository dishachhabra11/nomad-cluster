terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "7.13.0"
    }
    nomad = {
      source  = "hashicorp/nomad"
      version = "2.5.2"
    }
  }
}

provider "google" {
  project = "alfred-chainlake-staging"
  region  = "us-central1"
}

provider "nomad" {
  address = "http://34.72.43.127:4646"
  region  = "us-east-2"
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
  tags = ["nomad-server"]

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
    ports    = ["4646", "4647"]
  }

  target_tags = ["nomad-server"]

  source_ranges = [
    "0.0.0.0/0"
  ]
}

resource "google_compute_firewall" "client_firewall" {
  name    = "allow-lb-nomad"
  network = "default"

  allow {
    protocol = "tcp"
    ports    = ["4646"]
  }

  target_tags = ["nomad-client"]

  source_ranges = [
    "0.0.0.0/0"
  ]
}

##----------  greptime job 

resource "nomad_job" "greptime" {
  jobspec = file("${path.module}/jobs/greptime.nomad.hcl")
}

## ------------ nomad client instance_template

resource "google_compute_instance_template" "nomad-client-instance-template" {

  name_prefix = "nomad-client"
  machine_type  = "e2-medium"
  region        = "us-central1"

  disk{
   source = google_compute_region_disk.greptime_disk.name
   auto_delete = false
  }

  tags = ["nomad-client"]

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
     retry_join = ["provider=gce tag_value=nomad-server"]
    # replace with server private IP or DNS
  }
}

region        = "us-central1"

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


resource "google_compute_region_disk" "greptime_disk" {
  name          = "my-regional-disk"
  type          = "pd-balanced"
  region        = "us-central1"
  size          = 10
  
  # You must provide exactly two zones within the region
  replica_zones = [
    "us-central1-a",
    "us-central1-f"
  ]
}



