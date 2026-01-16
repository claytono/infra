# IAM user for ddns-route53 dynamic DNS updates
resource "aws_iam_user" "ddns_route53" {
  name = "crazy-max-ddns-user"
}

resource "aws_iam_access_key" "ddns_route53" {
  user = aws_iam_user.ddns_route53.name
}

# Policy allowing Route53 record updates for specific hosted zones
resource "aws_iam_policy" "ddns_route53" {
  name = "ddns-route53"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "VisualEditor0"
        Effect = "Allow"
        Action = [
          "route53:ChangeResourceRecordSets",
          "route53:ListResourceRecordSets"
        ]
        Resource = [
          "arn:aws:route53:::hostedzone/${module.dns.oneill_net_zone_id}",
          "arn:aws:route53:::hostedzone/${module.dns.fnord_net_zone_id}"
        ]
      }
    ]
  })
}

resource "aws_iam_user_policy_attachment" "ddns_route53" {
  user       = aws_iam_user.ddns_route53.name
  policy_arn = aws_iam_policy.ddns_route53.arn
}

# Store credentials and zone IDs in 1Password for Kubernetes ExternalSecret
resource "onepassword_item" "ddns_route53_aws" {
  vault    = data.onepassword_vault.infra.uuid
  title    = "ddns-route53-aws"
  category = "secure_note"

  note_value = "AWS credentials and zone IDs for ddns-route53. Managed by OpenTofu - do not edit manually."

  section {
    label = "credentials"

    field {
      label = "DDNSR53_CREDENTIALS_ACCESSKEYID"
      type  = "STRING"
      value = aws_iam_access_key.ddns_route53.id
    }

    field {
      label = "DDNSR53_CREDENTIALS_SECRETACCESSKEY"
      type  = "CONCEALED"
      value = aws_iam_access_key.ddns_route53.secret
    }

    field {
      label = "ONEILL_NET_ZONE_ID"
      type  = "STRING"
      value = module.dns.oneill_net_zone_id
    }

    field {
      label = "FNORD_NET_ZONE_ID"
      type  = "STRING"
      value = module.dns.fnord_net_zone_id
    }
  }
}
