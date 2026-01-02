job "grafana" {
    datacenters = ["us-central1"]
    type = "service"

    group "grafana" {
     count = 1;

     network {
        port "http" {
            static = 3000
        }
     }
     task "grafana" {
        driver = "docker"

    config {
        image = "grafana/grafana:latest"
        ports = ["http"]
      }

      resources {
        cpu    = 300
        memory = 1024
      }
     }
     
    }
}