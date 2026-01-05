resource "google_compute_instance_template" "consul-server-instance-template1" {

  name_prefix  = var.name_prefix
  machine_type = var.machine_type
  region       = var.region

  disk {
    source_image = var.image
    auto_delete  = true
    boot         = true
  }

  disk {
    boot         = false
    auto_delete  = true
    type         = "pd-ssd"
    disk_size_gb = 12
  }

  lifecycle {
    create_before_destroy = true
  }
  
  tags = var.tags

  network_interface {
    network = "default"
    access_config {}
  }

  metadata_startup_script = <<-EOF
  #!/bin/bash

  ############################
  # Disk Mount
  ############################
  DISK_PATH="/dev/disk/by-id/google-persistent-disk-1"
  MOUNT_POINT="/mnt/consul"

  while [ ! -b $DISK_PATH ]; do sleep 2; done
  mkdir -p $MOUNT_POINT

  if [ -z "$(lsblk -f -n -o FSTYPE $DISK_PATH)" ]; then
    mkfs.ext4 $DISK_PATH
  fi

  mount $DISK_PATH $MOUNT_POINT
  echo "$DISK_PATH $MOUNT_POINT ext4 defaults,nofail 0 2" >> /etc/fstab
  chmod 777 $MOUNT_POINT

  ############################
  # Install Consul
  ############################
  apt-get update -y
  apt-get install -y unzip curl

  curl -O https://releases.hashicorp.com/consul/1.17.2/consul_1.17.2_linux_amd64.zip
  unzip consul_1.17.2_linux_amd64.zip
  mv consul /usr/local/bin/
  chmod +x /usr/local/bin/consul

  mkdir -p /etc/consul.d /opt/consul
  chmod 777 /etc/consul.d /opt/consul

  LOCAL_IP=$(curl -H "Metadata-Flavor: Google" \
    http://metadata.google.internal/computeMetadata/v1/instance/network-interfaces/0/ip)

  ############################
  # Consul Server Config
  ############################
  cat <<EOT > /etc/consul.d/server.hcl
  server           = true
  datacenter       = "us-central1"
  data_dir         = "/opt/consul"
  bind_addr        = "$LOCAL_IP"
  advertise_addr   = "$LOCAL_IP"
  retry_join       = ["provider=gce tag_value=consul-server"]
  bootstrap_expect = 1
  ui_config {
    enabled = true
  }
  EOT

  ############################
  # Consul systemd
  ############################
  cat <<EOT > /etc/systemd/system/consul.service
  [Unit]
  Description=Consul Server
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
  EOF

}
