job "restic-exporter" {
  datacenters = ["us-central1"]
  type        = "service"

  group "restic-exporter-group" {
    count = 1

    network {
      port "metrics" {
        static = 8001
      }
    }

    task "restic-exporter-task" {
      driver = "docker"

      config {
        image = "ngosang/restic-exporter:latest"
        args  = [
          "--listen-port=8001"
        ]
      }

      env {
        TZ                   = "Asia/Kolkata"
        RESTIC_REPOSITORY    = "${restic_repository}"
        RESTIC_PASSWORD      = "${restic_password}"
        AWS_ACCESS_KEY_ID    = "${aws_access_key}"
        AWS_SECRET_ACCESS_KEY= "${aws_secret_key}"
        REFRESH_INTERVAL     = "3600"
      }

      resources {
        cpu    = 500
        memory = 256
      }

      volume_mount {
        volume      = "database-restic-data"
        destination = "/data"
        read_only   = false
      }

      service {
        name = "restic-exporter"
        port = "metrics"
        tags = ["metrics"]
      }
    }

    volume "database-restic-data" {
      type   = "host"
      source = "greptime"
    }
  }
}
