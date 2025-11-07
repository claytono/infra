# Variables for DNS module

variable "infrastructure_hosts" {
  description = "Map of infrastructure hosts with their network configuration"
  type = map(object({
    mac      = string
    ip       = string
    hostname = string
    note     = string
  }))
}
