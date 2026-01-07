job "wazuh" {
  datacenters = ["dc1"]
  type = "service"

  constraint {
    attribute = "$${node.unique.name}"
    value     = "worker-01"
  }

  group "wazuh-indexer" {
    count = 1
    
 
    network {
        mode = "host" 
      port "indexer" {
        static = 9200
        to     = 9200
      }
    }

    task "indexer" {
      driver = "docker"

      config {
        image = "wazuh/wazuh-indexer:4.14.1"
        
        ports = ["indexer"]
        
        hostname = "wazuh.indexer"

      cap_add = ["IPC_LOCK"]

      }

      volume_mount {
        volume      = "wazuh-indexer-data"
        destination = "/var/lib/wazuh-indexer"
      }

      env {
        OPENSEARCH_JAVA_OPTS = "-Xms1g -Xmx1g"
      }

      # Template for SSL certificates
      

# Root CA
template {
  destination = "local/usr/share/wazuh-indexer/config/certs/root-ca.pem"
  perms       = "644"
  data        = "${root_ca_public}"
}

# Indexer certificate (public)
template {
  destination = "local/usr/share/wazuh-indexer/config/certs/indexer.pem"
  perms       = "644"
  data        = "${indexer_public}"
}

# Indexer private key
template {
  destination = "local/usr/share/wazuh-indexer/config/certs/indexer-key.pem"
  perms       = "600"
  data        = "${indexer_private}"
}

# Admin certificate (optional)
template {
  destination = "local/usr/share/wazuh-indexer/config/certs/admin.pem"
  perms       = "644"
  data        = "${admin_public}"
}

# Admin private key (optional)
template {
  destination = "local/usr/share/wazuh-indexer/config/certs/admin-key.pem"
  perms       = "600"
  data        = "${admin_private}"
}



# Configuration files

    template {
  destination = "local/config/opensearch.yml"
  perms       = "600"
     data        = <<EOF
${opensearch_yml}
EOF
}

# Internal users config
template {
  destination = "local/config/opensearch-security/internal_users.yml"
  perms       = "644"
  data        = ${internal_users_yml }
}

      resources {
        cpu    = 1000
        memory = 2048
      }

      service {
        name = "wazuh-indexer"
        port = "indexer"
        
        check {
          type     = "tcp"
          interval = "10s"
          timeout  = "2s"
        }
      }
    }
  }

  group "wazuh-manager" {
    count = 1

    network {
      mode = "host" 
      port "agent" {
        static = 1514
        to     = 1514
      }
      port "agent_cluster" {
        static = 1515
        to     = 1515
      }
      port "syslog" {
        static = 514
        to     = 514
      }
      port "api" {
        static = 55000
        to     = 55000
      }
    }

    volume "wazuh-api-configuration" {
      type      = "host"
      source    = "greptime/wazuh/wazuh-api-configuration"
      read_only = false
    }

    volume "wazuh-etc" {
      type      = "host"
      source    = "greptime/wazuh/wazuh-etc"
      read_only = false
    }

    volume "wazuh-logs" {
      type      = "host"
      source    = "greptime/wazuh/wazuh-logs"
      read_only = false
    }

    volume "wazuh-queue" {
      type      = "host"
      source    = "greptime/wazuh/wazuh-queue"
      read_only = false
    }
/*
    volume "wazuh-var-multigroups" {
      type      = "host"
      source    = "greptime/wazuh/wazuh-var-multigroups"
      read_only = false
    }
  */

    volume "filebeat-etc" {
      type      = "host"
      source    = "greptime/wazuh/filebeat-etc"
      read_only = false
    }

    volume "filebeat-var" {
      type      = "host"
      source    = "greptime/wazuh/filebeat-var"
      read_only = false
    }

    

    task "manager" {
      driver = "docker"

      config {
        privileged = true

        image = "wazuh/wazuh-manager:4.14.1"
        
        ports = ["agent", "agent_cluster", "syslog", "api"]

        cap_add = ["IPC_LOCK"]
        
        hostname = "wazuh.manager"

      }

      env {
        INDEXER_URL = "https://127.0.0.1:9200"
        INDEXER_USERNAME = "admin"
        FILEBEAT_SSL_VERIFICATION_MODE = "full"
        SSL_CERTIFICATE_AUTHORITIES = "/var/ossec/local/ssl/root-ca.pem"
        SSL_CERTIFICATE = "/var/ossec/local/ssl/filebeat.pem"
        SSL_KEY = "/var/ossec/local/ssl/filebeat.key"
        API_USERNAME = "wazuh-wui"
        API_PASSWORD="MyS3cr37P450r.*-"

      }

    # SSL Certificates
     # Root CA
template {
  destination = "/var/ossec/local/ssl/root-ca.pem"
  perms       = "644"
  data        = "${root_ca_public}"
}

# Manager cert
template {
  destination = "/var/ossec/local/ssl/filebeat.pem"
  perms       = "644"
  data        = "${master_public}"
}

# Manager key
template {
  destination = "/var/ossec/local/ssl/filebeat.key"
  perms       = "600"
  data        = "${master_private}"
}


  # Wazuh Manager config
template {
  destination = "local/wazuh-config/ossec.conf"
  perms       = "644"
   data        = <<EOF
${wazuh_manager_conf}
EOF
}

# Secrets for API & Indexer (env file)
template {
  destination = "secrets/file.env"
  perms       = "600"
  env         = true
  data        = <<EOF
INDEXER_PASSWORD=${wazuh_indexer_password}
API_PASSWORD=${wazuh_api_password}
EOF
}

      resources {
        cpu    = 2000
        memory = 4096
      }

      service {
        name = "wazuh-manager"
        port = "api"
        
        check {
          type     = "tcp"
          interval = "10s"
          timeout  = "2s"
        }
      }
    }
  }

  group "wazuh-dashboard" {
    count = 1

    network {
    mode = "host" 
      port "dashboard" {
        static = 443
        to     = 5601
      }
    }

    volume "wazuh-dashboard-config" {
      type      = "host"
      source    = "greptime/wazuh/wazuh-dashboard-config"
      read_only = false
    }

    volume "wazuh-dashboard-custom" {
      type      = "host"
      source    = "greptime/wazuh/wazuh-dashboard-custom"
      read_only = false
    }

    task "dashboard" {
      driver = "docker"

      config {
        privileged = true

        image = "wazuh/wazuh-dashboard:4.14.1"
        
        ports = ["dashboard"]
        
        hostname = "wazuh.dashboard"
      }

      volume_mount {
        volume      = "wazuh-dashboard-config"
        destination = "/usr/share/wazuh-dashboard/data/wazuh/config"
      }

      volume_mount {
        volume      = "wazuh-dashboard-custom"
        destination = "/usr/share/wazuh-dashboard/plugins/wazuh/public/assets/custom"
      }

      env {
        INDEXER_USERNAME = "admin"
        WAZUH_API_URL = "https://127.0.0.1"
        DASHBOARD_USERNAME = "kibanaserver"
        DASHBOARD_PASSWORD = "kibanaserver"
        API_USERNAME = "wazuh-wui"
      }

      # SSL Certificates
     
     # Dashboard certificate
template {
  destination = "/usr/share/wazuh-dashboard/config/certs/wazuh-dashboard.pem"
  perms       = "644"
  data        = "${dashboard_public}"
}

# Dashboard key
template {
  destination = "/usr/share/wazuh-dashboard/config/certs/wazuh-dashboard-key.pem"
  perms       = "600"
  data        = "${dashboard_private}"
}

# Root CA (used by Dashboard)
template {
  destination = "/usr/share/wazuh-dashboard/config/certs/root-ca.pem"
  perms       = "644"
  data        = "${root_ca_public}"
}


      # Configuration files
       # Wazuh Dashboard config
template {
  destination = "local/wazuh-config/wazuh.yml"
  perms       = "644"
  data        = <<EOF
${wazuh_yml}
EOF
}

# OpenSearch Dashboards config
  template {
  destination = "local/config/opensearch_dashboards.yml"
  perms       = "644"
  data        = <<EOF
${opensearch_dashboards_yml}
EOF
}


      resources {
        cpu    = 1000
        memory = 2048
      }

      service {
        name = "wazuh-dashboard"
        port = "dashboard"
        
        check {
          type     = "http"
          path     = "/app/login"
          interval = "10s"
          timeout  = "2s"
          protocol = "https"
          tls_skip_verify = true
        }
      }
    }
  }
}