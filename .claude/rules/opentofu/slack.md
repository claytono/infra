---
paths:
  ["opentofu/slack/**/*", "scripts/tofu-slack", "scripts/slack-token-refresh"]
---

# Slack OpenTofu Root

Slack app manifests live in `opentofu/slack/`, isolated from the main tofu root
because the `slack-token` provider's token refresh mechanism breaks `tofu plan`
when the 12-hour config token expires, blocking all resources in the root.

## Commands

Always use the wrapper script instead of running `tofu` directly:

```bash
scripts/tofu-slack plan
scripts/tofu-slack apply
scripts/tofu-slack import <resource> <id>
```

## Token Expiry

If `scripts/tofu-slack` reports the token is expired, tell the user to run:

```bash
scripts/slack-token-refresh && direnv reload
```

Never call `op read` or `tooling.tokens.rotate` directly — the refresh script
handles both the Slack API call and 1Password update.

## 1Password

Item: `slack-config-tokens` in `infra` vault. Fields: `access-token`,
`refresh-token`, `expires-at`.
