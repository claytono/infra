# Variables for DNS module

variable "infrastructure_hosts" {
  description = "Map of infrastructure hosts with their network configuration"
  type = map(object({
    mac         = string
    ip          = string
    hostname    = string
    note        = string
    public_dns  = optional(bool, true)
    enable_ipv6 = optional(bool, true)
  }))
}

variable "infrastructure_ipv6_prefix" {
  description = "IPv6 /64 prefix for infrastructure hosts"
  type        = string
}

variable "cloudflare_account_id" {
  description = "Cloudflare account ID for zone management"
  type        = string
}
