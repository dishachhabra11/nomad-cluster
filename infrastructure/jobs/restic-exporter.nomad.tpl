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

    task "restic-exporter-task" {
      driver = "docker"

      config {
        image   = "ngosang/restic-exporter:latest"
        ports   = ["http"]
        command = "standalone"
      }

      env {
        TZ                      = "Asia/Kolkata"
        RESTIC_REPOSITORY       = "${restic_repository}"
        RESTIC_PASSWORD         = "${restic_password}"
        AWS_ACCESS_KEY_ID       = "${aws_access_key}"
        AWS_SECRET_ACCESS_KEY   = "${aws_secret_key}"
        AWS_DEFAULT_REGION      = "ap-south-1"
        REFRESH_INTERVAL        = "3600"
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
    }
  }
}
