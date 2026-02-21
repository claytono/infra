terraform {
  required_version = ">= 1.6"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 5.0"
    }
  }
}

locals {
  # AWS Route53 nameserver IP addresses for delegation set N1B52P4FUKL1S2
  nameserver_ips = {
    ns1 = {
      ipv4 = "205.251.198.43"
      ipv6 = "2600:9000:5306:2b00::1"
    }
    ns2 = {
      ipv4 = "205.251.196.178"
      ipv6 = "2600:9000:5304:b200::1"
    }
    ns3 = {
      ipv4 = "205.251.193.139"
      ipv6 = "2600:9000:5301:8b00::1"
    }
    ns4 = {
      ipv4 = "205.251.194.57"
      ipv6 = "2600:9000:5302:3900::1"
    }
  }
}

resource "aws_route53_delegation_set" "main" {
}
