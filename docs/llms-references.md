# LLM references

Registry of authoritative docs for libraries in this template. **Consult these before
generating code that touches the listed library** — training-data drift is real, especially
for the TanStack family, Tailwind v4, and shadcn.

Order of preference:

1. **TanStack Intent skill** (if installed and current) — `npm run skills:install` then check
   `npx intent list`.
2. **Microsoft Learn MCP server** (configured in `.mcp.json`) — for everything Microsoft:
   Graph, SWA, Azure CLI, Bicep, App Service, Entra, App Insights.
3. **`llms.txt` URLs below** — for libs without intent skills or MCP coverage.
4. **WebFetch / WebSearch** — last resort. Cite the URL in your PR description.

## llms.txt registry

| Library | URL | Notes |
| --- | --- | --- |
| shadcn/ui | https://ui.shadcn.com/llms.txt | CLI changed in 2026; uses `tw-animate-css` |
| Tailwind CSS v4 | https://tailwindcss.com/docs/installation/using-vite | v4 install is materially different from v3 — no `tailwind.config.ts`, theme in CSS |
| Vite | https://vite.dev/llms.txt | Verify path; vite ships a partial `llms-full.txt` |
| Vitest | https://vitest.dev/llms.txt | Verify; otherwise read the docs site |
| TanStack Query | https://tanstack.com/query/latest | No dedicated llms.txt; use intent skill if available |
| TanStack Router | https://tanstack.com/router/latest | File-based plugin lives at `@tanstack/router-plugin/vite` (not `@tanstack/router-vite-plugin` — that's an alias) |
| TanStack Form | https://tanstack.com/form/latest | Add when an app actually needs forms; not pre-installed |
| TanStack Intent | https://github.com/TanStack/intent | Early — verify available skills with `intent list` |
| Biome | https://biomejs.dev | Single tool replaces ESLint + Prettier; v2 is current |
| Playwright | https://playwright.dev | |
| React 19 | https://react.dev | Compiler is documented under Learn → React Compiler |
| Sonner | https://sonner.emilkowal.ski | |

## Microsoft Learn MCP

The Microsoft Learn MCP server is wired up in `.mcp.json` at the repo root:

```json
{
  "mcpServers": {
    "microsoft-learn": {
      "type": "http",
      "url": "https://learn.microsoft.com/api/mcp"
    }
  }
}
```

It exposes three tools to Claude Code (and any agent that supports the MCP HTTP transport):

- `microsoft_docs_search` — semantic search across all Microsoft Learn docs
- `microsoft_docs_fetch` — fetch a specific article in full
- `microsoft_code_sample_search` — search Microsoft's code samples

Use it instead of `WebFetch` for any of:

- Azure Static Web Apps configuration / app settings / runtimes
- Azure Functions programming model, triggers, bindings
- Microsoft Graph endpoints, scopes, query syntax
- Entra ID app registration, redirect URIs, consent flows
- Azure CLI (`az`) command syntax — these change frequently
- Bicep / ARM resource shapes
- Application Insights queries (KQL), availability tests, alert rules

It does NOT cover npm packages, React, TanStack libs, Tailwind, etc. — fall back to llms.txt
or intent for those.

## Verification recipe (paste this into your agent prompt)

> Before generating code that touches `<library>`, do the following in order:
> 1. Run `npm view <pkg> version` to confirm the installed major matches what you're about to write.
> 2. Read the entry in `docs/llms-references.md` for that library.
> 3. If it has an intent skill, use it. If it's Microsoft, query the `microsoft-learn` MCP server.
>    Otherwise WebFetch the documented URL.
> 4. Cite the source you used in your PR description so reviewers can verify.
