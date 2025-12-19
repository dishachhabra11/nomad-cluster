job "greptimedb" {
  datacenters = ["us-central1"]
  type        = "service"

  group "db" {
    count = 1

    network {
        port "http" {
          static = 4000
        }
      }

    volume "database-data" {
      type   = "host"
      source = "greptime" 
      read_only = false
    }

    task "greptimedb" {
      driver = "docker"

      config {
        image = "greptime/greptimedb:v1.0.0-beta.3"
        ports = ["http"]
        volumes = ["greptime:/greptimedb_data"]
      }

      resources {
        cpu    = 500
        memory = 1024
      }

    volume_mount {
     volume      = "database-data"
     destination = "/greptimedb"
     read_only   = false
}


    }
  }
}
