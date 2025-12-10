terraform {
  required_providers {
    google = {
      source = "hashicorp/google"
      version = "7.13.0"
    }
  }
}

provider "google" {
   project     = "alfred-chainlake-staging"
   region      = "us-central1"
}

module "nomad-lb-http" {
  source            = "GoogleCloudPlatform/lb-http/google"
  version           =  "14.0.0"

  project           = "alfred-chainlake-staging"
  name              = "nomad-group-http-lb"

  firewall_networks = ["default"]

  backends = {
    default = {
      port                            = 4646
      protocol                        = "HTTP"
      port_name                       = "nomad_ui"
      timeout_sec                     = 10
      enable_cdn                      = false


      log_config = {
        enable = true
        sample_rate = 1.0
      }

      groups = [
        {
          
          group                        = module.nomad_vm_mig.instance_group
        }
      ]

      iap_config = {
        enable               = false
      }
    }
  }
}


module "nomad_vm_mig" {
  source  = "terraform-google-modules/vm/google//modules/mig"
  version = "13.7.0"
  instance_template ="module.nomad_vm_instance_template.self_link"
  project_id= "alfred-chainlake-staging"
  region = "us-central1"
  mig_name="nomad_mig"
  min_replicas= 1
  target_size = 1

  named_ports = [{
    name = "nomad-ui"
    port = 4646
  }]

  # insert the 3 required variables here
}

module "nomad_vm_instance_template" {
  source  = "terraform-google-modules/vm/google//modules/instance_template"
  version = "13.7.0"
  project_id= "alfred-chainlake-staging"
  region = "us-central1"

  name_prefix  = "nomad-server-template"
  machine_type = "e2-medium"

  source_image_family  = "ubuntu-2204-lts"
  source_image_project = "ubuntu-os-cloud"

 network="default"



  startup_script =  <<-EOF
    #!/bin/bash

    # Update system
    apt update -y && apt upgrade -y

    # Install dependencies
    apt install -y unzip curl

    # Install Nomad

    curl -O https://releases.hashicorp.com/nomad/1.7.6/nomad_1.7.6_linux_amd64.zip
    unzip nomad_1.7.6_linux_amd64.zip
    mv nomad /usr/local/bin/
    chmod +x /usr/local/bin/nomad

    # Create config directory
    mkdir -p /etc/nomad.d
    chmod 777 /etc/nomad.d

    # Write Nomad server config
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

    # Create data directory
    mkdir -p /opt/nomad/data
    chmod 777 /opt/nomad/data

    # Create a systemd service so Nomad runs automatically
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

    # Start Nomad
    systemctl daemon-reload
    systemctl enable nomad
    systemctl start nomad
  EOF

  
}

