job "restic-exporter" {
  datacenters = ["us-central1"]
  type        = "service"

  group "restic-exporter-group" {
    count = 1

    network {

      port "http" {
        static = 8001
      }
      port "prometheus" {
        static = 9090
      }
    }

    volume "database-restic-data" {
      type      = "host"
      source    = "greptime"
      read_only = false
    }

    # Restic Exporter Task
    task "restic-exporter-task" {
      driver = "docker"

      config {
        image   = "ngosang/restic-exporter"
        ports   = ["http"]
      }

      env {
        TZ                      = "Asia/Kolkata"
        RESTIC_REPOSITORY       = "${restic_repository}"
        RESTIC_PASSWORD         = "${restic_password}"
        AWS_ACCESS_KEY_ID       = "${aws_access_key}"
        AWS_SECRET_ACCESS_KEY   = "${aws_secret_key}"
        GREPTIME_DB             = "public"
        GREPTIME_USER           = "greptimedb"
        GREPTIME_PASSWORD       = "deqode@123"
        GREPTIME_HOST           = "http://34.30.60.136:4000" 
        AWS_DEFAULT_REGION      = "ap-south-1"
        REFRESH_INTERVAL        = "3600"
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

      service {
        name = "restic-exporter"
        port = "http"
        tags = ["metrics"]
        
        check {
          type     = "http"
          path     = "/metrics"
          interval = "30s"
          timeout  = "5s"
        }
      }
    }

    # Prometheus Sidecar Task
    task "prometheus-task" {
      driver = "docker"

      lifecycle {
        hook    = "poststart"
        sidecar = true
      }

      config {
        image = "prom/prometheus:latest"
        ports = ["prometheus"]
        
        volumes = [
          "local/prometheus.yml:/etc/prometheus/prometheus.yml"
        ]
        
        args = [
          "--config.file=/etc/prometheus/prometheus.yml",
          "--storage.tsdb.path=/prometheus",
          "--web.console.libraries=/usr/share/prometheus/console_libraries",
          "--web.console.templates=/usr/share/prometheus/consoles"
        ]
      }

      # Prometheus configuration
      template {
        data = <<EOF
global:
  scrape_interval: 60s
  evaluation_interval: 60s

scrape_configs:
  - job_name: 'restic-exporter'
    metrics_path: '/metrics'
    static_configs:
      - targets: ['34.30.60.136:8001']
        labels:
          instance: 'restic-backup'

remote_write:
  - url: http://34.30.60.136:4000/v1/prometheus/write?db=public
    basic_auth:
      username: greptimedb
      password: deqode@123
    queue_config:
      capacity: 10000
      max_shards: 10
      min_shards: 1
      max_samples_per_send: 5000
      batch_send_deadline: 5s
      min_backoff: 30ms
      max_backoff: 100ms
EOF
        destination = "local/prometheus.yml"
        change_mode = "restart"
      }

      resources {
        cpu    = 256
        memory = 512
      }
    }
  }
}