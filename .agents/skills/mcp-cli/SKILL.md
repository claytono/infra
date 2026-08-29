---
name: mcp-cli
description:
  Interface for MCP (Model Context Protocol) servers via CLI. Use when you need
  to interact with external tools, APIs, or data sources through MCP servers.
---

# MCP-CLI

Access MCP servers through the command line. MCP enables interaction with
external systems like GitHub, filesystems, databases, and APIs.

## Commands

| Command                                 | Output                          |
| --------------------------------------- | ------------------------------- |
| `mcp-cli`                               | List all servers and tool names |
| `mcp-cli info <server>`                 | Show tools with parameters      |
| `mcp-cli info <server>/<tool>`          | Get tool JSON schema            |
| `mcp-cli call <server>/<tool> '<json>'` | Call tool with arguments        |
| `mcp-cli grep "<glob>"`                 | Search tools by name            |

**Add `-d` to include descriptions** (e.g., `mcp-cli info filesystem -d`)

## Workflow

1. **Discover**: `mcp-cli` → see available servers and tools
2. **Explore**: `mcp-cli info <server>` → see tools with parameters
3. **Inspect**: `mcp-cli info <server>/<tool>` → get full JSON input schema
4. **Execute**: `mcp-cli call <server>/<tool> '<json>'` → run with arguments

## Examples

```bash
# List all servers and tool names
mcp-cli

# See all tools with parameters
mcp-cli info filesystem

# With descriptions (more verbose)
mcp-cli info filesystem -d

# Get JSON schema for specific tool
mcp-cli info filesystem/read_file

# Call the tool
mcp-cli call filesystem/read_file '{"path": "./README.md"}'

# Search for tools
mcp-cli grep "*file*"

# Complex JSON with quotes (use stdin)
mcp-cli call server/tool <<EOF
{"content": "Text with 'quotes' inside"}
EOF

# Or pipe from a file/command
cat args.json | mcp-cli call server/tool
```

## Options

| Flag | Purpose              |
| ---- | -------------------- |
| `-d` | Include descriptions |

## Exit Codes

- `0`: Success
- `1`: Client error (bad args, missing config)
- `2`: Server error (tool failed)
- `3`: Network error
