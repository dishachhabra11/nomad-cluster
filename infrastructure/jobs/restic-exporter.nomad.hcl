job "restic-exporter" {
  datacenters = ["us-central1"]
  type        = "service"

  group "restic-exporter-group" {
    count = 1

    network {
      port "http" {
        static = 8001
      }
    }

    volume "database-restic-data" {
      type      = "host"
      source    = "greptime"
      read_only = false
    }

    # -------------------------------
    # RESTIC EXPORTER
    # -------------------------------
    task "restic-exporter-task" {
      driver = "docker"

      config {
        image = "disha029/prometheous-exporter:latest"
        ports = ["http"]
      }

      env {
        TZ                    = "Asia/Kolkata"
        RESTIC_REPOSITORY     = "${restic_repository}"
        RESTIC_PASSWORD       = "${restic_password}"
        AWS_ACCESS_KEY_ID     = "${aws_access_key}"
        AWS_SECRET_ACCESS_KEY = "${aws_secret_key}"
        AWS_DEFAULT_REGION    = "ap-south-1"
        REFRESH_INTERVAL      = "3600"
      }

      resources {
        cpu    = 500
        memory = 1024
      }

      volume_mount {
        volume      = "database-restic-data"
        destination = "/data"
        read_only   = false
      }
    }

    # -------------------------------
    # PROMETHEUS CONFIG
    # -------------------------------
    template {
      destination = "local/prometheus.yml"
      data = <<EOF
global:
  scrape_interval: 15s

scrape_configs:
  - job_name: "restic-exporter"
    static_configs:
      - targets: ["localhost:8001"]

remote_write:
  - url: "http://34.30.60.136:4000/v1/prometheus/write?db=public"
    basic_auth:
      username: "greptimedb"
      password: "deqode@123"
EOF
    }

    # -------------------------------
    # PROMETHEUS SIDECAR
    # -------------------------------
    task "prometheus-task" {
      driver = "docker"

      config {
        image = "prom/prometheus:v2.49.1"
        args = [
          "--config.file=/etc/prometheus/prometheus.yml",
          "--storage.tsdb.path=/prometheus"
        ]
        volumes = [
          "local/prometheus.yml:/etc/prometheus/prometheus.yml"
        ]
      }

      resources {
        cpu    = 300
        memory = 512
      }
    }
  }
}
