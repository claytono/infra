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
