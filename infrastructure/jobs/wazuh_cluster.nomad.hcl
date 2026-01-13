job "wazuh" {
  datacenters = ["dc1"]
  type = "service"

  constraint {
    attribute = "${node.unique.name}"
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

    volume "wazuh-indexer-data" {
      type      = "host"
      source    = "greptime/wazuh/indexer_data"
      read_only = false
    }

    task "indexer" {
      driver = "docker"

      config {
        image = "wazuh/wazuh-indexer:4.14.1"
        
        ports = ["indexer"]
        
        hostname = "wazuh.indexer"

        mount {
          type   = "bind"
          source = "local/wazuh/certs"
          target = "/usr/share/wazuh-indexer/config/certs"
          readonly = true
        }

        mount {
          type   = "bind"
          source = "local/wazuh/certs"
          target = "/usr/share/wazuh-indexer/config"
          readonly = false
        }

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
      template {
        data = <<EOF
{{ with nomadVar "nomad/jobs/wazuh/certs" }}
{{ .root_ca_pem }}
{{ end }}
EOF
        destination = "local/wazuh/certs/root-ca.pem"
        perms = "644"
      }

      template {
        data = <<EOF
{{ with nomadVar "nomad/jobs/wazuh/certs" }}
{{ .indexer_cert_pem }}
{{ end }}
EOF
        destination = "local/certs/wazuh.indexer.pem"
        perms = "644"
      }

      template {
        data = <<EOF
{{ with nomadVar "nomad/jobs/wazuh/certs" }}
{{ .indexer_key_pem }}
{{ end }}
EOF
        destination = "local/certs/wazuh.indexer.key"
        perms = "600"
      }

      template {
        data = <<EOF
{{ with nomadVar "nomad/jobs/wazuh/certs" }}
{{ .admin_cert_pem }}
{{ end }}
EOF
        destination = "local/certs/admin.pem"
        perms = "644"
      }

      template {
        data = <<EOF
{{ with nomadVar "nomad/jobs/wazuh/certs" }}
{{ .admin_key_pem }}
{{ end }}
EOF
        destination = "local/certs/admin-key.pem"
        perms = "600"
      }

      # Configuration files
      template {
        data = <<EOF
{{ with nomadVar "nomad/jobs/wazuh/config" }}
{{ .indexer_yml }}
{{ end }}
EOF
        destination = "local/config/opensearch.yml"
        perms = "644"
      }

      template {
        data = <<EOF
{{ with nomadVar "nomad/jobs/wazuh/config" }}
{{ .internal_users_yml }}
{{ end }}
EOF
        destination = "local/config/opensearch-security/internal_users.yml"
        perms = "644"
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

    volume "wazuh-var-multigroups" {
      type      = "host"
      source    = "greptime/wazuh/wazuh-var-multigroups"
      read_only = false
    }

    volume "wazuh-integrations" {
      type      = "host"
      source    = "greptime/wazuh/wazuh-integrations"
      read_only = false
    }

    volume "wazuh-active-response" {
      type      = "host"
      source    = "greptime/wazuh/wazuh-active-response"
      read_only = false
    }

    volume "wazuh-agentless" {
      type      = "host"
      source    = "greptime/wazuh/wazuh-agentless"
      read_only = false
    }

    volume "wazuh-wodles" {
      type      = "host"
      source    = "greptime/wazuh/wazuh-wodles"
      read_only = false
    }

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

        mount {
          type   = "bind"
          source = "local/ssl"
          target = "/etc/ssl"
          readonly = true
        }

        mount {
          type   = "bind"
          source = "local/wazuh-config"
          target = "/wazuh-config-mount/etc"
          readonly = true
        }


      }

      volume_mount {
        volume      = "wazuh-api-configuration"
        destination = "/var/ossec/api/configuration"
      }

      volume_mount {
        volume      = "wazuh-etc"
        destination = "/var/ossec/etc"
      }

      volume_mount {
        volume      = "wazuh-logs"
        destination = "/var/ossec/logs"
      }

      volume_mount {
        volume      = "wazuh-queue"
        destination = "/var/ossec/queue"
      }

      volume_mount {
        volume      = "wazuh-var-multigroups"
        destination = "/var/ossec/var/multigroups"
      }

      volume_mount {
        volume      = "wazuh-integrations"
        destination = "/var/ossec/integrations"
      }

      volume_mount {
        volume      = "wazuh-active-response"
        destination = "/var/ossec/active-response/bin"
      }

      volume_mount {
        volume      = "wazuh-agentless"
        destination = "/var/ossec/agentless"
      }

      volume_mount {
        volume      = "wazuh-wodles"
        destination = "/var/ossec/wodles"
      }

      volume_mount {
        volume      = "filebeat-etc"
        destination = "/etc/filebeat"
      }

      volume_mount {
        volume      = "filebeat-var"
        destination = "/var/lib/filebeat"
      }

      env {
        INDEXER_URL = "https://127.0.0.1:9200"
        INDEXER_USERNAME = "admin"
        FILEBEAT_SSL_VERIFICATION_MODE = "full"
        SSL_CERTIFICATE_AUTHORITIES = "/etc/ssl/root-ca.pem"
        SSL_CERTIFICATE = "/etc/ssl/filebeat.pem"
        SSL_KEY = "/etc/ssl/filebeat.key"
        API_USERNAME = "wazuh-wui"
        API_PASSWORD="MyS3cr37P450r.*-"

      }

      # Secrets from Nomad Variables
      template {
        data = <<EOF
INDEXER_PASSWORD={{ with nomadVar "nomad/jobs/wazuh/secrets" }}{{ .indexer_password }}{{ end }}
API_PASSWORD={{ with nomadVar "nomad/jobs/wazuh/secrets" }}{{ .api_password }}{{ end }}
EOF
        destination = "secrets/file.env"
        env = true
      }

      # SSL Certificates
      template {
        data = <<EOF
{{ with nomadVar "nomad/jobs/wazuh/certs" }}
{{ .root_ca_manager_pem }}
{{ end }}
EOF
        destination = "local/ssl/root-ca.pem"
        perms = "644"
      }

      template {
        data = <<EOF
{{ with nomadVar "nomad/jobs/wazuh/certs" }}
{{ .manager_cert_pem }}
{{ end }}
EOF
        destination = "local/ssl/filebeat.pem"
        perms = "644"
      }

      template {
        data = <<EOF
{{ with nomadVar "nomad/jobs/wazuh/certs" }}
{{ .manager_key_pem }}
{{ end }}
EOF
        destination = "local/ssl/filebeat.key"
        perms = "600"
      }

      # Wazuh configuration
      template {
        data = <<EOF
{{ with nomadVar "nomad/jobs/wazuh/config" }}
{{ .wazuh_manager_conf }}
{{ end }}
EOF
        destination = "local/wazuh-config/ossec.conf"
        perms = "644"
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

        mount {
          type   = "bind"
          source = "local/certs"
          target = "/usr/share/wazuh-dashboard/certs"
          readonly = true
        }

        mount {
          type   = "bind"
          source = "local/config"
          target = "/usr/share/wazuh-dashboard/config"
          readonly = true
        }

        mount {
          type   = "bind"
          source = "local/wazuh-config"
          target = "/usr/share/wazuh-dashboard/data/wazuh/config"
          readonly = true
        }
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

      # Secrets
      template {
        data = <<EOF
INDEXER_PASSWORD={{ with nomadVar "nomad/jobs/wazuh/secrets" }}{{ .indexer_password }}{{ end }}
API_PASSWORD={{ with nomadVar "nomad/jobs/wazuh/secrets" }}{{ .api_password }}{{ end }}
EOF
        destination = "secrets/file.env"
        env = true
      }

      # SSL Certificates
      template {
        data = <<EOF
{{ with nomadVar "nomad/jobs/wazuh/certs" }}
{{ .dashboard_cert_pem }}
{{ end }}
EOF
        destination = "local/certs/wazuh-dashboard.pem"
        perms = "644"
      }

      template {
        data = <<EOF
{{ with nomadVar "nomad/jobs/wazuh/certs" }}
{{ .dashboard_key_pem }}
{{ end }}
EOF
        destination = "local/certs/wazuh-dashboard-key.pem"
        perms = "600"
      }

      template {
        data = <<EOF
{{ with nomadVar "nomad/jobs/wazuh/certs" }}
{{ .root_ca_pem }}
{{ end }}
EOF
        destination = "local/certs/root-ca.pem"
        perms = "644"
      }

      # Configuration files
      template {
        data = <<EOF
{{ with nomadVar "nomad/jobs/wazuh/config" }}
{{ .opensearch_dashboards_yml }}
{{ end }}
EOF
        destination = "local/config/opensearch_dashboards.yml"
        perms = "644"
      }

      template {
        data = <<EOF
{{ with nomadVar "nomad/jobs/wazuh/config" }}
{{ .wazuh_yml }}
{{ end }}
EOF
        destination = "local/wazuh-config/wazuh.yml"
        perms = "644"
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