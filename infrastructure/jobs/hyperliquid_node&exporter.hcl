job "hyper-liquid" {
  datacenters = ["us-central1"]
  type        = "service"

  group "hyperliquid-group" {
    count = 1

   volume "hl-data" {
      type      = "host"
      read_only = false
      source    = "hl_shared_data"
    }
    network {

      port "p2p_4001" { static = 4001 }
      port "p2p_4002" { static = 4002 }
      port "p2p_4003" { static = 4003 }
      port "p2p_4004" { static = 4004 }
      port "p2p_4005" { static = 4005 }
      port "p2p_4006" { static = 4006 }
      port "p2p_4007" { static = 4007 }
      port "p2p_4008" { static = 4008 }
      port "p2p_4009" { static = 4009 }
      port "p2p_4010" { static = 4010 }
      port "p2p_3001" { static = 3001 }
      port "metrics" {
        static = 8086
        to     = 8086
      }
    }

    task "hl-docker-node" {
      driver = "docker"

      volume_mount {
        volume      = "hl-data"
        destination = "/home/hluser/hl" 
        read_only   = false
      }


      config {
        image = "disha029/hyperliquid-image"

        args = [
      "--serve-info",
      "--serve-eth-rpc",
      
    ]   
  # Mapping all ports from the range to the container

    ports = [
          "p2p_4001", "p2p_4002", "p2p_4003", "p2p_4004", "p2p_4005",
          "p2p_4006", "p2p_4007", "p2p_4008", "p2p_4009", "p2p_4010" , "p2p_3001"
        ]

      }

      resources {
        cpu    = 16000 # 16 vCPUs
        memory = 64000 # 64 GB RAM
      }

      service {

        name = "hyperliquid-node"
        port = "p2p_4001"
        check {
          type     = "tcp"
          interval = "20s"
          timeout  = "5s"

          check_restart {
            limit = 3
            grace = "5m" 
          }
        }
      }

    }



  task "hl-exporter" {
    driver = "docker"
    
    volume_mount {
      volume      = "hl-data"
      destination = "/hl" 
      read_only   = true  
    }

    config {
      image = "disha029/hl-exporter:latest"
      args = [
        "start",
        "--log-level=info",
        "--chain=Mainnet"
        "--replica-metrics=true"
      ]
      ports = ["metrics"]
    }

    resources {
      cpu    = 1000
      memory = 1024
    }

  }

    task "hl-pruner" {
    driver = "docker"

    volume_mount {
        volume      = "hl-data"
        destination = "/home/hluser"
        read_only   = false
    }

    config {
      image = "disha029/pruner-hl:latest"
    }

    resources {
      cpu    = 2000
      memory = 2048
    }
  }

  }
}



