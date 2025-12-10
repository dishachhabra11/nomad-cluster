output "load_balancer_ip" {
  value       = google_compute_global_forwarding_rule.nomad_lb_forwarding.ip_address
  description = "Public IP of the HTTP Load Balancer"
}
