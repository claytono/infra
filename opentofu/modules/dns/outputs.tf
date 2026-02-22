# Export k.oneill.net nameservers for use in Tailscale split DNS configuration
output "k_oneill_net_nameservers" {
  description = "AWS Route53 nameservers for k.oneill.net zone"
  value       = aws_route53_zone.k_oneill_net.name_servers
}

# Export zone IDs for use in IAM policies
output "oneill_net_zone_id" {
  description = "AWS Route53 hosted zone ID for oneill.net"
  value       = aws_route53_zone.oneill_net.zone_id
}

output "fnord_net_zone_id" {
  description = "AWS Route53 hosted zone ID for fnord.net"
  value       = aws_route53_zone.fnord_net.zone_id
}

output "cloudflare_fnord_net_zone_id" {
  description = "Cloudflare zone ID for fnord.net"
  value       = cloudflare_zone.fnord_net.id
}

output "cloudflare_fnord_net_nameservers" {
  description = "Cloudflare nameservers for fnord.net"
  value       = cloudflare_zone.fnord_net.name_servers
}

output "cloudflare_oneill_net_zone_id" {
  description = "Cloudflare zone ID for oneill.net"
  value       = cloudflare_zone.oneill_net.id
}

output "cloudflare_oneill_net_nameservers" {
  description = "Cloudflare nameservers for oneill.net"
  value       = cloudflare_zone.oneill_net.name_servers
}
