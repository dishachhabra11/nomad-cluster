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
  address = "http://34.122.191.198:4646"
  region  = "us-central1"
}

provider "random" {
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

service_account {
    email  = "terraform@alfred-chainlake-staging.iam.gserviceaccount.com"
    scopes = ["cloud-platform"]
  }
  
  lifecycle {
  create_before_destroy = true
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

# Download and install Consul
curl -O https://releases.hashicorp.com/consul/1.17.3/consul_1.17.3_linux_amd64.zip
unzip consul_1.17.3_linux_amd64.zip
sudo mv consul /usr/local/bin/
sudo chmod +x /usr/local/bin/consul

# Create Consul directories
sudo mkdir -p /etc/consul.d /opt/consul
sudo chmod 777 /etc/consul.d /opt/consul

LOCAL_IP=$(curl -H "Metadata-Flavor: Google" http://metadata.google.internal/computeMetadata/v1/instance/network-interfaces/0/ip)



# Configure Consul client
cat <<EOT >/etc/consul.d/consul.hcl
datacenter = "us-central1"
data_dir   = "/opt/consul"
bind_addr = "{{ GetPrivateIP }}"
client_addr = "0.0.0.0"
retry_join = ["provider=gce tag_value=consul-server"]
ui = true
EOT

# Consul systemd service
cat <<EOT >/etc/systemd/system/consul.service
[Unit]
Description=Consul Agent
After=network.target

[Service]
ExecStart=/usr/local/bin/consul agent -config-dir=/etc/consul.d
Restart=always

[Install]
WantedBy=multi-user.target
EOT

systemctl daemon-reload
systemctl enable consul
systemctl start consul


cat <<EOT > /etc/nomad.d/server.hcl 

advertise {
  http = "$LOCAL_IP"
  rpc  = "$LOCAL_IP"
  serf = "$LOCAL_IP"
}

server {
  enabled          = true
  bootstrap_expect = 1
}

ui {
  enabled = true
}
consul {
  enabled = true
  address = ""
  auto_advertise = false
  server_auto_join = true
  client_auto_join = true

  server_service_name = "nomad-server"
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

 systemctl daemon-reload
    systemctl enable consul
    systemctl start consul

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
    ports    = ["4646", "4647" , "4648", "8500" , "8600" , "8301" , "8501" , "8300"]
  }

  allow {
    protocol = "udp"
    ports    = ["4647"]
  }

  target_tags = ["nomad-server" , "consul-server"]

  source_ranges = [
    "0.0.0.0/0"
  ]
}

resource "google_compute_firewall" "allow_internal_nomad" {
  name    = "allow-nomad-internal"
  network = "default"

  allow {
    protocol = "tcp"
    ports    = ["4646", "4647", "4648"]
  }
  allow {
    protocol = "udp"
    ports    = ["4648"]
  }

  # Allow all internal subnets to talk to each other
  source_ranges = ["10.128.0.0/9"] 
}

resource "google_compute_firewall" "client_firewall" {
  name    = "allow-lb-nomad-client"
  network = "default"

  allow {
    protocol = "tcp"
    ports    = ["4646","4000", "4001", "4002", "4003", "8001", "9090" , "3000" , "8500" , "8600" , "8301" , "8501"]
  }

  target_tags = ["nomad-client"]

  source_ranges = [
    "0.0.0.0/0"
  ]
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

lifecycle {
  create_before_destroy = true
}

  service_account {
    email  = "terraform@alfred-chainlake-staging.iam.gserviceaccount.com"
    scopes = ["cloud-platform"]
  }



  tags = ["nomad-client"]

  network_interface {
    network= "default"
    access_config {
    }
  }

    metadata_startup_script = <<-EOF
    #!/bin/bash

    # 1. DISK MOUNTING LOGIC
    # Identify the secondary disk (usually persistent-disk-1 in GCP)
    DISK_PATH="/dev/disk/by-id/google-persistent-disk-1"
    MOUNT_POINT="/mnt/greptime"

    # Wait for the device to be attached
    while [ ! -b $DISK_PATH ]; do
      echo "Waiting for disk $DISK_PATH..."
      sleep 2
    done

    # Create mount point
    mkdir -p $MOUNT_POINT

    # Format the disk only if it doesn't have a file system (prevents data loss)
    if [ -z "$(lsblk -f -n -o FSTYPE $DISK_PATH)" ]; then
      echo "Formatting disk $DISK_PATH..."
      mkfs.ext4 -m 0 -E lazy_itable_init=0,lazy_journal_init=0,discard $DISK_PATH
    fi

    # Mount the disk
    mount -o discard,defaults $DISK_PATH $MOUNT_POINT

    # Add to /etc/fstab so it mounts automatically on reboot
    if ! grep -qs "$MOUNT_POINT" /etc/fstab; then
      echo "$DISK_PATH $MOUNT_POINT ext4 discard,defaults,nofail 0 2" >> /etc/fstab
    fi

    # Set permissions for Nomad/Docker to write to it
    chmod 777 $MOUNT_POINT 

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

# THEN Nomad
sudo apt update -y && apt upgrade -y
sudo apt install -y unzip curl

curl -O https://releases.hashicorp.com/nomad/1.7.6/nomad_1.7.6_linux_amd64.zip
unzip nomad_1.7.6_linux_amd64.zip
sudo mv nomad /usr/local/bin/
sudo chmod +x /usr/local/bin/nomad

sudo mkdir -p /etc/nomad.d
sudo chmod 777 /etc/nomad.d


# Download and install Consul
curl -O https://releases.hashicorp.com/consul/1.17.3/consul_1.17.3_linux_amd64.zip
unzip consul_1.17.3_linux_amd64.zip
sudo mv consul /usr/local/bin/
sudo chmod +x /usr/local/bin/consul

# Create Consul directories
sudo mkdir -p /etc/consul.d /opt/consul
sudo chmod 777 /etc/consul.d /opt/consul



# 1. Get this client's local IP
LOCAL_IP=$(curl -H "Metadata-Flavor: Google" http://metadata.google.internal/computeMetadata/v1/instance/network-interfaces/0/ip)

# 2. Find the Server's Private IP using the 'nomad-server' tag
# This requires the VM Service Account to have "Compute Viewer" permissions
SERVER_IP=$(gcloud compute instances list --filter="tags.items=nomad-server" --format="value(networkInterfaces[0].networkIP)" --limit=1)


cat <<EOT > /etc/nomad.d/client.hcl
datacenter = "us-central1"  # Matches your Job Spec
region     = "us-central1"

advertise {
  http = "$LOCAL_IP"
  rpc  = "$LOCAL_IP"
  serf = "$LOCAL_IP"
}

client {
  enabled = true
  server_join {
    retry_join = ["provider=gce tag_value=nomad-server"]
  }

  # THIS IS THE KEY: Linking the physical mount to the Nomad volume name
  host_volume "greptime" {
    path      = "/mnt/greptime"
    read_only = false
  }
}



consul {
  enabled = true
  address = ""  # Or invalid address like "invalid:8500"
  auto_advertise = true
  client_auto_join = true
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

# Configure Consul client
cat <<EOT > /etc/consul.d/consul.hcl
datacenter = "us-central1"
data_dir   = "/opt/consul"
bind_addr = "{{ GetPrivateIP }}"
client_addr = "0.0.0.0"
retry_join = ["provider=gce tag_value=consul-server"]
ui = true
EOT

# Create systemd service
cat <<EOT > /etc/systemd/system/consul.service
[Unit]
Description=Consul Agent
After=network.target

[Service]
ExecStart=/usr/local/bin/consul agent -config-dir=/etc/consul.d
Restart=always

[Install]
WantedBy=multi-user.target
EOT
  systemctl daemon-reload
  systemctl enable consul
  systemctl start consul


    systemctl daemon-reload
    systemctl enable nomad
    systemctl start nomad
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

  target_size        = 2
  
  named_port {
    name = "nomad-ui-client"
    port = 4646
  }
}

resource "google_compute_firewall" "nomad_internal_traffic" {
  name    = "allow-nomad-internal-gossip"
  network = "default"

  allow {
    protocol = "tcp"
    ports    = ["4646", "4647", "4648"]
  }

  allow {
    protocol = "udp"
    ports    = ["4648"]
  }

  # Allow the internal VPC range to talk to itself
  source_ranges = ["10.128.0.0/9"] 
  target_tags   = ["nomad-server", "nomad-client"]
}

module "consul-server-template" {
  source = "./modules/instance_template/consul_server"
  name_prefix= "consul-server"
  machine_type= "e2-medium"
  region = "us-central1"
  image = "projects/ubuntu-os-cloud/global/images/family/ubuntu-2204-lts"
  tags= ["consul-server"]
}

module "consul-server-mig" {
  source               = "./modules/mig/consul_server"
  project_id           = "alfred-chainlake-staging"
  region               = "us-central1"
  name_prefix          = "consul-server"
  instance_template_id = module.consul-server-template.instance_template_id
  target_size          = 1
}

data "google_secret_manager_secret_version" "restic_password" { secret = "restic_password" }

data "google_secret_manager_secret_version" "aws_access_key_id" { secret = "restic_aws_access_key_id" }

data "google_secret_manager_secret_version" "aws_secret_access_key" { secret = "restic_aws_secret_access_key" }

data "google_secret_manager_secret_version" "restic_repository" { secret = "restic_repository" }


###--------- ssl certificates
locals {
  wazuh_secrets = {
    root_ca_public        = "root-ca_pem"
    root_ca_private       = "root-ca_key"
    master_public         = "master_pem"
    master_private        = "master-key_pem
    indexer_public        = "indexer1_pem"
    indexer_private       = "indexer1-key_pem"
    dashboard_public      = "dashboard_pem"
    dashboard_private     = "dashboard-key_pem"
    admin_public          = "admin_pem"
    admin_private         = "admin-key_pem"
    wazuh_api_password   = "wazuh_api_password"
    wazuh_indexer_password = "wazuh_indexer_password"
  }
}


data "google_secret_manager_secret_version" "wazuh_certs" {
  for_each = local.wazuh_secrets
  secret   = each.value
}


##----------  greptime job 

resource "nomad_job" "wazuh" {
  jobspec = templatefile("${path.module}/jobs/wazuh_cluster.nomad.tpl", {
    for k, v in data.google_secret_manager_secret_version.wazuh_certs :
    k => v.secret_data
  })
}



/*

resource "nomad_job" "greptime" {
  jobspec = file("${path.module}/jobs/greptime.nomad.hcl")
}
resource "nomad_job" "restic-exporter" {
   jobspec = templatefile("${path.module}/jobs/restic-exporter.nomad.tpl", {
  restic_password = data.google_secret_manager_secret_version.restic_password.secret_data
  aws_access_key  = data.google_secret_manager_secret_version.aws_access_key_id.secret_data
  aws_secret_key  = data.google_secret_manager_secret_version.aws_secret_access_key.secret_data
  restic_repository = data.google_secret_manager_secret_version.restic_repository.secret_data
})
}

resource "nomad_job" "grafana" {
  jobspec = file("${path.module}/jobs/grafana.nomad.hcl")
}

*/








