job "greptimedb" {
  datacenters = ["us-central1"]
  type        = "service"

  group "db" {
    count = 1

    network {
      port "http"     { static = 4000 }
      port "rpc"      { static = 4001 }
      port "mysql"    { static = 4002 }
      port "postgres" { static = 4003 }
    }

    volume "database-data" {
      type      = "host"
      source    = "greptime"
      read_only = false
    }

    task "greptimedb" {
      driver = "docker"

      config {
        image   = "greptime/greptimedb:latest"
        ports   = ["http", "rpc", "mysql", "postgres"]
        command = "standalone"
        args = [
          "start",
          "--http-addr",       "0.0.0.0:4000",
          "--rpc-bind-addr",   "0.0.0.0:4001",
          "--mysql-addr",     "0.0.0.0:4002",
          "--postgres-addr",  "0.0.0.0:4003"
        ]
      }

      volume_mount {
        volume      = "database-data"
        destination = "/greptimedb_data"
        read_only   = false
      }

      resources {
        cpu    = 500
        memory = 1024
      }
    }
  }
}
