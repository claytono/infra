# Slack App Manifests

Manages Slack app manifests (Frank, Home) via the `change-engine/slack-app`
provider in an isolated tofu root.

## Why Isolated

The main tofu root previously included Slack resources using both
`change-engine/slack-token` (for token refresh) and `change-engine/slack-app`
(for manifests). The token refresh mechanism is broken: when the 12-hour config
token expires, `slack-app`'s `Configure()` receives an empty string and fails
with `not_authed`, blocking all `tofu plan` runs on the entire root.

This separate root still uses `change-engine/slack-app` for manifests (it
handles manifest roundtrips cleanly), but manages token rotation externally via
a wrapper script and 1Password.

## Token Management

Slack configuration tokens expire every 12 hours. Three values are cached in
1Password (`infra/slack-config-tokens`) and loaded via direnv:

- `access-token` → `SLACK_APP_TOKEN`
- `refresh-token` → `SLACK_REFRESH_TOKEN`
- `expires-at` → `SLACK_TOKEN_EXPIRES_AT`

## Usage

```bash
# Plan/apply (checks token expiry automatically)
scripts/tofu-slack plan
scripts/tofu-slack apply

# If token is expired
scripts/slack-token-refresh && direnv reload
scripts/tofu-slack plan
```
