# Tailscale ACL policy configuration - based on upstream with added K8s tags
resource "tailscale_acl" "main" {
  acl = <<-EOT
    // Example/default ACLs for unrestricted connections.
    {
        // Declare static groups of users. Use autogroups for all users or users with a specific role.
        // "groups": {
        //   "group:example": ["alice@example.com", "bob@example.com"],
        // },

        // Define the tags which can be applied to devices and by which users.
        "tagOwners": {
            "tag:k8s-operator": [],
            "tag:k8s": ["tag:k8s-operator"],
            "tag:github-actions": [],
            "tag:argocd": ["tag:k8s-operator"],
            "tag:flux": ["autogroup:admin"],
        },

        // Define access control lists for users, groups, autogroups, tags,
        // Tailscale IP addresses, and subnet ranges.
        "acls": [
            // Allow users to access their own devices and general internet
            {
                "action": "accept",
                "src":    ["autogroup:member"],
                "dst":    ["*:*"],
            },

            // Allow flux to reach other hosts via SSH only
            {
                "action": "accept",
                "src":    ["tag:flux"],
                "proto":  "tcp",
                "dst":    ["*:22"],
            },

            // Allow GitHub Actions to reach ArgoCD only
            {
                "action": "accept",
                "src":    ["tag:github-actions"],
                "proto":  "tcp",
                "dst":    ["tag:argocd:443"],
            },

            // Allow k8s operator to manage k8s nodes
            {
                "action": "accept",
                "src":    ["tag:k8s-operator"],
                "dst":    ["tag:k8s:*"],
            },
        ],

        // Define postures that will be applied to all rules without any specific
        // srcPosture definition.
        // "defaultSrcPosture": [
        //      "posture:anyMac",
        // ],

        // Define device posture rules requiring devices to meet
        // certain criteria to access parts of your system.
        // "postures": {
        //      // Require devices running macOS, a stable Tailscale
        //      // version and auto update enabled for Tailscale.
        //  "posture:autoUpdateMac": [
        //      "node:os == 'macos'",
        //      "node:tsReleaseTrack == 'stable'",
        //      "node:tsAutoUpdate",
        //  ],
        //      // Require devices running macOS and a stable
        //      // Tailscale version.
        //  "posture:anyMac": [
        //      "node:os == 'macos'",
        //      "node:tsReleaseTrack == 'stable'",
        //  ],
        // },

        // Define users and devices that can use Tailscale SSH.
        "ssh": [
            // Allow all users to SSH into their own devices in check mode.
            // Comment this section out if you want to define specific restrictions.
            {
                "action": "check",
                "src":    ["autogroup:member"],
                "dst":    ["autogroup:self"],
                "users":  ["autogroup:nonroot", "root"],
            },
        ],

        "nodeAttrs": [],

        // Test access rules every time they're saved.
        // "tests": [
        //   {
        //       "src": "alice@example.com",
        //       "accept": ["tag:example"],
        //       "deny": ["100.101.102.103:443"],
        //   },
        // ],
    }
  EOT
}

# Create OAuth client for Tailscale Kubernetes operator
resource "tailscale_oauth_client" "k8s_operator" {
  description = "tailscale-operator"
  scopes      = ["devices:core", "auth_keys"]
  tags        = ["tag:k8s-operator"]
}

# Create OAuth client for GitHub Actions (ephemeral nodes)
resource "tailscale_oauth_client" "github_actions" {
  description = "github-actions"
  scopes      = ["auth_keys"]
  tags        = ["tag:github-actions"]
}

# Store operator OAuth credentials in 1Password
resource "onepassword_item" "tailscale_operator" {
  vault    = data.onepassword_vault.infra.uuid
  title    = "tailscale-operator"
  category = "login"

  note_value = "Tailscale OAuth client for Kubernetes operator. Managed by OpenTofu - do not edit manually."

  section {
    label = "OAuth Credentials"

    field {
      label = "client_id"
      type  = "STRING"
      value = tailscale_oauth_client.k8s_operator.id
    }

    field {
      label = "client_secret"
      type  = "CONCEALED"
      value = tailscale_oauth_client.k8s_operator.key
    }
  }
}

# Store GitHub Actions OAuth credentials in 1Password
resource "onepassword_item" "tailscale_github_actions" {
  vault    = data.onepassword_vault.infra.uuid
  title    = "tailscale-github-actions"
  category = "login"

  note_value = "Tailscale OAuth client for GitHub Actions. Managed by OpenTofu - do not edit manually."

  section {
    label = "OAuth Credentials"

    field {
      label = "client_id"
      type  = "STRING"
      value = tailscale_oauth_client.github_actions.id
    }

    field {
      label = "client_secret"
      type  = "CONCEALED"
      value = tailscale_oauth_client.github_actions.key
    }
  }
}

# DNS Configuration
# Consolidated DNS configuration using tailscale_dns_configuration resource.
# This replaces the individual tailscale_dns_split_nameservers resources and allows
# us to set use_with_exit_node parameter for split DNS nameservers.
#
# Split DNS configuration:
# 1. k.oneill.net → AWS Route53 (for Kubernetes ingresses)
#    - Uses AWS Route53 nameservers with use_with_exit_node=true
#    - Works when using exit nodes (especially flux)
# 2. oneill.net → Local DNS (for infrastructure hosts and other local services)
#    - Uses local DNS server (172.19.74.1) with use_with_exit_node=true
#    - Router DNS is not listening on Tailscale interface, so exit node/subnet routes
#      must be disabled on the router to avoid routing conflicts

# Resolve k.oneill.net nameserver hostnames to IP addresses
# Tailscale requires IP addresses, not hostnames
data "dns_a_record_set" "k_oneill_net_ns" {
  for_each = toset(module.dns.k_oneill_net_nameservers)
  host     = each.value
}

resource "tailscale_dns_configuration" "main" {
  # Enable MagicDNS for *.ts.net resolution
  magic_dns = true

  # Don't override local DNS - prefer local DNS when not using exit node
  override_local_dns = false

  # Split DNS for k.oneill.net subdomain (Kubernetes ingresses)
  # Uses AWS Route53 nameservers resolved to IP addresses
  dynamic "split_dns" {
    for_each = [1] # Create exactly one split_dns block
    content {
      domain = "k.oneill.net"

      # Create a nameserver block for each resolved Route53 nameserver IP
      dynamic "nameservers" {
        for_each = data.dns_a_record_set.k_oneill_net_ns
        content {
          address            = nameservers.value.addrs[0]
          use_with_exit_node = true
        }
      }
    }
  }

  # Split DNS for oneill.net parent domain (infrastructure hosts + local services)
  split_dns {
    domain = "oneill.net"
    nameservers {
      address            = "172.19.74.1"
      use_with_exit_node = true
    }
  }
}
