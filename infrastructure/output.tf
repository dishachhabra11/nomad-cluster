output "load-balancer-ip" {
    value = module.nomad-lb-http.external_ip
    description =  "the external ip of load balancer"
}