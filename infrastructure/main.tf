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
  address = "http://34.69.184.157:4646"
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

consul {
  enabled = false
}
region = "us-central1" 

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
  name    = "allow-lb-nomad-server"
  network = "default"

  allow {
    protocol = "tcp"
    ports    = ["4646", "4647" , "4648"]
  }

  allow {
    protocol = "udp"
    ports    = ["4647"]
  }

  target_tags = ["nomad-server"]

  source_ranges = [
    "0.0.0.0/0"
  ]
}

resource "google_compute_firewall" "client_firewall" {
  name    = "allow-lb-nomad-client"
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

resource "google_compute_instance_template" "nomad-client-instance-template1" {

  name_prefix = "nomad-client"
  machine_type  = "e2-medium"
  region        = "us-central1"

  disk {
    source_image = "projects/ubuntu-os-cloud/global/images/family/ubuntu-2204-lts"
    auto_delete  = true
    boot         = true
  }

 disk {
  boot         = false
  auto_delete  = true
  type         = "pd-ssd"
  disk_size_gb = 12  # Match your greptime_disk size
  disk_type    = "pd-ssd"

}


  tags = ["nomad-client"]

  network_interface {
    network= "default"
    access_config {
    }
  }

    metadata_startup_script = <<-EOF
    #!/bin/bash

# Install Docker FIRST
sudo apt-get update
sudo apt-get install -y ca-certificates curl gnupg
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc

echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

sudo apt-get update
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
sudo systemctl start docker
sudo systemctl enable docker

# MOUNT GREPTIME DISK (NEW SECTION)
DISK="/dev/sdb"
MOUNT="/mnt/greptime"

# Wait for disk to be available
for i in {1..30}; do
  if [ -b "$DISK" ]; then
    echo "Disk $DISK found"
    break
  fi
  echo "Waiting for $DISK... ($i/30)"
  sleep 2
done

if [ ! -b "$DISK" ]; then
  echo "ERROR: Disk $DISK not found - check template config"
  exit 1
fi

# Format if empty (idempotent - skips if filesystem exists)
if ! blkid "$DISK" > /dev/null 2>&1; then
  echo "Formatting $DISK with ext4..."
  sudo mkfs.ext4 -F "$DISK"
fi

# Create mount point, mount, and set permissions
sudo mkdir -p "$MOUNT"
sudo mount "$DISK" "$MOUNT"
sudo chown -R 1000:1000 "$MOUNT"  # Docker/nomad user
sudo chmod 755 "$MOUNT"

# Add to fstab for persistence (using UUID)
UUID=$(sudo blkid -s UUID -o value "$DISK")
echo "UUID=$UUID $MOUNT ext4 defaults,nofail 0 2" | sudo tee -a /etc/fstab

echo "GreptimeDB volume mounted at $MOUNT"

# THEN Nomad
sudo apt update -y && apt upgrade -y
sudo apt install -y unzip curl

curl -O https://releases.hashicorp.com/nomad/1.7.6/nomad_1.7.6_linux_amd64.zip
unzip nomad_1.7.6_linux_amd64.zip
sudo mv nomad /usr/local/bin/
sudo chmod +x /usr/local/bin/nomad

sudo mkdir -p /etc/nomad.d
sudo chmod 755 /etc/nomad.d  # Fixed: was 777 (security issue)

cat <<EOT > /etc/nomad.d/client.hcl

client {
  enabled = true

  server_join {
    retry_join = ["10.128.0.21"]
  }

  drivers = ["docker"]

host_volume "greptime" {
  path      = "/mnt/greptime"
  read_only = false
}
}

region = "us-central1" 

consul {
  enabled = false
}



bind_addr = "0.0.0.0"
data_dir  = "/opt/nomad/data"
EOT

mkdir -p /opt/nomad/data
chmod 755 /opt/nomad/data  # Fixed: was 777

cat <<EOT > /etc/systemd/system/nomad.service
[Unit]
Description=Nomad Client
After=network.target

[Service]
ExecStart=/usr/local/bin/nomad agent -config=/etc/nomad.d
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOT

systemctl daemon-reload
systemctl enable nomad
systemctl start nomad

echo "Nomad client started with GreptimeDB volume at /mnt/greptime"

  EOF

depends_on = [google_compute_region_disk.greptime_disk]

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


##-------- instance group maanager


resource "google_compute_region_instance_group_manager" "nomad_mig" {
  name               = "nomad-mig"
  region             = "us-central1"
  version {
    instance_template = google_compute_instance_template.nomad_server.self_link
  }

  base_instance_name = "nomad"
  target_size        = 1
  
  named_port {
    name = "nomad-ui"
    port = 4646
  }
}

resource "google_compute_region_instance_group_manager" "nomad_mig_client" {
  name               = "nomad-mig-client"
  region             = "us-central1"
  version {
    instance_template = google_compute_instance_template.nomad-client-instance-template1.self_link
  }
  base_instance_name = "nomad-client"

  distribution_policy_zones      = [
    "us-central1-a",
    "us-central1-f"
  ]
  target_size        = 1
  
  named_port {
    name = "nomad-ui-client"
    port = 4646
  }
  depends_on = [google_compute_region_disk.greptime_disk]
}



