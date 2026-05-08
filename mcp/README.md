# `mcp/` — Model Context Protocol server

Empty by default. Populate this folder when the app should be reachable from MCP clients
(Claude Desktop, Cursor, ChatGPT desktop, custom agent runtimes) as a tool surface.

## Install

Use the [`+mcp-server` recipe](https://github.com/mwheatfill/app-platform-recipes/tree/main/recipes/%2Bmcp-server):

```bash
# from the repo root
curl -sSL https://raw.githubusercontent.com/mwheatfill/app-platform-recipes/main/install.sh | \
  bash -s -- +mcp-server
```

The recipe scaffolds an MCP server that:

- Reads the OpenAPI spec from `/api/openapi.json` (or a local copy)
- Exposes each endpoint as an MCP tool with the OpenAPI metadata as the tool description
- Forwards calls to the running API with the appropriate auth header
- Runs over stdio (for desktop MCP clients) and/or Streamable HTTP (for server-to-server)

## Convention

The MCP server is a **wrapper over the OpenAPI spec**, not a parallel implementation. If you
find yourself adding business logic in `mcp/`, that logic belongs in `api/` instead — then
the MCP layer picks it up automatically.

For auth, the MCP server typically uses an API key against an unauthed-but-key-gated route
(`/api/agent/*` pattern documented in [AGENTS.md](../AGENTS.md)) since MCP clients run outside
the EasyAuth session.
