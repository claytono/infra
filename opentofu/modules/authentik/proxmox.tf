###############################################
# Proxmox OIDC provider (manually maintained)
###############################################

resource "authentik_provider_oauth2" "proxmox" {
  name               = "proxmox"
  client_id          = local.proxmox_oidc_client_id
  client_secret      = local.proxmox_oidc_secret
  client_type        = "confidential"
  authorization_flow = data.authentik_flow.default_authorization.id
  invalidation_flow  = data.authentik_flow.default_invalidation.id
  property_mappings = [
    data.authentik_property_mapping_provider_scope.openid.id,
    data.authentik_property_mapping_provider_scope.email.id,
    data.authentik_property_mapping_provider_scope.profile.id,
  ]
  access_token_validity = "hours=1"
  allowed_redirect_uris = [
    { url = "https://pve.oneill.net", matching_mode = "strict" },
    { url = "https://p2.oneill.net:8006", matching_mode = "strict" },
    { url = "https://p3.oneill.net:8006", matching_mode = "strict" },
    { url = "https://p4.oneill.net:8006", matching_mode = "strict" },
    { url = "https://p9.oneill.net:8006", matching_mode = "strict" },
  ]
  signing_key = data.authentik_certificate_key_pair.self_signed.id
}

resource "authentik_application" "proxmox" {
  name              = "proxmox"
  slug              = "proxmox"
  protocol_provider = authentik_provider_oauth2.proxmox.id
}
