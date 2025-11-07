# Export k.oneill.net nameservers for use in Tailscale split DNS configuration
output "k_oneill_net_nameservers" {
  description = "AWS Route53 nameservers for k.oneill.net zone"
  value       = aws_route53_zone.k_oneill_net.name_servers
}
