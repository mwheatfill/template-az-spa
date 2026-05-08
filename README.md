# template-az-spa

GitHub template for **Tier 1** internal apps — a Vite + React + TypeScript SPA gated by Entra ID
and deployed to Azure Static Web Apps (Free tier), with optional managed Functions for
token-holding API proxies.

The architecture is described in
[app-platform-tier1.md](https://github.com/mwheatfill/thought-box/blob/main/docs/app-platform-tier1.md).
Use this template when you need a read-only viewer, dashboard, lookup tool, or simple API mashup
that doesn't need persistent relational data, streaming, or long-running server work.

## Quickstart

1. **Create a new repo from this template** (GitHub → "Use this template" → "Create a new repository").
   ```bash
   gh repo create my-org/my-new-app --template mwheatfill/template-az-spa --private --clone
   cd my-new-app
   ```

2. **Install deps and verify it builds locally:**
   ```bash
   npm install
   npm run dev      # http://localhost:5173, no auth, no Functions
   npm run build
   ```

3. **Bootstrap Azure + GitHub:**
   ```bash
   export SUB="<azure-subscription-id>"
   export TENANT="<entra-tenant-id>"
   export RG="my-new-app-rg"
   export LOC="westus2"               # or eastus2, centralus, eastasia, westeurope
   export SWA_NAME="my-new-app"
   export GH_REPO="my-org/my-new-app"
   export APP_DISPLAY_NAME="My New App"
   export ALERT_EMAIL="me@switchthink.com"
   export MONTHLY_BUDGET_USD=20       # optional, default 20
   export GRAPH_SCOPES=""             # comma-separated, e.g. "User.Read.All,Mail.Send"

   ./scripts/azure-deploy.sh
   ```

   The script is **idempotent** — safe to re-run. It creates (or reuses) the resource group, SWA,
   Entra app registration, App Insights, action group, availability test, and monthly budget. It
   pushes credentials into SWA app settings and tenant/client IDs into GitHub repository
   variables. It never writes secrets to GitHub.

4. **Push to deploy:**
   ```bash
   git add -A && git commit -m "wire up SWA" && git push
   gh run watch
   ```

5. **Visit your SWA URL** — printed by the bootstrap script. You'll be redirected to Entra to
   sign in.

## Required env vars for `azure-deploy.sh`

| Var | Required | Purpose |
| --- | --- | --- |
| `SUB` | yes | Azure subscription ID |
| `TENANT` | yes | Entra tenant ID |
| `RG` | yes | Resource group name |
| `LOC` | yes | Azure region (SWA-supported: `westus2`, `eastus2`, `centralus`, `eastasia`, `westeurope`) |
| `SWA_NAME` | yes | Static Web App resource name |
| `GH_REPO` | yes | `owner/repo` of the GitHub repo |
| `APP_DISPLAY_NAME` | yes | Display name for the Entra app registration |
| `ALERT_EMAIL` | yes | Email for availability + budget alerts |
| `MONTHLY_BUDGET_USD` | no, default `20` | Cost cap for the resource group |
| `GRAPH_SCOPES` | no | Comma-separated Graph scopes (prints admin-consent URL only) |

## Local development

```bash
npm run dev       # Vite only, fast, no auth, no Functions. Use for component work.
npm run dev:swa   # SWA CLI emulates auth + Functions + routing. Use when touching anything past static.
npm test          # Vitest, watch mode: npm run test:watch
npm run test:e2e  # Playwright (boots `npm run dev` automatically)
npm run check     # Biome lint + format
npm run typecheck # tsc -b --noEmit
```

The SWA CLI mocks the EasyAuth principal at `/.auth/me`. Override the mock user via `swa start`
flags or `swa-cli.config.json` if you need to test role-based behaviour.

## Adding a custom domain

Custom domains are *not* baked into bootstrap. Add manually:

```bash
az staticwebapp hostname set \
  --name "$SWA_NAME" \
  --resource-group "$RG" \
  --hostname "app.example.com"
```

Then add the DNS records the portal shows (CNAME for subdomains; ALIAS or `_dnsauth` TXT for
apex). Update the Entra app registration's redirect URI list to include
`https://app.example.com/.auth/login/aad/callback`.

## Branch protection

After the first deploy, set branch protection on `main` (Settings → Branches → Add rule):

- Require status checks to pass before merging
- Require both **`Azure Static Web Apps CI/CD`** and **`CI`** (lint/typecheck/test/build) to pass

GitHub doesn't expose this in `gh` cleanly enough for the bootstrap script to set it
non-destructively, so it's a one-time manual step.

## Tearing down

```bash
az group delete --name $RG --yes
```

That's the whole answer. The Entra app registration lives at the tenant level (not in the RG)
— delete it separately if you want:

```bash
az ad app delete --id "$(az ad app list --display-name "$APP_DISPLAY_NAME" --query "[0].appId" -o tsv)"
```

## When something breaks

Run `npm run diagnose` (or `bash scripts/diagnose.sh` directly) for a status overview, then
follow [docs/RUNBOOK.md](docs/RUNBOOK.md) for incident-specific playbooks.

## What's in the template

- **`src/`** — React 19 + TanStack Router (file-based) + TanStack Query, Tailwind v4 +
  shadcn/ui (new-york). Sample home page and `/health` route prove the stack loads.
- **`api/`** — Azure Functions v4 programming model. `health/` is the canonical endpoint
  pattern; `_shared/{auth,graph,http}.ts` are frozen reference helpers.
- **`scripts/azure-deploy.sh`** — idempotent bootstrap (RG → SWA → Entra → App Insights →
  alerts → budget).
- **`scripts/diagnose.sh`** — single-script support tool (read-only, never logs secret values).
- **`.github/workflows/`** — split into `azure-static-web-apps.yml` (deploy) and `ci.yml`
  (PR-only verify).
- **`AGENTS.md`** — canonical agent instructions. **Read this before opening a PR with an
  AI agent.**
- **`docs/RUNBOOK.md`** — incident playbook.
- **`docs/llms-references.md`** — registry of `llms.txt` URLs and MCP servers for libs the
  agent should consult before generating code that touches them.
- **`.mcp.json`** — pre-configured Microsoft Learn MCP server for Claude Code (Graph, SWA,
  Azure CLI, Bicep — authoritative live docs).
