job "greptimedb" {
  datacenters = ["dc1"]
  type        = "service"

  group "db" {
    count = 1

    network {
        port "http" {
          static = 4000
        }
      }

    task "greptimedb" {
      driver = "docker"

      config {
        image = "greptime/greptimedb:v1.0.0-beta.3"
        args  = []
        ports = ["http"]
      }

      resources {
        cpu    = 500
        memory = 1024
      }

    }
  }
}
