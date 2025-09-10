#############################
# Shared data sources
#############################

data "authentik_flow" "default_authorization" {
  slug = "default-provider-authorization-implicit-consent"
}

data "authentik_flow" "default_invalidation" {
  slug = "default-provider-invalidation-flow"
}


# Individual OAuth2 scope mappings for OIDC providers
data "authentik_property_mapping_provider_scope" "openid" {
  name = "authentik default OAuth Mapping: OpenID 'openid'"
}

data "authentik_property_mapping_provider_scope" "email" {
  name = "authentik default OAuth Mapping: OpenID 'email'"
}

data "authentik_property_mapping_provider_scope" "profile" {
  name = "authentik default OAuth Mapping: OpenID 'profile'"
}

# Signing key for OAuth2 providers
data "authentik_certificate_key_pair" "self_signed" {
  name = "authentik Self-signed Certificate"
}

# Kubernetes service connection for outpost
data "authentik_service_connection_kubernetes" "local" {
  name = "Local Kubernetes Cluster"
}

#############################
# Generated Authentik resources
#############################
#
# All Authentik providers, applications, and outpost resources
# are generated from Kubernetes ingress annotations by running:
#
#   ak-tool generate
#
# This creates generated-*.tf.json files in this directory
# which are automatically included by Terraform.
