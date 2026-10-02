Title: Live Content

Description: Fetched live

Source: https://raw.githubusercontent.com/jgraph/drawio-mcp/main/README.md

---

# Draw.io MCP Server

The official [draw.io](https://www.draw.io) MCP (Model Context Protocol) server that enables LLMs to create and open diagrams in the draw.io editor.

## Four Ways to Create Diagrams

This repository offers four approaches for integrating draw.io with AI assistants. Pick the one that fits your setup:

| | [MCP App Server](#mcp-app-server) | [MCP Tool Server](#mcp-tool-server) | [Assistant Plugins](#assistant-plugins-claude-code-codex-cli-github-copilot) | [Project Instructions](#alternative-project-instructions-no-mcp-required) |
|---|---|---|---|---|
| **How it works** | Renders diagrams inline in chat | Opens diagrams in your browser | Generates `.drawio` files, optional PNG/SVG/PDF export or browser URL | Claude generates draw.io URLs via Python |
| **Diagram output** | Interactive viewer embedded in conversation | draw.io editor in a new tab | `.drawio`, `.drawio.png` / `.svg` / `.pdf`, or browser URL | Clickable link to draw.io |
| **Requires installation** | No (hosted at `mcp.draw.io`) | Yes (npm package) | One-line plugin install (draw.io Desktop only for PNG/SVG/PDF export) | No — just paste instructions |
| **Supports XML, CSV, Mermaid** | XML only | ✅ All three | XML only (native format) | ✅ All three |
| **Editable in draw.io** | Via "Open in draw.io" button | ✅ Directly | ✅ Directly | Via link |
| **Works with** | Claude.ai, VS Code, Cursor, any MCP Apps host | Claude Desktop, Cursor, OpenCode, any MCP client | Claude Code, Codex CLI, GitHub Copilot, OpenCode | Claude.ai (with Projects) |
| **Best for** | Inline previews in chat | Local desktop workflows | Local development workflows | Quick setup, no install needed |

---

## MCP App Server

The MCP App server renders draw.io diagrams **inline** in AI chat interfaces using the [MCP Apps](https://modelcontextprotocol.io/docs/extensions/apps) protocol. Instead of opening a browser tab, diagrams appear directly in the conversation as interactive iframes.

The official hosted endpoint is available at:

```
https://mcp.draw.io/mcp
```

Add this URL as a remote MCP server in Claude.ai, Cursor, or any MCP Apps-compatible host — no installation required. On Claude.ai, draw.io is also listed in the [connector directory](https://claude.ai/directory/pending-draw-io) and can be added from there in one click. In Cursor (≥ 2.6), diagrams render inline in the Agent chat ([one-click install](https://cursor.com/en/install-mcp?name=drawio&config=eyJ1cmwiOiJodHRwczovL21jcC5kcmF3LmlvL21jcCJ9)); on older builds, use the stdio [`@drawio/mcp`](mcp-tool-server/README.md) tool server instead.

You can also run the server locally via Node.js or the [`jgraph/drawio-mcp`](https://hub.docker.com/r/jgraph/drawio-mcp) Docker image, or deploy your own instance to Cloudflare Workers.

**Tools:**
- **`create_diagram`** — Renders draw.io XML as an interactive diagram inline in chat
- **`search_shapes`** — Searches 10,000+ shapes across all draw.io libraries (AWS, Azure, GCP, P&ID, electrical, Cisco, Kubernetes, UML, BPMN, etc.) by keyword, supplemented by the draw.io icon service (brand logos and general-purpose concept icons) when the built-in libraries have no good match. Returns exact style strings that can be used directly in XML. Use this to find the correct shape before calling `create_diagram`.

**[Full documentation →](mcp-app-server/README.md)**

> **Note:** Inline diagram rendering requires an MCP host that supports the MCP Apps extension. In hosts without MCP Apps support, the tool still works but returns the XML as text.

---

## MCP Tool Server

The original MCP server that opens diagrams directly in the draw.io editor. Supports XML, CSV, and Mermaid.js formats with lightbox and dark mode options. Published as [`@drawio/mcp`](https://www.npmjs.com/package/@drawio/mcp) on npm.

Quick start: `npx @drawio/mcp`

Setup instructions are available for Claude Desktop, Claude Code, VS Code (GitHub Copilot), Cursor (with one-click install), and OpenCode.

**[Full documentation →](mcp-tool-server/README.md)**

---

## Assistant Plugins (Claude Code, Codex CLI, GitHub Copilot)

The `drawio` skill packaged as a plugin for AI coding assistants (under [`plugins/`](plugins/README.md)): it generates native `.drawio` files, with optional export to PNG, SVG, or PDF (with embedded XML so the exported file remains editable in draw.io) — or a browser URL that opens the diagram directly in `app.diagrams.net`. No MCP setup required. The same skill ships for three hosts:

**Claude Code** ([full documentation →](plugins/claude-code/README.md)) — install from this repo's marketplace:

```
/plugin marketplace add jgraph/drawio-mcp
/plugin install drawio@drawio
```

Or load it directly from a local clone with `claude --plugin-dir ./plugins/claude-code`.

**Codex CLI** ([full documentation →](plugins/codex/drawio/README.md)) — install from the same marketplace repo:

```bash
codex plugin marketplace add jgraph/drawio-mcp
codex plugin add drawio@drawio
```

**GitHub Copilot CLI** ([full documentation →](plugins/copilot/README.md)) — install from the same marketplace repo:

```bash
copilot plugin marketplace add jgraph/drawio-mcp
copilot plugin install drawio@drawio
```

Other Copilot surfaces (VS Code agent mode, the coding agent, code review) load the same skill from a repo's `.github/skills/` directory instead — see the [plugin README](plugins/copilot/README.md).

**OpenCode** needs no plugin at all: it discovers skills in `.opencode/skills/` and `.claude/skills/` (and their `~/` equivalents), so the Claude Code skill folder works as

