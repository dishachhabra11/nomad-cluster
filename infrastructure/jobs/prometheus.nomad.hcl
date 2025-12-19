job "prometheus" {
  datacenters = ["us-central1"]
  type        = "service"

  group "prom" {
    count = 1

    network {
      port "web" {
        static = 9090
      }
    }

    task "prometheus" {
      driver = "docker"

      template {
        destination = "local/prometheus.yml"
        change_mode = "restart"

        data = <<EOF
global:
  scrape_interval: 15s

scrape_configs:
  - job_name: "nomad-server"
    metrics_path: /v1/metrics
    params:
      format: ["prometheus"]
    static_configs:
      - targets:
          - "10.128.0.21:4646"

remote_write:
  - url: "http://127.0.0.1:4000/v1/prometheus/write"
EOF
      }

      config {
        image   = "prom/prometheus:latest"
        ports   = ["web"]
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
