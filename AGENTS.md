# AGENTS.md

Canonical instructions for AI coding agents working in this repo. Read fully before making
non-trivial changes. The architecture itself is defined in
[app-platform-tier1.md](https://github.com/mwheatfill/thought-box/blob/main/docs/app-platform-tier1.md)
— don't restate; consult.

## Stack and conventions

| Layer | Library | Pin notes |
| --- | --- | --- |
| Build | Vite 8 + Rolldown-when-stable | |
| Framework | React 19, TypeScript 6, JSX automatic | |
| Styling | Tailwind v4 via `@tailwindcss/vite` plugin (no `tailwind.config.ts`; theme in `src/index.css`) | |
| Components | shadcn/ui (new-york style, neutral base, CSS variables) | Copied into `src/components/ui/`, not a runtime dep |
| Data fetching | TanStack Query 5 | Loaders for route-level data; `useQuery` inside components only when route loaders are wrong |
| Routing | TanStack Router 1 (file-based, `@tanstack/router-plugin/vite`) | `src/routes/`, `routeTree.gen.ts` is generated and gitignored |
| Animation | Tailwind v4 utilities + `tw-animate-css` | shadcn v4 dropped `tailwindcss-animate` |
| Toasts | Sonner | |
| Forms | TanStack Form + Zod (when an app needs them; not pre-installed) | |
| Charts | shadcn charts / Recharts (add per-app) | |
| Testing | Vitest + Testing Library (unit), Playwright (e2e) | |
| Code quality | Biome 2 (single-tool: lint + format) | |
| API runtime | Azure Functions v4 programming model on Node 22 | `api/src/functions/*.ts` registers handlers via `app.http(...)` |

## Project structure

```
.
├── src/
│   ├── routes/              # TanStack Router file-based routes
│   │   ├── __root.tsx       # layout shell, theme toggle
│   │   ├── index.tsx        # home — sample shadcn page
│   │   └── health.tsx       # calls /api/health through TanStack Query
│   ├── components/
│   │   ├── ui/              # shadcn components (regenerate via `npx shadcn add ...`)
│   │   └── theme-provider.tsx
│   ├── lib/                 # client-only utilities
│   │   ├── utils.ts         # cn() — tailwind-merge + clsx
│   │   ├── principal.ts     # /.auth/me parser, zod-validated
│   │   └── telemetry.ts     # App Insights init (env-gated)
│   ├── test/setup.ts        # vitest setup
│   ├── index.css            # Tailwind v4 import + shadcn theme variables
│   ├── main.tsx
│   └── routeTree.gen.ts     # generated; gitignored
├── api/                     # Azure Functions v4 (managed by SWA)
│   ├── _shared/             # frozen reference patterns — match these in new endpoints
│   │   ├── auth.ts          # decodes x-ms-client-principal
│   │   ├── graph.ts         # app-only Graph client + token cache
│   │   └── http.ts          # ok/fail/unauthorized envelopes
│   ├── src/
│   │   ├── functions/
│   │   │   └── health.ts    # canonical endpoint pattern — copy this
│   │   └── index.ts         # imports each function module to register handlers
│   ├── host.json
│   ├── package.json         # api has its OWN deps; do not merge with root
│   └── tsconfig.json
├── e2e/                     # Playwright specs
├── scripts/
│   ├── azure-deploy.sh      # one-shot bootstrap (idempotent)
│   └── diagnose.sh          # read-only status check
├── .github/
│   ├── workflows/
│   │   ├── azure-static-web-apps.yml   # deploy on push/PR
│   │   └── ci.yml                       # PR safety: lint + typecheck + test + build
│   └── dependabot.yml
├── staticwebapp.config.json # contains __TENANT_ID__ placeholder; envsubst at deploy time
├── .mcp.json                # Microsoft Learn MCP server (Graph, SWA, Azure docs)
├── components.json          # shadcn CLI config
├── biome.json
└── docs/
    ├── RUNBOOK.md
    └── llms-references.md
```

## Commands

```bash
npm run dev          # Vite only — fastest, no auth, no /api
npm run dev:swa      # SWA CLI: emulates EasyAuth + Functions + routing
npm run build        # tsc -b && vite build
npm run typecheck    # tsc -b --noEmit
npm test             # vitest run
npm run test:watch   # vitest
npm run test:e2e     # playwright (boots dev server itself)
npm run check        # biome lint + format check
npm run skills:install   # TanStack Intent — re-run after dep upgrades
npm run diagnose     # bash scripts/diagnose.sh — read-only Azure status
```

## Auth model

- **EasyAuth** at the SWA layer gates the entire app to authenticated users in the tenant.
  No auth code needed in React — the user is signed in by the time React mounts.
- **Every `/api/*` Function MUST call `getPrincipal(req)` from `_shared/auth.ts`** even though
  EasyAuth gates the route. Defense in depth, single source of truth for identity. If an
  endpoint genuinely should be public, document why in a one-line comment above the handler.
- **Roles**: there's no role layer in the template. Add one only when an app needs it; the
  blueprint covers two patterns (Entra group claims for org-wide roles; app-level roles in a
  Cosmos doc for app-specific roles). Don't add Entra-group plumbing speculatively.

## Adding a Function

**Always copy `api/src/functions/health.ts` and modify.** Don't invent variations.

```ts
// api/src/functions/whoami.ts
import { app, type HttpRequest, type HttpResponseInit } from "@azure/functions";
import { requirePrincipal, AuthError } from "../../_shared/auth.js";
import { ok, unauthorized, serverError } from "../../_shared/http.js";

async function whoami(req: HttpRequest): Promise<HttpResponseInit> {
  try {
    const p = requirePrincipal(req);
    return ok({ user: p.userDetails, roles: p.userRoles });
  } catch (e) {
    if (e instanceof AuthError) return unauthorized();
    return serverError("whoami failed", String(e));
  }
}

app.http("whoami", { route: "whoami", methods: ["GET"], authLevel: "anonymous", handler: whoami });
```

Then add `import "./functions/whoami.js";` to `api/src/index.ts` so the registration runs.

`authLevel: "anonymous"` is correct — EasyAuth is what gates the request, not the Functions
key model.

## Adding a route

File-based, no manual route table. Drop a file in `src/routes/`:

```tsx
// src/routes/widgets.$id.tsx  — dynamic param
import { createFileRoute } from "@tanstack/react-router";
import { useSuspenseQuery } from "@tanstack/react-query";

export const Route = createFileRoute("/widgets/$id")({
  loader: ({ context, params }) =>
    context.queryClient.ensureQueryData({ queryKey: ["widget", params.id], queryFn: () => fetchWidget(params.id) }),
  component: WidgetPage,
});

function WidgetPage() {
  const { id } = Route.useParams();
  const { data } = useSuspenseQuery({ queryKey: ["widget", id], queryFn: () => fetchWidget(id) });
  return <div>{data.name}</div>;
}
```

Use **route loaders** for data fetching, not `useEffect`. The Vite plugin regenerates
`routeTree.gen.ts` automatically.

## Secrets and Key Vault

**Default: secrets live in SWA app settings.** The bootstrap script writes `AAD_CLIENT_SECRET`
and `APPINSIGHTS_CONNECTION_STRING` there. Functions read them via `process.env`.

**SWA Free tier does NOT support managed identity**, which means Key Vault references in app
settings won't work on Free. If an app's secrets touch PII / PHI / financial data, or you need
centralised rotation, **upgrade SWA to Standard ($9/mo)** for managed identity, then use Key
Vault references like `@Microsoft.KeyVault(SecretUri=https://kv-x.vault.azure.net/secrets/foo/)`.

**Do NOT fetch secrets from Key Vault using the app's own service-principal credentials** —
that defeats the security model (you've moved the secret problem one hop, not solved it).
Either accept SWA Free + app settings, or upgrade to Standard for real managed identity.

## Don't do

- **Don't import server-only modules into client code.** Anything from `api/_shared/` or any
  `@azure/*` package belongs only in `api/`.
- **Don't put secrets in `staticwebapp.config.json`.** That file ships to the client.
- **Don't add a database without checking whether this should be Tier 2 instead.** Cosmos
  free tier is fine for *incidental* state (a few hundred docs, lookup data). Anything more
  signals a Tier 2 promotion — see the blueprint.
- **Don't add MSAL.js** without first confirming app-only Graph permissions can't solve the
  use case. Adding a second sign-in dance for "act as the user" semantics is rarely worth it
  for read-only views.
- **Don't `sed` source files at deploy time.** `staticwebapp.config.json` uses
  `__TENANT_ID__` as a placeholder; the workflow does `envsubst` before deploy. Source stays
  clean.
- **Don't edit `src/routeTree.gen.ts`.** It's generated. Edit route files instead.
- **Don't edit `src/components/ui/*` by hand for major changes.** Use `npx shadcn add ...` /
  `npx shadcn diff ...` so we stay close to upstream.

## Verification discipline (the core point of this file)

The libraries in this template move fast. **Don't infer current API from training data**
for any of:

- TanStack Query, TanStack Router, TanStack Form, TanStack Intent
- Tailwind v4 (very different from v3)
- React 19 (Compiler, async Suspense, etc.)
- shadcn/ui (CLI changed; v4 uses `tw-animate-css` not `tailwindcss-animate`)
- Azure Static Web Apps Functions (programming model, runtime versions)
- Microsoft Graph

**Before adding or upgrading any dep:**

1. `npm view <pkg> version` — get the current version
2. Skim the changelog or release notes for breaking changes
3. Read the relevant `llms.txt` (see [docs/llms-references.md](docs/llms-references.md)) or
   query the Microsoft Learn MCP server for SWA/Graph/Azure CLI/Bicep
4. **Cite the URL you consulted in your PR description** so the reviewer can verify

When SWA, Graph, or Azure CLI questions come up, **prefer the Microsoft Learn MCP server**
over `WebFetch` — it serves authoritative, current docs from Microsoft. Configured in
`.mcp.json` at the repo root.

## TanStack Intent

`@tanstack/intent` ships skill packs alongside TanStack libraries so agents have current,
library-specific knowledge. The package was first published April 2026 (`0.0.x` series — early
days). Run `npm run skills:install` after the initial install and after every dep upgrade.

As of May 2026, intent skill availability across TanStack libraries is limited and changing
quickly — verify with `intent list` (or check
[github.com/TanStack/intent](https://github.com/TanStack/intent)) before relying on a skill
that "should" exist. For libraries without published skills, fall back to the `llms.txt`
registry in [docs/llms-references.md](docs/llms-references.md).

## Style

- Biome formats and lints (`npm run check` / `npm run format`).
- Default to no comments. Add a one-liner only when the WHY is non-obvious — a hidden
  constraint, a workaround, an invariant a reader would otherwise miss. Don't comment what
  the code obviously does.
- Don't reference current task / fix / caller in comments — that rots and belongs in the PR
  description.
